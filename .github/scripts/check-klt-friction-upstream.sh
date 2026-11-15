#!/usr/bin/env bash
# Upstream-state gate for the friction ledger (issue #333): the networked
# companion of check-klt-friction.sh. Forwards arguments (e.g. --root DIR,
# --states-file PATH) to check_klt_friction_upstream.py; see its docstring
# for the three-way status mapping and the exit-code contract (3 = upstream
# unreadable, never agreement).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 -I "$ROOT/.github/scripts/check_klt_friction_upstream.py" "$@"
