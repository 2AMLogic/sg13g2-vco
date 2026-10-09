#!/usr/bin/env bash
# Friction-ledger gate (issue #146): offline, PDK-free. Forwards arguments
# (e.g. --root DIR) to check_klt_friction.py; see its docstring for the rules.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 -I "$ROOT/.github/scripts/check_klt_friction.py" "$@"
