#!/usr/bin/env bash
# Cold-start invocation (this is the whole thing -- the netlist-freshness check
# and the OSDI build run automatically, there are no hidden manual steps):
#
#   sim/oscillator-core/run_pilot_grid.sh
#
# Optionally, if the PDK is not installed under one of the prefixes sim/env.sh
# probes (/usr/share/pdk, /usr/local/share/pdk, ~/share/pdk, ~/.ciel, ~/.volare):
#
#   export PDK_ROOT=/path/to/ihp-open-pdk   # parent dir containing ihp-sg13g2/
#   export PDK=ihp-sg13g2
#
# WHAT THIS IS -- AND, MORE IMPORTANTLY, WHAT IT IS NOT
# -----------------------------------------------------
# A deliberately PARTIAL measurement of design/vco.sch: the frequency, tuning,
# Kvco, startup, differential-mode and large-signal-power quantities the graded
# bench produces, over a corner set that is a small, explicitly declared SUBSET
# of the spec/target-spec.md row-10/11 grid.
#
# **It does not grade any spec row.** Rows 1, 2, 3, 6 and 8 are all stated at
# or over the row-10 corner set; row 6 in particular says "at every bound
# corner of the row-10 set" in so many words. A number measured at the nominal
# process corner and two temperatures is evidence about the circuit, not a
# verdict on a row, and this script's record says exactly that in its own
# words. run_pvt_sweep.sh is the graded entry point; see its header and
# README.md ("The graded grid is a fleet job") for why it has not been run.
#
# WHY A PILOT EXISTS AT ALL RATHER THAN JUST THE GRADED SWEEP
# The graded grid is 1350 transients plus the margin pass. Measured on this
# netlist (see the cost note in run_pvt_sweep.sh, and OSC_TSTOP's header in
# osc_bench.sh for the settings those measurements were taken at), that is
# ~200 CPU-hours, and the corner runner that would route it off-host cannot
# express this deck at all (klt-sim/README.md, upstream
# 2AMLogic/klayout-tools#2511). Shipping a bench with no circuit measurement
# behind it would leave every honest question -- does it start, does it land in
# the row-1 band, is the tank differential, is the row-6 proxy even
# well-behaved -- unanswered, and would leave the bench itself unexercised
# against the real netlist rather than against synthetic waveforms. This runs
# the subset that fits, and labels it as a subset everywhere it appears.
#
# THE CORNER SET, AND WHY EACH PART OF IT IS IN
#   1. The nominal PVT corner (mos_tt / cap_typ / hbt_typ, 27 C) over a
#      six-point Vctrl axis spanning the full 0.0-3.3 V domain. This is the
#      only part of the set that produces a tuning ratio and a Kvco curve at
#      all: both need the whole domain at one corner.
#   2. The same process corner at the two row-11 temperature EXTREMES
#      (-40 / +125 C), at the domain endpoints and at band centre. Three
#      points is enough for a ratio and for f_osc at band centre, and
#      temperature is the axis most likely to move f_osc out of the row-1
#      band, so it is the axis a pilot should spend its points on first.
#   3. One repeat of the nominal band-centre point at a COARSER timestep
#      ceiling. That is the circuit solution's own discretization error,
#      which run_method_check.sh cannot measure: it checks the EXTRACTOR
#      against closed forms, and says nothing about the solver's error with 32
#      OSDI varactors and four HBTs in the loop.
#   4. The row-6 margin ladder at the nominal corner. Row 6 needs the bound
#      corners and this is not them; what it establishes is that the declared
#      proxy behaves as its derivation says it should (a monotone measured
#      tail current down the ladder, a bracketed threshold) before ~50
#      CPU-hours are spent running it at 33 corners.
#
# NOT measured here: phase noise (row 4 -- separate work, see README.md), any
# MOS/MIM/HBT corner other than typical, and any supply sub-corner.
#
# Requires: ngspice, xschem and awk on PATH, bash, and an IHP-Open-PDK v0.3.0
# install (pinned in sim/pdk.json).
#
# Cost: 13 transients at OSC_TSTOP plus the margin ladder at
# OSC_MARGIN_TSTOP. The script prints its own estimate before it starts.
set -euo pipefail

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SIM_DIR}/.." && pwd)"

# shellcheck source=../env.sh
source "${SIM_DIR}/env.sh"
# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"

RECORD_ID="$(mint_record_id "${REPO_ROOT}")"
NETLIST_DIR="${EXPERIMENT_DIR}/netlist-snapshots/${RECORD_ID}"
LOG_DIR="${EXPERIMENT_DIR}/corners/${RECORD_ID}"
CSV_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}-pilot.csv"
TUNING_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-pilot-tuning.csv"
# shellcheck disable=SC2034  # read by osc_bench.sh's osc_emit_tuning
KVCO_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-pilot-kvco.csv"
# shellcheck disable=SC2034  # read by osc_bench.sh's osc_margin_corner
MARGIN_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-pilot-margin.csv"
MARGIN_SUM_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-pilot-margin-summary.csv"
MD_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.md"
mkdir -p "${NETLIST_DIR}" "${LOG_DIR}" "${EXPERIMENT_DIR}/records"

make_scratch_workdir "sg13g2-osc-pilot"

# shellcheck source=osc_bench.sh
source "${EXPERIMENT_DIR}/osc_bench.sh"

# --------------------------------------------------------------- the subset
PILOT_MOS="tt"
PILOT_CAP="cap_typ"
PILOT_HBT="hbt_typ"
PILOT_TEMP_NOM="27"
PILOT_TEMPS_EDGE="-40 125"
# Six points spanning the full 0.0-3.3 V HV domain DR-001 settled. Every value
# except 1.65 V is also in sim/varactor-characterization's own V list, so the
# df/dV measured here and that study's dC/dV sit on a shared abscissa at those
# points instead of being interpolated against one another; 1.65 V is the
# netlist's own default and the band-centre point rows 1 and 8 are stated at.
PILOT_VCTRL="0.0 0.6 1.2 1.65 2.4 3.3"
PILOT_VCTRL_EDGE="0.0 1.65 3.3"
BAND_CENTRE_VCTRL="1.65"
# The coarser ceiling the convergence point is repeated at.
PILOT_TMAX_COARSE="5p"

osc_preflight
osc_write_csv_headers

n_words() { echo "$1" | wc -w | tr -d ' '; }
N_TRAN=$(( $(n_words "${PILOT_VCTRL}") \
           + $(n_words "${PILOT_TEMPS_EDGE}") * $(n_words "${PILOT_VCTRL_EDGE}") \
           + 1 ))
N_RUNGS=$(n_words "${OSC_MARGIN_SCALES}")

echo
echo "---------------------------------------------------------------"
echo "oscillator-core PILOT grid   record ${RECORD_ID}"
echo "THIS IS NOT THE GRADED row-10/11 GRID AND GRADES NO SPEC ROW."
echo "---------------------------------------------------------------"
echo "process corner    : mos_${PILOT_MOS} / ${PILOT_CAP} / ${PILOT_HBT} (typical only)"
echo "temperatures      : ${PILOT_TEMP_NOM} C (full Vctrl axis),"
echo "                    ${PILOT_TEMPS_EDGE} C (endpoints + band centre)"
echo "Vctrl axis        : {${PILOT_VCTRL}} V"
echo "transient points  : ${N_TRAN} (incl. 1 timestep-convergence repeat at ${PILOT_TMAX_COARSE})"
echo "margin ladder     : 1 corner x ${N_RUNGS} rungs at tstop ${OSC_MARGIN_TSTOP}"
echo "transient settings: tran ${OSC_TSTEP} ${OSC_TSTOP}, ceiling ${OSC_TMAX};"
echo "                    discard 0..${OSC_TMEAS_START} s, measure to ${OSC_TSTOP_S} s"
echo "---------------------------------------------------------------"
echo

total=0
passed=0
nosc_points=()
failed_points=()

run_point() {
  local corner_id="$1" temp="$2" vctrl="$3" tmax="$4"
  total=$((total + 1))
  if osc_simulate_point "${corner_id}" "${PILOT_MOS}" "${PILOT_CAP}" "${PILOT_HBT}" \
                        "${temp}" "${vctrl}" "${tmax}"; then
    passed=$((passed + 1))
  else
    local st
    st="$(awk -F, -v c="${corner_id}" '$1 == c { print $8 }' "${CSV_OUT}" | tail -1)"
    if [[ "${st}" == "NOSC" ]]; then
      nosc_points+=("${corner_id}")
    else
      failed_points+=("${corner_id}")
    fi
  fi
}

# 1. nominal corner, full Vctrl domain
for vctrl in ${PILOT_VCTRL}; do
  run_point "pilot_${PILOT_MOS}_${PILOT_CAP}_${PILOT_HBT}_${PILOT_TEMP_NOM}c_${vctrl}v" \
            "${PILOT_TEMP_NOM}" "${vctrl}" "${OSC_TMAX}"
done
osc_emit_tuning "${PILOT_MOS}" "${PILOT_CAP}" "${PILOT_HBT}" "${PILOT_TEMP_NOM}" "${OSC_TMAX}"

# 2. temperature extremes, endpoints + band centre
for temp in ${PILOT_TEMPS_EDGE}; do
  for vctrl in ${PILOT_VCTRL_EDGE}; do
    run_point "pilot_${PILOT_MOS}_${PILOT_CAP}_${PILOT_HBT}_${temp}c_${vctrl}v" \
              "${temp}" "${vctrl}" "${OSC_TMAX}"
  done
  osc_emit_tuning "${PILOT_MOS}" "${PILOT_CAP}" "${PILOT_HBT}" "${temp}" "${OSC_TMAX}"
done

# 3. timestep-convergence repeat of the nominal band-centre point
run_point "pilot_${PILOT_MOS}_${PILOT_CAP}_${PILOT_HBT}_${PILOT_TEMP_NOM}c_${BAND_CENTRE_VCTRL}v_${PILOT_TMAX_COARSE}" \
          "${PILOT_TEMP_NOM}" "${BAND_CENTRE_VCTRL}" "${PILOT_TMAX_COARSE}"

CONV="$(awk -F, -v vc="${BAND_CENTRE_VCTRL}" -v t="${PILOT_TEMP_NOM}" \
            -v fine="${OSC_TMAX}" -v coarse="${PILOT_TMAX_COARSE}" '
  NR > 1 && $5 == t && $6 == vc && $8 == "PASS" { f[$7] = $9; v[$7] = $14; p[$7] = $27 }
  END {
    if (!(fine in f) || !(coarse in f)) { print "nan,nan,nan"; exit }
    printf "%.4g,%.4g,%.4g\n", 100*(f[coarse]/f[fine]-1), \
           100*(v[coarse]/v[fine]-1), 100*(p[coarse]/p[fine]-1)
  }' "${CSV_OUT}")"
CONV_DF="${CONV%%,*}"; CONV_REST="${CONV#*,}"
CONV_DV="${CONV_REST%%,*}"; CONV_DP="${CONV_REST#*,}"

# 4. row-6 margin proxy at the nominal corner
margin_failed=()
osc_margin_corner "pilot_${PILOT_MOS}_${PILOT_CAP}_${PILOT_HBT}_${PILOT_TEMP_NOM}c" \
                  "${PILOT_MOS}" "${PILOT_CAP}" "${PILOT_HBT}" "${PILOT_TEMP_NOM}" \
  || margin_failed+=("pilot_${PILOT_MOS}_${PILOT_CAP}_${PILOT_HBT}_${PILOT_TEMP_NOM}c")

# ---------------------------------------------------------------- findings
# Read straight out of the CSVs this run wrote, so the narrative and the
# machine-readable evidence cannot disagree. These are FINDINGS, phrased
# against the row bounds for orientation -- not row verdicts. A row is graded
# over the row-10 corner set and this is not it.
F_CENTRE="$(awk -F, -v vc="${BAND_CENTRE_VCTRL}" -v tm="${OSC_TMAX}" '
  NR > 1 && $6 == vc && $7 == tm && $8 == "PASS" { printf "%s C: %.4g GHz; ", $5, $9/1e9 }' "${CSV_OUT}")"
IN_BAND="$(awk -F, -v vc="${BAND_CENTRE_VCTRL}" -v tm="${OSC_TMAX}" \
               -v lo="${OSC_ROW1_F_MIN_HZ}" -v hi="${OSC_ROW1_F_MAX_HZ}" '
  NR > 1 && $6 == vc && $7 == tm && $8 == "PASS" { n++; if ($9 >= lo && $9 <= hi) k++ }
  END { printf "%d/%d", k+0, n+0 }' "${CSV_OUT}")"
RATIO_SUMMARY="$(awk -F, 'NR > 1 { printf "%s C: %.4f (%s pts, worst floor %.3g %%); ", $4, $10, $5, $17 }' "${TUNING_CSV}")"
SETTLE_SUMMARY="$(awk -F, -v tm="${OSC_TMAX}" -v disc="${OSC_TMEAS_START}" '
  NR > 1 && $7 == tm && $8 == "PASS" && $15 != "nan" {
    n++; if (w == "" || $15+0 > w+0) w = $15; if (b == "" || $15+0 < b+0) b = $15 }
  END { if (n == 0) { print "no settled point" }
        else { printf "%d of the %s-ceiling points settled, in %.3g .. %.3g s; the discarded window is %.3gx the slowest of those", n, tm, b, w, disc/w } }' "${CSV_OUT}")"
SETTLE_WORST="$(awk -F, -v tm="${OSC_TMAX}" '
  NR > 1 && $7 == tm && $8 == "PASS" && $15 != "nan" { if (w == "" || $15+0 > w+0) w = $15 }
  END { print (w == "" ? "nan" : w) }' "${CSV_OUT}")"
CM_SUMMARY="$(awk -F, -v tm="${OSC_TMAX}" '
  NR > 1 && $7 == tm && $8 == "PASS" { n++; if (w == "" || $17+0 > w+0) w = $17; if (ft == "" || ($21+0 < ft+0)) ft = $21; if ($21+0 > ftx+0) ftx = $21 }
  END { if (n == 0) { print "no point" } else { printf "worst Vpp(cm)/Vpp(diff) %.3g over %d points; f(TAIL)/f_osc in [%.3f, %.3f]", w, n, ft, ftx } }' "${CSV_OUT}")"
P_SUMMARY="$(awk -F, -v vc="${BAND_CENTRE_VCTRL}" -v tm="${OSC_TMAX}" -v pmax="${OSC_ROW8_P_MAX_W}" '
  NR > 1 && $6 == vc && $7 == tm && $5 == 27 && $8 == "PASS" {
    printf "large-signal %.4g mW vs DC-operating-point %.4g mW (bound %g mW)", $27*1e3, $26*1e3, pmax*1e3 }' "${CSV_OUT}")"
MARGIN_SUMMARY="$(awk -F, 'NR > 1 { printf "bracket [%s, %s] against bound %s -> %s", $9, $10, $12, $11 }' "${MARGIN_SUM_CSV}")"

# ------------------------------------------------------------------ record
{
  echo "# Record ${RECORD_ID}"
  echo
  echo "- **Experiment**: oscillator-core (PILOT grid -- a declared SUBSET of"
  echo "  the graded corner set)"
  echo "- **Claim**: that \`design/vco.sch\` starts from the 10 mV differential"
  echo "  initial condition and oscillates differentially, and what its"
  echo "  \`f_osc(Vctrl)\`, tuning ratio, \`Kvco\` curve, startup settling time,"
  echo "  large-signal supply current and row-6 margin proxy MEASURE at the"
  echo "  nominal process corner over the three row-11 temperatures."
  echo "- **This record grades NO \`spec/target-spec.md\` row.** Rows 1, 2, 3, 6"
  echo "  and 8 are stated over the row-10 corner set (row 6: \"at every bound"
  echo "  corner\" of it). This is the typical process corner only. The numbers"
  echo "  below are findings about the circuit, quoted against the row bounds"
  echo "  for orientation; the graded entry point is \`run_pvt_sweep.sh\`, and"
  echo "  \`README.md\` states why it has not been run."
  echo "- **Corner subset**: MOS \`mos_${PILOT_MOS}\` / MIM \`${PILOT_CAP}\` /"
  echo "  HBT \`${PILOT_HBT}\`; T = ${PILOT_TEMP_NOM} C over Vctrl"
  echo "  \`{${PILOT_VCTRL}}\` V and T = \`{${PILOT_TEMPS_EDGE}}\` C over Vctrl"
  echo "  \`{${PILOT_VCTRL_EDGE}}\` V; V_DD = ${OSC_VDD_NOM} V; plus one repeat"
  echo "  of the ${PILOT_TEMP_NOM} C / ${BAND_CENTRE_VCTRL} V point at a"
  echo "  \`${PILOT_TMAX_COARSE}\` timestep ceiling. ${N_TRAN} transients, plus"
  echo "  a ${N_RUNGS}-rung margin ladder at the nominal corner."
  echo "- **Method** (full statement, because a frequency without its method is"
  echo "  not a result -- \`CLAUDE.md\`):"
  echo "  - ngspice has no PSS/pnoise, so \`f_osc\` is a TRANSIENT plus period"
  echo "    count, not a spectral or harmonic-balance solve. It states no phase"
  echo "    noise and no line width."
  echo "  - transient \`tran ${OSC_TSTEP} ${OSC_TSTOP}\`, timestep ceiling"
  echo "    \`${OSC_TMAX}\` (~100 samples per period at 5 GHz)."
  echo "  - startup from a ${OSC_IC_DIFF_MV} mV differential \`.ic\`"
  echo "    (\`v(OUTP)=${OSC_IC_OUTP}\`, \`v(OUTN)=${OSC_IC_OUTN}\`) -- an"
  echo "    initial condition, never refreshed."
  echo "  - discarded startup window 0 .. ${OSC_TMEAS_START} s; measurement"
  echo "    window ${OSC_TMEAS_START} s .. ${OSC_TSTOP_S} s. The discard is"
  echo "    $(awk -v d="${OSC_TMEAS_START}" -v w="${SETTLE_WORST}" 'BEGIN{ if (w+0 > 0) printf "%.3g", d/w; else printf "an unknown multiple of" }')x"
  echo "    the slowest settling time THIS RUN measured (${SETTLE_WORST} s) --"
  echo "    the ratio is computed from this run's own data rather than quoted"
  echo "    from the run the window was originally sized against. Every point"
  echo "    records its own \`t_settle_s\`, so a corner that needed longer is"
  echo "    visible rather than silently mismeasured."
  echo "  - \`f_osc\` = rising crossings of \`v(OUTP)-v(OUTN)\` through the"
  echo "    window's own trapezoidal time average, crossing times linearly"
  echo "    interpolated, frequency from the first and last crossing"
  echo "    (\`sim/lib.sh\` \`osc_metrics\`)."
  echo "  - **frequency quantization floor**: recorded per point, both bounds"
  echo "    -- \`quant_floor_interp_pct\` = \`dt_max*f/cycles\` (the estimator"
  echo "    actually used) and \`quant_floor_count_pct\` = \`1/cycles\` (what"
  echo "    the floor would be without interpolation)."
  echo "  - \`Kvco\` = first differences of measured \`f_osc\` between"
  echo "    consecutive \`Vctrl\` points; linearity is the peak-to-peak spread"
  echo "    of the per-segment slopes as a percentage of their mean."
  echo "  - supply current recorded TWICE and never conflated:"
  echo "    \`isup_dc_op_a\`/\`p_core_dc_op_w\` from the DC operating point and"
  echo "    \`isup_ls_avg_a\`/\`p_core_ls_w\`, the LARGE-SIGNAL trapezoidal time"
  echo "    average of \`-i(VSUP)\` over the settled window."
  echo "  - differential-mode check on every point: \`vpp_cm_over_diff\`,"
  echo "    \`f_cm_over_diff\`, \`f_tail_over_diff\`."
  echo "  - row-6 margin: the tail-current-scaling threshold proxy declared in"
  echo "    \`testbench/tb_vco_core_margin.spice.tmpl\`, reported as a BRACKET"
  echo "    between the last oscillating and first non-oscillating rung. \"It"
  echo "    oscillated\" is not reported as a row-6 result."
  echo "  - extractor validation: \`run_method_check.sh\`, same"
  echo "    \`osc_metrics\`/\`osc_settle\`, closed-form answers, derived"
  echo "    tolerances."
  echo "- **Findings** (not row verdicts):"
  echo "  - \`f_osc\` at Vctrl = ${BAND_CENTRE_VCTRL} V: ${F_CENTRE:-none}"
  echo "    (${IN_BAND} of the measured band-centre points fall inside the"
  echo "    row-1 window ${OSC_ROW1_F_MIN_HZ}..${OSC_ROW1_F_MAX_HZ} Hz)"
  echo "  - tuning ratio over the measured Vctrl span, per temperature:"
  echo "    ${RATIO_SUMMARY:-none} (row-2 bound ${OSC_ROW2_RATIO}, stretch"
  echo "    ${OSC_ROW2_RATIO_STRETCH}; the per-corner verdict columns in the"
  echo "    tuning CSV mark a ratio inside the quantization floor of the bound"
  echo "    rather than calling it a pass)"
  echo "  - start-up: ${SETTLE_SUMMARY}"
  echo "  - differential-mode check: ${CM_SUMMARY}"
  echo "  - core power at ${BAND_CENTRE_VCTRL} V, 27 C: ${P_SUMMARY:-none}"
  echo "  - row-6 margin proxy at the nominal corner: ${MARGIN_SUMMARY:-none}."
  echo "    This is ONE corner; row 6 is stated at every bound corner of the"
  echo "    row-10 set and is therefore not graded by it."
  echo "  - timestep convergence ${OSC_TMAX} -> ${PILOT_TMAX_COARSE} at the"
  echo "    nominal band-centre point: f_osc ${CONV_DF} %, Vpp_diff"
  echo "    ${CONV_DV} %, large-signal core power ${CONV_DP} %. This is the"
  echo "    CIRCUIT solution's discretization error, which the extractor check"
  echo "    cannot see."
  echo "- **Non-PDK model**: \`sim/inductor-model/sg13g2_inductor_em.spice\`"
  echo "  sha256 \`$(sha256_of "${OSC_IND_MODEL}")\`. **The PDK ships no"
  echo "  spiral-inductor ngspice model** (\`sim/pdk.json\`"
  echo "  \`known_model_gaps.spiral_inductor\`), so every frequency in this"
  echo "  record inherits that model's stated error bars and is NOT a PDK model"
  echo "  result. See \`sim/inductor-model/README.md\`."
  echo "- **PDK**: \`${PDK}\` at \`${PDK_ROOT}\` -- pinned release in"
  echo "  \`sim/pdk.json\`. Loaded libraries and the OSDI binary by digest:"
  echo "  - \`cornerHBT.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerHBT.lib")\`"
  echo "  - \`cornerMOShv.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerMOShv.lib")\`"
  echo "  - \`cornerCAP.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerCAP.lib")\`"
  echo "  - \`sg13g2_svaricaphv_mod.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/sg13g2_svaricaphv_mod.lib")\`"
  echo "  - \`sg13g2_hbt_mod.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/sg13g2_hbt_mod.lib")\`"
  echo "  - \`mosvar.osdi\` (this run's build) sha256 \`$(sha256_of "${OSC_OSDI_MOSVAR}")\`"
  echo "- **Netlist under test**: \`design/vco.spice\`, verified current with"
  echo "  \`design/vco.sch\` by \`design/netlist.sh --check\` before this run"
  echo "  generated anything. Device section sha256"
  echo "  \`$(sha256_of "${OSC_VCO_BODY}")\`."
  echo "- **ngspice**: \`${OSC_NGSPICE_VERSION}\`"
  echo "- **Result**: ${passed}/${total} transient points reached a countable"
  echo "  oscillation. Non-oscillating: ${#nosc_points[@]}. Simulation"
  echo "  failures: ${#failed_points[@]}. Margin corners completed:"
  echo "  $(( 1 - ${#margin_failed[@]} ))/1."
  if [[ ${#nosc_points[@]} -gt 0 ]]; then
    echo "- **Non-oscillating points** (kept, not dropped): ${nosc_points[*]}"
  fi
  if [[ ${#failed_points[@]} -gt 0 ]]; then
    echo "- **Failed simulations**: ${failed_points[*]}"
  fi
  echo "- **Links**:"
  echo "  - Templates: \`testbench/tb_vco_core_tran.spice.tmpl\`,"
  echo "    \`testbench/tb_vco_core_margin.spice.tmpl\`"
  echo "  - Per-point generated netlists: \`netlist-snapshots/${RECORD_ID}/\`"
  echo "  - Per-point raw ngspice logs: \`corners/${RECORD_ID}/\`"
  echo "  - Per-point scalars: \`records/${RECORD_ID}-pilot.csv\`"
  echo "  - Tuning / Kvco summary: \`records/${RECORD_ID}-pilot-tuning.csv\`"
  echo "  - Kvco curve: \`records/${RECORD_ID}-pilot-kvco.csv\`"
  echo "  - Margin ladder and bracket:"
  echo "    \`records/${RECORD_ID}-pilot-margin.csv\`,"
  echo "    \`records/${RECORD_ID}-pilot-margin-summary.csv\`"
  echo "- **Reproduce**: \`sim/oscillator-core/run_pilot_grid.sh\` (no"
  echo "  arguments) against the pinned PDK."
  echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MD_OUT}"

echo
echo "---------------------------------------------------------------"
echo "record          : ${RECORD_ID}   (PILOT -- grades no spec row)"
echo "transients      : ${passed}/${total} oscillating"
echo "f_osc @ ${BAND_CENTRE_VCTRL} V : ${F_CENTRE:-none}"
echo "tuning ratio    : ${RATIO_SUMMARY:-none}"
echo "start-up        : ${SETTLE_SUMMARY}"
echo "diff-mode check : ${CM_SUMMARY}"
echo "core power      : ${P_SUMMARY:-none}"
echo "row-6 proxy     : ${MARGIN_SUMMARY:-none}"
echo "tstep converge  : df=${CONV_DF}%  dVpp=${CONV_DV}%  dP=${CONV_DP}%"
echo "written         : ${MD_OUT#"${REPO_ROOT}"/}"
echo "---------------------------------------------------------------"

# A number that misses a row bound is a RESULT, not a failure: this script
# grades no row and must not exit non-zero for one. Only a broken SIMULATION
# is an error.
if [[ ${#failed_points[@]} -gt 0 || ${#margin_failed[@]} -gt 0 ]]; then
  echo "error: ${#failed_points[@]} transient point(s) and ${#margin_failed[@]} margin corner(s) failed to simulate (distinct from failing to oscillate)." >&2
  exit 1
fi
