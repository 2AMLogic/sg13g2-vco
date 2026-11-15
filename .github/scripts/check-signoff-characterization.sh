#!/usr/bin/env bash
# check-signoff-characterization.sh -- keep the T1 item 8 characterization
# report honest (issue #261).
#
# Regenerates signoff/characterization.md in memory from spec/target-spec.md,
# signoff/characterization-rows.json and sim/record-currency.json, and fails,
# naming the row, when the committed report, its generic envelope or the
# manifest pin no longer matches. Refresh deliberately with:
#
#   python3 -I signoff/characterization.py --regen
#   .github/scripts/regen-signoff.sh
#
# Stdlib python3 only: no klt, PDK or simulator. The drift self-test is
# py-tests (tests/stdlib/test_signoff_characterization.py).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 -I "$ROOT/signoff/characterization.py" --check "$@"
