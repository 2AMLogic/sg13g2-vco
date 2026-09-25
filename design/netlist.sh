#!/usr/bin/env bash
# Regenerate design/vco.spice from design/vco.sch.
#
#   design/netlist.sh            regenerate design/vco.spice in place
#   design/netlist.sh --check    fail if the committed netlist is stale
#
# design/vco.spice is a DERIVED file. It is never hand-edited: every change to
# the circuit is made in design/vco.sch (in xschem) and this script re-derives
# the netlist. --check is what design/run_elaborate.sh calls first, so a run
# can never silently simulate a netlist that has drifted from the schematic.
#
# Requires: xschem on PATH and an IHP-Open-PDK install (for the sg13g2_pr
# symbol library). sim/env.sh resolves the PDK; xschem's own xschemrc from
# that install puts libs.tech/xschem on XSCHEM_LIBRARY_PATH.
#
# Normalisation applied to xschem's raw output, and why:
#   1. the `** sch_path:` header line carries the ABSOLUTE path of the
#      schematic on the machine that ran xschem -- rewritten to the
#      repo-relative path so the committed netlist is machine-independent;
#   2. trailing whitespace is stripped (xschem emits some).
# Nothing else is touched: the device lines are xschem's verbatim.
set -euo pipefail

DESIGN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DESIGN_DIR}/.." && pwd)"
SIM_DIR="${REPO_ROOT}/sim"

MODE="write"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
elif [[ $# -gt 0 ]]; then
  echo "usage: design/netlist.sh [--check]" >&2
  exit 2
fi

if ! command -v xschem >/dev/null 2>&1; then
  echo "error: xschem not found on PATH." >&2
  echo "       design/vco.spice is derived from design/vco.sch by xschem;" >&2
  echo "       install xschem (>= 3.4.x) and re-run." >&2
  exit 1
fi

# shellcheck source=../sim/env.sh
source "${SIM_DIR}/env.sh"

if [[ -z "${PDK_ROOT:-}" || ! -d "${PDK_ROOT}/${PDK}/libs.tech/xschem/sg13g2_pr" ]]; then
  echo "error: no ${PDK} xschem symbol library under PDK_ROOT=${PDK_ROOT:-unset}." >&2
  echo "       design/vco.sch instantiates sg13g2_pr/{npn13G2v,sg13_svaricap," >&2
  echo "       cap_cmim,inductor}.sym; see sim/pdk.json for the pinned release." >&2
  exit 1
fi

XSCHEMRC="${PDK_ROOT}/${PDK}/libs.tech/xschem/xschemrc"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/sg13g2-vco-netlist.XXXXXX")"
trap 'rm -rf "${SCRATCH}"' EXIT

# -q: no GUI, -n: netlist, -r: do not load the previous session's file list.
xschem -n -q -r --rcfile "${XSCHEMRC}" -o "${SCRATCH}" \
       "${DESIGN_DIR}/vco.sch" >"${SCRATCH}/xschem.log" 2>&1 || {
  echo "error: xschem netlisting failed; log follows." >&2
  cat "${SCRATCH}/xschem.log" >&2
  exit 1
}

RAW="${SCRATCH}/vco.spice"
if [[ ! -f "${RAW}" ]]; then
  echo "error: xschem produced no ${RAW}; log follows." >&2
  cat "${SCRATCH}/xschem.log" >&2
  exit 1
fi

sed -e "s|^\*\* sch_path: .*|** sch_path: design/vco.sch|" \
    -e "s/[[:space:]]*$//" "${RAW}" > "${SCRATCH}/vco.normalised.spice"

TARGET="${DESIGN_DIR}/vco.spice"
if [[ "${MODE}" == "check" ]]; then
  if [[ ! -f "${TARGET}" ]]; then
    echo "error: ${TARGET} does not exist; run design/netlist.sh." >&2
    exit 1
  fi
  if ! diff -u "${TARGET}" "${SCRATCH}/vco.normalised.spice"; then
    echo "error: design/vco.spice is STALE with respect to design/vco.sch." >&2
    echo "       Re-derive it with:  design/netlist.sh" >&2
    exit 1
  fi
  echo "netlist: design/vco.spice is current with design/vco.sch"
else
  cp "${SCRATCH}/vco.normalised.spice" "${TARGET}"
  echo "netlist: wrote design/vco.spice from design/vco.sch (xschem $(xschem --version 2>&1 | head -1))"
fi
