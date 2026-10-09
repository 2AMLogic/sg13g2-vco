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
  if "$CHECKER" --root "$d" --base main --head change >/dev/null 2>&1; then got=0; else got=1; fi
  rm -rf "$d"
  if [ "$got" -eq "$expect" ]; then echo "PASS: $name"; pass=$((pass+1))
  else echo "FAIL: $name (expected $expect, got $got)" >&2; fail=$((fail+1)); fi
}

DR=spec/decision-records
run_case "spec edit without DR fails"        1 spec
run_case "spec edit with valid DR passes"    0 spec $DR/DR-005-example-slug.md
run_case "malformed DR filename fails"       1 spec $DR/DR-5-bad.md
run_case "uppercase-slug DR filename fails"  1 spec $DR/DR-005-Bad_Slug.md
run_case "TEMPLATE.md edit does not count"   1 spec $DR/TEMPLATE.md
run_case "DR-only change passes"             0 $DR/DR-005-example-slug.md
run_case "unrelated change passes"           0 README.md

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
