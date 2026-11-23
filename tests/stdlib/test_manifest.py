"""Known-answer tests for layout/scripts/manifest.py (stdlib unittest only).

manifest.py has a main guard, so it is imported by path; main() is driven with
a synthetic build directory. Nothing here needs klayout, klt or the PDK.
"""
import contextlib
import copy
import io
import json
import os
import tempfile
import unittest

from _loader import load_module

manifest = load_module("vco_manifest", "layout/scripts/manifest.py")

NETS = ["A", "B"]

MAPPING = {
    "expected_device_counts": {"sg13g2/npn13G2": 2, "sg13g2/cmim": 1},
    "nets": NETS,
    "device_map": {"Q1": "npn_a"},
    "resistor_sizing": {"R1": {"l_um": 1.0}},
}
VERIFY = {
    "pcell_instance_counts": {"npn13G2": 2, "cmim": 1},
    "labels": [{"text": "A"}, {"text": "B"}],
    "em_only_layers_found": [],
    "top_cell": "vco",
    "dbu_um": 0.001,
    # the same four-key object the stream verifier (layout/scripts/
    # verify.py) supplies; equal to manifest.EXPECTED_BBOX_UM so the
    # outline check passes at baseline
    "bbox_um": {"x0": -305.13, "y0": -106.03, "x1": 305.13, "y1": 290.26},
    "area_mm2": 0.0001,
    "layers_present": ["1/0"],
}
DEVICES = {"npn_a": {"pcell": "sg13g2/npn13G2", "params": {"Nx": 1}}}
PORTS = {"ports": {"E": {"x_um": 1.0, "y_um": 2.0, "layer": "1/0", "extra": 9}}}


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        json.dump(obj, fh)


def make_build(root, verify=None):
    b = os.path.join(root, "build")
    write_json(os.path.join(b, "devices.json"), DEVICES)
    write_json(os.path.join(b, "mapping.json"), MAPPING)
    write_json(os.path.join(b, "verify.json"), verify or VERIFY)
    write_json(os.path.join(b, "dev", "npn_a.ports.json"), PORTS)
    write_json(os.path.join(b, "dev", "npn_a.gen.json"),
               {"cell_name": "npn13G2", "bbox_um": [0, 0, 1, 1]})
    for name in ("dev/npn_a.gds", "vco.gds"):
        with open(os.path.join(b, name), "wb") as fh:
            fh.write(b"abc")
    nets = [{"name": n} for n in NETS]
    for v in ("vco", "vco_nospiral"):
        write_json(os.path.join(b, "log", "extract_%s.json" % v),
                   {"deck": "d", "net_count": 2, "nets": nets, "dead_metal": [],
                    "device_counts": {}, "netlist_sha256": "x"})
    return b


def run_main(build, out):
    # main() prints one line per check (and a failure summary to stderr).
    with contextlib.redirect_stdout(io.StringIO()), \
            contextlib.redirect_stderr(io.StringIO()):
        return _run_main(build, out)


def _run_main(build, out):
    return manifest.main([build, out, "--klt", "9.9.9", "--klayout", "0.0.1",
                          "--pdk", "/pdk", "--repo", "/nonexistent-repo"])


class HelperTests(unittest.TestCase):
    def test_sha256_known_answer(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "f")
            with open(p, "wb") as fh:
                fh.write(b"abc")
            self.assertEqual(
                manifest.sha256(p),
                "sha256:ba7816bf8f01cfea414140de5dae2223"
                "b00361a396177a9cb410ff61f20015ad")

    def test_load_default_and_missing(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "absent.json")
            self.assertEqual(manifest.load(p, {"k": 1}), {"k": 1})
            with self.assertRaises(FileNotFoundError):
                manifest.load(p)

    def test_git_failure_returns_none(self):
        self.assertIsNone(manifest.git("/nonexistent-repo", "rev-parse", "HEAD"))


class MainTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name

    def test_passing_build(self):
        b = make_build(self.root)
        out = os.path.join(self.root, "m.json")
        self.assertEqual(run_main(b, out), 0)
        with open(out) as fh:
            m = json.load(fh)
        self.assertEqual(m["schema_version"], 1)
        self.assertTrue(all(c["pass"] for c in m["acceptance_checks"]))
        # 2 pcells + labels + em-only + nospiral nets + 2 dead-metal checks
        # + the artifact-outline check
        self.assertEqual(len(m["acceptance_checks"]), 8)
        self.assertEqual(m["artifact"]["digest"],
                         "sha256:ba7816bf8f01cfea414140de5dae2223"
                         "b00361a396177a9cb410ff61f20015ad")
        self.assertEqual(m["provenance"]["tools"], {"klt": "9.9.9", "klayout": "0.0.1"})
        # terminals keep only x/y/layer
        self.assertEqual(m["devices"]["npn_a"]["terminals"]["E"],
                         {"x_um": 1.0, "y_um": 2.0, "layer": "1/0"})
        self.assertIsNone(m["provenance"]["source_of_truth"]["repo_commit"])

    def test_output_is_deterministic(self):
        b = make_build(self.root)
        o1, o2 = (os.path.join(self.root, n) for n in ("a.json", "b.json"))
        run_main(b, o1)
        run_main(b, o2)
        with open(o1) as f1, open(o2) as f2:
            self.assertEqual(f1.read(), f2.read())

    def test_wrong_device_count_fails(self):
        bad = copy.deepcopy(VERIFY)
        bad["pcell_instance_counts"]["npn13G2"] = 3
        b = make_build(self.root, bad)
        out = os.path.join(self.root, "m.json")
        self.assertEqual(run_main(b, out), 1)
        with open(out) as fh:
            checks = json.load(fh)["acceptance_checks"]
        failed = [c for c in checks if not c["pass"]]
        self.assertEqual([c["pcell"] for c in failed], ["sg13g2/npn13G2"])

    def test_em_only_layer_and_missing_label_fail(self):
        bad = copy.deepcopy(VERIFY)
        bad["em_only_layers_found"] = ["201/0"]
        bad["labels"] = [{"text": "A"}]
        b = make_build(self.root, bad)
        out = os.path.join(self.root, "m.json")
        self.assertEqual(run_main(b, out), 1)
        with open(out) as fh:
            checks = json.load(fh)["acceptance_checks"]
        self.assertEqual(sum(1 for c in checks if not c["pass"]), 2)

    def test_dead_metal_fails(self):
        b = make_build(self.root)
        write_json(os.path.join(b, "log", "extract_vco.json"),
                   {"nets": [{"name": "A"}], "dead_metal": [{"x": 1}]})
        out = os.path.join(self.root, "m.json")
        self.assertEqual(run_main(b, out), 1)

    def test_outline_match_records_expected_and_measured(self):
        b = make_build(self.root)
        out = os.path.join(self.root, "m.json")
        self.assertEqual(run_main(b, out), 0)
        with open(out) as fh:
            check = [c for c in json.load(fh)["acceptance_checks"]
                     if c.get("check", "").startswith("artifact bbox")][0]
        self.assertTrue(check["pass"])
        self.assertEqual(check["expected"], manifest.EXPECTED_BBOX_UM)
        self.assertEqual(check["measured"], manifest.EXPECTED_BBOX_UM)

    def test_outline_one_edge_drift_fails(self):
        # one database unit (0.001 um on the committed stream) off on a
        # single edge must fail the check and name both bound sets
        for edge, delta in (("x0", -0.001), ("y0", -0.001),
                            ("x1", 0.001), ("y1", 0.001)):
            bad = copy.deepcopy(VERIFY)
            bad["bbox_um"][edge] += delta
            b = make_build(self.root, bad)
            out = os.path.join(self.root, "m.json")
            self.assertEqual(run_main(b, out), 1, edge)
            with open(out) as fh:
                failed = [c for c in json.load(fh)["acceptance_checks"]
                          if not c["pass"]]
            self.assertEqual(len(failed), 1, edge)
            self.assertTrue(failed[0]["check"].startswith("artifact bbox"),
                            edge)
            self.assertEqual(failed[0]["expected"], manifest.EXPECTED_BBOX_UM)
            self.assertEqual(failed[0]["measured"], bad["bbox_um"])

    def test_missing_required_input_raises(self):
        b = make_build(self.root)
        os.remove(os.path.join(b, "verify.json"))
        with self.assertRaises(FileNotFoundError):
            run_main(b, os.path.join(self.root, "m.json"))


if __name__ == "__main__":
    unittest.main()
