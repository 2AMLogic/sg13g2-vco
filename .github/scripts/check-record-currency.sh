#!/usr/bin/env bash
# Gate (issue #122): the committed sim/record-currency.json must equal the
# fresh classification of sim/**/records/ against design/vco.spice. Refresh:
#   python3 .github/scripts/record_currency.py write
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 -I "$ROOT/.github/scripts/record_currency.py" --root "$ROOT" check
