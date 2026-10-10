#!/usr/bin/env bash
# Self-test target for the record-currency classifier (issue #122): the
# classifier/citation unittests plus the source-capture (#122) and
# model-input capture (#133) bench tests. PDK-free,
# stdlib python3 only; no simulation is run.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
rc=0
python3 -I "$ROOT/.github/scripts/test_record_currency.py" || rc=1
"$ROOT/sim/tests/test-source-capture.sh" || rc=1
"$ROOT/sim/tests/test-model-bundle.sh" || rc=1
"$ROOT/sim/tests/test-resume-checkpoint.sh" || rc=1

# Clone matrix (issue #213): the gated index bytes must be identical for the
# same main commit in a full clone, a --no-local --single-branch clone, a
# clone that also fetched every branch, and a --depth 1 clone. Local-only.
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
mkdir -p "$T/src/design" "$T/src/sim/oscillator-core/records"
git init -q -b main "$T/src"
printf '* design\nXL1 a b ind\n' > "$T/src/design/vco.spice"
g "$T/src" add -A && g "$T/src" commit -qm base
BASE="$(g "$T/src" rev-parse --short HEAD)"
g "$T/src" checkout -q -b side
echo x > "$T/src/side.txt"; g "$T/src" add -A; g "$T/src" commit -qm side
SIDE="$(g "$T/src" rev-parse --short HEAD)"
g "$T/src" checkout -q main
: > "$T/src/sim/oscillator-core/records/20261001-000000-$BASE.md"
: > "$T/src/sim/oscillator-core/records/20261001-000001-$SIDE.md"
: > "$T/src/sim/oscillator-core/records/20261001-000002-abcdef1.md"
g "$T/src" add -A && g "$T/src" commit -qm records
render() {
  python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import record_currency as r; sys.stdout.write(r.render(r.build_index(sys.argv[2])))' \
    "$ROOT/.github/scripts" "$1"
}
git clone -q "$T/src" "$T/a" 2>/dev/null
git clone -q --no-local --single-branch --branch main "$T/src" "$T/b" 2>/dev/null
git clone -q --no-local "$T/src" "$T/c" 2>/dev/null
git -C "$T/c" fetch -q --all 2>/dev/null
git clone -q --depth 1 --branch main "file://$T/src" "$T/d" 2>/dev/null
render "$T/a" > "$T/a.out"
for x in b c d; do
  render "$T/$x" > "$T/$x.out"
  if ! cmp -s "$T/a.out" "$T/$x.out"; then
    echo "FAIL: record-currency index bytes differ between clone a and clone $x" >&2
    rc=1
  fi
done
[ -s "$T/a.out" ] || { echo "FAIL: empty clone-matrix render" >&2; rc=1; }
[ "$rc" -eq 0 ] && echo "OK: record-currency clone matrix (full, single-branch, all-branches, shallow) identical"
exit "$rc"
