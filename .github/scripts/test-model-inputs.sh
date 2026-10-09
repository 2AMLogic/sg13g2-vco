#!/usr/bin/env bash
# Self-test target for the committed model-input integrity gate (issue #139).
# Synthetic fixtures only: stdlib python3, no PDK, no simulation.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 -I "$ROOT/.github/scripts/test_model_inputs.py"
