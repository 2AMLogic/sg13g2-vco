#!/usr/bin/env bash
# Gate (issue #143): no sim/**/records/ paired report/deck sha256 mismatch
# (reports/<n>.json netlist_sha256 vs decks/<n>.spice), except the explicit,
# justified INTEGRITY_ALLOWLIST in record_currency.py. Issue #173: a paired
# report that is not valid JSON or lacks exactly one well-formed (64 lowercase
# hex) netlist_sha256 is a failure too, reported with its path and reason.
# Unpaired/legacy reports are listed as unchecked, never as verified and never
# as a failure. Separate from source currency. PDK-free, stdlib python3 + git.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 -I "$ROOT/.github/scripts/record_currency.py" --root "$ROOT" integrity
