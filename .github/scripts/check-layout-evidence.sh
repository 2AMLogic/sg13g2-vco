#!/usr/bin/env bash
# Gate: every layout record that vouches for layout/vco.gds must carry the
# sha256 of the *committed* GDS (issue #106).
#
# Pure bash + sha256sum + python3 stdlib: no klt, no PDK. Records are keyed on
# an explicit JSON field path, never by grepping for the hash, so the
# per-device sub-stream `gds_digest` entries in vco_manifest.json (which
# describe other files) are out of scope by construction. Fail closed: a
# listed record that is missing, unparsable, or lacks the field is a failure.
#
# Usage: check-layout-evidence.sh [--root DIR]

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
if [ "${1:-}" = "--root" ] && [ -n "${2:-}" ]; then
  ROOT="$2"
fi

GDS="$ROOT/layout/vco.gds"
if [ ! -f "$GDS" ]; then
  echo "FAIL: $GDS not found" >&2
  exit 1
fi
actual="sha256:$(sha256sum "$GDS" | cut -d' ' -f1)"

python3 - "$ROOT" "$actual" <<'PY'
import json, os, sys

root, actual = sys.argv[1], sys.argv[2]

# record (repo-relative) -> field path of its digest of layout/vco.gds
RECORDS = {
    "layout/vco_manifest.json": ["artifact", "digest"],
    "layout/drc/vco-drc.json": ["provenance", "input", "content_hash"],
    "layout/drc/vco-drc-ihp.json": ["provenance", "input", "content_hash"],
    "layout/drc/vco-drc-ihp-assertion.json": ["input", "content_hash"],
    "layout/drc/vco-cnt-c-control.json": ["layout", "content_hash"],
    "layout/lvs/vco-lvs-ihp.json": ["input", "content_hash"],
    "layout/lvs/vco-lvs-record.json": ["inputs", "layout", "content_hash"],
}

bad = 0
for rel, path in RECORDS.items():
    where = f"{rel} [{'.'.join(path)}]"
    try:
        with open(os.path.join(root, rel)) as fh:
            node = json.load(fh)
        for key in path:
            node = node[key]
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"FAIL: {where}: digest missing or unreadable ({exc!r})", file=sys.stderr)
        bad += 1
        continue
    if node != actual:
        print(f"FAIL: {where}: {node!r} != committed layout/vco.gds {actual}", file=sys.stderr)
        bad += 1

if bad:
    print(f"{bad} stale layout record(s): regenerate via layout/generate.sh, "
          "layout/drc.sh, layout/lvs.sh", file=sys.stderr)
    sys.exit(1)
print(f"OK: {len(RECORDS)} layout records match layout/vco.gds ({actual})")
PY
