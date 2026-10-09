"""Known-answer tests for sim/bn-substrate-tank/{make_requests,analyze}.py.

Both scripts run all their work at import time (no main guard), so they are
exercised as subprocesses in isolated mode (python3 -I), never imported.
The tests only read the committed inputs and write under a temp dir; they do
not touch sim/ results.
"""
import csv
import json
import math
import os
import tempfile
import unittest

from _loader import ROOT, run_script

MAKE = "sim/bn-substrate-tank/make_requests.py"
ANALYZE = "sim/bn-substrate-tank/analyze.py"


def read_json(*parts):
    with open(os.path.join(*parts)) as fh:
        return json.load(fh)


class MakeRequestsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.out = cls._tmp.name
        cls.proc = run_script(MAKE, cls.out)

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_exits_clean(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stderr)
        self.assertIn("ok " + self.out, self.proc.stdout)

    def test_variant_and_point_inventory(self):
        self.assertEqual(
            sorted(os.listdir(self.out)),
            ["bn-sub", "bn-sub-tnom125", "bn-sub-tnom85", "bn-tank"])
        for v, n in (("bn-tank", 5), ("bn-sub", 5), ("bn-sub-tnom125", 5),
                     ("bn-sub-tnom85", 1)):
            self.assertEqual(len(os.listdir(os.path.join(self.out, v))), n, v)
        self.assertEqual(
            sorted(os.listdir(os.path.join(self.out, "bn-tank"))),
            ["ff_v1.5", "ss_v1.5", "tt_v0.0", "tt_v1.5", "tt_v3.3"])

    def test_cell_values_known_answer(self):
        # Values are the committed varactor record rows (mos small, 27 C),
        # selected through V_rec = 3.3 - Vctrl (see make_requests.py).
        for vc, c, q in ((1.5, 5.63033e-15, 83.9788),    # V_rec 1.8
                         (0.0, 5.56899e-15, 84.9210),    # V_rec 3.3
                         (3.3, 1.04522e-14, 44.7882)):   # V_rec 0.0
            cell = read_json(self.out, "bn-tank", "tt_v%s" % vc, "cell.json")
            self.assertEqual(cell["c_cell_f"], c)
            self.assertEqual(cell["q5"], q)
            self.assertAlmostEqual(cell["r_cell_ohm"],
                                   1.0 / (2 * math.pi * 5e9 * c * q), delta=1e-9)

    def test_bn_connection_is_the_only_variable(self):
        def deck(v):
            with open(os.path.join(self.out, v, "tt_v1.5", "tank.spice")) as fh:
                return fh.read()
        tank, sub = deck("bn-tank"), deck("bn-sub")
        self.assertIn("XCVP1 VCTRL OUTP OUTP svar", tank)
        self.assertIn("XCVN16 VCTRL OUTN OUTN svar", tank)
        self.assertIn("XCVP1 VCTRL OUTP 0 svar", sub)
        self.assertIn("XCVN16 VCTRL OUTN 0 svar", sub)
        self.assertEqual(tank.count("\nXCV"), 32)
        self.assertEqual(sub.count("\nXCV"), 32)
        self.assertNotIn("tnom", tank)

    def test_tnom_workaround_variants(self):
        with open(os.path.join(self.out, "bn-sub-tnom125", "tt_v1.5", "tank.spice")) as fh:
            self.assertIn("tnom = 125", fh.read())
        req = read_json(self.out, "bn-sub-tnom85", "tt_v1.5", "request.json")
        self.assertEqual(req["corners"]["temperature_c"], [85])
        req = read_json(self.out, "bn-sub-tnom125", "ss_v1.5", "request.json")
        self.assertEqual(req["corners"]["temperature_c"], [125])

    def test_request_shape(self):
        req = read_json(self.out, "bn-tank", "tt_v1.5", "request.json")
        self.assertEqual(req["engine"], "ngspice")
        self.assertEqual(req["netlist"], "tank.spice")
        self.assertEqual(req["corners"]["temperature_c"], [-40, 27, 125])
        self.assertEqual([c["name"] for c in req["corners"]["process"]],
                         ["cap_typ", "cap_bcs", "cap_wcs"])
        self.assertEqual([m["name"] for m in req["measurements"]],
                         ["zpk", "f0", "f_p45", "f_m45"])

    def test_missing_outdir_argument_fails(self):
        p = run_script(MAKE)
        self.assertNotEqual(p.returncode, 0)


class CandidateSizingTests(unittest.TestCase):
    """Issue #93: explicit sizing, baseline defaults preserved, bn always 0."""

    def _gen(self, *extra):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        p = run_script(MAKE, tmp.name, *extra)
        return tmp.name, p

    def test_candidate_sizing(self):
        out, p = self._gen("--cells", "14", "--mim-um", "1.14", "--candidate", "c14")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(os.listdir(out), ["c14"])
        with open(os.path.join(out, "c14", "tt_v1.5", "tank.spice")) as fh:
            deck = fh.read()
        self.assertIn("cap_cmim w=1.14e-6 l=1.14e-6", deck)
        self.assertEqual(deck.count("\nXCVP"), 14)
        self.assertEqual(deck.count("\nXCVN"), 14)
        # every varactor cell's bn is the substrate
        for ln in deck.splitlines():
            if ln.startswith("XCV"):
                self.assertTrue(ln.endswith(" 0 svar"), ln)
        cell = read_json(out, "c14", "tt_v1.5", "cell.json")
        self.assertEqual((cell["cells_per_side"], cell["mim_side_um"]), (14, 1.14))

    def test_defaults_unchanged(self):
        out, p = self._gen()
        with open(os.path.join(out, "bn-sub", "tt_v1.5", "tank.spice")) as fh:
            deck = fh.read()
        self.assertIn("cap_cmim w=3.65e-6 l=3.65e-6", deck)
        self.assertEqual(deck.count("\nXCV"), 32)

    def test_illegal_or_unnamed_sizing_rejected(self):
        self.assertNotEqual(self._gen("--cells", "14")[1].returncode, 0)
        self.assertNotEqual(self._gen("--mim-um", "1.0", "--candidate", "x")[1].returncode, 0)
        self.assertNotEqual(self._gen("--candidate", "a__b")[1].returncode, 0)


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        json.dump(obj, fh)


def report(f0, fp45, fm45, zpk, process="cap_typ", temp=27, status="pass"):
    ms = [{"name": "f0", "value": f0}, {"name": "f_p45", "value": fp45},
          {"name": "f_m45", "value": fm45}, {"name": "zpk", "value": zpk}]
    return {"corners": [{"process": process, "temperature_c": temp,
                         "status": status, "measurements": ms}],
            "environment": {"remote": {"job_id": "job-1"}}}


def add_point(rec, variant, mos, vctrl, rpt):
    name = "%s__%s_v%s" % (variant, mos, vctrl)
    write_json(os.path.join(rec, "reports", name + ".json"), rpt)
    write_json(os.path.join(rec, "decks", name + ".cell.json"),
               {"mos": mos, "vctrl": vctrl})


def read_csv(path):
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh))


class AnalyzeTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.rec = self._tmp.name

    def _populate(self):
        # Q = f0 / (f_m45 - f_p45): 5e9 / (5.5e9 - 4.5e9) = 5.0 ; new: 6.0
        for vc, f0 in ((0.0, 6e9), (3.3, 4e9)):
            add_point(self.rec, "bn-tank", "tt", vc,
                      report(f0, f0 - 0.5e9, f0 + 0.5e9, 100.0))
            add_point(self.rec, "bn-sub", "tt", vc,
                      report(f0 * 1.1, f0 * 1.1 - 0.5e9, f0 * 1.1 + 0.5e9, 150.0))

    def test_known_answer_outputs(self):
        self._populate()
        p = run_script(ANALYZE, self.rec)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("4 rows; 2 paired deltas", p.stdout)

        rows = read_csv(os.path.join(self.rec, "tank-ab.csv"))
        self.assertEqual(len(rows), 4)
        base = [r for r in rows if r["variant"] == "bn-tank" and r["vctrl_v"] == "0.0"][0]
        self.assertEqual(base["status"], "ok")
        self.assertEqual(base["f0_ghz"], "6.0")
        self.assertEqual(base["q_phase45"], "6.0")   # 6e9 / 1e9
        self.assertEqual(base["job"], "job-1")

        delta = read_csv(os.path.join(self.rec, "tank-ab-delta.csv"))
        self.assertEqual(len(delta), 2)
        d0 = [r for r in delta if r["vctrl_v"] == "0.0"][0]
        self.assertEqual(d0["df0_pct"], "10.0")
        self.assertEqual(d0["zpk_ratio"], "1.5")
        self.assertEqual(d0["q_old"], "6.0")
        self.assertEqual(d0["q_new"], "6.6")         # 6.6e9 / 1e9
        self.assertEqual(d0["dq_pct"], "10.0")

        tun = read_csv(os.path.join(self.rec, "tank-ab-tuning.csv"))
        self.assertEqual(len(tun), 2)                # bn-tank and bn-sub
        t = [r for r in tun if r["variant"] == "bn-tank"][0]
        self.assertEqual(t["f0_vctrl0_ghz"], "6.0")
        self.assertEqual(t["f0_vctrl3p3_ghz"], "4.0")
        self.assertEqual(t["fmax_over_fmin"], "1.5")

    def test_failed_corner_is_flagged_not_dropped(self):
        self._populate()
        bad = report(5e9, 4.5e9, 5.5e9, 100.0, status="fail")
        add_point(self.rec, "bn-sub", "ss", 1.5, bad)
        p = run_script(ANALYZE, self.rec)
        self.assertEqual(p.returncode, 0, p.stderr)
        rows = read_csv(os.path.join(self.rec, "tank-ab.csv"))
        flagged = [r for r in rows if r["mos"] == "ss"]
        self.assertEqual(len(flagged), 1)
        self.assertTrue(flagged[0]["status"].startswith("NO-VALUE"))
        self.assertEqual(flagged[0]["f0_ghz"], "")

    def test_unparseable_report_is_no_report(self):
        self._populate()
        os.makedirs(os.path.join(self.rec, "reports"), exist_ok=True)
        with open(os.path.join(self.rec, "reports", "bn-sub__tt_v1.5.json"), "w") as fh:
            fh.write("{ not json")
        p = run_script(ANALYZE, self.rec)
        self.assertEqual(p.returncode, 0, p.stderr)
        rows = read_csv(os.path.join(self.rec, "tank-ab.csv"))
        self.assertIn("NO-REPORT", [r["status"] for r in rows])

    def test_no_arguments_fails(self):
        self.assertNotEqual(run_script(ANALYZE).returncode, 0)


if __name__ == "__main__":
    unittest.main()
