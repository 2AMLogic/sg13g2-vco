#!/usr/bin/env bash
# Gate (issue #139): every committed sim/**/records/<id>-model-inputs.json must
# match its retained netlist-snapshots/<id>/model-inputs/ bytes. PDK-free,
# stdlib python3; never reads live model files. Separate from record currency.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 -I "$ROOT/.github/scripts/model_inputs_check.py" --root "$ROOT" check
