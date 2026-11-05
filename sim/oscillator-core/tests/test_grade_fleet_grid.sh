#!/usr/bin/env bash
# PDK-free known-answer check of grade_fleet_grid.py (issue #94): synthetic
# per-unit CSV only. Prints one "PASS <name>" / "FAIL <name>" line per assertion.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "${W}"' EXIT
FAIL=0
check() { if [[ "$2" == "$3" ]]; then echo "PASS $1"; else echo "FAIL $1 (got '$2', want '$3')"; FAIL=1; fi; }
{
  echo "process,vct_V,temp_C,status,t_10_periods_s,f_osc_GHz_from_10_periods,vdiff_pp_V,diagnostic_codes"
  # linear f = 5.4 - 0.8*V/3.3 GHz: ratio 5.4/4.6 = 1.1739; W span 0.4 GHz
  for v in 0.0 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0 3.3; do
    f="$(awk -v v="$v" 'BEGIN { printf "%.6f", 5.4 - 0.8*v/3.3 }')"
    echo "full,${v},27,pass,1e-9,${f},0.5,"
  done
  # hole at 3.0 V -> INCOMPLETE
  for v in 0.0 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.3; do echo "hole,${v},27,pass,1e-9,5.0,0.5,"; done
  echo "hole,3.0,27,error,,,,measurement"
} > "${W}/u.csv"
python3 -I "${HERE}/../grade_fleet_grid.py" "${W}/u.csv" "${W}/g.csv" > /dev/null
col() { awk -F, -v p="$1" -v c="$2" 'NR>1 && $1==p { print $c }' "${W}/g.csv"; }
check "full row1"          "$(col full 7)"  "BOTH ENDPOINTS INSIDE"
check "full row2 ratio"    "$(col full 8)"  "1.17391"
check "full row2"          "$(col full 9)"  "MET"
check "full row2 stretch"  "$(col full 10)" "NOT MET"
check "full row3 coverage" "$(col full 13)" "0.5000"
check "full row3 kvco"     "$(col full 14)" "242.4"
check "full row3"          "$(col full 16)" "NOT MET"
check "full row7 swing"    "$(col full 18)" "MET"
check "full row7 bvceo"    "$(col full 19)" "NOT GRADED"
check "hole row2"          "$(col hole 9)"  "INCOMPLETE"
check "hole row3"          "$(col hole 16)" "INCOMPLETE"
exit "${FAIL}"
