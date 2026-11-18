#!/usr/bin/env bash
# Self-test for check-spec-change-has-dr.sh. Each case builds a throwaway git
# repo with a base commit and a change commit, then checks the verdict.
#   1. spec edit, no DR            -> FAIL
#   2. spec edit + valid DR        -> pass
#   3. spec edit + malformed DR    -> FAIL (also TEMPLATE.md-only edit)
#   4. DR only, no spec edit       -> pass
#   5. unrelated change            -> pass
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$HERE/check-spec-change-has-dr.sh"
[ -x "$CHECKER" ] || { echo "FAIL: $CHECKER not executable" >&2; exit 1; }

pass=0; fail=0
# run_case <name> <expect 0|1> <file to touch>...   ("spec" = target-spec.md)
run_case() {
  name="$1"; expect="$2"; shift 2
  d="$(mktemp -d)"
  (
    cd "$d" && git init -q -b main . &&
    git config user.email t@t && git config user.name t &&
    mkdir -p spec/decision-records &&
    echo base > spec/target-spec.md && echo t > spec/decision-records/TEMPLATE.md &&
    git add -A && git commit -qm base &&
    git checkout -q -b change
    for f in "$@"; do
      [ "$f" = spec ] && f=spec/target-spec.md
      mkdir -p "$(dirname "$f")"; echo change >> "$f"
    done
    git add -A && git commit -qm change
  ) >/dev/null 2>&1
  cb="$(case_ref "${CASE_BASE-main}" "$d")"
  ch="$(case_ref "${CASE_HEAD-change}" "$d")"
  if "$CHECKER" --root "$d" --base "$cb" --head "$ch" >/dev/null 2>&1; then got=0; else got=1; fi
  rm -rf "$d"
  if [ "$got" -eq "$expect" ]; then echo "PASS: $name"; pass=$((pass+1))
  else echo "FAIL: $name (expected $expect, got $got)" >&2; fail=$((fail+1)); fi
}

# case_ref <value> <repo>: CASE_BASE/CASE_HEAD may name a ref (default) or,
# for the merge-group shape (issue #410), "sha:main"/"sha:change" to pass the
# fixture's commit sha — how a merge_group run feeds the gate.
case_ref() {
  case "$1" in
    sha:main) git -C "$2" rev-parse main ;;
    sha:change) git -C "$2" rev-parse change ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# expect_fail_named <name> <message> <checker args...>: nonzero exit AND the
# named FAIL message — the fail-closed contract, not just any git error.
expect_fail_named() {
  name="$1"; msg="$2"; shift 2
  out="$("$CHECKER" "$@" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: $name (exit 0, expected nonzero)" >&2; fail=$((fail+1))
  elif printf '%s\n' "$out" | grep -Fq "$msg"; then
    echo "PASS: $name"; pass=$((pass+1))
  else
    echo "FAIL: $name (nonzero but message '$msg' not named)" >&2; fail=$((fail+1))
  fi
}

DR=spec/decision-records
run_case "spec edit without DR fails"        1 spec
run_case "spec edit with valid DR passes"    0 spec $DR/DR-005-example-slug.md
run_case "malformed DR filename fails"       1 spec $DR/DR-5-bad.md
run_case "uppercase-slug DR filename fails"  1 spec $DR/DR-005-Bad_Slug.md
run_case "TEMPLATE.md edit does not count"   1 spec $DR/TEMPLATE.md
run_case "DR-only change passes"             0 $DR/DR-005-example-slug.md
run_case "unrelated change passes"           0 README.md

# Merge-group cases (issue #410): a merge_group run feeds the gate raw
# base/head shas (github.event.merge_group.base_sha/head_sha) and has no
# github.base_ref. Verdict cases go through run_case with sha: refs; the
# fail-closed cases must exit nonzero with a named FAIL message, never a raw
# git error and never a silent origin/main default.
CASE_BASE=sha:main CASE_HEAD=sha:change \
  run_case "merge_group sha base/head with DR passes" 0 spec $DR/DR-005-example-slug.md
CASE_BASE=sha:main CASE_HEAD=sha:change \
  run_case "merge_group sha base/head, spec edit without DR fails" 1 spec

MG="$(mktemp -d)"
( cd "$MG" && git init -q -b main . &&
  git config user.email t@t && git config user.name t &&
  mkdir -p spec/decision-records &&
  echo base > spec/target-spec.md && echo t > spec/decision-records/TEMPLATE.md &&
  git add -A && git commit -qm base &&
  git checkout -q -b change &&
  echo change >> spec/target-spec.md &&
  echo c > spec/decision-records/DR-041-merge-queue-readiness.md &&
  git add -A && git commit -qm change ) >/dev/null 2>&1
MG_BASE="$(git -C "$MG" rev-parse main)"
MG_HEAD="$(git -C "$MG" rev-parse change)"
expect_fail_named "merge_group empty base fails closed (named)" \
  "FAIL: --base is empty" --root "$MG" --base "" --head "$MG_HEAD"
expect_fail_named "merge_group empty head fails closed (named)" \
  "FAIL: --head is empty" --root "$MG" --base "$MG_BASE" --head ""
expect_fail_named "merge_group unresolvable base sha fails closed (named)" \
  "does not resolve to a commit" \
  --root "$MG" --base 0123456789abcdef0123456789abcdef01234567 --head "$MG_HEAD"
expect_fail_named "merge_group unresolvable head sha fails closed (named)" \
  "does not resolve to a commit" \
  --root "$MG" --base "$MG_BASE" --head 0123456789abcdef0123456789abcdef01234567
rm -rf "$MG"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
