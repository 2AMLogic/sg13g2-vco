#!/usr/bin/env python3
"""Audited inventories behind T1 items 1, 9 and 10 (issue #243).

`klt signoff` (>= 0.7.0) accepts a `kind: generic` envelope for these items
when it is bound to an audited artifact: the envelope declares
`"t1_item": <n>`, names the artifact in `provenance.input.path`, and the
manifest pins the same `content_hash`. That proves the artifact's *bytes* are
fresh. It does not prove the files the artifact describes have not moved, so
the artifacts bound here are inventories carrying the sha256 of every member
file, and this module is both their only writer and their verifier:

* `build_inventory` derives an inventory from the tree and raises when the
  audit fails (a listed file missing, a testbench with no classification).
* `verify` rebuilds each inventory from the live tree and compares it with the
  committed one member by member, so a changed, deleted or added file fails
  with its name even though the inventory's own bytes did not change. It also
  checks the envelope -> inventory and manifest -> envelope hash bindings.

Pure stdlib. No klt, PDK, xschem or ngspice. Nothing here runs a simulation,
and `sim/` is only read.

    python3 -I signoff/inventories.py --check    # CI: fail on drift (default)
    python3 -I signoff/inventories.py --regen    # rewrite inventories + envelopes
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

EVIDENCE = "signoff/evidence"
ITEM_INVENTORY = {
    1: f"{EVIDENCE}/inventory-1-design-sources.json",
    9: f"{EVIDENCE}/inventory-9-testbenches.json",
    10: f"{EVIDENCE}/inventory-10-repo-hygiene.json",
}
ITEM_ENVELOPE = {
    1: f"{EVIDENCE}/t1-item-1-design-sources.json",
    9: f"{EVIDENCE}/t1-item-9-testbenches.json",
    10: f"{EVIDENCE}/t1-item-10-repo-hygiene.json",
}
MANIFEST = "signoff/manifest.json"

SCHEMATIC = "design/vco.sch"
NETLIST = "design/vco.spice"
NETLIST_GATE = "design/netlist.sh"
NETLIST_GATE_CMD = "design/netlist.sh --check"
PDK_PIN = "sim/pdk.json"
SPEC = "spec/target-spec.md"
SPEC_DRS = (
    "spec/decision-records/DR-003-target-spec-ratification.md",
    "spec/decision-records/DR-004-target-spec-ratification-pass-2.md",
)
VALIDATION_CMD = ".github/scripts/check-all.sh test"

# Testbench directories whose graded run is blocked on open issues. A bench
# listed here ships and is inventoried, but no committed evidence grades it
# against the current netlist: it is "shipped-but-not-yet-graded", never
# omitted and never counted as measured.
BLOCKED = {
    "sim/oscillator-core/testbench": [50, 94],
    "sim/phase-noise/testbench": [53, 94],
}
TESTBENCH_GLOB = "sim/*/testbench/*"
RUNNER_GLOB = "sim/**/*.sh"
RUNNER_EXCLUDE = ("/tests/", "/records/", "/netlist-snapshots/", "/corners/")

SUMMARY = {
    1: (
        "Audited inventory for T1 item 1 (Design sources): {n} files "
        "(schematic design/vco.sch, derived netlist design/vco.spice and the "
        "regeneration script), each listed with its sha256; signoff/inventories.py --check "
        "re-derives the inventory from the live tree in CI. The netlist "
        "freshness gate '" + NETLIST_GATE_CMD + "' needs xschem and an "
        "IHP-Open-PDK install, which the signoff CI does not have: it did NOT "
        "run there, so this envelope does not assert the netlist is "
        "regenerated from the schematic -- only that both files are the bytes "
        "inventoried. Run the gate where xschem and the PDK exist."
    ),
    9: (
        "Audited inventory for T1 item 9 (Testbenches shipped): {n} "
        "testbench templates under sim/*/testbench/, each with its sha256, the "
        "runner script(s) that reference it, the pinned PDK release "
        "(sim/pdk.json) and the pinned klt version. Benches whose graded run "
        "is blocked (#50, #53, #94) are listed as shipped-but-not-yet-graded. "
        "This proves the benches ship and their bytes are unchanged; it does "
        "not run a simulation or grade any specification row."
    ),
    10: (
        "Audited inventory for T1 item 10 (Repo hygiene): {n} files "
        "(README.md, LICENSE, the ratified spec and its DR-003/DR-004 "
        "decision records, the CI workflows and the shared gate runner), each "
        "with its sha256, plus the CI command that validates harness and "
        "evidence formats ('" + VALIDATION_CMD + "'). signoff/inventories.py --check "
        "re-derives the inventory from the live tree in CI."
    ),
}


def sha256_of(rel: str, root: Path = REPO_ROOT) -> str:
    return "sha256:" + hashlib.sha256((root / rel).read_bytes()).hexdigest()


def member(rel: str, root: Path) -> dict:
    if not (root / rel).is_file():
        raise SystemExit(f"inventory audit failed: {rel} is not a file")
    return {"path": rel, "sha256": sha256_of(rel, root)}


def _tracked_files(root: Path, pattern: str) -> list[str]:
    return sorted(
        p.relative_to(root).as_posix() for p in root.glob(pattern) if p.is_file()
    )


def build_design_sources(root: Path) -> dict:
    return {
        "inventory": "design-sources",
        "t1_item": 1,
        "members": [member(p, root) for p in (SCHEMATIC, NETLIST, NETLIST_GATE)],
        "regeneration_gate": {
            "command": NETLIST_GATE_CMD,
            "requires": ["xschem", "IHP-Open-PDK"],
            "ran_in_signoff_ci": False,
        },
    }


def _runners(root: Path) -> dict[str, list[str]]:
    """Map testbench basename -> runner scripts that mention it."""
    scripts = [
        p
        for p in _tracked_files(root, RUNNER_GLOB)
        if not any(x in "/" + p for x in RUNNER_EXCLUDE)
    ]
    texts = {p: (root / p).read_text(errors="replace") for p in scripts}
    out: dict[str, list[str]] = {}
    for tb in _tracked_files(root, TESTBENCH_GLOB):
        base = Path(tb).name
        out[tb] = [p for p in scripts if base in texts[p]]
    return out


def build_testbenches(root: Path) -> dict:
    runners = _runners(root)
    runner_paths = sorted({r for rs in runners.values() for r in rs})
    benches = []
    for tb, rs in runners.items():
        directory = Path(tb).parent.as_posix()
        blocked = BLOCKED.get(directory)
        known_answer = "known_answer" in Path(tb).name
        if blocked and not known_answer:
            status = "shipped-but-not-yet-graded"
        else:
            status = "shipped"
        entry = {
            **member(tb, root),
            "status": status,
            "runners": rs,
        }
        if status == "shipped-but-not-yet-graded":
            entry["blocked_by"] = [f"#{n}" for n in blocked]
        if not rs:
            entry["note"] = "no runner script in sim/ references this bench"
        benches.append(entry)
    cold = []
    for r in runner_paths:
        head = "\n".join((root / r).read_text(errors="replace").splitlines()[:12])
        cold.append({**member(r, root), "cold_start_documented": bool(re.search(r"cold-start", head, re.I))})
    pdk = json.loads((root / PDK_PIN).read_text())
    klt = (root / ".github/klt-version").read_text().strip()
    return {
        "inventory": "testbenches",
        "t1_item": 9,
        "pdk": {
            "pin_file": member(PDK_PIN, root),
            "source": pdk["source"],
            "release_tag": pdk["release_tag"],
            "tarball_sha256": pdk["tarball_sha256"],
            "documented_tool_versions": {
                k: v
                for k, v in pdk["documented_tool_versions_from_pdk_versions_txt"].items()
                if k != "note"
            },
        },
        "klt_version": klt,
        "testbenches": benches,
        "runners": cold,
    }


def build_repo_hygiene(root: Path) -> dict:
    workflows = _tracked_files(root, ".github/workflows/*.yml")
    paths = [
        "README.md",
        "LICENSE",
        SPEC,
        *SPEC_DRS,
        *workflows,
        ".github/scripts/check-all.sh",
    ]
    return {
        "inventory": "repo-hygiene",
        "t1_item": 10,
        "members": [member(p, root) for p in paths],
        "format_validation_command": VALIDATION_CMD,
    }


BUILDERS = {1: build_design_sources, 9: build_testbenches, 10: build_repo_hygiene}


def member_paths(inv: dict) -> dict[str, str]:
    """path -> sha256 for every file an inventory binds."""
    out = {}
    for m in inv.get("members", []) + inv.get("testbenches", []) + inv.get("runners", []):
        out[m["path"]] = m["sha256"]
    if "pdk" in inv:
        out[inv["pdk"]["pin_file"]["path"]] = inv["pdk"]["pin_file"]["sha256"]
    return out


def dump(obj: dict) -> str:
    return json.dumps(obj, indent=2) + "\n"


def envelope_for(item: int, inv_text: str, n: int) -> dict:
    rel = ITEM_INVENTORY[item]
    return {
        "schema_version": 1,
        "kind": "generic",
        "t1_item": item,
        "status": "pass",
        "summary": SUMMARY[item].format(n=n),
        "source": rel,
        "provenance": {
            "klt_version": None,
            "klayout_version": None,
            "pdk": None,
            "deck": None,
            "input": {
                "path": {"path": rel, "scope": "repo"},
                "content_hash": "sha256:" + hashlib.sha256(inv_text.encode()).hexdigest(),
            },
        },
    }


def _count(inv: dict) -> int:
    return len(inv["testbenches"]) if inv["t1_item"] == 9 else len(inv["members"])


def regen(root: Path = REPO_ROOT) -> None:
    (root / EVIDENCE).mkdir(parents=True, exist_ok=True)
    manifest_path = root / MANIFEST
    manifest = json.loads(manifest_path.read_text())
    for item, build in BUILDERS.items():
        inv = build(root)
        text = dump(inv)
        (root / ITEM_INVENTORY[item]).write_text(text)
        env_text = dump(envelope_for(item, text, _count(inv)))
        (root / ITEM_ENVELOPE[item]).write_text(env_text)
        manifest["evidence"][str(item)] = {
            "file": ITEM_ENVELOPE[item],
            # The pin is the *bound artifact's* hash (the envelope's
            # provenance.input.content_hash), not the envelope file's own.
            "content_hash": "sha256:" + hashlib.sha256(text.encode()).hexdigest(),
        }
    manifest["evidence"] = dict(sorted(manifest["evidence"].items(), key=lambda kv: int(kv[0])))
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")


def verify(root: Path = REPO_ROOT) -> list[str]:
    """Return a list of drift messages; empty means every binding holds."""
    errors: list[str] = []
    manifest = json.loads((root / MANIFEST).read_text())
    for item, build in BUILDERS.items():
        inv_path, env_path = root / ITEM_INVENTORY[item], root / ITEM_ENVELOPE[item]
        if not inv_path.is_file() or not env_path.is_file():
            errors.append(f"item {item}: inventory or envelope missing (run --regen)")
            continue
        committed = json.loads(inv_path.read_text())
        try:
            fresh = build(root)
        except SystemExit as exc:
            errors.append(f"item {item}: {exc}")
            continue
        old, new = member_paths(committed), member_paths(fresh)
        for p in sorted(old.keys() | new.keys()):
            if p not in new:
                errors.append(f"item {item}: {p} is inventoried but no longer exists/qualifies")
            elif p not in old:
                errors.append(f"item {item}: {p} is new and not in the inventory")
            elif old[p] != new[p]:
                errors.append(f"item {item}: {p} changed since the inventory was generated")
        if not errors and committed != fresh:
            errors.append(f"item {item}: inventory fields differ from the live tree")
        inv_hash = sha256_of(ITEM_INVENTORY[item], root)
        env = json.loads(env_path.read_text())
        if env["provenance"]["input"]["content_hash"] != inv_hash:
            errors.append(f"item {item}: envelope is not bound to the current inventory bytes")
        cited = manifest["evidence"].get(str(item), {})
        if cited.get("file") != ITEM_ENVELOPE[item] or cited.get("content_hash") != inv_hash:
            errors.append(f"item {item}: signoff/manifest.json does not pin the current inventory hash")
    return errors


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "--check"
    if mode == "--regen":
        regen()
        print("regenerated inventories, envelopes and manifest citations for items 1, 9, 10")
        return 0
    if mode != "--check":
        print(__doc__, file=sys.stderr)
        return 2
    errors = verify()
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    if errors:
        print(
            "Refresh deliberately with: python3 -I signoff/inventories.py --regen, then re-render "
            "signoff/t1-report.json (see signoff/README.md).",
            file=sys.stderr,
        )
        return 1
    print("OK: inventories for T1 items 1, 9, 10 match the live tree")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
