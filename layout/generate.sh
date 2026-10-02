#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# generate.sh -- regenerate layout/vco.gds and layout/vco_manifest.json from
# the PDK, end to end, with no GUI and no hand-editing step.
#
# Cold-start invocation:
#
#   layout/generate.sh
#
# Stages (each skippable via LAYOUT_STAGES):
#   devices   `klt gen --pdk-pcell` one stream per distinct PDK PCell call
#   ports     measure each stream's own terminal geometry (klayout -zz -r)
#   requests  emit the klt gen-compose / klt draw request documents
#   compose   run them: 2 varactor banks, the bias core, the drawn wiring, top
#   connectivity  klt extract the result and check every net (not LVS -- see #62)
#   verify    read the composed stream back and write the manifest
#
#   LAYOUT_STAGES="requests compose verify" layout/generate.sh
#
# REQUIREMENTS (all verified up front and recorded in the manifest):
#   * klt       (klayout-tools) -- the generation and composition driver
#   * klayout   -- for the two read-back helper scripts
#   * an IHP-Open-PDK install -- $IHP_PDK_ROOT, $PDK_ROOT/ihp-sg13g2, or
#     ~/share/pdk/ihp-sg13g2
#
# This is NOT a sign-off flow.  `klt draw` is PDK-unaware by construction and
# `klt gen-compose`'s own `nets[].routed` is explicitly not a DRC guarantee.
# DRC closure is issue #61 and LVS closure is issue #62; see PROVENANCE.md.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"
BUILD="${LAYOUT_BUILD_DIR:-${HERE}/build}"

LAYOUT_STAGES="${LAYOUT_STAGES:-devices ports requests compose connectivity verify}"
stage() { [[ " ${LAYOUT_STAGES} " == *" $1 "* ]]; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not on PATH" >&2; exit 1; }; }
need klt
need klayout
need python3

mkdir -p "${BUILD}/dev" "${BUILD}/req" "${BUILD}/log"

# shellcheck source=scripts/pdk_env.sh
source "${HERE}/scripts/pdk_env.sh"

KLT_VERSION="$(klt --version 2>&1 | head -1)"
KLAYOUT_VERSION="$(klayout -v 2>&1 | head -1)"
echo "== tools: ${KLT_VERSION} / ${KLAYOUT_VERSION}"
echo "== pdk:   ${PDK}"
echo "== overlay: ${PDK_OVERLAY_ROOT}"

PDKARGS=(--pdk ihp-sg13g2 --pdk-root "${PDK_OVERLAY_ROOT}")
# KLayout emits a `psutil` warning per PCell-library load that is pure noise.
# KLayout emits a `psutil` warning per library load that is pure noise, and
# its bundled Python prints "Could not import tkinter" on hosts whose
# KLayout has no GUI Tk -- also pure noise for every headless use here
# (PCell evaluation without callbacks is exactly how this flow runs; the
# rppd `Calculate:` limitation is handled by supplying `l` directly).
filt() { grep -v -e "^Warning: Python package 'psutil' not found!$" \
                 -e "^Could not import tkinter. No callback support.$" \
                 -e "^Warning: No tkinter installed. No callback support.*$" \
                 || true; }
KLSCRATCH="${BUILD}/klayout-scratch"
mkdir -p "${KLSCRATCH}"

# --------------------------------------------------------------- devices --
if stage devices; then
  echo "== devices: instantiating the PDK's own PCells with klt gen"
  python3 "${HERE}/scripts/floorplan.py" "${BUILD}" devices > "${BUILD}/log/devices.tsv"
  while IFS=$'\t' read -r id kind params; do
    [[ -n "${id}" ]] || continue
    pcell="$(python3 -c "
import json,sys
d=json.load(open('${BUILD}/devices.json'));print(d['${id}']['pcell'])")"
    klt gen --pdk-pcell "${pcell}" "${PDKARGS[@]}" \
      --params "${params}" --cell-name "vco_${id}" \
      -o "${BUILD}/dev/${id}.gds" --format json 2>&1 \
      | filt > "${BUILD}/dev/${id}.gen.json"
    python3 - "${BUILD}/dev/${id}.gen.json" "${id}" <<'PY'
import json, sys
p, dev = sys.argv[1], sys.argv[2]
d = json.load(open(p))
if "error" in d:
    raise SystemExit("klt gen failed for %s: %s" % (dev, d["error"]))
print("  %-12s %-22s bbox %.3f x %.3f um" % (
    dev, d["generator"],
    d["bbox_um"]["x1"] - d["bbox_um"]["x0"],
    d["bbox_um"]["y1"] - d["bbox_um"]["y0"]))
PY
    # Mask-grid step: IHP rules 3.1/3.2 require 5 nm vertices and exact
    # 0/45/90 edges; PCell arithmetic guarantees neither (see
    # scripts/snap_grid.py).  Runs before port measurement, so every
    # measured coordinate is the snapped one the stream really carries.
    KLAYOUT_PATH="${KLSCRATCH}" klayout -zz -r "${HERE}/scripts/snap_grid.py" \
      -rd gds="${BUILD}/dev/${id}.gds" 2>&1 | filt | sed 's/^/  /'
  done < "${BUILD}/log/devices.tsv"
fi

# ----------------------------------------------------------------- ports --
if stage ports; then
  echo "== ports: measuring each generated stream's own terminal geometry"
  python3 "${HERE}/scripts/floorplan.py" "${BUILD}" devices > "${BUILD}/log/devices.tsv"
  while IFS=$'\t' read -r id kind params; do
    [[ -n "${id}" ]] || continue
    : "${params}"
    KLAYOUT_PATH="${KLSCRATCH}" klayout -zz -r "${HERE}/scripts/measure_ports.py" \
      -rd gds="${BUILD}/dev/${id}.gds" -rd kind="${kind}" \
      -rd out="${BUILD}/dev/${id}.ports.json" 2>&1 | filt | sed 's/^/  /'
  done < "${BUILD}/log/devices.tsv"
fi

# -------------------------------------------------------------- requests --
if stage requests; then
  echo "== requests: emitting the klt gen-compose / klt draw documents"
  python3 "${HERE}/scripts/floorplan.py" "${BUILD}" requests | sed 's/^/  /'
  # The PDK-root overlay is a per-host scratch path, so the committed request
  # documents carry a token and it is substituted here, never baked in.
  for f in "${BUILD}"/req/*.json; do
    python3 - "$f" "${PDK_OVERLAY_ROOT}" "${BUILD}" <<'PY'
import sys
p, root, build = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read().replace("@PDK_ROOT@", root).replace("@BUILD@", build)
open(p, "w").write(s)
PY
  done
fi

# --------------------------------------------------------------- compose --
run_compose() {  # run_compose <request> <label>
  local req="$1" label="$2" rc=0
  klt gen-compose "${req}" --format json 2>&1 | filt > "${BUILD}/log/${label}.json" || rc=$?
  python3 - "${BUILD}/log/${label}.json" "${label}" "${rc}" <<'PY'
import json, sys
p, label, rc = sys.argv[1], sys.argv[2], int(sys.argv[3])
d = json.load(open(p))
if "error" in d:
    raise SystemExit("klt gen-compose failed for %s: %s" % (label, d["error"]))
nets = d.get("nets", [])
print("  %-14s cell=%s  blocks=%d  nets=%d routed=%d  unrouted=%s  exit=%d" % (
    label, d["cell_name"], len(d.get("blocks", [])), len(nets),
    sum(1 for n in nets if n.get("status") == "routed"),
    d.get("unrouted_nets", []), rc))
for w in d.get("warnings", []):
    print("    warning: %s" % w)
PY
}

if stage compose; then
  echo "== compose: placing the banks, the bias core, the wiring and the top"
  run_compose "${BUILD}/req/varbank_p.json" varbank_p
  run_compose "${BUILD}/req/varbank_n.json" varbank_n
  run_compose "${BUILD}/req/core.json" core
  klt draw --params "${BUILD}/req/wiring.json" --cell-name vco_wiring \
    -o "${BUILD}/vco_wiring.gds" --format json 2>&1 \
    | filt > "${BUILD}/log/wiring.json"
  python3 - "${BUILD}/log/wiring.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if "error" in d:
    raise SystemExit("klt draw failed: %s" % d["error"])
print("  %-14s cell=%s  shapes=%s  labels=%s" % (
    "wiring", d.get("cell_name"), d.get("shape_count"), d.get("label_count")))
PY
  run_compose "${BUILD}/req/top.json" top
  # Mask-grid step over the composed stream: snaps the hand-drawn wiring
  # rectangles, the router's inter-core wires and every fractional instance
  # origin (via ladders, taps) onto the same 5 nm grid the device streams
  # were snapped to.  Runs BEFORE connectivity so the extraction evidence
  # describes the final geometry.
  KLAYOUT_PATH="${KLSCRATCH}" klayout -zz -r "${HERE}/scripts/snap_grid.py" \
    -rd gds="${BUILD}/vco.gds" 2>&1 | filt | sed 's/^/  /'
fi

# ---------------------------------------------------------- connectivity --
# Evidence for this phase's "all 9 nets are routed" criterion, read out of the
# stream by `klt extract` rather than asserted.  Two extractions:
#   full     -- every piece of routing metal must join an extracted net
#               (dead_metal[] empty); VDD/OUTP/OUTN come back merged, because
#               an inductor is a DC short and klt's sg13g2 deck models no
#               inductor device.
#   nospiral -- the same layout with the two spiral instances deleted, which
#               separates the three tank nodes iff nothing else shorts them.
# NOT an LVS run: `klt lvs` closure is issue #62.
if stage connectivity; then
  echo "== connectivity: extracting the stream to check every net"
  KLAYOUT_PATH="${KLSCRATCH}" klayout -zz -r "${HERE}/scripts/prune_spirals.py" \
    -rd gds="${BUILD}/vco.gds" -rd out="${BUILD}/vco_nospiral.gds" \
    -rd cell=inductor2 2>&1 | filt | sed 's/^/  /'
  for v in vco vco_nospiral; do
    klt extract "${BUILD}/${v}.gds" --deck sg13g2 "${PDKARGS[@]}" \
      -o "${BUILD}/${v}_extracted.sp" --format json 2>&1 \
      | filt > "${BUILD}/log/extract_${v}.json" || true
    python3 - "${BUILD}/log/extract_${v}.json" "${v}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if "error" in d:
    raise SystemExit("klt extract failed for %s: %s" % (sys.argv[2], d["error"]))
print("  %-14s nets=%d  dead_metal_clusters=%d  %s" % (
    sys.argv[2], d.get("net_count", 0), len(d.get("dead_metal", [])),
    sorted(n.get("name") for n in d.get("nets", []))))
PY
  done
fi

# ---------------------------------------------------------------- verify --
if stage verify; then
  echo "== verify: reading the composed stream back"
  KLAYOUT_PATH="${KLSCRATCH}" klayout -zz -r "${HERE}/scripts/verify.py" \
    -rd gds="${BUILD}/vco.gds" -rd out="${BUILD}/verify.json" 2>&1 | filt
  cp "${BUILD}/vco.gds" "${HERE}/vco.gds"
  python3 "${HERE}/scripts/manifest.py" "${BUILD}" "${HERE}/vco_manifest.json" \
    --klt "${KLT_VERSION}" --klayout "${KLAYOUT_VERSION}" --pdk "${PDK}" \
    --repo "${REPO_ROOT}"
  echo "== wrote ${HERE}/vco.gds and ${HERE}/vco_manifest.json"
fi
