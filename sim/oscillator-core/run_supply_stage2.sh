#!/usr/bin/env bash
# DR-004 STAGE 2: the 18 supply sub-corners, oscillator-core rows 1/6/7/8
# (issue #113). Phase noise (row 4) is the sibling sim/phase-noise/
# run_supply_stage2.sh; sim/oscillator-core/report_supply_stage2.sh joins them.
#
#   sim/oscillator-core/run_supply_stage2.sh --list            # PDK-free: print the 18 points
#   sim/oscillator-core/run_supply_stage2.sh --check           # PDK-free: enumeration self-check
#   sim/oscillator-core/run_supply_stage2.sh \
#       [--baseline-osc <dir>/<stage-1-record-id>] [--stage2-pn <dir>/<id>]... [--baseline-pn <dir>/<id>]...
#
# With no mode flag it RUNS the points and needs the pinned PDK (same
# requirements as run_pvt_sweep.sh); with --baseline-osc it then writes the
# escalation report next to its own record.
#
# WHAT IT IS, AND WHAT IT IS NOT
# DR-004 ratifies a STAGED supply disposition. Stage 1 is the 135-point model
# grid at the nominal 3.3 V rail (run_pvt_sweep.sh, #50/#53, unchanged).
# This is stage 2: {2.970, 3.630} V x {SLOW, TYP, FAST} x {-40, 27, 125} C =
# 18 points, the process vertices AGGREGATE (SLOW = ss+hbt_wcs+cap_wcs, TYP =
# tt+hbt_typ+cap_typ, FAST = ff+hbt_bcs+cap_bcs), each swept over the same
# 10-point Vctrl axis as stage 1, plus the row-6 margin ladder at
# rails x {SLOW,FAST} x {-40,125} (8 corners). It is NOT the 405-point full
# cross, which DR-004 stage 3 requires only if this stage's report says
# ESCALATION_REQUIRED -- via a superseding decision record, never from here.
#
# COST (derived exactly as run_pvt_sweep.sh derives its own, from the same
# measured rate): about 180 transients + 72 margin rungs ~ 27 CPU-hours. It is
# a fleet job, not a workstation job; DO NOT hand-launch it on a shared
# dispatch host. The script prints its own estimate and writes point-by-point
# so an interrupted run leaves usable partial evidence.
#
# NOMINAL DEFAULTS ARE UNTOUCHED. The rail is carried by osc_bench.sh's
# OSC_VSUP_V (empty = nominal), so run_pvt_sweep.sh generates byte-identical
# decks and CSVs. The stage-2 CSVs gain a trailing vsup_v column
# (OSC_CSV_RAIL=1) so a row can never be aggregated across rails, and every
# point id carries the rail.
#
# Outputs (append-only, keyed by a fresh record id):
#   netlist-snapshots/<id>/<point>.spice    corners/<id>/<point>.log
#   records/<id>.csv                        per-point scalars (+ vsup_v)
#   records/<id>-tuning.csv / -kvco.csv     row 1/2/3 curves per (corner, rail)
#   records/<id>-margin.csv / -margin-summary.csv   row-6 ladder (+ vsup_v)
#   records/<id>-row7.csv                   row-7 grade per (corner, rail) (+ vsup_v):
#                                           complete-window swing and full-domain
#                                           compliance, kept as separate columns
#   records/<id>.md                         the narrative record + provenance
#   records/<id>-report-supply-stage2.{csv,md}   (only with --baseline-osc)
set -euo pipefail

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SIM_DIR}/.." && pwd)"

# shellcheck source=supply_stage2.sh
source "${EXPERIMENT_DIR}/supply_stage2.sh"

MODE=run BASE_OSC="" S2_PN=() BASE_PN=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)         MODE=list; shift ;;
    --check)        MODE=check; shift ;;
    --baseline-osc) BASE_OSC="$2"; shift 2 ;;
    --stage2-pn)    S2_PN+=("$2"); shift 2 ;;
    --baseline-pn)  BASE_PN+=("$2"); shift 2 ;;
    -h|--help)      sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

s2_check_enumeration || exit 2
if [[ "${MODE}" == check ]]; then
  echo "stage 2: ${S2_N_POINTS} distinct sub-corners, mappings consistent"
  exit 0
fi
if [[ "${MODE}" == list ]]; then
  echo "process rail_v temp_c mos cap hbt point_id"
  while read -r proc rail temp mos cap hbt; do
    echo "${proc} ${rail} ${temp} ${mos} ${cap} ${hbt} $(s2_point_id "${proc}" "${rail}" "${temp}")"
  done < <(s2_enumerate)
  echo "# row-6 margin corners:"
  s2_enumerate_margin | sed 's/^/# /'
  exit 0
fi

# shellcheck source=../env.sh
source "${SIM_DIR}/env.sh"
# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"

RECORD_ID="$(reserve_record_id "${REPO_ROOT}" "${EXPERIMENT_DIR}")" || exit 1
NETLIST_DIR="${EXPERIMENT_DIR}/netlist-snapshots/${RECORD_ID}"
LOG_DIR="${EXPERIMENT_DIR}/corners/${RECORD_ID}"
CSV_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.csv"
# shellcheck disable=SC2034  # read by osc_bench.sh's osc_emit_tuning
TUNING_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-tuning.csv"
# shellcheck disable=SC2034  # read by osc_bench.sh's osc_emit_tuning
KVCO_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-kvco.csv"
# shellcheck disable=SC2034  # read by osc_bench.sh's osc_margin_corner
MARGIN_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-margin.csv"
# shellcheck disable=SC2034  # read by osc_bench.sh's osc_margin_corner
MARGIN_SUM_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-margin-summary.csv"
# shellcheck disable=SC2034  # read by osc_bench.sh's osc_emit_row7 (issue #119)
ROW7_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-row7.csv"
MD_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.md"
mkdir -p "${NETLIST_DIR}" "${LOG_DIR}" "${EXPERIMENT_DIR}/records"

make_scratch_workdir "sg13g2-osc-s2"

# shellcheck disable=SC2034  # read by osc_bench.sh
OSC_CSV_RAIL=1          # rail identity column on every stage-2 CSV
# shellcheck source=osc_bench.sh
source "${EXPERIMENT_DIR}/osc_bench.sh"

osc_preflight
osc_write_csv_headers

N_TRAN=$(( S2_N_POINTS * $(echo "${S2_VCTRL_LIST}" | wc -w | tr -d ' ') ))
N_MARGIN="$(s2_enumerate_margin | wc -l | tr -d ' ')"
N_RUNGS="$(echo "${OSC_MARGIN_SCALES}" | wc -w | tr -d ' ')"
OSC_SECS_PER_NS=76   # the measured rate run_pvt_sweep.sh derives its estimate from
EST_H=$(awk -v nt="${N_TRAN}" -v ts="${OSC_TSTOP_S}" -v nm="$((N_MARGIN * N_RUNGS))" \
            -v ms="${OSC_MARGIN_TSTOP_S}" -v r="${OSC_SECS_PER_NS}" \
        'BEGIN { printf "%.0f", (nt*ts*1e9 + nm*ms*1e9) * r / 3600 }')
echo
echo "---------------------------------------------------------------"
echo "oscillator-core DR-004 stage 2   record ${RECORD_ID}"
echo "---------------------------------------------------------------"
echo "sub-corners       : ${S2_N_POINTS}  rails {${S2_RAILS}} V x {${S2_PROCESSES}} x T {${S2_TEMPS}} C"
echo "transients        : ${N_TRAN}  (x Vctrl {${S2_VCTRL_LIST}})"
echo "margin corners    : ${N_MARGIN} x ${N_RUNGS} rungs = $((N_MARGIN * N_RUNGS)) transients"
echo "estimated cost    : ~${EST_H} CPU-hours (fleet job; see header)"
echo "---------------------------------------------------------------"

total=0 passed=0
nosc_points=() failed_points=() margin_failed=()
while read -r proc rail temp mos cap hbt; do
  OSC_VSUP_V="${rail}"
  for vctrl in ${S2_VCTRL_LIST}; do
    corner_id="$(s2_point_id "${proc}" "${rail}" "${temp}" "${vctrl}")"
    total=$((total + 1))
    if osc_simulate_point "${corner_id}" "${mos}" "${cap}" "${hbt}" "${temp}" "${vctrl}" "${OSC_TMAX}"; then
      passed=$((passed + 1))
    else
      st="$(awk -F, -v c="${corner_id}" '$1 == c { print $8 }' "${CSV_OUT}" | tail -1)"
      if [[ "${st}" == "NOSC" ]]; then nosc_points+=("${corner_id}"); else failed_points+=("${corner_id}"); fi
    fi
  done
  osc_emit_tuning "${mos}" "${cap}" "${hbt}" "${temp}" "${OSC_TMAX}" "${S2_VCTRL_LIST}" "${rail}"
  # Row 7 (issue #119): the SAME grader stage 1 uses (osc_bench.sh,
  # issue #112), restricted to this rail's rows of the rail-tagged points CSV.
  osc_emit_row7 "${mos}" "${cap}" "${hbt}" "${temp}" "${OSC_TMAX}" "${S2_VCTRL_LIST}" "${rail}"
done < <(s2_enumerate)

margin_total=0
while read -r proc rail temp mos cap hbt; do
  OSC_VSUP_V="${rail}"
  base="$(s2_point_id "${proc}" "${rail}" "${temp}")"
  margin_total=$((margin_total + 1))
  osc_margin_corner "${base}" "${mos}" "${cap}" "${hbt}" "${temp}" || margin_failed+=("${base}")
done < <(s2_enumerate_margin)
# shellcheck disable=SC2034  # read by osc_bench.sh
OSC_VSUP_V=""

{
  echo "# Record ${RECORD_ID}"
  echo
  echo "- **Experiment**: oscillator-core (DR-004 stage-2 supply sub-corners)"
  echo "- **Claim**: rows 1/6/7/8 inputs of \`design/vco.sch\` at the 18 supply"
  echo "  sub-corners \`{${S2_RAILS}}\` V x \`{${S2_PROCESSES}}\` x \`{${S2_TEMPS}}\` C,"
  echo "  process vertices aggregate (SLOW = ss/hbt_wcs/cap_wcs, TYP ="
  echo "  tt/hbt_typ/cap_typ, FAST = ff/hbt_bcs/cap_bcs). Row 4 is the"
  echo "  phase-noise sibling driver. **This is stage 2 of DR-004; it is not the"
  echo "  405-point cross and it does not edit or relax \`spec/\`.** Escalation to"
  echo "  stage 3 is decided by \`report_supply_stage2.sh\` and routes to a"
  echo "  superseding decision record."
  echo "- **Netlist under test**: \`design/vco.spice\`, verified current with"
  echo "  \`design/vco.sch\` by \`design/netlist.sh --check\`. Device section sha256"
  echo "  \`$(sha256_of "${OSC_VCO_BODY}")\`; only its \`VSUP\` value is rewritten"
  echo "  (to the sub-corner rail, \`osc_render\`), together with the common-mode"
  echo "  observation offset and the startup \`.ic\` (centred on the rail with the"
  echo "  same ${OSC_IC_DIFF_MV} mV perturbation); core power is current x that rail."
  echo "- **Method**: identical to \`run_pvt_sweep.sh\` (same code path, same"
  echo "  transient \`tran ${OSC_TSTEP} ${OSC_TSTOP}\`, timestep ceiling"
  echo "  \`${OSC_TMAX}\`, window ${OSC_TMEAS_START} .. ${OSC_TSTOP_S} s, row-6"
  echo "  tail-current-scaling proxy ladder); see that record's method section."
  echo "  Every CSV row carries \`vsup_v\`."
  echo "- **Row 7** (issue #119): graded per (sub-corner, rail) by"
  echo "  \`osc_emit_row7\` -- the stage-1 grader of issue #112, unchanged --"
  echo "  into \`records/${RECORD_ID}-row7.csv\`: swing = Vpp_diff >="
  echo "  ${OSC_ROW7_VPP_MIN_V} V (stretch ${OSC_ROW7_VPP_MIN_STRETCH_V} V) at every Vctrl of the"
  echo "  window [${OSC_ROW3_V_LO}, ${OSC_ROW3_V_HI}] V; compliance = (VDD + Vpp_diff/4) -"
  echo "  V(TAIL)_min <= ${OSC_ROW7_BVCEO_MIN_V} V at every Vctrl of the full domain, VDD the"
  echo "  point's sampled rail. Both extremes are samples of an adaptive-timestep"
  echo "  trace; the compliance pass uses the sinusoidal sampling-bound upper"
  echo "  value, and a measured value under the limit whose bound is not is"
  echo "  WITHIN SAMPLING BOUND (not a pass). A cusp sharper than a sinusoid can"
  echo "  hide more than the bound: a stated limit."
  echo "- **Non-PDK model**: \`sim/inductor-model/sg13g2_inductor_em.spice\`"
  echo "  sha256 \`$(osc_ind_model_sha)\`. The PDK ships no spiral-inductor"
  echo "  ngspice model; every frequency inherits that model's stated error bars."
  osc_provenance_md
  echo "- **ngspice**: \`${OSC_NGSPICE_VERSION}\`"
  echo "- **Result**: ${passed}/${total} transient points reached a countable"
  echo "  oscillation; non-oscillating ${#nosc_points[@]}; simulation failures"
  echo "  ${#failed_points[@]}; margin corners completed"
  echo "  $(( margin_total - ${#margin_failed[@]} ))/${margin_total}."
  echo "- **Reproduce**: \`sim/oscillator-core/run_supply_stage2.sh\` against the pinned PDK."
  echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${WORKDIR}/summary.md"
# Publish only after the captured model inputs re-verify intact (issue #133).
osc_publish_summary "${WORKDIR}/summary.md" "${MD_OUT}"

echo "record          : ${RECORD_ID}"
echo "transients      : ${passed}/${total} oscillating"
echo "margin corners  : $(( margin_total - ${#margin_failed[@]} ))/${margin_total}"

if [[ -n "${BASE_OSC}" ]]; then
  args=(--stage2-osc "${EXPERIMENT_DIR}/records/${RECORD_ID}" --baseline-osc "${BASE_OSC}"
        --out "${EXPERIMENT_DIR}/records/${RECORD_ID}")
  for p in ${S2_PN[@]+"${S2_PN[@]}"}; do args+=(--stage2-pn "${p}"); done
  for p in ${BASE_PN[@]+"${BASE_PN[@]}"}; do args+=(--baseline-pn "${p}"); done
  "${EXPERIMENT_DIR}/report_supply_stage2.sh" "${args[@]}"
else
  echo "no --baseline-osc given: run report_supply_stage2.sh with the stage-1 record to compare."
fi

if [[ ${#failed_points[@]} -gt 0 || ${#margin_failed[@]} -gt 0 ]]; then
  echo "error: ${#failed_points[@]} transient point(s) and ${#margin_failed[@]} margin corner(s) failed to simulate (distinct from failing to oscillate)." >&2
  exit 1
fi
