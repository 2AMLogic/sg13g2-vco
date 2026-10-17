#!/usr/bin/env bash
# check-signoff-inventories.sh -- keep the T1 item 1/9/10 evidence honest
# (issue #243).
#
# Re-derives each audited inventory (signoff/evidence/inventory-*.json) from
# the live tree and fails, naming the file, when an inventoried file changed,
# appeared or vanished without regenerating, or when an envelope / manifest
# pin no longer matches its inventory. Refresh deliberately with:
#
#   python3 -I signoff/inventories.py --regen
#   klt signoff --manifest signoff/manifest.json \
#     --tiers-doc signoff/design-evidence-tiers.md --format json \
#     > signoff/t1-report.json
#
# Stdlib python3 only: no klt, PDK, xschem or ngspice. In particular it does
# NOT run design/netlist.sh --check (needs xschem + the PDK); the item 1
# envelope summary states that.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 -I "$ROOT/signoff/inventories.py" --check "$@"
