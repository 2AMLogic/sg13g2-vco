#!/usr/bin/env bash
# Presence check: a diff that modifies spec/target-spec.md must, in the same
# diff, add or modify a decision record spec/decision-records/DR-NNN-slug.md
# (NNN = three digits, slug = lowercase alnum words joined by hyphens;
# TEMPLATE.md does not count). Not a judgment on whether the DR justifies the
# change -- review does that. A DR-only diff passes.
#
# Usage: check-spec-change-has-dr.sh [--root DIR] [--base REF] [--head REF]
#   Diffs BASE...HEAD (merge-base form). Defaults: base=origin/main, head=HEAD.
set -eu

root="."; base="origin/main"; head="HEAD"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$root"
# Added/Copied/Modified/Renamed/Type-changed; deletions do not count.
files="$(git diff --name-only --diff-filter=ACMRT "$base...$head")"
# Also catch a deletion of the spec itself as a modification.
spec_touched="$(git diff --name-only "$base...$head" -- spec/target-spec.md)"

if [ -z "$spec_touched" ]; then
  echo "OK: spec/target-spec.md not modified; no decision record required."
  exit 0
fi

dr_re='^spec/decision-records/DR-[0-9]{3}-[a-z0-9]+(-[a-z0-9]+)*\.md$'
if printf '%s\n' "$files" | grep -Eq "$dr_re"; then
  echo "OK: spec/target-spec.md modified with decision record:"
  printf '%s\n' "$files" | grep -E "$dr_re" | sed 's/^/  /'
  exit 0
fi

echo "FAIL: spec/target-spec.md is modified but this diff adds/modifies no" >&2
echo "decision record named spec/decision-records/DR-NNN-slug.md" >&2
echo "(see spec/decision-records/TEMPLATE.md; TEMPLATE.md does not count)." >&2
others="$(printf '%s\n' "$files" | grep -E '^spec/decision-records/' || true)"
if [ -n "$others" ]; then
  echo "Decision-record files in diff with non-conforming names:" >&2
  printf '%s\n' "$others" | sed 's/^/  /' >&2
fi
exit 1
