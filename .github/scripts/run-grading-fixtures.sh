#!/usr/bin/env bash
# Simulator-free grading-fixture dispatcher (issue #132). The single list of
# the repo's PDK-free, ngspice-free grading/known-answer fixtures: the emit-
# tuning, row-3, row-7, waveform-validity (stubbed simulator), DR-004
# stage-2 supply and phase-noise validity (#137) fixtures. Shared by `check-all.sh grading-fixtures` (in the
# `test` / `ci` aggregates) and run-method-checks.sh, so the two cannot drift.
#
#   .github/scripts/run-grading-fixtures.sh [log-dir]
#
# By default it runs from a DISPOSABLE copy of the git-tracked tree, so the
# committed append-only sim/ evidence is never touched. It needs only bash,
# awk, grep and git: no ngspice, xschem, OSDI or PDK_ROOT (those variables
# are scrubbed from each fixture's environment to prove it).
# sim/tests/test-source-capture.sh is NOT listed here: it already runs via
# test-record-currency.sh (the currency-selftest target).
#
# Env:
#   GRADING_SRC          tree to test (default: repo containing this script;
#                        only git-TRACKED files are copied)
#   GRADING_TREE         run in place in this ready-made disposable tree
#                        instead of copying (used by run-method-checks.sh)
#   METHOD_CHECK_MIN_S2  minimum PASS lines for the supply-stage2 fixture
#                        (raise when checks are added, never lower)
#
# Exit: 0 all fixtures passed, 1 a fixture failed (its name is printed),
#       2 setup error.
set -uo pipefail

SRC="${GRADING_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOGS="${1:-}"
CLEAN=""
if [[ -z "${LOGS}" ]]; then
  LOGS="$(mktemp -d "${TMPDIR:-/tmp}/grading-logs.XXXXXX")" || exit 2
  CLEAN="${LOGS}"
fi
mkdir -p "${LOGS}" || exit 2
LOGS="$(cd "${LOGS}" && pwd)"

TREE="${GRADING_TREE:-}"
if [[ -z "${TREE}" ]]; then
  TREE="$(mktemp -d "${TMPDIR:-/tmp}/grading-work.XXXXXX")" || exit 2
  CLEAN="${CLEAN} ${TREE}"
  # shellcheck disable=SC2064
  trap "rm -rf ${CLEAN}" EXIT
  git -C "${SRC}" ls-files -z | (cd "${SRC}" && xargs -0 cp --parents -t "${TREE}") \
    || { echo "error: could not copy tracked tree from ${SRC}" >&2; exit 2; }
elif [[ -n "${CLEAN}" ]]; then
  # shellcheck disable=SC2064
  trap "rm -rf ${CLEAN}" EXIT
fi
cd "${TREE}" || exit 2

FAILS=0
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }

# run_fixture <name> <script>: exit status and wall time go to the log.
run_fixture() {
  local name="$1"; shift
  local t0=$SECONDS rc
  env -u PDK_ROOT -u PDK -u OPENVAF_OSDI -u OSDI_DIR -u GH_TOKEN -u GITHUB_TOKEN \
    "$@" >"${LOGS}/${name}.log" 2>&1
  rc=$?
  echo "${name}: exit ${rc} in $((SECONDS - t0))s"
  [[ ${rc} -eq 0 ]] || fail "${name} exited ${rc} (see ${LOGS}/${name}.log)"
  return 0
}

# need_pass_lines <name>: >=1 '^PASS ' line and no '^FAIL ' line.
need_pass_lines() {
  local name="$1" log="${LOGS}/$1.log"
  if ! grep -q '^PASS ' "${log}" || grep -q '^FAIL ' "${log}"; then
    fail "${name}: no PASS lines or a FAIL line in ${log}"
  fi
}

run_fixture emit-tuning sim/oscillator-core/tests/test_emit_tuning.sh
need_pass_lines emit-tuning

run_fixture row3-grade sim/oscillator-core/tests/test_row3.sh
need_pass_lines row3-grade

run_fixture row3-global sim/oscillator-core/tests/test_row3_global.sh
need_pass_lines row3-global

run_fixture row7-grade sim/oscillator-core/tests/test_row7.sh
need_pass_lines row7-grade

# Waveform-validity fault injection (#83), extended with the row-7 columns
# (#112): the real osc_simulate_point over stubbed traces, no simulator.
run_fixture waveform-validity sim/oscillator-core/run_validity_check.sh
if ! grep -q '^all cases passed$' "${LOGS}/waveform-validity.log" \
   || grep -q '^FAIL ' "${LOGS}/waveform-validity.log"; then
  fail "waveform-validity: no 'all cases passed' line or a FAIL line in ${LOGS}/waveform-validity.log"
fi

# DR-004 stage-2 supply sub-corners (issue #113): enumeration, rails in
# generated decks, nominal reproducibility, rail identity and the escalation
# report on synthetic fixtures. Renders decks and runs no PDK simulation.
MIN_S2="${METHOD_CHECK_MIN_S2:-122}"
run_fixture supply-stage2 sim/oscillator-core/tests/test_supply_stage2.sh
s2_pass="$(grep -c '^PASS ' "${LOGS}/supply-stage2.log" || true)"
if [[ "${s2_pass}" -lt "${MIN_S2}" ]] || grep -q '^FAIL ' "${LOGS}/supply-stage2.log"; then
  fail "supply-stage2: ${s2_pass} PASS lines (minimum ${MIN_S2}) or a FAIL line in ${LOGS}/supply-stage2.log"
fi

# Phase-noise measurement validity (issue #137): pn_verdict, the gamma/noise
# reducers and the ensemble reduction on synthetic NaN/inf/malformed/missing
# inputs, plus the known-answer reduction of the committed pilot record.
run_fixture pn-validity sim/phase-noise/tests/test_validity.sh
need_pass_lines pn-validity
if ! grep -q '^all cases passed$' "${LOGS}/pn-validity.log"; then
  fail "pn-validity: no 'all cases passed' line in ${LOGS}/pn-validity.log"
fi

if [[ ${FAILS} -gt 0 ]]; then
  echo "grading-fixtures: ${FAILS} failure(s)" >&2
  exit 1
fi
echo "grading-fixtures: all fixtures passed"
