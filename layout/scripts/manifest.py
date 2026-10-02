#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""manifest.py -- assemble layout/vco_manifest.json.

The manifest is the machine-readable half of this phase's provenance record
(PROVENANCE.md is the prose half).  Everything in it is either a tool version
string, a request this flow issued, or a measurement read back from the
generated streams -- nothing is transcribed by hand.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


def load(path, default=None):
    try:
        with open(path) as fh:
            return json.load(fh)
    except FileNotFoundError:
        if default is None:
            raise
        return default


def git(repo, *args):
    try:
        return subprocess.check_output(["git", "-C", repo] + list(args),
                                       text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return None


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("build")
    ap.add_argument("out")
    ap.add_argument("--klt", required=True)
    ap.add_argument("--klayout", required=True)
    ap.add_argument("--pdk", required=True)
    ap.add_argument("--repo", required=True)
    a = ap.parse_args(argv)

    b = a.build
    devices = load(os.path.join(b, "devices.json"))
    mapping = load(os.path.join(b, "mapping.json"))
    verify = load(os.path.join(b, "verify.json"))
    overlay = load(os.path.join(b, "pdk_overlay.json"), {})

    dev_records = {}
    for dev_id, spec in sorted(devices.items()):
        gen = load(os.path.join(b, "dev", dev_id + ".gen.json"), {})
        ports = load(os.path.join(b, "dev", dev_id + ".ports.json"), {})
        rec = {
            "pcell": spec["pcell"],
            "params": spec["params"],
            "cell_name": gen.get("cell_name"),
            "bbox_um": gen.get("bbox_um"),
            "gds_digest": sha256(os.path.join(b, "dev", dev_id + ".gds")),
            "terminals": {k: {"x_um": v["x_um"], "y_um": v["y_um"],
                              "layer": v["layer"]}
                          for k, v in sorted(ports.get("ports", {}).items())},
        }
        if "pcell_annotations" in ports:
            rec["pcell_annotations"] = ports["pcell_annotations"]
        if "pads" in ports:
            rec["pads"] = ports["pads"]
        dev_records[dev_id] = rec

    compose = {}
    for label in ("varbank_p", "varbank_n", "core", "wiring", "top"):
        d = load(os.path.join(b, "log", label + ".json"), {})
        entry = {"generator": d.get("generator"), "cell_name": d.get("cell_name"),
                 "bbox_um": d.get("bbox_um"), "warnings": d.get("warnings", [])}
        if "nets" in d:
            entry["nets"] = [{"net": n["net"], "status": n.get("status"),
                              "routed": n.get("routed"),
                              "route_length_um": n.get("route_length_um")}
                             for n in d["nets"]]
            entry["unrouted_nets"] = d.get("unrouted_nets", [])
            entry["drc_hints_notes"] = d.get("drc_hints", {}).get("notes", [])
        if "shape_count" in d:
            entry["shape_count"] = d["shape_count"]
            entry["label_count"] = d.get("label_count")
        compose[label] = entry

    # Connectivity evidence (see generate.sh's `connectivity` stage).
    connectivity = {}
    for v, why in (("vco", "as composed"),
                   ("vco_nospiral", "with the two spiral instances deleted")):
        d = load(os.path.join(b, "log", "extract_%s.json" % v), {})
        connectivity[v] = {
            "variant": why,
            "deck": d.get("deck"),
            "net_count": d.get("net_count"),
            "nets": sorted(n.get("name") for n in d.get("nets", [])),
            "dead_metal_clusters": len(d.get("dead_metal", [])),
            "device_counts": d.get("device_counts", {}),
            "netlist_sha256": d.get("netlist_sha256"),
        }

    expected = mapping["expected_device_counts"]
    got = verify["pcell_instance_counts"]
    checks = []
    for pcell, n in sorted(expected.items()):
        stem = pcell.split("/")[-1]
        checks.append({"pcell": pcell, "expected": n,
                       "measured": got.get(stem, 0),
                       "pass": got.get(stem, 0) == n})
    labelled = {lb["text"] for lb in verify["labels"]}
    checks.append({"check": "all 9 nets labelled in the stream",
                   "expected": sorted(mapping["nets"]),
                   "measured": sorted(labelled),
                   "pass": set(mapping["nets"]) <= labelled})
    checks.append({"check": "no EM-only layers (201/0, 202/0, 210/0)",
                   "expected": [], "measured": verify["em_only_layers_found"],
                   "pass": not verify["em_only_layers_found"]})
    # Routing evidence, read out of the stream by `klt extract` rather than
    # asserted from the requests that drew it.
    nosp = connectivity.get("vco_nospiral", {})
    checks.append({
        "check": ("all 9 nets of design/vco.spice extract as 9 distinct, "
                  "singly-connected nets once the two spirals (DC shorts) "
                  "are removed"),
        "expected": sorted(mapping["nets"]),
        "measured": nosp.get("nets"),
        "pass": nosp.get("nets") == sorted(mapping["nets"])})
    for v in ("vco", "vco_nospiral"):
        checks.append({
            "check": "no dead routing metal in %s (every shape joins a net)" % v,
            "expected": 0,
            "measured": connectivity.get(v, {}).get("dead_metal_clusters"),
            "pass": connectivity.get(v, {}).get("dead_metal_clusters") == 0})

    manifest = {
        "schema_version": 1,
        "artifact": {
            "gds": "layout/vco.gds",
            "top_cell": verify["top_cell"],
            "digest": sha256(os.path.join(b, "vco.gds")),
            "dbu_um": verify["dbu_um"],
            "bbox_um": verify["bbox_um"],
            "area_mm2": verify["area_mm2"],
        },
        "provenance": {
            "generated_by": "layout/generate.sh",
            "method": ("fully scripted, headless: klt gen --pdk-pcell per "
                       "device, klt gen-compose for placement and the "
                       "router-owned nets, klt draw for the nets klt's "
                       "sg13g2 layer-role table cannot name"),
            "tools": {"klt": a.klt, "klayout": a.klayout},
            "pdk": {"install": a.pdk,
                    "overlay": overlay,
                    "note": ("the overlay repairs IHP-Open-PDK's two empty "
                             "git submodules without mutating the shared "
                             "install; see layout/scripts/pdk_env.sh and "
                             "2AMLogic/klayout-tools#1630")},
            "source_of_truth": {
                "schematic": "design/vco.sch",
                "netlist": "design/vco.spice",
                "repo_commit": git(a.repo, "rev-parse", "HEAD"),
                "repo_describe": git(a.repo, "describe", "--always", "--dirty"),
            },
            "not_signoff": ("klt draw is PDK-unaware and klt gen-compose's "
                            "nets[].routed is not a DRC guarantee; DRC "
                            "closure is issue #61, LVS closure issue #62"),
        },
        "devices": dev_records,
        "device_map": mapping["device_map"],
        "resistor_sizing": mapping["resistor_sizing"],
        "nets": mapping["nets"],
        "composition": compose,
        "connectivity": connectivity,
        "measured": {
            "pcell_instance_counts": got,
            "layers_present": verify["layers_present"],
            "labels": verify["labels"],
        },
        "acceptance_checks": checks,
    }

    with open(a.out, "w") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write("\n")

    failed = [c for c in checks if not c["pass"]]
    for c in checks:
        print("  [%s] %s" % ("ok" if c["pass"] else "FAIL",
                             c.get("pcell") or c.get("check")))
    if failed:
        print("manifest.py: %d acceptance check(s) failed" % len(failed),
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
