#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# pdk_env.sh -- resolve the IHP-Open-PDK install and build the scratch PDK-root
# overlay that `klt gen --pdk-pcell` needs to reach the SG13G2 PCell library.
#
# WHY AN OVERLAY IS NEEDED.  IHP-Open-PDK ships `pycell4klayout-api` and
# `pypreprocessor` as *git submodules* under libs.tech/klayout/python/, and a
# GitHub source tarball never carries submodule contents -- so in a tarball
# install `import sg13g2_pycell_lib` dies at `from cni.dlo import PCellWrapper`
# and no SG13G2 PCell is reachable.  `klt 0.6.0` diagnoses this precisely and
# attributes it to the PDK (already filed upstream as
# 2AMLogic/klayout-tools#1630 -- do not re-file).
#
# The repair is NOT ours to make in the shared PDK install.  This script
# therefore reuses the committed, revision-pinned workaround already in this
# repo --
#   sim/inductor-model/em-extraction/scripts/setup_pdk_overlay.sh
# -- which builds a symlink tree of libs.tech/klayout with those two submodule
# directories replaced by real checkouts, and then wraps it in a second symlink
# tree shaped like a PDK *root* so `klt --pdk-root` can be pointed at it.
#
# Sourced by generate.sh; exports PDK, PDK_OVERLAY_ROOT, PDK_OVERLAY_JSON.

set -euo pipefail

LAYOUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${LAYOUT_DIR}/.." && pwd)"
BUILD="${LAYOUT_BUILD_DIR:-${LAYOUT_DIR}/build}"

# --- resolve the PDK (same search order as sim/inductor-model/em-extraction) --
if [[ -n "${IHP_PDK_ROOT:-}" ]]; then
  PDK="${IHP_PDK_ROOT}"
elif [[ -n "${PDK_ROOT:-}" && -d "${PDK_ROOT}/ihp-sg13g2" ]]; then
  PDK="${PDK_ROOT}/ihp-sg13g2"
elif [[ -d "${HOME}/share/pdk/ihp-sg13g2" ]]; then
  PDK="${HOME}/share/pdk/ihp-sg13g2"
else
  echo "error: cannot find an IHP-Open-PDK install; set IHP_PDK_ROOT" >&2
  exit 1
fi
PDK_KLAYOUT="${PDK}/libs.tech/klayout"
[[ -d "${PDK_KLAYOUT}" ]] || { echo "error: no ${PDK_KLAYOUT}" >&2; exit 1; }

mkdir -p "${BUILD}"

# --- stage 1: the libs.tech/klayout overlay with populated submodules ---------
KL_OVERLAY="${BUILD}/pdk-klayout-overlay"
PDK_OVERLAY_JSON="${BUILD}/pdk_overlay.json"
bash "${REPO_ROOT}/sim/inductor-model/em-extraction/scripts/setup_pdk_overlay.sh" \
  "${PDK_KLAYOUT}" "${KL_OVERLAY}" > "${PDK_OVERLAY_JSON}"

# --- stage 2: a PDK-root-shaped tree around it -------------------------------
# `klt --pdk-root <dir>` expects <dir>/<variant>/libs.tech/..., so mirror the
# real root by symlink and swap only libs.tech/klayout for the stage-1 overlay.
PDK_OVERLAY_ROOT="${BUILD}/pdk-root-overlay"
rm -rf "${PDK_OVERLAY_ROOT}"
mkdir -p "${PDK_OVERLAY_ROOT}/ihp-sg13g2/libs.tech"
for e in "${PDK}"/*; do
  b="$(basename "$e")"
  [[ "$b" == "libs.tech" ]] && continue
  ln -s "$e" "${PDK_OVERLAY_ROOT}/ihp-sg13g2/${b}"
done
for e in "${PDK}"/libs.tech/*; do
  b="$(basename "$e")"
  [[ "$b" == "klayout" ]] && continue
  ln -s "$e" "${PDK_OVERLAY_ROOT}/ihp-sg13g2/libs.tech/${b}"
done
ln -s "${KL_OVERLAY}" "${PDK_OVERLAY_ROOT}/ihp-sg13g2/libs.tech/klayout"

export PDK PDK_KLAYOUT PDK_OVERLAY_ROOT PDK_OVERLAY_JSON
