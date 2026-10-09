#!/usr/bin/env bash
# Self-test for check-layout-evidence.sh — a gate that cannot fail is no gate.
# Each case runs on a throwaway copy of layout/, never the real tree:
#   1. pristine copy            -> passes
#   2. GDS bytes changed        -> FAILS
#   3. one record digest edited -> FAILS
#   4. one record omits digest  -> FAILS

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECKER="$HERE/check-layout-evidence.sh"

[ -x "$CHECKER" ] || { echo "FAIL: $CHECKER not executable" >&2; exit 1; }

pass=0
fail=0
trees=()
trap 'rm -rf "${trees[@]}"' EXIT

fresh_tree() {
  t="$(mktemp -d)"
  trees+=("$t")
  mkdir "$t/layout"
  cp -R "$ROOT/layout/drc" "$ROOT/layout/lvs" "$ROOT/layout/vco.gds" \
    "$ROOT/layout/vco_manifest.json" "$t/layout/"
  echo "$t"
}

run_case() {
  name="$1"; expect="$2"; tree="$3"
  if "$CHECKER" --root "$tree" >/dev/null 2>&1; then got=0; else got=1; fi
  if [ "$got" -eq "$expect" ]; then
    echo "PASS: $name"; pass=$((pass + 1))
  else
    echo "FAIL: $name (expected $expect, got $got)" >&2; fail=$((fail + 1))
  fi
}

t="$(fresh_tree)"
run_case "pristine tree passes" 0 "$t"

t="$(fresh_tree)"
printf 'x' >> "$t/layout/vco.gds"
run_case "changed GDS bytes fail" 1 "$t"

t="$(fresh_tree)"
sed -i 's/sha256:937e5b16/sha256:937e5b17/' "$t/layout/lvs/vco-lvs-ihp.json"
run_case "edited record digest fails" 1 "$t"

t="$(fresh_tree)"
python3 - "$t/layout/drc/vco-cnt-c-control.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
del d["layout"]["content_hash"]
json.dump(d, open(p, "w"))
PY
run_case "record omitting digest fails" 1 "$t"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
