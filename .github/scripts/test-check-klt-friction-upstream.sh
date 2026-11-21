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
#   9. reduce_state() on fixture payloads: open issue, closed issue,
#      open PR -> "open" (was the mis-reduction to "closed"), merged PR,
#      closed-unmerged PR; ledger "open" agrees with an "open" reduced
#      from an open-PR payload end to end (agrees() + reduce_state()).
#  10. --states-file: ledger open vs upstream open (PR-shaped item's
#      reduced third vocabulary value, end to end)
#  11. reporting decisions (issue #422), gh stubbed on PATH, fed real
#      captured checker output: agreement, unreadable-only and
#      setup-failure logs file no issue (an entry-shaped FAIL line is the
#      only drift signal); a confirmed drift with no open repair issue
#      creates one labeled loom:triage with entries, states and run URL;
#      an open repair issue is refreshed by comment, never duplicated (a
#      retried run adds evidence); a closed prior issue is invisible to
#      --state open so a recurrence opens a new issue; a mixed log's body
#      separates confirmed mismatches from unreadable entries; workflow
#      wiring asserts the schedule + result==1 gates, issue-write confined
#      to the reporting job, and the compare step re-exiting with the
#      checker's code so the failing check is preserved.
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

# --- reduce_state(): the payload->state reduction, fixture-driven, no
# network. This is the only place the three-way mapping is derived from
# API payloads; drive it directly so a mis-reduction (e.g. an open PR
# reduced to "closed") cannot hide behind the injected --states-file.
reduce_case() { # name issue-json pull-json-or-'-' want-state
  local got
  got="$(python3 -I -c '
import json, sys
sys.path.insert(0, sys.argv[1])
import check_klt_friction_upstream as m
issue = json.loads(sys.argv[2])
pull = None if sys.argv[3] == "-" else json.loads(sys.argv[3])
print(m.reduce_state(issue, pull)[0])
' "$HERE" "$2" "$3" 2>&1)"
  if [ "$got" = "$4" ]; then echo "PASS: reduce $1 -> $4"; pass=$((pass + 1))
  else echo "FAIL: reduce $1 (expected $4, got $got)" >&2; fail=$((fail + 1)); fi
}

reduce_case "open issue" '{"state": "open"}' - open
reduce_case "closed issue" '{"state": "closed", "closed_at": "2026-01-01T00:00:00Z"}' - closed
# An open PR: issues endpoint says "open", pulls says merged=false. The
# mis-reduction took the closed branch here and reported "closed".
reduce_case "open PR" '{"state": "open", "pull_request": {"merged_at": null}}' \
  '{"merged": false, "closed_at": null}' open
reduce_case "merged PR" '{"state": "closed", "pull_request": {"merged_at": null}}' \
  '{"merged": true, "merged_at": "2026-01-02T00:00:00Z"}' merged
reduce_case "closed-unmerged PR" '{"state": "closed", "pull_request": {"merged_at": null}}' \
  '{"merged": false, "closed_at": "2026-01-03T00:00:00Z"}' closed

# End to end over the vocabulary's third value: ledger "open" vs an
# upstream "open" reduced from an open-PR payload must agree. Before the
# fix this pair was a false failure (upstream mis-read as "closed")
# while the reversed ledger status was a false agreement.
got="$(python3 -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import check_klt_friction_upstream as m
issue = {"state": "open", "pull_request": {"merged_at": None}}
pull = {"merged": False, "closed_at": None}
state = m.reduce_state(issue, pull)[0]
print("agree" if m.agrees("open", state) else "disagree:%s" % state)
' "$HERE" 2>&1)"
if [ "$got" = "agree" ]; then
  echo "PASS: ledger open agrees with upstream open reduced from an open PR"
  pass=$((pass + 1))
else echo "FAIL: ledger open vs open-PR reduction (got: $got)" >&2; fail=$((fail + 1)); fi

# --states-file end to end: the PR-shaped open value ("7" above) agreeing
# on the ledger's "open" - the vocabulary's third value covered through
# the full checker, not just agrees().
states "$S" '{"7": "open", "8": "closed", "9": "merged"}'
run_case "ledger open vs upstream open (PR-shaped value) passes" 0 "$TMP/tree" "$S"

# --- report-friction-drift.sh: the scheduled repair-issue reporter
# (issue #422). gh is replaced on PATH by a stub that records every
# invocation plus the issue body it was handed; the logs fed to the
# reporter are real captured checker output (stdout+stderr merged, the
# same bytes the workflow's compare step exports as its job output), so
# the entry-shaped FAIL line the reporter keys on is the line CI sees.
REPORT="$HERE/report-friction-drift.sh"
GHDIR="$TMP/gh-stub"
export GH_STUB_DIR="$GHDIR"
mkdir -p "$GHDIR"
cat >"$GHDIR/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_DIR/calls"
prev=""
for a in "$@"; do
  [ "$prev" = "--body-file" ] && cp "$a" "$GH_STUB_DIR/last-body"
  prev="$a"
done
case "$1 $2" in
  "issue list") cat "$GH_STUB_DIR/list.json" ;;
  "issue create") echo "https://stub.example/stub/stub/issues/99" ;;
  "issue comment") echo "https://stub.example/stub/stub/issues/99#issuecomment-1" ;;
  *) echo "gh-stub: unexpected subcommand: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$GHDIR/gh"

run_report() { # name expect-exit; reads RLOG (checker log) and RLIST (open issues)
  rm -f "$GHDIR/calls" "$GHDIR/last-body"
  printf '%s' "$RLIST" >"$GHDIR/list.json"
  got=0
  PATH="$GHDIR:$PATH" GH_TOKEN=stub-token GITHUB_REPOSITORY=stub/stub \
    "$REPORT" --log "$RLOG" --run-url "https://example/runs/1" \
    >"$TMP/rout" 2>"$TMP/rerr" || got=$?
  if [ "$got" -eq "$2" ]; then echo "PASS: $1"; pass=$((pass + 1))
  else echo "FAIL: $1 (expected $2, got $got)" >&2; sed -n '1,5p' "$TMP/rerr" >&2; fail=$((fail + 1)); fi
}

check() { # name condition-as-command
  if eval "$2"; then echo "PASS: $1"; pass=$((pass + 1))
  else echo "FAIL: $1" >&2; fail=$((fail + 1)); fi
}

assert_no_calls() { # name
  if [ -s "$GHDIR/calls" ]; then
    echo "FAIL: $1 made unexpected issue API calls:" >&2
    cat "$GHDIR/calls" >&2
    fail=$((fail + 1))
  else echo "PASS: $1 makes no issue API calls"; pass=$((pass + 1)); fi
}

# Real checker logs, captured exactly as the workflow captures them.
mk "$TMP/report-tree"
RS="$TMP/report-states"
states "$RS" '{"7": "open", "8": "closed", "9": "merged"}'
"$CHECKER" --root "$TMP/report-tree" --states-file "$RS" >"$TMP/log-agree" 2>&1
states "$RS" '{"7": "closed", "8": "closed", "9": "merged"}'
"$CHECKER" --root "$TMP/report-tree" --states-file "$RS" >"$TMP/log-drift" 2>&1 || true
states "$RS" '{"7": "closed", "8": "unreadable", "9": "merged"}'
"$CHECKER" --root "$TMP/report-tree" --states-file "$RS" >"$TMP/log-mixed" 2>&1 || true
states "$RS" '{"7": "open", "8": "unreadable", "9": "merged"}'
"$CHECKER" --root "$TMP/report-tree" --states-file "$RS" >"$TMP/log-unreadable" 2>&1 || true
mk "$TMP/report-bad"
echo '{' >"$TMP/report-bad/.github/klt-friction-ledger.json"
"$CHECKER" --root "$TMP/report-bad" --states-file "$RS" >"$TMP/log-setup" 2>&1 || true

# Agreement / unreadable-only / setup failure: no issue write at all.
RLIST='[]'; RLOG="$TMP/log-agree"
run_report "agreement files nothing" 0
assert_no_calls "agreement"
RLOG="$TMP/log-unreadable"
run_report "unreadable-only files nothing (exit 3 shape is not drift)" 0
assert_no_calls "unreadable-only"
RLOG="$TMP/log-setup"
run_report "setup FAIL line has no entry shape, files nothing" 0
assert_no_calls "setup failure"

# Confirmed drift, nothing open: create one labeled issue with evidence.
RLIST='[]'; RLOG="$TMP/log-drift"
run_report "drift with no open repair issue creates one" 0
check "one lookup then one create, no comment" \
  '[ "$(grep -c "^issue " "$GHDIR/calls")" -eq 2 ] && grep -q "^issue create " "$GHDIR/calls" && ! grep -q "^issue comment " "$GHDIR/calls"'
check "created issue carries loom:triage" \
  'grep -q " --label loom:triage " "$GHDIR/calls"'
check "created issue uses the stable title" \
  'grep -qF -- "--title ci: friction-upstream ledger drift repair " "$GHDIR/calls"'
check "created body names entry, both states" \
  'grep -qF -- "- ledger entry #7: status '\''open'\'' but upstream is '\''closed'\''" "$GHDIR/last-body"'
check "created body links the Actions run" \
  'grep -qF "https://example/runs/1" "$GHDIR/last-body"'
check "created body names no unreadable section" \
  '! grep -q "Unreadable entries" "$GHDIR/last-body"'

# Recurrence after closure: a closed issue is absent from --state open,
# and identity is the exact title, so unrelated open issues do not match.
RLIST='[{"number": 5, "title": "unrelated open issue"}]'
run_report "recurrence after closure opens a new issue" 0
check "exact-title identity ignores unrelated open issues" \
  'grep -q "^issue create " "$GHDIR/calls" && ! grep -q "^issue comment " "$GHDIR/calls"'

# Open repair issue: refreshed by comment, not duplicated.
RLIST='[{"number": 42, "title": "ci: friction-upstream ledger drift repair"},
        {"number": 5, "title": "unrelated open issue"}]'
run_report "open repair issue is refreshed, not duplicated" 0
check "comment targets the open repair issue" \
  'grep -q "^issue comment 42 " "$GHDIR/calls"'
check "no create while the repair issue is open" \
  '! grep -q "^issue create " "$GHDIR/calls"'
check "refresh body carries current evidence" \
  'grep -qF -- "- ledger entry #7: status '\''open'\'' but upstream is '\''closed'\''" "$GHDIR/last-body"'

# Retrying the run adds evidence, never a second issue: run_report clears
# the call log per run, so re-append the first run's calls to assert on the
# cumulative picture.
before_calls="$(cat "$GHDIR/calls" 2>/dev/null || true)"
run_report "retried run refreshes again" 0
printf '%s\n' "$before_calls" >>"$GHDIR/calls"
check "two failures, two comments, zero creates" \
  '[ "$(grep -c "^issue comment 42 " "$GHDIR/calls")" -eq 2 ] && ! grep -q "^issue create " "$GHDIR/calls"'

# Mixed result: mismatches and unreadable entries both named, separated.
RLOG="$TMP/log-mixed"
run_report "mixed result refreshes with both classes named" 0
check "mixed body names the confirmed mismatch" \
  'grep -qF -- "- ledger entry #7: status '\''open'\'' but upstream is '\''closed'\''" "$GHDIR/last-body"'
check "mixed body keeps unreadable entries separate" \
  'grep -q "Unreadable entries (not counted as drift)" "$GHDIR/last-body" && grep -qF -- "- #8:" "$GHDIR/last-body"'

# Workflow wiring: the reporting decision and its permission scope live
# in friction-upstream.yml; these structural assertions pin the gates the
# shell cases cannot reach (event, needs/result, per-job permissions).
WF="$HERE/../workflows/friction-upstream.yml"
wf_grep() { # name fixed-string-pattern (must be present in the workflow)
  if grep -qF -- "$2" "$WF"; then echo "PASS: $1"; pass=$((pass + 1))
  else echo "FAIL: $1" >&2; fail=$((fail + 1)); fi
}

wf_grep "reporting is gated on the schedule event" "github.event_name == 'schedule'"
wf_grep "reporting fires only on confirmed drift (result == 1)" "needs.friction-upstream.outputs.result == '1'"
wf_grep "reporting job runs after the check job despite its red" "needs: friction-upstream"
wf_grep "compare step preserves the checker exit" 'exit "$result"'
wf_grep "reporter script is on the workflow PR path list" ".github/scripts/report-friction-drift.sh"

if [ "$(grep -c "issues: write" "$WF")" -eq 1 ] && grep -qF "always()" "$WF"; then
  echo "PASS: issue-write permission exists only in the reporting job"; pass=$((pass + 1))
else echo "FAIL: issue-write permission exists only in the reporting job" >&2; fail=$((fail + 1)); fi

echo "test-check-klt-friction-upstream: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
