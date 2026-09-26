#!/usr/bin/env bash
# Cold-start invocation (this is the whole thing -- the netlist-freshness check
# and the OSDI build run automatically, there are no hidden manual steps):
#
#   sim/phase-noise/run_isf_pilot.sh
#
# Optionally, if the PDK is not installed under one of the prefixes sim/env.sh
# probes (/usr/share/pdk, /usr/local/share/pdk, ~/share/pdk, ~/.ciel, ~/.volare):
#
#   export PDK_ROOT=/path/to/ihp-open-pdk   # parent dir containing ihp-sg13g2/
#   export PDK=ihp-sg13g2
#
# WHAT THIS IS -- AND WHAT IT IS NOT
# ----------------------------------
# The measured phase noise of design/vco.sch: an ISF (Hajimiri-Lee) derivation
# of L(df) at 1 MHz and 10 MHz offsets, with its method, its variance across
# realisations and its stated limits, at ONE declared corner.
#
# **It grades no spec/target-spec.md row.** Row 4 is stated at a band-centre
# carrier over the corner set rows 10 and 11 settle -- 135 PVT points -- and
# this is the nominal process corner at 27 C only. The number below is a
# finding about the circuit, quoted against the row-4 bounds for orientation.
# Why the graded grid did not run, and what it would cost, is printed by this
# script from its OWN measured rate constant and restated in the record; see
# also README.md, "The graded grid is a fleet job".
#
# THE ESTIMATOR, IN ONE PARAGRAPH (the full justification is in README.md)
# ngspice has no PSS and no pnoise, and -- decisively -- its transient analysis
# runs with device noise sources switched off, so a periodogram or a
# period-jitter conversion of this deck's own transient would measure the
# solver's truncation error rather than the circuit's phase noise, at any
# transient length. The estimator here is therefore not spectral at all: it
# measures the oscillator's impulse sensitivity function by injecting charge
# impulses at a train of carrier phases and reading the permanent excess-phase
# step each one produces, then combines Gq_rms with the port's equivalent noise
# current from a small-signal `noise` analysis through the Hajimiri-Lee kernel.
# It needs tens of carrier periods, not the hundreds of thousands a 1 MHz
# offset resolution would demand -- which, at this netlist's measured 13 ps of
# circuit time per wall-clock second, is the difference between minutes and
# millennia.
#
# Requires: ngspice, xschem and awk on PATH, bash, and an IHP-Open-PDK v0.3.0
# install (pinned in sim/pdk.json).
#
# Everything it writes is APPEND-ONLY evidence under this directory, keyed by a
# record ID minted fresh on every run (sim/README.md).
#
# The PN_* bench constants and the OSC_* ones come from the two files this
# script sources, so shellcheck cannot see where they are assigned.
# shellcheck disable=SC2153
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
ISF_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-pilot-isf.csv"
REAL_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-pilot-realizations.csv"
NOISE_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-pilot-portnoise.csv"
SUMMARY_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-pilot-summary.csv"
MD_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.md"
mkdir -p "${NETLIST_DIR}" "${LOG_DIR}" "${EXPERIMENT_DIR}/records"

make_scratch_workdir "sg13g2-pn-pilot"

# osc_bench.sh is sourced by pn_bench.sh -- see that file's header for why the
# preflight, the device-section derivation and the rendering are reused from
# sim/oscillator-core/ rather than reimplemented.
# shellcheck source=../oscillator-core/osc_bench.sh
source "${SIM_DIR}/oscillator-core/osc_bench.sh"
# shellcheck source=pn_bench.sh
source "${EXPERIMENT_DIR}/pn_bench.sh"

# ---------------------------------------------------------- the declared corner
PILOT_MOS="tt"
PILOT_CAP="cap_typ"
PILOT_HBT="hbt_typ"
PILOT_TEMP="27"

osc_preflight

# ------------------------------------------------- the impulse-train schedule
# Derived ONCE and shared by every run in this record, so all of them carry an
# identical PWL breakpoint set. That is what makes the reference run's
# pre-impulse crossing-offset residual an exact null rather than a measurement
# of the solver's step-sequence divergence.
PN_IMP_DT="$(awk -v f="${PN_F0_NOM}" -v n="${PN_IMP_NPER}" -v m="${PN_N_IMP}" \
                 'BEGIN{ printf "%.12e", (n + 1.0/m)/f }')"
PN_IMP_TIMES="$(pn_imp_times "${PN_IMP_T1}" "${PN_IMP_DT}" "${PN_N_IMP}")"
PN_TSTOP_S="$(awk -v t1="${PN_IMP_T1}" -v dt="${PN_IMP_DT}" -v m="${PN_N_IMP}" \
                  'BEGIN{ printf "%.12e", t1 + m*dt }')"

N_RUNS=$(( 1 + $(echo "${PN_TANK_DQ_LIST}" | wc -w) + $(echo "${PN_TAIL_DQ_LIST}" | wc -w) ))

echo
echo "---------------------------------------------------------------"
echo "phase-noise ISF PILOT   record ${RECORD_ID}"
echo "ONE CORNER. THIS GRADES NO spec/target-spec.md ROW."
echo "---------------------------------------------------------------"
echo "corner            : mos_${PILOT_MOS} / ${PILOT_CAP} / ${PILOT_HBT}, ${PILOT_TEMP} C,"
echo "                    Vctrl = ${PN_VCTRL} V, V_DD = ${OSC_VDD_NOM} V"
echo "transient         : tran ${PN_TSTEP} ${PN_TSTOP_S}, ceiling ${PN_TMAX},"
echo "                    crossings compared from ${PN_TMEAS_START} s"
echo "impulse train     : ${PN_N_IMP} impulses, first at ${PN_IMP_T1} s,"
echo "                    spacing ${PN_IMP_DT} s = (${PN_IMP_NPER} + 1/${PN_N_IMP}) periods at ${PN_F0_NOM} Hz,"
echo "                    triangular half-width ${PN_IMP_HW} s"
echo "realisations      : tank {${PN_TANK_DQ_LIST}} C, tail {${PN_TAIL_DQ_LIST}} C"
echo "transient runs    : ${N_RUNS} (1 reference + $(( N_RUNS - 1 )) perturbed)"
echo "port-noise runs   : 2 (tank, tail), small-signal, seconds each"
echo "---------------------------------------------------------------"
echo

echo "port,realization,dq_c,impulse,t_imp_s,phi_rad,dphi_rad,gq_rad_per_C,plateau_ripple_s,n_plateau" > "${ISF_CSV}"
echo "port,realization,dq_c,f0_hz,vpp_diff_v,gq_rms_trapz,gq_rms_sample,c0,c1,c2,c3,max_phase_gap_rad,n_phases,null_floor_s,n_crossings_unmatched,l_1mhz_dbc,l_10mhz_dbc" > "${REAL_CSV}"
echo "port,freq_hz,inoise_a_per_sqrt_hz" > "${NOISE_CSV}"
echo "quantity,value,unit,note" > "${SUMMARY_CSV}"

# ============================================================ port noise
# Cheap (a DC operating point plus a linear solve per frequency), so it runs
# first: if the noise analysis cannot be done at all, there is no point
# spending an hour on the transients.
for port in tank tail; do
  cls="$(pn_noise_run "${port}" "${PILOT_MOS}" "${PILOT_CAP}" "${PILOT_HBT}" "${PILOT_TEMP}" "${PN_VCTRL}")"
  rc="${cls#rc=}"; rc="${rc%% *}"
  merr="${cls##*model_error=}"
  if [[ "${rc}" != "0" || "${merr}" != "0" ]]; then
    echo "error: the ${port}-port noise analysis failed (rc=${rc} model_error=${merr}); see ${LOG_DIR}/pnoise_${port}.log" >&2
    exit 1
  fi
  while read -r f v; do echo "${port},${f},${v}" >> "${NOISE_CSV}"; done < <(pn_inoise_table "${LOG_DIR}/pnoise_${port}.log")
  echo "[pnoise_${port}] median inoise = $(pn_inoise_from_log "${LOG_DIR}/pnoise_${port}.log") A/sqrt(Hz)"
done

SI_TANK_SQRT="$(pn_inoise_from_log "${LOG_DIR}/pnoise_tank.log")"
SI_TAIL_SQRT="$(pn_inoise_from_log "${LOG_DIR}/pnoise_tail.log")"
SI_TANK="$(awk -v s="${SI_TANK_SQRT}" 'BEGIN{ if (s=="nan") print "nan"; else printf "%.8e", s*s }')"
SI_TAIL="$(awk -v s="${SI_TAIL_SQRT}" 'BEGIN{ if (s=="nan") print "nan"; else printf "%.8e", s*s }')"
# Flatness of the referral over the swept band: a referral that was ill
# conditioned somewhere shows up here rather than hiding inside the median.
NOISE_FLAT_TANK="$(awk -F, '$1=="tank" && NR>1 { n++; if (lo==""||$3+0<lo) lo=$3+0; if ($3+0>hi) hi=$3+0 }
  END { if (n<2) print "nan"; else printf "%.3f", 100*(hi-lo)/(0.5*(hi+lo)) }' "${NOISE_CSV}")"
NOISE_FLAT_TAIL="$(awk -F, '$1=="tail" && NR>1 { n++; if (lo==""||$3+0<lo) lo=$3+0; if ($3+0>hi) hi=$3+0 }
  END { if (n<2) print "nan"; else printf "%.3f", 100*(hi-lo)/(0.5*(hi+lo)) }' "${NOISE_CSV}")"

# ============================================================ the reference run
T_WALL_START="$(date +%s)"
cls="$(pn_isf_run "ref" "0" "0" "${PILOT_MOS}" "${PILOT_CAP}" "${PILOT_HBT}" "${PILOT_TEMP}" "${PN_VCTRL}")"
T_WALL_REF=$(( $(date +%s) - T_WALL_START ))
rc="${cls#rc=}"; rc="${rc%% *}"; merr="${cls##*model_error=}"
if [[ "${rc}" != "0" || "${merr}" != "0" ]]; then
  echo "error: the reference transient failed (rc=${rc} model_error=${merr}); see ${LOG_DIR}/ref.log" >&2
  exit 1
fi
REF_DAT="${WORKDIR}/pn_ref_vdiff"
[[ -f "${REF_DAT}" ]] || { echo "error: the reference deck wrote no trace at ${REF_DAT}" >&2; exit 1; }

# ONE crossing threshold, from the reference run, applied to every run: see
# pn_window_mean's header in sim/lib.sh.
THR="$(pn_window_mean "${REF_DAT}" "${PN_TMEAS_START}" "${PN_TSTOP_S}")"
pn_crossings "${REF_DAT}" "${PN_TMEAS_START}" "${PN_TSTOP_S}" "${THR}" > "${WORKDIR}/ref.cross"
read -r F0_MEAS VPP_MEAS CYCLES_MEAS _MEAN_MEAS _TX1 _TX2 DTMAX_MEAS _NS \
  <<<"$(osc_metrics "${REF_DAT}" "${PN_TMEAS_START}" "${PN_TSTOP_S}")"
echo "[ref] ${T_WALL_REF} s wall; f_osc = ${F0_MEAS} Hz, Vpp_diff = ${VPP_MEAS} V, ${CYCLES_MEAS} cycles"

# Phase-grid uniformity is a property of how far the MEASURED carrier is from
# the nominal the train was designed around. Recorded, because it is the only
# thing that nominal affects.
F0_GRID_ERR_PCT="$(awk -v a="${F0_MEAS}" -v b="${PN_F0_NOM}" 'BEGIN{ printf "%.4f", 100*(a/b - 1) }')"

# ============================================================ the perturbed runs
n_realizations=0
run_realization() {
  local port="$1" idx="$2" dq="$3"
  local run_id="${port}_r${idx}"
  local dq_tank="0" dq_tail="0"
  [[ "${port}" == "tank" ]] && dq_tank="${dq}" || dq_tail="${dq}"

  local t0 cls rc merr
  t0="$(date +%s)"
  cls="$(pn_isf_run "${run_id}" "${dq_tank}" "${dq_tail}" \
                    "${PILOT_MOS}" "${PILOT_CAP}" "${PILOT_HBT}" "${PILOT_TEMP}" "${PN_VCTRL}")"
  rc="${cls#rc=}"; rc="${rc%% *}"; merr="${cls##*model_error=}"
  local twall=$(( $(date +%s) - t0 ))
  if [[ "${rc}" != "0" || "${merr}" != "0" ]]; then
    echo "error: run ${run_id} failed (rc=${rc} model_error=${merr}); see ${LOG_DIR}/${run_id}.log" >&2
    return 1
  fi
  local dat="${WORKDIR}/pn_${run_id}_vdiff"
  [[ -f "${dat}" ]] || { echo "error: ${run_id} wrote no trace" >&2; return 1; }

  pn_crossings "${dat}" "${PN_TMEAS_START}" "${PN_TSTOP_S}" "${THR}" > "${WORKDIR}/${run_id}.cross"
  local steps base_rms n_far
  steps="$(pn_isf_steps "${WORKDIR}/ref.cross" "${WORKDIR}/${run_id}.cross" \
                        "${PN_IMP_TIMES}" "${PN_PLATEAU_FRAC}" "${PN_TSTOP_S}")"
  base_rms="$(echo "${steps}" | awk '$1 == "BASE" { print $3 }')"
  n_far="$(echo "${steps}" | awk '$1 == "GUARD" { print $5 }')"

  : > "${WORKDIR}/${run_id}.gamma"
  local tag k t_imp phi tb ta dtau dphi ripple n_pl gq
  while read -r tag k t_imp phi tb ta dtau dphi ripple n_pl; do
    [[ "${tag}" == "IMP" ]] || continue
    : "${tb}" "${ta}" "${dtau}"
    gq="$(awk -v d="${dphi}" -v q="${dq}" 'BEGIN{ if (d == "nan") print "nan"; else printf "%.8e", d/q }')"
    echo "${port},${idx},${dq},${k},${t_imp},${phi},${dphi},${gq},${ripple},${n_pl}" >> "${ISF_CSV}"
    [[ "${phi}" != "nan" ]] && echo "${phi} ${gq}" >> "${WORKDIR}/${run_id}.gamma"
  done <<<"${steps}"

  local rms_t rms_s c0 c1 c2 c3 maxgap ngam
  read -r rms_t rms_s c0 c1 c2 c3 maxgap ngam <<<"$(pn_gamma_stats "${WORKDIR}/${run_id}.gamma")"

  local si="${SI_TANK}"
  [[ "${port}" == "tail" ]] && si="${SI_TAIL}"
  local l1 l1hl l10 l10hl
  read -r l1 l1hl <<<"$(pn_l_dbc "${rms_t}" "${si}" "1e6")"
  read -r l10 l10hl <<<"$(pn_l_dbc "${rms_t}" "${si}" "10e6")"
  : "${l1hl}" "${l10hl}"

  echo "${port},${idx},${dq},${F0_MEAS},${VPP_MEAS},${rms_t},${rms_s},${c0},${c1},${c2},${c3},${maxgap},${ngam},${base_rms},${n_far},${l1},${l10}" >> "${REAL_CSV}"
  printf "[%s] %4d s wall  dq=%s C  Gq_rms=%s rad/C  L(1MHz)=%s dBc/Hz  (null floor %s s, %s unmatched)\n" \
         "${run_id}" "${twall}" "${dq}" "${rms_t}" "${l1}" "${base_rms}" "${n_far}"
  rm -f "${dat}"
  n_realizations=$((n_realizations + 1))
}

idx=0
for dq in ${PN_TANK_DQ_LIST}; do
  idx=$((idx + 1)); run_realization tank "${idx}" "${dq}"
done
idx=0
for dq in ${PN_TAIL_DQ_LIST}; do
  idx=$((idx + 1)); run_realization tail "${idx}" "${dq}"
done
T_WALL_TOTAL=$(( $(date +%s) - T_WALL_START ))

# ============================================================ reduce
# Mean and SAMPLE standard deviation over the tank-port realisations. This is
# the estimate's variance as this experiment defines it -- see README.md,
# "What the variance here is, and what it is not".
read -r GQ_MEAN GQ_SD GQ_N L1_MEAN L1_SD L1_MIN L1_MAX L10_MEAN L10_SD \
  <<<"$(awk -F, 'NR>1 && $1=="tank" {
      n++; g+=$6; g2+=$6*$6; a+=$16; a2+=$16*$16; b+=$17; b2+=$17*$17
      if (lo=="" || $16+0<lo) lo=$16+0; if (hi=="" || $16+0>hi) hi=$16+0
    }
    END {
      if (n == 0) { print "nan nan 0 nan nan nan nan nan nan"; exit }
      gm=g/n; am=a/n; bm=b/n
      gs=(n>1)?sqrt((g2-n*gm*gm)/(n-1)):0
      as=(n>1)?sqrt((a2-n*am*am)/(n-1)):0
      bs=(n>1)?sqrt((b2-n*bm*bm)/(n-1)):0
      printf "%.6e %.6e %d %.4f %.4f %.4f %.4f %.4f %.4f\n", gm, gs, n, am, as, lo, hi, bm, bs
    }' "${REAL_CSV}")"

GQ_TAIL="$(awk -F, 'NR>1 && $1=="tail" { print $6; exit }' "${REAL_CSV}")"
L1_TAIL="$(awk -F, 'NR>1 && $1=="tail" { print $16; exit }' "${REAL_CSV}")"
PORT_RATIO_DB="$(awk -v a="${GQ_TAIL}" -v b="${GQ_MEAN}" \
  'BEGIN{ if (a=="nan"||b=="nan"||a<=0||b<=0) print "nan"; else printf "%.2f", 20*log(a/b)/log(10) }')"
LINEARITY_PCT="$(awk -F, 'NR>1 && $1=="tank" {
    q=$3+0; if (q<0) q=-q
    if (q < qmin || qmin==0) { }
    key=sprintf("%.4g", q); s[key]+=$6; c[key]++
  }
  END {
    n=0; for (k in s) { n++; m[n]=s[k]/c[k] }
    if (n<2) { print "nan"; exit }
    lo=m[1]; hi=m[1]
    for (i=1;i<=n;i++) { if (m[i]<lo) lo=m[i]; if (m[i]>hi) hi=m[i] }
    printf "%.3f", 100*(hi-lo)/(0.5*(hi+lo))
  }' "${REAL_CSV}")"

read -r IND_BAR_Q_DB IND_BAR_FIT_DB IND_BAR_DB <<<"$(pn_ind_bar_db)"

V1="$(pn_verdict "${L1_MEAN}" "${PN_ROW4_1M_TARGET}" "${PN_ROW4_1M_STRETCH}")"
V10="$(pn_verdict "${L10_MEAN}" "${PN_ROW4_10M_TARGET}" "${PN_ROW4_10M_STRETCH}")"

# ---- the cost of the graded grid, from THIS run's own measured rate --------
RATE_PS_PER_S="$(awk -v t="${T_WALL_REF}" -v ts="${PN_TSTOP_S}" \
                     'BEGIN{ if (t<=0) print "nan"; else printf "%.2f", ts*1e12/t }')"
GRID_HOURS="$(awk -v t="${T_WALL_TOTAL}" -v n="${N_RUNS}" 'BEGIN{ printf "%.0f", 135*t/3600 }')"

{
  echo "f0_measured,${F0_MEAS},Hz,crossing-counted over the reference run"
  echo "vpp_diff,${VPP_MEAS},V,peak-to-peak of v(OUTP)-v(OUTN) over the measurement window"
  echo "si_tank,${SI_TANK},A^2/Hz,input-referred one-sided noise current at the differential tank port"
  echo "si_tail,${SI_TAIL},A^2/Hz,input-referred one-sided noise current at the tail node"
  echo "si_tank_band_spread_pct,${NOISE_FLAT_TANK},%,peak-to-peak over ${PN_NOISE_FSTART}..${PN_NOISE_FSTOP} Hz"
  echo "si_tail_band_spread_pct,${NOISE_FLAT_TAIL},%,peak-to-peak over ${PN_NOISE_FSTART}..${PN_NOISE_FSTOP} Hz"
  echo "gq_rms_tank_mean,${GQ_MEAN},rad/C,mean over ${GQ_N} realisations"
  echo "gq_rms_tank_sd,${GQ_SD},rad/C,sample standard deviation over ${GQ_N} realisations"
  echo "gq_rms_tail,${GQ_TAIL},rad/C,single realisation"
  echo "isf_linearity_spread_pct,${LINEARITY_PCT},%,spread of Gq_rms between the two injected-charge magnitudes"
  echo "l_1mhz_mean,${L1_MEAN},dBc/Hz,mean over the tank-port realisations"
  echo "l_1mhz_sd,${L1_SD},dBc/Hz,sample standard deviation over the tank-port realisations"
  echo "l_1mhz_min,${L1_MIN},dBc/Hz,best realisation"
  echo "l_1mhz_max,${L1_MAX},dBc/Hz,worst realisation"
  echo "l_10mhz_mean,${L10_MEAN},dBc/Hz,mean over the tank-port realisations"
  echo "l_10mhz_sd,${L10_SD},dBc/Hz,sample standard deviation over the tank-port realisations"
  echo "l_1mhz_tail_port,${L1_TAIL},dBc/Hz,the same circuit noise weighted by the TAIL port ISF instead"
  echo "port_isf_ratio_db,${PORT_RATIO_DB},dB,20*log10(Gq_rms tail / Gq_rms tank)"
  echo "inductor_bar_q,${IND_BAR_Q_DB},dB,propagated from the EM model's +-${PN_IND_Q_BAR_PCT}% Q bar"
  echo "inductor_bar_fit,${IND_BAR_FIT_DB},dB,propagated from the EM model's ${PN_IND_FIT_BAR_PCT}% rms fit residual"
  echo "inductor_bar_total,${IND_BAR_DB},dB,the two added in quadrature"
  echo "rate_ps_per_wallclock_s,${RATE_PS_PER_S},ps/s,measured on the reference transient"
  echo "wall_clock_total_s,${T_WALL_TOTAL},s,all ${N_RUNS} transients of this record"
} >> "${SUMMARY_CSV}"

# ------------------------------------------------------------------ record
{
  echo "# Record ${RECORD_ID}"
  echo
  echo "- **Experiment**: phase-noise (ISF pilot -- ONE declared corner)"
  echo "- **Claim**: what \`design/vco.sch\`'s single-sideband phase noise"
  echo "  \`L(df)\` MEASURES at 1 MHz and 10 MHz offsets from a band-centre"
  echo "  carrier, at the nominal process corner and 27 C, by an ISF"
  echo "  (Hajimiri-Lee) derivation -- with the method, its variance across"
  echo "  realisations and its stated limits."
  echo "- **This record grades NO \`spec/target-spec.md\` row.** Row 4 is"
  echo "  stated over the corner set rows 10 and 11 settle (135 PVT points);"
  echo "  this is \`mos_${PILOT_MOS}\` / \`${PILOT_CAP}\` / \`${PILOT_HBT}\` at"
  echo "  ${PILOT_TEMP} C and \`Vctrl\` = ${PN_VCTRL} V only. The numbers below"
  echo "  are findings about the circuit, quoted against the row-4 bounds for"
  echo "  orientation. **Measuring a row is not ratifying it**, and a number"
  echo "  that misses a bound is recorded as a miss -- this experiment does not"
  echo "  edit \`spec/target-spec.md\`."
  echo
  echo "## Method"
  echo
  echo "A phase-noise number without its method is not a result (\`CLAUDE.md\`),"
  echo "so the whole method is restated here rather than cited."
  echo
  echo "- **Why not a spectrum.** ngspice ships neither PSS nor pnoise, and its"
  echo "  transient analysis runs with device noise sources switched off. A"
  echo "  periodogram of this deck's own transient -- or a period-jitter"
  echo "  extraction converted to \`L(df)\` -- would therefore measure the"
  echo "  solver's truncation error, not the circuit's phase noise, at any"
  echo "  transient length. See \`README.md\`, \"Why not a periodogram\"."
  echo "- **Estimator**: the impulse sensitivity function, measured. A"
  echo "  triangular charge impulse of half-width ${PN_IMP_HW} s is injected at"
  echo "  each of ${PN_N_IMP} carrier phases, and the PERMANENT excess-phase"
  echo "  step it produces is read from the shift in the differential tank"
  echo "  voltage's crossing times. Reduced through"
  echo "  \`Gq(phi) = dphi/dq\` [rad/C] and"
  echo "  \`L(df) = Gq_rms^2 * S_i / (2 * (2*pi*df)^2)\`."
  echo "- **q_max is never measured**, deliberately: the unnormalised"
  echo "  \`Gq = Gamma/q_max\` is what the impulse response gives directly, and"
  echo "  \`q_max\` cancels out of the kernel. A \`q_max\` for a tank loaded by"
  echo "  32 varactor instances, two EM-fitted inductor ladders and a MIM would"
  echo "  have carried an error bar larger than the ISF's own."
  echo "- **The kernel's factor of 2 is named, not assumed.** The form above"
  echo "  counts noise folding down from BOTH \`w0+dw\` and \`w0-dw\`;"
  echo "  Hajimiri & Lee 1998 eq. 14 as literally written counts only the"
  echo "  upper sideband and is 3 dB lower. The form used here is the one that"
  echo "  reproduces Leeson's linear-tank kernel exactly for an ideal LC, which"
  echo "  \`run_method_check.sh\` verifies numerically (KA-4) -- and it is the"
  echo "  more pessimistic of the two. Both are printed by \`pn_l_dbc\`."
  echo "- **Transient**: \`tran ${PN_TSTEP} ${PN_TSTOP_S}\`, timestep ceiling"
  echo "  \`${PN_TMAX}\`, startup from the ${OSC_IC_DIFF_MV} mV differential"
  echo "  \`.ic\` (\`v(OUTP)=${OSC_IC_OUTP}\`, \`v(OUTN)=${OSC_IC_OUTN}\`)."
  echo "- **Discarded startup window**: 0 .. ${PN_TMEAS_START} s. Crossings"
  echo "  before it are not compared. The value is"
  echo "  \`sim/oscillator-core\`'s, derived there from a MEASURED"
  echo "  90 %-envelope settling time of 0.487 .. 1.256 ns across its pilot"
  echo "  corners, i.e. 2.0x the slowest observed."
  echo "- **Impulse train**: first impulse at ${PN_IMP_T1} s, spacing"
  echo "  ${PN_IMP_DT} s = (${PN_IMP_NPER} + 1/${PN_N_IMP}) periods at the"
  echo "  declared nominal ${PN_F0_NOM} Hz. The fractional part is what walks"
  echo "  the carrier phase so one run samples the whole ISF; the integer part"
  echo "  is what lets the amplitude transient decay between impulses. The"
  echo "  measured carrier came out ${F0_GRID_ERR_PCT} % from that nominal, and"
  echo "  the resulting phase grid's largest gap is recorded per realisation."
  echo "- **Plateau**: each step is read over the last ${PN_PLATEAU_FRAC} of"
  echo "  the inter-impulse interval, so the amplitude transient is excluded by"
  echo "  construction; the plateau's own ripple is recorded per impulse."
  echo "- **The reference run is this same deck with zero-amplitude impulses**,"
  echo "  so both decks carry an identical PWL breakpoint set and take"
  echo "  identical timesteps until the first non-zero impulse. The"
  echo "  pre-impulse crossing-offset residual is therefore an exact null, and"
  echo "  it is recorded per realisation as \`null_floor_s\` -- this method's"
  echo "  own noise floor, measured rather than asserted."
  echo "- **Crossing threshold**: ONE value, the reference run's trapezoidal"
  echo "  time average over the measurement window, applied to both runs. A"
  echo "  per-run mean would have folded any DC shift the perturbation caused"
  echo "  into the very crossing times being measured."
  echo "- **Port noise** \`S_i\`: ngspice small-signal \`noise\`, unit AC"
  echo "  current probe across the port, port voltage as the output, so"
  echo "  \`inoise_spectrum\` is the port's Norton-equivalent noise current"
  echo "  density. Swept over ${PN_NOISE_FSTART} .. ${PN_NOISE_FSTOP} Hz"
  echo "  (${PN_NOISE_NPTS} points), median taken, band spread recorded."
  echo "- **Estimator validation**: \`run_method_check.sh\`, the same"
  echo "  \`pn_crossings\`/\`pn_isf_steps\`/\`pn_gamma_stats\`/\`pn_l_dbc\`"
  echo "  against synthetic oscillators with closed-form ISF and closed-form"
  echo "  phase noise, with derived tolerances."
  echo
  echo "## Measured"
  echo
  echo "- **Carrier**: \`f_osc\` = ${F0_MEAS} Hz, \`Vpp(VDIFF)\` = ${VPP_MEAS} V"
  echo "  over ${CYCLES_MEAS} counted cycles (largest sample spacing"
  echo "  ${DTMAX_MEAS} s)."
  echo "- **Equivalent port noise**: tank ${SI_TANK} A^2/Hz"
  echo "  (${SI_TANK_SQRT} A/sqrt(Hz), ${NOISE_FLAT_TANK} % peak-to-peak across"
  echo "  the swept band); tail ${SI_TAIL} A^2/Hz (${SI_TAIL_SQRT} A/sqrt(Hz),"
  echo "  ${NOISE_FLAT_TAIL} %)."
  echo "- **ISF at the differential tank port**: \`Gq_rms\` ="
  echo "  ${GQ_MEAN} +- ${GQ_SD} rad/C over ${GQ_N} realisations."
  echo "- **\`L(1 MHz)\` = ${L1_MEAN} +- ${L1_SD} dBc/Hz**"
  echo "  (realisations spanned ${L1_MIN} .. ${L1_MAX} dBc/Hz)."
  echo "  Row-4 bounds ${PN_ROW4_1M_TARGET} target / ${PN_ROW4_1M_STRETCH}"
  echo "  stretch: **${V1}** at this corner."
  echo "- **\`L(10 MHz)\` = ${L10_MEAN} +- ${L10_SD} dBc/Hz**. Row-4 companion"
  echo "  bounds ${PN_ROW4_10M_TARGET} / ${PN_ROW4_10M_STRETCH}: **${V10}** at"
  echo "  this corner. This offset is reported from the same 1/f^2 kernel as"
  echo "  the 1 MHz number, so it is 20 dB below it by construction and is NOT"
  echo "  independent evidence -- see the limits below."
  echo "- **Variance across realisations**: the ensemble is"
  echo "  ${PN_TANK_DQ_LIST} C of injected charge -- both signs (which cancels"
  echo "  any even-order term in the phase response) at two magnitudes (which"
  echo "  is the linearity test the first-order ISF assumption stands on). The"
  echo "  \`Gq_rms\` spread between the two magnitudes was"
  echo "  ${LINEARITY_PCT} %. **This is not a Monte Carlo variance**: this"
  echo "  estimator has no random input. See \`README.md\`, \"What the variance"
  echo "  here is, and what it is not\"."
  echo "- **Non-PDK inductor model, propagated** (\`sim/README.md\` rule 6):"
  echo "  \`sim/inductor-model/sg13g2_inductor_em.spice\` sha256"
  echo "  \`$(sha256_of "${OSC_IND_MODEL}")\`. The PDK ships NO spiral-inductor"
  echo "  ngspice model (\`sim/pdk.json\` \`known_model_gaps.spiral_inductor\`),"
  echo "  so this number is not a PDK-model result. \`design/vco.sch\`"
  echo "  instantiates the \`p11\` geometry, one of the three the EM extraction"
  echo "  actually covered, so its own bars apply rather than an extrapolation:"
  echo "  a +-${PN_IND_Q_BAR_PCT} % bar on the EM-measured Q propagates to at"
  echo "  most +-${IND_BAR_Q_DB} dB on \`L\` (through the tank loss noise), and"
  echo "  the ${PN_IND_FIT_BAR_PCT} % rms lumped-fit residual to at most"
  echo "  +-${IND_BAR_FIT_DB} dB (through the resonating C in \`q_max\`);"
  echo "  **+-${IND_BAR_DB} dB in quadrature**. Two of that model's stated"
  echo "  limits are NOT quantifiable as a dB bar and do not appear in it: the"
  echo "  EM solve was run at one process point and one temperature, and no"
  echo "  measured silicon backs any of it."
  echo
  echo "## Corner coverage, stated honestly"
  echo
  echo "Row 10 enumerates MOS \`{tt,ss,ff,sf,fs}\` x MIM"
  echo "\`{cap_typ,cap_bcs,cap_wcs}\` x HBT \`{hbt_typ,hbt_bcs,hbt_wcs}\`"
  echo "crossed with row 11's \`{-40, +27, +125} C\` = **135 PVT points**. This"
  echo "record measured **1**."
  echo
  echo "This run took ${T_WALL_TOTAL} s of wall clock for ${N_RUNS} transients"
  echo "at one corner (measured rate: ${RATE_PS_PER_S} ps of circuit time per"
  echo "wall-clock second on one core, from the reference transient). The same"
  echo "measurement over the row-10/11 grid is therefore **~${GRID_HOURS}"
  echo "CPU-hours**, and \`klt sim\` cannot route this deck off-host at all"
  echo "(no OSDI device loading, no \`ngbehavior\` selection, no \`ihp-sg13g2\`"
  echo "off-host image -- reproduced in \`sim/oscillator-core/klt-sim/\`, filed"
  echo "as 2AMLogic/klayout-tools#2511). So the graded grid did not run, and"
  echo "this record grades no row rather than presenting one corner as one."
  echo
  echo "## What this does NOT show"
  echo
  echo "- **The noise is taken at the DC operating point, not over the cycle.**"
  echo "  ngspice's \`noise\` is a small-signal analysis about the oscillator's"
  echo "  UNSTABLE EQUILIBRIUM, where each device of the cross-coupled pair"
  echo "  carries half the tail current continuously. The running oscillator's"
  echo "  noise sources are cyclostationary. This is the single largest stated"
  echo "  limit on the number above, it is not corrected here, and its sign"
  echo "  depends on how hard the pair switches."
  echo "- **All circuit noise is referred to the tank port.** The primary"
  echo "  number weights the whole Norton-equivalent noise by the TANK port's"
  echo "  ISF. Noise physically originating in the tail branch should be"
  echo "  weighted by the tail port's ISF instead, which measured"
  echo "  ${PORT_RATIO_DB} dB different (\`Gq_rms\` tail ${GQ_TAIL} vs tank"
  echo "  ${GQ_MEAN} rad/C); referring the tail port's own noise through its"
  echo "  own ISF gives ${L1_TAIL} dBc/Hz. That is an indicator of how much the"
  echo "  assumption could matter, not a correction and not a rigorous bound."
  echo "- **Only the 1/f^2 region.** The kernel used is the white-noise one."
  echo "  The 1/f^3 corner -- which is set by the ISF's DC coefficient c0"
  echo "  acting on device flicker noise -- is not evaluated, so neither offset"
  echo "  above is evidence about close-in noise, and the 10 MHz number is 20 dB"
  echo "  below the 1 MHz one by construction rather than by measurement."
  echo "- **No AM-to-PM conversion**, no supply or substrate noise path, and no"
  echo "  noise from anything outside the netlist."
  echo "- **One corner**, as stated above. Whether the tank's loss, the pair's"
  echo "  noise or the varactor bank's Q move this number at"
  echo "  \`mos_ss\`/\`cap_wcs\`/\`hbt_wcs\` or at -40/+125 C is unmeasured."
  echo
  echo "## Provenance"
  echo
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
  echo "  \`$(sha256_of "${OSC_VCO_BODY}")\` -- derived by"
  echo "  \`sim/oscillator-core/osc_bench.sh\`'s \`osc_derive_body\`, the same"
  echo "  code path that experiment's own records were produced through."
  echo "- **ngspice**: \`${OSC_NGSPICE_VERSION}\`"
  echo "- **Links**:"
  echo "  - Templates: \`testbench/tb_vco_isf_impulse.spice.tmpl\`,"
  echo "    \`testbench/tb_vco_port_noise.spice.tmpl\`"
  echo "  - Per-run generated netlists: \`netlist-snapshots/${RECORD_ID}/\`"
  echo "  - Per-run raw ngspice logs: \`corners/${RECORD_ID}/\`"
  echo "  - Measured ISF, per impulse: \`records/${RECORD_ID}-pilot-isf.csv\`"
  echo "  - Per-realisation scalars: \`records/${RECORD_ID}-pilot-realizations.csv\`"
  echo "  - Port-noise spectra: \`records/${RECORD_ID}-pilot-portnoise.csv\`"
  echo "  - Scalar summary: \`records/${RECORD_ID}-pilot-summary.csv\`"
  echo "- **Reproduce**: \`sim/phase-noise/run_isf_pilot.sh\` (no arguments)"
  echo "  against the pinned PDK."
  echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MD_OUT}"

echo
echo "---------------------------------------------------------------"
echo "record          : ${RECORD_ID}   (ISF PILOT -- grades no spec row)"
echo "carrier         : ${F0_MEAS} Hz, Vpp_diff ${VPP_MEAS} V"
echo "S_i tank        : ${SI_TANK} A^2/Hz (${NOISE_FLAT_TANK} % spread over the band)"
echo "Gq_rms tank     : ${GQ_MEAN} +- ${GQ_SD} rad/C over ${GQ_N} realisations"
echo "L(1 MHz)        : ${L1_MEAN} +- ${L1_SD} dBc/Hz   -> ${V1}"
echo "L(10 MHz)       : ${L10_MEAN} +- ${L10_SD} dBc/Hz  -> ${V10}"
echo "inductor bar    : +-${IND_BAR_DB} dB (non-PDK model, sim/README.md rule 6)"
echo "graded grid     : ~${GRID_HOURS} CPU-hours for the 135 row-10/11 points -- NOT RUN"
echo "written         : ${MD_OUT#"${REPO_ROOT}"/}"
echo "---------------------------------------------------------------"

# A number that misses a row bound is a RESULT, not a failure: this script
# grades no row and must not exit non-zero for one. Only a broken measurement
# is an error.
if [[ "${GQ_N}" == "0" ]]; then
  echo "error: no realisation produced an ISF." >&2
  exit 1
fi
