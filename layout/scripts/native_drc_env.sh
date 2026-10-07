#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# native_drc_env.sh -- provision the THROWAWAY, pinned environment the
# IHP-native DRC run of record (layout/drc.sh) needs, inside the repo's
# gitignored scratch area.  Idempotent; touches nothing outside <env-dir>.
#
#   layout/scripts/native_drc_env.sh <env-dir>
#
# Why a separate environment.  The native run's `clean` verdict rests on
# `klt drc --expect-rule-categories N`, which first landed in klayout-tools
# PR #2803 (merge commit below) -- after the 0.6.0 release this repo's CI
# and the rest of layout/drc.sh pin.  No release carries it yet, so the run
# of record uses that exact source revision, installed into a private venv;
# the repo-wide `klt` on PATH is left alone.
#
# It also needs a standalone KLayout new enough for IHP's runset (the deck
# uses DRC-DSL features -- e.g. `absolute` in edge-angle filters -- that
# KLayout 0.28.x rejects with a NameError part-way through the deck).  The
# run of record used KLayout 0.30.12, the same version as the `klayout`
# Python module klt itself pulls in, so klt records
# `klayout_version_mismatch: false`.  On Ubuntu 24.04/amd64 this script
# fetches KLayout's own 0.30.12 package and EXTRACTS it (dpkg-deb -x) into
# <env-dir> -- nothing is installed system-wide.  Anywhere else, point
# NATIVE_KLAYOUT at a KLayout 0.30.12 binary; drc.sh refuses any other
# version rather than silently recording a different engine.
#
# Result (paths drc.sh uses):
#   <env-dir>/klt/bin/klt      klayout-tools @ KLT_REV
#   <env-dir>/bin/klayout      KLayout 0.30.12 wrapper (unless NATIVE_KLAYOUT)

set -euo pipefail

KLT_REPO="https://github.com/2AMLogic/klayout-tools"
KLT_REV="70dee3b679a6451c5f4d830fb995c5eeb16084ee"   # PR #2803 merge commit
KLAYOUT_VER="0.30.12"
KLAYOUT_DEB="klayout_${KLAYOUT_VER}-1_amd64.deb"
KLAYOUT_URL="https://www.klayout.org/downloads/Ubuntu-24/${KLAYOUT_DEB}"
# sha256 of the file served at KLAYOUT_URL on 2026-10-07; its MD5
# (0181713e60891e461d6d1664c1b8e213) matches the one klayout.de publishes.
KLAYOUT_DEB_SHA256="23480767fec91bc9a15e075a9bd6906ba85cd7fdda8b4040dde4ffc95c26a742"

ENV_DIR="${1:?usage: native_drc_env.sh <env-dir>}"
mkdir -p "${ENV_DIR}"
ENV_DIR="$(cd "${ENV_DIR}" && pwd)"

# ---------------------------------------------------------------- klt -----
installed_rev() {
  "${ENV_DIR}/klt/bin/python" - <<'PY' 2>/dev/null || true
import json, importlib.metadata as m
d = m.distribution("klayout-tools")
print(json.loads(d.read_text("direct_url.json") or "{}")
      .get("vcs_info", {}).get("commit_id", ""))
PY
}
if [[ "$(installed_rev)" != "${KLT_REV}" ]]; then
  echo "== native-env: installing klayout-tools @ ${KLT_REV} into ${ENV_DIR}/klt"
  rm -rf "${ENV_DIR}/klt"
  if command -v uv >/dev/null 2>&1; then
    uv venv -q "${ENV_DIR}/klt"
    VIRTUAL_ENV="${ENV_DIR}/klt" uv pip install -q \
      "klayout-tools @ git+${KLT_REPO}@${KLT_REV}"
  else
    python3 -m venv "${ENV_DIR}/klt"
    "${ENV_DIR}/klt/bin/python" -m pip install -q \
      "klayout-tools @ git+${KLT_REPO}@${KLT_REV}"
  fi
  [[ "$(installed_rev)" == "${KLT_REV}" ]] || {
    echo "error: klayout-tools install does not report revision ${KLT_REV}" >&2
    exit 1; }
fi

# ------------------------------------------------------------ klayout -----
if [[ -n "${NATIVE_KLAYOUT:-}" ]]; then
  exit 0   # caller-supplied binary; drc.sh checks its version
fi
if [[ ! -x "${ENV_DIR}/bin/klayout" ]]; then
  if [[ "$(uname -s)/$(uname -m)" != "Linux/x86_64" ]] \
     || ! grep -q '^VERSION_ID="24.04"' /etc/os-release 2>/dev/null; then
    echo "error: no bundled KLayout ${KLAYOUT_VER} for this host; set" \
         "NATIVE_KLAYOUT to a KLayout ${KLAYOUT_VER} binary" >&2
    exit 1
  fi
  echo "== native-env: extracting KLayout ${KLAYOUT_VER} into ${ENV_DIR}/klayout"
  [[ -f "${ENV_DIR}/${KLAYOUT_DEB}" ]] \
    || curl -sSfL -o "${ENV_DIR}/${KLAYOUT_DEB}" "${KLAYOUT_URL}"
  echo "${KLAYOUT_DEB_SHA256}  ${ENV_DIR}/${KLAYOUT_DEB}" | sha256sum -c --quiet - \
    || { echo "error: ${KLAYOUT_DEB} checksum mismatch" >&2; exit 1; }
  rm -rf "${ENV_DIR}/klayout"
  dpkg-deb -x "${ENV_DIR}/${KLAYOUT_DEB}" "${ENV_DIR}/klayout"
  mkdir -p "${ENV_DIR}/bin"
  cat > "${ENV_DIR}/bin/klayout" <<'SH'
#!/usr/bin/env bash
# throwaway wrapper around the extracted KLayout package (native_drc_env.sh)
set -euo pipefail
R="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../klayout/usr" && pwd)"
[[ -x "${R}/bin/klayout" ]] || { echo "error: no extracted KLayout under ${R}" >&2; exit 1; }
export LD_LIBRARY_PATH="${R}/lib/klayout${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec "${R}/bin/klayout" "$@"
SH
  chmod +x "${ENV_DIR}/bin/klayout"
fi
