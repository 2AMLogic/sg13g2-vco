#!/usr/bin/env bash
# Cold-start:  sim/tank-stub-load/run_stub_ab.sh
#
# Issue #420 tank-stub A/B: the passive differential tank with and without
# the two TopMetal1 edge-pin straps, small-signal AC, quantifying the f0 /
# Q / tuning-ratio shift the straps load onto the tank nodes.
# Every unit goes to the Spot batch fleet as a `klt sim` request (host rule:
# no hand-launched ngspice grids), submitted with --wait-for-capacity 600 so
# a full shared fleet drains instead of refusing the unit.
#
# If a submit fails the unit is recorded as failed in the record and the
# script does NOT fall back to running anything locally.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
# The record id comes from reserve_record_id (sim/lib.sh), which atomically
# reserves the id (exclusive mkdir), so two runs at the same second/commit
# never share a record or work namespace.  A label is appended AFTER the
# reserved id and cannot cause a collision.
# Test hooks (simulator-free fixture): STUB_AB_MAKE_REQUESTS (request
# generator script), STUB_AB_KLT (fleet client command, word-split) and
# STUB_AB_STORE (evidence writer, default sim/store-evidence.sh).
# shellcheck source=../lib.sh
source "${HERE}/../lib.sh"
LABEL="${STUB_AB_LABEL:-}"
if [[ -n "${LABEL}" ]] && { [[ ! "${LABEL}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "${LABEL}" == *..* ]]; }; then
  echo "run_stub_ab: invalid STUB_AB_LABEL '${LABEL}' (allowed: [A-Za-z0-9._-], no leading . or -, no '..')" >&2
  exit 2
fi
RID="$(reserve_record_id "${REPO_ROOT}" "${HERE}")" || { echo "run_stub_ab: record id reservation failed; nothing written, nothing submitted" >&2; exit 1; }
STAMP="${RID}${LABEL:+-${LABEL}}"
REC="${HERE}/records/${STAMP}"
WORK="${REPO_ROOT}/sim/build/tank-stub-load/${STAMP}"
# Exclusive creation: the reserved id makes these paths ours alone; refuse
# to write into anything that already exists.
mkdir -p "${HERE}/records" "${REPO_ROOT}/sim/build/tank-stub-load" || exit 1
mkdir "${REC}" "${WORK}" || { echo "run_stub_ab: ${REC} or ${WORK} already exists; refusing to reuse" >&2; exit 1; }
mkdir "${REC}/reports" "${REC}/decks" || exit 1
python3 -I "${STUB_AB_MAKE_REQUESTS:-${HERE}/make_requests.py}" "${WORK}" ${STUB_AB_ARGS:-} >/dev/null || { echo "request generation failed" >&2; exit 1; }
# Fleet client: the repo worker's own klt (the client the 2026-11 fleet
# records used, e.g. oscillator-core/records/20261115-190000-0b056b1).  The
# 2026-10 klt-0.6.0-via-uvx workaround this directory's sibling needed is
# retired: the runner image accepts current clients.
read -ra KLT <<< "${STUB_AB_KLT:-klt}"
export KLT_SIM_BACKEND=batch
fails=0; units=0
# Collection health per unit, exposed as the exit status AFTER the whole
# batch ran (partial evidence is kept, other units are still attempted).
# A unit fails collection if a retained-input copy fails (it is then NOT
# submitted), the client exits nonzero, or the report is missing/empty.
# A successful report that carries device-model failures is NOT a collection
# failure here; the analyzers judge report content.
shopt -s nullglob
reqs=("${WORK}"/*/*/request.json)
shopt -u nullglob
for req in "${reqs[@]}"; do
  units=$((units+1))
  d="$(dirname "${req}")"; v="$(basename "$(dirname "${d}")")"; p="$(basename "${d}")"
  echo "== ${v}/${p}"
  copied=1
  for pair in "tank.spice:spice" "request.json:request.json" "cell.json:cell.json"; do
    cp "${d}/${pair%%:*}" "${REC}/decks/${v}__${p}.${pair#*:}" || copied=0
  done
  if [[ "${copied}" -ne 1 ]]; then
    echo "   INPUT COPY FAILED: not submitted" >&2; fails=$((fails+1)); continue
  fi
  (cd "${d}" && "${KLT[@]}" sim request.json --backend batch \
      --wait-for-capacity 600 --format json -o out > "${REC}/reports/${v}__${p}.json" 2> "${REC}/reports/${v}__${p}.err")
  rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    echo "   CLIENT FAILED (exit ${rc}); diagnostics kept in reports/${v}__${p}.{json,err}" >&2
    fails=$((fails+1))
  elif [[ ! -s "${REC}/reports/${v}__${p}.json" ]]; then
    echo "   NO REPORT" >&2; fails=$((fails+1))
  fi
done
echo "${REC}"
echo "units: ${units}"
echo "collection failures: ${fails}"
if [[ "${units}" -eq 0 ]]; then
  echo "run_stub_ab: empty request inventory; nothing collected" >&2; exit 1
fi
[[ "${fails}" -eq 0 ]] || exit 1
# After a clean collection each unit's raw outputs (<unit>/out/*) are packed
# into one reproducible archive and the archives go to the fleet artifact
# store; only the manifest is committed (sim/store-evidence.sh, fail closed,
# no fallback to committing bytes).
archives=()
while IFS= read -r od; do
  ud="$(dirname "${od}")"; ar="${WORK}/$(basename "$(dirname "${ud}")")__$(basename "${ud}").out.tar.gz"
  (cd "${od}" && find . -type f | LC_ALL=C sort \
      | tar --mtime='1970-01-01 00:00:00Z' --owner=0 --group=0 --numeric-owner \
            --no-recursion -T - -cf - | gzip -n > "${ar}") \
    && [[ -s "${ar}" ]] \
    || { echo "run_stub_ab: packing ${od} failed; nothing stored" >&2; exit 1; }
  archives+=("${ar}")
done < <(find "${WORK}" -mindepth 3 -maxdepth 3 -type d -name out | LC_ALL=C sort)
if [[ "${#archives[@]}" -eq 0 ]]; then
  echo "run_stub_ab: no raw outputs under ${WORK}/*/*/out; nothing to store" >&2
else
  "${STUB_AB_STORE:-${HERE}/../store-evidence.sh}" tank-stub-load "${STAMP}" "${archives[@]}" \
    || { echo "run_stub_ab: evidence store failed; no manifest written, nothing committed" >&2; exit 1; }
fi
