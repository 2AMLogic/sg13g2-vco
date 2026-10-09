#!/usr/bin/env bash
# PDK-free analytic-fixture check for osc_emit_row3 (ratified row 3, DR-004).
# Fakes CSV_OUT with synthetic f_osc(Vctrl) curves whose window slope,
# coverage and chord nonlinearity are known in closed form; runs no simulator.
# Usage: tests/test_row3.sh [path/to/osc_bench.sh]  (default: ../osc_bench.sh)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH="${1:-${HERE}/../osc_bench.sh}"
# shellcheck disable=SC1090
source "${BENCH}"
W="$(mktemp -d)"; trap 'rm -rf "${W}"' EXIT
FAIL=0
FULL="0.0 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0 3.3"
CSV_OUT="${W}/o.csv"; ROW3_CSV="${W}/r3.csv"

# row <v> <status> <f> [tmax] [meas_status]   (29 columns like the real CSV)
row() { echo "c,m,c1,h,27,$1,${4:-${OSC_TMAX}},$2,$3,20,1e-12,0.1,0.1,1,1e-9,0,0,0,0,0,0,0,0,0,0,0,0,${5:-VALID},-"; }
# curve <f0.0> <f1.65> <f1.8> <f2.4> <f3.0> <f3.3> : interior low-V points interpolate f0.0..f1.65
curve() {
  local f0="$1" f165="$2" r
  for v in 0.0 0.3 0.6 0.9 1.2; do
    r=$(awk -v a="${f0}" -v b="${f165}" -v v="${v}" 'BEGIN{printf "%.6e", a+(b-a)*v/1.65}')
    row "${v}" PASS "${r}"
  done
  row 1.65 PASS "${f165}"; row 1.8 PASS "$3"; row 2.4 PASS "$4"; row 3.0 PASS "$5"; row 3.3 PASS "$6"
}
run() { # run [vlist] ; rows on stdin
  { echo hdr; cat; } > "${CSV_OUT}"; : > "${ROW3_CSV}"
  osc_emit_row3 m c1 h 27 "${OSC_TMAX}" "${1:-${FULL}}"
}
col() { awk -F, -v c="$1" '{print $c}' "${ROW3_CSV}"; }
# req1,req2,req3,req4t,req4s,target,stretch
verd() { awk -F, '{print $16","$17","$18","$19","$20","$21","$22}' "${ROW3_CSV}"; }
check() { if [[ "$2" == ok ]]; then echo "PASS $1"; else echo "FAIL $1 ($2)"; FAIL=1; fi; }
expect() { # expect <name> <expected verdict string>
  [[ "$(verd)" == "$2" ]] && check "$1" ok || check "$1" "got: $(verd) reason: $(col 23)"
}
near() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<=t)}'; }
INC="INCOMPLETE,INCOMPLETE,INCOMPLETE,INCOMPLETE,INCOMPLETE,INCOMPLETE,INCOMPLETE"

# Linear window: slope -500 MHz/V, f(1.65)=5.0e9, f(3.3)=4.175e9; f(0)=5.075e9.
# span 825 MHz, full span 900 MHz -> coverage 91.67 %, INL 0 %.
LIN=(5.075e9 5.0e9 4.925e9 4.625e9 4.325e9 4.175e9)
curve "${LIN[@]}" | run
expect linear-passes "MET,MET,MET,MET,MET,MET,MET"
near "$(col 15)" 0 0.01 && check linear-inl-zero ok || check linear-inl-zero "$(col 15)"
near "$(col 13)" 91.6667 0.01 && check linear-coverage ok || check linear-coverage "$(col 13)"
near "$(col 14)" 5e8 1 && check linear-kvco-mean ok || check linear-kvco-mean "$(col 14)"
[[ "$(col 7)" == 5 ]] && check window-sample-count ok || check window-sample-count "$(col 7)"

# Slope reversal: f(2.4) bumps above f(1.8); the end values (hence coverage,
# mean slope) are unchanged but requirement 1 fails and so does the row.
curve 5.075e9 5.0e9 4.925e9 4.95e9 4.325e9 4.175e9 | run
expect slope-reversal "NOT MET,MET,MET,NOT MET,NOT MET,NOT MET,NOT MET"
# A flat segment is not single-signed either.
curve 5.075e9 5.0e9 4.9e9 4.9e9 4.325e9 4.175e9 | run
[[ "$(col 16)" == "NOT MET" && "$(col 21)" == "NOT MET" ]] && check flat-segment ok || check flat-segment "$(verd)"
# Increasing (wrong-sign) window: single-signed but mean slope/coverage fail.
curve 5.0e9 4.3e9 4.35e9 4.45e9 4.55e9 4.6e9 | run
[[ "$(col 18)" == "NOT MET" && "$(col 21)" == "NOT MET" ]] && check wrong-sign ok || check wrong-sign "$(verd)"

# Deficient coverage: f(0.0)=5.5e9 -> full span 1.325e9, coverage 62.3 %.
curve 5.5e9 5.0e9 4.925e9 4.625e9 4.325e9 4.175e9 | run
expect deficient-coverage "MET,NOT MET,MET,MET,MET,NOT MET,NOT MET"
# Deficient slope: 300 MHz/V (span 495 MHz, f(0)=5.05e9 -> coverage 90.8 %).
curve 5.05e9 5.0e9 4.94e9 4.7e9 4.55e9 4.505e9 | run
[[ "$(col 17)" == MET && "$(col 18)" == "NOT MET" && "$(col 21)" == "NOT MET" ]] \
  && check deficient-slope ok || check deficient-slope "$(verd)"

# Chord deviation at 2.4 V of 25 % of span: 4.625e9 - 0.25*825e6 = 4.41875e9.
curve 5.075e9 5.0e9 4.95e9 4.41875e9 4.325e9 4.175e9 | run
expect chord-25pct-target-only "MET,MET,MET,MET,NOT MET,MET,NOT MET"
near "$(col 15)" 25 0.01 && check chord-25-value ok || check chord-25-value "$(col 15)"
# 35 % (4.33625e9): fails both.
curve 5.075e9 5.0e9 4.95e9 4.33625e9 4.325e9 4.175e9 | run
expect chord-35pct-fails "MET,MET,MET,NOT MET,NOT MET,NOT MET,NOT MET"
# 15 % (4.50125e9 -> dev 123.75e6): meets target and stretch.
curve 5.075e9 5.0e9 4.95e9 4.50125e9 4.325e9 4.175e9 | run
expect chord-15pct-stretch "MET,MET,MET,MET,MET,MET,MET"

# ---- incomplete data never passes
curve "${LIN[@]}" | grep -v ',3.3,' | run
expect missing-hi-endpoint "${INC}"
curve "${LIN[@]}" | grep -v ',1.65,' | run
expect missing-lo-endpoint "${INC}"
curve "${LIN[@]}" | grep -v ',0.0,' | run
expect missing-full-domain-0V "${INC}"
curve "${LIN[@]}" | grep -v ',2.4,' | run
expect missing-interior "${INC}"
{ curve "${LIN[@]}"; row 2.4 PASS 4.6e9; } | run
expect duplicate "${INC}"
{ curve "${LIN[@]}"; row 2.0 PASS 4.7e9; } | run
expect unexpected-voltage "${INC}"
curve "${LIN[@]}" | sed 's/,2.4,\([^,]*\),PASS,[^,]*/,2.4,\1,NOSC,0/' | run
expect interior-nosc "${INC}"
curve "${LIN[@]}" | sed 's/,VALID,-$/,INVALID,x/' | run
expect invalid-measurement "${INC}"
curve "${LIN[@]}" | sed 's/,3.3,\([^,]*\),PASS,[^,]*/,3.3,\1,PASS,nan/' | run
expect nan-frequency "${INC}"
# zero full-domain span
curve 4.175e9 4.175e9 4.175e9 4.175e9 4.175e9 4.175e9 | run
expect zero-span "${INC}"
# inadequate window sampling: a 4-point window axis
V4="0.0 0.3 0.6 0.9 1.2 1.65 2.4 3.0 3.3"
curve "${LIN[@]}" | grep -v ',1.8,' | run "${V4}"
expect four-window-samples "${INC}"
# a coarser-tmax repeat is ignored, not a duplicate
{ curve "${LIN[@]}"; row 1.65 PASS 5.0e9 5p; } | run
expect coarse-tmax-ignored "MET,MET,MET,MET,MET,MET,MET"
# list is required; no ROW3_CSV is a no-op (pilots grade nothing)
osc_emit_row3 m c1 h 27 "${OSC_TMAX}" 2>/dev/null && check list-required bad || check list-required ok
( unset ROW3_CSV; osc_emit_row3 m c1 h 27 "${OSC_TMAX}" "${FULL}" ) && check no-csv-noop ok || check no-csv-noop bad

exit "${FAIL}"
