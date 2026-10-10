#!/usr/bin/env bash
# Self-test target for the record-currency classifier (issue #122): the
# classifier/citation unittests plus the source-capture (#122) and
# model-input capture (#133) bench tests. PDK-free,
# stdlib python3 only; no simulation is run.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
rc=0
python3 -I "$ROOT/.github/scripts/test_record_currency.py" || rc=1
"$ROOT/sim/tests/test-source-capture.sh" || rc=1
"$ROOT/sim/tests/test-model-bundle.sh" || rc=1
"$ROOT/sim/tests/test-resume-checkpoint.sh" || rc=1
exit "$rc"
