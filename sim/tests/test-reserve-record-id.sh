#!/usr/bin/env bash
# Self-test for reserve_record_id in sim/lib.sh (issue #102). No PDK, no
# simulator: pure bash on a scratch experiment dir. Timestamp and commit are
# frozen so only the reservation logic decides uniqueness.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib.sh
source "${HERE}/../lib.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
bad() { fail=$((fail + 1)); echo "FAIL - $1"; }

export SIM_RECORD_TS=20260101-000000 SIM_RECORD_SHA=abc1234
E="$T/exp"; mkdir -p "$E"

# 1. consecutive allocations are distinct and reserved
a="$(reserve_record_id "$T" "$E")"; b="$(reserve_record_id "$T" "$E")"
if [ -n "$a" ] && [ "$a" != "$b" ] && [ -d "$E/corners/$a" ] && [ -d "$E/corners/$b" ]; then
  ok "consecutive allocations distinct (frozen ts+commit)"; else bad "consecutive: '$a' '$b'"; fi
case "$a" in 20260101-000000-abc1234-*) ok "id keeps readable ts-commit prefix";; *) bad "id format: $a";; esac

# 2. concurrent allocations (4 background procs)
mkdir -p "$T/out"
for i in 1 2 3 4; do
  ( reserve_record_id "$T" "$E" > "$T/out/$i" ) &
done
wait
n="$(cat "$T"/out/* | sort -u | wc -l | tr -d ' ')"
if [ "$n" = 4 ]; then ok "4 concurrent allocations distinct"; else bad "concurrent distinct count $n"; fi

# 3. forced collision with sentinel evidence: first attempt uses a frozen
# suffix that is already taken; sentinel must stay byte-identical.
pre="20260101-000000-abc1234-deadbeef"
mkdir -p "$E/corners/$pre"; echo sentinel > "$E/corners/$pre/log.txt"
mkdir -p "$E/records"; echo sentinel-md > "$E/records/$pre.md"
cp -R "$E" "$T/snapshot"
c="$(SIM_RECORD_SUFFIX=deadbeef reserve_record_id "$T" "$E")"
if [ -n "$c" ] && [ "$c" != "$pre" ]; then ok "collision retried with fresh id"; else bad "collision gave '$c'"; fi
if [ "$(cat "$E/corners/$pre/log.txt")" = sentinel ] && [ "$(cat "$E/records/$pre.md")" = sentinel-md ]; then
  ok "sentinel evidence byte-identical"; else bad "sentinel changed"; fi

# 4. historical flat record (no corners dir) is never reused either
hist="20260101-000000-abc1234-cafe0001"
echo old > "$E/records/$hist.md"
d="$(SIM_RECORD_SUFFIX=cafe0001 reserve_record_id "$T" "$E")"
if [ -n "$d" ] && [ "$d" != "$hist" ] && [ "$(cat "$E/records/$hist.md")" = old ]; then
  ok "historical flat record id skipped"; else bad "historical: '$d'"; fi

# 5. failure is clear when the namespace cannot be created.
if reserve_record_id "$T" "/dev/null/nope" 2>/dev/null; then bad "unwritable dir succeeded"; else ok "unwritable dir fails"; fi

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
