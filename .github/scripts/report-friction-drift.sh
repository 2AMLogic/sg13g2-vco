#!/usr/bin/env bash
# Scheduled-run repair-issue reporter for the friction-upstream gate
# (issue #422). The daily comparison (check-klt-friction-upstream.sh)
# already turns ledger drift red on main; this script turns a *confirmed*
# disagreement into queued work: one open loom:triage issue that later
# scheduled runs refresh, so drift stops piling onto whichever PR next
# edits the ledger.
#
# Defense in depth against false drift reports: the workflow gates this
# script on event == schedule and on the checker's raw exit 1 (confirmed
# mismatch; 2 = input error, 3 = unreadable-only, 0 = agreement file
# nothing), and the script itself keys only on the checker's entry-shaped
# FAIL lines:
#
#   FAIL: ledger entry #<n>: status '<ledger>' but upstream is '<state>'
#
# A setup failure prints "FAIL: <message>" without the entry shape and
# files nothing even if handed this script's input. UNREADABLE lines are
# reported in a separate section of the issue body, never counted as
# drift (ci-principles.md rule 6).
#
# Issue identity is the exact TITLE below, matched against open issues
# only: while one is open, every scheduled failure comments on it (a
# retried run adds evidence, never a duplicate); after it is closed, a
# recurrence opens a new issue. The loom:triage label is applied at
# creation only.
#
# Usage: report-friction-drift.sh --log PATH --run-url URL
#   --log      combined stdout+stderr of the checker run (the workflow's
#              compare step exports exactly that as its job output)
#   --run-url  the Actions run that found the drift, linked in the issue
# Env: GH_TOKEN (issues: write), GITHUB_REPOSITORY (owner/repo)
# Exit: 0 filed or refreshed an issue, or deliberately had nothing to
#       file; nonzero when the issue API cannot be reached - that stays
#       visible in the reporting job and never touches the check job's
#       outcome, which already preserved the checker's failing exit.
set -euo pipefail

TITLE='ci: friction-upstream ledger drift repair'
MISMATCH_RE="^FAIL: ledger entry #[0-9]+: status '(open|closed|merged)' but upstream is '(open|closed|merged)'$"
UNREADABLE_RE='^UNREADABLE: #[0-9]+: '

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' \
    "${BASH_SOURCE[0]}" >&2
  exit 2
}

LOG=""
RUN_URL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log) [ $# -ge 2 ] || usage; LOG="$2"; shift 2 ;;
    --run-url) [ $# -ge 2 ] || usage; RUN_URL="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "report-friction-drift: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$LOG" ] && [ -n "$RUN_URL" ] || usage
[ -r "$LOG" ] || { echo "report-friction-drift: cannot read checker log '$LOG'" >&2; exit 2; }
[ -n "${GH_TOKEN:-}" ] || { echo "report-friction-drift: GH_TOKEN must be set (issues: write)" >&2; exit 2; }
repo="${GITHUB_REPOSITORY:-}"
[ -n "$repo" ] || { echo "report-friction-drift: GITHUB_REPOSITORY must name the target repository" >&2; exit 2; }

mismatches="$(grep -E "$MISMATCH_RE" "$LOG" || true)"
unreadable="$(grep -E "$UNREADABLE_RE" "$LOG" || true)"
count="$(grep -Ec "$MISMATCH_RE" "$LOG" || true)"

if [ -z "$mismatches" ]; then
  echo "report-friction-drift: no confirmed ledger-entry mismatches in the" \
       "checker log; nothing to file (agreement, unreadable-only and setup" \
       "failures are not drift)"
  exit 0
fi

# One open issue per title: refresh it while open, create after closure.
# Closed issues never appear in --state open, so a recurrence re-enters
# the create branch on its own.
open_json="$(gh issue list --repo "$repo" --state open --limit 200 --json number,title)"
issue_number="$(printf '%s\n' "$open_json" | TITLE="$TITLE" python3 -I -c '
import json, os, sys
try:
    rows = json.load(sys.stdin)
except ValueError as exc:
    sys.exit("report-friction-drift: gh issue list returned invalid JSON: %s" % exc)
ids = sorted(int(r["number"]) for r in rows if r.get("title") == os.environ["TITLE"])
print(ids[0] if ids else "")')"

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
{
  echo "The scheduled \`friction-upstream\` comparison found confirmed ledger drift against the upstream tracker."
  echo
  echo "- Actions run: $RUN_URL"
  echo "- Confirmed mismatches: $count"
  echo
  echo '### Confirmed mismatches (correct these ledger entries)'
  echo
  printf '%s\n' "$mismatches" | sed 's/^FAIL: /- /'
  if [ -n "$unreadable" ]; then
    echo
    echo '### Unreadable entries (not counted as drift)'
    echo
    printf '%s\n' "$unreadable" | sed 's/^UNREADABLE: /- /'
  fi
  echo
  echo "A maintainer should update the listed entries' \`status\` and \`status_checked_on\` fields in \`.github/klt-friction-ledger.json\` (workaround retirement stays pin-gated and out of scope here). While this issue is open, later scheduled runs refresh it with current evidence; after it closes, a recurrence opens a new issue."
} > "$body_file"

if [ -n "$issue_number" ]; then
  gh issue comment "$issue_number" --repo "$repo" --body-file "$body_file" >/dev/null
  echo "report-friction-drift: refreshed #$issue_number with current drift evidence ($count mismatch(es), run $RUN_URL)"
else
  url="$(gh issue create --repo "$repo" --title "$TITLE" --label loom:triage --body-file "$body_file")"
  echo "report-friction-drift: opened $url ($count mismatch(es), run $RUN_URL)"
fi
