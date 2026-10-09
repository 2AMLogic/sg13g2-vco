"""Known-answer tests for sim/tank-screen/tank_screen.py.

The script is run as a `python3 -I` subprocess. The expected values are read
here straight from the committed A/B record (independently of the script's own
loader) and compared within stated tolerances. Output goes to a temp dir only.
"""
import csv
import json
import os
import tempfile
import unittest

from _loader import ROOT, run_script

SCREEN = "sim/tank-screen/tank_screen.py"
AB = os.path.join(ROOT, "sim/bn-substrate-tank/records/20261009-002323-383f22e/"
                  "tank-ab-tuning.csv")

# Stated tolerances: the lumped model is checked against the record's own
# ngspice AC result. Observed forward error is ~0.33 %; allow 0.5 %.
F0_TOL_PCT = 0.5
DF0_TOL_PCT_POINTS = 0.5      # observed 0.25 points
DRATIO_TOL = 0.005            # observed 0.0003


def record(variant):
    with open(AB) as fh:
        for r in csv.DictReader(fh):
            if (r["variant"], r["mim"], r["temp_c"]) == (variant, "cap_typ", "27"):
                return (float(r["f0_vctrl0_ghz"]), float(r["f0_vctrl3p3_ghz"]))
    raise KeyError(variant)


class SelfcheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        proc = run_script(SCREEN, "--selfcheck")
        assert proc.returncode == 0, proc.stderr
        cls.sc = json.loads(proc.stdout)

    def test_labelled_and_method_stated(self):
        self.assertIn("NOT EVIDENCE", self.sc["label"])
        for s in ("lumped LC", "no HBT pair loading"):
            self.assertIn(s, self.sc["method"])

    def test_forward_f0_reproduces_bn_tank_record(self):
        for got, exp in zip(self.sc["bn_tank_forward_f0_ghz"], record("bn-tank")):
            self.assertAlmostEqual(got / exp, 1.0, delta=F0_TOL_PCT / 100)

    def test_bn_sub_endpoints_reproduced(self):
        for got, exp in zip(self.sc["bn_sub_model_f0_ghz"], record("bn-sub")):
            self.assertAlmostEqual(got, exp, delta=1e-6)

    def test_deltas_match_record(self):
        t, s = record("bn-tank"), record("bn-sub")
        rec_df0 = [100 * (a / b - 1) for a, b in zip(s, t)]
        for got, exp in zip(self.sc["df0_pct_model"], rec_df0):
            self.assertAlmostEqual(got, exp, delta=DF0_TOL_PCT_POINTS)
        rec_dr = s[0] / s[1] - t[0] / t[1]
        self.assertAlmostEqual(self.sc["dratio_model"], rec_dr, delta=DRATIO_TOL)
        # the headline record numbers: ratio 1.18 -> 1.11
        self.assertAlmostEqual(self.sc["ratio_model_tank"], 1.18, delta=0.01)
        self.assertAlmostEqual(self.sc["ratio_model_sub"], 1.11, delta=0.01)


class OutputTests(unittest.TestCase):
    def test_table_written_and_ranked(self):
        with tempfile.TemporaryDirectory() as out:
            proc = run_script(SCREEN, "--out", out)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertIn("NOT EVIDENCE", proc.stdout)
            with open(os.path.join(out, "tank-screen.csv")) as fh:
                rows = list(csv.DictReader(fh))
            self.assertGreater(len(rows), 100)
            scores = [float(r["score"]) for r in rows]
            self.assertEqual(scores, sorted(scores, reverse=True))
            with open(os.path.join(out, "tank-screen.md")) as fh:
                md = fh.read()
            self.assertIn("NOT EVIDENCE", md)
            self.assertIn("no HBT", md)

    def test_refuses_graded_paths(self):
        for sub in ("sim/tank-screen/out", "sim/foo/records/x"):
            proc = run_script(SCREEN, "--out", os.path.join(ROOT, sub))
            self.assertNotEqual(proc.returncode, 0)
            self.assertFalse(os.path.exists(os.path.join(ROOT, sub)))


if __name__ == "__main__":
    unittest.main()
