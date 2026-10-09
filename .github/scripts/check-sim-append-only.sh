#!/usr/bin/env bash
# PR-time gate: sim/ evidence is append-only (issue #88).
#
# Fails if the diff from the merge-base of the base ref to HEAD contains any
# status other than A (added) for a path under a records/, netlist-snapshots/
# or corners/ directory below sim/ (any depth, so nested experiment dirs such
# as sim/inductor-model/em-extraction/records/ are covered).  Renames are not
# detected (--no-renames), so a move shows as D + A and fails.  Fails closed
# when the base ref or merge-base cannot be resolved.  There is deliberately
# no exemption mechanism: a correction is a new, superseding record.
#
# Usage: check-sim-append-only.sh [--root DIR] [--base REF]
#   --base defaults to $SIM_APPEND_ONLY_BASE, else origin/$GITHUB_BASE_REF.
# Pure bash + git; no PDK, no klt.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BASE="${SIM_APPEND_ONLY_BASE:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    *) echo "usage: $0 [--root DIR] [--base REF]" >&2; exit 2 ;;
  esac
done

if [ -z "$BASE" ] && [ -n "${GITHUB_BASE_REF:-}" ]; then
  git -C "$ROOT" fetch --no-tags origin "$GITHUB_BASE_REF" >/dev/null 2>&1 || true
  BASE="origin/$GITHUB_BASE_REF"
fi

if [ -z "$BASE" ]; then
  echo "FAIL: no base ref (pass --base, set SIM_APPEND_ONLY_BASE, or run in a pull_request job)" >&2
  exit 1
fi

if ! git -C "$ROOT" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
  echo "FAIL: base ref '$BASE' is not available (fetch it, e.g. fetch-depth: 0)" >&2
  exit 1
fi

MB="$(git -C "$ROOT" merge-base "$BASE" HEAD 2>/dev/null)" || MB=""
if [ -z "$MB" ]; then
  echo "FAIL: no merge-base between '$BASE' and HEAD (shallow clone?)" >&2
  exit 1
fi

DIFF="$(mktemp)"
trap 'rm -f "$DIFF"' EXIT
if ! git -C "$ROOT" diff --name-status --no-renames -z "$MB" HEAD -- sim >"$DIFF"; then
  echo "FAIL: git diff failed" >&2
  exit 1
fi

# -z output: STATUS NUL PATH NUL ...
bad=0
while IFS= read -r -d '' status && IFS= read -r -d '' path; do
  if [[ "$path" =~ ^sim/([^/]+/)+(records|netlist-snapshots|corners)/ ]] && [ "$status" != "A" ]; then
    echo "FAIL: $status $path (sim evidence is append-only; add a new superseding record instead)" >&2
    bad=$((bad + 1))
  fi
done <"$DIFF"

if [ "$bad" -ne 0 ]; then
  echo "$bad append-only violation(s) vs merge-base ${MB:0:12} of $BASE" >&2
  exit 1
fi
echo "OK: sim evidence append-only vs merge-base ${MB:0:12} of $BASE"
