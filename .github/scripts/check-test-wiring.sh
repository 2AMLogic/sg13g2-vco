#!/usr/bin/env bash
# Orphan-test guard (issue #228): fails when a tracked shell self-test is not
# reachable through an executable chain rooted in a check-all.sh target that
# the `test` aggregate runs. Parses only; runs no registered test. Registry:
# .github/scripts/test-wiring.tsv. Contract: test_wiring_check.py header.
#
#   check-test-wiring.sh [--root DIR] [--registry FILE]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I "$HERE/test_wiring_check.py" "$@"
