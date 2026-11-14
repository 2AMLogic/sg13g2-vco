"""Shared evidence-envelope scaffolding for the signoff/ generators (issue #334).

`signoff/characterization.py` (T1 item 8) and `signoff/inventories.py` (T1
items 1, 9, 10) each remain the only writer and verifier of their own
artifacts, but both speak the same `klt signoff` interface: a `kind: "generic"`
envelope bound to an audited artifact by sha256, a manifest `evidence` pin at
that same hash, and a `--check`/`--regen` CLI. That scaffolding is defined here
once, so a klt-side schema change is applied in one place instead of two.

What stays with each generator: what its artifact *is*, how the bytes are
derived, how `status` is decided, and the summary text. This module knows only
the envelope's shape and the hash / manifest / CLI plumbing.

One hash convention, deliberately: `sha256_of` and `sha256_bytes` return the
**prefixed** `"sha256:<hex>"` form, because that is what an envelope's
`provenance.input.content_hash` and a manifest pin compare against. (The
unrelated `.github/scripts/record_currency.py` writes a bare hexdigest for
`sim/record-currency.json`; it is a different consumer and is not a caller of
this module.)

Pure stdlib. Not a CLI: no `main`, and nothing is read or written on import.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

# Nine-key generic envelope; bump in lockstep with what `klt signoff` accepts.
SCHEMA_VERSION = 1


def sha256_bytes(data: bytes) -> str:
    """Prefixed digest of `data`, the form envelopes and manifest pins use."""
    return "sha256:" + hashlib.sha256(data).hexdigest()


def sha256_of(rel: str, root: Path) -> str:
    """Prefixed digest of the file at `root / rel`."""
    return sha256_bytes((root / rel).read_bytes())


def dump(obj: dict) -> str:
    """The one JSON spelling every signoff artifact is written with."""
    return json.dumps(obj, indent=2) + "\n"


def generic_envelope(item: int, source_rel: str, status: str, summary: str, content_hash: str) -> dict:
    """A `kind: "generic"` envelope for T1 `item`, bound to `source_rel`.

    `content_hash` is the prefixed digest of the *artifact's* bytes (not of the
    envelope file), which is also what the manifest pins: that pairing is what
    proves to `klt signoff` that the cited artifact is the one graded. The
    `klt_version` / `klayout_version` / `pdk` / `deck` keys are present and
    null because these generators run on stdlib python alone -- no klt, PDK or
    simulator is involved in deriving the artifact.
    """
    return {
        "schema_version": SCHEMA_VERSION,
        "kind": "generic",
        "t1_item": item,
        "status": status,
        "summary": summary,
        "source": source_rel,
        "provenance": {
            "klt_version": None,
            "klayout_version": None,
            "pdk": None,
            "deck": None,
            "input": {
                "path": {"path": source_rel, "scope": "repo"},
                "content_hash": content_hash,
            },
        },
    }


def pin_manifest(root: Path, manifest_rel: str, pins: dict[str, dict]) -> None:
    """Write `pins` into the manifest's `evidence` map and re-sort it.

    `pins` maps the T1 item number *as a string key* to its
    `{"file", "content_hash"}` citation. The map is re-sorted by integer item
    number on every write, so item 10 keeps sorting after item 9 rather than
    after item 1.
    """
    path = root / manifest_rel
    manifest = json.loads(path.read_text())
    manifest["evidence"].update(pins)
    manifest["evidence"] = dict(sorted(manifest["evidence"].items(), key=lambda kv: int(kv[0])))
    path.write_text(dump(manifest))


def run_cli(
    argv: list[str],
    *,
    script_rel: str,
    doc: str | None,
    regen,
    verify,
    regen_msg: str,
    ok_msg: str,
    root: Path,
) -> int:
    """The `--root DIR` / `--check` / `--regen` CLI both generators expose.

    `--root DIR` may appear anywhere in `argv` and is consumed before the mode
    is read, so the CI gates' `--check "$@"` form accepts it too. The mode
    defaults to `--check`, the CI-safe direction: a bare run reports drift and
    never rewrites an artifact.

    Exit codes: 0 the gate passed (or `--regen` rewrote the artifacts), 1 the
    committed artifacts drifted from their inputs, 2 usage error.
    """
    args = list(argv[1:])
    if "--root" in args:
        i = args.index("--root")
        if i + 1 >= len(args):
            print(f"{script_rel}: --root needs a directory", file=sys.stderr)
            return 2
        root = Path(args[i + 1]).resolve()
        del args[i : i + 2]
    mode = args[0] if args else "--check"
    if mode == "--regen":
        regen(root)
        print(regen_msg)
        return 0
    if mode != "--check":
        print(doc, file=sys.stderr)
        return 2
    errors = verify(root)
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    if errors:
        print(
            f"Refresh deliberately with: python3 -I {script_rel} --regen, then re-render "
            "signoff/t1-report.json (see signoff/README.md).",
            file=sys.stderr,
        )
        return 1
    print(ok_msg)
    return 0
