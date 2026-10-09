#!/usr/bin/env bash
# Wrapper for check-grader-spec-agreement.py (issue #138): verifies that the
# shell constants the simulation graders copy from the ratified spec still
# agree with spec/target-spec.md and DR-004's stage-2 condition. Agreement
# only -- it never authorises a changed requirement. Stdlib python3; no
# simulator, no PDK.
#
# Usage: check-grader-spec-agreement.sh [--root DIR]
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python3}" -I "$HERE/check-grader-spec-agreement.py" "$@"
