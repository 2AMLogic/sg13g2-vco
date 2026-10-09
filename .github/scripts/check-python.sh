#!/usr/bin/env bash
# Python gates (issue #118): the repo's tracked *.py had no CI gate at all.
#
# Usage: check-python.sh [--root DIR] <compile|tests|klayout>
#
#   compile   py_compile over EVERY tracked *.py (git ls-files, so the list
#             cannot go stale). Syntax only: nothing is imported or run, so
#             scripts that need numpy/openEMS/klayout/the PDK are covered too.
#   tests     stdlib unittest known-answer tests in tests/stdlib. Pure
#             python3 standard library; no klayout, klt or PDK.
#   klayout   unittest tests in tests/klayout for the klayout-needing scripts
#             (snap_grid / break_ring / prune_spirals macros, lvsdb_summary).
#             Needs the klayout pip wheel at the version in
#             .github/klayout-pip-version -- a missing or different klayout is
#             a FAILURE, never a skip. (This pin is the `klayout` wheel; it is
#             unrelated to .github/klt-version, which pins klayout-tools.)
#
# --root DIR grades another tree (used by test-check-python.sh); default is
# this repository. PYTHON overrides the interpreter (default python3). All
# Python runs in isolated mode (-I). Nothing is installed by this script.
#
# Exit: 0 gate passed, 1 gate failed or tool missing, 2 usage error.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PY="${PYTHON:-python3}"

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' \
    "${BASH_SOURCE[0]}" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; ROOT="$(cd "$2" && pwd)" || exit 2; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "check-python: unknown option $1" >&2; usage ;;
    *) break ;;
  esac
done
[ $# -eq 1 ] || usage
MODE="$1"

if ! command -v "$PY" >/dev/null 2>&1; then
  echo "check-python: $PY not found on PATH" >&2
  exit 1
fi

run_compile() {
  local files=() f tmp rc=0
  while IFS= read -r f; do files+=("$f"); done < <(git -C "$ROOT" ls-files '*.py')
  if [ "${#files[@]}" -eq 0 ]; then
    echo "check-python: no tracked *.py files -- refusing to pass an empty gate" >&2
    return 1
  fi
  tmp="$(mktemp -d)"
  # Compile to a scratch dir so no __pycache__ lands in the tree.
  (cd "$ROOT" && "$PY" -I -c '
import os, py_compile, sys
tmp, bad = sys.argv[1], 0
for i, f in enumerate(sys.argv[2:]):
    try:
        py_compile.compile(f, cfile=os.path.join(tmp, "%d.pyc" % i), doraise=True)
    except py_compile.PyCompileError as e:
        print("FAIL: " + str(e), file=sys.stderr)
        bad += 1
print("py_compile: %d file(s), %d failure(s)" % (len(sys.argv) - 2, bad))
sys.exit(1 if bad else 0)
' "$tmp" "${files[@]}") || rc=1
  rm -rf "$tmp"
  return "$rc"
}

run_unittest() {
  # run_unittest <dir>: a missing dir or zero discovered tests is a failure.
  local dir="$ROOT/$1"
  if [ ! -d "$dir" ]; then
    echo "check-python: $1 not found" >&2
    return 1
  fi
  # -B: no bytecode written into the tree.
  (cd "$dir" && "$PY" -I -B -m unittest discover -v -s "$dir" -p 'test_*.py')
}

run_klayout() {
  local want have
  want="$(tr -d '[:space:]' < "$ROOT/.github/klayout-pip-version" 2>/dev/null)"
  if [ -z "$want" ]; then
    echo "check-python: .github/klayout-pip-version missing or empty" >&2
    return 1
  fi
  have="$("$PY" -I -c 'import importlib.metadata as m; print(m.version("klayout"))' 2>/dev/null)"
  if [ -z "$have" ]; then
    echo "MISSING TOOL: klayout pip wheel (pip install klayout==$want)" >&2
    return 1
  fi
  if [ "$have" != "$want" ]; then
    echo "check-python: klayout version mismatch: found $have, pinned $want" >&2
    return 1
  fi
  run_unittest tests/klayout
}

case "$MODE" in
  compile) run_compile ;;
  tests) run_unittest tests/stdlib ;;
  klayout) run_klayout ;;
  *) echo "check-python: unknown mode '$MODE'" >&2; usage ;;
esac
