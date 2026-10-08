#!/usr/bin/env bash
# PDK-free fixture check for osc_emit_tuning's complete-voltage-coverage rule.
# Fakes CSV_OUT with synthetic rows; runs no simulator.
# Usage: tests/test_emit_tuning.sh [path/to/osc_bench.sh]  (default: ../osc_bench.sh)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH="${1:-${HERE}/../osc_bench.sh}"
# shellcheck disable=SC1090
source "${BENCH}"
W="$(mktemp -d)"; trap 'rm -rf "${W}"' EXIT
FAIL=0
FULL="0.0 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0 3.3"
EDGE="0.0 1.65 3.3"

# row <v> <status> <f> [tmax]
row() { echo "c,m,c1,h,27,$1,${4:-${OSC_TMAX}},$2,$3,20,1e-12,0.1,0.1,1,1e-9,0,0,0,0,0,0,0,0,0,0,0,0"; }
CSV_OUT="${W}/o.csv"; TUNING_CSV="${W}/t.csv"; KVCO_CSV="${W}/k.csv"
run() { # run <vlist> ; rows on stdin
  { echo hdr; cat; } > "${CSV_OUT}"; : > "${TUNING_CSV}"; : > "${KVCO_CSV}"
  osc_emit_tuning m c1 h 27 "${OSC_TMAX}" "$1"
}
curve() { # curve <vlist> [skip-list]: monotone f falling 5.48e9 -> 4.52e9
  local n=0 tot; tot=$(wc -w <<<"$1")
  for v in $1; do
    f=$(awk -v i="${n}" -v t="${tot}" 'BEGIN{printf "%.6e", 5.48e9 - 0.96e9*i/(t-1)}')
    row "${v}" PASS "${f}"; n=$((n+1))
  done
}
check() { # check <name> <condition-result>
  if [[ "$2" == ok ]]; then echo "PASS $1"; else echo "FAIL $1"; FAIL=1; fi
}
verd() { awk -F, '{print $18","$19","$20}' "${TUNING_CSV}"; }

# (f) complete valid curve: MET, kvco rows for all 9 segments
curve "${FULL}" | run "${FULL}"
[[ "$(verd)" == "BOTH ENDPOINTS INSIDE,MET,MET" ]] && check complete-valid ok || check complete-valid "bad: $(verd)"
[[ "$(wc -l < "${KVCO_CSV}")" == 9 ]] && check complete-kvco ok || check complete-kvco bad
# byte-for-byte vs pre-change implementation
OLD="${W}/old.csv"
( source /tmp/osc_bench_old.sh 2>/dev/null; CSV_OUT="${W}/o.csv"; TUNING_CSV="${OLD}"; KVCO_CSV="${W}/ko.csv"; : > "${OLD}"; : > "${KVCO_CSV}"
  osc_emit_tuning m c1 h 27 ) 2>/dev/null
if [[ -s "${OLD}" ]]; then
  cmp -s "${OLD}" "${TUNING_CSV}" && check byte-identical-to-prechange ok || check byte-identical-to-prechange bad
fi

# (a) endpoints only
{ row 0.0 PASS 5.4e9; for v in 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0; do row "$v" NOSC 0; done; row 3.3 PASS 4.6e9; } | run "${FULL}"
[[ "$(verd)" == "INCOMPLETE,INCOMPLETE,INCOMPLETE" ]] && check endpoints-only ok || check endpoints-only "bad: $(verd)"
[[ "$(wc -l < "${KVCO_CSV}")" == 0 ]] && check endpoints-no-slope ok || check endpoints-no-slope bad
# (b) interior NOSC, (c) interior FAIL
for st in NOSC FAIL; do
  { row 0.0 PASS 5.4e9; row 0.3 PASS 5.35e9; row 0.6 "$st" 0; row 0.9 PASS 5.2e9; row 1.2 PASS 5.1e9; row 1.65 PASS 5.0e9; row 1.8 PASS 4.9e9; row 2.4 PASS 4.8e9; row 3.0 PASS 4.7e9; row 3.3 PASS 4.6e9; } | run "${FULL}"
  [[ "$(verd)" == "INCOMPLETE,INCOMPLETE,INCOMPLETE" ]] && check "interior-${st}" ok || check "interior-${st}" "bad: $(verd)"
  # 8 segments between PASS points, but the two spanning 0.6 are skipped -> 6
  [[ "$(wc -l < "${KVCO_CSV}")" == 7 ]] && check "interior-${st}-no-gap-slope" ok || check "interior-${st}-no-gap-slope" "bad $(wc -l < "${KVCO_CSV}")"
done
# (d) missing voltage
curve "${FULL}" | grep -v ",1.8," | run "${FULL}"
[[ "$(verd)" == "INCOMPLETE,INCOMPLETE,INCOMPLETE" ]] && check missing-voltage ok || check missing-voltage "bad: $(verd)"
# (e) duplicate voltage
{ curve "${FULL}"; row 1.2 PASS 5.1e9; } | run "${FULL}"
[[ "$(verd)" == "INCOMPLETE,INCOMPLETE,INCOMPLETE" ]] && check duplicate-voltage ok || check duplicate-voltage "bad: $(verd)"
# unexpected voltage
{ curve "${FULL}"; row 2.0 PASS 4.8e9; } | run "${FULL}"
[[ "$(verd)" == "INCOMPLETE,INCOMPLETE,INCOMPLETE" ]] && check unexpected-voltage ok || check unexpected-voltage "bad: $(verd)"
# (g) coarse-tmax repeat ignored
{ curve "${FULL}"; row 1.65 PASS 5.0e9 5p; } | run "${FULL}"
[[ "$(verd)" == "BOTH ENDPOINTS INSIDE,MET,MET" ]] && check coarse-tmax-ignored ok || check coarse-tmax-ignored "bad: $(verd)"
# (h) pilot edge set complete
curve "${EDGE}" | run "${EDGE}"
[[ "$(verd)" == "BOTH ENDPOINTS INSIDE,MET,MET" ]] && check pilot-edge-complete ok || check pilot-edge-complete "bad: $(verd)"
# fewer than two PASS stays INSUFFICIENT; missing list is an error
row 0.0 PASS 5.4e9 | run "${EDGE}"
[[ "$(verd)" == "INSUFFICIENT,INSUFFICIENT,INSUFFICIENT" ]] && check insufficient ok || check insufficient "bad: $(verd)"
osc_emit_tuning m c1 h 27 "${OSC_TMAX}" 2>/dev/null && check list-required bad || check list-required ok

exit "${FAIL}"
