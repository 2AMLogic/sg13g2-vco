#!/usr/bin/env bash
# Regenerate design/vco.spice (from design/vco.sch) and design/vco_core.spice
# (from design/vco_core.sch).
#
#   design/netlist.sh            regenerate both netlists in place
#   design/netlist.sh --check    fail if the committed netlist is stale
#
# design/vco.spice and design/vco_core.spice are DERIVED files. They are never
# hand-edited: every change to the circuit is made in design/vco.sch AND
# design/vco_core.sch (in xschem) and this script re-derives the netlists and
# fails if the two schematics' devices diverge. --check is what design/run_elaborate.sh calls first, so a run
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

# netlist_one <name> <extra xschem args...>
#   Netlist design/<name>.sch with xschem into SCRATCH/<name>.spice and write
#   the normalised result to SCRATCH/<name>.normalised.spice.
# -n: netlist, -x: no X/Tk GUI, -q: quit when done, -r: do not load the
# previous session's file list. -x is load-bearing: without it xschem on macOS
# starts the Aqua GUI and hangs instead of netlisting.
netlist_one() {
  local name="$1"; shift
  mkdir -p "${SCRATCH}/${name}"
  xschem -n -x -q -r --rcfile "${XSCHEMRC}" "$@" -o "${SCRATCH}/${name}" \
         "${DESIGN_DIR}/${name}.sch" >"${SCRATCH}/${name}.xschem.log" 2>&1 || {
    echo "error: xschem netlisting of ${name}.sch failed; log follows." >&2
    cat "${SCRATCH}/${name}.xschem.log" >&2
    exit 1
  }
  if [[ ! -f "${SCRATCH}/${name}/${name}.spice" ]]; then
    echo "error: xschem produced no ${name}.spice; log follows." >&2
    cat "${SCRATCH}/${name}.xschem.log" >&2
    exit 1
  fi
  sed -e "s|^\*\* sch_path: .*|** sch_path: design/${name}.sch|" \
      -e "s/[[:space:]]*\$//" "${SCRATCH}/${name}/${name}.spice" \
      > "${SCRATCH}/${name}.normalised.spice"
}

# vco.spice: the flat bench. vco_core.spice: the device-only subcircuit; its
# `lvs_netlist` switch makes xschem emit a real `.subckt vco_core ... .ends`
# (the default for a top-level schematic is a `**.subckt` comment), and the
# trailing `.end` is dropped so the file can be `.include`d into a parent
# deck without terminating it.
netlist_one vco
netlist_one vco_core --tcl "set lvs_netlist 1"
sed -i -e '/^\.end$/d' "${SCRATCH}/vco_core.normalised.spice"

# Drift guard: the core must stay the same circuit as the bench. Compare the
# device lines (the bench's, minus its sources and `.save`; the core's, between
# `.subckt` and `.ends`) with the bench's ground node `0` read as the core's
# `VSS`, order-insensitive.
devices() { # <file> <ground-token-to-map-to-0 or ->
  grep -E '^[XRCLQMD]' "$1" | sed -E "s/[[:space:]]+$2([[:space:]]|\$)/ 0\1/g" | sort
}
if ! diff -u <(devices "${SCRATCH}/vco.normalised.spice" -) \
             <(devices "${SCRATCH}/vco_core.normalised.spice" VSS); then
  echo "error: design/vco_core.sch and design/vco.sch no longer describe the" >&2
  echo "       same devices (diff above: - bench, + core). Edit both together." >&2
  exit 1
fi

status=0
for name in vco vco_core; do
  TARGET="${DESIGN_DIR}/${name}.spice"
  NORM="${SCRATCH}/${name}.normalised.spice"
  if [[ "${MODE}" == "check" ]]; then
    if [[ ! -f "${TARGET}" ]]; then
      echo "error: ${TARGET} does not exist; run design/netlist.sh." >&2
      status=1
    elif ! diff -u "${TARGET}" "${NORM}"; then
      echo "error: design/${name}.spice is STALE with respect to design/${name}.sch." >&2
      echo "       Re-derive it with:  design/netlist.sh" >&2
      status=1
    else
      echo "netlist: design/${name}.spice is current with design/${name}.sch"
    fi
  else
    cp "${NORM}" "${TARGET}"
    echo "netlist: wrote design/${name}.spice from design/${name}.sch (xschem $(xschem --version 2>&1 | head -1))"
  fi
done
exit "${status}"
