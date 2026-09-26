#!/usr/bin/env bash
# Cold-start invocation (this is the whole thing -- there are no hidden manual
# steps; the netlist-freshness check and the OSDI build run automatically):
#
#   sim/oscillator-core/run_pvt_sweep.sh
#
# Optionally, if the PDK is not installed under one of the prefixes sim/env.sh
# probes (/usr/share/pdk, /usr/local/share/pdk, ~/share/pdk, ~/.ciel, ~/.volare):
#
#   export PDK_ROOT=/path/to/ihp-open-pdk   # parent dir containing ihp-sg13g2/
#   export PDK=ihp-sg13g2
#
# WHAT THIS MEASURES
# ------------------
# The GRADED oscillator-core evidence for design/vco.sch, over the
# spec/target-spec.md row-10/11 PVT grid:
#
#   row 1  f_osc at the band-centre control voltage, per corner
#   row 2  the fractional tuning ratio f_max/f_min over the full 0.0-3.3 V
#          Vctrl domain, per corner, with its quantization floor
#   row 3  Kvco(Vctrl) and its linearity, as first differences of the measured
#          f_osc(Vctrl) curve -- EVIDENCE for row 3, which is OPEN; measuring
#          a row is not ratifying it, and ratification is a
#          spec/decision-records/ PR, not this script
#   row 6  the startup margin, as the tail-current-scaling threshold proxy,
#          at the bound corners of the row-10 set (see
#          testbench/tb_vco_core_margin.spice.tmpl for what the proxy is, why
#          it maps onto the row's g_m/G_tank ratio, and where the map is
#          imperfect). "It oscillated" is NOT reported as a row-6 pass.
#   row 8  the LARGE-SIGNAL average supply current and core power over the
#          settled window, reported separately from the DC operating point's
#          current so the two are never confused
#
# plus, on every point: whether the oscillator started from the differential
# initial condition and when its envelope settled, and the differential-mode
# check (Vpp(vcm)/Vpp(vdiff) and both f(vcm)/f_osc and f(TAIL)/f_osc) without
# which every frequency above could be measuring two independently resonating
# branches instead of one differential tank.
#
# It does NOT measure phase noise (row 4). That needs a method design of its
# own size -- ngspice has no PSS/pnoise, so per CLAUDE.md a phase-noise number
# must carry its transient length, window, estimator, variance and stated
# limits -- and it needs a working graded transient bench to build on, which is
# what this is. It is a separate, later experiment.
#
# THIS IS A LARGE JOB. READ THIS BEFORE STARTING IT.
# --------------------------------------------------
# Measured on the machine that wrote this script (ngspice-46, one core, host
# under contention): this netlist simulates at roughly 13 ps of circuit time
# per second of wall clock at the 2 ps timestep ceiling -- 32 OSDI varactor
# instances and four HBTs, all stiff. A 2 ns transient took 169 s; the whole
# grid below is upward of 150 CPU-hours. It is a fleet job, not a workstation
# job. The script prints its own point count and cost estimate before it
# starts, and every point writes its own frozen netlist, raw log and CSV row
# as it completes, so an interrupted run leaves usable partial evidence
# rather than nothing.
#
# THREE WAYS TO MAKE IT CHEAPER HAVE BEEN MEASURED, NOT ASSUMED:
#   * shorten the transient. Done, and it is why OSC_TSTOP is 5 ns rather
#     than the 20 ns design/vco.spice's comments propose -- see that
#     constant's header in osc_bench.sh for the measured settling time the
#     window is derived from. This cut the grid ~4x.
#   * coarsen the timestep ceiling. MEASURED AND REJECTED: the same 2 ns
#     transient costs 169 s at a 2 ps ceiling and 183 s at 5 ps. The cost is
#     in the Newton iterations per accepted point, not in the point count, so
#     coarsening buys no CPU time and only discretization error (the measured
#     2p -> 5p delta on f_osc is -0.19 %; run_pilot_grid.sh records it).
#   * name the save set instead of `save all`. Done in both templates: ~10 %
#     of the run, bit-identical extracted f_osc and Vpp.
# What is left after all three is still a fleet job. Do not shave corners off
# the grid instead -- rows 1/2/6/10/11 are stated over this corner set, and a
# subset of it grades nothing. If only a subset can be afforded, run
# run_pilot_grid.sh, whose record says in its own words that it grades no row.
#
# `klt sim` is the tool that is supposed to route a grid this shape off-host,
# and at the time this landed it could not express this deck at all. The
# blocking gaps, all reproduced rather than assumed, are recorded with their
# logs in klt-sim/README.md, which also carries the request document to submit
# once they close.
#
# Requires: ngspice, xschem and awk on PATH, bash, and an IHP-Open-PDK v0.3.0
# install (pinned in sim/pdk.json).
#
# Everything it writes is APPEND-ONLY evidence under this directory, keyed by a
# record ID minted fresh on every run (sim/README.md):
#
#   netlist-snapshots/<record-id>/<corner-id>.spice   exact netlist simulated
#   corners/<record-id>/<corner-id>.log               raw ngspice batch output
#   records/<record-id>.csv                           one row per simulated point
#   records/<record-id>-tuning.csv                    row 1/2/3 summary per corner
#   records/<record-id>-kvco.csv                      the Kvco curve, per segment
#   records/<record-id>-margin.csv                    the row-6 ladder, per rung
#   records/<record-id>-margin-summary.csv            the bracketed row-6 margin
#   records/<record-id>.md                            the narrative record
set -euo pipefail

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SIM_DIR}/.." && pwd)"

# shellcheck source=../env.sh
source "${SIM_DIR}/env.sh"
# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"

RECORD_ID="$(mint_record_id "${REPO_ROOT}")"
# The record paths osc_bench.sh's helpers write to. shellcheck cannot follow a
# `source` of a file whose functions dereference them, so the two this script
# never names itself get an explicit disable rather than a silent warning.
NETLIST_DIR="${EXPERIMENT_DIR}/netlist-snapshots/${RECORD_ID}"
LOG_DIR="${EXPERIMENT_DIR}/corners/${RECORD_ID}"
CSV_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.csv"
TUNING_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-tuning.csv"
# shellcheck disable=SC2034  # read by osc_bench.sh's osc_emit_tuning
KVCO_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-kvco.csv"
# shellcheck disable=SC2034  # read by osc_bench.sh's osc_margin_corner
MARGIN_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-margin.csv"
MARGIN_SUM_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-margin-summary.csv"
MD_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.md"
mkdir -p "${NETLIST_DIR}" "${LOG_DIR}" "${EXPERIMENT_DIR}/records"

make_scratch_workdir "sg13g2-osc-pvt"

# shellcheck source=osc_bench.sh
source "${EXPERIMENT_DIR}/osc_bench.sh"

# ------------------------------------------------------------------ the grid
# spec/target-spec.md rows 10 and 11. The circuit contains three device
# families and SG13G2 ships one corner library per family, so a corner here
# names all three -- there is no single all-device corner section to select,
# and collapsing the three axes into a "tt/ss/ff" triple would silently assert
# that the families move together.
#
#   MOS: cornerMOShv.lib's five non-statistical sections. All five, not just
#        tt/ss/ff: sim/varactor-characterization established by reading the
#        file that sf and fs carry DISTINCT sg13g2_hv_svaricap_{vfbo,toxo,
#        dlq,dwq} values, so they are not ss/ff duplicates for the device that
#        does the tuning here.
#   CAP: cornerCAP.lib's three non-statistical sections.
#   HBT: cornerHBT.lib's three non-statistical sections.
#   T:   -40 / 27 / 125 C, row 11, the same span the other three sim/ studies
#        use.
# The *_mismatch / *_stat sections are omitted for the same reason the sibling
# studies omit them: they are a Monte-Carlo harness, which is later work.
MOS_LABELS="tt ss ff sf fs"
CAP_SECTIONS="cap_typ cap_bcs cap_wcs"
HBT_SECTIONS="hbt_typ hbt_bcs hbt_wcs"
TEMPS="-40 27 125"

# Control-voltage grid over the full 0.0-3.3 V HV domain row 2 names. The
# first nine values are exactly sim/varactor-characterization's own V list, so
# this bench's df/dV and that study's dC/dV are on the same abscissa and can be
# compared point for point instead of interpolated against each other; 1.65 V
# is added because it is the netlist's own default and the band-centre point
# rows 1 and 8 are graded at.
VCTRL_LIST="0.0 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0 3.3"
BAND_CENTRE_VCTRL="1.65"

# Bound corners for the row-6 margin pass. Row 6 says "at every bound corner
# of the row-10 set", so this is every combination of the NON-TYPICAL section
# of each family with the temperature extremes -- MOS {ss,ff,sf,fs} x CAP
# {bcs,wcs} x HBT {bcs,wcs} x T {-40,125} -- plus the nominal corner as the
# reference the margins are read against. MOS sf/fs are included for the same
# reason they are in the main grid: they are not interior to ss/ff for the
# varactor.
MARGIN_MOS="ss ff sf fs"
MARGIN_CAP="cap_bcs cap_wcs"
MARGIN_HBT="hbt_bcs hbt_wcs"
MARGIN_TEMPS="-40 125"

osc_preflight
osc_write_csv_headers

# ------------------------------------------------------------- cost estimate
# n_words <space-separated list> -- the axis lengths, so the printed point
# count is derived from the declared axes rather than restated next to them.
n_words() { echo "$1" | wc -w | tr -d ' '; }
N_PVT=$(( $(n_words "${MOS_LABELS}") * $(n_words "${CAP_SECTIONS}") \
          * $(n_words "${HBT_SECTIONS}") * $(n_words "${TEMPS}") ))
N_VCTRL=$(n_words "${VCTRL_LIST}")
N_TRAN=$((N_PVT * N_VCTRL))
# +1 for the nominal reference corner the bound-corner margins are read against
N_MARGIN=$(( 1 + $(n_words "${MARGIN_MOS}") * $(n_words "${MARGIN_CAP}") \
                 * $(n_words "${MARGIN_HBT}") * $(n_words "${MARGIN_TEMPS}") ))
N_RUNGS=$(n_words "${OSC_MARGIN_SCALES}")

echo
echo "---------------------------------------------------------------"
echo "oscillator-core graded PVT sweep   record ${RECORD_ID}"
echo "---------------------------------------------------------------"
echo "PVT points        : ${N_PVT}  (MOS {${MOS_LABELS}} x CAP {${CAP_SECTIONS}}"
echo "                     x HBT {${HBT_SECTIONS}} x T {${TEMPS}} C)"
echo "Vctrl points      : ${N_VCTRL}  {${VCTRL_LIST}} V"
echo "transient points  : ${N_TRAN}"
echo "margin corners    : ${N_MARGIN} x ${N_RUNGS} rungs = $((N_MARGIN * N_RUNGS)) transients"
echo "transient settings: tran ${OSC_TSTEP} ${OSC_TSTOP}, ceiling ${OSC_TMAX};"
echo "                    discard 0..${OSC_TMEAS_START} s, measure to ${OSC_TSTOP_S} s"
echo "                    margin ladder runs to ${OSC_MARGIN_TSTOP}"
# The estimate is DERIVED from one measured rate constant and the declared
# axes, so it cannot drift away from the settings above the way a hardcoded
# "~N CPU-hours" sentence would. OSC_SECS_PER_NS is the measured wall-clock
# cost of one nanosecond of circuit time on one core at OSC_TMAX; everything
# else is arithmetic.
OSC_SECS_PER_NS=76
EST_H=$(awk -v nt="${N_TRAN}" -v ts="${OSC_TSTOP_S}" -v nm="$((N_MARGIN * N_RUNGS))" \
            -v ms="${OSC_MARGIN_TSTOP_S}" -v r="${OSC_SECS_PER_NS}" \
        'BEGIN { printf "%.0f", (nt*ts*1e9 + nm*ms*1e9) * r / 3600 }')
echo "measured rate     : ~${OSC_SECS_PER_NS} s wall clock per ns of circuit time per core"
echo "                    at this ceiling (2 ns transient = 169 s, ngspice-46)."
echo "                    Coarsening the ceiling does NOT help: the same 2 ns"
echo "                    transient costs 183 s at a 5 ps ceiling."
echo "estimated cost    : ~${EST_H} CPU-hours."
echo "                    This is a fleet job. Partial evidence is written"
echo "                    point by point, so an interrupted run is not lost."
echo "---------------------------------------------------------------"
echo

# --------------------------------------------------------------- main sweep
total=0
passed=0
nosc_points=()
failed_points=()

for mos in ${MOS_LABELS}; do
  for cap in ${CAP_SECTIONS}; do
    for hbt in ${HBT_SECTIONS}; do
      for temp in ${TEMPS}; do
        for vctrl in ${VCTRL_LIST}; do
          corner_id="vco_${mos}_${cap}_${hbt}_${temp}c_${vctrl}v"
          total=$((total + 1))
          if osc_simulate_point "${corner_id}" "${mos}" "${cap}" "${hbt}" \
                                "${temp}" "${vctrl}" "${OSC_TMAX}"; then
            passed=$((passed + 1))
          else
            # Distinguish "simulated fine, did not oscillate" from "the
            # simulation itself failed": they are different findings and row 6
            # in particular is decided by which one it is.
            st="$(awk -F, -v c="${corner_id}" '$1 == c { print $8 }' "${CSV_OUT}" | tail -1)"
            if [[ "${st}" == "NOSC" ]]; then
              nosc_points+=("${corner_id}")
            else
              failed_points+=("${corner_id}")
            fi
          fi
        done
        osc_emit_tuning "${mos}" "${cap}" "${hbt}" "${temp}"
      done
    done
  done
done

# ------------------------------------------------------------- margin sweep
margin_total=0
margin_failed=()
osc_margin_corner "vco_tt_cap_typ_hbt_typ_27c" tt cap_typ hbt_typ 27 \
  || margin_failed+=("vco_tt_cap_typ_hbt_typ_27c")
margin_total=$((margin_total + 1))
for mos in ${MARGIN_MOS}; do
  for cap in ${MARGIN_CAP}; do
    for hbt in ${MARGIN_HBT}; do
      for temp in ${MARGIN_TEMPS}; do
        base="vco_${mos}_${cap}_${hbt}_${temp}c"
        margin_total=$((margin_total + 1))
        osc_margin_corner "${base}" "${mos}" "${cap}" "${hbt}" "${temp}" \
          || margin_failed+=("${base}")
      done
    done
  done
done

# ---------------------------------------------------------------- verdicts
# Read straight out of the CSVs the run just wrote, so the narrative and the
# machine-readable evidence can never disagree.
ROW1_AT_CENTRE="$(awk -F, -v vc="${BAND_CENTRE_VCTRL}" -v lo="${OSC_ROW1_F_MIN_HZ}" -v hi="${OSC_ROW1_F_MAX_HZ}" '
  NR > 1 && $6 == vc && $8 == "PASS" { n++; if (fmin == "" || $9 < fmin) fmin = $9; if ($9 > fmax) fmax = $9; if ($9 >= lo && $9 <= hi) inband++ }
  END { if (n == 0) { print "no oscillating point at the band-centre control voltage"; exit }
        printf "%d/%d corners inside %g..%g Hz; measured %g..%g Hz", inband+0, n, lo, hi, fmin, fmax }' "${CSV_OUT}")"
ROW2_SUMMARY="$(awk -F, 'NR > 1 { n++; if ($19 == "MET") met++; else if ($19 ~ /QUANTIZATION/) floor++ }
  END { if (n == 0) { print "no corner produced a tuning ratio"; exit }
        printf "%d/%d corners MET, %d within the quantization floor of the bound", met+0, n, floor+0 }' "${TUNING_CSV}")"
ROW6_SUMMARY="$(awk -F, 'NR > 1 { n++; if ($11 == "MET") met++; else if ($11 ~ /STRADDLES/) strad++ }
  END { if (n == 0) { print "no margin corner completed"; exit }
        printf "%d/%d corners MET, %d straddling the bound", met+0, n, strad+0 }' "${MARGIN_SUM_CSV}")"
ROW8_SUMMARY="$(awk -F, -v vc="${BAND_CENTRE_VCTRL}" -v pmax="${OSC_ROW8_P_MAX_W}" '
  NR > 1 && $6 == vc && $5 == 27 && $8 == "PASS" { n++; if ($27 <= pmax) ok++; if (worst == "" || $27 > worst) worst = $27 }
  END { if (n == 0) { print "no oscillating point at band centre and 27 C" ; exit }
        printf "%d/%d corners at or below %g W large-signal core power; worst %g W", ok+0, n, pmax, worst }' "${CSV_OUT}")"

# ------------------------------------------------------------------ record
{
  echo "# Record ${RECORD_ID}"
  echo
  echo "- **Experiment**: oscillator-core (graded PVT sweep)"
  echo "- **Claim**: start-up, \`f_osc\` over the full 0.0-3.3 V \`Vctrl\`"
  echo "  domain, the derived tuning ratio and \`Kvco(Vctrl)\` curve, and the"
  echo "  large-signal supply current of \`design/vco.sch\`, over the"
  echo "  \`spec/target-spec.md\` row-10/11 PVT grid; plus the row-6 startup"
  echo "  margin at the bound corners of that grid via a declared proxy."
  echo "  **Measuring a row is not ratifying it.** Row 3 is OPEN and this"
  echo "  record supplies its evidence without ratifying it; ratification is a"
  echo "  \`spec/decision-records/\` PR. Phase noise (row 4) is not measured"
  echo "  here."
  echo "- **Netlist under test**: \`design/vco.spice\`, verified current with"
  echo "  \`design/vco.sch\` by \`design/netlist.sh --check\` before this run"
  echo "  generated anything. Device section sha256"
  echo "  \`$(sha256_of "${OSC_VCO_BODY}")\`; the schematic's own \`.control\`"
  echo "  elaboration block and its \`.save i(vsup)\` card are excluded (see"
  echo "  \`osc_bench.sh\`'s \`osc_derive_body\`), nothing else is rewritten."
  echo "- **Corner matrix**: MOS \`{${MOS_LABELS}}\` x MIM"
  echo "  \`{${CAP_SECTIONS}}\` x HBT \`{${HBT_SECTIONS}}\` x T"
  echo "  \`{${TEMPS}}\` C = ${N_PVT} PVT points, x \`{${VCTRL_LIST}}\` V ="
  echo "  ${N_TRAN} transients. Margin pass: ${N_MARGIN} corners x ${N_RUNGS}"
  echo "  ladder rungs."
  echo "- **Method** (full statement -- a frequency without its method is not a"
  echo "  result, \`CLAUDE.md\`):"
  echo "  - ngspice has no PSS/pnoise, so \`f_osc\` is a TRANSIENT plus period"
  echo "    count. It is not a spectral estimate and it states no phase noise"
  echo "    and no line width."
  echo "  - transient \`tran ${OSC_TSTEP} ${OSC_TSTOP}\`, timestep ceiling"
  echo "    \`${OSC_TMAX}\` (~100 samples per period at the 5 GHz row-1"
  echo "    target)."
  echo "  - startup from a ${OSC_IC_DIFF_MV} mV differential \`.ic\`"
  echo "    (\`v(OUTP)=${OSC_IC_OUTP}\`, \`v(OUTN)=${OSC_IC_OUTN}\`) -- an"
  echo "    initial condition, never refreshed. A perfectly symmetric pair"
  echo "    otherwise sits on its unstable DC equilibrium and never starts."
  echo "  - discarded startup window 0 .. ${OSC_TMEAS_START} s; measurement"
  echo "    window ${OSC_TMEAS_START} s .. ${OSC_TSTOP_S} s (~50 settled"
  echo "    periods at 5 GHz)."
  echo "  - \`f_osc\` = rising crossings of \`v(OUTP)-v(OUTN)\` through the"
  echo "    window's own trapezoidal time average, crossing times linearly"
  echo "    interpolated, frequency taken from the first and last crossing"
  echo "    (\`sim/lib.sh\` \`osc_metrics\`)."
  echo "  - **frequency quantization floor**: recorded per point, both bounds"
  echo "    -- \`quant_floor_interp_pct\` = \`dt_max*f/cycles\` (the estimator"
  echo "    actually used) and \`quant_floor_count_pct\` = \`1/cycles\` (the"
  echo "    no-interpolation bound). A row-2 ratio landing inside the floor of"
  echo "    its bound is recorded as WITHIN QUANTIZATION FLOOR OF BOUND, never"
  echo "    as a bare pass."
  echo "  - startup settling time = when the envelope first reaches"
  echo "    ${OSC_SETTLE_FRAC} of its final peak-to-peak and stays there"
  echo "    (\`sim/lib.sh\` \`osc_settle\`); a non-starting corner is recorded"
  echo "    as status \`NOSC\` and kept in the grid, never dropped."
  echo "  - \`Kvco\` = first differences of measured \`f_osc\` between"
  echo "    consecutive \`Vctrl\` points -- the same finite-difference"
  echo "    derivation \`sim/varactor-characterization\` applies to C(V), on"
  echo "    the same abscissa. Linearity is the peak-to-peak spread of the"
  echo "    per-segment slopes as a percentage of their mean."
  echo "  - supply current is recorded TWICE and the two are never conflated:"
  echo "    \`isup_dc_op_a\`/\`p_core_dc_op_w\` from the DC operating point,"
  echo "    and \`isup_ls_avg_a\`/\`p_core_ls_w\`, the LARGE-SIGNAL"
  echo "    trapezoidal time average of \`-i(VSUP)\` over the settled window."
  echo "    Row 8 is the large-signal number."
  echo "  - differential-mode check, per point: \`vpp_cm_over_diff\`,"
  echo "    \`f_cm_over_diff\` and \`f_tail_over_diff\`. A differential tank"
  echo "    puts the whole fundamental in \`vdiff\` and leaves the common mode"
  echo "    and the tail with the 2f component the two half-circuits pump in"
  echo "    phase, so both frequency ratios should land near 2 and the"
  echo "    common-mode amplitude should be a small fraction of the"
  echo "    differential one. A fundamental in the common mode would mean two"
  echo "    independently resonating branches, and every frequency number here"
  echo "    would be measuring the wrong circuit."
  echo "  - row-6 margin: the tail-current-scaling threshold proxy, NOT \"it"
  echo "    oscillated\". \`testbench/tb_vco_core_margin.spice.tmpl\` states"
  echo "    what it measures, why \`I_tail,nom/I_tail,threshold\` maps onto the"
  echo "    row's \`g_m/G_tank\` ratio (\`g_m = I_C/V_T\` makes \`g_m\`"
  echo "    proportional to \`I_tail\` exactly in the HBT's forward-active"
  echo "    region), and its four stated limits. The margin is reported as a"
  echo "    BRACKET between the last oscillating and first non-oscillating"
  echo "    rung, never as an interpolated single number, and the proxy is"
  echo "    conservative (a near-threshold rung still growing at the end of"
  echo "    the window is recorded as not oscillating, which biases the"
  echo "    margin DOWN)."
  echo "  - extractor validation: \`run_method_check.sh\` checks the same"
  echo "    \`osc_metrics\`/\`osc_settle\` against synthetic waveforms whose"
  echo "    frequency, amplitude, time average and settling time are known in"
  echo "    closed form, with tolerances DERIVED from the estimator's own"
  echo "    discretization bounds. Its record is the companion to this one."
  echo "- **Non-PDK model**: \`sim/inductor-model/sg13g2_inductor_em.spice\`"
  echo "  sha256 \`$(sha256_of "${OSC_IND_MODEL}")\`. **The PDK ships no"
  echo "  spiral-inductor ngspice model** (\`sim/pdk.json\`"
  echo "  \`known_model_gaps.spiral_inductor\`), so every frequency in this"
  echo "  record inherits that model's stated error bars and is NOT a PDK"
  echo "  model result. See \`sim/inductor-model/README.md\`."
  echo "- **PDK**: \`${PDK}\` at \`${PDK_ROOT}\` -- pinned release in"
  echo "  \`sim/pdk.json\`. Loaded libraries and the OSDI binary by digest:"
  echo "  - \`cornerHBT.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerHBT.lib")\`"
  echo "  - \`cornerMOShv.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerMOShv.lib")\`"
  echo "  - \`cornerCAP.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerCAP.lib")\`"
  echo "  - \`sg13g2_svaricaphv_mod.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/sg13g2_svaricaphv_mod.lib")\`"
  echo "  - \`sg13g2_hbt_mod.lib\` sha256 \`$(sha256_of "${SG13G2_NGSPICE_MODELS}/sg13g2_hbt_mod.lib")\`"
  echo "  - \`mosvar.osdi\` (this run's build) sha256 \`$(sha256_of "${OSC_OSDI_MOSVAR}")\`"
  echo "- **ngspice**: \`${OSC_NGSPICE_VERSION}\`"
  echo "- **Result**: ${passed}/${total} transient points reached a countable"
  echo "  oscillation. Non-oscillating points: ${#nosc_points[@]}."
  echo "  Simulation failures: ${#failed_points[@]}."
  echo "  Margin corners completed: $(( margin_total - ${#margin_failed[@]} ))/${margin_total}."
  if [[ ${#nosc_points[@]} -gt 0 ]]; then
    echo "- **Non-oscillating corners** (kept in the grid, not dropped):"
    echo "  ${nosc_points[*]}"
  fi
  if [[ ${#failed_points[@]} -gt 0 ]]; then
    echo "- **Failed simulations**: ${failed_points[*]}"
  fi
  if [[ ${#margin_failed[@]} -gt 0 ]]; then
    echo "- **Failed margin corners**: ${margin_failed[*]}"
  fi
  echo "- **Row verdicts, read out of the CSVs this run wrote**:"
  echo "  - row 1 (band ${OSC_ROW1_F_MIN_HZ}..${OSC_ROW1_F_MAX_HZ} Hz at Vctrl"
  echo "    = ${BAND_CENTRE_VCTRL} V): ${ROW1_AT_CENTRE}"
  echo "  - row 2 (ratio >= ${OSC_ROW2_RATIO}, stretch ${OSC_ROW2_RATIO_STRETCH}):"
  echo "    ${ROW2_SUMMARY}"
  echo "  - row 6 (margin >= ${OSC_ROW6_MARGIN}, via the declared proxy):"
  echo "    ${ROW6_SUMMARY}"
  echo "  - row 8 (core power <= ${OSC_ROW8_P_MAX_W} W, large-signal, band"
  echo "    centre, 27 C): ${ROW8_SUMMARY}"
  echo "  - row 3 (Kvco and its linearity): measured, see"
  echo "    \`records/${RECORD_ID}-kvco.csv\` and the \`kvco_*\` columns of"
  echo "    \`records/${RECORD_ID}-tuning.csv\`. **Row 3 is OPEN; this record"
  echo "    does not ratify it.**"
  echo "- **Links**:"
  echo "  - Templates: \`testbench/tb_vco_core_tran.spice.tmpl\`,"
  echo "    \`testbench/tb_vco_core_margin.spice.tmpl\`"
  echo "  - Per-point generated netlists: \`netlist-snapshots/${RECORD_ID}/\`"
  echo "  - Per-point raw ngspice logs: \`corners/${RECORD_ID}/\`"
  echo "  - Per-point scalars: \`records/${RECORD_ID}.csv\`"
  echo "  - Tuning / Kvco summary: \`records/${RECORD_ID}-tuning.csv\`"
  echo "  - Kvco curve: \`records/${RECORD_ID}-kvco.csv\`"
  echo "  - Row-6 ladder and bracket: \`records/${RECORD_ID}-margin.csv\`,"
  echo "    \`records/${RECORD_ID}-margin-summary.csv\`"
  echo "- **Reproduce**: \`sim/oscillator-core/run_pvt_sweep.sh\` (no"
  echo "  arguments) against the pinned PDK."
  echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MD_OUT}"

echo
echo "---------------------------------------------------------------"
echo "record          : ${RECORD_ID}"
echo "transients      : ${passed}/${total} oscillating"
echo "non-oscillating : ${#nosc_points[@]}"
echo "sim failures    : ${#failed_points[@]}"
echo "margin corners  : $(( margin_total - ${#margin_failed[@]} ))/${margin_total}"
echo "row 1           : ${ROW1_AT_CENTRE}"
echo "row 2           : ${ROW2_SUMMARY}"
echo "row 6           : ${ROW6_SUMMARY}"
echo "row 8           : ${ROW8_SUMMARY}"
echo "written         : ${MD_OUT#"${REPO_ROOT}"/}"
echo "---------------------------------------------------------------"

# A missed spec row is a RESULT and must not fail the run: the record above is
# the deliverable either way, and per CLAUDE.md a sizing change is a separate
# design/ PR rather than something to chase here. Only a broken SIMULATION is
# an error.
if [[ ${#failed_points[@]} -gt 0 || ${#margin_failed[@]} -gt 0 ]]; then
  echo "error: ${#failed_points[@]} transient point(s) and ${#margin_failed[@]} margin corner(s) failed to simulate (distinct from failing to oscillate)." >&2
  exit 1
fi
