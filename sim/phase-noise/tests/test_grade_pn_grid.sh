#!/usr/bin/env bash
# Simulator-free known-answer fixture for grade_pn_grid.py (issue #53): grade-on-
# completeness, a corner that fails to oscillate, n_plateau < 3, worst-corner pick,
# and append-only --out. Synthetic CSVs only. Prints PASS/FAIL lines.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="${HERE}/../grade_pn_grid.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
has() { if grep -q -- "$3" <<<"$2"; then pass "$1"; else fail "$1: no '$3' in: $2"; fi; }
hasnt() { if grep -q -- "$3" <<<"$2"; then fail "$1: unexpected '$3'"; else pass "$1"; fi; }

HDR="process,temp_c,status,l_1mhz_dbc,l_10mhz_dbc,l_1mhz_sd_db,inductor_bar_db,n_plateau_min,plateau_ripple_max_s,f0_hz,job_id,raw_log"
# full(L1) : all 135 corners valid at -L1 dBc/Hz @ 1 MHz (10 MHz = L1 - 20)
full() { python3 - "$1" <<'PY'
import sys
l1 = float(sys.argv[1])
print("process,temp_c,status,l_1mhz_dbc,l_10mhz_dbc,l_1mhz_sd_db,inductor_bar_db,n_plateau_min,plateau_ripple_max_s,f0_hz,job_id,raw_log")
for m in "tt ss ff sf fs".split():
  for c in "typ bcs wcs".split():
    for h in "typ bcs wcs".split():
      for t in (-40, 27, 125):
        print(f"{m}_{c}_{h},{t},pass,{l1:g},{l1-20:g},0.2,0.42,3,1e-13,4.2e9,job1,log")
PY
}

full -100 > "$T/ok.csv"
out="$(python3 "$G" "$T/ok.csv")"
has "complete grid is graded" "$out" "row 4 @ 1 MHz"
has "miss reported" "$out" "TARGET NOT MET"
hasnt "complete grid not INCOMPLETE" "$out" "INCOMPLETE"

full -120 > "$T/good.csv"
has "both stretch met" "$(python3 "$G" "$T/good.csv")" "TARGET AND STRETCH BOTH MET"

# one corner worse: worst-corner pick, and -105.1 vs target -105 is bar-sensitive
sed 's/^ss_wcs_wcs,125,pass,-120,-140/ss_wcs_wcs,125,pass,-105.1,-125.1/' "$T/good.csv" > "$T/worst.csv"
out="$(python3 "$G" "$T/worst.csv")"
has "worst corner named" "$out" "worst -105.10 dBc/Hz at ss_wcs_wcs 125C"
has "bar-sensitive flagged" "$out" "BAR-SENSITIVE"

# partial grid grades nothing
head -n 100 "$T/ok.csv" > "$T/partial.csv"
out="$(python3 "$G" "$T/partial.csv")"
has "partial grid INCOMPLETE" "$out" "INCOMPLETE"
has "partial lists missing" "$out" "MISSING"
hasnt "partial grades no offset" "$out" "row 4 @"

# a corner that fails to oscillate is listed with its raw log, not dropped
sed 's/^tt_typ_typ,125,pass,-100,-120,0.2,0.42,3,1e-13,4.2e9,job1,log/tt_typ_typ,125,no_oscillation,,,,,,,,job9,logs\/hot.log/' "$T/ok.csv" > "$T/noosc.csv"
out="$(python3 "$G" "$T/noosc.csv")"
has "failed corner listed" "$out" "INVALID  tt_typ_typ 125C: status=no_oscillation raw_log=logs/hot.log"
has "failed corner blocks grading" "$out" "INCOMPLETE"

# degenerate plateau (n_plateau < 3) blocks grading
sed 's/^ff_typ_typ,27,pass,-100,-120,0.2,0.42,3,/ff_typ_typ,27,pass,-100,-120,0.2,0.42,1,/' "$T/ok.csv" > "$T/plat.csv"
has "n_plateau<3 blocks" "$(python3 "$G" "$T/plat.csv")" "n_plateau_min=1 < 3"

# non-finite L on a pass row
sed 's/^fs_typ_bcs,-40,pass,-100,-120/fs_typ_bcs,-40,pass,nan,nan/' "$T/ok.csv" > "$T/nan.csv"
has "NaN pass row blocks" "$(python3 "$G" "$T/nan.csv")" "non-finite L"

# --out is append-only
python3 "$G" "$T/ok.csv" --out "$T/g.csv" >/dev/null
has "out written" "$(cat "$T/g.csv")" "graded,offset"
has "out refuses overwrite" "$(python3 "$G" "$T/ok.csv" --out "$T/g.csv" 2>&1)" "append-only"
python3 "$G" "$T/partial.csv" --out "$T/g2.csv" >/dev/null
has "partial out says INCOMPLETE" "$(cat "$T/g2.csv")" "False,,,,INCOMPLETE"

# grid declaration: 135 corners, nothing is run
n="$("${HERE}/../run_pn_sweep.sh" --list | wc -l | tr -d ' ')"
[[ "$n" == 135 ]] && pass "grid is 135 corners" || fail "grid is $n corners"
[[ "$("${HERE}/../run_pn_sweep.sh" --submit 2>&1 | head -n1)" == usage* ]] && pass "submit needs a dir" || fail "submit needs a dir"

echo "${fails} failure(s)"
[[ ${fails} -eq 0 ]]
