#!/usr/bin/env bash
# regen-signoff.sh — the one guarded, atomic regen entry point for
# signoff/t1-report.json (issue #360).
#
# The fence it replaced piped klt signoff's stdout straight into the record,
# and had two ways to destroy the verdict of record: a mismatched klt
# rendered a wrong record silently (exit 3 is a documented successful render
# with empty stderr, so nothing flagged it), and the redirect truncated the
# record before klt ran, so any failing render left a 0-byte file. This
# wrapper makes the wrong render impossible rather than undocumented:
#
#   1. runs python3 -I signoff/inventories.py --regen
#   2. renders the tier report to a temp file with the pinned tool
#      (ambient klt == .github/klt-version, else uvx; see klt-pin.sh)
#   3. accepts only the documented clean exits (0 or 3) and applies the
#      payload gates check-signoff.sh enforces
#   4. only then moves the temp file over signoff/t1-report.json
#
# A failed render leaves the committed record untouched.
#
# Upstream gap: `klt signoff --manifest` cannot write its render to a file —
# -o/--output is scoped to --attest — which is why callers resorted to the
# destructive redirect. Filed generically as klayout-tools#5867; workaround
# recorded in .github/klt-friction-ledger.json.
#
# Usage: .github/scripts/regen-signoff.sh
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# shellcheck source=./klt-pin.sh
. "$HERE/klt-pin.sh"

klt_pin_read || exit 1
klt_pin_resolve || exit 1

cd "$ROOT"

if ! python3 -I signoff/inventories.py --regen; then
  echo "FAIL: signoff/inventories.py --regen failed — signoff/t1-report.json left untouched" >&2
  exit 1
fi

tmp="$(mktemp)"
err="$(mktemp)"
trap 'rm -f "$tmp" "$err"' EXIT

rc=0
"${KLT_CMD[@]}" signoff --manifest signoff/manifest.json \
  --tiers-doc signoff/design-evidence-tiers.md --format json \
  >"$tmp" 2>"$err" || rc=$?

case "$rc" in
  0|3) ;;
  *)
    cat "$err" >&2
    echo "FAIL: klt signoff did not run clean (exit $rc) — 0 (all T1 met) and 3 (>=1 unmet) are the only successful renders; signoff/t1-report.json left untouched" >&2
    exit 1
    ;;
esac

if ! python3 - "$tmp" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    report = json.load(f)

assert isinstance(report, dict), "report is not a JSON object"
assert "error" not in report, f"report is a klt error envelope: {report.get('error')}"
assert report.get("schema_version") == 1, "unexpected report schema_version"
assert report.get("block") == "sg13g2-vco", "report does not grade this block"
assert report.get("kind") == "analog", "report does not grade kind=analog"
assert report.get("t1_item_count") == 11, "report does not render the 11-item checklist"
PY
then
  cat "$err" >&2
  echo "FAIL: the fresh render failed the payload gates — signoff/t1-report.json left untouched" >&2
  exit 1
fi

mv "$tmp" signoff/t1-report.json
echo "OK: signoff/t1-report.json regenerated (render ran clean, exit $rc; tool: ${KLT_CMD[*]})"
