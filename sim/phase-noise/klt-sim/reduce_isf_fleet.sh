#!/usr/bin/env bash
# Reduce the fleet-run ISF pilot inputs (issue #94) with the SAME estimator functions
# run_isf_pilot.sh uses (sim/lib.sh pn_* and sim/oscillator-core/osc_bench.sh), so the only
# thing that changed versus the pre-#79 pilot is where the SPICE ran, not how it is read.
#
#   reduce_isf_fleet.sh [options] <traces-dir (index.tsv + .dat)> <noise-tank in> <noise-tail in> <record-id> [f0_nom]
#
# Writes <outdir>/<id>-pilot-{isf,realizations,portnoise,summary}.csv (<outdir> defaults to
# sim/phase-noise/records). Exits non-zero, publishing nothing, on any invalid trace /
# incomplete ensemble / unresolvable port-noise value, exactly as run_isf_pilot.sh does
# (issue #137, #157).
#
# ONE CORNER PER INVOCATION. Everything that identifies the corner is an option, so the
# 135-corner grid driver (klt-sim/reduce_pn_grid.sh, issue #329) can drive this file 135
# times without every summary claiming to be tt_typ_typ at 27 C -- which is what the
# hardcoded preamble used to say, and what the grader would have seen as one corner
# repeated 135 times. The four positionals and the optional fifth keep their pre-#329
# meaning, so the invocation cited in record 20261105-200000-6834172 still runs and still
# produces that record's numbers byte for byte.
#
#   --process <mos_cap_hbt>  corner process bundle for the summary preamble (default tt_typ_typ)
#   --temp <C>               corner temperature for the summary preamble (default 27)
#   --nper <N>               integer part of the impulse spacing in carrier periods. MUST equal
#                            the --nper the deck was GENERATED at (gen_isf_request.py): the
#                            impulse instants are baked into the PWL sources, and this is what
#                            rebuilds the schedule they are read against. Default PN_IMP_NPER
#                            (3, the pilot's); the graded grid generates at 9.
#   --outdir <dir>           where the four CSVs go (default sim/phase-noise/records). The
#                            append-only refusal applies to the records dir only -- a run's own
#                            OUTDIR is scratch, so re-reducing a corner there overwrites.
#   --f0 <Hz>                same as the fifth positional (the grid-design carrier).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENT_DIR="$(cd "${HERE}/.." && pwd)"; SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
# shellcheck source=../../lib.sh
source "${SIM_DIR}/lib.sh"
# shellcheck source=../../oscillator-core/osc_bench.sh
source "${SIM_DIR}/oscillator-core/osc_bench.sh"
# shellcheck source=../pn_bench.sh
source "${EXPERIMENT_DIR}/pn_bench.sh"

usage() { sed -n '6,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

ARG_PROCESS="tt_typ_typ"; ARG_TEMP="27"; ARG_NPER="${PN_IMP_NPER}"; ARG_OUTDIR=""; ARG_F0=""
NPOS=0; P1=""; P2=""; P3=""; P4=""; P5=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --process) ARG_PROCESS="${2:?--process needs a value}"; shift 2 ;;
    --temp)    ARG_TEMP="${2:?--temp needs a value}"; shift 2 ;;
    --nper)    ARG_NPER="${2:?--nper needs a value}"; shift 2 ;;
    --outdir)  ARG_OUTDIR="${2:?--outdir needs a value}"; shift 2 ;;
    --f0)      ARG_F0="${2:?--f0 needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*)       echo "error: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    *) NPOS=$((NPOS + 1))
       case "${NPOS}" in
         1) P1="$1" ;; 2) P2="$1" ;; 3) P3="$1" ;; 4) P4="$1" ;; 5) P5="$1" ;;
         *) echo "error: too many positional arguments (got '$1')" >&2; exit 2 ;;
       esac; shift ;;
  esac
done
[[ "${NPOS}" -ge 4 ]] || { echo "error: need 4 positional arguments" >&2; usage >&2; exit 2; }
TR="${P1}"; NTANK="${P2}"; NTAIL="${P3}"; ID="${P4}"
# grid-design carrier (must equal the --f0 given to gen_isf_request.py); default = pn_bench.sh value
PN_F0_NOM="${ARG_F0:-${P5:-${PN_F0_NOM}}}"
PN_IMP_NPER="${ARG_NPER}"

# Corner identity. The summary preamble used to hardcode tt / cap_typ / hbt_typ / 27 C;
# it is now this corner's own, because the grader keys its rows on (process, temp_c).
case "${ARG_PROCESS}" in
  *_*_*) MOS_SEC="${ARG_PROCESS%%_*}"
         CAP_SEC="${ARG_PROCESS#*_}"; CAP_SEC="${CAP_SEC%%_*}"
         HBT_SEC="${ARG_PROCESS##*_}" ;;
  *) echo "error: --process '${ARG_PROCESS}' is not <mos>_<cap>_<hbt>" >&2; exit 2 ;;
esac

RECORDS_DIR="${EXPERIMENT_DIR}/records"
OUT_DIR="${ARG_OUTDIR:-${RECORDS_DIR}}"
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"
OUT="${OUT_DIR}/${ID}"
ISF_CSV="${OUT}-pilot-isf.csv"; REAL_CSV="${OUT}-pilot-realizations.csv"
NOISE_CSV="${OUT}-pilot-portnoise.csv"; SUMMARY_CSV="${OUT}-pilot-summary.csv"
# Append-only applies to the committed evidence dir, never to a run's scratch OUTDIR --
# re-reducing one corner of a grid must not be a hard abort (issue #329).
if [[ "${OUT_DIR}" == "${RECORDS_DIR}" ]]; then
  [[ ! -e "${SUMMARY_CSV}" ]] || { echo "error: ${SUMMARY_CSV} exists (records are append-only)" >&2; exit 1; }
fi
W="$(mktemp -d /tmp/isf-reduce.XXXXXX)"

PN_IMP_DT="$(awk -v f="${PN_F0_NOM}" -v n="${PN_IMP_NPER}" -v m="${PN_N_IMP}" 'BEGIN{ printf "%.12e", (n + 1.0/m)/f }')"
PN_IMP_TIMES="$(pn_imp_times "${PN_IMP_T1}" "${PN_IMP_DT}" "${PN_N_IMP}")"
PN_TSTOP_S="$(awk -v t1="${PN_IMP_T1}" -v dt="${PN_IMP_DT}" -v m="${PN_N_IMP}" 'BEGIN{ printf "%.12e", t1 + m*dt }')"

echo "port,realization,dq_c,impulse,t_imp_s,phi_rad,dphi_rad,gq_rad_per_C,plateau_ripple_s,n_plateau" > "${ISF_CSV}"
echo "port,realization,dq_c,f0_hz,vpp_diff_v,gq_rms_trapz,gq_rms_sample,c0,c1,c2,c3,max_phase_gap_rad,n_phases,null_floor_s,n_crossings_unmatched,l_1mhz_dbc,l_10mhz_dbc" > "${REAL_CSV}"
echo "port,freq_hz,inoise_a_per_sqrt_hz" > "${NOISE_CSV}"
echo "quantity,value,unit,note" > "${SUMMARY_CSV}"

# ---- port noise: the PN_NOISE_NPTS inoise_spectrum points the fleet returned
# The k-th frequency of the declared linear sweep, derived from the band constants rather
# than re-hardcoded as "3+k GHz" (it has to agree with the deck gen_isf_request.py wrote).
freq_k() {
  awk -v a="${PN_NOISE_FSTART}" -v b="${PN_NOISE_FSTOP}" -v n="${PN_NOISE_NPTS}" -v k="$1" \
    'BEGIN { printf "%.6e", (n > 1) ? a + (b - a) * k / (n - 1) : a }'
}
# noise_points <file> -> one "<freq_hz> <inoise>" line per declared point.
noise_points() {
  local f="$1" t k v
  [[ -f "${f}" ]] || { echo "error: port-noise input ${f} does not exist" >&2; return 1; }
  # (a) an ngspice `print inoise_spectrum` table -- the local bench's own output, read with
  #     the lib's existing parser rather than a second one.
  t="$(pn_inoise_table "${f}")"
  if [[ -n "${t}" ]]; then printf '%s\n' "${t}"; return 0; fi
  # (b) a bare "<freq> <inoise>" table: THIS corner's own points, as extract_inoise.py pulls
  #     them per corner out of a multi-corner job's report.json.
  if awk 'NF == 0 { next } NF != 2 { bad = 1 } { n++ } END { exit (bad || n == 0) ? 1 : 0 }' "${f}"; then
    awk 'NF == 2 { print $1, $2 }' "${f}"; return 0
  fi
  # (c) a klt-sim submit.stdout. Its "worst=" is a per-measurement extremum ACROSS the job's
  #     corners, so this path is correct ONLY for a single-corner job -- which is what the
  #     pre-#329 pilot submitted, and why it is kept. The 135-corner grid puts every corner
  #     in ONE noise job per port, so it must come in through (a) or (b) instead (issue #329).
  for k in $(seq 0 $((PN_NOISE_NPTS - 1))); do
    v="$(sed -n "s/^ *inoise_${k} \[pass\] *worst=\([^ ]*\).*/\1/p" "${f}")"
    [[ -n "${v}" ]] || { echo "error: no inoise_${k} in ${f}" >&2; return 1; }
    echo "$(freq_k "${k}") ${v}"
  done
}
for port in tank tail; do
  f="${NTANK}"; [[ "${port}" == "tail" ]] && f="${NTAIL}"
  PTS="$(noise_points "${f}")" || { echo "error: ${port}-port noise unresolved from ${f}" >&2; exit 1; }
  NPTS_GOT="$(printf '%s\n' "${PTS}" | grep -c '[^[:space:]]' || true)"
  [[ "${NPTS_GOT}" -eq "${PN_NOISE_NPTS}" ]] || {
    echo "error: ${port}-port noise: ${NPTS_GOT} point(s) in ${f}, need ${PN_NOISE_NPTS}" >&2; exit 1; }
  printf '%s\n' "${PTS}" | awk -v p="${port}" 'NF == 2 { print p "," $1 "," $2 }' >> "${NOISE_CSV}"
done
med() { awk -F, -v p="$1" "${PN_AWK_FINITE}"'$1==p && NR>1 { if (!pn_fin($3) || $3+0<=0) bad++; n++; v[n]=$3+0 }
  END { if (n==0||bad>0) { print "nan"; exit }
    for(i=1;i<=n;i++)for(j=i+1;j<=n;j++)if(v[j]<v[i]){t=v[i];v[i]=v[j];v[j]=t}
    printf "%.8e\n", (n%2)?v[(n+1)/2]:0.5*(v[n/2]+v[n/2+1]) }' "${NOISE_CSV}"; }
spread() { awk -F, -v p="$1" '$1==p && NR>1 { n++; if (lo==""||$3+0<lo) lo=$3+0; if ($3+0>hi) hi=$3+0 }
  END { if (n<2) print "nan"; else printf "%.3f", 100*(hi-lo)/(0.5*(hi+lo)) }' "${NOISE_CSV}"; }
SI_TANK_SQRT="$(med tank)"; SI_TAIL_SQRT="$(med tail)"
# A non-finite median is the "missing port-noise value" failure mode: it would otherwise
# reach pn_l_dbc and come back as a nan L, i.e. a corner with no number and no cause.
for q in "tank ${SI_TANK_SQRT}" "tail ${SI_TAIL_SQRT}"; do
  set -- ${q}
  pn_is_finite "$2" || { echo "error: $1-port noise median is '$2' (a malformed, non-finite or non-positive point in the ${PN_NOISE_NPTS}-point band); no summary published" >&2; exit 1; }
done
SI_TANK="$(awk -v s="${SI_TANK_SQRT}" 'BEGIN{ printf "%.8e", s*s }')"
SI_TAIL="$(awk -v s="${SI_TAIL_SQRT}" 'BEGIN{ printf "%.8e", s*s }')"
NOISE_FLAT_TANK="$(spread tank)"; NOISE_FLAT_TAIL="$(spread tail)"
echo "[pnoise] tank median ${SI_TANK_SQRT} A/sqrt(Hz), tail ${SI_TAIL_SQRT}"

dat() { echo "${TR}/dqd_${1}_dqt_${2}.dat"; }
REF="$(dat 0 0)"
pn_require_valid_trace ref "${REF}" "${PN_TMEAS_START}" "${PN_TSTOP_S}"
THR="$(pn_window_mean "${REF}" "${PN_TMEAS_START}" "${PN_TSTOP_S}")"
pn_crossings "${REF}" "${PN_TMEAS_START}" "${PN_TSTOP_S}" "${THR}" > "${W}/ref.cross"
read -r F0_MEAS VPP_MEAS CYCLES_MEAS _a _b _c _d _e <<<"$(osc_metrics "${REF}" "${PN_TMEAS_START}" "${PN_TSTOP_S}")"
echo "[ref] f_osc = ${F0_MEAS} Hz, Vpp_diff = ${VPP_MEAS} V, ${CYCLES_MEAS} cycles"
# osc_metrics reports f_osc = 0 for "fewer than 3 crossings in the window", i.e. a valid
# trace that did not oscillate (sim/README.md rule 4). Say so here rather than letting it
# surface as an unexplained empty ensemble several hundred lines later.
awk -v f="${F0_MEAS}" "${PN_AWK_FINITE}"'BEGIN{ exit (pn_fin(f) && f+0 > 0) ? 0 : 1 }' || {
  echo "error: reference trace ${REF} did not oscillate over ${PN_TMEAS_START}..${PN_TSTOP_S} s (f_osc = ${F0_MEAS} Hz); no summary published" >&2; exit 1; }
F0_GRID_ERR_PCT="$(awk -v a="${F0_MEAS}" -v b="${PN_F0_NOM}" 'BEGIN{ printf "%.4f", 100*(a/b - 1) }')"

run_realization() {
  local port="$1" idx="$2" dq="$3" dat_f="$4" run_id="${1}_r${2}"
  pn_require_valid_trace "${run_id}" "${dat_f}" "${PN_TMEAS_START}" "${PN_TSTOP_S}"
  pn_crossings "${dat_f}" "${PN_TMEAS_START}" "${PN_TSTOP_S}" "${THR}" > "${W}/${run_id}.cross"
  local steps base_rms n_far
  steps="$(pn_isf_steps "${W}/ref.cross" "${W}/${run_id}.cross" "${PN_IMP_TIMES}" "${PN_PLATEAU_FRAC}" "${PN_TSTOP_S}")"
  base_rms="$(echo "${steps}" | awk '$1 == "BASE" { print $3 }')"
  n_far="$(echo "${steps}" | awk '$1 == "GUARD" { print $5 }')"
  : > "${W}/${run_id}.gamma"
  local tag k t_imp phi tb ta dtau dphi ripple n_pl gq
  while read -r tag k t_imp phi tb ta dtau dphi ripple n_pl; do
    [[ "${tag}" == "IMP" ]] || continue
    : "${tb}" "${ta}" "${dtau}"
    gq="$(awk -v d="${dphi}" -v q="${dq}" "${PN_AWK_FINITE}"' BEGIN{ if (!pn_fin(d) || !pn_fin(q) || q + 0 == 0) print "nan"; else printf "%.8e", d/q }')"
    echo "${port},${idx},${dq},${k},${t_imp},${phi},${dphi},${gq},${ripple},${n_pl}" >> "${ISF_CSV}"
    if pn_is_finite "${phi}" && pn_is_finite "${gq}"; then echo "${phi} ${gq}" >> "${W}/${run_id}.gamma"; fi
  done <<<"${steps}"
  local rms_t rms_s c0 c1 c2 c3 maxgap ngam si l1 l1hl l10 l10hl
  read -r rms_t rms_s c0 c1 c2 c3 maxgap ngam <<<"$(pn_gamma_stats "${W}/${run_id}.gamma")"
  si="${SI_TANK}"; [[ "${port}" == "tail" ]] && si="${SI_TAIL}"
  read -r l1 l1hl <<<"$(pn_l_dbc "${rms_t}" "${si}" "1e6")"
  read -r l10 l10hl <<<"$(pn_l_dbc "${rms_t}" "${si}" "10e6")"
  : "${l1hl}" "${l10hl}"
  echo "${port},${idx},${dq},${F0_MEAS},${VPP_MEAS},${rms_t},${rms_s},${c0},${c1},${c2},${c3},${maxgap},${ngam},${base_rms},${n_far},${l1},${l10}" >> "${REAL_CSV}"
  printf "[%s] dq=%s C  Gq_rms=%s rad/C  L(1MHz)=%s dBc/Hz  (null floor %s s, %s unmatched)\n" "${run_id}" "${dq}" "${rms_t}" "${l1}" "${base_rms}" "${n_far}"
}
idx=0; for dq in ${PN_TANK_DQ_LIST}; do idx=$((idx+1)); run_realization tank "${idx}" "${dq}" "$(dat "${dq}" 0)"; done
idx=0; for dq in ${PN_TAIL_DQ_LIST}; do idx=$((idx+1)); run_realization tail "${idx}" "${dq}" "$(dat 0 "${dq}")"; done

if ! REDUCED="$(pn_reduce_ensemble "${REAL_CSV}" "$(echo "${PN_TANK_DQ_LIST}" | wc -w | tr -d ' ')" "$(echo "${PN_TAIL_DQ_LIST}" | wc -w | tr -d ' ')" "${PN_N_IMP}")"; then
  echo "error: ensemble incomplete or non-finite; no summary published" >&2; exit 1; fi
read -r GQ_MEAN GQ_SD GQ_N L1_MEAN L1_SD L1_MIN L1_MAX L10_MEAN L10_SD <<<"${REDUCED}"
GQ_TAIL="$(awk -F, 'NR>1 && $1=="tail" { print $6; exit }' "${REAL_CSV}")"
L1_TAIL="$(awk -F, 'NR>1 && $1=="tail" { print $16; exit }' "${REAL_CSV}")"
PORT_RATIO_DB="$(awk -v a="${GQ_TAIL}" -v b="${GQ_MEAN}" 'BEGIN{ if (a=="nan"||b=="nan"||a<=0||b<=0) print "nan"; else printf "%.2f", 20*log(a/b)/log(10) }')"
LINEARITY_PCT="$(awk -F, 'NR>1 && $1=="tank" { q=$3+0; if (q<0) q=-q; key=sprintf("%.4g", q); s[key]+=$6; c[key]++ }
  END { n=0; for (k in s) { n++; m[n]=s[k]/c[k] } if (n<2) { print "nan"; exit }
    lo=m[1]; hi=m[1]; for (i=1;i<=n;i++) { if (m[i]<lo) lo=m[i]; if (m[i]>hi) hi=m[i] }
    printf "%.3f", 100*(hi-lo)/(0.5*(hi+lo)) }' "${REAL_CSV}")"
read -r IND_BAR_Q_DB IND_BAR_FIT_DB IND_BAR_DB <<<"$(pn_ind_bar_db)"
{
  echo "mos,${MOS_SEC},,process model section"; echo "cap,cap_${CAP_SEC},,process model section"; echo "hbt,hbt_${HBT_SEC},,process model section"
  echo "temp_c,${ARG_TEMP},C,simulation temperature"; echo "vctrl_v,${PN_VCTRL},V,control voltage"; echo "vsup_v,3.3,V,supply rail simulated"
  echo "imp_nper,${PN_IMP_NPER},periods,integer part of the impulse spacing the deck was generated at"
  echo "f0_nominal,${PN_F0_NOM},Hz,the carrier the impulse spacing was designed around (grid-design parameter)"
  echo "f0_measured,${F0_MEAS},Hz,crossing-counted over the reference run"
  echo "vpp_diff,${VPP_MEAS},V,peak-to-peak of v(OUTP)-v(OUTN) over the measurement window"
  echo "f0_grid_error_pct,${F0_GRID_ERR_PCT},%,measured carrier vs the nominal the impulse spacing was designed around"
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
  echo "l_1mhz_min,${L1_MIN},dBc/Hz,best realisation"; echo "l_1mhz_max,${L1_MAX},dBc/Hz,worst realisation"
  echo "l_10mhz_mean,${L10_MEAN},dBc/Hz,mean over the tank-port realisations"
  echo "l_10mhz_sd,${L10_SD},dBc/Hz,sample standard deviation over the tank-port realisations"
  echo "l_1mhz_tail_port,${L1_TAIL},dBc/Hz,the same circuit noise weighted by the TAIL port ISF instead"
  echo "port_isf_ratio_db,${PORT_RATIO_DB},dB,20*log10(Gq_rms tail / Gq_rms tank)"
  echo "inductor_bar_q,${IND_BAR_Q_DB},dB,propagated from the EM model's +-${PN_IND_Q_BAR_PCT}% Q bar"
  echo "inductor_bar_fit,${IND_BAR_FIT_DB},dB,propagated from the EM model's ${PN_IND_FIT_BAR_PCT}% rms fit residual"
  echo "inductor_bar_total,${IND_BAR_DB},dB,the two added in quadrature"
} >> "${SUMMARY_CSV}"
echo "wrote ${SUMMARY_CSV}"
echo "verdict 1 MHz (row-4 orientation only): $(pn_verdict "${L1_MEAN}" "${PN_ROW4_1M_TARGET}" "${PN_ROW4_1M_STRETCH}")"
echo "verdict 10 MHz (row-4 orientation only): $(pn_verdict "${L10_MEAN}" "${PN_ROW4_10M_TARGET}" "${PN_ROW4_10M_STRETCH}")"
rm -rf "${W}"
