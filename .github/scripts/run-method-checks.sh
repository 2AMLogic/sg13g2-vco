#!/usr/bin/env bash
# PDK-free measurement-method gate (issue #103).
#
# Runs the known-answer checks of the estimators in sim/lib.sh from a
# DISPOSABLE copy of the tracked tree, so the committed append-only sim/
# evidence is never touched, and fails unless every check both exits 0 and
# leaves a summary with passing rows (a script that measures nothing must not
# pass). Shared by .github/workflows/method-check.yml and local use:
#
#   .github/scripts/run-method-checks.sh [artifact-dir]
#
# Requires bash, awk, git and ngspice on PATH (CI pins ngspice 42; see
# sim/README.md). No PDK_ROOT, OSDI, xschem, KLayout or credentials are used;
# PDK/credential variables are scrubbed from the child environment to prove it.
#
# Env overrides:
#   METHOD_CHECK_SRC   tree to test (default: repo containing this script;
#                      only git-TRACKED files are copied)
#   METHOD_CHECK_MIN_* minimum passing-row counts (see MIN_* below)
#
# Generated logs and new evidence files are copied to <artifact-dir>
# (default: a fresh mktemp dir) for upload; nothing is written to the source tree.
set -uo pipefail

SRC="${METHOD_CHECK_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ART="${1:-$(mktemp -d "${TMPDIR:-/tmp}/method-check-artifacts.XXXXXX")}"
mkdir -p "${ART}/logs"
ART="$(cd "${ART}" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/method-check-work.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# Lower bounds on passing rows per summary (current: 56 / 42 / 324 = 27 points x 12 frequencies). Guards
# against a script that silently drops measurements; raise them when checks
# are added, never lower them to make a run pass.
MIN_OSC="${METHOD_CHECK_MIN_OSC:-56}"
MIN_PN="${METHOD_CHECK_MIN_PN:-42}"
MIN_IND="${METHOD_CHECK_MIN_IND:-324}"

command -v ngspice >/dev/null || { echo "error: ngspice not on PATH" >&2; exit 2; }
echo "simulator: $(ngspice --version 2>&1 | grep -m1 -i 'ngspice-[0-9]')"

git -C "${SRC}" ls-files -z | (cd "${SRC}" && xargs -0 cp --parents -t "${WORK}") \
  || { echo "error: could not copy tracked tree from ${SRC}" >&2; exit 2; }
cd "${WORK}" || exit 2
find sim -type f | sort > "${ART}/files.before"

FAILS=0
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }

# run_check <name> <script> ; exit status and wall time go to the log.
run_check() {
  local name="$1"; shift
  local t0=$SECONDS rc
  env -u PDK_ROOT -u PDK -u OPENVAF_OSDI -u OSDI_DIR -u GH_TOKEN -u GITHUB_TOKEN \
    "$@" >"${ART}/logs/${name}.log" 2>&1
  rc=$?
  echo "${name}: exit ${rc} in $((SECONDS - t0))s"
  [[ ${rc} -eq 0 ]] || fail "${name} exited ${rc} (see logs/${name}.log)"
  return 0
}

# check_summary <name> <dir> <min-pass>: the newest <dir>/records/*-method-check.csv
# must have >= min-pass rows, every row (last column) PASS, none else.
check_summary() {
  local name="$1" dir="$2" min="$3" csv
  csv="$(comm -13 "${ART}/files.before" <(find sim -type f | sort) \
         | grep "^sim/${dir}/records/.*-method-check\.csv$" | head -1)"
  [[ -n "${csv}" ]] || { fail "${name}: no method-check.csv was produced"; return; }
  awk -F, -v n="${name}" -v min="${min}" '
    NR == 1 { next }
    $NF == "PASS" { p++; next }
    { bad++; printf "FAIL: %s: non-passing row %d: %s\n", n, NR, $0 > "/dev/stderr" }
    END {
      printf "%s: %d passing, %d failing rows (minimum %d)\n", n, p, bad, min
      exit (bad > 0 || p < min)
    }' "${csv}" || fail "${name}: summary ${csv} failed or has fewer than ${min} passing rows"
}

run_check oscillator-core sim/oscillator-core/run_method_check.sh
check_summary oscillator-core oscillator-core "${MIN_OSC}"
run_check phase-noise sim/phase-noise/run_method_check.sh
check_summary phase-noise phase-noise "${MIN_PN}"
run_check inductor-model sim/inductor-model/run_model_check.sh
check_summary inductor-model inductor-model "${MIN_IND}"

run_check emit-tuning sim/oscillator-core/tests/test_emit_tuning.sh
if ! grep -q '^PASS ' "${ART}/logs/emit-tuning.log" || grep -q '^FAIL ' "${ART}/logs/emit-tuning.log"; then
  fail "emit-tuning: no PASS lines or a FAIL line in logs/emit-tuning.log"
fi

# DR-004 stage-2 supply sub-corners (issue #113): enumeration, rails in
# generated decks, nominal reproducibility, rail identity and the escalation
# report on synthetic fixtures. Renders decks and runs no PDK simulation.
MIN_S2="${METHOD_CHECK_MIN_S2:-79}"
run_check supply-stage2 sim/oscillator-core/tests/test_supply_stage2.sh
s2_pass="$(grep -c '^PASS ' "${ART}/logs/supply-stage2.log" || true)"
if [[ "${s2_pass}" -lt "${MIN_S2}" ]] || grep -q '^FAIL ' "${ART}/logs/supply-stage2.log"; then
  fail "supply-stage2: ${s2_pass} PASS lines (minimum ${MIN_S2}) or a FAIL line in logs/supply-stage2.log"
fi

# Ship the freshly generated evidence (disposable copy only) for diagnosis.
comm -13 "${ART}/files.before" <(find sim -type f | sort) > "${ART}/files.new"
if [[ -s "${ART}/files.new" ]]; then
  xargs -d '\n' cp --parents -t "${ART}" < "${ART}/files.new"
fi
echo "artifacts: ${ART}"

if [[ ${FAILS} -gt 0 ]]; then
  echo "method-check: ${FAILS} failure(s)" >&2
  exit 1
fi
echo "method-check: all known-answer checks passed"
