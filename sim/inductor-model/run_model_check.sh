#!/usr/bin/env bash
# Cold-start invocation (this is the whole thing -- there are no hidden steps):
#
#   sim/inductor-model/run_model_check.sh
#
# Requires: ngspice on PATH, a bash, and awk. Unlike sim/tank-characterization,
# this experiment does NOT need the PDK installed -- sg13g2_inductor_analytic.spice
# is self-contained (its PDK constants are transcribed into it, with each one's
# source cited in its header), and it loads no PDK model library. That is a
# deliberate property, not an accident: the model has to be checkable by a
# reader who has the repository but not a 3 GB PDK tarball.
#
# WHAT IT DOES
# ------------
# Exercises sg13g2_inductor_analytic.spice over a process x temperature grid for
# the three PDK LVS-testcase geometries, and holds the SPICE netlist to an
# INDEPENDENTLY COMPUTED CLOSED FORM at every point (testbench/closed_form_z.awk).
# The run exits non-zero if any point drifts past the tolerance, so "it ran" and
# "it produced trustworthy numbers" stay distinguishable.
#
# It also records, for every geometry / corner / frequency, the Q the model
# gives AND the Q lower bound that follows from the one-sided
# effective-conduction-depth assumption -- i.e. an explicit bracket on the
# largest known systematic error in this model (unmodelled lateral current
# crowding). See ACCURACY LIMITS in sg13g2_inductor_analytic.spice.
#
# Everything it writes is APPEND-ONLY evidence keyed by a fresh record ID:
#
#   netlist-snapshots/<record-id>/<corner-id>.spice   exact netlist simulated
#   corners/<record-id>/<corner-id>.log               raw ngspice batch output
#   records/<record-id>-curves/<corner-id>.csv        L/Q vs frequency
#   records/<record-id>.csv                           scalar summary
#   records/<record-id>-method-check.csv              netlist vs closed form
#   records/<record-id>-geometry-check.csv            L cross-checks (no ngspice)
#   records/<record-id>.md                            the narrative record
#
# See sim/README.md for the convention. Nothing here is ever rewritten.
set -euo pipefail

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SIM_DIR}/.." && pwd)"

MODEL_LIB="${EXPERIMENT_DIR}/sg13g2_inductor_analytic.spice"
REF_AWK="${EXPERIMENT_DIR}/testbench/closed_form_z.awk"

if ! command -v ngspice >/dev/null 2>&1; then
  echo "error: ngspice not found on PATH." >&2
  exit 1
fi
for f in "${MODEL_LIB}" "${REF_AWK}"; do
  [[ -f "${f}" ]] || { echo "error: missing ${f}" >&2; exit 1; }
done

NGSPICE_VERSION="$(ngspice --version 2>&1 | sed -n 's/^\*\* \(ngspice-[0-9.]*\).*/\1/p' | head -1)"
NGSPICE_VERSION="${NGSPICE_VERSION:-unknown}"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else echo "unavailable"; fi
}
MODEL_SHA="$(sha256_of "${MODEL_LIB}")"
REF_SHA="$(sha256_of "${REF_AWK}")"

GIT_SHA="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo nogit)"
RECORD_ID="$(date -u +%Y%m%d-%H%M%S)-${GIT_SHA}"

NETLIST_DIR="${EXPERIMENT_DIR}/netlist-snapshots/${RECORD_ID}"
LOG_DIR="${EXPERIMENT_DIR}/corners/${RECORD_ID}"
CURVE_DIR="${EXPERIMENT_DIR}/records/${RECORD_ID}-curves"
CSV_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.csv"
METHOD_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-method-check.csv"
GEOM_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-geometry-check.csv"
MD_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.md"
mkdir -p "${NETLIST_DIR}" "${LOG_DIR}" "${CURVE_DIR}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/sg13g2-indmodel.XXXXXX")"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT
cp "${EXPERIMENT_DIR}/.spiceinit" "${WORKDIR}/.spiceinit"

# --------------------------------------------------------------- sweep ranges
# Same 100 MHz .. 300 GHz band as sim/tank-characterization, for the same
# reason: the target band is not chosen yet, so narrowing the sweep would make
# the study circular. The model's OWN stated validity window is far narrower
# (0.5 .. 20 GHz -- see sg13g2_inductor_analytic.spice) and the extra decades
# are swept so the record shows where it stops being credible.
FMIN=1e8
FMAX=3e11
NDEC_MEAS=500
NDEC_CURVE=50

# PVT grid.
#   P: the two independent process axes this model actually has --
#      TopMetal2 sheet resistance RSTM2 (7.5 / 11 / 14.5 mOhm/sq) and substrate
#      resistivity RSBLK (37.5 / 50 / 62.5 Ohm*cm), both from the SG13G2
#      Process Specification Rev. 1.2. They are swept independently rather than
#      as a single "slow/fast" knob because they move Q in different directions
#      and their worst case is not at a corner of either axis alone.
#   T: -40 / 27 / 125 C, the same span sim/tank-characterization uses.
#   V: not swept, and not silently skipped -- this device is a passive metal
#      spiral with no junction anywhere in the model, so it is bias-independent
#      by construction, not by measurement. (Contrast the MIM study, which DID
#      sweep bias because the MIM models could in principle have had a voltage
#      coefficient.)
#
# Colon-separated strings rather than `declare -A`: macOS still ships bash 3.2,
# and spec/review-bar.md item 1 forbids a cold start that needs a newer bash.
CORNERS=(
  "typ:1.0:1.0"
  "rlo:0.6818:1.0"
  "rhi:1.3182:1.0"
  "slo:1.0:0.75"
  "shi:1.0:1.25"
  "rlo_slo:0.6818:0.75"
  "rlo_shi:0.6818:1.25"
  "rhi_slo:1.3182:0.75"
  "rhi_shi:1.3182:1.25"
)
TEMPS=(-40 27 125)

# <key>:<w_um>:<s_um>:<d_um>:<nr_r>
IND_SPECS=(
  "p1:8.22:3.29:47.65:1"
  "p13:6.10:3.29:110.11:5"
  "p11:8.22:3.74:141.975:4"
)
# Frequencies the known-answer check gates on. All are inside the model's
# stated 0.5-20 GHz validity window; the ladder truncation error is < 0.1 %
# there, which is what sets the tolerance below.
CHECK_FREQS=(1e9 5e9 1e10 2e10)
CHECK_TOL_PCT=0.5

meas_value() {
  local log="$1" name="$2"
  awk -v n="${name}" '$1 == n && $2 == "=" { print $3; found=1 } END { if (!found) print "" }' "${log}" | head -1
}

echo "corner_label,mc_rsh,mc_rsub,temp_c,geometry,w_um,s_um,d_um,nr_r,status,srf_hz,l_1ghz_h,l_5ghz_h,l_10ghz_h,q_1ghz,q_5ghz,q_10ghz,qlow_1ghz,qlow_5ghz,qlow_10ghz" > "${CSV_OUT}"
echo "corner_label,temp_c,geometry,f_hz,quantity,simulated,closed_form,rel_err_pct,tol_pct,status" > "${METHOD_CSV}"

total=0
passed=0
method_fail=0
failed_points=()

for centry in "${CORNERS[@]}"; do
  IFS=: read -r clabel mc_rsh mc_rsub <<EOF
${centry}
EOF
  for temp in "${TEMPS[@]}"; do
    corner_id="ind_${clabel}_${temp}c"
    netlist="${NETLIST_DIR}/${corner_id}.spice"
    log="${LOG_DIR}/${corner_id}.log"
    curve="${CURVE_DIR}/${corner_id}.csv"
    total=$((total + 1))

    sed \
      -e "s|@@MODEL_LIB@@|${MODEL_LIB}|g" \
      -e "s|@@MC_RSH@@|${mc_rsh}|g" \
      -e "s|@@MC_RSUB@@|${mc_rsub}|g" \
      -e "s|@@TEMP_C@@|${temp}|g" \
      -e "s|@@CORNER_ID@@|${corner_id}|g" \
      -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
      -e "s|@@FMIN@@|${FMIN}|g" \
      -e "s|@@FMAX@@|${FMAX}|g" \
      -e "s|@@NDEC_MEAS@@|${NDEC_MEAS}|g" \
      -e "s|@@NDEC_CURVE@@|${NDEC_CURVE}|g" \
      -e "s|@@CURVE_CSV@@|${curve}|g" \
      "${EXPERIMENT_DIR}/testbench/tb_inductor_model_check.spice.tmpl" > "${netlist}"

    rc=0
    ( cd "${WORKDIR}" && ngspice -b "${netlist}" ) > "${log}" 2>&1 || rc=$?
    model_error=0
    if grep -qiE "unknown subckt|could not find|can't find|undefined parameter|no such (parameter|model)" "${log}"; then
      model_error=1
    fi
    echo "[${corner_id}] ngspice rc=${rc} model_error=${model_error}"

    point_ok=1
    for spec in "${IND_SPECS[@]}"; do
      IFS=: read -r key gw gs gd gn <<EOF
${spec}
EOF
      srf="$(meas_value "${log}" "srf_${key}")"
      l1="$(meas_value  "${log}" "l_${key}_1g")"
      l5="$(meas_value  "${log}" "l_${key}_5g")"
      l10="$(meas_value "${log}" "l_${key}_10g")"
      q1="$(meas_value  "${log}" "q_${key}_1g")"
      q5="$(meas_value  "${log}" "q_${key}_5g")"
      q10="$(meas_value "${log}" "q_${key}_10g")"

      # ---- known-answer check, and the crowding lower bound on Q -------------
      qlow1=""; qlow5=""; qlow10=""
      for fhz in "${CHECK_FREQS[@]}"; do
        ref="$(awk -v w="${gw}" -v s="${gs}" -v d="${gd}" -v n="${gn}" \
                   -v mc_rsh="${mc_rsh}" -v mc_rsub="${mc_rsub}" \
                   -v temp="${temp}" -v f="${fhz}" -f "${REF_AWK}" </dev/null)"
        # Word splitting is the point here: closed_form_z.awk prints eight
        # space-separated fields on one line, and this splits them into $1..$8.
        # shellcheck disable=SC2086
        set -- ${ref}
        ref_zr="$1"; ref_zi="$2"; ref_abs="$3"; ref_dr="$8"
        case "${fhz}" in
          1e9)  ftag=1g  ;;
          5e9)  ftag=5g  ;;
          1e10) ftag=10g ;;
          2e10) ftag=20g ;;
        esac
        sim_zr="$(meas_value "${log}" "zr_${key}_${ftag}")"
        sim_zi="$(meas_value "${log}" "zi_${key}_${ftag}")"

        read -r err st <<EOF
$(awk -v sr="${sim_zr:-nan}" -v si="${sim_zi:-nan}" -v rr="${ref_zr}" -v ri="${ref_zi}" -v ra="${ref_abs}" -v tol="${CHECK_TOL_PCT}" '
  BEGIN {
    if (sr == "nan" || si == "nan" || sr == "" || si == "") { print "nan FAIL"; exit }
    dr = sr - rr; di = si - ri
    e = sqrt(dr*dr + di*di)/ra*100.0
    printf "%.6f %s\n", e, (e <= tol ? "PASS" : "FAIL")
  }')
EOF
        echo "${clabel},${temp},${key},${fhz},z_driving_point,${sim_zr}${sim_zi:+ + j}${sim_zi},${ref_zr} + j${ref_zi},${err},${CHECK_TOL_PCT},${st}" >> "${METHOD_CSV}"
        [[ "${st}" == "PASS" ]] || point_ok=0

        # Q lower bound: add the crowding excess series resistance to Re(Z).
        if [[ -n "${sim_zr}" && -n "${sim_zi}" ]]; then
          ql="$(awk -v zr="${sim_zr}" -v zi="${sim_zi}" -v dr="${ref_dr}" 'BEGIN { printf "%.6e", zi/(zr + dr) }')"
          case "${ftag}" in
            1g)  qlow1="${ql}"  ;;
            5g)  qlow5="${ql}"  ;;
            10g) qlow10="${ql}" ;;
          esac
        fi
      done

      status=FAIL
      if [[ ${rc} -eq 0 && ${model_error} -eq 0 && -n "${l1}" && -n "${q1}" && -n "${srf}" ]]; then
        status=PASS
      fi
      echo "${clabel},${mc_rsh},${mc_rsub},${temp},${key},${gw},${gs},${gd},${gn},${status},${srf},${l1},${l5},${l10},${q1},${q5},${q10},${qlow1},${qlow5},${qlow10}" >> "${CSV_OUT}"
      [[ "${status}" == "PASS" ]] || failed_points+=("${corner_id}/${key}")
    done

    [[ ${point_ok} -eq 1 ]] || method_fail=$((method_fail + 1))
    if [[ ${rc} -eq 0 && ${model_error} -eq 0 && ${point_ok} -eq 1 ]]; then
      passed=$((passed + 1))
    fi
  done
done

# ------------------------------------------------- geometry-level cross-checks
# No ngspice involved: these compare the inductance the model USES (Mohan et
# al. 1999 modified Wheeler, octagonal) against the two other independent
# expressions in the same paper, against the classical single-loop formula for
# the one-turn case, and against IHP's own PCell default `lEstim`. This is the
# closest thing to an external check on the MODEL (as opposed to on the
# netlist) that is available without EM extraction or silicon.
echo "case,w_um,s_um,d_um,nr_r,d_out_um,d_avg_um,fill_ratio,l_modwheeler_h,l_currentsheet_h,l_monomial_h,l_singleloop_h,spread_of_3_pct,external_reference_h,err_vs_external_pct,note" > "${GEOM_CSV}"
# Table columns: key w s d n external_reference_L note   ("-" = no external ref)
awk '
{
  key = $1; w = $2+0; s = $3+0; d = $4+0; n = $5+0; ext = $6; note = $7
  PI = 3.14159265358979; MU0 = 1.25663706212e-6
  KOCT = 3.31370849898476; GRID = 0.01
  pitch = s + w + GRID
  din = d; dout = d + 2*(n-1)*pitch + 2*w
  davg = (din + dout)/2; rho = (dout - din)/(dout + din)
  # Mohan et al. 1999 (1) modified Wheeler, octagonal K1=2.25 K2=3.55
  lmw = 2.25*MU0*n*n*davg*1e-6/(1 + 3.55*rho)
  # Mohan et al. 1999 (2) current sheet, octagonal c1..c4 = 1.07 2.29 0.00 0.19
  lcs = MU0*n*n*davg*1e-6*1.07/2*(log(2.29/rho) + 0.19*rho*rho)
  # Mohan et al. 1999 (3) monomial, octagonal; um in, nH out
  lmn = 1.33e-3 * exp(-1.21*log(dout)) * exp(-0.163*log(w)) * exp(2.43*log(davg)) \
        * exp(1.75*log(n)) * exp(-0.049*log(s)) * 1e-9
  # Classical single loop (Grover): equal-perimeter circle of radius a, with the
  # geometric mean distance of a w x t strip, GMD = 0.2235*(w+t):
  #   L = mu0*a*(ln(8a/GMD) - 2)
  lsl = ""
  if (n == 1) {
    len = KOCT*(d + w); a = len/(2*PI)*1e-6; gmd = 0.2235*(w + 3.0)*1e-6
    lsl = sprintf("%.6e", MU0*a*(log(8*a/gmd) - 2))
  }
  lo = lmw; hi = lmw
  if (lcs < lo) lo = lcs
  if (lcs > hi) hi = lcs
  if (lmn < lo) lo = lmn
  if (lmn > hi) hi = lmn
  spread = (hi - lo)/lmw*100
  eref = ""; eerr = ""
  if (ext != "-") { eref = sprintf("%.6e", ext+0); eerr = sprintf("%.3f", (lmw - ext)/ext*100) }
  printf "%s,%g,%g,%g,%d,%.4f,%.4f,%.5f,%.6e,%.6e,%.6e,%s,%.3f,%s,%s,%s\n",
    key, w, s, d, n, dout, davg, rho, lmw, lcs, lmn, lsl, spread, eref, eerr, note
}' >> "${GEOM_CSV}" <<'GEOMTABLE'
p1 8.22 3.29 47.65 1 - PDK-LVS-testcase-single-turn
p13 6.10 3.29 110.11 5 - PDK-LVS-testcase-5-turn
p11 8.22 3.74 141.975 4 - PDK-LVS-testcase-4-turn
ihp_lEstim_at_minD 2.0 2.1 14.76 1 33.303e-12 IHP-inductor2-PCell-lEstim-vs-d-from-inductor_minD()
ihp_lEstim_at_DMIN 2.0 2.1 15.48 1 33.303e-12 IHP-inductor2-PCell-lEstim-vs-shipped-DMIN
GEOMTABLE

# ------------------------------------------------------------------- record
{
  echo "# Record ${RECORD_ID}"
  echo
  echo "- **Experiment**: inductor-model"
  echo "- **Claim**: the SPICE netlist in \`sg13g2_inductor_analytic.spice\`"
  echo "  implements, to ${CHECK_TOL_PCT} % on the complex driving-point impedance,"
  echo "  the closed form its header says it implements, at every point of a"
  echo "  process x temperature grid, for the three PDK LVS-testcase geometries."
  echo "  This record ratifies NO spec row, and it does NOT claim the model is a"
  echo "  faithful description of a real SG13G2 spiral -- that would need EM"
  echo "  extraction or silicon. See README.md, \"What this does not establish\"."
  echo "- **Model under test**: \`sg13g2_inductor_analytic.spice\`, sha256"
  echo "  \`${MODEL_SHA}\`"
  echo "- **Closed-form reference**: \`testbench/closed_form_z.awk\`, sha256"
  echo "  \`${REF_SHA}\` -- an independent evaluation of Z(f) in complex"
  echo "  arithmetic, NOT the ladder truncation the netlist uses, so agreement"
  echo "  bounds the truncation error as well as the netlist's correctness."
  echo "- **Method**: 1 A AC current injection into \`la\` with \`lb\` and \`sub\`"
  echo "  grounded, so V(la) = Z(f). Then Leff = Im(Z)/(2*pi*f),"
  echo "  Q = Im(Z)/Re(Z), and SRF = the f at which Im(Z) crosses zero falling."
  echo "  Scalars from a ${NDEC_MEAS} point/decade pass over ${FMIN}..${FMAX} Hz;"
  echo "  committed curves from a ${NDEC_CURVE} point/decade pass."
  echo "- **Q bracket**: every row also carries \`qlow_*\`, the Q that follows if"
  echo "  the one-sided effective-conduction-depth assumption is used for the"
  echo "  series resistance instead of the exact two-sided solution. The"
  echo "  difference is this model's unmodelled lateral current crowding, and"
  echo "  the true Q is expected between the two columns."
  echo "- **Corners run**: process {$(printf '%s ' "${CORNERS[@]%%:*}")} x"
  echo "  temperature {${TEMPS[*]}} C = ${total} simulation points, each"
  echo "  covering 3 geometries = $((total * 3)) device rows."
  echo "  The process axes are RSTM2 (TopMetal2 sheet resistance) and RSBLK"
  echo "  (substrate resistivity), swept independently; \`rlo\`/\`rhi\` and"
  echo "  \`slo\`/\`shi\` are their min/max from the SG13G2 Process Specification."
  echo "  Bias is not an axis: the model contains no junction."
  echo "- **PDK**: none loaded. This model is self-contained by design; the PDK"
  echo "  constants it uses are transcribed into its header with their sources."
  echo "- **ngspice**: \`${NGSPICE_VERSION}\`"
  echo "- **Result**: ${passed}/${total} simulation points PASS (ngspice exit 0,"
  echo "  no model-load error, and every known-answer check within"
  echo "  ${CHECK_TOL_PCT} %)."
  if [[ ${method_fail} -gt 0 ]]; then
    echo "- **Known-answer failures**: ${method_fail} point(s) exceeded the"
    echo "  ${CHECK_TOL_PCT} % tolerance -- treat every number in this record as"
    echo "  suspect until that is explained."
  fi
  if [[ ${#failed_points[@]} -gt 0 ]]; then
    echo "- **Failed device rows**: ${failed_points[*]}"
  fi
  echo "- **Links**:"
  echo "  - Model: \`sg13g2_inductor_analytic.spice\`"
  echo "  - Template: \`testbench/tb_inductor_model_check.spice.tmpl\`"
  echo "  - Closed-form reference: \`testbench/closed_form_z.awk\`"
  echo "  - Per-point generated netlists: \`netlist-snapshots/${RECORD_ID}/\`"
  echo "  - Per-point raw ngspice logs: \`corners/${RECORD_ID}/\`"
  echo "  - Scalar summary: \`records/${RECORD_ID}.csv\`"
  echo "  - Curves vs frequency: \`records/${RECORD_ID}-curves/\`"
  echo "  - Known-answer check: \`records/${RECORD_ID}-method-check.csv\`"
  echo "  - Inductance cross-checks: \`records/${RECORD_ID}-geometry-check.csv\`"
  echo "- **Reproduce**: \`sim/inductor-model/run_model_check.sh\` (no arguments,"
  echo "  no preceding steps, no PDK install needed)."
  echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MD_OUT}"

echo
echo "record       : ${RECORD_ID}"
echo "points       : ${passed}/${total} PASS"
echo "known-answer : $(( total - method_fail ))/${total} within ${CHECK_TOL_PCT}%"
echo "written      : ${MD_OUT#"${REPO_ROOT}"/}"

if [[ ${passed} -ne ${total} ]]; then
  echo "error: ${#failed_points[@]} device row(s) and/or $(( total - passed )) simulation point(s) did not pass." >&2
  exit 1
fi
