#!/usr/bin/env bash
# PDK-free fixture for osc_row3_summary, the global row-3 reducer (issue #153).
# Synthetic row-3 CSVs only; no simulator. Global coverage means each required
# mos:cap:hbt:temp identity occurs exactly once, not merely N lines.
# Usage: tests/test_row3_global.sh [path/to/osc_bench.sh]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH="${1:-${HERE}/../osc_bench.sh}"
# shellcheck disable=SC1090
source "${BENCH}"
W="$(mktemp -d)"; trap 'rm -rf "${W}"' EXIT
FAIL=0
CSV="${W}/r3.csv"
REQ="tt:c1:h1:-40 tt:c1:h1:27 tt:c1:h2:-40 tt:c1:h2:27 ss:c1:h1:27 ss:c1:h2:27"
check() { if [[ "$2" == ok ]]; then echo "PASS $1"; else echo "FAIL $1 ($2)"; FAIL=1; fi; }

# line <key> <target> <stretch> : 23-column row-3 line
line() { IFS=: read -r m c h t <<<"$1"; echo "$m,$c,$h,$t,0.0,3.3,6,5e9,5e9,4e9,1e9,8e8,90,5e8,5,MET,MET,MET,MET,MET,$2,$3,-"; }
full() { for k in ${REQ}; do line "${k}" "${1:-MET}" "${2:-MET}"; done; }
build() { { osc_row3_header; cat; } > "${CSV}"; }
summ() { osc_row3_summary "${CSV}" "${REQ}"; }
expect_prefix() { local g; g="$(summ)"; [[ "${g}" == "$2"* ]] && check "$1" ok || check "$1" "got: ${g}"; }

full | build
expect_prefix complete-met "MET (target and stretch): target MET at 6/6 corners, stretch MET at 6/6"
full MET NOT\ MET | build
expect_prefix complete-stretch-not-met "MET (target); stretch NOT MET"
{ full | head -5; line ss:c1:h2:27 "NOT MET" "NOT MET"; } | build
expect_prefix complete-one-not-met "NOT MET: target MET at 5/6"

# duplicate replacing a required corner: count stays 6
{ full | head -5; line ss:c1:h1:27 MET MET; } | build
[[ "$(wc -l < "${CSV}")" == 7 ]] && check dup-count-preserved ok || check dup-count-preserved "$(wc -l < "${CSV}")"
expect_prefix duplicate-not-graded "NOT GRADED (partial)"
summ | grep -q "1 missing (e.g. ss:c1:h2:27), 1 duplicated" && check dup-diagnostic ok || check dup-diagnostic "$(summ)"
# 135-style: one corner repeated N times
for _ in 1 2 3 4 5 6; do line tt:c1:h1:27 MET MET; done | build
expect_prefix repeated-single-corner "NOT GRADED (partial)"
# missing
full | head -4 | build
expect_prefix missing "NOT GRADED (partial): 4/6"
# unexpected key (count still correct after dropping one required)
{ full | head -5; line xx:c1:h1:27 MET MET; } | build
expect_prefix unexpected-key "NOT GRADED (partial)"
summ | grep -q "1 unexpected (e.g. xx:c1:h1:27)" && check unexpected-diagnostic ok || check unexpected-diagnostic "$(summ)"
# extra line beyond a complete set
{ full; line xx:c1:h1:27 MET MET; } | build
expect_prefix extra-unexpected "NOT GRADED (partial)"
# incomplete per-corner grade
{ full | head -5; line ss:c1:h2:27 INCOMPLETE INCOMPLETE; } | build
expect_prefix incomplete-grade "NOT GRADED (partial)"
{ full | head -5; line ss:c1:h2:27 MET INCOMPLETE; } | build
expect_prefix incomplete-stretch-only "NOT GRADED (partial)"
# header / file / empty requirements
{ echo "a,b,c"; full; } > "${CSV}"
expect_prefix bad-header "NOT GRADED: row-3 CSV header"
rm -f "${CSV}"; expect_prefix no-file "NOT GRADED: no row-3 CSV"
full | build
[[ "$(osc_row3_summary "${CSV}" "")" == "NOT GRADED: no required"* ]] && check no-required ok || check no-required bad

exit "${FAIL}"
