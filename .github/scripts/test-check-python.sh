#!/usr/bin/env bash
# Self-test for check-python.sh (issue #118) -- a Python gate that cannot fail
# is indistinguishable from no gate. Before trusting its verdict on the real
# tree, prove it still rejects each defect class it exists to catch. Modeled on
# test-check-signoff.sh; every case runs in a throwaway git tree, never the
# real one, and needs only bash, git and python3 (no klayout, klt or PDK).
#
# Cases:
#   1. pristine fixture                     -> compile and tests PASS
#   2. tracked file with a syntax error     -> compile FAILS
#   3. deliberately failing unittest        -> tests FAILS
#   4. test dir with zero tests             -> tests FAILS (empty != green)
#   5. no tracked *.py                      -> compile FAILS (empty != green)
#   6. klayout absent / version mismatch    -> klayout FAILS (never a skip)
#   7. klayout at the pinned version        -> klayout runs tests/klayout, PASSES
#   8. real tree: compile covers every tracked *.py (count matches git)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REAL_ROOT="$(cd "$HERE/../.." && pwd)"
CHECKER="$HERE/check-python.sh"

if [ ! -x "$CHECKER" ]; then
  echo "FAIL: $CHECKER not found or not executable" >&2
  exit 1
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0
fail=0

run_case() {
  # run_case <name> <expect: 0=pass 1=fail> <mode> <tree> [extra-env...]
  local name="$1" expect="$2" mode="$3" tree="$4" got
  shift 4
  if env "$@" "$CHECKER" --root "$tree" "$mode" >"$T/out" 2>"$T/err"; then
    got=0
  else
    got=1
  fi
  if [ "$got" -eq "$expect" ]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (expected $expect, got $got)" >&2
    cat "$T/err" >&2
    fail=$((fail + 1))
  fi
}

n=0
fresh_tree() {
  # A minimal repo shaped like the real one: a tracked script, a passing
  # stdlib test, a (passing) klayout test dir and a klayout pin.
  n=$((n + 1))
  tree="$T/tree$n"
  mkdir -p "$tree/tests/stdlib" "$tree/tests/klayout" "$tree/.github"
  printf 'def f():\n    return 1\n' > "$tree/mod.py"
  cat > "$tree/tests/stdlib/test_ok.py" <<'PY'
import unittest


class T(unittest.TestCase):
    def test_ok(self):
        self.assertEqual(1 + 1, 2)
PY
  cp "$tree/tests/stdlib/test_ok.py" "$tree/tests/klayout/test_ok.py"
  echo "1.2.3" > "$tree/.github/klayout-pip-version"
  git -C "$tree" init -q
  git -C "$tree" add -A
  echo "$tree"
}

# 1. Pristine copy passes.
t="$(fresh_tree)"
run_case "pristine tree: compile passes" 0 compile "$t"
run_case "pristine tree: tests pass" 0 tests "$t"

# 2. Syntax error in a tracked file fails the compile gate.
t="$(fresh_tree)"
printf 'def broken(:\n' > "$t/bad.py"
git -C "$t" add bad.py
run_case "syntax error fails compile" 1 compile "$t"

# 3. A deliberately failing test fails the tests gate.
t="$(fresh_tree)"
cat > "$t/tests/stdlib/test_deliberate_failure.py" <<'PY'
import unittest


class T(unittest.TestCase):
    def test_must_fail(self):
        self.assertEqual(1, 2, "deliberate failure fixture")
PY
run_case "deliberately failing test fails tests" 1 tests "$t"

# 4. Zero discovered tests must not read as green.
t="$(fresh_tree)"
rm "$t/tests/stdlib/test_ok.py"
run_case "zero tests fails tests" 1 tests "$t"

# 5. No tracked *.py must not read as green.
t="$(fresh_tree)"
git -C "$t" rm -q -r -f --cached . >/dev/null
run_case "no tracked python fails compile" 1 compile "$t"

# 6. klayout gate: absent wheel and wrong version both fail. A stub
#    interpreter stands in for python3 so no klayout is needed.
mkdir -p "$T/stub-none" "$T/stub-ver"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/stub-none/python3"
printf '#!/usr/bin/env bash\necho 1.2.3\n' > "$T/stub-ver/python3"
chmod +x "$T/stub-none/python3" "$T/stub-ver/python3"

t="$(fresh_tree)"
run_case "absent klayout fails (not skipped)" 1 klayout "$t" "PYTHON=$T/stub-none/python3"
if grep -q "MISSING TOOL" "$T/err"; then
  echo "PASS: absent klayout reports MISSING TOOL"; pass=$((pass + 1))
else
  echo "FAIL: absent klayout reports MISSING TOOL (wrong reason)" >&2; fail=$((fail + 1))
fi

echo "9.9.9" > "$t/.github/klayout-pip-version"
run_case "klayout version mismatch fails" 1 klayout "$t" "PYTHON=$T/stub-ver/python3"
if grep -q "version mismatch" "$T/err"; then
  echo "PASS: version mismatch reports the reason"; pass=$((pass + 1))
else
  echo "FAIL: version mismatch reports the reason (wrong reason)" >&2; fail=$((fail + 1))
fi

# 7. Pinned version present: the gate proceeds to the klayout tests. With the
#    stub interpreter (which exits 0) this proves the version check passes.
echo "1.2.3" > "$t/.github/klayout-pip-version"
run_case "klayout at pinned version passes" 0 klayout "$t" "PYTHON=$T/stub-ver/python3"

# 8. The real tree's compile gate sees every tracked *.py.
want="$(git -C "$REAL_ROOT" ls-files '*.py' | wc -l | tr -d ' ')"
if "$CHECKER" --root "$REAL_ROOT" compile 2>/dev/null | grep -q "py_compile: $want file(s), 0 failure(s)"; then
  echo "PASS: real tree compile covers all $want tracked files"; pass=$((pass + 1))
else
  echo "FAIL: real tree compile did not cover all $want tracked files" >&2; fail=$((fail + 1))
fi

echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
