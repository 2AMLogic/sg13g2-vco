#!/usr/bin/env bash
# DR-004 STAGE 2, row 4: the ISF phase-noise estimator at the 18 supply
# sub-corners (issue #113).
#
#   sim/phase-noise/run_supply_stage2.sh --list     # PDK-free: print the 18 points
#   sim/phase-noise/run_supply_stage2.sh            # run (needs the pinned PDK)
#
# Each sub-corner is ONE invocation of run_isf_pilot.sh -- the same estimator,
# the same method statement and the same limits -- with the corner and rail
# passed through its PILOT_* environment overrides. Each therefore mints its
# own append-only phase-noise record, whose summary CSV carries the identity
# rows (mos, cap, hbt, temp_c, vsup_v) the stage-2 report matches on:
#
#   sim/oscillator-core/report_supply_stage2.sh --stage2-pn <dir>/<id> ...
#
# COST: ~14 CPU-hours for the 18 points (DR-004: ~0.80 CPU-h/corner at
# stage 1's rate; this netlist's measured ISF pilot is ~0.8 CPU-h). It is a
# fleet job; do not hand-launch it on a shared dispatch host.
#
# THE METHOD AND ITS LIMITS are run_isf_pilot.sh's and are restated in every
# record: ngspice has no PSS/pnoise; L(df) is an ISF (Hajimiri-Lee) derivation
# from impulse-train transients at ONE operating point; the reported spread is
# the sample sd over injected-charge realisations, not a Monte-Carlo variance;
# the non-PDK inductor model's bars apply. This driver adds nothing to the
# estimator.
set -euo pipefail

EXPERIMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"

# shellcheck source=../oscillator-core/supply_stage2.sh
source "${SIM_DIR}/oscillator-core/supply_stage2.sh"
s2_check_enumeration || exit 2

case "${1:-}" in
  --list)
    echo "process rail_v temp_c mos cap hbt"
    s2_enumerate
    exit 0 ;;
  "") ;;
  *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
esac

# Refuse a local multi-point grid when the fleet backend is exported (issue
# #176, extending #160). A single-point child cannot enforce this parent's
# multi-corner policy, so the check lives here, after the read-only --list and
# before any child is invoked. The count comes from the stage-2 enumeration.
# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"
require_local_grid_ok "$(s2_enumerate | wc -l | tr -d ' ')" || exit 1

fail=0
while read -r proc rail temp mos cap hbt; do
  echo "== phase-noise stage 2: ${proc} ${rail} V ${temp} C"
  PILOT_MOS="${mos}" PILOT_CAP="${cap}" PILOT_HBT="${hbt}" PILOT_TEMP="${temp}" \
  PILOT_VSUP_V="${rail}" "${EXPERIMENT_DIR}/run_isf_pilot.sh" || fail=$((fail + 1))
done < <(s2_enumerate)

if [[ ${fail} -gt 0 ]]; then
  echo "error: ${fail} sub-corner(s) failed" >&2
  exit 1
fi
