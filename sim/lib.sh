# Source me:  source "${SIM_DIR}/lib.sh"
#
# Shared scaffolding for the sim/*/run_*.sh experiment scripts
# (sim/tank-characterization/run_pvt_sweep.sh, sim/inductor-model/run_model_check.sh,
# sim/varactor-characterization/run_varactor_sweep.sh,
# sim/oscillator-core/run_pvt_sweep.sh + run_pilot_grid.sh + run_method_check.sh).
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

# ---------------------------------------------------------------------------
# Phase-noise / ISF extractors (sim/phase-noise/, issue #49)
# ---------------------------------------------------------------------------
#
# These implement the ONE estimator sim/phase-noise/ grades row 4 through: an
# impulse-response measurement of the oscillator's impulse sensitivity function
# (ISF), in its UNNORMALIZED form
#
#     Gq(phi) = d(phi_excess) / d(q_injected)          [rad / coulomb]
#
# so that the Hajimiri-Lee kernel can be evaluated WITHOUT ever measuring
# q_max = C_node * V_swing separately (Gq = Gamma / q_max identically, and
# q_max cancels out of the phase-noise expression -- see pn_l_dbc below). That
# is not a cosmetic choice: q_max on a tank loaded by 32 varactor instances,
# two EM-fitted inductor ladders and a MIM is not a quantity this repo can
# measure without introducing an error bar larger than the one the ISF itself
# carries.
#
# They live HERE and not in sim/phase-noise/pn_bench.sh for the same reason
# osc_metrics/osc_settle do: sim/phase-noise/run_method_check.sh has to
# validate the SAME functions the measured run grades with, against synthetic
# oscillators whose ISF and phase noise are known in closed form, and it must
# do so with no PDK install. A private copy inside the experiment would be a
# copy the method check does not check (issue #16).
#
# Bash-3.2 / POSIX-awk clean, like the rest of this file.

# pn_window_mean <datafile> <t_start_s> <t_end_s>
# Trapezoidal time average of a wrdata two-column trace over the window
# (t_end <= 0 means "to the end of the run"). Printed separately from
# osc_metrics because the ISF bench must apply the SAME crossing threshold to
# the reference and the perturbed run: letting each run compute its own mean
# would fold any DC shift the perturbation caused into the measured crossing
# times, which is exactly the quantity being measured.
pn_window_mean() {
  awk -v ts="${2:-0}" -v te="${3:-0}" '
    NF >= 2 {
      t = $1 + 0; v = $2 + 0
      if (t < ts) next
      if (te > 0 && t > te) next
      n++
      if (n > 1) { area += 0.5 * (pv + v) * (t - pt) }
      else { t0 = t }
      pt = t; pv = v
    }
    END {
      if (n < 2) { print "nan"; exit }
      span = pt - t0
      printf "%.10e\n", (span > 0) ? area / span : pv
    }' "$1"
}

# pn_crossings <datafile> <t_start_s> <t_end_s> <threshold_v>
# Print the LINEARLY INTERPOLATED time of every rising crossing of <threshold_v>
# inside the window, one per line, in increasing time order.
#
# Same interpolated-rising-crossing estimator osc_metrics() counts frequency
# with -- deliberately, so the phase-noise bench and the frequency bench share
# one validated notion of "when did this oscillation cross" -- but emitting the
# crossing TIMES rather than a frequency, because the ISF measurement is a
# comparison of two runs' crossing times, not of their frequencies.
#
# The threshold is an ARGUMENT, not a per-run mean: see pn_window_mean.
pn_crossings() {
  awk -v ts="${2:-0}" -v te="${3:-0}" -v thr="${4:-0}" '
    NF >= 2 {
      t = $1 + 0; v = $2 + 0
      if (t < ts) { pt = t; pv = v; have = 1; next }
      if (te > 0 && t > te) next
      if (have) {
        a = pv - thr; b = v - thr
        if (a < 0 && b >= 0) printf "%.12e\n", pt + (t - pt) * (-a) / (b - a)
      }
      pt = t; pv = v; have = 1
    }' "$1"
}

# pn_isf_steps <ref_crossfile> <pert_crossfile> <imp_times_csv> <plateau_frac> <t_end_s>
# The core of the ISF measurement. Given the crossing times of a REFERENCE run
# and of a run identical to it except for a train of charge impulses at the
# times in <imp_times_csv>, recover the permanent excess-phase STEP each
# impulse produced, and the phase of the carrier at which it landed.
#
# Method, stated because the number is only a result with its method
# (CLAUDE.md):
#   * crossings are matched between the two runs by NEAREST TIME, not by index:
#     a phase step large enough to move a crossing across a window boundary
#     would silently misalign an index match. A match further than a quarter
#     period away is counted in the GUARD line rather than used.
#   * tau_n = t_pert,n - t_ref,n is the crossing-time offset. An impulse
#     produces a permanent step in tau and, after the amplitude transient has
#     died, nothing else -- so tau(t) is a STAIRCASE. That is not assumed: the
#     per-plateau spread is reported (`ripple`), and the flatness of the
#     pre-first-impulse baseline is reported as the method's own null floor.
#   * a plateau is measured over only the LAST <plateau_frac> of each
#     inter-impulse interval, so the amplitude transient the impulse also
#     excited is excluded by construction rather than assumed to be absent.
#   * excess phase is dphi = -2*pi*(tau_after - tau_before)/T. The sign is the
#     physical one: a later crossing is a phase LAG. T is the mean period of
#     the perturbed run over the whole window.
#   * the phase at which impulse k landed is measured from the PERTURBED run's
#     own crossings (phi = 2*pi*(t_imp - t_cross)/(t_next - t_cross)), so the
#     cumulative phase the earlier impulses already imposed cannot bias the
#     phase axis. phi = 0 is a rising crossing of the threshold.
#
# Prints, in this order:
#   GUARD <n_ref> <n_pert> <n_matched> <n_far> <period_s>
#   BASE  <tau_mean_s> <tau_rms_s> <n_samples>
#   IMP <k> <t_imp_s> <phi_rad> <tau_before_s> <tau_after_s> <dtau_s> <dphi_rad> <ripple_after_s> <n_after>
# one IMP line per impulse.
pn_isf_steps() {
  local ref="$1" pert="$2" imps="$3" pfrac="${4:-0.4}" tend="$5"
  awk -v imps="${imps}" -v pfrac="${pfrac}" -v tend="${tend}" '
    BEGIN { PI = 4*atan2(1,1) }
    FNR == NR { nr++; tr[nr] = $1 + 0; next }
    { np++; tp[np] = $1 + 0 }
    END {
      if (nr < 4 || np < 4) { print "GUARD " nr+0 " " np+0 " 0 0 nan"; exit }
      period = (tp[np] - tp[1]) / (np - 1)
      nfar = 0; nm = 0
      for (i = 1; i <= nr; i++) {
        best = -1; bd = 1e30
        for (j = 1; j <= np; j++) {
          d = tp[j] - tr[i]; if (d < 0) d = -d
          if (d < bd) { bd = d; best = j }
        }
        if (bd > 0.25 * period) { nfar++; continue }
        nm++; mt[nm] = tr[i]; mtau[nm] = tp[best] - tr[i]
      }
      printf "GUARD %d %d %d %d %.10e\n", nr, np, nm, nfar, period
      m = split(imps, ti, ",")
      # ---- baseline: everything before the first impulse
      s = 0; s2 = 0; nb = 0
      for (i = 1; i <= nm; i++) if (mt[i] < ti[1]) { nb++; s += mtau[i]; s2 += mtau[i]*mtau[i] }
      bmean = (nb > 0) ? s / nb : 0
      brms = (nb > 1) ? sqrt((s2 - nb*bmean*bmean) / (nb - 1)) : 0
      printf "BASE %.10e %.10e %d\n", bmean, brms, nb
      prev = bmean
      for (k = 1; k <= m; k++) {
        hi  = (k < m) ? ti[k+1] : tend + 0
        dtk = hi - ti[k]
        lo  = hi - pfrac * dtk
        s = 0; s2 = 0; n = 0
        for (i = 1; i <= nm; i++) if (mt[i] >= lo && mt[i] < hi) { n++; s += mtau[i]; s2 += mtau[i]*mtau[i] }
        if (n == 0) { printf "IMP %d %.10e nan nan nan nan nan nan 0\n", k, ti[k]; continue }
        cur  = s / n
        ripp = (n > 1) ? sqrt((s2 - n*cur*cur) / (n - 1)) : 0
        # phase of the carrier at the impulse, from the perturbed run itself
        phi = -1
        for (j = 1; j < np; j++) if (tp[j] <= ti[k] && tp[j+1] > ti[k]) {
          phi = 2*PI * (ti[k] - tp[j]) / (tp[j+1] - tp[j]); break
        }
        dtau = cur - prev
        dphi = -2*PI * dtau / period
        if (phi < 0) printf "IMP %d %.10e nan %.10e %.10e %.10e %.10e %.10e %d\n", \
                            k, ti[k], prev, cur, dtau, dphi, ripp, n
        else          printf "IMP %d %.10e %.8f %.10e %.10e %.10e %.10e %.10e %d\n", \
                            k, ti[k], phi, prev, cur, dtau, dphi, ripp, n
        prev = cur
      }
    }' "${ref}" "${pert}"
}

# pn_gamma_stats <phi_gamma_file>
# Reduce a measured ISF -- a file of "<phi_rad> <Gq_rad_per_coulomb>" lines,
# sampled at M phases over one period -- to the scalars the phase-noise kernel
# needs. Prints ONE space-separated line:
#
#   rms_trapz rms_sample c0 c1 c2 c3 max_phase_gap_rad n
#
# rms_trapz is the PRIMARY figure: Gamma_rms^2 is defined as the mean of
# Gamma^2 over the CYCLE, (1/2pi) * integral(Gamma^2 dphi), and the samples are
# not exactly equally spaced in phase (the impulse train's spacing is designed
# to walk the phase by T/M per impulse, but the oscillator's own period is only
# known to the accuracy of the run that measured it). The trapezoidal integral
# over the phase-sorted, wrapped samples is correct to O(dphi^2) at any
# spacing; the naive sample mean-square (rms_sample) is only correct for an
# exactly uniform grid, and is printed alongside so the reader can see how much
# the non-uniformity mattered.
#
# c0..c3 are the ISF's DC and first three Fourier coefficient MAGNITUDES, by
# the same quadrature. They are not used in the 1/f^2 kernel -- they are
# recorded because c0 is what converts low-frequency (1/f, and any bias-network)
# noise into close-in phase noise, and because a c3 comparable to c1 is the
# signature that M samples per period is too few (see max_phase_gap_rad).
pn_gamma_stats() {
  awk '
    BEGIN { PI = 4*atan2(1,1) }
    NF >= 2 && $1 != "nan" && $2 != "nan" { n++; p[n] = $1 + 0; g[n] = $2 + 0 }
    END {
      if (n < 4) { print "nan nan nan nan nan nan nan " n+0; exit }
      for (i = 1; i <= n; i++) for (j = i+1; j <= n; j++) if (p[j] < p[i]) {
        tp = p[i]; p[i] = p[j]; p[j] = tp; tg = g[i]; g[i] = g[j]; g[j] = tg
      }
      # close the cycle by wrapping the first sample round to phi+2pi
      p[n+1] = p[1] + 2*PI; g[n+1] = g[1]
      s2 = 0; ssamp = 0; maxgap = 0
      for (k = 0; k <= 3; k++) { a[k] = 0; b[k] = 0 }
      for (i = 1; i <= n; i++) {
        d = p[i+1] - p[i]
        if (d > maxgap) maxgap = d
        s2 += 0.5 * (g[i]*g[i] + g[i+1]*g[i+1]) * d
        ssamp += g[i]*g[i]
        for (k = 0; k <= 3; k++) {
          a[k] += 0.5 * (g[i]*cos(k*p[i]) + g[i+1]*cos(k*p[i+1])) * d
          b[k] += 0.5 * (g[i]*sin(k*p[i]) + g[i+1]*sin(k*p[i+1])) * d
        }
      }
      rms_t = sqrt(s2 / (2*PI))
      rms_s = sqrt(ssamp / n)
      c0 = a[0] / (2*PI); if (c0 < 0) c0 = -c0
      printf "%.8e %.8e %.8e", rms_t, rms_s, c0
      for (k = 1; k <= 3; k++) printf " %.8e", sqrt((a[k]/PI)^2 + (b[k]/PI)^2)
      printf " %.6f %d\n", maxgap, n
    }' "$1"
}

# pn_l_dbc <gamma_q_rms_rad_per_C> <s_i_a2_per_hz> <offset_hz>
# The 1/f^2-region phase-noise kernel, in dBc/Hz. Prints TWO numbers:
#
#   L_both_sidebands   L_hl_paper_form
#
# BOTH are printed, and the record states which is quoted, because the two
# differ by exactly 3 dB and the difference is a real, documented ambiguity in
# the literature rather than an arithmetic slip:
#
#   L(df) = Gq_rms^2 * S_i / (2 * (2*pi*df)^2)          <- quoted as primary
#   L(df) = Gq_rms^2 * S_i / (4 * (2*pi*df)^2)          <- Hajimiri-Lee 1998
#                                                          eq. 14 as literally
#                                                          written
#
# The first is what the cyclostationary derivation gives when noise at BOTH
# ω0+Δω and ω0-Δω is counted (they fold to the same offset and are
# independent, so their powers add); the HL paper's worked substitution counts
# only the upper sideband. The first also reproduces Leeson's linear-tank
# kernel EXACTLY for an ideal LC (Gamma = cos, Gq_rms = 1/(sqrt2 * C * A),
# S_i = 4kTG): both reduce to kTG/(C^2 A^2 dw^2). sim/phase-noise's method
# check verifies that identity numerically, which is why the both-sideband
# form -- the more pessimistic of the two -- is the one this repo quotes.
#
# S_i is the ONE-SIDED equivalent noise-current PSD at the injection port,
# A^2/Hz (i.e. the square of ngspice's `inoise_spectrum`, which is A/sqrt(Hz)).
pn_l_dbc() {
  awk -v g="$1" -v si="$2" -v df="$3" 'BEGIN {
    PI = 4*atan2(1,1); dw = 2*PI*df
    if (g == "nan" || si == "nan" || g <= 0 || si <= 0 || dw <= 0) { print "nan nan"; exit }
    l2 = g*g*si / (2*dw*dw)
    printf "%.4f %.4f\n", 10*log(l2)/log(10), 10*log(l2/2)/log(10)
  }'
}

# pn_imp_times <t_first_s> <dt_s> <n>
# The impulse-train schedule, as a comma-separated list of centroid times.
# Shared by sim/phase-noise's method check and its measured run for the same
# reason the extractors are: the method check has to exercise the same train
# the measured run is read through, not a lookalike.
pn_imp_times() {
  awk -v t1="$1" -v dt="$2" -v n="$3" 'BEGIN {
    for (k = 0; k < n; k++) printf "%s%.12e", (k ? "," : ""), t1 + k*dt
    printf "\n"
  }'
}

# pn_pwl_train <imp_times_csv> <half_width_s> <amplitude_a>
# Render the schedule as an ngspice PWL argument list: a symmetric TRIANGLE of
# half-width hw and peak amp at each centroid, i.e. exactly q = amp*hw coulombs
# per impulse, with the centroid at the apex.
#
# A triangle rather than a rectangle because its charge and its centroid are
# both exact under trapezoidal integration once the solver takes the PWL's
# breakpoints (which it always does), so neither the injected charge nor the
# effective impulse instant depends on the timestep. Its cost is that it is not
# a delta: it attenuates the ISF's n-th harmonic by roughly (1 - (n*pi*w/T0)^2/6)
# for full width w, which is the `width` term in the method check's derived
# tolerance.
#
# An amplitude of 0 still emits every breakpoint. That is load-bearing: the
# reference run uses this same call with amp = 0 so that the reference and the
# perturbed deck have an identical timestep schedule until the first non-zero
# impulse.
pn_pwl_train() {
  awk -v imps="$1" -v hw="$2" -v amp="$3" 'BEGIN {
    n = split(imps, t, ",")
    printf "0 0"
    for (k = 1; k <= n; k++)
      printf " %.12e 0 %.12e %.10e %.12e 0", t[k]-hw, t[k], amp+0, t[k]+hw
    printf "\n"
  }'
}

# pn_inoise_table <ngspice-log>
# Print "<frequency> <inoise_spectrum>" for every row of the `print
# inoise_spectrum` table an ngspice `noise` analysis emitted into a batch log.
# ngspice prints these as "<index>\t<freq>\t<value>" under an "Index
# frequency inoise_spectrum" header; nothing else in the log has that shape.
pn_inoise_table() {
  awk '
    /^Index[ \t]+frequency[ \t]+inoise_spectrum/ { inblk = 1; next }
    inblk && /^-+$/ { next }
    inblk && NF >= 3 && $1 ~ /^[0-9]+$/ { print $2, $3; next }
    inblk && NF == 0 { next }
    inblk { inblk = 0 }
  ' "$1"
}

# pn_inoise_from_log <ngspice-log>
# The MEDIAN inoise_spectrum over the rows pn_inoise_table found, or "nan".
# The median rather than a single point because the band is swept deliberately
# (see tb_vco_port_noise.spice.tmpl's header): a referral that was ill
# conditioned at one frequency shows up as a spread across the band, which the
# caller records, rather than as a silently wrong scalar.
pn_inoise_from_log() {
  pn_inoise_table "$1" | awk '
    { n++; v[n] = $2 + 0 }
    END {
      if (n == 0) { print "nan"; exit }
      for (i = 1; i <= n; i++) for (j = i+1; j <= n; j++) if (v[j] < v[i]) { t=v[i]; v[i]=v[j]; v[j]=t }
      printf "%.8e\n", (n % 2) ? v[(n+1)/2] : 0.5*(v[n/2] + v[n/2+1])
    }'
}
