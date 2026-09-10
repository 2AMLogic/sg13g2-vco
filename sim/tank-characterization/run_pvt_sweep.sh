#!/usr/bin/env bash
# Cold-start invocation (this is the whole thing -- there are no hidden steps):
#
#   sim/tank-characterization/run_pvt_sweep.sh
#
# Optionally, if the PDK is not installed under one of the prefixes sim/env.sh
# probes (/usr/share/pdk, /usr/local/share/pdk, ~/share/pdk, ~/.ciel, ~/.volare):
#
#   export PDK_ROOT=/path/to/ihp-open-pdk   # parent dir containing ihp-sg13g2/
#   export PDK=ihp-sg13g2
#
# Requires: ngspice on PATH, a bash, and an IHP-Open-PDK v0.3.0 install (pinned
# in sim/pdk.json; fetchable with klayout-tools scripts/fetch-ihp-sg13g2.sh).
# Does NOT require xschem, klayout, klt, python, or any compiled OSDI model --
# every device this sweep touches is built from ngspice native primitives.
#
# Optional, and normally unset:
#   SG13G2_IND_MODEL_LIB   path to a SPICE file defining `.subckt inductor`.
#                          IHP-Open-PDK v0.3.0 ships no such model; see
#                          README.md "The inductor gap". When unset the
#                          inductor probe is still run, and its failure is
#                          recorded as MODEL_ABSENT evidence. This repository
#                          ships one analytic model with stated error bars:
#
#   export SG13G2_IND_MODEL_LIB=$PWD/sim/inductor-model/sg13g2_inductor_analytic.spice
#
#                          The record then names that file by its repo-relative
#                          path and its content sha256, because the numbers it
#                          produces are only as good as the model's own stated
#                          limits -- which are NOT the PDK's.
#
# WHAT IT DOES
# ------------
# Sweeps the SG13G2 MIM-capacitor models over the full process x temperature x
# bias grid, extracting C(f), Q(f) and SRF for three geometries of each of the
# two shipped MIM models, and runs the spiral-inductor probe once. Everything
# it writes is APPEND-ONLY evidence under this directory, keyed by a record ID
# that is minted fresh on every run:
#
#   netlist-snapshots/<record-id>/<corner-id>.spice   exact netlist simulated
#   corners/<record-id>/<corner-id>.log               raw ngspice batch output
#   records/<record-id>-curves/<corner-id>.csv        C/Q/L vs frequency
#   records/<record-id>.csv                           scalar summary, one row
#                                                     per corner x device
#   records/<record-id>-method-check.csv              known-answer check of the
#                                                     extraction arithmetic
#   records/<record-id>-inductor.csv                  inductor probe outcome
#   records/<record-id>.md                            the narrative record
#
# Nothing under those directories is ever rewritten -- a re-run mints a new
# record ID. See sim/README.md for the convention.
set -euo pipefail

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SIM_DIR}/.." && pwd)"

# shellcheck source=../env.sh
source "${SIM_DIR}/env.sh"
# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"

# ------------------------------------------------------------------ preflight
if ! command -v ngspice >/dev/null 2>&1; then
  echo "error: ngspice not found on PATH." >&2
  exit 1
fi
if [[ -z "${SG13G2_NGSPICE_MODELS:-}" || ! -f "${SG13G2_NGSPICE_MODELS}/cornerCAP.lib" ]]; then
  echo "error: could not resolve the SG13G2 ngspice model libraries." >&2
  echo "       expected \$PDK_ROOT/\$PDK/libs.tech/ngspice/models/cornerCAP.lib" >&2
  echo "       see the message from sim/env.sh above, and sim/pdk.json." >&2
  exit 1
fi

NGSPICE_VERSION="$(detect_ngspice_version)"

CORNERCAP_SHA="$(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerCAP.lib")"
CAPMOD_SHA="$(sha256_of "${SG13G2_NGSPICE_MODELS}/capacitors_mod.lib")"

RECORD_ID="$(mint_record_id "${REPO_ROOT}")"

NETLIST_DIR="${EXPERIMENT_DIR}/netlist-snapshots/${RECORD_ID}"
LOG_DIR="${EXPERIMENT_DIR}/corners/${RECORD_ID}"
CURVE_DIR="${EXPERIMENT_DIR}/records/${RECORD_ID}-curves"
CSV_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.csv"
METHOD_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-method-check.csv"
IND_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-inductor.csv"
MD_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.md"
mkdir -p "${NETLIST_DIR}" "${LOG_DIR}" "${CURVE_DIR}"

# ngspice must run from a directory holding this experiment's own .spiceinit,
# so a cold-start run does not depend on whether the PDK's install.py ever
# symlinked one into $HOME.
make_scratch_workdir "sg13g2-tank"

# --------------------------------------------------------------- sweep ranges
# The target band for this block is NOT chosen yet (spec/target-spec.md row 1
# is blank, and choosing it is downstream of this very study), so the sweep is
# deliberately wide rather than centred on an assumed frequency:
#   100 MHz .. 300 GHz, i.e. from well below any plausible LC-VCO tank up to
#   roughly the fT of this process's fastest HBT. The upper decade is knowingly
#   outside IHP's stated model validity -- see README.md "Band edges and model
#   validity". It is swept anyway so the record shows where the model stops
#   being credible instead of quietly stopping short of it.
FMIN=1e8
FMAX=3e11
NDEC_MEAS=500     # dense pass: scalar .meas extractions (SRF interpolation)
NDEC_CURVE=50     # coarse pass: the committed curve CSVs

# PVT grid.
#   P: cornerCAP.lib's three non-statistical MIM sections. cap_bcs/cap_wcs
#      scale cap_carea by 0.9/1.1 and cap_cpara likewise, i.e. +-10 % on the
#      MIM area capacitance. (The *_mismatch and *_stat sections are omitted:
#      they model device-to-device spread within one die, which needs a Monte
#      Carlo harness this study does not have -- named as future work in
#      README.md rather than silently skipped.)
#   V: MIM caps are passives; cmim_core carries TC1/TC2 temperature
#      coefficients but no voltage coefficient, so the model is
#      bias-independent by construction. Two bias points are swept anyway so
#      that claim is measured rather than asserted.
#   T: the same -40 / 27 / 125 C span the sibling blocks in this catalog use.
CAP_SECTIONS=(cap_typ cap_bcs cap_wcs)
CAP_LABELS=(typ bcs wcs)
TEMPS=(-40 27 125)
VBIASES=(0.0 1.5)

# Device instance table, one colon-separated record per instance:
#   <key>:<model>:<w_um>:<l_um>:<wfeed_um>
# <key> matches the node and .meas name prefixes in the template. cap_cmim has
# no wfeed parameter at all, hence the trailing empty field on those rows.
#
# Colon-separated strings rather than `declare -A`, deliberately: bash's
# associative arrays are a bash-4 feature and macOS still ships bash 3.2 as
# /bin/bash. A "one-command cold start" (spec/review-bar.md item 1) that
# silently needs a Homebrew bash is exactly the hidden prerequisite that bar
# exists to forbid, so this script stays bash-3.2 clean throughout.
DEV_SPECS=(
  "a20:cap_cmim:20:20:"
  "a35:cap_cmim:35:35:"
  "a50:cap_cmim:50:50:"
  "b20:cap_rfcmim:20:20:5"
  "b35:cap_rfcmim:35:35:10"
  "b50:cap_rfcmim:50:50:15"
)

echo "corner_label,cap_section,temp_c,vbias_v,device_model,w_um,l_um,wfeed_um,status,srf_hz,c_1ghz_f,c_2ghz_f,c_5ghz_f,c_10ghz_f,c_20ghz_f,q_1ghz,q_2ghz,q_5ghz,q_10ghz,q_20ghz" > "${CSV_OUT}"
echo "corner_label,temp_c,vbias_v,quantity,simulated,closed_form,rel_err_pct,tol_pct,status" > "${METHOD_CSV}"

total=0
passed=0
failed_points=()
method_fail=0
METHOD_TOL_PCT=0.1

# ------------------------------------------------------------- MIM cap sweep
for i in "${!CAP_SECTIONS[@]}"; do
  section="${CAP_SECTIONS[$i]}"
  label="${CAP_LABELS[$i]}"
  for temp in "${TEMPS[@]}"; do
    for vbias in "${VBIASES[@]}"; do
      corner_id="mimcap_${label}_${temp}c_${vbias}v"
      netlist="${NETLIST_DIR}/${corner_id}.spice"
      log="${LOG_DIR}/${corner_id}.log"
      curve="${CURVE_DIR}/${corner_id}.csv"
      total=$((total + 1))

      sed \
        -e "s|@@MODELS_DIR@@|${SG13G2_NGSPICE_MODELS}|g" \
        -e "s|@@CAP_SECTION@@|${section}|g" \
        -e "s|@@TEMP_C@@|${temp}|g" \
        -e "s|@@VBIAS@@|${vbias}|g" \
        -e "s|@@CORNER_ID@@|${corner_id}|g" \
        -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
        -e "s|@@FMIN@@|${FMIN}|g" \
        -e "s|@@FMAX@@|${FMAX}|g" \
        -e "s|@@NDEC_MEAS@@|${NDEC_MEAS}|g" \
        -e "s|@@NDEC_CURVE@@|${NDEC_CURVE}|g" \
        -e "s|@@CURVE_CSV@@|${curve}|g" \
        "${EXPERIMENT_DIR}/testbench/tb_mimcap_zscan.spice.tmpl" > "${netlist}"

      rc=0
      ( cd "${WORKDIR}" && ngspice -b "${netlist}" ) > "${log}" 2>&1 || rc=$?

      # A model-load failure is not always a nonzero exit, so check the text too.
      model_error=0
      if grep -qiE "unknown subckt|could not find|can't find|no such (parameter|model)" "${log}"; then
        model_error=1
      fi

      echo "[${corner_id}] ngspice rc=${rc} model_error=${model_error}"

      for spec in "${DEV_SPECS[@]}"; do
        IFS=: read -r key dev_model dev_w dev_l dev_wfeed <<EOF
${spec}
EOF
        srf="$(meas_value "${log}" "srf_${key}")"
        c1="$(meas_value  "${log}" "c_${key}_1g")"
        c2="$(meas_value  "${log}" "c_${key}_2g")"
        c5="$(meas_value  "${log}" "c_${key}_5g")"
        c10="$(meas_value "${log}" "c_${key}_10g")"
        c20="$(meas_value "${log}" "c_${key}_20g")"
        q1="$(meas_value  "${log}" "q_${key}_1g")"
        q2="$(meas_value  "${log}" "q_${key}_2g")"
        q5="$(meas_value  "${log}" "q_${key}_5g")"
        q10="$(meas_value "${log}" "q_${key}_10g")"
        q20="$(meas_value "${log}" "q_${key}_20g")"

        # cap_cmim has no self-resonance in ANY band (it is a series R-C with
        # no inductance at all), so a missing SRF for it is the expected,
        # physically meaningful answer -- not a failure.
        srf_field="${srf}"
        if [[ -z "${srf}" && "${dev_model}" == "cap_cmim" ]]; then
          srf_field="none"
        fi

        status=FAIL
        if [[ ${rc} -eq 0 && ${model_error} -eq 0 && -n "${c1}" && -n "${q1}" && -n "${srf_field}" ]]; then
          status=PASS
        fi
        echo "${label},${section},${temp},${vbias},${dev_model},${dev_w},${dev_l},${dev_wfeed},${status},${srf_field},${c1},${c2},${c5},${c10},${c20},${q1},${q2},${q5},${q10},${q20}" >> "${CSV_OUT}"
        if [[ "${status}" == "FAIL" ]]; then failed_points+=("${corner_id}/${key}"); fi
      done

      # ---- known-answer check on the extraction arithmetic -----------------
      # See sim/lib.sh's method_check_point for the shared reference-network
      # implementation (ideal R=2, L=1n, C=100f) and why it is re-checked at
      # every corner.
      point_status="$(method_check_point "${label}" "${temp}" "${vbias}" "${log}" "${METHOD_CSV}" "${METHOD_TOL_PCT}")"
      if [[ "${point_status}" != "PASS" ]]; then method_fail=$((method_fail + 1)); fi

      if [[ ${rc} -eq 0 && ${model_error} -eq 0 && "${point_status}" == "PASS" ]]; then
        passed=$((passed + 1))
      fi
    done
  done
done

# ------------------------------------------------------- spiral-inductor probe
# Run once, at nominal. IHP-Open-PDK v0.3.0 ships no inductor model, so with
# $SG13G2_IND_MODEL_LIB unset the probe is corner-independent: there is nothing
# for the corner section or temperature to act on, and the outcome is recorded
# as MODEL_ABSENT. With a model library supplied, this single nominal point is
# still all this experiment claims -- a drop-in model's own PVT behaviour is
# that model's business to evidence, not this MIM study's. sim/inductor-model/
# is where the model shipped in this repository corners itself.
ind_corner_id="inductor_probe"
ind_netlist="${NETLIST_DIR}/${ind_corner_id}.spice"
ind_log="${LOG_DIR}/${ind_corner_id}.log"
ind_curve="${CURVE_DIR}/${ind_corner_id}.csv"

if [[ -n "${SG13G2_IND_MODEL_LIB:-}" && -f "${SG13G2_IND_MODEL_LIB}" ]]; then
  # ngspice runs from a scratch directory, so the .include must be absolute;
  # but a committed record must not carry this machine's directory layout, so
  # what gets RECORDED is the repo-relative path when the model lives in this
  # repository, plus its content sha256 -- the same "state the digest of every
  # model library the run loaded" rule sim/README.md applies to the PDK libs.
  ind_model_abs="$(cd "$(dirname "${SG13G2_IND_MODEL_LIB}")" && pwd)/$(basename "${SG13G2_IND_MODEL_LIB}")"
  ind_model_id="${ind_model_abs}"
  case "${ind_model_abs}" in
    "${REPO_ROOT}"/*) ind_model_id="${ind_model_abs#"${REPO_ROOT}"/}" ;;
  esac
  ind_model_sha="$(sha256_of "${ind_model_abs}")"
  ind_model_line=".include \"${ind_model_abs}\""
  ind_model_comment="${ind_model_id} sha256 ${ind_model_sha} (via \$SG13G2_IND_MODEL_LIB)"
  ind_model_source="${ind_model_id} sha256=${ind_model_sha}"
else
  ind_model_line="* (no inductor model library: \$SG13G2_IND_MODEL_LIB unset or missing, and IHP-Open-PDK v0.3.0 ships none)"
  ind_model_comment="NONE -- \$SG13G2_IND_MODEL_LIB unset and the PDK ships no ngspice inductor model"
  ind_model_source="none"
  ind_model_id=""
fi

sed \
  -e "s|@@MODELS_DIR@@|${SG13G2_NGSPICE_MODELS}|g" \
  -e "s|@@TEMP_C@@|27|g" \
  -e "s|@@CORNER_ID@@|${ind_corner_id}|g" \
  -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
  -e "s|@@FMIN@@|${FMIN}|g" \
  -e "s|@@FMAX@@|${FMAX}|g" \
  -e "s|@@NDEC_MEAS@@|${NDEC_MEAS}|g" \
  -e "s|@@NDEC_CURVE@@|${NDEC_CURVE}|g" \
  -e "s|@@CURVE_CSV@@|${ind_curve}|g" \
  -e "s|@@IND_MODEL_LINE@@|${ind_model_line}|g" \
  -e "s|@@IND_MODEL_LINE_COMMENT@@|${ind_model_comment}|g" \
  "${EXPERIMENT_DIR}/testbench/tb_inductor_zscan.spice.tmpl" > "${ind_netlist}"

ind_rc=0
( cd "${WORKDIR}" && ngspice -b "${ind_netlist}" ) > "${ind_log}" 2>&1 || ind_rc=$?
ind_model_absent=0
if grep -qiE "unknown subckt" "${ind_log}"; then ind_model_absent=1; fi
echo "[${ind_corner_id}] ngspice rc=${ind_rc} model_absent=${ind_model_absent}"

echo "geometry,w_um,s_um,d_um,nr_r,model_source,status,srf_hz,l_1ghz_h,l_5ghz_h,l_10ghz_h,q_1ghz,q_5ghz,q_10ghz" > "${IND_CSV}"
# <key>:<w_um>:<s_um>:<d_um>:<nr_r>, matching the instances in the template.
# Same bash-3.2 rationale as DEV_SPECS above.
IND_SPECS=(
  "p1:8.22:3.29:47.65:1"
  "p13:6.10:3.29:110.11:5"
  "p11:8.22:3.74:141.975:4"
)
for spec in "${IND_SPECS[@]}"; do
  IFS=: read -r key ind_w ind_s ind_d ind_n <<EOF
${spec}
EOF
  if [[ ${ind_model_absent} -eq 1 ]]; then
    echo "${key},${ind_w},${ind_s},${ind_d},${ind_n},none,MODEL_ABSENT,,,,,,," >> "${IND_CSV}"
  else
    srf="$(meas_value "${ind_log}" "srf_${key}")"
    l1="$(meas_value "${ind_log}" "l_${key}_1g")"
    l5="$(meas_value "${ind_log}" "l_${key}_5g")"
    l10="$(meas_value "${ind_log}" "l_${key}_10g")"
    q1="$(meas_value "${ind_log}" "q_${key}_1g")"
    q5="$(meas_value "${ind_log}" "q_${key}_5g")"
    q10="$(meas_value "${ind_log}" "q_${key}_10g")"
    st=FAIL
    if [[ ${ind_rc} -eq 0 && -n "${l1}" ]]; then st=PASS; fi
    echo "${key},${ind_w},${ind_s},${ind_d},${ind_n},${ind_model_source},${st},${srf},${l1},${l5},${l10},${q1},${q5},${q10}" >> "${IND_CSV}"
  fi
done

# ------------------------------------------------------------------- record
{
  echo "# Record ${RECORD_ID}"
  echo
  echo "- **Experiment**: tank-characterization"
  echo "- **Claim**: the L / Q / SRF behaviour of the passive devices an LC tank"
  echo "  on this PDK would be built from, measured over a deliberately wide"
  echo "  candidate band (${FMIN} Hz .. ${FMAX} Hz) rather than at one assumed"
  echo "  centre frequency, because the target band is not chosen yet"
  echo "  (\`spec/target-spec.md\` row 1). This record ratifies NO spec row."
  echo "- **Devices measured**: \`cap_cmim\` and \`cap_rfcmim\` from"
  echo "  \`capacitors_mod.lib\`, three square geometries each (20, 35, 50 um)."
  echo "- **Device NOT measured**: the SG13G2 spiral inductor. IHP-Open-PDK"
  echo "  v0.3.0 ships no ngspice-simulatable inductor model, so the L half of"
  echo "  the tank could not be characterized in this flow at all. The probe was"
  echo "  run anyway and its failure recorded -- see"
  echo "  \`records/${RECORD_ID}-inductor.csv\`, the raw log at"
  echo "  \`corners/${RECORD_ID}/${ind_corner_id}.log\`, and README.md"
  echo "  \"The inductor gap\"."
  echo "- **Method**: 1 A AC current injection into each device's hot node, so"
  echo "  V(node) = Z(f). Then Ceff = Im(1/Z)/(2*pi*f), Q = |Im(1/Z)|/Re(1/Z),"
  echo "  and SRF = the frequency at which Im(Z) crosses zero. Scalars come from"
  echo "  a ${NDEC_MEAS} point/decade pass; the committed curves are a"
  echo "  ${NDEC_CURVE} point/decade pass over the same range."
  echo "- **Method validation**: every corner also carries an ideal R-L-C"
  echo "  reference network whose Leff, Q and SRF are known in closed form. The"
  echo "  same extraction arithmetic is applied to it and compared against the"
  echo "  algebra to ${METHOD_TOL_PCT} %; results in"
  echo "  \`records/${RECORD_ID}-method-check.csv\`."
  echo "- **PDK**: \`${PDK}\` at \`${PDK_ROOT}\` -- pinned release in"
  echo "  \`sim/pdk.json\` (IHP-Open-PDK v0.3.0). Loaded model libraries, by"
  echo "  content digest, so a reader can confirm their install matches:"
  echo "  - \`cornerCAP.lib\` sha256 \`${CORNERCAP_SHA}\`"
  echo "  - \`capacitors_mod.lib\` sha256 \`${CAPMOD_SHA}\`"
  echo "- **ngspice**: \`${NGSPICE_VERSION}\`"
  echo "- **Corner matrix run**: MIM process section {cap_typ, cap_bcs, cap_wcs}"
  echo "  x temperature {${TEMPS[*]}} C x bias {${VBIASES[*]}} V = ${total}"
  echo "  simulation points, each covering 6 device instances = $((total * 6))"
  echo "  device rows. The V axis is present to MEASURE, not assume, that the"
  echo "  MIM models are bias-independent."
  echo "- **Result**: ${passed}/${total} simulation points PASS (ngspice exit 0,"
  echo "  no model-load error, and the known-answer method check within"
  echo "  ${METHOD_TOL_PCT} %)."
  if [[ ${method_fail} -gt 0 ]]; then
    echo "- **Method-check failures**: ${method_fail} point(s) exceeded the"
    echo "  ${METHOD_TOL_PCT} % tolerance -- treat every number in this record as"
    echo "  suspect until that is explained."
  fi
  if [[ ${#failed_points[@]} -gt 0 ]]; then
    echo "- **Failed device rows**: ${failed_points[*]}"
  fi
  if [[ ${ind_model_absent} -eq 1 ]]; then
    echo "- **Inductor probe**: MODEL_ABSENT (expected on a stock v0.3.0"
    echo "  install: IHP-Open-PDK v0.3.0 ships no ngspice inductor model)."
  else
    echo "- **Inductor probe**: ran against \`${ind_model_source}\`, supplied"
    echo "  through \`\$SG13G2_IND_MODEL_LIB\`. That model is NOT part of the PDK"
    echo "  -- it is one of the two non-PDK models sim/inductor-model/ ships"
    echo "  (analytic screening, or an openEMS extraction fit -- see that"
    echo "  file's own header for which); its accuracy limits are stated in"
    echo "  its own header and they propagate into every L/Q/SRF number in"
    echo "  \`records/${RECORD_ID}-inductor.csv\`. Read them before using one."
  fi
  echo "- **Links**:"
  echo "  - Templates: \`testbench/tb_mimcap_zscan.spice.tmpl\`,"
  echo "    \`testbench/tb_inductor_zscan.spice.tmpl\`"
  echo "  - Per-point generated netlists: \`netlist-snapshots/${RECORD_ID}/\`"
  echo "  - Per-point raw ngspice logs: \`corners/${RECORD_ID}/\`"
  echo "  - Scalar summary: \`records/${RECORD_ID}.csv\`"
  echo "  - Curves vs frequency: \`records/${RECORD_ID}-curves/\`"
  echo "  - Method known-answer check: \`records/${RECORD_ID}-method-check.csv\`"
  echo "  - Inductor probe outcome: \`records/${RECORD_ID}-inductor.csv\`"
  if [[ ${ind_model_absent} -eq 1 ]]; then
    echo "- **Reproduce**: \`sim/tank-characterization/run_pvt_sweep.sh\` (no"
    echo "  arguments, no preceding steps) against the pinned PDK."
  else
    echo "- **Reproduce**: against the pinned PDK, with the inductor model"
    echo "  library above on \`\$SG13G2_IND_MODEL_LIB\`:"
    echo
    echo "  \`\`\`bash"
    echo "  export SG13G2_IND_MODEL_LIB=\$PWD/${ind_model_id}"
    echo "  sim/tank-characterization/run_pvt_sweep.sh"
    echo "  \`\`\`"
    echo
  fi
  echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MD_OUT}"

echo
echo "record        : ${RECORD_ID}"
echo "points        : ${passed}/${total} PASS"
echo "method check  : $(( total - method_fail ))/${total} within ${METHOD_TOL_PCT}%"
echo "inductor probe: $( [[ ${ind_model_absent} -eq 1 ]] && echo MODEL_ABSENT || echo ran )"
echo "written       : ${MD_OUT#"${REPO_ROOT}"/}"

if [[ ${passed} -ne ${total} ]]; then
  echo "error: ${#failed_points[@]} device row(s) and/or $(( total - passed )) simulation point(s) did not pass." >&2
  exit 1
fi
