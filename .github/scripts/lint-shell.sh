#!/usr/bin/env bash
# Headless shellcheck gate (issue #98). Single source of truth for the file
# list, exclusions and severity, shared by CI (.github/workflows/lint.yml)
# and `npm run lint`.
#
# Scope: tracked repo-owned *.sh (git ls-files, so untracked files are not
# linted). Excluded: .loom/ .claude/ .agents/ and the Loom-installed root
# loom.sh wrapper (overwritten on Loom resync). --shell=bash because several
# sourced libraries (sim/env.sh, sim/lib.sh, ...) carry no shebang.
#
# Usage: lint-shell.sh [file ...]   (default: all tracked in-scope scripts)
# Single shellcheck process; exit 0 clean, non-zero on any warning+ finding.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "lint-shell: shellcheck not found on PATH" >&2
  exit 2
fi

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(
    git ls-files '*.sh' | grep -v -E '^(\.loom|\.claude|\.agents)/|^loom\.sh$' || true
  )
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "lint-shell: no shell scripts to lint"
  exit 0
fi

echo "lint-shell: shellcheck $(shellcheck --version | sed -n 's/^version: //p') on ${#files[@]} file(s)"
shellcheck --shell=bash --severity=warning "${files[@]}"
echo "lint-shell: OK"
