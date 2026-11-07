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

# 2. concurrent allocations (N background procs). Each caller's stdout, stderr
# and exit status are kept so a failure shows which caller printed what, and
# SIM_RECORD_TRACE records every mint/mkdir attempt (pid, id, outcome) so a
# duplicate print can be traced to the attempt that produced it (issue #305).
# $1 = label, $2 = caller count, remaining args = extra env (e.g. SIM_RECORD_SUFFIX=..).
concurrent_case() {
  local label="$1" count="$2" i n; shift 2
  local D="$T/out-${label//[^a-z0-9]/_}"; rm -rf "$D"; mkdir -p "$D"
  : > "$D/trace"
  for i in $(seq 1 "$count"); do
    # Forked subshell (not a fresh bash): same RANDOM/fork conditions as the
    # CI failure this case was written for.
    ( [ "$#" -eq 0 ] || declare -gx "$@"; export SIM_RECORD_TRACE="$D/trace"
      reserve_record_id "$T" "$E" > "$D/$i.out" 2> "$D/$i.err"; echo $? > "$D/$i.rc" ) &
  done
  wait
  n="$(cat "$D"/*.out | sort -u | wc -l | tr -d ' ')"
  if [ "$n" = "$count" ] && [ "$(cat "$D"/*.out | wc -l | tr -d ' ')" = "$count" ]; then ok "$label distinct"; else
    bad "$label distinct count $n of $count (bash ${BASH_VERSION})"
    for i in $(seq 1 "$count"); do
      echo "  caller $i: rc=$(cat "$D/$i.rc" 2>/dev/null || echo missing)" \
        "stdout='$(cat "$D/$i.out" 2>/dev/null)'" \
        "stderr='$(cat "$D/$i.err" 2>/dev/null)'"
    done
    echo "  trace:"; sed 's/^/    /' "$D/trace"
    echo "  reserved dirs (inode name):"; ls -i "$E/corners" | sed 's/^/    /'
  fi
}
concurrent_case "4 concurrent allocations" 4
# Deterministic arbitration: every caller's FIRST attempt uses the same frozen
# suffix, so mkdir alone must decide the winner and the rest must retry onto
# fresh ids. Exercises the collision path on every run, not 1 CI run in N.
concurrent_case "4 callers forcing one suffix" 4 SIM_RECORD_SUFFIX=0badc0de
concurrent_case "8 callers forcing one suffix" 8 SIM_RECORD_SUFFIX=0badc0df

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
