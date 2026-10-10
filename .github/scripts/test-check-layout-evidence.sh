#!/usr/bin/env bash
# Self-test for check-layout-evidence.sh — a gate that cannot fail is no gate.
# Each case runs on a throwaway copy of layout/, never the real tree:
#   1. pristine copy            -> passes
#   2. GDS bytes changed        -> FAILS
#   3. one record digest edited -> FAILS
#   4. one record omits digest  -> FAILS
#   5. one record holds a different, valid-looking GDS digest -> FAILS
# Mutations are applied programmatically (never by matching the current
# digest), so they stay effective after the GDS and its evidence are refreshed.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECKER="$HERE/check-layout-evidence.sh"

[ -x "$CHECKER" ] || { echo "FAIL: $CHECKER not executable" >&2; exit 1; }

pass=0
fail=0
# One tracked parent dir: cases are created in the parent shell (no command
# substitution), so cleanup always covers every tree.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
n=0

# Sets $t to a fresh throwaway copy of the evidence under test.
fresh_tree() {
  n=$((n + 1))
  t="$TMP/case$n"
  mkdir -p "$t/layout"
  cp -R "$ROOT/layout/drc" "$ROOT/layout/lvs" "$ROOT/layout/vco.gds" \
    "$ROOT/layout/vco_manifest.json" "$t/layout/"
}

# set_digest FILE JSON_KEY... VALUE : set a record field, then verify it took.
set_digest() {
  python3 - "$@" <<'PY'
import json, sys
p, *keys, value = sys.argv[1:]
d = json.load(open(p))
node = d
for k in keys[:-1]:
    node = node[k]
if node[keys[-1]] == value:
    sys.exit("mutation is a no-op: field already holds " + value)
node[keys[-1]] = value
json.dump(d, open(p, "w"))
PY
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

fresh_tree
run_case "pristine tree passes" 0 "$t"

fresh_tree
printf 'x' >> "$t/layout/vco.gds"
run_case "changed GDS bytes fail" 1 "$t"

# A digest that cannot equal any real GDS hash (and differs from the current one).
fresh_tree
set_digest "$t/layout/lvs/vco-lvs-ihp.json" input content_hash "sha256:$(printf '0%.0s' {1..64})" \
  || { echo "FAIL: digest mutation did not apply" >&2; fail=$((fail + 1)); }
run_case "edited record digest fails" 1 "$t"

fresh_tree
python3 - "$t/layout/drc/vco-cnt-c-control.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
del d["layout"]["content_hash"]
json.dump(d, open(p, "w"))
PY
run_case "record omitting digest fails" 1 "$t"

# A well-formed digest of a *different* GDS (sha256 of other bytes).
fresh_tree
other="sha256:$(printf 'not-the-committed-gds' | sha256sum | cut -d' ' -f1)"
set_digest "$t/layout/vco_manifest.json" artifact digest "$other" \
  || { echo "FAIL: digest mutation did not apply" >&2; fail=$((fail + 1)); }
run_case "record with another valid GDS digest fails" 1 "$t"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
