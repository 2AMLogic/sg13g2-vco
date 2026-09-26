#!/usr/bin/env bash
# Cold-start invocation (this is the whole thing):
#
#   sim/oscillator-core/run_method_check.sh
#
# WHAT THIS IS
# ------------
# The known-answer check of the EXTRACTORS this experiment grades every
# oscillator number with: sim/lib.sh's osc_metrics() (crossing-counted
# frequency, peak-to-peak, trapezoidal time average) and osc_settle()
# (envelope settling time). It simulates synthetic waveforms whose frequency,
# amplitude, time-average and settling time are known in CLOSED FORM, runs the
# real extractors over them, and records the error against each closed form.
#
# It measures the arithmetic, not the circuit. It grades no
# spec/target-spec.md row and says nothing about design/vco.sch. What it buys
# is the thing a transient-plus-period-count method most needs and most often
# lacks: evidence that the estimator itself is not the source of the number.
# The other three sim/ studies each ship one of these (sim/inductor-model's
# 27/27 analytic points, sim/tank-characterization's reference R-L-C network);
# this is oscillator-core's.
#
# THE TOLERANCES ARE DERIVED, NOT CHOSEN
# Every tolerance below is a closed-form bound on the estimator's OWN
# discretization error at the timestep ceiling being checked, printed in the
# record next to the number as `tol_basis`. None of them is a round number
# picked to make a run pass:
#
#   frequency   dt*f/cycles          the interpolated-crossing bound
#                                    osc_quant_floor_pct() already reports
#                                    with every measured frequency
#   amplitude   1 - cos(pi*dt*f)     peak-sampling error: the sampled peak of
#                                    a sinusoid misses the true peak by this
#                                    fraction in the worst phase alignment
#   time-avg    amp/(pi*cycles)      the trapezoidal average's residual over
#                                    a window that is not an integer number
#                                    of periods
#   settling    half a period        osc_settle() resolves to the nearest
#                                    local extremum by construction
#
# Each bound is then given a x1.5 headroom factor, stated in the record, so
# the check fails on a BROKEN extractor rather than on the last digit of a
# bound that is itself an estimate.
#
# Requires: ngspice and awk on PATH, and bash. Deliberately NO PDK install,
# no model library and no OSDI build -- the deck uses only ngspice-native
# behavioural sources, so a failing extractor can never be confused with a
# PDK or toolchain problem. This is the same no-PDK property
# sim/inductor-model/run_model_check.sh has, and the reason sim/lib.sh must
# never gain a PDK dependency.
#
# Everything it writes is APPEND-ONLY evidence under this directory, keyed by
# a record ID minted fresh on every run (sim/README.md):
#
#   netlist-snapshots/<record-id>/<corner-id>.spice   exact deck simulated
#   corners/<record-id>/<corner-id>.log               raw ngspice batch output
#   records/<record-id>-method-check.csv              one row per quantity
#   records/<record-id>.md                            the narrative record
set -euo pipefail

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SIM_DIR}/.." && pwd)"

# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"

for tool in ngspice awk; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} not found on PATH." >&2
    exit 1
  fi
done

NGSPICE_VERSION="$(detect_ngspice_version)"
RECORD_ID="$(mint_record_id "${REPO_ROOT}")"

NETLIST_DIR="${EXPERIMENT_DIR}/netlist-snapshots/${RECORD_ID}"
LOG_DIR="${EXPERIMENT_DIR}/corners/${RECORD_ID}"
METHOD_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-method-check.csv"
MD_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.md"
mkdir -p "${NETLIST_DIR}" "${LOG_DIR}" "${EXPERIMENT_DIR}/records"

make_scratch_workdir "sg13g2-osc-method"

# ---------------------------------------------------------------- the grid
# Waveform parameters. The three tone frequencies bracket
# spec/target-spec.md row 1's 4.5 / 5.0 / 5.5 GHz band, so the extractor is
# checked across the band it will actually report in.
F_LO="4.5e9"
F_MID="5.0e9"
F_HI="5.5e9"
AMP="0.55"
OFFSET="3.3"
# TAU is chosen so exp(-TSTOP/TAU) is negligible (20 ns / 0.5 ns = e^-40):
# that makes the ramped trace's final envelope exactly 2*AMP and removes the
# settling-time closed form's dependence on where the final window starts.
TAU="0.5e-9"
TSTEP="1p"
TSTOP="20n"
TSTOP_S="20e-9"
TMEAS_START="10e-9"
SETTLE_FRAC="0.9"
SETTLE_REF="15e-9"

# Timestep ceilings checked. 2 ps is the ceiling the graded sweep runs at
# (~100 samples/period at 5 GHz); the coarser ones are here so the error
# model above is validated over a range rather than at one point, and so a
# future decision to run the grid cheaper has measured evidence to lean on
# instead of an assumption.
TMAX_LIST="2p 5p 10p 20p"
TMAX_S_LIST="2e-12 5e-12 10e-12 20e-12"

TOL_HEADROOM="1.5"

echo "tmax,tmax_s,trace,quantity,simulated,closed_form,abs_err,rel_err_pct,tol_pct,tol_basis,status" > "${METHOD_CSV}"

total=0
passed=0
failed_rows=()

# check_row <tmax> <trace> <quantity> <sim> <ref> <tol_pct> <tol_basis>
# Append one comparison row and print PASS/FAIL. A relative error is only
# meaningful against a non-zero reference, so a zero reference is compared
# absolutely against tol_pct interpreted as an absolute value in the
# quantity's own unit -- that is the DC_ONLY case, where the correct answer
# is exactly zero and "0.2 % of zero" would be a vacuous test.
check_row() {
  local tmax="$1" tmax_s="$2" trace="$3" qty="$4" sim="$5" ref="$6" tol="$7" basis="$8"
  local out
  out="$(awk -v s="${sim}" -v r="${ref}" -v tol="${tol}" 'BEGIN {
    if (s == "" || s == "nan") { printf "nan,nan,FAIL\n"; exit }
    ae = s - r; if (ae < 0) ae = -ae
    if (r == 0) {
      printf "%.6e,nan,%s\n", ae, (ae <= tol) ? "PASS" : "FAIL"
    } else {
      re = 100.0 * (s - r) / r
      are = (re < 0) ? -re : re
      printf "%.6e,%+.6g,%s\n", ae, re, (are <= tol) ? "PASS" : "FAIL"
    }
  }')"
  local abs_err rel_err status
  IFS=, read -r abs_err rel_err status <<<"${out}"
  echo "${tmax},${tmax_s},${trace},${qty},${sim},${ref},${abs_err},${rel_err},${tol},${basis},${status}" >> "${METHOD_CSV}"
  total=$((total + 1))
  if [[ "${status}" == "PASS" ]]; then passed=$((passed + 1)); else failed_rows+=("${tmax}/${trace}/${qty}"); fi
  echo "${status}"
}

i=0
for tmax in ${TMAX_LIST}; do
  i=$((i + 1))
  tmax_s="$(echo "${TMAX_S_LIST}" | awk -v k="${i}" '{print $k}')"
  corner_id="method_${tmax}"
  netlist="${NETLIST_DIR}/${corner_id}.spice"
  log="${LOG_DIR}/${corner_id}.log"
  prefix="mc_${corner_id}"

  sed \
    -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
    -e "s|@@F_LO@@|${F_LO}|g" \
    -e "s|@@F_MID@@|${F_MID}|g" \
    -e "s|@@F_HI@@|${F_HI}|g" \
    -e "s|@@AMP@@|${AMP}|g" \
    -e "s|@@OFFSET@@|${OFFSET}|g" \
    -e "s|@@TAU@@|${TAU}|g" \
    -e "s|@@TSTEP@@|${TSTEP}|g" \
    -e "s|@@TSTOP@@|${TSTOP}|g" \
    -e "s|@@TMAX@@|${tmax}|g" \
    -e "s|@@OUT_PREFIX@@|${prefix}|g" \
    "${EXPERIMENT_DIR}/testbench/tb_period_count_known_answer.spice.tmpl" > "${netlist}"

  if grep -vE '^[[:space:]]*\*' "${netlist}" | grep -q '@@'; then
    echo "error: unsubstituted placeholder token left in ${netlist}" >&2
    exit 1
  fi

  rc=0
  ( cd "${WORKDIR}" && ngspice -b "${netlist}" ) > "${log}" 2>&1 || rc=$?
  echo "[${corner_id}] ngspice rc=${rc}"
  if [[ ${rc} -ne 0 ]]; then
    echo "error: ngspice exited ${rc} on ${corner_id}; log at ${log}" >&2
    exit 1
  fi

  # ------------------------------------------------------------ pure tones
  j=0
  for spec in "pure_lo:${F_LO}" "pure_mid:${F_MID}" "pure_hi:${F_HI}"; do
    j=$((j + 1))
    trace="${spec%%:*}"
    fref="${spec#*:}"
    dat="${WORKDIR}/${prefix}_${trace}"
    if [[ ! -f "${dat}" ]]; then
      echo "error: ${dat} was not written -- the deck did not emit trace ${trace}." >&2
      exit 1
    fi
    read -r f vpp cycles mean _tx1 _tx2 _dtmax _ns <<<"$(osc_metrics "${dat}" "${TMEAS_START}")"

    tol_f="$(awk -v dt="${tmax_s}" -v f="${fref}" -v c="${cycles}" -v h="${TOL_HEADROOM}" \
                 'BEGIN { printf "%.6g", h * 100.0 * dt * f / (c > 0 ? c : 1) }')"
    tol_v="$(awk -v dt="${tmax_s}" -v f="${fref}" -v h="${TOL_HEADROOM}" \
                 'BEGIN { printf "%.6g", h * 100.0 * (1 - cos(3.141592653589793*dt*f)) }')"
    tol_m="$(awk -v a="${AMP}" -v c="${cycles}" -v off="${OFFSET}" -v h="${TOL_HEADROOM}" \
                 'BEGIN { printf "%.6g", h * 100.0 * (a / (3.141592653589793 * (c > 0 ? c : 1))) / off }')"

    check_row "${tmax}" "${tmax_s}" "${trace}" "f_hz"  "${f}"   "${fref}" "${tol_f}" "dt*f/cycles x${TOL_HEADROOM}" >/dev/null
    check_row "${tmax}" "${tmax_s}" "${trace}" "vpp_v" "${vpp}" \
              "$(awk -v a="${AMP}" 'BEGIN{printf "%.10g", 2*a}')" "${tol_v}" "1-cos(pi*dt*f) x${TOL_HEADROOM}" >/dev/null
    check_row "${tmax}" "${tmax_s}" "${trace}" "time_avg_v" "${mean}" "${OFFSET}" "${tol_m}" "amp/(pi*cycles) x${TOL_HEADROOM}" >/dev/null
  done

  # --------------------------------------------------- exponentially ramped
  dat="${WORKDIR}/${prefix}_ramp"
  read -r f vpp cycles mean _tx1 _tx2 _dtmax _ns <<<"$(osc_metrics "${dat}" "${TMEAS_START}")"
  read -r t_settle _vppf _nex <<<"$(osc_settle "${dat}" "${SETTLE_FRAC}" "${SETTLE_REF}")"
  t_settle_ref="$(awk -v tau="${TAU}" -v q="${SETTLE_FRAC}" 'BEGIN { printf "%.10e", -tau * log(1 - q) }')"
  tol_f="$(awk -v dt="${tmax_s}" -v f="${F_MID}" -v c="${cycles}" -v h="${TOL_HEADROOM}" \
               'BEGIN { printf "%.6g", h * 100.0 * dt * f / (c > 0 ? c : 1) }')"
  tol_t="$(awk -v f="${F_MID}" -v tref="${t_settle_ref}" -v h="${TOL_HEADROOM}" \
               'BEGIN { printf "%.6g", h * 100.0 * (0.5 / f) / tref }')"
  check_row "${tmax}" "${tmax_s}" "ramp" "f_hz" "${f}" "${F_MID}" "${tol_f}" "dt*f/cycles x${TOL_HEADROOM}" >/dev/null
  check_row "${tmax}" "${tmax_s}" "ramp" "t_settle_s" "${t_settle}" "${t_settle_ref}" "${tol_t}" "half a period x${TOL_HEADROOM}" >/dev/null

  # -------------------------------------------------------- falsification
  # A flat trace must come back as "no oscillation", not as a manufactured
  # frequency: a non-starting PVT corner is exactly the finding the graded
  # sweep must not misreport, so the estimator is checked on one.
  dat="${WORKDIR}/${prefix}_dconly"
  read -r f vpp cycles mean _tx1 _tx2 _dtmax _ns <<<"$(osc_metrics "${dat}" "${TMEAS_START}")"
  check_row "${tmax}" "${tmax_s}" "dconly" "f_hz"  "${f}"   "0" "1e-30" "exactly zero" >/dev/null
  check_row "${tmax}" "${tmax_s}" "dconly" "vpp_v" "${vpp}" "0" "1e-9"  "exactly zero (1 nV slack)" >/dev/null
  check_row "${tmax}" "${tmax_s}" "dconly" "time_avg_v" "${mean}" "${OFFSET}" "1e-6" "a constant trace has an exact average" >/dev/null

  rm -f "${WORKDIR}/${prefix}"_*
done

# ------------------------------------------------------------------ record
{
  echo "# Record ${RECORD_ID}"
  echo
  echo "- **Experiment**: oscillator-core (method check)"
  echo "- **Claim**: that \`sim/lib.sh\`'s \`osc_metrics()\` and"
  echo "  \`osc_settle()\` -- the crossing-counted frequency / peak-to-peak /"
  echo "  trapezoidal-time-average and envelope-settling-time estimators every"
  echo "  number in this experiment is derived through -- recover the correct"
  echo "  answer on waveforms whose frequency, amplitude, time average and"
  echo "  settling time are known in closed form. **Ratifies no"
  echo "  \`spec/target-spec.md\` row and says nothing about \`design/vco.sch\`.**"
  echo "- **Method**: an ngspice transient over five behavioural-source"
  echo "  traces (\`testbench/tb_period_count_known_answer.spice.tmpl\`):"
  echo "  pure sinusoids at ${F_LO} / ${F_MID} / ${F_HI} Hz with amplitude"
  echo "  ${AMP} V on a ${OFFSET} V offset; the same ${F_MID} Hz tone with an"
  echo "  exponentially rising envelope of time constant ${TAU} s; and a"
  echo "  constant ${OFFSET} V trace as the falsification case. Run"
  echo "  \`tran ${TSTEP} ${TSTOP}\` at each timestep ceiling in"
  echo "  \`{${TMAX_LIST}}\`; extracted over the ${TMEAS_START} s .. ${TSTOP_S} s"
  echo "  window, the same window split the graded sweep uses."
  echo "- **Closed forms checked**: \`f\` = the stated tone frequency;"
  echo "  \`Vpp\` = 2*${AMP} V; time average = ${OFFSET} V;"
  echo "  \`t_settle\` = -${TAU}*ln(1-${SETTLE_FRAC}) ="
  echo "  $(awk -v tau="${TAU}" -v q="${SETTLE_FRAC}" 'BEGIN{printf "%.6e", -tau*log(1-q)}') s;"
  echo "  and, for the constant trace, \`f\` = 0 with \`Vpp\` = 0."
  echo "- **Tolerances**: DERIVED, not chosen -- each is a closed-form bound"
  echo "  on the estimator's own discretization error at the ceiling being"
  echo "  checked, times a stated ${TOL_HEADROOM}x headroom, and each row's"
  echo "  \`tol_basis\` column names its bound:"
  echo "  - frequency: \`dt*f/cycles\` (the interpolated-crossing bound)"
  echo "  - amplitude: \`1-cos(pi*dt*f)\` (peak-sampling error)"
  echo "  - time average: \`amp/(pi*cycles)\` (non-integer-period residual)"
  echo "  - settling time: half a period (\`osc_settle\` resolves to the"
  echo "    nearest local extremum by construction)"
  echo "- **PDK**: none, deliberately. The deck uses only ngspice-native"
  echo "  behavioural sources, so this check runs on a bare checkout and a"
  echo "  failing extractor cannot be confused with a PDK or OSDI problem."
  echo "- **ngspice**: \`${NGSPICE_VERSION}\`"
  echo "- **Result**: ${passed}/${total} checked quantities within their"
  echo "  derived tolerance."
  if [[ ${#failed_rows[@]} -gt 0 ]]; then
    echo "- **Failed rows**: ${failed_rows[*]}"
  fi
  echo "- **Links**:"
  echo "  - Template: \`testbench/tb_period_count_known_answer.spice.tmpl\`"
  echo "  - Per-ceiling generated decks: \`netlist-snapshots/${RECORD_ID}/\`"
  echo "  - Per-ceiling raw ngspice logs: \`corners/${RECORD_ID}/\`"
  echo "  - Comparison table: \`records/${RECORD_ID}-method-check.csv\`"
  echo "- **Reproduce**: \`sim/oscillator-core/run_method_check.sh\` (no"
  echo "  arguments, no PDK required)."
  echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MD_OUT}"

echo
echo "record        : ${RECORD_ID}"
echo "method check  : ${passed}/${total} quantities within their derived tolerance"
echo "written       : ${MD_OUT#"${REPO_ROOT}"/}"

if [[ ${passed} -ne ${total} ]]; then
  echo "error: ${#failed_rows[@]} checked quantity/quantities exceeded tolerance: ${failed_rows[*]}" >&2
  exit 1
fi
echo "OK: the period-count and settling-time extractors reproduce every closed form."
