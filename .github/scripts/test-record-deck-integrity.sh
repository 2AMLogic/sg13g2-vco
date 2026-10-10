#!/usr/bin/env bash
# Self-test target for the report/deck integrity gate (issue #143): the
# integrity cases of test_record_currency.py. Synthetic fixtures only:
# stdlib python3, no PDK, no simulation.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 -I "$ROOT/.github/scripts/test_record_currency.py" TestDeckIntegrity
