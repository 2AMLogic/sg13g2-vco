#!/usr/bin/env bash
# Shared gate runner (issue #117). The single list of the repo's PDK-free
# gates: CI workflow steps call its named targets and `npm test` /
# `npm run check:ci` / `npm run check:all` call its aggregates, so CI and
# local runs cannot drift. Gate logic stays in the existing checkers; this
# script only orders them, checks their tools and counts results.
#
# PYTHON overrides the interpreter of the py-* targets (default python3).
#
# Usage: check-all.sh [--strict] [--base REF] [--head REF] [--artifacts DIR]
#                     <target> [target-args...]
#
# Single targets (one CI step each; extra args are forwarded):
#   lint-selftest         .github/scripts/test-lint-shell.sh        shellcheck
#   lint                  .github/scripts/lint-shell.sh [file...]   shellcheck
#   signoff-selftest      .github/scripts/test-check-signoff.sh     pinned klt
#   signoff               .github/scripts/check-signoff.sh          pinned klt
#   append-only-selftest  .github/scripts/test-check-sim-append-only.sh
#   record-id-selftest    sim/tests/test-reserve-record-id.sh
#   spec-dr-selftest      .github/scripts/test-check-spec-change-has-dr.sh
#   runner-selftest       .github/scripts/test-check-all.sh
#   grader-spec-selftest  .github/scripts/test-check-grader-spec-agreement.sh
#                         python3 (mutation fixtures on a temp copy of the
#                         spec, DR-004 and the graders; no ngspice/PDK)
#   grader-spec           .github/scripts/check-grader-spec-agreement.sh
#                         python3 (grader OSC_ROW*/PN_ROW4_*/S2_* constants ==
#                         spec/target-spec.md + DR-004 stage-2 condition;
#                         agreement only, never authorises a change)
#   currency-selftest     .github/scripts/test-record-currency.sh   python3
#   currency              .github/scripts/check-record-currency.sh  python3
#                         (sim/record-currency.json == fresh classification)
#   grading-fixtures      .github/scripts/run-grading-fixtures.sh   git awk
#                         (emit-tuning, row3, row7, waveform-validity and
#                         stage-2 supply fixtures from a disposable copy of the
#                         tracked tree; no ngspice/PDK; source-capture stays
#                         in currency-selftest)
#   model-inputs-selftest .github/scripts/test-model-inputs.sh      python3
#   model-inputs          .github/scripts/check-model-inputs.sh     python3
#                         (issue #139: committed model-input manifests ==
#                         their retained snapshots; separate from currency,
#                         never reads live model files)
#   py-selftest           .github/scripts/test-check-python.sh      python3
#   py-compile            check-python.sh compile (py_compile, all tracked *.py)
#   py-tests              check-python.sh tests (stdlib unittest, tests/stdlib)
#   py-klayout            check-python.sh klayout (tests/klayout; needs the
#                         klayout pip wheel at .github/klayout-pip-version)
#   append-only [--base REF]               PR diff gate (git, base ref)
#   spec-dr [--base REF] [--head REF]      PR diff gate (git, base/head refs)
#   method [artifact-dir]  ngspice-42 check, then run-method-checks.sh
#
# Aggregates:
#   test  = lint-selftest signoff-selftest append-only-selftest
#           record-id-selftest spec-dr-selftest runner-selftest
#           grader-spec-selftest grader-spec currency-selftest currency
#           model-inputs-selftest model-inputs
#           grading-fixtures py-selftest py-compile py-tests
#   ci    = lint + test
#   all   = ci + signoff + py-klayout (only with the pinned klayout wheel)
#           + pr-diff (only with --base) + method
#   pr-diff --base REF [--head REF] = append-only + spec-dr
# Runner options may also follow an aggregate name (the npm form:
# `npm run check:all -- --strict --base origin/main`).
# Before a single target, --base/--head are forwarded to the diff gates
# (spec-dr: both; append-only: --base only) and verified like trailing ones;
# --artifacts is accepted only by method. Any other leading
# --base/--head/--artifacts on a single target is a usage error (exit 2),
# never silently ignored.
#
# Within `all`, method is optional: without ngspice 42 on PATH it prints
# "SKIPPED: ngspice 42 not found" and is counted as skipped; pr-diff without
# --base is likewise counted as skipped, and py-klayout without the klayout
# wheel importable is counted as skipped. As a single target py-klayout
# requires the pinned wheel (missing or other version -> failure). A skip never reads as a pass: the
# summary counts it, and --strict turns any skip into a nonzero exit. As a
# single target, `method` requires ngspice 42 (missing -> failure).
#
# Missing mandatory tools and child failures are counted as failures; every
# gate of an aggregate still runs so one run reports them all. Explicit
# --base/--head refs are verified to resolve to commits; an unavailable ref
# fails rather than being skipped. Nothing is installed and nothing is
# fetched by this script (append-only's own CI fallback may fetch the PR base
# when GITHUB_BASE_REF is set and no --base is given).
#
# Exit: 0 all requested gates passed (skips allowed unless --strict),
#       1 a gate failed, a tool was missing, or --strict saw a skip,
#       2 usage error.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$ROOT/.github/scripts"

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' \
    "${BASH_SOURCE[0]}" >&2
  exit 2
}

STRICT=0
BASE=""
HEAD_REF=""
ARTIFACTS=""
# parse_opts <args...>: consume runner options; sets NPARSED.
parse_opts() {
  NPARSED=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --strict) STRICT=1; shift; NPARSED=$((NPARSED + 1)) ;;
      --base) [ $# -ge 2 ] || usage; BASE="$2"; shift 2; NPARSED=$((NPARSED + 2)) ;;
      --head) [ $# -ge 2 ] || usage; HEAD_REF="$2"; shift 2; NPARSED=$((NPARSED + 2)) ;;
      --artifacts) [ $# -ge 2 ] || usage; ARTIFACTS="$2"; shift 2; NPARSED=$((NPARSED + 2)) ;;
      -h|--help) usage ;;
      -*) echo "check-all: unknown option $1" >&2; usage ;;
      *) return 0 ;;
    esac
  done
}
parse_opts "$@"; shift "$NPARSED"
[ $# -ge 1 ] || usage
TARGET="$1"; shift
# Aggregates also take the runner options after the target, so
# `npm run check:all -- --strict` works; they take no other arguments.
case "$TARGET" in
  test|ci|all|pr-diff)
    parse_opts "$@"; shift "$NPARSED"
    if [ $# -gt 0 ]; then
      echo "check-all: unexpected argument '$1' for aggregate '$TARGET'" >&2
      usage
    fi ;;
esac

cd "$ROOT" || { echo "check-all: cannot cd to $ROOT" >&2; exit 1; }

PASSED=(); FAILED=(); SKIPPED=()

pass() { PASSED+=("$1"); echo "PASS: $1"; }
failg() { FAILED+=("$1"); echo "FAIL: $1${2:+ ($2)}" >&2; }
skip() { SKIPPED+=("$1"); echo "SKIPPED: $1${2:+: $2}"; }

# need_tools <gate> <tool>...: record a failure for each missing tool.
need_tools() {
  local gate="$1" t missing=0; shift
  for t in "$@"; do
    if ! command -v "$t" >/dev/null 2>&1; then
      echo "MISSING TOOL: $t (required by $gate)" >&2
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || { failg "$gate" "missing required tool"; return 1; }
}

# need_ref <gate> <ref>: an explicitly requested ref must resolve to a commit.
need_ref() {
  if ! git -C "$ROOT" rev-parse --verify --quiet "$2^{commit}" >/dev/null 2>&1; then
    echo "UNAVAILABLE REF: '$2' does not resolve to a commit (fetch it, e.g. git fetch origin main, or a full-history checkout)" >&2
    failg "$1" "unavailable ref $2"
    return 1
  fi
}

# ngspice_42: 0 if ngspice 42 is on PATH; prints the reason otherwise.
ngspice_42() {
  if ! command -v ngspice >/dev/null 2>&1; then
    echo "ngspice 42 not found (no ngspice on PATH)"; return 1
  fi
  local v
  v="$(ngspice --version 2>&1 | grep -m1 -o 'ngspice-[0-9][0-9.]*' || true)"
  case "$v" in
    ngspice-42|ngspice-42.*) return 0 ;;
    *) echo "ngspice 42 not found (found ${v:-unrecognised version})"; return 1 ;;
  esac
}

# klayout_wheel: 0 if the klayout pip wheel is importable; prints the reason
# otherwise. (The py-klayout gate itself also verifies the pinned version.)
klayout_wheel() {
  local py="${PYTHON:-python3}"
  if ! command -v "$py" >/dev/null 2>&1 ||
     ! "$py" -I -c 'import klayout.db' >/dev/null 2>&1; then
    echo "klayout pip wheel not importable (pip install klayout==$(cat "$ROOT/.github/klayout-pip-version" 2>/dev/null))"
    return 1
  fi
}

# run_gate <gate> <cmd...>: run a child, record pass/fail by exit status.
run_gate() {
  local gate="$1" rc; shift
  echo "==> $gate: $*"
  "$@"
  rc=$?
  if [ "$rc" -eq 0 ]; then pass "$gate"; else failg "$gate" "exit $rc"; fi
}

# Forwarded --base/--head (single diff targets) are verified like globals.
check_forwarded_refs() {
  local gate="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --base|--head) [ $# -ge 2 ] || { failg "$gate" "$1 needs a value"; return 1; }
                     need_ref "$gate" "$2" || return 1; shift 2 ;;
      *) shift ;;
    esac
  done
}

gate() {
  local g="$1"; shift
  case "$g" in
    lint-selftest)
      need_tools "$g" shellcheck git && run_gate "$g" "$SCRIPTS/test-lint-shell.sh" "$@" ;;
    lint)
      need_tools "$g" shellcheck git && run_gate "$g" "$SCRIPTS/lint-shell.sh" "$@" ;;
    signoff-selftest)
      need_tools "$g" klt python3 && run_gate "$g" "$SCRIPTS/test-check-signoff.sh" "$@" ;;
    signoff)
      need_tools "$g" klt python3 && run_gate "$g" "$SCRIPTS/check-signoff.sh" "$@" ;;
    append-only-selftest)
      need_tools "$g" git && run_gate "$g" "$SCRIPTS/test-check-sim-append-only.sh" "$@" ;;
    record-id-selftest)
      run_gate "$g" "$ROOT/sim/tests/test-reserve-record-id.sh" "$@" ;;
    spec-dr-selftest)
      need_tools "$g" git && run_gate "$g" "$SCRIPTS/test-check-spec-change-has-dr.sh" "$@" ;;
    runner-selftest)
      need_tools "$g" git && run_gate "$g" "$SCRIPTS/test-check-all.sh" "$@" ;;
    grader-spec-selftest)
      need_tools "$g" python3 && run_gate "$g" "$SCRIPTS/test-check-grader-spec-agreement.sh" "$@" ;;
    grader-spec)
      need_tools "$g" python3 && run_gate "$g" "$SCRIPTS/check-grader-spec-agreement.sh" "$@" ;;
    currency-selftest)
      need_tools "$g" git python3 && run_gate "$g" "$SCRIPTS/test-record-currency.sh" "$@" ;;
    currency)
      need_tools "$g" git python3 && run_gate "$g" "$SCRIPTS/check-record-currency.sh" "$@" ;;
    model-inputs-selftest)
      need_tools "$g" python3 && run_gate "$g" "$SCRIPTS/test-model-inputs.sh" "$@" ;;
    model-inputs)
      need_tools "$g" python3 && run_gate "$g" "$SCRIPTS/check-model-inputs.sh" "$@" ;;
    grading-fixtures)
      need_tools "$g" git awk grep && run_gate "$g" "$SCRIPTS/run-grading-fixtures.sh" "$@" ;;
    py-selftest)
      need_tools "$g" git python3 && run_gate "$g" "$SCRIPTS/test-check-python.sh" "$@" ;;
    py-compile)
      need_tools "$g" git python3 && run_gate "$g" "$SCRIPTS/check-python.sh" compile "$@" ;;
    py-tests)
      need_tools "$g" git python3 && run_gate "$g" "$SCRIPTS/check-python.sh" tests "$@" ;;
    py-klayout)
      need_tools "$g" git python3 && run_gate "$g" "$SCRIPTS/check-python.sh" klayout "$@" ;;
    append-only)
      need_tools "$g" git && check_forwarded_refs "$g" "$@" &&
        run_gate "$g" "$SCRIPTS/check-sim-append-only.sh" "$@" ;;
    spec-dr)
      need_tools "$g" git && check_forwarded_refs "$g" "$@" &&
        run_gate "$g" "$SCRIPTS/check-spec-change-has-dr.sh" "$@" ;;
    method)
      local why
      if ! why="$(ngspice_42)"; then
        echo "MISSING TOOL: $why (required by $g)" >&2
        failg "$g" "missing required tool"
      else
        need_tools "$g" git awk && run_gate "$g" "$SCRIPTS/run-method-checks.sh" "$@"
      fi ;;
    *) echo "check-all: unknown target '$g'" >&2; usage ;;
  esac
  return 0
}

# reject_opts <target> <VAR>...: a leading runner option the single target
# does not use is a usage error rather than being silently dropped.
reject_opts() {
  local t="$1" v opt; shift
  for v in "$@"; do
    [ -n "${!v}" ] || continue
    case "$v" in BASE) opt=--base ;; HEAD_REF) opt=--head ;; *) opt=--artifacts ;; esac
    echo "check-all: $opt is not accepted by target '$t'" >&2
    usage
  done
}

agg_test() {
  gate lint-selftest
  gate signoff-selftest
  gate append-only-selftest
  gate record-id-selftest
  gate spec-dr-selftest
  gate runner-selftest
  gate grader-spec-selftest
  gate grader-spec
  gate currency-selftest
  gate currency
  gate model-inputs-selftest
  gate model-inputs
  gate grading-fixtures
  gate py-selftest
  gate py-compile
  gate py-tests
}

agg_pr_diff() {
  local hd=() head_sha cur_sha
  need_ref pr-diff "$BASE" || return 0
  if [ -n "$HEAD_REF" ]; then
    hd=(--head "$HEAD_REF")
    need_ref pr-diff "$HEAD_REF" || return 0
    # check-sim-append-only.sh always diffs the checked-out HEAD, so a
    # different --head would silently grade the wrong commit: refuse it.
    head_sha="$(git -C "$ROOT" rev-parse "$HEAD_REF^{commit}")"
    cur_sha="$(git -C "$ROOT" rev-parse HEAD)"
    if [ "$head_sha" != "$cur_sha" ]; then
      failg append-only "--head $HEAD_REF is not the checked-out HEAD; check it out first"
    else
      gate append-only --base "$BASE"
    fi
  else
    gate append-only --base "$BASE"
  fi
  gate spec-dr --base "$BASE" ${hd[@]+"${hd[@]}"}
}

case "$TARGET" in
  test) agg_test ;;
  ci) gate lint; agg_test ;;
  all)
    gate lint
    agg_test
    gate signoff
    if why="$(klayout_wheel)"; then
      gate py-klayout
    else
      skip py-klayout "$why"
    fi
    if [ -n "$BASE" ]; then
      agg_pr_diff
    else
      skip pr-diff "no --base REF given (e.g. --base origin/main)"
    fi
    if why="$(ngspice_42)"; then
      if [ -n "$ARTIFACTS" ]; then gate method "$ARTIFACTS"; else gate method; fi
    else
      skip method "$why"
    fi ;;
  pr-diff)
    if [ -z "$BASE" ]; then
      echo "check-all: pr-diff needs --base REF (e.g. --base origin/main)" >&2
      exit 2
    fi
    agg_pr_diff ;;
  method)
    reject_opts "$TARGET" BASE HEAD_REF
    if [ $# -eq 0 ] && [ -n "$ARTIFACTS" ]; then set -- "$ARTIFACTS"; fi
    gate method "$@" ;;
  spec-dr)
    reject_opts "$TARGET" ARTIFACTS
    gate spec-dr ${BASE:+--base "$BASE"} ${HEAD_REF:+--head "$HEAD_REF"} "$@" ;;
  append-only)
    # check-sim-append-only.sh has no --head (it diffs the checked-out HEAD).
    reject_opts "$TARGET" HEAD_REF ARTIFACTS
    gate append-only ${BASE:+--base "$BASE"} "$@" ;;
  *)
    reject_opts "$TARGET" BASE HEAD_REF ARTIFACTS
    gate "$TARGET" "$@" ;;
esac

np=${#PASSED[@]}; nf=${#FAILED[@]}; ns=${#SKIPPED[@]}
echo "check-all $TARGET: $np passed, $nf failed, $ns skipped"
[ "$nf" -eq 0 ] || echo "  failed: ${FAILED[*]}" >&2
[ "$ns" -eq 0 ] || echo "  skipped (NOT passed): ${SKIPPED[*]}"
if [ "$nf" -gt 0 ]; then exit 1; fi
if [ "$ns" -gt 0 ] && [ "$STRICT" -eq 1 ]; then
  echo "check-all: --strict: $ns skipped gate(s) count as failure" >&2
  exit 1
fi
exit 0
