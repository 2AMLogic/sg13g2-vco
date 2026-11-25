"""Known-answer tests for layout/scripts/manifest.py (stdlib unittest only).

manifest.py has a main guard, so it is imported by path; main() is driven with
a synthetic build directory. Nothing here needs klayout, klt or the PDK.
"""
import contextlib
import copy
import io
import json
import os
import re
import tempfile
import unittest

from _loader import ROOT, load_module

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


# PROVENANCE.md states the artifact outline in prose as
# "(x ±305.13, y −106.03…290.26)": ± is U+00B1, − is U+2212 and … is
# U+2026, so a plain-ASCII pattern cannot match it.  The pattern is
# anchored to the full prose form so a reformat that drops or reshapes it
# matches nothing and fails loudly instead of passing vacuously.
OUTLINE_RE = re.compile(
    r"\(x ±(?P<x>\d+(?:\.\d+)?), "
    r"y −(?P<y0>\d+(?:\.\d+)?)…(?P<y1>\d+(?:\.\d+)?)\)")


def provenance_sections():
    """PROVENANCE.md split at its `## N.` headers -> {number: text}."""
    with open(os.path.join(ROOT, "layout", "PROVENANCE.md"),
              encoding="utf-8") as fh:
        text = fh.read()
    sections = {}
    header = re.compile(r"^## (\d+)\.")
    current, buf = None, []
    for line in text.splitlines(keepends=True):
        m = header.match(line)
        if m:
            if current is not None:
                sections[current] = "".join(buf)
            current, buf = int(m.group(1)), [line]
        elif current is not None:
            buf.append(line)
    if current is not None:
        sections[current] = "".join(buf)
    return sections


def provenance_outlines(text):
    """Every "(x ±A, y −B…C)" outline in one section, as four-key dicts."""
    return [{"x0": -float(m.group("x")), "y0": -float(m.group("y0")),
             "x1": float(m.group("x")), "y1": float(m.group("y1"))}
            for m in OUTLINE_RE.finditer(text)]


def assert_section_outline(text, number, bbox):
    """One section's outline statements must all equal the transcription."""
    found = provenance_outlines(text)
    if not found:
        raise AssertionError(
            "PROVENANCE section %d states no outline of the form "
            "(x ±A, y −B…C); it was reformatted?" % number)
    for outline in found:
        if outline != bbox:
            raise AssertionError(
                "PROVENANCE section %d states %r but the transcribed "
                "bbox is %r" % (number, outline, bbox))


def assert_outline_agrees(section_numbers, bbox):
    """The §15/§17 drift gate (issue #445): EXPECTED_BBOX_UM is a
    hand transcription of PROVENANCE's prose outline, so every outline
    statement in each named section must match it."""
    sections = provenance_sections()
    for n in section_numbers:
        if n not in sections:
            raise AssertionError("PROVENANCE.md has no section %d" % n)
        assert_section_outline(sections[n], n, bbox)


def assert_every_outline_agrees(bbox, sections=None):
    """Issue #456: every section that restates the outline (section 18
    today, any later one) must agree with the transcription.  Sections
    with no outline statement are skipped; the 15/17 gate remains the
    authority and fails on a reformat."""
    if sections is None:
        sections = provenance_sections()
    for n in sorted(sections):
        if provenance_outlines(sections[n]):
            assert_section_outline(sections[n], n, bbox)


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

    def test_failed_check_prints_expected_and_measured(self):
        # a failed check must print both bound sets under its name; the
        # drifted edge (y1) is readable straight off the terminal
        bad = copy.deepcopy(VERIFY)
        bad["bbox_um"]["y1"] += 0.001
        b = make_build(self.root, bad)
        out = os.path.join(self.root, "m.json")
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout), \
                contextlib.redirect_stderr(io.StringIO()):
            rc = _run_main(b, out)
        self.assertEqual(rc, 1)
        lines = stdout.getvalue().splitlines()
        fail_ix = [i for i, line in enumerate(lines) if "FAIL" in line]
        self.assertEqual(len(fail_ix), 1)
        i = fail_ix[0]
        self.assertIn("artifact bbox", lines[i])
        self.assertEqual(lines[i + 1],
                         "    expected: %r" % manifest.EXPECTED_BBOX_UM)
        self.assertEqual(lines[i + 2],
                         "    measured: %r" % bad["bbox_um"])
        # passing checks stay one line each: no indented detail follows [ok]
        for j, line in enumerate(lines):
            if "[ok]" in line and j + 1 < len(lines):
                self.assertFalse(lines[j + 1].startswith("    "), line)

    def test_missing_required_input_raises(self):
        b = make_build(self.root)
        os.remove(os.path.join(b, "verify.json"))
        with self.assertRaises(FileNotFoundError):
            run_main(b, os.path.join(self.root, "m.json"))


class OutlineProvenanceTests(unittest.TestCase):
    """EXPECTED_BBOX_UM is a hand transcription of the prose outline in
    PROVENANCE sections 15 and 17 (the authority, checked individually),
    and every other section restating it must agree (issue #456); these
    tests fail the moment the constant and
    the record disagree (issue #445)."""

    def test_expected_bbox_transcribes_provenance_15_and_17(self):
        assert_outline_agrees((15, 17), manifest.EXPECTED_BBOX_UM)

    def test_one_edge_drift_in_expected_bbox_fails(self):
        # mutation case: mutate one edge of the transcription at a time
        # and require the agreement check to fire for every one of them
        for edge, delta in (("x0", -0.001), ("y0", -0.001),
                            ("x1", 0.001), ("y1", 0.001)):
            mutant = dict(manifest.EXPECTED_BBOX_UM)
            mutant[edge] += delta
            with self.assertRaises(AssertionError, msg=edge):
                assert_outline_agrees((15, 17), mutant)

    def test_reformatted_section_fails_not_passes_vacuously(self):
        # a section whose outline no longer matches the prose form must
        # fail the gate, not let it pass by finding nothing to compare
        mangled = OUTLINE_RE.sub("", provenance_sections()[15])
        self.assertEqual(provenance_outlines(mangled), [])
        with self.assertRaises(AssertionError):
            assert_section_outline(mangled, 15, manifest.EXPECTED_BBOX_UM)

    def test_every_section_restating_outline_agrees(self):
        assert_every_outline_agrees(manifest.EXPECTED_BBOX_UM)
        # section 18 restates the outline today, so it is covered
        self.assertTrue(provenance_outlines(provenance_sections()[18]))

    def test_stale_section_18_alone_fails_naming_it(self):
        sections = dict(provenance_sections())
        sections[18] = sections[18].replace("y −106.03", "y −106.04")
        self.assertNotEqual(sections[18], provenance_sections()[18])
        assert_outline_agrees((15, 17), manifest.EXPECTED_BBOX_UM)
        with self.assertRaisesRegex(AssertionError, "section 18"):
            assert_every_outline_agrees(manifest.EXPECTED_BBOX_UM, sections)

    def test_every_section_check_covers_later_sections_and_skips_empty(self):
        good = "(x ±305.13, y −106.03…290.26) and again (x ±305.13, y −106.03…290.26)"
        bad = "(x ±305.13, y −106.03…290.27)"
        bbox = manifest.EXPECTED_BBOX_UM
        assert_every_outline_agrees(bbox, {1: "no outline here", 19: good})
        with self.assertRaisesRegex(AssertionError, "section 19"):
            assert_every_outline_agrees(bbox, {1: "none", 19: good + bad})

    def test_missing_section_fails(self):
        with self.assertRaises(AssertionError):
            assert_outline_agrees((15, 99), manifest.EXPECTED_BBOX_UM)


if __name__ == "__main__":
    unittest.main()
