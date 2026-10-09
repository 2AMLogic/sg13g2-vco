#!/usr/bin/env bash
# Cold-start:  sim/bn-substrate-tank/run_tank_ab.sh
#
# Issue #79 tank A/B: varactor bn tied to the tank node (pre-#79) vs to 0
# (post-#79), on the passive differential tank, small-signal AC.
# Every unit goes to the Spot batch fleet as a `klt sim` request (host rule:
# no hand-launched ngspice grids).  Requests are submitted one per
# (variant, mos corner, Vctrl); each carries its own process x temperature
# matrix.  The client is klayout-tools==0.6.0 in a throwaway uvx environment:
# the fleet runner image is klt 0.5.0 and refuses a 0.7.0 client
# (batch_runner_version_mismatch), 0.5.0 has no batch backend, 0.6.0 is the one
# that is both accepted and batch-capable -- but it does not stage .include
# targets, so make_requests.py inlines the inductor model.
#
# If a submit fails the unit is recorded as failed in the record and the
# script does NOT fall back to running anything locally.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
# Issue #93 candidates: TANK_AB_ARGS="--cells 14 --mim-um 1.14 --candidate NAME"
# TANK_AB_LABEL=NAME adds a suffix to the record id.  Unset = the original #79 run.
STAMP="$(date -u +%Y%m%d-%H%M%S)-$(git -C "${REPO_ROOT}" rev-parse --short HEAD)${TANK_AB_LABEL:+-${TANK_AB_LABEL}}"
REC="${HERE}/records/${STAMP}"
WORK="${REPO_ROOT}/sim/build/bn-substrate-tank/${STAMP}"
mkdir -p "${REC}/reports" "${REC}/decks" "${WORK}"
python3 -I "${HERE}/make_requests.py" "${WORK}" ${TANK_AB_ARGS:-} >/dev/null
export KLT_SIM_BACKEND=batch
fails=0
for req in "${WORK}"/*/*/request.json; do
  d="$(dirname "${req}")"; v="$(basename "$(dirname "${d}")")"; p="$(basename "${d}")"
  echo "== ${v}/${p}"
  cp "${d}/tank.spice" "${REC}/decks/${v}__${p}.spice"
  cp "${d}/request.json" "${REC}/decks/${v}__${p}.request.json"
  cp "${d}/cell.json" "${REC}/decks/${v}__${p}.cell.json"
  (cd "${d}" && uvx --from "klayout-tools==0.6.0" klt sim request.json --backend batch \
      --format json -o out > "${REC}/reports/${v}__${p}.json" 2> "${REC}/reports/${v}__${p}.err") || true
  [[ -s "${REC}/reports/${v}__${p}.json" ]] || { echo "   NO REPORT"; fails=$((fails+1)); }
done
echo "${REC}"
echo "submit failures (no report): ${fails}"
