#!/usr/bin/env bash
# Self-test for check-all.sh (issue #117): a runner that turns failures or
# skips into a pass is worse than no runner. Runs the REAL check-all.sh from
# a scratch git repo whose children are logging stubs and whose PATH holds
# stub tools (shellcheck, klt, python3, ngspice), so it needs no shellcheck,
# klt, ngspice or PDK and never touches the real tree.
#
# Cases: aggregate order and success, child-failure propagation, absent
# mandatory tool, missing / wrong-version ngspice (counted skip in `all`,
# failure for `method`), --strict skip failure, argument forwarding, method
# artifact-dir forwarding and failure, unavailable explicit refs, leading
# runner options on single targets (forwarded or rejected), usage errors.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER_SRC="$HERE/check-all.sh"
[ -x "$RUNNER_SRC" ] || { echo "FAIL: $RUNNER_SRC not executable" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }

# --- fixture repo: real runner, stub children ------------------------------
F="$T/repo"
mkdir -p "$F/.github/scripts" "$F/sim/tests"
cp "$RUNNER_SRC" "$F/.github/scripts/check-all.sh"
RUNNER="$F/.github/scripts/check-all.sh"
for c in .github/scripts/test-lint-shell.sh .github/scripts/lint-shell.sh \
         .github/scripts/test-check-signoff.sh .github/scripts/check-signoff.sh \
         .github/scripts/test-check-sim-append-only.sh \
         .github/scripts/check-sim-append-only.sh \
         .github/scripts/test-check-spec-change-has-dr.sh \
         .github/scripts/check-spec-change-has-dr.sh \
         .github/scripts/test-check-all.sh .github/scripts/run-method-checks.sh \
         .github/scripts/test-check-grader-spec-agreement.sh \
         .github/scripts/check-grader-spec-agreement.sh \
         .github/scripts/run-grading-fixtures.sh \
         .github/scripts/test-check-python.sh .github/scripts/check-python.sh \
         .github/scripts/test-record-currency.sh \
         .github/scripts/check-record-currency.sh \
         .github/scripts/test-model-inputs.sh \
         .github/scripts/check-model-inputs.sh \
         .github/scripts/test-record-deck-integrity.sh \
         .github/scripts/check-record-deck-integrity.sh \
         .github/scripts/test-check-klt-friction.sh \
         .github/scripts/check-klt-friction.sh \
         sim/tests/test-reserve-record-id.sh sim/tests/test-tank-ab-reserve.sh \
         sim/tests/test-local-grid-guard.sh \
         sim/tests/test-build-osdi-staging.sh; do
  cat > "$F/$c" <<'EOF'
#!/usr/bin/env bash
n="$(basename "$0")"
echo "$n${*:+ $*}" >> "$CALLS"
[ ! -e "$FAILDIR/$n" ]
EOF
  chmod +x "$F/$c"
done
git -C "$F" init -q -b main
git -C "$F" config user.email t@t
git -C "$F" config user.name t
git -C "$F" add -A
git -C "$F" commit -q -m base
echo two > "$F/two.txt"; git -C "$F" add two.txt; git -C "$F" commit -q -m two
FIRST="$(git -C "$F" rev-parse HEAD~1)"

# --- stub PATH ---------------------------------------------------------------
BIN="$T/bin"; mkdir -p "$BIN"
for t in bash git awk grep sed dirname basename cat rm mkdir mktemp env tr xargs cp touch; do
  p="$(command -v "$t")" || { echo "FAIL: host lacks $t" >&2; exit 1; }
  ln -s "$p" "$BIN/$t"
done
for t in shellcheck klt python3; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/$t"; chmod +x "$BIN/$t"
done
cat > "$BIN/ngspice" <<'EOF'
#!/usr/bin/env bash
echo "******"
echo "** ${NGSPICE_VER:-ngspice-42} : Circuit level simulation program"
EOF
chmod +x "$BIN/ngspice"

export CALLS="$T/calls" FAILDIR="$T/fail"
mkdir -p "$FAILDIR"
OUT="$T/out"

# run_case <path-dir> <args...>: sets RC; output in $OUT, child calls in $CALLS.
run_case() {
  local path="$1"; shift
  : > "$CALLS"
  PATH="$path" "$RUNNER" "$@" > "$OUT" 2>&1
  RC=$?
}
reset() { rm -f "$FAILDIR"/*; }
calls() { tr '\n' '|' < "$CALLS"; }

# PATH whose python3 cannot import klayout (the stub python3 accepts anything)
NOKL="$T/bin-nokl"; mkdir -p "$NOKL"
for f in "$BIN"/*; do [ "$(basename "$f")" = python3 ] || ln -s "$f" "$NOKL/"; done
printf '#!/usr/bin/env bash\nexit 1\n' > "$NOKL/python3"; chmod +x "$NOKL/python3"
# PATH without ngspice / without klt
NONG="$T/bin-nong"; mkdir -p "$NONG"
for f in "$BIN"/*; do [ "$(basename "$f")" = ngspice ] || ln -s "$f" "$NONG/"; done
NOKLT="$T/bin-noklt"; mkdir -p "$NOKLT"
for f in "$BIN"/*; do [ "$(basename "$f")" = klt ] || ln -s "$f" "$NOKLT/"; done

SELFTESTS="test-lint-shell.sh|test-check-signoff.sh|test-check-sim-append-only.sh|test-reserve-record-id.sh|test-tank-ab-reserve.sh|test-local-grid-guard.sh|test-build-osdi-staging.sh|test-check-spec-change-has-dr.sh|test-check-all.sh|test-check-grader-spec-agreement.sh|check-grader-spec-agreement.sh|test-record-currency.sh|check-record-currency.sh|test-model-inputs.sh|check-model-inputs.sh|test-record-deck-integrity.sh|check-record-deck-integrity.sh|test-check-klt-friction.sh|check-klt-friction.sh|run-grading-fixtures.sh|test-check-python.sh|check-python.sh compile|check-python.sh tests|"

# 1. test aggregate: twenty-three gates in workflow order, exit 0
reset; run_case "$NONG" test
if [ "$RC" -eq 0 ] && [ "$(calls)" = "$SELFTESTS" ] && grep -q '23 passed, 0 failed, 0 skipped' "$OUT"; then
  ok "test runs the self-tests in order and passes"; else bad "test: rc=$RC calls=$(calls)"; fi

# 2. ci = lint + test
reset; run_case "$NONG" ci
if [ "$RC" -eq 0 ] && [ "$(calls)" = "lint-shell.sh|$SELFTESTS" ]; then
  ok "ci runs lint then the self-tests"; else bad "ci: rc=$RC calls=$(calls)"; fi

# 3. child failure propagates, remaining gates still run
reset; touch "$FAILDIR/test-check-signoff.sh"; run_case "$NONG" test
if [ "$RC" -eq 1 ] && [ "$(calls)" = "$SELFTESTS" ] && grep -q '22 passed, 1 failed' "$OUT"; then
  ok "child failure -> exit 1, others still run"; else bad "child failure: rc=$RC calls=$(calls)"; fi

# 4. absent mandatory tool fails (child not run)
reset; run_case "$NOKLT" test
if [ "$RC" -eq 1 ] && grep -q 'MISSING TOOL: klt' "$OUT" && ! grep -q 'test-check-signoff' "$CALLS"; then
  ok "missing klt -> exit 1, signoff self-test not run"; else bad "missing tool: rc=$RC"; fi
reset; run_case "$NOKLT" signoff
if [ "$RC" -eq 1 ] && [ ! -s "$CALLS" ]; then
  ok "signoff target without klt -> exit 1"; else bad "signoff no klt: rc=$RC"; fi

# 4b. named currency targets: dispatch, argument forwarding, failure, tools
reset; run_case "$BIN" currency-selftest
if [ "$RC" -eq 0 ] && [ "$(calls)" = "test-record-currency.sh|" ]; then
  ok "currency-selftest target dispatches the classifier self-test"; else bad "currency-selftest: rc=$RC $(calls)"; fi
reset; run_case "$BIN" currency
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-record-currency.sh|" ]; then
  ok "currency target dispatches the index gate"; else bad "currency: rc=$RC $(calls)"; fi
reset; touch "$FAILDIR/check-record-currency.sh"; run_case "$BIN" currency
if [ "$RC" -eq 1 ]; then ok "currency failure -> exit 1"; else bad "currency failure: rc=$RC"; fi
# 4b3. friction-ledger targets (issue #146)
reset; run_case "$BIN" friction-selftest
if [ "$RC" -eq 0 ] && [ "$(calls)" = "test-check-klt-friction.sh|" ]; then
  ok "friction-selftest target dispatches the fixture self-test"; else bad "friction-selftest: rc=$RC $(calls)"; fi
reset; run_case "$BIN" friction
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-klt-friction.sh|" ]; then
  ok "friction target dispatches the ledger gate"; else bad "friction: rc=$RC $(calls)"; fi
reset; touch "$FAILDIR/check-klt-friction.sh"; run_case "$BIN" friction
if [ "$RC" -eq 1 ]; then ok "friction failure -> exit 1"; else bad "friction failure: rc=$RC"; fi
# 4c. named grader/spec agreement targets (issue #138)
reset; run_case "$BIN" grader-spec-selftest
if [ "$RC" -eq 0 ] && [ "$(calls)" = "test-check-grader-spec-agreement.sh|" ]; then
  ok "grader-spec-selftest target dispatches the mutation fixtures"; else bad "grader-spec-selftest: rc=$RC $(calls)"; fi
reset; run_case "$BIN" grader-spec
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-grader-spec-agreement.sh|" ]; then
  ok "grader-spec target dispatches the agreement checker"; else bad "grader-spec: rc=$RC $(calls)"; fi
reset; touch "$FAILDIR/check-grader-spec-agreement.sh"; run_case "$BIN" grader-spec
if [ "$RC" -eq 1 ]; then ok "grader-spec failure -> exit 1"; else bad "grader-spec failure: rc=$RC"; fi
reset; touch "$FAILDIR/test-record-currency.sh"; run_case "$NONG" test
if [ "$RC" -eq 1 ] && grep -q '22 passed, 1 failed' "$OUT" && grep -q '^check-record-currency.sh$' "$CALLS"; then
  ok "currency self-test failure fails test, later gates still run"; else bad "currency selftest fail: rc=$RC"; fi

# 4b2. model-inputs targets (issue #139)
reset; run_case "$BIN" model-inputs-selftest
if [ "$RC" -eq 0 ] && [ "$(calls)" = "test-model-inputs.sh|" ]; then
  ok "model-inputs-selftest target dispatches the fixture self-test"; else bad "model-inputs-selftest: rc=$RC $(calls)"; fi
reset; run_case "$BIN" model-inputs
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-model-inputs.sh|" ]; then
  ok "model-inputs target dispatches the integrity gate"; else bad "model-inputs: rc=$RC $(calls)"; fi
reset; touch "$FAILDIR/check-model-inputs.sh"; run_case "$BIN" model-inputs
if [ "$RC" -eq 1 ]; then ok "model-inputs failure -> exit 1"; else bad "model-inputs failure: rc=$RC"; fi

# 4a. osdi-staging-selftest target (issue #182): dispatch, failure, aggregates
reset; run_case "$BIN" osdi-staging-selftest
if [ "$RC" -eq 0 ] && [ "$(calls)" = "test-build-osdi-staging.sh|" ]; then
  ok "osdi-staging-selftest target dispatches the staging regression"; else bad "osdi-staging-selftest: rc=$RC $(calls)"; fi
reset; touch "$FAILDIR/test-build-osdi-staging.sh"; run_case "$BIN" osdi-staging-selftest
if [ "$RC" -eq 1 ] && grep -q 'FAIL: osdi-staging-selftest' "$OUT"; then
  ok "osdi-staging-selftest failure -> exit 1"; else bad "osdi-staging failure: rc=$RC"; fi
reset; touch "$FAILDIR/test-build-osdi-staging.sh"; run_case "$NONG" test
if [ "$RC" -eq 1 ] && grep -q 'FAIL: osdi-staging-selftest' "$OUT" && grep -q '22 passed, 1 failed' "$OUT" \
   && grep -q '^test-check-spec-change-has-dr.sh$' "$CALLS"; then
  ok "osdi-staging failure fails test, later gates still run"; else bad "osdi-staging test agg: rc=$RC"; fi
reset; touch "$FAILDIR/test-build-osdi-staging.sh"; run_case "$NONG" ci
if [ "$RC" -eq 1 ] && grep -q 'FAIL: osdi-staging-selftest' "$OUT"; then
  ok "osdi-staging failure fails ci"; else bad "osdi-staging ci agg: rc=$RC"; fi

# 4b4. deck-integrity targets (issue #143)
reset; run_case "$BIN" deck-integrity-selftest
if [ "$RC" -eq 0 ] && [ "$(calls)" = "test-record-deck-integrity.sh|" ]; then
  ok "deck-integrity-selftest target dispatches the fixture self-test"; else bad "deck-integrity-selftest: rc=$RC $(calls)"; fi
reset; run_case "$BIN" deck-integrity
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-record-deck-integrity.sh|" ]; then
  ok "deck-integrity target dispatches the integrity gate"; else bad "deck-integrity: rc=$RC $(calls)"; fi
reset; touch "$FAILDIR/check-record-deck-integrity.sh"; run_case "$BIN" deck-integrity
if [ "$RC" -eq 1 ]; then ok "deck-integrity failure -> exit 1"; else bad "deck-integrity failure: rc=$RC"; fi

# 4c. grading-fixtures target: dispatch, failure propagation, no ngspice needed
reset; run_case "$NONG" grading-fixtures
if [ "$RC" -eq 0 ] && [ "$(calls)" = "run-grading-fixtures.sh|" ]; then
  ok "grading-fixtures target dispatches without ngspice"; else bad "grading-fixtures: rc=$RC $(calls)"; fi
reset; touch "$FAILDIR/run-grading-fixtures.sh"; run_case "$NONG" test
if [ "$RC" -eq 1 ] && grep -q 'FAIL: grading-fixtures' "$OUT" && grep -q '22 passed, 1 failed' "$OUT" \
   && grep -q '^check-python.sh tests$' "$CALLS"; then
  ok "grading-fixtures failure fails test, later gates still run"; else bad "grading-fixtures fail: rc=$RC"; fi

# 5. all without ngspice: counted skip, exit 0; --strict -> 1
reset; run_case "$NONG" all
if [ "$RC" -eq 0 ] && grep -q 'SKIPPED: method: ngspice 42 not found' "$OUT" \
   && grep -q 'SKIPPED: pr-diff' "$OUT" && grep -q '0 failed, 2 skipped' "$OUT" \
   && ! grep -q 'run-method-checks' "$CALLS" && grep -q '^check-signoff.sh$' "$CALLS"; then
  ok "all without ngspice: counted skips, exit 0"; else bad "all skip: rc=$RC"; cat "$OUT"; fi
reset; run_case "$NONG" --strict all
if [ "$RC" -eq 1 ] && grep -q -- '--strict' "$OUT"; then
  ok "all --strict with skips -> exit 1"; else bad "strict: rc=$RC"; fi
reset; run_case "$NONG" all --strict   # npm run check:all -- --strict
if [ "$RC" -eq 1 ] && grep -q -- '--strict' "$OUT"; then
  ok "options after the aggregate (npm -- form) are honoured"; else bad "trailing strict: rc=$RC"; fi
reset; run_case "$NONG" test extra
if [ "$RC" -eq 2 ] && [ ! -s "$CALLS" ]; then
  ok "stray argument to an aggregate -> exit 2"; else bad "stray arg: rc=$RC"; fi

# 5b. py-klayout: skipped in all without the wheel, runs with it, and always
#     required as a single target
reset; run_case "$NOKL" all
if [ "$RC" -eq 0 ] && grep -q 'SKIPPED: py-klayout: klayout pip wheel not importable' "$OUT" \
   && ! grep -q 'check-python.sh klayout' "$CALLS"; then
  ok "all without klayout wheel: py-klayout counted skip"; else bad "all no klayout: rc=$RC"; cat "$OUT"; fi
reset; run_case "$NOKL" --strict all
if [ "$RC" -eq 1 ]; then ok "all --strict with py-klayout skipped -> exit 1"; else bad "strict klayout: rc=$RC"; fi
reset; run_case "$BIN" all
if grep -q '^check-python.sh klayout$' "$CALLS"; then
  ok "all with klayout wheel runs py-klayout"; else bad "all klayout run: $(calls)"; fi
reset; touch "$FAILDIR/check-python.sh"; run_case "$NOKL" py-klayout
if [ "$RC" -eq 1 ] && grep -q '^check-python.sh klayout$' "$CALLS"; then
  ok "py-klayout single target always runs the gate (failure -> exit 1)"; else bad "py-klayout single: rc=$RC"; fi
reset; run_case "$BIN" py-compile
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-python.sh compile|" ]; then
  ok "py-compile target"; else bad "py-compile: $(calls)"; fi

# 6. wrong-version ngspice: skip in all, failure for method
reset; NGSPICE_VER=ngspice-41 run_case "$BIN" --base HEAD all
if [ "$RC" -eq 0 ] && grep -q 'SKIPPED: method: ngspice 42 not found (found ngspice-41)' "$OUT"; then
  ok "ngspice-41 -> counted skip in all"; else bad "wrong version all: rc=$RC"; fi
reset; NGSPICE_VER=ngspice-41 run_case "$BIN" method
if [ "$RC" -eq 1 ] && [ ! -s "$CALLS" ]; then
  ok "ngspice-41 -> method target fails, runner not started"; else bad "wrong version method: rc=$RC"; fi
reset; run_case "$NONG" method
if [ "$RC" -eq 1 ] && grep -q 'MISSING TOOL: ngspice 42 not found' "$OUT"; then
  ok "no ngspice -> method target fails"; else bad "no ngspice method: rc=$RC"; fi

# 7. method with ngspice 42: artifact dir forwarded; failure propagates
reset; run_case "$BIN" method "$T/art"
if [ "$RC" -eq 0 ] && [ "$(calls)" = "run-method-checks.sh $T/art|" ]; then
  ok "method forwards the artifact dir"; else bad "method fwd: rc=$RC calls=$(calls)"; fi
reset; touch "$FAILDIR/run-method-checks.sh"; run_case "$BIN" method "$T/art"
if [ "$RC" -eq 1 ]; then ok "method failure -> exit 1"; else bad "method failure: rc=$RC"; fi
reset; run_case "$BIN" --strict --base HEAD --artifacts "$T/art" all
if [ "$RC" -eq 0 ] && grep -q "^run-method-checks.sh $T/art$" "$CALLS" \
   && grep -q '^check-sim-append-only.sh --base HEAD$' "$CALLS" \
   && grep -q '^check-spec-change-has-dr.sh --base HEAD$' "$CALLS" \
   && grep -q '0 failed, 0 skipped' "$OUT"; then
  ok "all --strict with every tool and --base: no skips, exit 0"; else bad "all full: rc=$RC calls=$(calls)"; fi

# 8. argument forwarding to single targets
reset; run_case "$BIN" lint a.sh b.sh
if [ "$RC" -eq 0 ] && [ "$(calls)" = "lint-shell.sh a.sh b.sh|" ]; then
  ok "lint forwards file args"; else bad "lint fwd: $(calls)"; fi
reset; run_case "$BIN" spec-dr --base "$FIRST" --head HEAD
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-spec-change-has-dr.sh --base $FIRST --head HEAD|" ]; then
  ok "spec-dr forwards --base/--head"; else bad "spec-dr fwd: $(calls)"; fi
reset; run_case "$BIN" append-only
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-sim-append-only.sh|" ]; then
  ok "append-only with no args keeps the checker's CI default"; else bad "append-only bare: $(calls)"; fi
reset; touch "$FAILDIR/check-spec-change-has-dr.sh"; run_case "$BIN" pr-diff --base "$FIRST"
if [ "$RC" -eq 1 ] && [ "$(calls)" = "check-sim-append-only.sh --base $FIRST|check-spec-change-has-dr.sh --base $FIRST|" ]; then
  ok "pr-diff runs both diff gates and propagates failure"; else bad "pr-diff fail: rc=$RC $(calls)"; fi

# 9. unavailable explicit refs fail without running the gate
reset; run_case "$BIN" spec-dr --base no-such-ref --head HEAD
if [ "$RC" -eq 1 ] && grep -q "UNAVAILABLE REF: 'no-such-ref'" "$OUT" && [ ! -s "$CALLS" ]; then
  ok "unavailable --base on spec-dr -> exit 1"; else bad "bad ref spec-dr: rc=$RC"; fi
reset; run_case "$BIN" append-only --base no-such-ref
if [ "$RC" -eq 1 ] && [ ! -s "$CALLS" ]; then
  ok "unavailable --base on append-only -> exit 1"; else bad "bad ref append-only: rc=$RC"; fi
reset; run_case "$BIN" --base no-such-ref all
if [ "$RC" -eq 1 ] && grep -q "UNAVAILABLE REF" "$OUT"; then
  ok "unavailable --base on all -> exit 1"; else bad "bad ref all: rc=$RC"; fi
reset; run_case "$BIN" --base HEAD --head "$FIRST" pr-diff
if [ "$RC" -eq 1 ] && grep -q 'not the checked-out HEAD' "$OUT" \
   && [ "$(calls)" = "check-spec-change-has-dr.sh --base HEAD --head $FIRST|" ]; then
  ok "pr-diff --head other than checked-out HEAD fails append-only"; else bad "head mismatch: rc=$RC $(calls)"; fi

# 9b. leading runner options on single targets are forwarded or rejected,
#     never silently dropped
reset; run_case "$BIN" --base no-such-ref spec-dr
if [ "$RC" -eq 1 ] && grep -q "UNAVAILABLE REF: 'no-such-ref'" "$OUT" && [ ! -s "$CALLS" ]; then
  ok "leading unavailable --base on spec-dr -> exit 1, gate not run"; else bad "leading bad ref spec-dr: rc=$RC $(calls)"; fi
reset; run_case "$BIN" --base "$FIRST" --head HEAD spec-dr
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-spec-change-has-dr.sh --base $FIRST --head HEAD|" ]; then
  ok "leading --base/--head forwarded to spec-dr"; else bad "leading fwd spec-dr: rc=$RC $(calls)"; fi
reset; run_case "$BIN" --base "$FIRST" append-only
if [ "$RC" -eq 0 ] && [ "$(calls)" = "check-sim-append-only.sh --base $FIRST|" ]; then
  ok "leading --base forwarded to append-only"; else bad "leading fwd append-only: rc=$RC $(calls)"; fi
reset; run_case "$BIN" --base no-such-ref append-only
if [ "$RC" -eq 1 ] && grep -q "UNAVAILABLE REF" "$OUT" && [ ! -s "$CALLS" ]; then
  ok "leading unavailable --base on append-only -> exit 1"; else bad "leading bad ref append-only: rc=$RC"; fi
reset; run_case "$BIN" --head HEAD append-only
if [ "$RC" -eq 2 ] && [ ! -s "$CALLS" ]; then
  ok "leading --head on append-only -> exit 2"; else bad "leading head append-only: rc=$RC"; fi
reset; run_case "$BIN" --base HEAD lint
if [ "$RC" -eq 2 ] && [ ! -s "$CALLS" ]; then
  ok "leading --base on a non-diff target -> exit 2"; else bad "leading base lint: rc=$RC"; fi
reset; run_case "$BIN" --base HEAD method
if [ "$RC" -eq 2 ] && [ ! -s "$CALLS" ]; then
  ok "leading --base on method -> exit 2"; else bad "leading base method: rc=$RC"; fi
reset; run_case "$BIN" --artifacts "$T/art" spec-dr
if [ "$RC" -eq 2 ] && [ ! -s "$CALLS" ]; then
  ok "leading --artifacts on spec-dr -> exit 2"; else bad "leading artifacts spec-dr: rc=$RC"; fi
reset; run_case "$BIN" --artifacts "$T/art" method
if [ "$RC" -eq 0 ] && [ "$(calls)" = "run-method-checks.sh $T/art|" ]; then
  ok "leading --artifacts forwarded to method"; else bad "leading artifacts method: rc=$RC $(calls)"; fi

# 10. usage errors
reset; run_case "$BIN" pr-diff
if [ "$RC" -eq 2 ]; then ok "pr-diff without --base -> exit 2"; else bad "pr-diff no base: rc=$RC"; fi
reset; run_case "$BIN" no-such-target
if [ "$RC" -eq 2 ]; then ok "unknown target -> exit 2"; else bad "unknown target: rc=$RC"; fi
reset; run_case "$BIN"
if [ "$RC" -eq 2 ]; then ok "no target -> exit 2"; else bad "no target: rc=$RC"; fi

# 11. the REAL dispatcher (run-grading-fixtures.sh) over a scratch tracked tree
#     of stub fixtures: success, injected failure (nonzero + fixture name),
#     missing PASS lines, the stage-2 floor, and an untouched source tree.
G="$T/gsrc"
mkdir -p "$G/sim/oscillator-core/tests" "$G/sim/phase-noise/tests" "$G/.github/scripts"
mkfix() { # <path> <body-line>
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$G/$1"; chmod +x "$G/$1"
}
PASSL='echo "PASS a"; echo "PASS b"'
mkfix sim/oscillator-core/tests/test_emit_tuning.sh "$PASSL"
mkfix sim/oscillator-core/tests/test_row3.sh "$PASSL"
mkfix sim/oscillator-core/tests/test_row3_global.sh "$PASSL"
mkfix sim/oscillator-core/tests/test_row7.sh "$PASSL"
mkfix sim/oscillator-core/run_validity_check.sh 'echo "all cases passed"'
mkfix sim/oscillator-core/tests/test_supply_stage2.sh 'echo "PASS a"; echo "PASS b"; touch sim/scribble'
mkfix sim/phase-noise/tests/test_validity.sh 'echo "PASS a"; echo "all cases passed"'
mkfix sim/phase-noise/tests/test_trace_gate.sh 'echo "PASS a"; echo "all cases passed"'
cp "$HERE/run-grading-fixtures.sh" "$G/.github/scripts/"
git -C "$G" init -q -b main
git -C "$G" config user.email t@t; git -C "$G" config user.name t
git -C "$G" add -A; git -C "$G" commit -q -m base
GR="$G/.github/scripts/run-grading-fixtures.sh"
grun() { PATH="$NONG" GRADING_SRC="$G" METHOD_CHECK_MIN_S2=2 "$GR" > "$OUT" 2>&1; RC=$?; }
grun
if [ "$RC" -eq 0 ] && grep -q 'all fixtures passed' "$OUT" && [ -z "$(git -C "$G" status --porcelain)" ]; then
  ok "dispatcher passes without ngspice and leaves the source tree clean"; else bad "dispatcher ok: rc=$RC"; cat "$OUT"; fi
mkfix sim/oscillator-core/tests/test_row7.sh 'echo "PASS a"; exit 1'
grun
if [ "$RC" -eq 1 ] && grep -q 'row7-grade exited 1' "$OUT"; then
  ok "dispatcher: failing fixture -> exit 1 naming the fixture"; else bad "dispatcher fail: rc=$RC"; fi
mkfix sim/oscillator-core/tests/test_row7.sh 'echo "no markers"'
grun
if [ "$RC" -eq 1 ] && grep -q 'row7-grade: no PASS lines' "$OUT"; then
  ok "dispatcher: fixture with no PASS lines -> exit 1"; else bad "dispatcher nopass: rc=$RC"; fi
mkfix sim/oscillator-core/tests/test_row7.sh "$PASSL"
mkfix sim/oscillator-core/run_validity_check.sh 'echo "something else"'
grun
if [ "$RC" -eq 1 ] && grep -q 'waveform-validity: no' "$OUT"; then
  ok "dispatcher: missing 'all cases passed' -> exit 1"; else bad "dispatcher validity: rc=$RC"; fi
mkfix sim/oscillator-core/run_validity_check.sh 'echo "all cases passed"'
PATH="$NONG" GRADING_SRC="$G" METHOD_CHECK_MIN_S2=3 "$GR" > "$OUT" 2>&1; RC=$?
if [ "$RC" -eq 1 ] && grep -q 'supply-stage2: 2 PASS lines (minimum 3)' "$OUT"; then
  ok "dispatcher: stage-2 PASS floor enforced"; else bad "dispatcher floor: rc=$RC"; fi
sed -i 's/PASS b"; touch/PASS b"; echo "FAIL x"; touch/' "$G/sim/oscillator-core/tests/test_supply_stage2.sh"
grun
if [ "$RC" -eq 1 ] && grep -q 'supply-stage2: 2 PASS lines (minimum 2) or a FAIL line' "$OUT"; then
  ok "dispatcher: FAIL line in stage-2 -> exit 1"; else bad "dispatcher s2 fail: rc=$RC"; fi

mkfix sim/phase-noise/tests/test_validity.sh 'echo "PASS a"; echo "FAIL pn"; echo "all cases passed"'
grun
if [ "$RC" -eq 1 ] && grep -q 'pn-validity: no PASS lines or a FAIL line' "$OUT"; then
  ok "dispatcher: FAIL line in pn-validity -> exit 1"; else bad "dispatcher pn fail: rc=$RC"; fi

TG=sim/phase-noise/tests/test_trace_gate.sh
mkfix $TG 'echo "PASS a"; echo "all cases passed"; exit 3'
grun
if [ "$RC" -eq 1 ] && grep -q 'pn-trace-gate exited 3' "$OUT"; then
  ok "dispatcher: nonzero pn-trace-gate -> exit 1"; else bad "dispatcher tg rc: rc=$RC"; fi
mkfix $TG 'echo "PASS a"; echo "FAIL tg"; echo "all cases passed"'
grun
if [ "$RC" -eq 1 ] && grep -q 'pn-trace-gate: no PASS lines or a FAIL line' "$OUT"; then
  ok "dispatcher: FAIL line in pn-trace-gate -> exit 1"; else bad "dispatcher tg fail: rc=$RC"; fi
mkfix $TG 'echo "all cases passed"'
grun
if [ "$RC" -eq 1 ] && grep -q 'pn-trace-gate: no PASS lines' "$OUT"; then
  ok "dispatcher: pn-trace-gate without PASS lines -> exit 1"; else bad "dispatcher tg nopass: rc=$RC"; fi
mkfix $TG 'echo "PASS a"'
grun
if [ "$RC" -eq 1 ] && grep -q "pn-trace-gate: no 'all cases passed'" "$OUT"; then
  ok "dispatcher: pn-trace-gate without completion marker -> exit 1"; else bad "dispatcher tg marker: rc=$RC"; fi
mkfix $TG 'echo "PASS a"; echo "all cases passed"'
# missing python3 -> setup error (exit 2), not a misleading fixture verdict
NOPY="$T/bin-nopy"; mkdir -p "$NOPY"
for f in "$NONG"/*; do [ "$(basename "$f")" = python3 ] || ln -s "$(readlink -f "$f")" "$NOPY/"; done
PATH="$NOPY" GRADING_SRC="$G" METHOD_CHECK_MIN_S2=2 "$GR" > "$OUT" 2>&1; RC=$?
if [ "$RC" -eq 2 ] && grep -q 'python3 not found' "$OUT"; then
  ok "dispatcher: missing python3 -> exit 2"; else bad "dispatcher no python3: rc=$RC"; fi

echo "check-all self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
