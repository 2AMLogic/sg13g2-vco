#!/usr/bin/env bash
# Cold-start invocation (this is the whole thing -- there are no hidden
# manual steps; the OSDI build below runs automatically):
#
#   sim/varactor-characterization/run_varactor_sweep.sh
#
# Optionally, if the PDK is not installed under one of the prefixes sim/env.sh
# probes (/usr/share/pdk, /usr/local/share/pdk, ~/share/pdk, ~/.ciel, ~/.volare):
#
#   export PDK_ROOT=/path/to/ihp-open-pdk   # parent dir containing ihp-sg13g2/
#   export PDK=ihp-sg13g2
#
# Requires: ngspice and curl on PATH, a bash, and an IHP-Open-PDK v0.3.0
# install (pinned in sim/pdk.json). UNLIKE tank-characterization, this
# experiment DOES need a build step: sg13_hv_svaricap is a Verilog-A
# ("mosvar") compact model, only instantiable via an OSDI-compiled shared
# library. This script calls sim/tools/build-osdi.sh itself (per
# sim/README.md rule 1, "if a run needs a build step, that step belongs
# INSIDE the run script") -- the first invocation fetches a checksum-pinned
# OpenVAF-Reloaded release (~60 MB, cached under
# ${SG13G2_TOOLS_CACHE:-~/.cache/sg13g2-vco}) and compiles mosvar.osdi from
# the PDK's own Verilog-A source; every later invocation just verifies the
# result still loads and skips straight to the sweep.
#
# WHAT IT DOES
# ------------
# Sweeps sg13_hv_svaricap (the MOS accumulation-mode varactor) and the two
# junction-diode tuning candidates (dantenna, dpantenna) over control
# voltage x process corner x temperature, extracting C(V), dC/dV (the Kvco
# kernel) and Q(V,f) at four scalar frequencies for four device geometries
# each. Everything it writes is APPEND-ONLY evidence under this directory,
# keyed by a record ID minted fresh on every run:
#
#   netlist-snapshots/<record-id>/<corner-id>.spice   exact netlist simulated
#   corners/<record-id>/<corner-id>.log               raw ngspice batch output
#   records/<record-id>-curves/<corner-id>.csv        C/Q vs frequency
#   records/<record-id>.csv                           scalar summary, one row
#                                                      per corner x device
#   records/<record-id>-kvco.csv                       Cmax/Cmin/dC/dV per
#                                                      device x corner x temp,
#                                                      core and full domains
#   records/<record-id>-method-check.csv              known-answer check of
#                                                      the extraction arithmetic
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
if [[ -z "${SG13G2_NGSPICE_MODELS:-}" || ! -f "${SG13G2_NGSPICE_MODELS}/cornerMOShv.lib" || ! -f "${SG13G2_NGSPICE_MODELS}/cornerDIO.lib" ]]; then
  echo "error: could not resolve the SG13G2 ngspice model libraries." >&2
  echo "       expected \$PDK_ROOT/\$PDK/libs.tech/ngspice/models/{cornerMOShv,cornerDIO}.lib" >&2
  echo "       see the message from sim/env.sh above, and sim/pdk.json." >&2
  exit 1
fi

# --------------------------------------------------------------- OSDI build
# The build step this study needs and tank-characterization did not (see the
# header comment). Idempotent: build-osdi.sh checks first and only compiles
# if mosvar.osdi is missing or fails to load.
echo "sg13g2: ensuring mosvar.osdi is built and loadable ..."
"${SIM_DIR}/tools/build-osdi.sh"
OSDI_MOSVAR="${SG13G2_OSDI_DIR}/mosvar.osdi"
if [[ ! -f "${OSDI_MOSVAR}" ]]; then
  echo "error: sim/tools/build-osdi.sh reported success but ${OSDI_MOSVAR} is missing." >&2
  exit 1
fi

NGSPICE_VERSION="$(detect_ngspice_version)"

CORNERMOSHV_SHA="$(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerMOShv.lib")"
SVARICAP_SHA="$(sha256_of "${SG13G2_NGSPICE_MODELS}/sg13g2_svaricaphv_mod.lib")"
CORNERDIO_SHA="$(sha256_of "${SG13G2_NGSPICE_MODELS}/cornerDIO.lib")"
DIODES_SHA="$(sha256_of "${SG13G2_NGSPICE_MODELS}/diodes.lib")"
MOSVAR_VA_SHA="$(sha256_of "${PDK_ROOT}/${PDK}/libs.tech/verilog-a/mosvar/mosvar.va")"
MOSVAR_OSDI_SHA="$(sha256_of "${OSDI_MOSVAR}")"

RECORD_ID="$(mint_record_id "${REPO_ROOT}")"

NETLIST_DIR="${EXPERIMENT_DIR}/netlist-snapshots/${RECORD_ID}"
LOG_DIR="${EXPERIMENT_DIR}/corners/${RECORD_ID}"
CURVE_DIR="${EXPERIMENT_DIR}/records/${RECORD_ID}-curves"
CSV_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.csv"
METHOD_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-method-check.csv"
KVCO_CSV="${EXPERIMENT_DIR}/records/${RECORD_ID}-kvco.csv"
MD_OUT="${EXPERIMENT_DIR}/records/${RECORD_ID}.md"
mkdir -p "${NETLIST_DIR}" "${LOG_DIR}" "${CURVE_DIR}"

# ngspice must run from a directory holding this experiment's own .spiceinit,
# so a cold-start run does not depend on whether the PDK's install.py ever
# symlinked one into $HOME.
make_scratch_workdir "sg13g2-varactor"

# --------------------------------------------------------------- sweep ranges
# Same band as tank-characterization, for the same reason (the target band is
# not chosen yet -- spec/target-spec.md row 1 is blank): sweep wide rather
# than centre on an assumed frequency.
FMIN=1e8
FMAX=3e11
NDEC_MEAS=500     # dense pass: scalar .meas extractions
NDEC_CURVE=50     # coarse pass: the committed curve CSVs

# Control-voltage grid. ONE monotonic list spans both domains issue #18 asks
# for -- the 1.2 V core range and the 3.3 V HV range -- rather than two
# separate sweeps, because every point above 1.2 V is *also* a point a
# report on "what the 1.2 V-only range buys" needs as its baseline. The first
# N_CORE_POINTS entries (0.0 .. 1.2 V) are exactly the core-only subset;
# README.md "Why one V-list, not two" states this design choice and its
# consequence (the two domains share every point below 1.2 V, so a "core"
# finding and a "full 3.3 V" finding are never independently re-simulated,
# only re-sliced from the same run).
VCTRL_LIST=(0.0 0.3 0.6 0.9 1.2 1.8 2.4 3.0 3.3)
N_CORE_POINTS=5   # VCTRL_LIST[0..4] = 0.0 .. 1.2 V inclusive (the core domain)

# PVT grid.
#   MOS: cornerMOShv.lib's five non-statistical sections. tt is the all-1.0
#        baseline; ss/ff/sf/fs all carry DISTINCT
#        sg13g2_hv_svaricap_{vfbo,toxo,dlq,dwq} values (verified by reading
#        the file -- sf and fs are NOT ss/ff duplicates for this device, so
#        all five are swept, not just tt/ss/ff as issue #18 provisionally
#        suggested). The *_mismatch/*_stat sections are omitted for the same
#        Monte-Carlo-harness reason tank-characterization omits cornerCAP's.
#   DIO: cornerDIO.lib's three non-statistical sections (dio_tt/ss/ff).
#   T:   -40 / 27 / 125 C, the same span tank-characterization and the
#        sibling blocks in this catalog use.
MOS_SECTIONS=(mos_tt mos_ss mos_ff mos_sf mos_fs)
MOS_LABELS=(tt ss ff sf fs)
DIO_SECTIONS=(dio_tt dio_ss dio_ff)
DIO_LABELS=(tt ss ff)
TEMPS=(-40 27 125)

# MOS device instance table: <key>:<l_um>:<w_um>:<nx>:<label>. See
# testbench/tb_mos_varactor_vscan.spice.tmpl's header for the geometry
# rationale (spans the model's OWN l/w/Nx range, not the "few um" the issue
# informally assumed).
MOS_DEV_SPECS=(
  "small:0.300:3.74:1:mos_small (l floor, w floor, Nx=1)"
  "mid:0.550:6.00:4:mos_mid"
  "large:0.800:9.74:10:mos_large (l ceiling, w ceiling, Nx ceiling)"
  "xlarge:0.800:9.74:40:mos_xlarge (4x mos_large cells in parallel)"
)

# Diode device instance table: <key>:<model>:<l_um>:<w_um>:<area_um2>.
DIODE_DEV_SPECS=(
  "dasm:dantenna:2:2:4"
  "dalg:dantenna:20:20:400"
  "dpsm:dpantenna:2:2:4"
  "dplg:dpantenna:20:20:400"
)

echo "device_class,device_key,corner_label,temp_c,vctrl_v,status,srf_hz,c_1ghz_f,c_5ghz_f,c_10ghz_f,c_20ghz_f,q_1ghz,q_5ghz,q_10ghz,q_20ghz" > "${CSV_OUT}"
echo "corner_label,temp_c,vctrl_v,quantity,simulated,closed_form,rel_err_pct,tol_pct,status" > "${METHOD_CSV}"
echo "device_class,device_key,corner_label,temp_c,domain,v_min,v_max,n_points,c_at_vmin_1ghz_f,c_at_vmax_1ghz_f,cmax_1ghz_f,cmin_1ghz_f,cmax_over_cmin,dcdv_peak_f_per_v,dcdv_min_f_per_v" > "${KVCO_CSV}"

total=0
passed=0
failed_points=()
method_fail=0
METHOD_TOL_PCT=0.1

# kvco_stats <space-separated V list> <space-separated C(1GHz) list, same order>
# Prints "cmax cmin ratio dcdv_peak dcdv_min" (F, F, dimensionless, F/V, F/V).
# dcdv_peak/min are the largest/smallest |dC/dV| finite differences between
# CONSECUTIVE swept V points, signed. A group of fewer than 2 points prints
# "nan" for both.
kvco_stats() {
  awk -v vs="$1" -v cs="$2" 'BEGIN {
    n = split(vs, V, " "); split(cs, C, " ");
    cmax = C[1]; cmin = C[1];
    for (i = 1; i <= n; i++) { if (C[i] > cmax) cmax = C[i]; if (C[i] < cmin) cmin = C[i]; }
    ratio = (cmin > 0) ? cmax/cmin : "nan";
    if (n < 2) { printf "%.6e %.6e %s nan nan\n", cmax, cmin, ratio; exit }
    dpeak = ""; dmin = "";
    for (i = 1; i < n; i++) {
      dv = V[i+1] - V[i]; dc = C[i+1] - C[i];
      if (dv == 0) continue;
      d = dc/dv; ad = (d < 0) ? -d : d;
      if (dpeak == "" || ad > adpeak) { adpeak = ad; dpeak = d }
      if (dmin == "" || ad < admin)  { admin  = ad; dmin  = d }
    }
    printf "%.6e %.6e %s %.6e %.6e\n", cmax, cmin, ratio, dpeak, dmin;
  }'
}

# ---------------------------------------------------------------- MOS sweep
for i in "${!MOS_SECTIONS[@]}"; do
  section="${MOS_SECTIONS[$i]}"
  label="${MOS_LABELS[$i]}"
  for temp in "${TEMPS[@]}"; do
    C_small=(); C_mid=(); C_large=(); C_xlarge=()

    for vctrl in "${VCTRL_LIST[@]}"; do
      corner_id="svaricap_mos_${label}_${temp}c_${vctrl}v"
      netlist="${NETLIST_DIR}/${corner_id}.spice"
      log="${LOG_DIR}/${corner_id}.log"
      curve="${CURVE_DIR}/${corner_id}.csv"
      total=$((total + 1))

      sed \
        -e "s|@@MODELS_DIR@@|${SG13G2_NGSPICE_MODELS}|g" \
        -e "s|@@OSDI_MOSVAR@@|${OSDI_MOSVAR}|g" \
        -e "s|@@CORNER_SECTION@@|${section}|g" \
        -e "s|@@TEMP_C@@|${temp}|g" \
        -e "s|@@VCTRL@@|${vctrl}|g" \
        -e "s|@@CORNER_ID@@|${corner_id}|g" \
        -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
        -e "s|@@FMIN@@|${FMIN}|g" \
        -e "s|@@FMAX@@|${FMAX}|g" \
        -e "s|@@NDEC_MEAS@@|${NDEC_MEAS}|g" \
        -e "s|@@NDEC_CURVE@@|${NDEC_CURVE}|g" \
        -e "s|@@CURVE_CSV@@|${curve}|g" \
        "${EXPERIMENT_DIR}/testbench/tb_mos_varactor_vscan.spice.tmpl" > "${netlist}"

      rc=0
      ( cd "${WORKDIR}" && ngspice -b "${netlist}" ) > "${log}" 2>&1 || rc=$?

      model_error=0
      if grep -qiE "unknown subckt|could not find|can't find|no such (parameter|model)|Unable to find definition of model" "${log}"; then
        model_error=1
      fi
      echo "[${corner_id}] ngspice rc=${rc} model_error=${model_error}"

      for spec in "${MOS_DEV_SPECS[@]}"; do
        key="${spec%%:*}"
        srf="$(meas_value "${log}" "srf_${key}")"
        c1="$(meas_value  "${log}" "c_${key}_1g")"
        c5="$(meas_value  "${log}" "c_${key}_5g")"
        c10="$(meas_value "${log}" "c_${key}_10g")"
        c20="$(meas_value "${log}" "c_${key}_20g")"
        q1="$(meas_value  "${log}" "q_${key}_1g")"
        q5="$(meas_value  "${log}" "q_${key}_5g")"
        q10="$(meas_value "${log}" "q_${key}_10g")"
        q20="$(meas_value "${log}" "q_${key}_20g")"

        # sg13_hv_svaricap has no plate/feed inductance -- a missing SRF is
        # the EXPECTED, physically meaningful answer at every point, not a
        # measurement miss. See the testbench template header.
        srf_field="${srf}"
        [[ -z "${srf}" ]] && srf_field="none"

        status=FAIL
        if [[ ${rc} -eq 0 && ${model_error} -eq 0 && -n "${c1}" && -n "${q1}" ]]; then
          status=PASS
        fi
        echo "mos,${key},${label},${temp},${vctrl},${status},${srf_field},${c1},${c5},${c10},${c20},${q1},${q5},${q10},${q20}" >> "${CSV_OUT}"
        if [[ "${status}" == "FAIL" ]]; then failed_points+=("${corner_id}/${key}"); fi

        case "${key}" in
          small)  C_small+=("${c1:-nan}") ;;
          mid)    C_mid+=("${c1:-nan}") ;;
          large)  C_large+=("${c1:-nan}") ;;
          xlarge) C_xlarge+=("${c1:-nan}") ;;
        esac
      done

      point_status="$(method_check_point "${label}" "${temp}" "${vctrl}" "${log}" "${METHOD_CSV}" "${METHOD_TOL_PCT}")"
      if [[ "${point_status}" != "PASS" ]]; then method_fail=$((method_fail + 1)); fi

      if [[ ${rc} -eq 0 && ${model_error} -eq 0 ]]; then passed=$((passed + 1)); fi
    done

    # ---- Kvco stats: full (all N points, 0..3.3 V) and core (first
    # N_CORE_POINTS, 0..1.2 V). Last-index lookups use explicit
    # count-minus-one arithmetic rather than bash's `array[-1]`, which needs
    # bash 4.3+ and macOS still ships 3.2 as /bin/bash (see lib.sh's header).
    n_full=${#VCTRL_LIST[@]}
    last_full=$((n_full - 1))
    last_core=$((N_CORE_POINTS - 1))
    V_FULL="${VCTRL_LIST[*]}"
    V_CORE="${VCTRL_LIST[*]:0:${N_CORE_POINTS}}"
    vmin_full="${VCTRL_LIST[0]}"; vmax_full="${VCTRL_LIST[${last_full}]}"
    vmin_core="${VCTRL_LIST[0]}"; vmax_core="${VCTRL_LIST[${last_core}]}"
    for pair in "small:${C_small[*]}" "mid:${C_mid[*]}" "large:${C_large[*]}" "xlarge:${C_xlarge[*]}"; do
      key="${pair%%:*}"
      carr="${pair#*:}"
      # shellcheck disable=SC2206
      carr_a=(${carr})
      c_full="${carr_a[*]}"
      # shellcheck disable=SC2206
      c_core_a=(${carr_a[*]:0:${N_CORE_POINTS}})
      c_core="${c_core_a[*]}"

      read -r cmax cmin ratio dpeak dmin <<EOF
$(kvco_stats "${V_FULL}" "${c_full}")
EOF
      c_at_vmin="${carr_a[0]}"; c_at_vmax="${carr_a[${last_full}]}"
      echo "mos,${key},${label},${temp},full,${vmin_full},${vmax_full},${n_full},${c_at_vmin},${c_at_vmax},${cmax},${cmin},${ratio},${dpeak},${dmin}" >> "${KVCO_CSV}"

      read -r cmax cmin ratio dpeak dmin <<EOF
$(kvco_stats "${V_CORE}" "${c_core}")
EOF
      c_at_vmin="${c_core_a[0]}"; c_at_vmax="${c_core_a[${last_core}]}"
      echo "mos,${key},${label},${temp},core,${vmin_core},${vmax_core},${N_CORE_POINTS},${c_at_vmin},${c_at_vmax},${cmax},${cmin},${ratio},${dpeak},${dmin}" >> "${KVCO_CSV}"
    done
  done
done

# --------------------------------------------------------------- diode sweep
for i in "${!DIO_SECTIONS[@]}"; do
  section="${DIO_SECTIONS[$i]}"
  label="${DIO_LABELS[$i]}"
  for temp in "${TEMPS[@]}"; do
    C_dasm=(); C_dalg=(); C_dpsm=(); C_dplg=()

    for vctrl in "${VCTRL_LIST[@]}"; do
      corner_id="svaricap_dio_${label}_${temp}c_${vctrl}v"
      netlist="${NETLIST_DIR}/${corner_id}.spice"
      log="${LOG_DIR}/${corner_id}.log"
      curve="${CURVE_DIR}/${corner_id}.csv"
      total=$((total + 1))

      sed \
        -e "s|@@MODELS_DIR@@|${SG13G2_NGSPICE_MODELS}|g" \
        -e "s|@@CORNER_SECTION@@|${section}|g" \
        -e "s|@@TEMP_C@@|${temp}|g" \
        -e "s|@@VCTRL@@|${vctrl}|g" \
        -e "s|@@CORNER_ID@@|${corner_id}|g" \
        -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
        -e "s|@@FMIN@@|${FMIN}|g" \
        -e "s|@@FMAX@@|${FMAX}|g" \
        -e "s|@@NDEC_MEAS@@|${NDEC_MEAS}|g" \
        -e "s|@@NDEC_CURVE@@|${NDEC_CURVE}|g" \
        -e "s|@@CURVE_CSV@@|${curve}|g" \
        "${EXPERIMENT_DIR}/testbench/tb_diode_varactor_vscan.spice.tmpl" > "${netlist}"

      rc=0
      ( cd "${WORKDIR}" && ngspice -b "${netlist}" ) > "${log}" 2>&1 || rc=$?

      model_error=0
      if grep -qiE "unknown subckt|could not find|can't find|no such (parameter|model)" "${log}"; then
        model_error=1
      fi
      echo "[${corner_id}] ngspice rc=${rc} model_error=${model_error}"

      for spec in "${DIODE_DEV_SPECS[@]}"; do
        key="${spec%%:*}"
        srf="$(meas_value "${log}" "srf_${key}")"
        c1="$(meas_value  "${log}" "c_${key}_1g")"
        c5="$(meas_value  "${log}" "c_${key}_5g")"
        c10="$(meas_value "${log}" "c_${key}_10g")"
        c20="$(meas_value "${log}" "c_${key}_20g")"
        q1="$(meas_value  "${log}" "q_${key}_1g")"
        q5="$(meas_value  "${log}" "q_${key}_5g")"
        q10="$(meas_value "${log}" "q_${key}_10g")"
        q20="$(meas_value "${log}" "q_${key}_20g")"

        srf_field="${srf}"
        [[ -z "${srf}" ]] && srf_field="none"

        status=FAIL
        if [[ ${rc} -eq 0 && ${model_error} -eq 0 && -n "${c1}" && -n "${q1}" ]]; then
          status=PASS
        fi
        echo "diode,${key},${label},${temp},${vctrl},${status},${srf_field},${c1},${c5},${c10},${c20},${q1},${q5},${q10},${q20}" >> "${CSV_OUT}"
        if [[ "${status}" == "FAIL" ]]; then failed_points+=("${corner_id}/${key}"); fi

        case "${key}" in
          dasm) C_dasm+=("${c1:-nan}") ;;
          dalg) C_dalg+=("${c1:-nan}") ;;
          dpsm) C_dpsm+=("${c1:-nan}") ;;
          dplg) C_dplg+=("${c1:-nan}") ;;
        esac
      done

      point_status="$(method_check_point "${label}" "${temp}" "${vctrl}" "${log}" "${METHOD_CSV}" "${METHOD_TOL_PCT}")"
      if [[ "${point_status}" != "PASS" ]]; then method_fail=$((method_fail + 1)); fi

      if [[ ${rc} -eq 0 && ${model_error} -eq 0 ]]; then passed=$((passed + 1)); fi
    done

    n_full=${#VCTRL_LIST[@]}
    last_full=$((n_full - 1))
    last_core=$((N_CORE_POINTS - 1))
    V_FULL="${VCTRL_LIST[*]}"
    V_CORE="${VCTRL_LIST[*]:0:${N_CORE_POINTS}}"
    vmin_full="${VCTRL_LIST[0]}"; vmax_full="${VCTRL_LIST[${last_full}]}"
    vmin_core="${VCTRL_LIST[0]}"; vmax_core="${VCTRL_LIST[${last_core}]}"
    for pair in "dasm:${C_dasm[*]}" "dalg:${C_dalg[*]}" "dpsm:${C_dpsm[*]}" "dplg:${C_dplg[*]}"; do
      key="${pair%%:*}"
      carr="${pair#*:}"
      # shellcheck disable=SC2206
      carr_a=(${carr})
      c_full="${carr_a[*]}"
      # shellcheck disable=SC2206
      c_core_a=(${carr_a[*]:0:${N_CORE_POINTS}})
      c_core="${c_core_a[*]}"

      read -r cmax cmin ratio dpeak dmin <<EOF
$(kvco_stats "${V_FULL}" "${c_full}")
EOF
      c_at_vmin="${carr_a[0]}"; c_at_vmax="${carr_a[${last_full}]}"
      echo "diode,${key},${label},${temp},full,${vmin_full},${vmax_full},${n_full},${c_at_vmin},${c_at_vmax},${cmax},${cmin},${ratio},${dpeak},${dmin}" >> "${KVCO_CSV}"

      read -r cmax cmin ratio dpeak dmin <<EOF
$(kvco_stats "${V_CORE}" "${c_core}")
EOF
      c_at_vmin="${c_core_a[0]}"; c_at_vmax="${c_core_a[${last_core}]}"
      echo "diode,${key},${label},${temp},core,${vmin_core},${vmax_core},${N_CORE_POINTS},${c_at_vmin},${c_at_vmax},${cmax},${cmin},${ratio},${dpeak},${dmin}" >> "${KVCO_CSV}"
    done
  done
done

# ------------------------------------------------------------------- record
{
  echo "# Record ${RECORD_ID}"
  echo
  echo "- **Experiment**: varactor-characterization"
  echo "- **Claim**: C(V), dC/dV and Q(V,f) of \`sg13_hv_svaricap\` (the MOS"
  echo "  accumulation-mode varactor) and the \`dantenna\`/\`dpantenna\`"
  echo "  junction-diode candidates, over control voltage, at four scalar"
  echo "  frequencies (1/5/10/20 GHz, from a ${FMIN} Hz .. ${FMAX} Hz sweep),"
  echo "  process corner and temperature. This record ratifies NO"
  echo "  \`spec/target-spec.md\` row -- it feeds the tuning-mechanism"
  echo "  decision record that rows 0, 2, 3 and 9 are waiting on."
  echo "- **Devices measured**: \`sg13_hv_svaricap\` at 4 geometries"
  echo "  (mos_small/mid/large/xlarge); \`dantenna\` and \`dpantenna\` at 2"
  echo "  areas each (small 4 um^2, large 400 um^2)."
  echo "- **Control-voltage grid**: ${VCTRL_LIST[*]} V (one monotonic list"
  echo "  covering both the 1.2 V core domain -- the first ${N_CORE_POINTS}"
  echo "  points -- and the full 3.3 V HV domain; see README.md \"Why one"
  echo "  V-list, not two\")."
  echo "- **Method**: 1 A AC current injection into each device's hot node"
  echo "  (gates tied together for the MOS varactor; anode for the diodes),"
  echo "  DC-referenced to 0 V through an ideal 1 H choke, with the control"
  echo "  voltage applied to the well/bn node (MOS) or the cathode (diodes)"
  echo "  through an ideal DC source. Then Ceff = Im(1/Z)/(2*pi*f),"
  echo "  Q = |Im(1/Z)|/Re(1/Z), same as tank-characterization's Z-scan."
  echo "  Scalars come from a ${NDEC_MEAS} point/decade pass; curves are a"
  echo "  ${NDEC_CURVE} point/decade pass over the same range."
  echo "- **Kvco extraction**: dC/dV computed as finite differences between"
  echo "  consecutive swept V points on the 1 GHz capacitance, separately"
  echo "  over the core (0..1.2 V) and full (0..3.3 V) domains --"
  echo "  \`records/${RECORD_ID}-kvco.csv\`."
  echo "- **Method validation**: the same ideal R-L-C reference network as"
  echo "  tank-characterization (Leff, Q, SRF known in closed form), re-run"
  echo "  at every simulated point and checked to ${METHOD_TOL_PCT} %;"
  echo "  results in \`records/${RECORD_ID}-method-check.csv\`."
  echo "- **PDK**: \`${PDK}\` at \`${PDK_ROOT}\` -- pinned release in"
  echo "  \`sim/pdk.json\` (IHP-Open-PDK v0.3.0). Loaded model libraries and"
  echo "  the OSDI binary, by content digest:"
  echo "  - \`cornerMOShv.lib\` sha256 \`${CORNERMOSHV_SHA}\`"
  echo "  - \`sg13g2_svaricaphv_mod.lib\` sha256 \`${SVARICAP_SHA}\`"
  echo "  - \`cornerDIO.lib\` sha256 \`${CORNERDIO_SHA}\`"
  echo "  - \`diodes.lib\` sha256 \`${DIODES_SHA}\`"
  echo "  - \`libs.tech/verilog-a/mosvar/mosvar.va\` (source) sha256 \`${MOSVAR_VA_SHA}\`"
  echo "  - \`libs.tech/ngspice/osdi/mosvar.osdi\` (this run's build) sha256 \`${MOSVAR_OSDI_SHA}\`"
  echo "- **ngspice**: \`${NGSPICE_VERSION}\`"
  echo "- **OSDI toolchain**: OpenVAF-Reloaded, pinned in"
  echo "  \`sim/tools/build-osdi.sh\` -- see \`sim/pdk.json\`'s"
  echo "  \`osdi_toolchain\` block for the compiler tag and sha256."
  echo "- **Corner matrix run**: MOS \`{${MOS_SECTIONS[*]}}\` x temperature"
  echo "  \`{${TEMPS[*]}}\` C x \`{${VCTRL_LIST[*]}}\` V = $(( ${#MOS_SECTIONS[@]} * ${#TEMPS[@]} * ${#VCTRL_LIST[@]} ))"
  echo "  simulation points x 4 geometries; diode"
  echo "  \`{${DIO_SECTIONS[*]}}\` x temperature \`{${TEMPS[*]}}\` C x"
  echo "  \`{${VCTRL_LIST[*]}}\` V = $(( ${#DIO_SECTIONS[@]} * ${#TEMPS[@]} * ${#VCTRL_LIST[@]} ))"
  echo "  simulation points x 4 device/area combinations. Total simulated"
  echo "  points: ${total}."
  echo "- **Result**: ${passed}/${total} simulation points PASS (ngspice"
  echo "  exit 0, no model-load error). Known-answer method check:"
  echo "  $(( total - method_fail ))/${total} points within ${METHOD_TOL_PCT} %"
  echo "  (${method_fail} point(s) exceeded tolerance)."
  if [[ ${#failed_points[@]} -gt 0 ]]; then
    echo "- **Failed device rows**: ${failed_points[*]}"
  fi
  echo "- **Links**:"
  echo "  - Templates: \`testbench/tb_mos_varactor_vscan.spice.tmpl\`,"
  echo "    \`testbench/tb_diode_varactor_vscan.spice.tmpl\`"
  echo "  - Per-point generated netlists: \`netlist-snapshots/${RECORD_ID}/\`"
  echo "  - Per-point raw ngspice logs: \`corners/${RECORD_ID}/\`"
  echo "  - Scalar summary: \`records/${RECORD_ID}.csv\`"
  echo "  - Curves vs frequency: \`records/${RECORD_ID}-curves/\`"
  echo "  - Kvco (Cmax/Cmin/dC/dV) summary: \`records/${RECORD_ID}-kvco.csv\`"
  echo "  - Method known-answer check: \`records/${RECORD_ID}-method-check.csv\`"
  echo "- **Reproduce**: \`sim/varactor-characterization/run_varactor_sweep.sh\`"
  echo "  (no arguments; builds mosvar.osdi itself) against the pinned PDK."
  echo "- **Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${MD_OUT}"

echo
echo "record        : ${RECORD_ID}"
echo "points        : ${passed}/${total} PASS"
echo "method check  : $(( total - method_fail ))/${total} within ${METHOD_TOL_PCT}%"
echo "written       : ${MD_OUT#"${REPO_ROOT}"/}"

if [[ ${passed} -ne ${total} || ${method_fail} -gt 0 ]]; then
  echo "error: ${#failed_points[@]} device row(s) and/or $(( total - passed )) simulation point(s) did not pass, and/or ${method_fail} method-check point(s) exceeded tolerance." >&2
  exit 1
fi
