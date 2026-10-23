#!/usr/bin/env bash
# Store a run's raw outputs in the fleet artifact store and commit only a
# manifest (issue #253). Bytes go through `klt artifact put`; git keeps
# manifests/artifacts/<bench>-<run-id>.manifest.json and the run's Markdown
# record. Fail closed: a nonzero exit means nothing was written to the
# manifest and there is NO fallback to committing bytes.
#
# Usage: sim/store-evidence.sh <bench> <run-id> FILE [FILE...]
#   FILE: raw outputs staged outside git, e.g. under the ignored sim/build/.
#   Re-running with the same names merges into the existing manifest.
# Needs $KLT_ARTIFACT_BROKER (set for fleet-worker agent sessions) and a klt
# with `artifact put`. The broker URL is never printed or written.
# Exit: 0 stored, 1 refused or failed, 2 usage error.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${STORE_EVIDENCE_ROOT:-$(cd "${HERE}/.." && pwd)}"

[ $# -ge 3 ] || { sed -n '2,/^set -u/p' "$0" | sed '$d' >&2; exit 2; }
bench="$1"; run_id="$2"; shift 2
case "${bench}${run_id}" in *[!A-Za-z0-9._-]*|'')
  echo "store-evidence: bench and run-id must match [A-Za-z0-9._-]+" >&2; exit 2 ;;
esac

if [ -z "${KLT_ARTIFACT_BROKER:-}" ]; then
  echo "store-evidence: KLT_ARTIFACT_BROKER is unset; nothing stored, nothing committed" >&2
  exit 1
fi
if ! command -v klt >/dev/null 2>&1 || ! klt artifact put --help >/dev/null 2>&1; then
  echo "store-evidence: this klt has no 'artifact put'; nothing stored, nothing committed" >&2
  exit 1
fi
for f in "$@"; do
  [ -f "$f" ] || { echo "store-evidence: not a file: $f" >&2; exit 1; }
  if git -C "${ROOT}" ls-files --error-unmatch -- "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" >/dev/null 2>&1; then
    echo "store-evidence: $f is already tracked by git; raw outputs must stay out of the repo" >&2
    exit 1
  fi
done

dest="${ROOT}/manifests/artifacts/${bench}-${run_id}.manifest.json"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "${work}"' EXIT
staged="${work}/manifest.json"
[ ! -f "${dest}" ] || cp "${dest}" "${staged}"
# --name defaults to the path relative to the file's git checkout; the
# manifest lands in dest only after the whole put succeeded.
# klt's diagnostics are kept but the broker URL is scrubbed from them.
if ! klt artifact put --manifest "${staged}" "$@" >/dev/null 2>"${work}/err"; then
  awk -v u="${KLT_ARTIFACT_BROKER}" '{ while ((i = index($0, u)) > 0) $0 = substr($0, 1, i - 1) "<broker>" substr($0, i + length(u)); print }' "${work}/err" >&2
  echo "store-evidence: klt artifact put failed (broker unreachable or refused); nothing committed" >&2
  exit 1
fi
mkdir -p "$(dirname "${dest}")" && cp "${staged}" "${dest}" || exit 1
echo "store-evidence: wrote ${dest#"${ROOT}"/}"
