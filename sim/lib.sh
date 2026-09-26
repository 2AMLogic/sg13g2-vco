# Source me:  source "${SIM_DIR}/lib.sh"
#
# Shared scaffolding for the sim/*/run_*.sh experiment scripts
# (sim/tank-characterization/run_pvt_sweep.sh, sim/inductor-model/run_model_check.sh,
# sim/varactor-characterization/run_varactor_sweep.sh,
# sim/oscillator-core/run_pvt_sweep.sh + run_method_check.sh).
# These are legitimate, distinct experiments -- this file exists
# because the bash *scaffolding* around them (hashing, record-ID minting, a
# scratch ngspice workdir, pulling a scalar out of a .meas log) was
# byte-identical between them, not because the experiments themselves should
# be merged. See issue #16 for the duplication this replaces.
#
# Deliberately does NOT source sim/env.sh and must not gain any
# PDK-resolution dependency: sim/inductor-model/run_model_check.sh's "only
# needs ngspice (and bash, and awk) on PATH -- no PDK install required"
# property depends on that (see its own header comment). Callers that DO need
# the PDK (sim/tank-characterization/run_pvt_sweep.sh) source sim/env.sh
# themselves, separately from this file.
#
# This file is sourced, not executed, so it has no shebang; the directive
# below tells shellcheck which dialect to assume.
# shellcheck shell=bash
#
# Bash-3.2 clean throughout, on purpose: macOS still ships bash 3.2 as
# /bin/bash, and spec/review-bar.md item 1 forbids a "one-command cold start"
# that silently needs a newer bash. No `declare -A`, no bash-4+ builtins or
# parameter expansions.

# sha256_of <file>
# Print the sha256 digest of a file, or "unavailable" if neither shasum nor
# sha256sum is on PATH.
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else echo "unavailable"; fi
}

# meas_value <log> <name>
# Pull a scalar out of an ngspice batch log. `meas` prints
#   "<name>                =  <value>"
# on success and "meas ... failed!" on a miss; a miss must come back empty so
# the caller can record it as "none" instead of as a number.
meas_value() {
  local log="$1" name="$2"
  awk -v n="${name}" '$1 == n && $2 == "=" { print $3; found=1 } END { if (!found) print "" }' "${log}" | head -1
}

# detect_ngspice_version
# Print the installed ngspice's version string (e.g. "ngspice-42"), parsed
# from `ngspice --version`, or "unknown" if it could not be parsed. Requires
# ngspice on PATH -- callers already check that before sourcing this file.
detect_ngspice_version() {
  local v
  v="$(ngspice --version 2>&1 | sed -n 's/^\*\* \(ngspice-[0-9.]*\).*/\1/p' | head -1)"
  echo "${v:-unknown}"
}

# mint_record_id <repo_root>
# Print a fresh RECORD_ID of the form <UTC timestamp>-<short git SHA>
# (<git SHA> is "nogit" outside a git checkout). Every sim/*/run_*.sh script
# mints exactly one of these per run and uses it to key its append-only
# evidence directories -- see each script's own header comment.
mint_record_id() {
  local repo_root="$1"
  local git_sha
  git_sha="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || echo nogit)"
  echo "$(date -u +%Y%m%d-%H%M%S)-${git_sha}"
}

# make_scratch_workdir <mktemp-prefix>
# Create a scratch directory under ${TMPDIR:-/tmp} for ngspice to run in, copy
# this experiment's .spiceinit into it (so a cold-start run does not depend on
# whether the PDK's install.py ever symlinked one into $HOME), and arrange for
# it to be removed on exit. Sets the global WORKDIR variable and installs an
# EXIT trap that removes it.
#
# Requires the caller to have already set EXPERIMENT_DIR (every sim/*/run_*.sh
# script does this before sourcing lib.sh) and to have a "${EXPERIMENT_DIR}/.spiceinit"
# present.
make_scratch_workdir() {
  local prefix="$1"
  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")"
  cleanup() { rm -rf "${WORKDIR}"; }
  trap cleanup EXIT
  cp "${EXPERIMENT_DIR}/.spiceinit" "${WORKDIR}/.spiceinit"
}

# method_check_point <label> <temp> <axis_val> <log> <method_csv> <tol_pct>
# Known-answer check on the extraction arithmetic itself, not on any device
# under test: pulls l_ref_1g/q_ref_1g/srf_ref out of <log> (a testbench's
# .meas outputs for the ideal reference network R=2 ohm, L=1 nH, C=100 fF)
# and compares each against that network's closed form at w = 2*pi*1 GHz.
# The reference network is corner- and temperature-independent, so its
# closed forms are constants; it is re-checked at every corner anyway,
# because the whole point is to catch a run whose extraction arithmetic
# silently went wrong. Appends one row per quantity (leff_1ghz_h, q_1ghz,
# srf_hz) to <method_csv>, in the shared
# "label,temp,axis_val,quantity,simulated,closed_form,rel_err_pct,tol_pct,status"
# format. Prints "PASS" on stdout if every quantity was within <tol_pct> of
# its closed form, "FAIL" otherwise -- deliberately a print, not a mutated
# global counter, so the caller decides what a FAIL means for its own
# pass/fail bookkeeping (see sim/tank-characterization/run_pvt_sweep.sh and
# sim/varactor-characterization/run_varactor_sweep.sh for the two different
# ways that turns out to matter).
method_check_point() {
  local label="$1" temp="$2" axis_val="$3" log="$4" method_csv="$5" tol_pct="$6"
  local l_sim q_sim s_sim point_ok
  l_sim="$(meas_value "${log}" "l_ref_1g")"
  q_sim="$(meas_value "${log}" "q_ref_1g")"
  s_sim="$(meas_value "${log}" "srf_ref")"
  point_ok=1
  while read -r qty sim ref err st; do
    echo "${label},${temp},${axis_val},${qty},${sim},${ref},${err},${tol_pct},${st}" >> "${method_csv}"
    if [[ "${st}" != "PASS" ]]; then point_ok=0; fi
  done < <(awk -v ls="${l_sim:-nan}" -v qs="${q_sim:-nan}" -v ss="${s_sim:-nan}" -v tol="${tol_pct}" '
    BEGIN {
      PI = 4*atan2(1,1); R = 2.0; L = 1e-9; C = 100e-15; w = 2*PI*1e9;
      # Z(w) = (R + jwL) / ((1 - w^2 LC) + jwRC)
      nr = R;  ni = w*L;
      dr = 1 - w*w*L*C;  di = w*R*C;
      den = dr*dr + di*di;
      zr = (nr*dr + ni*di)/den;
      zi = (ni*dr - nr*di)/den;
      l_ref = zi/w;
      q_ref = zi/zr;
      srf_ref = sqrt((L - R*R*C)/(L*L*C))/(2*PI);
      split("leff_1ghz_h q_1ghz srf_hz", names, " ");
      sims[1] = ls; sims[2] = qs; sims[3] = ss;
      refs[1] = l_ref; refs[2] = q_ref; refs[3] = srf_ref;
      for (i = 1; i <= 3; i++) {
        if (sims[i] == "nan" || sims[i] == "") { printf "%s %s %.6e nan %s\n", names[i], "", refs[i], "FAIL"; continue }
        e = (sims[i] - refs[i]) / refs[i] * 100.0;
        ae = (e < 0) ? -e : e;
        printf "%s %.6e %.6e %+.5f %s\n", names[i], sims[i], refs[i], e, (ae <= tol ? "PASS" : "FAIL");
      }
    }')
  if [[ ${point_ok} -eq 1 ]]; then echo PASS; else echo FAIL; fi
}

# ---------------------------------------------------------------------------
# Oscillator transient extractors (sim/oscillator-core/, issue #47)
# ---------------------------------------------------------------------------
#
# ngspice ships no PSS/pnoise, so every oscillator number in this repo comes
# out of a TRANSIENT plus period counting. The two functions below are that
# estimator, factored here rather than into the experiment because
# sim/oscillator-core/ has two entry points that must share one extractor:
# the graded PVT sweep, and the known-answer check that validates the
# extractor against synthetic waveforms whose frequency and settling time are
# known in closed form (run_method_check.sh). A private copy in the sweep
# script would be a copy the method check does not actually check -- see
# issue #16 for the duplication lib.sh exists to prevent.
#
# Both read an ngspice `wrdata` two-column file ("<time> <value>", whitespace
# separated) and both work on a caller-chosen measurement window, so the
# startup ramp can be excluded from a settled-oscillation measurement.

# osc_metrics <datafile> <t_start_s> [t_end_s]
# Crossing-counted frequency and amplitude of a (possibly DC-offset)
# oscillation, over the window t_start <= t <= t_end (t_end omitted or <= 0
# means "to the end of the run"). Prints ONE space-separated line:
#
#   f_hz vpp_v cycles mean_v tx_first_s tx_last_s dt_max_s n_samples
#
# Method, stated because the number is only a result with its method
# (CLAUDE.md):
#   * mean_v is the TRAPEZOIDAL time average over the window, not the
#     arithmetic mean of the samples -- ngspice's timestep is adaptive, so a
#     sample mean silently weights the densely-stepped parts of a cycle more
#     heavily. Row 8's average supply current leans on this directly.
#   * crossings are counted RISING through mean_v, not through zero: the
#     common-mode, tail and supply-current traces all ride on a DC level, and
#     counting about zero there counts nothing at all.
#   * each crossing time is LINEARLY INTERPOLATED between the two bracketing
#     samples, so the resolution floor is set by the interpolation error, not
#     by the integer crossing count. f = (nx-1) / (tx_last - tx_first) uses
#     only the first and last crossing, so per-cycle jitter averages out over
#     the window.
#   * dt_max_s is the largest sample spacing inside the window: the caller
#     needs it to state the quantization floor (a conservative bound on the
#     interpolated estimate is dt_max * f / cycles; the no-interpolation
#     bound is 1/cycles).
#
# Fewer than 3 samples, or fewer than 3 crossings, is reported as f_hz = 0
# with the amplitude still filled in -- "it did not oscillate" is a result,
# not an error (sim/README.md rule 4), and the caller decides what it means.
osc_metrics() {
  awk -v ts="${2:-0}" -v te="${3:-0}" '
    NF >= 2 {
      t = $1 + 0; v = $2 + 0
      if (t < ts) next
      if (te > 0 && t > te) next
      n++; tt[n] = t; vv[n] = v
    }
    END {
      if (n < 3) { print "0 0 0 0 0 0 0 " n+0; exit }
      lo = vv[1]; hi = vv[1]; area = 0; dtmax = 0
      for (i = 1; i <= n; i++) {
        if (vv[i] < lo) lo = vv[i]
        if (vv[i] > hi) hi = vv[i]
        if (i < n) {
          dt = tt[i+1] - tt[i]
          if (dt > dtmax) dtmax = dt
          area += 0.5 * (vv[i] + vv[i+1]) * dt
        }
      }
      span = tt[n] - tt[1]
      av = (span > 0) ? area / span : vv[1]
      vpp = hi - lo
      nx = 0
      for (i = 1; i < n; i++) {
        a = vv[i] - av; b = vv[i+1] - av
        if (a < 0 && b >= 0) {
          nx++
          x[nx] = tt[i] + (tt[i+1] - tt[i]) * (-a) / (b - a)
        }
      }
      if (nx < 3) { printf "0 %.6e 0 %.6e 0 0 %.6e %d\n", vpp, av, dtmax, n; exit }
      T = (x[nx] - x[1]) / (nx - 1)
      printf "%.6e %.6e %d %.6e %.6e %.6e %.6e %d\n", \
             1.0 / T, vpp, nx - 1, av, x[1], x[nx], dtmax, n
    }' "$1"
}

# osc_settle <datafile> <frac> <t_final_start_s>
# Startup settling time: when the oscillation envelope first reaches <frac>
# of its FINAL peak-to-peak amplitude and stays there. Prints ONE line:
#
#   t_settle_s vpp_final_v n_extrema
#
# Method: vpp_final is the peak-to-peak over [t_final_start, end of run] --
# the window the caller has already decided is settled. The envelope is then
# taken from successive local extrema of the trace (sign changes of the
# first difference), with extrema closer than 2 % of vpp_final to the
# previous kept extremum discarded so numerical ripple on a stiff solution
# does not register as a cycle. t_settle is the time of the earliest extremum
# from which EVERY later half-cycle swing is >= frac * vpp_final, i.e. the
# envelope's last crossing of that level, not its first -- a ringing or
# beating envelope must not be reported as settled at its first excursion.
# "nan" means the envelope never reached the level and stayed: a non-starting
# or still-ramping corner, which is a finding to record, not an error.
osc_settle() {
  awk -v frac="${2:-0.9}" -v tfs="${3:-0}" '
    NF >= 2 { n++; tt[n] = $1 + 0; vv[n] = $2 + 0 }
    END {
      if (n < 5) { print "nan 0 0"; exit }
      lo = ""; hi = ""
      for (i = 1; i <= n; i++) {
        if (tt[i] < tfs) continue
        if (lo == "" || vv[i] < lo) lo = vv[i]
        if (hi == "" || vv[i] > hi) hi = vv[i]
      }
      if (lo == "") { print "nan 0 0"; exit }
      vppf = hi - lo
      if (vppf <= 0) { printf "nan %.6e 0\n", vppf; exit }
      # local extrema of the whole trace, ripple-filtered
      m = 0
      for (i = 2; i < n; i++) {
        d0 = vv[i] - vv[i-1]; d1 = vv[i+1] - vv[i]
        if (d0 == 0 && d1 == 0) continue
        if ((d0 >= 0 && d1 < 0) || (d0 <= 0 && d1 > 0)) {
          if (m > 0) {
            dv = vv[i] - ev[m]; if (dv < 0) dv = -dv
            if (dv < 0.02 * vppf) continue
          }
          m++; et[m] = tt[i]; ev[m] = vv[i]
        }
      }
      if (m < 3) { printf "nan %.6e %d\n", vppf, m; exit }
      # last index from which every later half-cycle swing clears the level
      lim = frac * vppf
      idx = 0
      for (k = m - 1; k >= 1; k--) {
        sw = ev[k+1] - ev[k]; if (sw < 0) sw = -sw
        if (sw < lim) { idx = k + 1; break }
      }
      if (idx == 0) { printf "%.6e %.6e %d\n", et[1], vppf, m; exit }
      if (idx > m - 1) { printf "nan %.6e %d\n", vppf, m; exit }
      printf "%.6e %.6e %d\n", et[idx], vppf, m
    }' "$1"
}
