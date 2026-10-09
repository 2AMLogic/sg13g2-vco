#!/usr/bin/env bash
# Self-test for check-sim-append-only.sh: builds a scratch git repo and shows
# the checker passes add-only changes and fails each violation class.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$HERE/check-sim-append-only.sh"
[ -x "$CHECKER" ] || { echo "FAIL: $CHECKER not executable" >&2; exit 1; }

pass=0
fail=0
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

mkrepo() {
  # fresh repo with a base commit on branch main containing evidence files
  local d; R="$T/$1"
  mkdir -p "$R"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@t
  git -C "$R" config user.name t
  for d in sim/a/records sim/a/netlist-snapshots sim/a/corners \
           sim/a/b/records sim/inductor-model/em-extraction/records \
           sim/inductor-model/em-extraction/results; do
    mkdir -p "$R/$d"; echo base > "$R/$d/x.txt"
  done
  echo base > "$R/sim/README.md"
  git -C "$R" add -A
  git -C "$R" commit -q -m base
  git -C "$R" checkout -q -b pr
}

commit() { git -C "$R" add -A; git -C "$R" commit -q -m change; }

run_case() {
  # run_case <name> <expect 0|1> [base]
  local name="$1" expect="$2" base="${3:-main}" got
  if "$CHECKER" --root "$R" --base "$base" >/dev/null 2>&1; then got=0; else got=1; fi
  if [ "$got" -eq "$expect" ]; then
    echo "PASS: $name"; pass=$((pass + 1))
  else
    echo "FAIL: $name (expected $expect, got $got)" >&2; fail=$((fail + 1))
  fi
}

mkrepo add
for d in sim/a/records sim/a/netlist-snapshots sim/a/corners sim/a/b/records \
         sim/inductor-model/em-extraction/records; do echo new > "$R/$d/y.txt"; done
commit; run_case "add-only across all dirs incl. nested passes" 0

mkrepo nonev
echo changed > "$R/sim/inductor-model/em-extraction/results/x.txt"
echo changed > "$R/sim/README.md"
commit; run_case "edits to non-evidence sim files pass" 0

mkrepo nochange
run_case "empty diff passes" 0

for d in sim/a/records sim/a/netlist-snapshots sim/a/corners sim/a/b/records \
         sim/inductor-model/em-extraction/records; do
  mkrepo "mod-$(echo "$d" | tr / _)"
  echo changed > "$R/$d/x.txt"; commit
  run_case "modify in $d fails" 1
done

mkrepo del
git -C "$R" rm -q sim/a/records/x.txt; commit
run_case "delete fails" 1

mkrepo mv
git -C "$R" mv sim/a/corners/x.txt sim/a/corners/z.txt; commit
run_case "rename fails (D+A)" 1

mkrepo mixed
echo new > "$R/sim/a/records/y.txt"; echo changed > "$R/sim/a/corners/x.txt"; commit
run_case "add plus modify fails" 1

mkrepo nobase
run_case "unresolvable base fails closed" 1 no-such-ref
(unset SIM_APPEND_ONLY_BASE GITHUB_BASE_REF
 if "$CHECKER" --root "$R" >/dev/null 2>&1; then exit 1; else exit 0; fi) \
  && { echo "PASS: missing base fails closed"; pass=$((pass + 1)); } \
  || { echo "FAIL: missing base fails closed" >&2; fail=$((fail + 1)); }

mkrepo nomb
git -C "$R" checkout -q --orphan orphan; commit
run_case "no merge-base fails closed" 1 main

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
