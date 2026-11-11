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
# Requires: `klt` (klayout-tools) on PATH and an IHP-Open-PDK install (for the
# sg13g2_pr symbol library). sim/env.sh resolves the PDK; xschem's own xschemrc
# from that install puts libs.tech/xschem on XSCHEM_LIBRARY_PATH. xschem is
# only ever run through `klt netlist`, which forces the headless flags and
# bounds the run with a timeout (a raw xschem can hang for hours).
#
# `klt netlist --relative-paths` rewrites the absolute `** sch_path:` line to
# the repo-relative path, so the committed netlist is machine-independent.
# vco_core is generated with `--block` (a real `.subckt vco_core ... .ends`,
# trailing `.end` dropped so the file can be `.include`d into a parent deck).
#
# Staleness is judged with `klt netlist --check --ignore-comments`: only
# comment lines (e.g. the pin-annotation comments of vco_core.spice) are
# ignored, never device or directive lines. Write mode rewrites a target only
# when its non-comment content is stale, so an up-to-date committed netlist
# is never rewritten byte-wise.
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

if ! command -v klt >/dev/null 2>&1; then
  echo "error: klt not found on PATH." >&2
  echo "       design/vco.spice is derived from design/vco.sch by 'klt netlist';" >&2
  echo "       install klayout-tools and re-run." >&2
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

KLT_COMMON=(--relative-paths --no-provenance-header --rcfile "${XSCHEMRC}")

# klt_netlist <name> <klt args...>: run `klt netlist` on design/<name>.sch,
# keeping its report quiet unless it fails (exit status is returned).
klt_netlist() {
  local name="$1"; shift
  klt netlist "${KLT_COMMON[@]}" "$@" "${DESIGN_DIR}/${name}.sch" \
      >"${SCRATCH}/${name}.klt.log" 2>&1 || {
    local rc=$?
    return "${rc}"
  }
}

# generate <name> <extra klt args...>: netlist design/<name>.sch into
# SCRATCH/<name>.spice (the drift guard below reads these).
generate() {
  local name="$1"; shift
  klt_netlist "${name}" "$@" -o "${SCRATCH}/${name}.spice" || {
    echo "error: klt netlist of ${name}.sch failed; log follows." >&2
    cat "${SCRATCH}/${name}.klt.log" >&2
    exit 1
  }
}

# vco.spice: the flat bench. vco_core.spice: the device-only subcircuit; its
# `lvs_netlist` switch makes xschem emit a real `.subckt vco_core ... .ends`
# (the default for a top-level schematic is a `**.subckt` comment), and the
# trailing `.end` is dropped so the file can be `.include`d into a parent
# deck without terminating it.
generate vco
generate vco_core --block

# Drift guard: the core must stay the same circuit as the bench. Compare the
# device lines (the bench's, minus its sources and `.save`; the core's, between
# `.subckt` and `.ends`) with the bench's ground node `0` read as the core's
# `VSS`, order-insensitive.
devices() { # <file> <ground-token-to-map-to-0 or ->
  grep -E '^[XRCLQMD]' "$1" | sed -E "s/[[:space:]]+$2([[:space:]]|\$)/ 0\1/g" | sort
}
if ! diff -u <(devices "${SCRATCH}/vco.spice" -) \
             <(devices "${SCRATCH}/vco_core.spice" VSS); then
  echo "error: design/vco_core.sch and design/vco.sch no longer describe the" >&2
  echo "       same devices (diff above: - bench, + core). Edit both together." >&2
  exit 1
fi

status=0
for name in vco vco_core; do
  TARGET="${DESIGN_DIR}/${name}.spice"
  BLOCK=(); [[ "${name}" == "vco_core" ]] && BLOCK=(--block)
  if [[ ! -f "${TARGET}" ]]; then
    current=1
  elif klt_netlist "${name}" "${BLOCK[@]}" --check --ignore-comments -o "${TARGET}"; then
    current=0
  else
    current=1
  fi
  if [[ "${MODE}" == "check" ]]; then
    if [[ "${current}" -eq 0 ]]; then
      echo "netlist: design/${name}.spice is current with design/${name}.sch"
    else
      [[ -f "${TARGET}" ]] && diff -u "${TARGET}" "${SCRATCH}/${name}.spice" || true
      echo "error: design/${name}.spice is STALE with respect to design/${name}.sch." >&2
      echo "       Re-derive it with:  design/netlist.sh" >&2
      status=1
    fi
  elif [[ "${current}" -eq 0 ]]; then
    echo "netlist: design/${name}.spice already current with design/${name}.sch"
  else
    cp "${SCRATCH}/${name}.spice" "${TARGET}"
    echo "netlist: wrote design/${name}.spice from design/${name}.sch ($(grep -m1 '^xschem:' "${SCRATCH}/${name}.klt.log" | awk '{print $2, $3}'))"
  fi
done
exit "${status}"
