#!/usr/bin/env bash
# Cold-start invocation:  sim/oscillator-core/run_validity_check.sh
#
# PDK-free fault-injection check of the bench's MEASUREMENT-VALIDITY gate
# (issue #83). It sources the real osc_bench.sh, replaces only the renderer
# and the simulator with stubs (ngspice is never started), and has the stub
# leave a chosen set of wrdata traces in the scratch dir. The real extractors
# and the real osc_simulate_point then run over them. Asserted per case:
#   * a missing / empty / malformed / non-finite / truncated required trace
#     gives meas_status=INVALID with the faulty trace named in meas_reason;
#   * the derived values (power, common-mode, tail) are nan, never 0;
#   * the simulator status stays separate (clean run + valid vdiff stays
#     PASS; a flat vdiff stays an honest NOSC; a simulator failure stays FAIL);
#   * the complete valid trace set gives VALID, a nonzero power, and PASS.
#   * row 7 (issue #112): the appended columns carry the SAMPLED tail minimum
#     (not the mean), the actual rail from the vdd trace and the DR-004 (e)
#     VCE_max at their closed-form values; a missing/invalid vtail or vdd
#     trace leaves them nan (never 0) and makes the point INVALID.
# Grades no spec row and writes nothing outside a mktemp dir. Needs only bash
# and awk. Exit status is nonzero if any assertion fails.
set -euo pipefail

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"
# shellcheck source=osc_bench.sh
source "${EXPERIMENT_DIR}/osc_bench.sh"

T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT
WORKDIR="${T}/work"; NETLIST_DIR="${T}/net"; LOG_DIR="${T}/log"; CSV_OUT="${T}/out.csv"
mkdir -p "${WORKDIR}" "${NETLIST_DIR}" "${LOG_DIR}"
# shellcheck disable=SC2034 # fixture record id; reserved for sourced helpers, behavior-neutral
RECORD_ID="fixture"

# ---- stubs: no netlist, no simulator --------------------------------------
osc_render() { : > "$2"; }
FIXTURE_RC=0
osc_run_ngspice() { : > "$2"; echo "rc=${FIXTURE_RC} model_error=0"; }
# One fixture trace: <name> <kind>. 5 GHz, 0..5 ns, 1 ps steps, mean 1.0.
gen() {
  local path="${WORKDIR}/tr_c_$1" kind="$2" amp="${3:-0.2}"
  case "${kind}" in
    ok|flat)
      [[ "${kind}" == flat ]] && amp=0
      awk -v a="${amp}" 'BEGIN { for (i = 0; i <= 5000; i++) { t = i * 1e-12
        printf "%.6e %.6e\n", t, 1.0 + a * sin(6.283185307179586 * 5e9 * t) } }' > "${path}" ;;
    missing) rm -f "${path}" ;;
    empty) : > "${path}" ;;
    malformed) printf '0.0 1.0\n1e-12 oops\n2e-12 1.0\n' > "${path}" ;;
    short) printf '0.0\n1e-12\n' > "${path}" ;;
    nan) awk 'BEGIN { for (i = 0; i <= 5000; i++) printf "%.6e %s\n", i*1e-12, (i == 4000 ? "-nan(0x8000000000000)" : "1.0") }' > "${path}" ;;
    inf) awk 'BEGIN { for (i = 0; i <= 5000; i++) printf "%.6e %s\n", i*1e-12, (i == 4000 ? "inf" : "1.0") }' > "${path}" ;;
    truncated) awk 'BEGIN { for (i = 0; i <= 3000; i++) printf "%.6e %.6e\n", i*1e-12, 1.0 + 0.2*sin(6.283185307179586*5e9*i*1e-12) }' > "${path}" ;;
  esac
}
# Sub-trace carrying a constant supply current (negated by the real deck).
gen_isup() { awk 'BEGIN { for (i = 0; i <= 5000; i++) printf "%.6e %.6e\n", i*1e-12, 2.0e-3 }' > "${WORKDIR}/tr_c_isup"; }
# The rail: a constant 3.3 V, as the netlist's ideal VSUP gives.
gen_vdd() { awk 'BEGIN { for (i = 0; i <= 5000; i++) printf "%.6e %.6e\n", i*1e-12, 3.3 }' > "${WORKDIR}/tr_c_vdd"; }
near() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(a != "nan" && d <= t) }'; }

fails=0
# case <label> <vdiff> <vcm> <vtail> <isup> <rc> <want_status> <want_meas> <want_reason_substr>
run_case() {
  local label="$1" vd="$2" vc="$3" vt="$4" is="$5" rc="$6" ws="$7" wm="$8" wr="$9" vv="${10:-ok}"
  rm -f "${WORKDIR}"/tr_c_*
  gen vdiff "${vd}"; gen vcm "${vc}" 0.05; gen vtail "${vt}" 0.05
  if [[ "${is}" == ok ]]; then gen_isup; else gen isup "${is}"; fi
  if [[ "${vv}" == ok ]]; then gen_vdd; else gen vdd "${vv}"; fi
  FIXTURE_RC="${rc}"; : > "${CSV_OUT}"
  osc_simulate_point c m c h 27 1.65 "${OSC_TMAX}" >/dev/null || true
  local row; row="$(tail -1 "${CSV_OUT}")"
  [[ -n "${SHOW:-}" ]] && echo "$row"
  local st mv rs p cm ft
  st="$(cut -d, -f8 <<<"${row}")";  p="$(cut -d, -f27 <<<"${row}")"
  mv="$(cut -d, -f28 <<<"${row}")"; rs="$(cut -d, -f29 <<<"${row}")"
  cm="$(cut -d, -f16 <<<"${row}")"; ft="$(cut -d, -f20 <<<"${row}")"
  local vtm vdd vce nf
  vtm="$(cut -d, -f30 <<<"${row}")"; vdd="$(cut -d, -f35 <<<"${row}")"
  vce="$(cut -d, -f36 <<<"${row}")"; nf="$(awk -F, '{ print NF }' <<<"${row}")"
  local bad=""
  [[ "${nf}" == 37 ]] || bad="${bad} columns=${nf}(want 37)"
  [[ "${st}" == "${ws}" ]] || bad="${bad} status=${st}(want ${ws})"
  [[ "${mv}" == "${wm}" ]] || bad="${bad} meas=${mv}(want ${wm})"
  [[ -z "${wr}" || "${rs}" == *"${wr}"* ]] || bad="${bad} reason=${rs}(want *${wr}*)"
  if [[ "${wm}" == INVALID ]]; then
    case "${wr}" in
      isup:*) [[ "${p}" == nan ]] || bad="${bad} p_core_ls=${p}(want nan)" ;;
      vcm:*)  [[ "${cm}" == nan ]] || bad="${bad} vpp_cm=${cm}(want nan)" ;;
      vtail:*) [[ "${ft}" == nan && "${vtm}" == nan && "${vce}" == nan ]] \
                 || bad="${bad} f_tail/v_tail_min/vce=${ft}/${vtm}/${vce}(want nan)" ;;
      vdd:*)  [[ "${vdd}" == nan && "${vce}" == nan ]] || bad="${bad} vdd/vce=${vdd}/${vce}(want nan)" ;;
    esac
  else
    awk -v p="${p}" 'BEGIN { exit (p > 0) ? 0 : 1 }' || bad="${bad} p_core_ls=${p}(want >0)"
  fi
  # Closed form for a VALID oscillating point: tail mean 1.0, amplitude 0.05
  # -> sampled minimum 0.95 (the mean, 1.0, must NOT be reported); vdd 3.3;
  # vpp_diff 0.4 -> VCE_max = 3.3 + 0.4/4 - 0.95 = 2.45 V.
  if [[ "${wm}" == VALID && "${ws}" == PASS ]]; then
    near "${vtm}" 0.95 1e-4 || bad="${bad} v_tail_min=${vtm}(want 0.95)"
    near "${vdd}" 3.3 1e-9  || bad="${bad} vdd=${vdd}(want 3.3)"
    near "${vce}" 2.45 2e-4 || bad="${bad} vce_max=${vce}(want 2.45)"
  fi
  if [[ -n "${bad}" ]]; then echo "FAIL ${label}:${bad}"; fails=$((fails + 1))
  else echo "ok   ${label}"; fi
}

run_case valid-complete           ok ok ok ok        0 PASS   VALID   ""
run_case isup-missing             ok ok ok missing   0 PASS   INVALID isup:missing
run_case isup-empty               ok ok ok empty     0 PASS   INVALID isup:empty
run_case isup-malformed           ok ok ok malformed 0 PASS   INVALID isup:malformed
run_case isup-short-lines         ok ok ok short     0 PASS   INVALID isup:malformed
run_case isup-nan                 ok ok ok nan       0 PASS   INVALID isup:nonfinite
run_case isup-inf                 ok ok ok inf       0 PASS   INVALID isup:nonfinite
run_case isup-truncated           ok ok ok truncated 0 PASS   INVALID isup:truncated
run_case vcm-missing              ok missing ok ok   0 PASS   INVALID vcm:missing
run_case vcm-truncated            ok truncated ok ok 0 PASS   INVALID vcm:truncated
run_case vtail-missing            ok ok missing ok   0 PASS   INVALID vtail:missing
run_case vtail-nan                ok ok nan ok       0 PASS   INVALID vtail:nonfinite
run_case vtail-truncated           ok ok truncated ok 0 PASS   INVALID vtail:truncated
run_case vdd-missing               ok ok ok ok        0 PASS   INVALID vdd:missing   missing
run_case vdd-truncated             ok ok ok ok        0 PASS   INVALID vdd:truncated truncated
run_case vdiff-missing-clean-run  missing ok ok ok   0 NODATA INVALID vdiff:missing
run_case vdiff-truncated          truncated ok ok ok 0 NODATA INVALID vdiff:truncated
run_case honest-nosc-valid-traces flat flat flat ok  0 NOSC   VALID   ""
run_case simulator-failure        ok ok ok ok        1 FAIL   VALID   ""

if [[ "${fails}" -ne 0 ]]; then echo "${fails} case(s) failed" >&2; exit 1; fi
echo "all cases passed"
