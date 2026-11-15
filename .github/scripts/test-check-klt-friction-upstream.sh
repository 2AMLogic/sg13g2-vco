#!/usr/bin/env bash
# Self-test for the upstream-state gate (issue #333). Every case runs the
# checker offline through --states-file on a throwaway ledger copy; a gate
# that cannot fail is no gate, and an unreadable state that reads as
# agreement is worse than none (ci-principles.md rule 6). Stdlib python3
# only, no network.
#
#   1. all agree                                   -> 0
#   2. ledger closed vs upstream merged PR         -> 0 (merged is closed)
#   3. ledger open vs upstream closed              -> 1, both states named
#   4. ledger merged vs closed-unmerged PR         -> 1
#   5. an unreadable state (404/rate-limit shape)  -> 3, never 0
#   6. a number absent from the states file        -> 3
#   7. disagreement + unreadable together          -> 1, unreadable printed
#   8. malformed ledger / states file / usage      -> 2
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$HERE/check-klt-friction-upstream.sh"
pass=0; fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

run_case() { # name expect(0|1|2|3) tree states-file
  local got=0
  "$CHECKER" --root "$3" --states-file "$4" >"$TMP/out" 2>"$TMP/err" || got=$?
  if [ "$got" -eq "$2" ]; then echo "PASS: $1"; pass=$((pass + 1))
  else echo "FAIL: $1 (expected $2, got $got)" >&2; fail=$((fail + 1)); fi
}

# mk <dir>: a three-entry ledger covering the whole status vocabulary.
mk() {
  local d="$1"
  mkdir -p "$d/.github"
  cat > "$d/.github/klt-friction-ledger.json" <<'JSON'
{"schema": 1, "upstream": "2AMLogic/klayout-tools", "entries": [
  {"number": 7, "gap": "g7", "status": "open", "status_checked_on": "2026-10-09",
   "klt_version_verified": "0.8.0", "workarounds": []},
  {"number": 8, "gap": "g8", "status": "closed", "status_checked_on": "2026-10-09",
   "klt_version_verified": "0.8.0", "workarounds": []},
  {"number": 9, "gap": "g9", "status": "merged", "status_checked_on": "2026-10-09",
   "klt_version_verified": "0.8.0", "workarounds": []}
]}
JSON
}

# states <file> <json>
states() { printf '%s\n' "$2" > "$1"; }

mk "$TMP/tree"
S="$TMP/states"

states "$S" '{"7": "open", "8": "closed", "9": "merged"}'
run_case "all-agree passes" 0 "$TMP/tree" "$S"

states "$S" '{"7": "open", "8": "merged", "9": "merged"}'
run_case "ledger closed agrees with upstream merged PR" 0 "$TMP/tree" "$S"

states "$S" '{"7": "closed", "8": "closed", "9": "merged"}'
run_case "open-vs-closed disagrees" 1 "$TMP/tree" "$S"
if grep -q "ledger entry #7: status 'open' but upstream is 'closed'" "$TMP/err"; then
  echo "PASS: disagreement names both states"; pass=$((pass + 1))
else echo "FAIL: disagreement message incomplete" >&2; sed -n '1,5p' "$TMP/err" >&2; fail=$((fail + 1)); fi

states "$S" '{"7": "open", "8": "closed", "9": "closed"}'
run_case "merged vs closed-unmerged PR disagrees" 1 "$TMP/tree" "$S"

states "$S" '{"7": "open", "8": "unreadable", "9": "merged"}'
run_case "unreadable state exits 3, never 0" 3 "$TMP/tree" "$S"
if grep -q "UNREADABLE: #8" "$TMP/err"; then
  echo "PASS: unreadable entry is named"; pass=$((pass + 1))
else echo "FAIL: unreadable entry not named" >&2; fail=$((fail + 1)); fi

states "$S" '{"7": "open", "9": "merged"}'
run_case "number absent from the states file is unreadable" 3 "$TMP/tree" "$S"

states "$S" '{"7": "closed", "8": "unreadable", "9": "merged"}'
run_case "disagreement outranks unreadable (exit 1)" 1 "$TMP/tree" "$S"
if grep -q "UNREADABLE: #8" "$TMP/err"; then
  echo "PASS: unreadable still printed alongside the disagreement"; pass=$((pass + 1))
else echo "FAIL: unreadable not printed" >&2; fail=$((fail + 1)); fi

states "$S" '{"7": null, "8": "closed", "9": "merged"}'
run_case "null state counts as unreadable" 3 "$TMP/tree" "$S"

# Malformed inputs are setup errors (2), the offline gate owns the details.
mk "$TMP/bad-ledger"
echo '{' > "$TMP/bad-ledger/.github/klt-friction-ledger.json"
states "$S" '{"7": "open"}'
run_case "malformed ledger is a setup error" 2 "$TMP/bad-ledger" "$S"

mk "$TMP/no-ledger"
rm "$TMP/no-ledger/.github/klt-friction-ledger.json"
states "$S" '{"7": "open"}'
run_case "missing ledger is a setup error" 2 "$TMP/no-ledger" "$S"

mk "$TMP/tree"
echo '{"7": "reopened"}' > "$S"
run_case "unknown state value in the states file is a usage error" 2 "$TMP/tree" "$S"

echo 'not json' > "$S"
run_case "malformed states file is a setup error" 2 "$TMP/tree" "$S"

got=0
"$CHECKER" --root "$TMP/tree" --no-such-flag >/dev/null 2>&1 || got=$?
if [ "$got" -eq 2 ]; then echo "PASS: unknown flag is a usage error"; pass=$((pass + 1))
else echo "FAIL: unknown flag exited $got" >&2; fail=$((fail + 1)); fi

echo "test-check-klt-friction-upstream: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
