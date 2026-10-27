"""Drift tests for signoff/characterization.py (issue #261; stdlib unittest only).

Each case runs in a throwaway fixture tree (a three-row spec, a row map, a
currency index and one CSV), never the real tree: a drift gate that cannot
fail is indistinguishable from no gate. One case also checks the real tree.
"""
import json
import os
import tempfile
import unittest

from _loader import ROOT, load_module

ch = load_module("signoff_characterization", "signoff/characterization.py")

SPEC = """| # | Parameter | Min | Typ | Max | Corner / condition | Status |
|---|---|---|---|---|---|---|
| 0 | Supply | 2.97 V | 3.30 V | 3.63 V | rail | **RATIFIED (target)** |
| 1 | Margin | ≥ 3.0 | | | every corner | **RATIFIED (target)** |
| 2 | Power | | | ≤ 10 mW | nominal | **RATIFIED (target)** |
"""
REC1 = "sim/x/records/20260101-000000-abc1234.md"
REC2 = "sim/x/records/20260101-000001-abc1234.md"
CSV1 = "sim/x/records/20260101-000000-abc1234.csv"


def load(*parts):
    with open(os.path.join(*parts)) as f:
        return json.load(f)


def write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def fixture(root, state1="current", state2="current", margin="4.2"):
    write(root, "spec/target-spec.md", SPEC)
    write(root, "design/vco.spice", "* netlist\n")
    for rec in (REC1, REC2):
        write(root, rec, "record\n")
    write(root, CSV1, f"corner,margin\ntt,{margin}\nss,9.9\n")
    write(root, "sim/record-currency.json", json.dumps({"records": [
        {"path": REC1, "record_id": "20260101-000000-abc1234", "state": state1},
        {"path": REC2, "record_id": "20260101-000001-abc1234", "state": state2},
    ]}))
    write(root, "signoff/characterization-rows.json", json.dumps({"rows": [
        {"row": 0, "kind": "condition", "records": [], "evidence": ["design/vco.spice"]},
        {"row": 1, "kind": "graded", "records": [REC1], "blocked_by": [50], "grade": {
            "record": REC1, "csv": CSV1, "column": "margin", "aggregate": "min",
            "op": ">=", "limit": 3.0, "corner_columns": ["corner"]}},
        {"row": 2, "kind": "graded", "records": [REC2], "blocked_by": [50]},
    ]}))
    write(root, "signoff/manifest.json", json.dumps({"block": "b", "kind": "analog", "evidence": {}}))
    os.makedirs(os.path.join(root, "signoff/evidence"), exist_ok=True)


class CharacterizationDrift(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name
        fixture(self.root)
        self.path = ch.Path(self.root)
        ch.regen(self.path)

    def verify(self):
        return ch.verify(self.path)

    def report(self):
        with open(os.path.join(self.root, ch.REPORT)) as f:
            return f.read()

    def test_real_tree_is_current(self):
        self.assertEqual(ch.verify(ch.Path(ROOT)), [])

    def test_real_tree_has_every_spec_row(self):
        with open(os.path.join(ROOT, ch.REPORT)) as f:
            text = f.read()
        for n in range(12):
            self.assertIn(f"\n| {n} |", text)

    def test_clean_fixture_passes_and_pending_row_names_blocker(self):
        self.assertEqual(self.verify(), [])
        self.assertIn("pending: no graded record yet; owed by #50", self.report())

    def test_current_failing_row_is_fail_and_envelope_fail(self):
        fixture(self.root, margin="2.0")
        ch.regen(self.path)
        self.assertIn("fail", self.report().split("\n| 1 |")[1].split("\n")[0])
        env = load(self.root, ch.ENVELOPE)
        self.assertEqual(env["status"], "fail")

    def test_envelope_passes_only_when_every_graded_row_passes(self):
        env = lambda: load(self.root, ch.ENVELOPE)["status"]
        self.assertEqual(env(), "fail")  # row 2 has no grade -> pending
        write(self.root, "signoff/characterization-rows.json", json.dumps({"rows": [
            {"row": 0, "kind": "condition", "records": []},
            {"row": 1, "kind": "graded", "records": [REC1], "grade": {
                "record": REC1, "csv": CSV1, "column": "margin", "aggregate": "min",
                "op": ">=", "limit": 3.0}},
            {"row": 2, "kind": "condition", "records": []},
        ]}))
        ch.regen(self.path)
        self.assertEqual(env(), "pass")
        self.assertEqual(self.verify(), [])

    def test_record_state_flip_makes_row_pending_and_fails_check(self):
        fixture(self.root, state1="superseded")
        errs = self.verify()
        self.assertTrue(any(e.startswith("row 1:") for e in errs), errs)
        ch.regen(self.path)
        self.assertIn("pending: record 20260101-000000-abc1234 is superseded", self.report())

    def test_changed_measured_value_names_row(self):
        fixture(self.root, margin="3.5")
        self.assertTrue(any(e.startswith("row 1:") for e in self.verify()))

    def test_changed_spec_target_names_row(self):
        write(self.root, "spec/target-spec.md", SPEC.replace("≤ 10 mW", "≤ 8 mW"))
        self.assertTrue(any(e.startswith("row 2:") for e in self.verify()))

    def test_spec_row_without_map_entry_fails(self):
        write(self.root, "spec/target-spec.md", SPEC + "| 3 | New | 1 | | | c | **RATIFIED (target)** |\n")
        self.assertTrue(any("spec rows with no entry" in e for e in self.verify()))

    def test_map_row_the_spec_lacks_fails(self):
        write(self.root, "spec/target-spec.md", "\n".join(SPEC.splitlines()[:-1]) + "\n")
        self.assertTrue(any("cites rows the spec lacks" in e for e in self.verify()))

    def test_hand_edited_report_fails(self):
        with open(os.path.join(self.root, ch.REPORT), "a") as f:
            f.write("hand edit\n")
        self.assertTrue(self.verify())

    def test_stale_manifest_pin_fails(self):
        m = os.path.join(self.root, ch.MANIFEST)
        d = load(m)
        d["evidence"]["8"]["content_hash"] = "sha256:0"
        with open(m, "w") as f:
            json.dump(d, f)
        self.assertTrue(any("manifest" in e for e in self.verify()))


if __name__ == "__main__":
    unittest.main()
