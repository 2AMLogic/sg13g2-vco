#!/usr/bin/env bash
# Mutation self-test for check-test-wiring.sh (issue #228). Each case builds a
# disposable git repo (a mini check-all.sh, launchers and a registry), mutates
# ONE property and asserts the checker's verdict and that the message names the
# full repository-relative path / root. Nothing registered is ever executed and
# the real tree is untouched. Needs bash, git, python3.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check-test-wiring.sh"
[ -x "$CHECK" ] || { echo "FAIL: $CHECK not executable" >&2; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }

W=""   # current fixture tree
n=0
# fresh: valid tree. a, b: direct; c launches d (transitive); e/f run_fixture.
fresh() {
  n=$((n + 1)); W="$T/w$n"
  mkdir -p "$W/.github/scripts" "$W/sim/tests" "$W/sim/x/tests"
  cat > "$W/.github/scripts/check-all.sh" <<'EOT'
gate() {
  local g="$1"; shift
  case "$g" in
    a-selftest)
      run_gate "$g" "$SCRIPTS/test-a.sh" "$@" ;;
    b-selftest)
      need_tools "$g" git && run_gate "$g" "$ROOT/sim/tests/test-b.sh" "$@" ;;
    c-selftest)
      run_gate "$g" "$SCRIPTS/test-c.sh" "$@" ;;
    fix)
      run_gate "$g" "$SCRIPTS/run-fix.sh" "$@" ;;
    *) echo "unknown" >&2 ;;
  esac
  return 0
}
agg_test() {
  gate a-selftest
  gate b-selftest
  gate c-selftest
  gate fix
}
case "$TARGET" in
  test) agg_test ;;
esac
EOT
  for f in .github/scripts/test-a.sh sim/tests/test-b.sh .github/scripts/test-c.sh \
           sim/tests/test-d.sh sim/x/tests/test_e.sh .github/scripts/run-fix.sh; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$W/$f"
  done
  cat > "$W/.github/scripts/test-c.sh" <<'EOT'
#!/usr/bin/env bash
ROOT=.
rc=0
"$ROOT/sim/tests/test-d.sh" || rc=1
exit $rc
EOT
  cat > "$W/.github/scripts/run-fix.sh" <<'EOT'
#!/usr/bin/env bash
run_fixture() { :; }
run_fixture e-fix sim/x/tests/test_e.sh
EOT
  printf '# registry\n' > "$W/.github/scripts/test-wiring.tsv"
  while IFS='|' read -r t r l; do
    printf '%s\t%s\t%s\n' "$t" "$r" "$l" >> "$W/.github/scripts/test-wiring.tsv"
  done <<'EOT'
.github/scripts/test-a.sh|a-selftest|.github/scripts/check-all.sh
sim/tests/test-b.sh|b-selftest|.github/scripts/check-all.sh
.github/scripts/test-c.sh|c-selftest|.github/scripts/check-all.sh
sim/tests/test-d.sh|c-selftest|.github/scripts/test-c.sh
sim/x/tests/test_e.sh|fix|.github/scripts/run-fix.sh
EOT
}
commit() {
  git -C "$W" init -q -b main 2>/dev/null
  git -C "$W" add -A
  git -C "$W" -c user.name=t -c user.email=t@t commit -q -m t
}
OUT="$T/out"
# expect <label> <rc> [grep-pattern...]: run the checker on $W.
expect() {
  local label="$1" want="$2" rc; shift 2
  "$CHECK" --root "$W" > "$OUT" 2>&1; rc=$?
  local good=1 p
  [ "$rc" -eq "$want" ] || good=0
  for p in "$@"; do grep -qF -- "$p" "$OUT" || good=0; done
  if [ "$good" -eq 1 ]; then ok "$label"; else bad "$label (rc=$rc want $want)"; cat "$OUT"; fi
}
reg() { echo "$W/.github/scripts/test-wiring.tsv"; }

# 0. valid tree incl. the one-level transitive and run_fixture shapes
fresh; commit
expect "valid tree (direct, transitive, run_fixture) passes" 0 "5 shell self-tests"

# 1. ordinary orphan: tracked test matching a pattern with no row
fresh; printf '#!/usr/bin/env bash\n' > "$W/sim/tests/test-orphan.sh"; commit
expect "orphan test fails naming its full path" 1 "ORPHAN: sim/tests/test-orphan.sh"

# 1b. untracked scratch file does not count
fresh; commit; printf 'x\n' > "$W/sim/tests/test-scratch.sh"
expect "untracked scratch test is ignored" 0

# 1c. python tests are not enumerated
fresh; printf 'x\n' > "$W/sim/tests/test_py.py"; printf 'x\n' > "$W/.github/scripts/test_py.py"; commit
expect "python tests are out of scope" 0

# 2. comment-only mention in the launcher
fresh; sed -i 's|^"\$ROOT/sim/tests/test-d.sh" .*|# "$ROOT/sim/tests/test-d.sh" \|\| rc=1|' "$W/.github/scripts/test-c.sh"; commit
expect "comment-only reference fails" 1 "NOT LAUNCHED: sim/tests/test-d.sh"

# 2b. prose/echo and substring are not an invocation
fresh; sed -i 's|^"\$ROOT/sim/tests/test-d.sh" .*|echo "$ROOT/sim/tests/test-d.sh" \|\| rc=1|' "$W/.github/scripts/test-c.sh"; commit
expect "echo of the path fails" 1 "NOT LAUNCHED: sim/tests/test-d.sh"
fresh; sed -i 's|^"\$ROOT/sim/tests/test-d.sh"|"$ROOT/sim/tests/test-d.sh.bak"|' "$W/.github/scripts/test-c.sh"; commit
expect "substring/near-miss path fails" 1 "NOT LAUNCHED: sim/tests/test-d.sh"

# 3. root target exists but was removed from the test aggregate
fresh; sed -i '/^  gate c-selftest$/d' "$W/.github/scripts/check-all.sh"; commit
expect "root removed from aggregate fails" 1 "NOT IN TEST AGGREGATE: root target c-selftest" "sim/tests/test-d.sh"
fresh; sed -i 's|^  gate c-selftest$|  # gate c-selftest|' "$W/.github/scripts/check-all.sh"; commit
expect "commented-out aggregate entry fails" 1 "NOT IN TEST AGGREGATE: root target c-selftest"

# 3b. aggregate no longer called by the test arm
fresh; sed -i 's|test) agg_test ;;|test) : ;;|' "$W/.github/scripts/check-all.sh"; commit
expect "test arm not calling agg_test fails" 1 "does not call agg_test"

# 3c. root arm does not dispatch the test / missing root
fresh; sed -i 's|test-a.sh" "\$@"|test-zzz.sh" "$@"|' "$W/.github/scripts/check-all.sh"; commit
expect "root arm not executing the test fails" 1 "UNREACHABLE: arm a-selftest" ".github/scripts/test-a.sh"
fresh
sed -i 's|^\(.github/scripts/test-a.sh\)	a-selftest|\1	nope-selftest|' "$(reg)"; commit
expect "unknown root target fails" 1 "NO ROOT: target nope-selftest"

# 4. unreachable mutual references: neither has a chain from a root
fresh
printf '#!/usr/bin/env bash\n"$ROOT/sim/tests/test-g.sh"\n' > "$W/sim/tests/test-f.sh"
printf '#!/usr/bin/env bash\n"$ROOT/sim/tests/test-f.sh"\n' > "$W/sim/tests/test-g.sh"
printf 'sim/tests/test-f.sh\ta-selftest\tsim/tests/test-g.sh\nsim/tests/test-g.sh\ta-selftest\tsim/tests/test-f.sh\n' >> "$(reg)"
commit
expect "mutually referencing orphans fail" 1 \
  "UNREACHABLE: arm a-selftest in .github/scripts/check-all.sh does not execute sim/tests/test-g.sh for sim/tests/test-f.sh" \
  "UNREACHABLE: arm a-selftest in .github/scripts/check-all.sh does not execute sim/tests/test-f.sh for sim/tests/test-g.sh"

# 5. same-basename collision: only one of two same-named files is launched
fresh
printf '#!/usr/bin/env bash\n' > "$W/sim/x/tests/test-b.sh"
printf 'sim/x/tests/test-b.sh\tb-selftest\t.github/scripts/check-all.sh\n' >> "$(reg)"
commit
expect "same-basename collision judged by full path" 1 \
  "UNREACHABLE: arm b-selftest" "for sim/x/tests/test-b.sh"
fresh; printf '#!/usr/bin/env bash\n' > "$W/sim/x/tests/test-b.sh"; commit
expect "same-basename sibling without a row is an orphan" 1 "ORPHAN: sim/x/tests/test-b.sh"
fresh; printf '#!/usr/bin/env bash\n' > "$W/sim/x/tests/test-b.sh"
printf 'sim/x/tests/test-b.sh\tb-selftest\t.github/scripts/check-all.sh\n' >> "$(reg)"
sed -i 's|\$ROOT/sim/tests/test-b.sh" "\$@"|$ROOT/sim/x/tests/test-b.sh" "$@"|' "$W/.github/scripts/check-all.sh"; commit
expect "basename match with the wrong sibling path fails" 1 "UNREACHABLE: arm b-selftest" "for sim/tests/test-b.sh"

# 6. malformed / duplicate / absolute / traversal registry rows
fresh; printf 'sim/tests/test-h.sh\ta-selftest\n' >> "$(reg)"; commit
expect "short registry row fails" 1 "MALFORMED registry line"
fresh; printf '/abs/test-h.sh\ta-selftest\t.github/scripts/check-all.sh\n' >> "$(reg)"; commit
expect "absolute registry path fails" 1 "MALFORMED registry line" "/abs/test-h.sh"
fresh; printf 'sim/../sim/tests/test-h.sh\ta-selftest\t.github/scripts/check-all.sh\n' >> "$(reg)"; commit
expect "traversal registry path fails" 1 "MALFORMED registry line" "traversal"
fresh; printf '.github/scripts/test-a.sh\ta-selftest\t.github/scripts/check-all.sh\n' >> "$(reg)"; commit
expect "duplicate registry row fails" 1 "DUPLICATE registry row for .github/scripts/test-a.sh"
fresh; sed -i 's|run-fix.sh$|run-gone.sh|' "$(reg)"; commit
expect "untracked launcher fails" 1 "UNTRACKED launcher" "run-gone.sh"
fresh; sed -i '/test-b.sh/d' "$(reg)"; commit
expect "removed registry row is an orphan" 1 "ORPHAN: sim/tests/test-b.sh"
fresh; printf 'sim/tests/test-gone.sh\ta-selftest\t.github/scripts/check-all.sh\n' >> "$(reg)"; commit
expect "registry row for a non-file is stale" 1 "STALE: registry path sim/tests/test-gone.sh"

echo "check-test-wiring self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
