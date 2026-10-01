#!/usr/bin/env bash
# Cold-start invocation (this is the whole thing):
#
#   design/run_elaborate.sh
#
# Optionally, if the PDK is not installed under one of the prefixes sim/env.sh
# probes (/usr/share/pdk, /usr/local/share/pdk, ~/share/pdk, ~/.ciel, ~/.volare):
#
#   export PDK_ROOT=/path/to/ihp-open-pdk   # parent dir containing ihp-sg13g2/
#   export PDK=ihp-sg13g2
#
# WHAT THIS IS, AND WHAT IT IS NOT
# --------------------------------
# This is the ELABORATION CHECK for design/vco.sch, not a graded testbench.
# It answers exactly three questions, which are the ones issue #44 scopes:
#
#   1. Is design/vco.spice still the netlist design/vco.sch derives to?
#      (design/netlist.sh --check, run first -- a stale netlist fails here
#      rather than being silently simulated.)
#   2. Does that netlist ELABORATE against the pinned PDK -- i.e. does every
#      device resolve, with zero unknown-subckt / unknown-model errors?
#      (npn13G2v and cap_cmim from the PDK's ngspice model libraries,
#      sg13_hv_svaricap through the OSDI mosvar build, and this repo's own
#      EM-fitted `inductor` subckt.)
#   3. Does it start up and oscillate, and where -- at Vctrl = 0.0, 1.65 and
#      3.3 V, from a 10 mV differential initial condition?
#
# It writes NO evidence record, sweeps NO corner, and grades NO
# spec/target-spec.md row. The phase-noise, Kvco, startup-margin and PVT
# testbenches are separate work and belong under sim/ with their own
# append-only records, per sim/README.md.
#
# Requires: ngspice, xschem and awk on PATH, bash, and an IHP-Open-PDK
# v0.3.0 install (pinned in sim/pdk.json). Like
# sim/varactor-characterization/run_varactor_sweep.sh, this script runs the
# OSDI build itself (sim/README.md rule 1: a run that needs a build step owns
# that step), so sg13_hv_svaricap is instantiable on a cold checkout.
set -euo pipefail

DESIGN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DESIGN_DIR}/.." && pwd)"
SIM_DIR="${REPO_ROOT}/sim"

# shellcheck source=../sim/env.sh
source "${SIM_DIR}/env.sh"
# shellcheck source=../sim/lib.sh
source "${SIM_DIR}/lib.sh"

# ----------------------------------------------------------------- preflight
for tool in ngspice awk; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} not found on PATH." >&2
    exit 1
  fi
done
if [[ -z "${SG13G2_NGSPICE_MODELS:-}" \
      || ! -f "${SG13G2_NGSPICE_MODELS}/cornerHBT.lib" \
      || ! -f "${SG13G2_NGSPICE_MODELS}/cornerMOShv.lib" \
      || ! -f "${SG13G2_NGSPICE_MODELS}/cornerCAP.lib" ]]; then
  echo "error: could not resolve the SG13G2 ngspice model libraries." >&2
  echo "       expected \$PDK_ROOT/\$PDK/libs.tech/ngspice/models/{cornerHBT,cornerMOShv,cornerCAP}.lib" >&2
  echo "       see the message from sim/env.sh above, and sim/pdk.json." >&2
  exit 1
fi

IND_MODEL="${SIM_DIR}/inductor-model/sg13g2_inductor_em.spice"
if [[ ! -f "${IND_MODEL}" ]]; then
  echo "error: ${IND_MODEL} is missing -- the PDK ships no ngspice inductor" >&2
  echo "       model (sim/pdk.json known_model_gaps.spiral_inductor); this" >&2
  echo "       repo supplies its own and design/vco.sch depends on it." >&2
  exit 1
fi

# ------------------------------------------------- netlist freshness (step 1)
echo "sg13g2: checking design/vco.spice against design/vco.sch ..."
"${DESIGN_DIR}/netlist.sh" --check

# ---------------------------------------------------------------- OSDI build
echo "sg13g2: ensuring mosvar.osdi is built and loadable ..."
"${SIM_DIR}/tools/build-osdi.sh"
OSDI_MOSVAR="${SG13G2_OSDI_DIR}/mosvar.osdi"
if [[ ! -f "${OSDI_MOSVAR}" ]]; then
  echo "error: sim/tools/build-osdi.sh reported success but ${OSDI_MOSVAR} is missing." >&2
  exit 1
fi

NGSPICE_VERSION="$(detect_ngspice_version)"

# ngspice must run from a directory holding a .spiceinit, so a cold-start run
# does not depend on whether the PDK's install.py ever symlinked one into $HOME.
# sim/lib.sh's make_scratch_workdir provides exactly that scratch setup (mktemp
# dir, EXIT-trap cleanup, .spiceinit copy -- contract at sim/lib.sh:70-79).
# shellcheck disable=SC2034  # read by lib.sh's make_scratch_workdir
EXPERIMENT_DIR="${DESIGN_DIR}"
make_scratch_workdir "sg13g2-vco-elab"

# ------------------------------------------------------ token substitution
# The committed netlist carries @@TOKEN@@ placeholders instead of absolute
# paths (see the header block inside design/vco.spice). This is the same
# substitution sim/*/run_*.sh apply to their testbench templates.
sed -e "s|@@MODELS_DIR@@|${SG13G2_NGSPICE_MODELS}|g" \
    -e "s|@@IND_MODEL@@|${IND_MODEL}|g" \
    -e "s|@@OSDI_MOSVAR@@|${OSDI_MOSVAR}|g" \
    "${DESIGN_DIR}/vco.spice" > "${WORKDIR}/vco_elab.spice"

if grep -vE '^[[:space:]]*\*' "${WORKDIR}/vco_elab.spice" | grep -q '@@'; then
  echo "error: unsubstituted placeholder token left in the elaborated netlist:" >&2
  grep -nE '@@' "${WORKDIR}/vco_elab.spice" | grep -vE ':[[:space:]]*\*' >&2
  exit 1
fi

# -------------------------------------------------------------- elaborate
echo "sg13g2: elaborating design/vco.spice under ${NGSPICE_VERSION} ..."
LOG="${WORKDIR}/ngspice.log"
set +e
( cd "${WORKDIR}" && ngspice -b vco_elab.spice ) >"${LOG}" 2>&1
NG_RC=$?
set -e

# ngspice reports an unresolvable device as "unknown subckt" / "Unable to find
# definition of model" (among other wordings), and keeps going, so the exit
# status alone is not enough -- grep for the model-resolution failures
# explicitly, via sim/lib.sh's shared NGSPICE_MODEL_ERROR_PATTERN (issue #55)
# so this file states the pattern once instead of twice.
MODEL_ERRORS="$(grep -icE "${NGSPICE_MODEL_ERROR_PATTERN}" "${LOG}" || true)"

echo
echo "---------------------------------------------------------------"
echo "elaboration"
echo "---------------------------------------------------------------"
echo "ngspice exit status      : ${NG_RC}"
echo "model-resolution errors  : ${MODEL_ERRORS}"
if [[ "${MODEL_ERRORS}" -ne 0 ]]; then
  echo
  ngspice_model_error_lines "${LOG}" >&2
fi

echo
echo "operating point (Vctrl = 1.65 V as netlisted, before the sweep):"
awk '/^v\(nbias\)|^v\(te\)|^v\(tail\)|^v\(outp\)|^v\(outn\)|^i\(vsup\)/ { print "  " $0 }' "${LOG}"

# ------------------------------------------------------- oscillation readout
# Frequency from rising zero crossings of v(OUTP)-v(OUTN) over the SECOND HALF
# of the transient only (10-20 ns), so the startup ramp is excluded and what is
# measured is the settled oscillation. Amplitude is peak-to-peak over the same
# window. This is a period count, not a spectral estimate: it states no phase
# noise and no line width, and it is not a substitute for the row-4 method.
# The extractor itself is sim/lib.sh's method-checked osc_metrics() (the same
# estimator sim/oscillator-core/run_method_check.sh validates against synthetic
# waveforms with closed-form frequency, amplitude and time average), called
# with the same 10 ns window start read_osc used to hardcode. Note the mean it
# reports -- the one P_core below leans on -- is the TRAPEZOIDAL time average
# over the window, not the arithmetic mean of the samples: ngspice's timestep
# is adaptive, so a sample mean silently weights the densely-stepped parts of a
# cycle more heavily (sim/lib.sh:167-170).

echo
echo "---------------------------------------------------------------"
echo "startup transient   tran 1p 20n 0 2p, .ic 10 mV differential"
echo "measurement window  10-20 ns (second half), rising mean crossings"
echo "---------------------------------------------------------------"
printf "  %-10s %-13s %-13s %-9s %s\n" \
       "Vctrl (V)" "f_osc (GHz)" "Vpp_diff (V)" "cycles" "P_core (mW), 10-20 ns mean"

F_AT_0=""
F_AT_33=""
OSC_FAIL=0
for vv in 0 1.65 3.3; do
  DAT="${WORKDIR}/vco_tran_${vv}"
  if [[ ! -f "${DAT}" ]]; then
    printf "  %-10s %s\n" "${vv}" "NO DATA -- the transient did not run"
    OSC_FAIL=1
    continue
  fi
  read -r f vpp cyc _mean _txf _txl _dtmax _ns <<<"$(osc_metrics "${DAT}" 10e-9)"
  PMW="n/a"
  if [[ -f "${WORKDIR}/vco_isup_${vv}" ]]; then
    read -r _fi _vppi _cyci imean _txf _txl _dtmax _ns <<<"$(osc_metrics "${WORKDIR}/vco_isup_${vv}" 10e-9)"
    PMW="$(awk -v i="${imean}" 'BEGIN{ printf "%.4f", i*3.3*1e3 }')"
  fi
  printf "  %-10s %-13.5f %-13.4f %-9s %s\n" \
         "${vv}" "$(awk -v f="${f}" 'BEGIN{print f/1e9}')" "${vpp}" "${cyc}" "${PMW}"
  if awk -v f="${f}" 'BEGIN { exit (f > 1e9) ? 0 : 1 }'; then :; else OSC_FAIL=1; fi
  [[ "${vv}" == "0" ]] && F_AT_0="${f}"
  [[ "${vv}" == "3.3" ]] && F_AT_33="${f}"
done

# ------------------------------------------------- differential-mode check
# The tank must be ONE differential resonator, not two branches that happen
# to ring separately. The test: the fundamental lives entirely in the
# differential mode, while the common mode and the tail node carry only the
# second harmonic the two half-circuits pump in phase. So f_cm / f_diff and
# f_tail / f_diff must both land on 2, and Vpp_cm must be a small fraction of
# Vpp_diff. A pair of independent branches would put a FUNDAMENTAL into the
# common mode (ratio 1), which is what this table is here to exclude.
echo
echo "---------------------------------------------------------------"
echo "differential-mode check (same 10-20 ns window)"
echo "---------------------------------------------------------------"
printf "  %-10s %-13s %-13s %-13s %s\n" \
       "Vctrl (V)" "Vpp_cm/Vpp_d" "f_cm/f_diff" "f_tail/f_diff" "V(TAIL) DC (V)"
for vv in 0 1.65 3.3; do
  [[ -f "${WORKDIR}/vco_tran_${vv}" ]] || continue
  read -r fd vppd _c _m _txf _txl _dtmax _ns <<<"$(osc_metrics "${WORKDIR}/vco_tran_${vv}" 10e-9)"
  read -r fc vppc _c2 _m2 _txf _txl _dtmax _ns <<<"$(osc_metrics "${WORKDIR}/vco_cm_${vv}" 10e-9)"
  read -r ft _vppt _c3 _m3 _txf _txl _dtmax _ns <<<"$(osc_metrics "${WORKDIR}/vco_tail_${vv}" 10e-9)"
  TAILDC="$(awk '/^v\(tail\)/ { print $3 }' "${LOG}")"
  awk -v vv="${vv}" -v fd="${fd}" -v vppd="${vppd}" -v fc="${fc}" \
      -v vppc="${vppc}" -v ft="${ft}" -v tdc="${TAILDC}" 'BEGIN {
    printf "  %-10s %-13.4f %-13.3f %-13.3f %s\n", vv, \
           (vppd > 0 ? vppc/vppd : 0), (fd > 0 ? fc/fd : 0), \
           (fd > 0 ? ft/fd : 0), tdc
  }'
done

if [[ -n "${F_AT_0}" && -n "${F_AT_33}" ]]; then
  echo
  awk -v a="${F_AT_0}" -v b="${F_AT_33}" 'BEGIN {
    if (a <= 0 || b <= 0) exit
    hi = (a > b) ? a : b; lo = (a > b) ? b : a
    printf "  fractional tuning range  f_max/f_min = %.4f  (%.2f %%)\n", hi/lo, 100*(hi/lo - 1)
    printf "  geometric band centre    %.4f GHz\n", sqrt(a*b)/1e9
    printf "  spec/target-spec.md row 2 target >= 15 %% (stretch >= 20 %%): %s\n", \
           (100*(hi/lo - 1) >= 15.0) ? "MET" : "NOT MET"
    printf "  spec/target-spec.md row 1 band 4.5-5.5 GHz: %s\n", \
           (lo >= 4.5e9 && hi <= 5.5e9) ? "both endpoints inside" : "an endpoint is OUTSIDE"
  }'
fi

echo
echo "---------------------------------------------------------------"
echo "PDK_ROOT       : ${PDK_ROOT}  (PDK=${PDK})"
echo "ngspice        : ${NGSPICE_VERSION}"
echo "models sha256  : cornerHBT.lib    $(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerHBT.lib")"
echo "                 cornerMOShv.lib  $(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerMOShv.lib")"
echo "                 cornerCAP.lib    $(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerCAP.lib")"
echo "                 mosvar.osdi      $(sha256_of "${OSDI_MOSVAR}")"
echo "inductor model : sim/inductor-model/sg13g2_inductor_em.spice"
echo "                 $(sha256_of "${IND_MODEL}")"
echo "---------------------------------------------------------------"

if [[ "${MODEL_ERRORS}" -ne 0 ]]; then
  echo "error: the netlist did NOT elaborate cleanly -- see the model-resolution errors above." >&2
  exit 1
fi
if [[ "${OSC_FAIL}" -ne 0 ]]; then
  echo "error: at least one Vctrl point did not produce a countable oscillation." >&2
  exit 1
fi
if [[ "${NG_RC}" -ne 0 ]]; then
  echo "error: ngspice exited ${NG_RC}; full log:" >&2
  cat "${LOG}" >&2
  exit 1
fi
echo "OK: design/vco.spice elaborates with zero unknown-model/unknown-subckt errors"
echo "    and oscillates at all three Vctrl points."
