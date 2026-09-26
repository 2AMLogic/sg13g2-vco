#!/usr/bin/env bash
# Cold-start invocation (this is the whole thing):
#
#   sim/phase-noise/run_method_check.sh
#
# WHAT THIS IS
# ------------
# The known-answer check of the ESTIMATOR this experiment produces every
# phase-noise number with. It never touches design/vco.sch: it runs
# sim/lib.sh's pn_crossings / pn_isf_steps / pn_gamma_stats / pn_l_dbc over
# synthetic oscillators whose impulse sensitivity function and whose
# phase noise are known in CLOSED FORM, and records the error against each
# closed form.
#
# It exists because a broken phase-noise estimator does not announce itself.
# A wrong sign in the excess-phase step, a plateau read before the amplitude
# transient decayed, a factor of two in the kernel, an ISF sampled too coarsely
# to resolve its harmonics -- every one of those produces a perfectly
# plausible-looking L(df) in dBc/Hz. CLAUDE.md's "numbers without methods are
# not results" is exactly a rule about this failure, so the method is measured
# against algebra rather than trusted. The other four sim/ studies each ship
# one of these; this is sim/phase-noise's.
#
# THE FOUR CHECKS
#   KA-1  isf_highq     ISF shape and Gq_rms of a high-Q limit-cycle LC
#                       oscillator against the closed form Gq(phi) =
#                       cos(phi)/(C*A). Includes the FALSIFICATION case:
#                       at phi = pi/2 and 3*pi/2 the ISF is exactly zero, i.e.
#                       an injected charge that is purely an amplitude
#                       perturbation must produce NO phase shift. An estimator
#                       that reported a phase shift there would be reporting
#                       amplitude noise as phase noise.
#   KA-2  isf_fastamp   the same closed form on an oscillator whose amplitude
#                       relaxation is as fast as design/vco.sch's, so the
#                       plateau extraction is under stress. Looser DERIVED
#                       tolerance, because the closed form itself is only
#                       good to O(eps) and eps is large here.
#   KA-3  portnoise     ngspice's input-referred `noise` output against
#                       sqrt(4kT/R) on a bare R||C port -- the second measured
#                       input to the kernel.
#   KA-4  kernel        the WHOLE pipeline end to end: the measured Gq_rms from
#                       KA-1 and the measured port noise from the SAME deck,
#                       pushed through pn_l_dbc, against the closed-form
#                       Leeson kernel kTG/(C^2 A^2 dw^2) for that tank --
#                       which is derived independently of the ISF formalism,
#                       so an agreement is not circular.
#
# THE TOLERANCES ARE DERIVED, NOT CHOSEN
# Each is a closed-form bound on a named error term, times a stated x1.5
# headroom, and each row names its terms in a `tol_basis` column:
#
#   eps  = (Gn-G)/(w0*C)   the closed form Gq = cos(phi)/(C*A) is exact only
#                          for a vanishingly weak nonlinearity; a real limit
#                          cycle deviates at first order in eps
#   interp                 (w0*dt^2/8) / dtau_char -- linear interpolation of
#                          a crossing time, relative to the crossing-time step
#                          the impulse actually produces
#   2nd order              dq/(2*q_max) -- the ISF is the FIRST-order phase
#                          response; a finite impulse carries a second-order
#                          term
#   width                  (pi*w/T0)^2/6 -- a triangular impulse of full width
#                          w is not a delta; this is its attenuation of the
#                          ISF fundamental
#
# Requires: ngspice and awk on PATH, and bash. Deliberately NO PDK install, no
# model library and no OSDI build -- the decks use only ngspice-native L/C/R
# and behavioural sources, so a failing estimator can never be confused with a
# PDK or toolchain problem. Same no-PDK property
# sim/oscillator-core/run_method_check.sh and
# sim/inductor-model/run_model_check.sh have, and the reason sim/lib.sh must
# never gain a PDK dependency.
#
# Everything it writes is APPEND-ONLY evidence under this directory, keyed by a
# record ID minted fresh on every run (sim/README.md):
#
#   netlist-snapshots/<record-id>/<case-id>.spice   exact deck simulated
#   corners/<record-id>/<case-id>.log               raw ngspice batch output
#   records/<record-id>-method-check.csv            one row per checked quantity
#   records/<record-id>-method-isf.csv              the measured ISF, per phase
#   records/<record-id>.md                          the narrative record
set -euo pipefail

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SIM_DIR}/.." && pwd)"

# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"
# Deliberately does NOT source pn_bench.sh: that file resolves the PDK, and
# this check must keep its no-PDK-install cold start (see the header, and
# sim/lib.sh's own header for why lib.sh must never gain a PDK dependency).
# Everything this script shares with the measured run lives in sim/lib.sh, so
# the two exercise the same code rather than two copies of it.

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
CHECK_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-method-check.csv"
ISF_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-method-isf.csv"
MD_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.md"
mkdir -p "${NETLIST_DIR}" "${LOG_DIR}" "${EXPERIMENT_DIR}/records"

make_scratch_workdir "sg13g2-pn-method"

# --------------------------------------------------------------- the decks
# Both synthetic oscillators are the same L-C resonator; they differ only in
# how hard the negative-conductance element is driven, i.e. in how fast the
# amplitude relaxes and therefore in how far the closed form is from exact.
KA_LT="1e-9"
KA_CT="1e-12"
KA_A="1.0"          # target limit-cycle amplitude, V (also the .ic)
KA_TSTEP="0.5p"
KA_TMAX="0.5p"
KA_IMP_HW="2e-12"   # triangular impulse half-width: q = amp * hw
KA_DQ="1e-14"       # 10 fC, i.e. dq/q_max = 0.01 at q_max = C*A = 1 pC
KA_NIMP="12"
KA_PLATEAU_FRAC="0.3"
KA_OFFSET_HZ="1e6"

# f0 of the bare resonator, the value the impulse spacing is designed around.
KA_F0="$(awk -v l="${KA_LT}" -v c="${KA_CT}" 'BEGIN{ PI=4*atan2(1,1); printf "%.10e", 1/(2*PI*sqrt(l*c)) }')"
KA_T0="$(awk -v f="${KA_F0}" 'BEGIN{ printf "%.10e", 1/f }')"

# A lossless resonator is NOT used as a case here, deliberately. It would give
# an exactly closed-form ISF, but it has no limit cycle: each impulse's
# amplitude component is never restored, so an impulse TRAIN walks q_max = C*A
# as it goes and the closed form it is being checked against drifts underneath
# the measurement. Both cases below are genuine limit cycles, so the amplitude
# self-restores and q_max is the same for every impulse in the train.

# case          RLOSS   GNEG     spacing (periods)  baseline (periods)
#   isf_highq   10k     7e-4     34                 20
#   isf_fastamp 10k     4.1e-3   6                  20
# GNEG - G sets both the amplitude relaxation time constant tau = C/(Gn-G) and
# the nonlinearity strength eps = (Gn-G)/(w0*C); BNL is then fixed by the
# describing-function balance A = sqrt((Gn-G)/(0.75*Bn)) at the target A.
KA_CASES="isf_highq isf_fastamp"

ka_case_param() {
  # ka_case_param <case> <field>;  fields: rloss gneg nper nbase
  awk -v c="$1" -v f="$2" 'BEGIN {
    if (c == "isf_highq")   { rloss="1e4"; gneg="7e-4";   nper="34"; nbase="20" }
    if (c == "isf_fastamp") { rloss="1e4"; gneg="4.1e-3"; nper="6";  nbase="20" }
    if (f == "rloss") print rloss; else if (f == "gneg") print gneg;
    else if (f == "nper") print nper; else print nbase
  }'
}

echo "case,quantity,detail,simulated,closed_form,abs_err,rel_err_pct,tol,tol_unit,tol_basis,status" > "${CHECK_CSV}"
echo "case,impulse,t_imp_s,phi_rad,dphi_rad,gq_measured_rad_per_C,gq_closed_form_rad_per_C,abs_err_rad_per_C,plateau_ripple_s,n_plateau" > "${ISF_CSV}"

total=0
passed=0
failed_rows=()

# check_row <case> <quantity> <detail> <sim> <ref> <tol> <tol_unit> <tol_basis>
# tol_unit is "pct" (relative) or "abs" (in the quantity's own unit) or "dB".
check_row() {
  local case_id="$1" qty="$2" detail="$3" sim="$4" ref="$5" tol="$6" unit="$7" basis="$8"
  local out abs_err rel_err status
  out="$(awk -v s="${sim}" -v r="${ref}" -v tol="${tol}" -v u="${unit}" 'BEGIN {
    if (s == "" || s == "nan") { print "nan,nan,FAIL"; exit }
    ae = s - r; if (ae < 0) ae = -ae
    re = (r != 0) ? 100.0*(s - r)/r : 0
    are = (re < 0) ? -re : re
    ok = (u == "pct") ? (r != 0 && are <= tol) : (ae <= tol)
    printf "%.6e,%s,%s\n", ae, (r != 0 ? sprintf("%+.6g", re) : "nan"), (ok ? "PASS" : "FAIL")
  }')"
  IFS=, read -r abs_err rel_err status <<<"${out}"
  echo "${case_id},${qty},${detail},${sim},${ref},${abs_err},${rel_err},${tol},${unit},${basis},${status}" >> "${CHECK_CSV}"
  total=$((total + 1))
  if [[ "${status}" == "PASS" ]]; then passed=$((passed + 1)); else failed_rows+=("${case_id}/${qty}/${detail}"); fi
}

# ============================================================ KA-1 and KA-2
KERNEL_CASE="isf_highq"
KERNEL_GQ_RMS="nan"; KERNEL_SI="nan"; KERNEL_A="nan"; KERNEL_G="nan"
KA_EPS_REPORT=""
for case_id in ${KA_CASES}; do
  rloss="$(ka_case_param "${case_id}" rloss)"
  gneg="$(ka_case_param "${case_id}" gneg)"
  nper="$(ka_case_param "${case_id}" nper)"
  nbase="$(ka_case_param "${case_id}" nbase)"

  # describing-function balance: A^2 = (Gn - G)/(0.75*Bn)  =>  Bn = (Gn-G)/(0.75*A^2)
  bnl="$(awk -v gn="${gneg}" -v r="${rloss}" -v a="${KA_A}" 'BEGIN{ printf "%.10e", (gn - 1/r)/(0.75*a*a) }')"
  eps="$(awk -v gn="${gneg}" -v r="${rloss}" -v c="${KA_CT}" -v f="${KA_F0}" \
             'BEGIN{ PI=4*atan2(1,1); printf "%.6e", (gn - 1/r)/(2*PI*f*c) }')"
  KA_EPS_REPORT="${KA_EPS_REPORT}${case_id} eps=${eps}; "

  # impulse train: spacing (nper + 1/N) periods, so the phase walks by T0/N
  imp_dt="$(awk -v t="${KA_T0}" -v n="${nper}" -v m="${KA_NIMP}" 'BEGIN{ printf "%.10e", t*(n + 1.0/m) }')"
  imp_t1="$(awk -v t="${KA_T0}" -v nb="${nbase}" 'BEGIN{ printf "%.10e", t*nb }')"
  imp_times="$(pn_imp_times "${imp_t1}" "${imp_dt}" "${KA_NIMP}")"
  tstop_s="$(awk -v t1="${imp_t1}" -v dt="${imp_dt}" -v m="${KA_NIMP}" 'BEGIN{ printf "%.10e", t1 + m*dt }')"
  tmeas_start="$(awk -v t="${KA_T0}" 'BEGIN{ printf "%.10e", 3*t }')"

  amp="$(awk -v q="${KA_DQ}" -v hw="${KA_IMP_HW}" 'BEGIN{ printf "%.10e", q/hw }')"

  for variant in ref pert; do
    this_amp="0"
    [[ "${variant}" == "pert" ]] && this_amp="${amp}"
    cid="${case_id}_${variant}"
    netlist="${NETLIST_DIR}/${cid}.spice"
    log="${LOG_DIR}/${cid}.log"
    sed \
      -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
      -e "s|@@CORNER_ID@@|${case_id}|g" \
      -e "s|@@LT@@|${KA_LT}|g" \
      -e "s|@@CT@@|${KA_CT}|g" \
      -e "s|@@RLOSS@@|${rloss}|g" \
      -e "s|@@GNEG@@|${gneg}|g" \
      -e "s|@@BNL@@|${bnl}|g" \
      -e "s|@@VIC@@|${KA_A}|g" \
      -e "s|@@TSTEP@@|${KA_TSTEP}|g" \
      -e "s|@@TSTOP@@|${tstop_s}|g" \
      -e "s|@@TMAX@@|${KA_TMAX}|g" \
      -e "s|@@IMP_HW@@|${KA_IMP_HW}|g" \
      -e "s|@@IMP_AMP@@|${this_amp}|g" \
      -e "s|@@IMP_PWL@@|$(pn_pwl_train "${imp_times}" "${KA_IMP_HW}" "${this_amp}")|g" \
      -e "s|@@NOISE_FSTART@@|$(awk -v f="${KA_F0}" 'BEGIN{printf "%.6e", 0.9*f}')|g" \
      -e "s|@@NOISE_FSTOP@@|$(awk -v f="${KA_F0}" 'BEGIN{printf "%.6e", 1.1*f}')|g" \
      -e "s|@@OUT_PREFIX@@|mc_${cid}|g" \
      "${EXPERIMENT_DIR}/testbench/tb_isf_known_answer.spice.tmpl" > "${netlist}"
    if grep -vE '^[[:space:]]*\*' "${netlist}" | grep -q '@@'; then
      echo "error: unsubstituted placeholder token left in ${netlist}" >&2
      grep -nE '@@' "${netlist}" | grep -vE ':[[:space:]]*\*' >&2
      exit 1
    fi
    rc=0
    ( cd "${WORKDIR}" && ngspice -b "${netlist}" ) > "${log}" 2>&1 || rc=$?
    if [[ ${rc} -ne 0 ]]; then
      echo "error: ngspice exited ${rc} on ${cid}; log at ${log}" >&2
      exit 1
    fi
  done

  ref_dat="${WORKDIR}/mc_${case_id}_ref_tank"
  pert_dat="${WORKDIR}/mc_${case_id}_pert_tank"
  for f in "${ref_dat}" "${pert_dat}"; do
    [[ -f "${f}" ]] || { echo "error: ${f} was not written by the deck." >&2; exit 1; }
  done

  # ONE threshold, taken from the reference run, applied to both: see
  # pn_window_mean's header.
  thr="$(pn_window_mean "${ref_dat}" "${tmeas_start}" "${tstop_s}")"
  pn_crossings "${ref_dat}"  "${tmeas_start}" "${tstop_s}" "${thr}" > "${WORKDIR}/${case_id}_ref.cross"
  pn_crossings "${pert_dat}" "${tmeas_start}" "${tstop_s}" "${thr}" > "${WORKDIR}/${case_id}_pert.cross"

  read -r f_meas vpp_meas _cyc _mean _a _b dtmax_meas _n \
    <<<"$(osc_metrics "${ref_dat}" "${tmeas_start}" "${tstop_s}")"
  a_meas="$(awk -v v="${vpp_meas}" 'BEGIN{ printf "%.10e", v/2 }')"
  qmax="$(awk -v c="${KA_CT}" -v a="${a_meas}" 'BEGIN{ printf "%.10e", c*a }')"
  gq_peak="$(awk -v q="${qmax}" 'BEGIN{ printf "%.10e", 1/q }')"

  steps="$(pn_isf_steps "${WORKDIR}/${case_id}_ref.cross" "${WORKDIR}/${case_id}_pert.cross" \
                        "${imp_times}" "${KA_PLATEAU_FRAC}" "${tstop_s}")"
  base_rms="$(echo "${steps}" | awk '$1 == "BASE" { print $3 }')"
  n_far="$(echo "${steps}" | awk '$1 == "GUARD" { print $5 }')"

  : > "${WORKDIR}/${case_id}.gamma"
  dtau_char="$(awk -v q="${KA_DQ}" -v qm="${qmax}" -v f="${f_meas}" \
                   'BEGIN{ PI=4*atan2(1,1); printf "%.10e", 0.7071*(q/qm)/(2*PI*f) }')"
  tol_interp="$(awk -v f="${f_meas}" -v dt="${dtmax_meas}" -v dc="${dtau_char}" \
                    'BEGIN{ PI=4*atan2(1,1); printf "%.6f", 100*(2*PI*f*dt*dt/8)/dc }')"
  tol_2nd="$(awk -v q="${KA_DQ}" -v qm="${qmax}" 'BEGIN{ printf "%.6f", 100*q/(2*qm) }')"
  tol_width="$(awk -v hw="${KA_IMP_HW}" -v t0="${KA_T0}" \
                   'BEGIN{ PI=4*atan2(1,1); x=PI*2*hw/t0; printf "%.6f", 100*x*x/6 }')"
  tol_eps="$(awk -v e="${eps}" 'BEGIN{ printf "%.6f", 100*e }')"
  tol_pct="$(awk -v a="${tol_eps}" -v b="${tol_interp}" -v c="${tol_2nd}" -v d="${tol_width}" \
                 'BEGIN{ printf "%.4f", 1.5*(a+b+c+d) }')"
  tol_basis="eps ${tol_eps}% + interp ${tol_interp}% + 2nd ${tol_2nd}% + width ${tol_width}% then x1.5"

  while read -r tag k t_imp phi _tb _ta _dtau dphi ripple n_pl; do
    [[ "${tag}" == "IMP" ]] || continue
    gq="$(awk -v d="${dphi}" -v q="${KA_DQ}" 'BEGIN{ if (d == "nan") print "nan"; else printf "%.8e", d/q }')"
    gq_ref="$(awk -v p="${phi}" -v gp="${gq_peak}" 'BEGIN{ if (p == "nan") print "nan"; else printf "%.8e", gp*cos(p) }')"
    aerr="$(awk -v a="${gq}" -v b="${gq_ref}" 'BEGIN{ if (a=="nan"||b=="nan") print "nan"; else { d=a-b; if(d<0)d=-d; printf "%.8e", d } }')"
    echo "${case_id},${k},${t_imp},${phi},${dphi},${gq},${gq_ref},${aerr},${ripple},${n_pl}" >> "${ISF_CSV}"
    if [[ "${phi}" != "nan" ]]; then echo "${phi} ${gq}" >> "${WORKDIR}/${case_id}.gamma"; fi
    # Per-phase SHAPE check, ABSOLUTE against the ISF peak 1/q_max -- not
    # relative, because the closed form passes through zero twice per cycle
    # and a relative test there is vacuous. Those two phases are the
    # falsification case: a purely-amplitude perturbation must move the phase
    # by nothing.
    check_row "${case_id}" "gq_phi" "impulse ${k} at phi=${phi} rad" "${gq}" "${gq_ref}" \
      "$(awk -v gp="${gq_peak}" -v t="${tol_pct}" 'BEGIN{ printf "%.6e", gp*t/100 }')" "abs" \
      "${tol_basis} / absolute against the ISF peak 1/q_max"
  done <<<"${steps}"

  read -r rms_t rms_s c0 c1 c2 c3 maxgap ngam <<<"$(pn_gamma_stats "${WORKDIR}/${case_id}.gamma")"
  gq_rms_ref="$(awk -v gp="${gq_peak}" 'BEGIN{ printf "%.8e", gp/sqrt(2) }')"

  check_row "${case_id}" "gq_rms" "trapezoidal over the measured phase grid" \
            "${rms_t}" "${gq_rms_ref}" "${tol_pct}" "pct" "${tol_basis}"
  # The ISF of this oscillator is a pure fundamental to O(eps): c1 must be the
  # peak and c2/c3 must be down at the eps level. A c3 comparable to c1 is the
  # signature of a phase grid too coarse for the ISF's harmonic content.
  check_row "${case_id}" "gq_c1" "ISF fundamental coefficient" \
            "${c1}" "${gq_peak}" "${tol_pct}" "pct" "${tol_basis}"
  check_row "${case_id}" "gq_c3" "ISF 3rd harmonic (must be at the eps level)" \
            "${c3}" "0" "$(awk -v gp="${gq_peak}" -v t="${tol_pct}" 'BEGIN{ printf "%.6e", gp*t/100 }')" "abs" \
            "${tol_basis} / absolute against zero"
  # The null test. Before the first impulse the two decks are bit-identical
  # (same breakpoints, zero amplitude), so the crossing-offset residual is
  # exactly zero up to the file's printed precision. The bound is 1 % of the
  # crossing-time step a single impulse produces: anything larger would mean
  # the comparison itself, not the circuit, is setting the floor.
  check_row "${case_id}" "null_floor" "pre-impulse crossing-offset residual (s)" \
            "${base_rms}" "0" "$(awk -v d="${dtau_char}" 'BEGIN{ printf "%.6e", 0.01*d }')" "abs" \
            "1 % of the single-impulse crossing-time step ${dtau_char} s"
  check_row "${case_id}" "crossing_match" "crossings further than T/4 from their partner" \
            "${n_far}" "0" "0.5" "abs" "exactly zero"

  # port noise from the SAME deck (the reference run's log carries it)
  si_sqrt="$(pn_inoise_from_log "${LOG_DIR}/${case_id}_ref.log")"
  si="$(awk -v s="${si_sqrt}" 'BEGIN{ if (s=="nan"||s=="") print "nan"; else printf "%.8e", s*s }')"
  g_loss="$(awk -v r="${rloss}" 'BEGIN{ printf "%.8e", 1/r }')"
  si_ref="$(awk -v g="${g_loss}" 'BEGIN{ printf "%.8e", 4*1.380649e-23*(273.15+27)*g }')"
  check_row "${case_id}" "port_noise_si" "input-referred S_i at the tank port (A^2/Hz)" \
            "${si}" "${si_ref}" "1.0" "pct" "4kT/R exactly; ngspice's own resistor noise model"

  if [[ "${case_id}" == "${KERNEL_CASE}" ]]; then
    KERNEL_GQ_RMS="${rms_t}"; KERNEL_SI="${si}"; KERNEL_A="${a_meas}"; KERNEL_G="${g_loss}"
    KERNEL_TOL_PCT="${tol_pct}"
    KERNEL_C1="${c1}"; KERNEL_C2="${c2}"; KERNEL_C3="${c3}"; KERNEL_C0="${c0}"
    KERNEL_MAXGAP="${maxgap}"; KERNEL_NGAM="${ngam}"
    KERNEL_RMS_S="${rms_s}"
  fi

  rm -f "${WORKDIR}/mc_${case_id}"_*
done

# ============================================================ KA-3 portnoise
PN_R="1e3"
PN_C="1e-12"
PN_TEMP="27"
PN_NPTS="5"
PN_FSTART="1e9"
PN_FSTOP="11e9"
cid="portnoise"
netlist="${NETLIST_DIR}/${cid}.spice"
log="${LOG_DIR}/${cid}.log"
sed \
  -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
  -e "s|@@CORNER_ID@@|${cid}|g" \
  -e "s|@@RN@@|${PN_R}|g" \
  -e "s|@@CN@@|${PN_C}|g" \
  -e "s|@@TEMP_C@@|${PN_TEMP}|g" \
  -e "s|@@NPTS@@|${PN_NPTS}|g" \
  -e "s|@@FSTART@@|${PN_FSTART}|g" \
  -e "s|@@FSTOP@@|${PN_FSTOP}|g" \
  "${EXPERIMENT_DIR}/testbench/tb_portnoise_known_answer.spice.tmpl" > "${netlist}"
if grep -vE '^[[:space:]]*\*' "${netlist}" | grep -q '@@'; then
  echo "error: unsubstituted placeholder token left in ${netlist}" >&2; exit 1
fi
rc=0
( cd "${WORKDIR}" && ngspice -b "${netlist}" ) > "${log}" 2>&1 || rc=$?
[[ ${rc} -eq 0 ]] || { echo "error: ngspice exited ${rc} on ${cid}" >&2; exit 1; }

pn_ref="$(awk -v r="${PN_R}" -v t="${PN_TEMP}" 'BEGIN{ printf "%.8e", sqrt(4*1.380649e-23*(273.15+t)/r) }')"
while read -r freq val; do
  check_row "${cid}" "inoise_spectrum" "at ${freq} Hz (A/sqrt(Hz))" "${val}" "${pn_ref}" "0.5" "pct" \
            "sqrt(4kT/R) exactly and frequency-independent by construction"
done < <(pn_inoise_table "${log}")

# ============================================================ KA-4 kernel
# The end-to-end identity. Both sides are computed from the isf_highq deck:
#   measured  -> pn_l_dbc(Gq_rms measured, S_i measured, 1 MHz)
#   closed    -> Leeson's linear-tank kernel kTG/(C^2 A^2 dw^2), derived
#                without reference to the ISF formalism at all.
read -r L_MEAS L_MEAS_HL <<<"$(pn_l_dbc "${KERNEL_GQ_RMS}" "${KERNEL_SI}" "${KA_OFFSET_HZ}")"
L_CLOSED="$(awk -v g="${KERNEL_G}" -v c="${KA_CT}" -v a="${KERNEL_A}" -v df="${KA_OFFSET_HZ}" 'BEGIN{
  PI=4*atan2(1,1); dw=2*PI*df; kT=1.380649e-23*(273.15+27)
  printf "%.4f", 10*log(kT*g/(c*c*a*a*dw*dw))/log(10)
}')"
KERNEL_TOL_DB="$(awk -v t="${KERNEL_TOL_PCT}" 'BEGIN{ printf "%.4f", 20*log(1+t/100)/log(10) + 0.05 }')"
check_row "kernel" "L_1MHz_dBc_per_Hz" "measured ISF + measured S_i vs the closed-form Leeson kernel" \
          "${L_MEAS}" "${L_CLOSED}" "${KERNEL_TOL_DB}" "abs" \
          "L ~ Gq_rms^2 so the ${KERNEL_TOL_PCT}% ISF tolerance maps to 20*log10(1+tol) dB; +0.05 dB for S_i"

# ------------------------------------------------------------------ record
{
  echo "# Record ${RECORD_ID}"
  echo
  echo "- **Experiment**: phase-noise (method check)"
  echo "- **Claim**: that the phase-noise estimator this experiment grades"
  echo "  \`spec/target-spec.md\` row 4 through -- \`sim/lib.sh\`'s"
  echo "  \`pn_crossings\` / \`pn_isf_steps\` / \`pn_gamma_stats\` / \`pn_l_dbc\`,"
  echo "  i.e. an impulse-response measurement of the ISF reduced through the"
  echo "  Hajimiri-Lee kernel -- recovers the right answer on oscillators whose"
  echo "  ISF and whose phase noise are known in closed form. **Ratifies no"
  echo "  \`spec/target-spec.md\` row and says nothing about \`design/vco.sch\`.**"
  echo "- **Method**: two synthetic limit-cycle LC oscillators"
  echo "  (\`testbench/tb_isf_known_answer.spice.tmpl\`: L = ${KA_LT} H,"
  echo "  C = ${KA_CT} F, f0 = ${KA_F0} Hz, limit-cycle amplitude ${KA_A} V set"
  echo "  by a cubic negative-conductance element) and a bare R||C port"
  echo "  (\`testbench/tb_portnoise_known_answer.spice.tmpl\`)."
  echo "  - A train of ${KA_NIMP} triangular charge impulses of ${KA_DQ} C"
  echo "    (half-width ${KA_IMP_HW} s) is injected into the tank at a spacing"
  echo "    deliberately offset from an integer number of periods, so the"
  echo "    impulses walk the carrier phase and one run samples the whole ISF."
  echo "  - The reference run is the SAME deck with the impulse amplitude set"
  echo "    to zero, so both runs carry an identical PWL breakpoint set and the"
  echo "    pre-impulse crossing-offset residual is an exact null test. It is"
  echo "    checked as \`null_floor\`."
  echo "  - Each impulse's excess-phase step is read off the plateau over the"
  echo "    last ${KA_PLATEAU_FRAC} of the inter-impulse interval, so the"
  echo "    amplitude transient is excluded by construction."
  echo "  - transient \`tran ${KA_TSTEP} <case tstop>\`, timestep ceiling"
  echo "    \`${KA_TMAX}\`, \`uic\` from the limit-cycle amplitude."
  echo "- **Closed forms checked**:"
  echo "  - \`Gq(phi) = cos(phi)/(C*A)\`, from the phase-plane geometry of an"
  echo "    LC resonator (derivation in the testbench header). Checked at every"
  echo "    sampled phase, ABSOLUTELY against the ISF peak \`1/q_max\`, so the"
  echo "    two phases where the ISF is exactly zero are a real falsification"
  echo "    case rather than a vacuous relative test."
  echo "  - \`Gq_rms = 1/(sqrt(2)*C*A)\`, the scalar the kernel consumes."
  echo "  - \`inoise_spectrum = sqrt(4kT/R)\`, exactly, frequency-independent."
  echo "  - \`L(df) = kTG/(C^2 A^2 dw^2)\` -- Leeson's linear-tank kernel,"
  echo "    derived independently of the ISF formalism, against the measured"
  echo "    ISF and the measured port noise pushed through \`pn_l_dbc\`."
  echo "- **Tolerances**: DERIVED, not chosen. Each is the sum of closed-form"
  echo "  bounds on named error terms times a stated x1.5 headroom, and each"
  echo "  row's \`tol_basis\` column names its terms: \`eps = (Gn-G)/(w0 C)\`"
  echo "  (the closed form is exact only as eps -> 0), \`interp\` (linear"
  echo "  crossing interpolation relative to the step being measured),"
  echo "  \`2nd\` (\`dq/2q_max\`, the second-order phase response), \`width\`"
  echo "  (a triangular impulse is not a delta). Measured: ${KA_EPS_REPORT}"
  echo "- **Result**: ${passed}/${total} checked quantities within their"
  echo "  derived tolerance."
  if [[ ${#failed_rows[@]} -gt 0 ]]; then
    echo "- **Failed rows**: ${failed_rows[*]}"
  fi
  echo "- **End-to-end kernel check (KA-4)**: measured Gq_rms"
  echo "  ${KERNEL_GQ_RMS} rad/C and measured S_i ${KERNEL_SI} A^2/Hz give"
  echo "  **${L_MEAS} dBc/Hz** at ${KA_OFFSET_HZ} Hz against the closed-form"
  echo "  Leeson kernel **${L_CLOSED} dBc/Hz** (tolerance ${KERNEL_TOL_DB} dB)."
  echo "  \`pn_l_dbc\`'s Hajimiri-Lee-paper-form output for the same inputs is"
  echo "  ${L_MEAS_HL} dBc/Hz, exactly 3 dB lower; the agreement above is what"
  echo "  settles which of the two forms this repo quotes. See \`pn_l_dbc\`'s"
  echo "  header and \`README.md\`."
  echo "- **Measured ISF harmonics (${KERNEL_CASE})**: c0 ${KERNEL_C0},"
  echo "  c1 ${KERNEL_C1}, c2 ${KERNEL_C2}, c3 ${KERNEL_C3} rad/C; phase grid"
  echo "  ${KERNEL_NGAM} samples, largest gap ${KERNEL_MAXGAP} rad. Sample-mean"
  echo "  Gq_rms ${KERNEL_RMS_S} vs trapezoidal ${KERNEL_GQ_RMS} rad/C -- the"
  echo "  difference is what the phase grid's non-uniformity was worth."
  echo "- **PDK**: none, deliberately. The decks use only ngspice-native L/C/R"
  echo "  and behavioural sources, so this check runs on a bare checkout and a"
  echo "  failing estimator cannot be confused with a PDK or OSDI problem."
  echo "- **ngspice**: \`${NGSPICE_VERSION}\`"
  echo "- **Links**:"
  echo "  - Templates: \`testbench/tb_isf_known_answer.spice.tmpl\`,"
  echo "    \`testbench/tb_portnoise_known_answer.spice.tmpl\`"
  echo "  - Per-case generated decks: \`netlist-snapshots/${RECORD_ID}/\`"
  echo "  - Per-case raw ngspice logs: \`corners/${RECORD_ID}/\`"
  echo "  - Comparison table: \`records/${RECORD_ID}-method-check.csv\`"
  echo "  - Measured ISF, per phase: \`records/${RECORD_ID}-method-isf.csv\`"
  echo "- **Reproduce**: \`sim/phase-noise/run_method_check.sh\` (no arguments,"
  echo "  no PDK required)."
  echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MD_OUT}"

echo
echo "record        : ${RECORD_ID}"
echo "method check  : ${passed}/${total} quantities within their derived tolerance"
echo "kernel (KA-4) : measured ${L_MEAS} dBc/Hz vs closed form ${L_CLOSED} dBc/Hz"
echo "written       : ${MD_OUT#"${REPO_ROOT}"/}"

if [[ ${passed} -ne ${total} ]]; then
  echo "error: ${#failed_rows[@]} checked quantity/quantities exceeded tolerance: ${failed_rows[*]}" >&2
  exit 1
fi
echo "OK: the ISF extractor, the port-noise extraction and the phase-noise kernel all reproduce their closed forms."
