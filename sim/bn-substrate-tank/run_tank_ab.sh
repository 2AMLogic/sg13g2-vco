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
# TANK_AB_LABEL=NAME is kept as a readable suffix after the reserved id.
# Issue #203: the record id comes from reserve_record_id (sim/lib.sh), which
# atomically reserves the id (exclusive mkdir), so two runs at the same
# second/commit/label never share a record or work namespace.  The label is
# appended AFTER the reserved id (<ts>-<sha>-<rand>-<label>); the reserved
# id prefix is unique, so the label cannot cause a collision.
# Test hooks (simulator-free fixture): TANK_AB_MAKE_REQUESTS (request
# generator script) and TANK_AB_KLT (fleet client command, word-split).
# shellcheck source=../lib.sh
source "${HERE}/../lib.sh"
LABEL="${TANK_AB_LABEL:-}"
if [[ -n "${LABEL}" ]] && { [[ ! "${LABEL}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "${LABEL}" == *..* ]]; }; then
  echo "run_tank_ab: invalid TANK_AB_LABEL '${LABEL}' (allowed: [A-Za-z0-9._-], no leading . or -, no '..')" >&2
  exit 2
fi
RID="$(reserve_record_id "${REPO_ROOT}" "${HERE}")" || { echo "run_tank_ab: record id reservation failed; nothing written, nothing submitted" >&2; exit 1; }
STAMP="${RID}${LABEL:+-${LABEL}}"
REC="${HERE}/records/${STAMP}"
WORK="${REPO_ROOT}/sim/build/bn-substrate-tank/${STAMP}"
# Exclusive creation: the reserved id makes these paths ours alone; refuse to
# write into anything that already exists.
mkdir -p "${HERE}/records" "${REPO_ROOT}/sim/build/bn-substrate-tank" || exit 1
mkdir "${REC}" "${WORK}" || { echo "run_tank_ab: ${REC} or ${WORK} already exists; refusing to reuse" >&2; exit 1; }
mkdir "${REC}/reports" "${REC}/decks" || exit 1
python3 -I "${TANK_AB_MAKE_REQUESTS:-${HERE}/make_requests.py}" "${WORK}" ${TANK_AB_ARGS:-} >/dev/null || { echo "request generation failed" >&2; exit 1; }
read -ra KLT <<< "${TANK_AB_KLT:-uvx --from klayout-tools==0.6.0 klt}"
export KLT_SIM_BACKEND=batch
fails=0
for req in "${WORK}"/*/*/request.json; do
  d="$(dirname "${req}")"; v="$(basename "$(dirname "${d}")")"; p="$(basename "${d}")"
  echo "== ${v}/${p}"
  cp "${d}/tank.spice" "${REC}/decks/${v}__${p}.spice"
  cp "${d}/request.json" "${REC}/decks/${v}__${p}.request.json"
  cp "${d}/cell.json" "${REC}/decks/${v}__${p}.cell.json"
  (cd "${d}" && "${KLT[@]}" sim request.json --backend batch \
      --format json -o out > "${REC}/reports/${v}__${p}.json" 2> "${REC}/reports/${v}__${p}.err") || true
  [[ -s "${REC}/reports/${v}__${p}.json" ]] || { echo "   NO REPORT"; fails=$((fails+1)); }
done
echo "${REC}"
echo "submit failures (no report): ${fails}"
