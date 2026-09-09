# Source me:  source "${SIM_DIR}/lib.sh"
#
# Shared scaffolding for the sim/*/run_*.sh experiment scripts
# (sim/tank-characterization/run_pvt_sweep.sh, sim/inductor-model/run_model_check.sh).
# These two scripts are legitimate, distinct experiments -- this file exists
# because the bash *scaffolding* around them (hashing, record-ID minting, a
# scratch ngspice workdir, pulling a scalar out of a .meas log) was
# byte-identical between them, not because the experiments themselves should
# be merged. See issue #16 for the duplication this replaces.
#
# Deliberately does NOT source sim/env.sh and must not gain any
# PDK-resolution dependency: sim/inductor-model/run_model_check.sh's "only
# needs ngspice (and bash, and awk) on PATH -- no PDK install required"
# property depends on that (see its own header comment). Callers that DO need
# the PDK (sim/tank-characterization/run_pvt_sweep.sh) source sim/env.sh
# themselves, separately from this file.
#
# This file is sourced, not executed, so it has no shebang; the directive
# below tells shellcheck which dialect to assume.
# shellcheck shell=bash
#
# Bash-3.2 clean throughout, on purpose: macOS still ships bash 3.2 as
# /bin/bash, and spec/review-bar.md item 1 forbids a "one-command cold start"
# that silently needs a newer bash. No `declare -A`, no bash-4+ builtins or
# parameter expansions.

# sha256_of <file>
# Print the sha256 digest of a file, or "unavailable" if neither shasum nor
# sha256sum is on PATH.
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else echo "unavailable"; fi
}

# meas_value <log> <name>
# Pull a scalar out of an ngspice batch log. `meas` prints
#   "<name>                =  <value>"
# on success and "meas ... failed!" on a miss; a miss must come back empty so
# the caller can record it as "none" instead of as a number.
meas_value() {
  local log="$1" name="$2"
  awk -v n="${name}" '$1 == n && $2 == "=" { print $3; found=1 } END { if (!found) print "" }' "${log}" | head -1
}

# detect_ngspice_version
# Print the installed ngspice's version string (e.g. "ngspice-42"), parsed
# from `ngspice --version`, or "unknown" if it could not be parsed. Requires
# ngspice on PATH -- callers already check that before sourcing this file.
detect_ngspice_version() {
  local v
  v="$(ngspice --version 2>&1 | sed -n 's/^\*\* \(ngspice-[0-9.]*\).*/\1/p' | head -1)"
  echo "${v:-unknown}"
}

# mint_record_id <repo_root>
# Print a fresh RECORD_ID of the form <UTC timestamp>-<short git SHA>
# (<git SHA> is "nogit" outside a git checkout). Every sim/*/run_*.sh script
# mints exactly one of these per run and uses it to key its append-only
# evidence directories -- see each script's own header comment.
mint_record_id() {
  local repo_root="$1"
  local git_sha
  git_sha="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || echo nogit)"
  echo "$(date -u +%Y%m%d-%H%M%S)-${git_sha}"
}

# make_scratch_workdir <mktemp-prefix>
# Create a scratch directory under ${TMPDIR:-/tmp} for ngspice to run in, copy
# this experiment's .spiceinit into it (so a cold-start run does not depend on
# whether the PDK's install.py ever symlinked one into $HOME), and arrange for
# it to be removed on exit. Sets the global WORKDIR variable and installs an
# EXIT trap that removes it.
#
# Requires the caller to have already set EXPERIMENT_DIR (every sim/*/run_*.sh
# script does this before sourcing lib.sh) and to have a "${EXPERIMENT_DIR}/.spiceinit"
# present.
make_scratch_workdir() {
  local prefix="$1"
  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")"
  cleanup() { rm -rf "${WORKDIR}"; }
  trap cleanup EXIT
  cp "${EXPERIMENT_DIR}/.spiceinit" "${WORKDIR}/.spiceinit"
}
