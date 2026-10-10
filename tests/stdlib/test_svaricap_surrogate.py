"""Known-answer tests for sim/tools/svaricap_surrogate.py (issue #179). No simulator.

SCREENING ONLY -- the surrogate grades no specification row.
"""
import math
import os
import re
import shutil
import subprocess
import tempfile
import unittest

from _loader import ROOT, load_module

sur = load_module("svaricap_surrogate", "sim/tools/svaricap_surrogate.py")
CSV = os.path.join(ROOT, sur.DEFAULT_CSV)
HDR = ("device_class,device_key,corner_label,temp_c,vctrl_v,status,srf_hz,c_1ghz_f,"
       "c_5ghz_f,c_10ghz_f,c_20ghz_f,q_1ghz,q_5ghz,q_10ghz,q_20ghz\n")


def row(v, c, q, cls="mos", key="small", corner="tt", temp=27, status="PASS"):
    return "%s,%s,%s,%s,%s,%s,none,0,%s,0,0,0,%s,0,0\n" % (cls, key, corner, temp, v, status, c, q)


def write_csv(rows):
    fd, path = tempfile.mkstemp(suffix=".csv")
    with os.fdopen(fd, "w") as fh:
        fh.write(HDR + "".join(rows))
    return path


GOOD = [(0.0, 10e-15, 40), (1.0, 8e-15, 55), (2.0, 6e-15, 80), (3.3, 5.5e-15, 85)]


def good_rows(**kw):
    return [row(v, c, q, **kw) for v, c, q in GOOD]


class Parsing(unittest.TestCase):
    def reject(self, rows, pat):
        p = write_csv(rows)
        self.addCleanup(os.unlink, p)
        with self.assertRaisesRegex(sur.SurrogateError, pat):
            sur.load_series(p)

    def test_selects_only_mos_small_and_separates_corner_temp(self):
        rows = good_rows() + good_rows(corner="ss", temp=-40) + [row(0.0, 1e-12, 1, key="mid"),
                                                                 row(0.0, 1e-12, 1, cls="hbt")]
        p = write_csv(rows)
        self.addCleanup(os.unlink, p)
        s = sur.load_series(p)
        self.assertEqual(sorted(s), [("ss", -40.0), ("tt", 27.0)])
        self.assertEqual(s[("tt", 27.0)].cs, [c for _, c, _ in GOOD])

    def test_committed_record_every_corner_temperature(self):
        s = sur.load_series(CSV)
        self.assertEqual(len(s), 15)  # 5 MOS corners x 3 temperatures
        self.assertEqual({k[0] for k in s}, {"tt", "ss", "ff", "sf", "fs"})
        self.assertEqual({k[1] for k in s}, {-40.0, 27.0, 125.0})
        for ser in s.values():
            self.assertEqual((ser.vs[0], ser.vs[-1]), (0.0, 3.3))

    def test_rejections(self):
        self.reject([row(v, c, q) for v, c, q in GOOD[:2]], "need >= 3")
        self.reject(good_rows() + [row(2.0, 6e-15, 80)], "duplicate|unsorted")
        self.reject([row(v, c, q) for v, c, q in [GOOD[0], GOOD[2], GOOD[1], GOOD[3]]], "unsorted")
        self.reject([row(0.0, "nan", 40)] + good_rows()[1:], "non-finite")
        self.reject([row(0.0, 10e-15, "inf")] + good_rows()[1:], "non-finite")
        self.reject([row(0.0, -1e-15, 40)] + good_rows()[1:], "non-positive")
        self.reject([row(0.0, 1e-15, 0)] + good_rows()[1:], "non-positive")
        self.reject([row(0.0, 10e-15, 40, status="FAIL")] + good_rows()[1:], "not PASS")
        self.reject(good_rows()[:-1] + [row(3.0, 5e-15, 85)], "spans")
        self.reject([row(0.0, 1e-12, 1, key="mid")], "no mos/small")

    def test_missing_column(self):
        fd, p = tempfile.mkstemp(suffix=".csv")
        with os.fdopen(fd, "w") as fh:
            fh.write("device_class,device_key\nmos,small\n")
        self.addCleanup(os.unlink, p)
        with self.assertRaisesRegex(sur.SurrogateError, "missing columns"):
            sur.load_series(p)


class Charge(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.series = sur.load_series(CSV)

    def test_knots_reproduce_source_values_exactly(self):
        rows = {}
        import csv
        with open(CSV) as fh:
            for r in csv.DictReader(fh):
                if r["device_class"] == "mos" and r["device_key"] == "small":
                    rows[(r["corner_label"], float(r["temp_c"]), float(r["vctrl_v"]))] = (
                        float(r["c_5ghz_f"]), float(r["q_5ghz"]))
        self.assertEqual(len(rows), 135)
        for (corner, t, v), (c, q) in rows.items():
            s = self.series[(corner, t)]
            self.assertAlmostEqual(s.c_at(v) / c, 1.0, places=12)
            r = 1.0 / (2 * math.pi * 5e9 * c * q)
            self.assertAlmostEqual(s.r_at(v) / r, 1.0, places=12)

    def test_positive_everywhere(self):
        for s in self.series.values():
            for i in range(0, 331):
                v = i / 100.0
                self.assertGreater(s.c_at(v), 0)
                self.assertGreater(s.r_at(v), 0)

    def test_q_zero_at_origin_and_monotone_with_correct_sign(self):
        for s in self.series.values():
            self.assertEqual(s.q_gw(0.0), 0.0)
            # v_gw < 0 (v_rec > 0): negative gate charge; strictly increasing in v_gw
            prev = None
            for i in range(-330, 1, 5):
                q = s.q_gw(i / 100.0)
                if i < 0:
                    self.assertLess(q, 0)
                if prev is not None:
                    self.assertGreater(q, prev)
                prev = q

    def test_q_and_c_continuous_across_every_knot(self):
        eps = 1e-9
        for s in self.series.values():
            for v in s.vs:
                lo, hi = s.qint(v - eps), s.qint(v + eps)
                self.assertLess(abs(hi - lo), 2 * eps * max(s.cs) * 1.0001)
                if V_IN(v):
                    self.assertAlmostEqual(s.c_at(v - eps) / s.c_at(v + eps), 1.0, places=6)

    def test_dqdv_matches_fitted_c_at_knots_and_midpoints_under_declared_tolerance(self):
        h = 1e-6
        for s in self.series.values():
            tol = s.tolerances()["tol_dqdv"]
            pts = list(s.vs) + [(a + b) / 2 for a, b in zip(s.vs, s.vs[1:])]
            for v_rec in pts:
                v_gw = -v_rec
                # central difference, shrunk at the domain edge to stay inside
                hh = min(h, v_rec - 0.0 if v_rec > 0 else h, 3.3 - v_rec if v_rec < 3.3 else h)
                hh = hh if hh > 0 else h
                num = (s.q_gw(v_gw + hh) - s.q_gw(v_gw - hh)) / (2 * hh)
                self.assertLessEqual(abs(num - s.c_at(v_rec)) / s.c_at(v_rec), tol,
                                     "%s v_rec=%g" % (s.key, v_rec))

    def test_tolerance_formulas(self):
        s = sur.Series("tt", 27, [(0.0, 10e-15, 40), (1.1, 8e-15, 55), (3.3, 5e-15, 85)])
        eC, eR = s.loo()
        t = (1.1 - 0.0) / 3.3
        pred_c = 10e-15 + t * (5e-15 - 10e-15)
        self.assertAlmostEqual(eC, abs(pred_c - 8e-15) / 8e-15, places=12)
        tol = s.tolerances()
        self.assertEqual(tol["tol_dqdv"], max(1e-3, 1.25 * eC))
        self.assertEqual(tol["tol_R"], max(1e-3, 1.25 * eR))
        # a perfectly linear series falls back to the 0.1 % floor
        lin = sur.Series("x", 0, [(0.0, 1e-15, 10), (1.65, 2e-15, 10), (3.3, 3e-15, 10)])
        self.assertEqual(lin.tolerances()["tol_dqdv"], 1e-3)
        kt = sur.known_answer_tolerances(0.1, 0.02, 0.08)
        self.assertAlmostEqual(kt["tol_freq"], max(0.01, 0.05 + 0.0008))
        self.assertAlmostEqual(kt["tol_amp"], max(0.05, 0.12))
        kt = sur.known_answer_tolerances(0.001, 0.001, 0.08)
        self.assertEqual((kt["tol_freq"], kt["tol_amp"]), (0.01, 0.05))


def V_IN(v):
    return 0.0 < v < 3.3


class Polarity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = sur.load_series(CSV)[("tt", 27.0)]

    def test_csv_axis_is_v_rec_not_reversed(self):
        # csv: vctrl_v = 0.0 -> 10.45 fF (largest C), 3.3 -> 5.57 fF
        self.assertAlmostEqual(self.s.c_at(0.0), 1.04522e-14, delta=1e-19)
        self.assertAlmostEqual(self.s.c_at(3.3), 5.56899e-15, delta=1e-20)

    def test_v_rec_is_well_minus_gate(self):
        # V(W)=3.3, V(G)=0  ->  v_rec = 3.3 -> small C (depletion end of the record)
        v_g, v_w = 0.0, 3.3
        v_gw = v_g - v_w
        self.assertAlmostEqual(self.s.c_at(-v_gw), 5.56899e-15, delta=1e-20)
        # V(W)=0, V(G)=0 -> v_rec = 0 -> large C
        self.assertAlmostEqual(self.s.c_at(-(0.0 - 0.0)), 1.04522e-14, delta=1e-19)

    def test_oscillator_dc_point_maps_to_3p3_minus_vctrl(self):
        for vctrl in (0.0, 1.65, 3.3):
            self.assertAlmostEqual(sur.vrec_from_vctrl_dc(vctrl), 3.3 - vctrl)
        # VCTRL = 0 (gate low, well 3.3) is the LOW-C end -> highest oscillator frequency
        self.assertLess(self.s.c_at(sur.vrec_from_vctrl_dc(0.0)),
                        self.s.c_at(sur.vrec_from_vctrl_dc(3.3)))

    def test_deliberately_reversed_mapping_fails(self):
        for vctrl in (0.0, 1.0, 3.3):
            right = self.s.c_at(3.3 - vctrl)
            reversed_ = self.s.c_at(vctrl)       # forgets that v_rec = 3.3 - VCTRL
            self.assertGreater(abs(reversed_ - right) / right, 0.01)
        # reversed CSV axis (v -> 3.3 - v) is also detected
        self.assertNotAlmostEqual(self.s.c_at(0.3), self.s.c_at(3.3 - 0.3), delta=1e-17)

    def test_generated_text_uses_well_minus_gate_orientation(self):
        txt = sur.render_subckt(self.s)
        self.assertIn("v(nc,G1)", txt)       # V(well side) - V(G)
        self.assertNotIn("v(G1,nc)", txt)
        self.assertRegex(txt, r"Ccore G1 nc q='-\(")  # q(v_gw) = -Qint(v_rec)


class Deck(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = sur.load_series(CSV)[("tt", 27.0)]
        cls.txt = sur.render_subckt(cls.s)
        with open(os.path.join(ROOT, "design/vco.spice")) as fh:
            cls.vco = fh.read()

    def test_four_terminals_same_as_pdk(self):
        self.assertIn(".subckt sg13_hv_svaricap_sur G1 W G2 bn", self.txt)

    def test_single_native_junction_branch(self):
        self.assertEqual(len(re.findall(r"^dsubw ", self.txt, re.M)), 1)
        self.assertEqual(len(re.findall(r"^rsubw ", self.txt, re.M)), 1)
        self.assertEqual(len(re.findall(r"^\.subckt ", self.txt, re.M)), 1)
        card = sur.render_model_card()
        self.assertEqual(card.count(".model dsubw "), 1)
        self.assertIn("vj = 0.3357", card)
        self.assertNotIn("vj = 0.1 ", card)

    def test_core_is_junction_free(self):
        core = [l for l in self.txt.splitlines() if l.startswith(("Rcore", "Ccore"))]
        self.assertEqual(len(core), 2)
        for l in core:
            for tok in ("dsubw", "rsubw", "cjo", "cjp", " bn"):
                self.assertNotIn(tok, l)
        # the fit uses only the 5 GHz C/Q of the tied-W/bn record: no junction C is added to it
        self.assertEqual(self.s.cs[0], 1.04522e-14)

    def test_series_resistance_expression_values_at_knots(self):
        # R at the first and last knots from the emitted constants
        txt = self.txt
        self.assertIn(("%.12g" % self.s.rs[0]), txt)
        self.assertIn(("%.12g" % self.s.rs[-2]), txt)

    def test_vco_rewrite_corrected_and_pre79(self):
        cor = sur.surrogate_vco_body(self.vco, "svs", "corrected")
        pre = sur.surrogate_vco_body(self.vco, "svs", "pre79")
        self.assertEqual(len(re.findall(r"^XCV\S+ VCTRL OUT[PN] VCTRL 0 svs w=3.74e-6 l=0.3e-6 Nx=1$", cor, re.M)), 32)
        self.assertEqual(len(re.findall(r"^XCV\S+ VCTRL (OUT[PN]) VCTRL \1 svs w=3.74e-6 l=0.3e-6 Nx=1$", pre, re.M)), 32)
        for body in (cor, pre):
            self.assertNotIn("sg13_hv_svaricap", body)
            self.assertNotIn(".save", body)
            self.assertNotIn("osdi", body.lower())
            self.assertNotIn(".control", body)
        self.assertIn("XQ1 OUTP OUTN TAIL 0 npn13G2v", cor)

    def test_vco_rewrite_refuses_unexpected_wiring(self):
        with self.assertRaisesRegex(sur.SurrogateError, "bn on 0"):
            sur.surrogate_vco_body(self.vco.replace("VCTRL 0 sg13_hv_svaricap", "VCTRL OUTP sg13_hv_svaricap", 1),
                                   "svs", "corrected")
        with self.assertRaisesRegex(sur.SurrogateError, "expected 32"):
            sur.surrogate_vco_body(self.vco.replace("XCVN16", "XQX16"), "svs", "corrected")
        with self.assertRaisesRegex(sur.SurrogateError, "unknown topology"):
            sur.surrogate_vco_body(self.vco, "svs", "nope")

    def test_production_deck_untouched_osdi_path(self):
        self.assertEqual(self.vco.count("sg13_hv_svaricap w=3.74e-6"), 32)
        self.assertIn("pre_osdi @@OSDI_MOSVAR@@", self.vco)

    def test_expression_ternaries_balanced(self):
        for expr in (sur.qint_expr(self.s, "x"), sur.r_expr(self.s, "x")):
            self.assertEqual(expr.count("("), expr.count(")"))
            self.assertEqual(expr.count("?"), expr.count(":"))


class Domain(unittest.TestCase):
    def test_inside_and_boundaries(self):
        for lo, hi in ((0.0, 3.3), (1.0, 2.0), (-0.0009, 3.3009), (0.0, 0.0)):
            self.assertEqual(sur.classify_domain(lo, hi), sur.STATUS_OK)

    def test_beyond_one_millivolt_fails_closed_both_edges(self):
        self.assertEqual(sur.classify_domain(-0.00101, 2.0), sur.STATUS_INVALID)
        self.assertEqual(sur.classify_domain(1.0, 3.30101), sur.STATUS_INVALID)
        self.assertEqual(sur.classify_domain(-1.0, 4.0), sur.STATUS_INVALID)
        self.assertEqual(sur.classify_domain(float("nan"), 1.0), sur.STATUS_INVALID)
        self.assertEqual(sur.STATUS_INVALID, "INVALID-OUT-OF-DOMAIN")

    def test_tolerance_cannot_be_widened(self):
        with self.assertRaises(sur.SurrogateError):
            sur.classify_domain(-0.01, 1.0, tol=0.02)

    def test_cli_exit_codes(self):
        import subprocess, sys
        sc = os.path.join(ROOT, "sim/tools/svaricap_surrogate.py")
        ok = subprocess.run([sys.executable, "-I", sc, "check-domain", "0.5", "2.5"],
                            capture_output=True, text=True)
        self.assertEqual((ok.returncode, ok.stdout.strip()), (0, "OK"))
        bad = subprocess.run([sys.executable, "-I", sc, "check-domain", "-0.002", "2.5"],
                             capture_output=True, text=True)
        self.assertEqual(bad.returncode, 3)
        self.assertEqual(bad.stdout.strip(), "INVALID-OUT-OF-DOMAIN")

    def test_oscillator_dc_point_inside_domain_only_midband(self):
        # swing of ~0.55 V about the DC point: VCTRL=1.65 fits, VCTRL=0 / 3.3 do not
        swing = 0.55
        for vctrl, expect in ((1.65, sur.STATUS_OK), (0.0, sur.STATUS_INVALID), (3.3, sur.STATUS_INVALID)):
            v0 = sur.vrec_from_vctrl_dc(vctrl)
            self.assertEqual(sur.classify_domain(v0 - swing, v0 + swing), expect)


class Provenance(unittest.TestCase):
    def test_labels_and_csv_digest(self):
        self.assertEqual(sur.LABEL, "SCREENING ONLY — grades no specification row")
        self.assertIn("#94", sur.PATH_NOTE)
        self.assertIn("noise", sur.NOISE_NOTE)
        p = sur.source_provenance()
        self.assertEqual(len(p["csv_sha256"]), 64)
        self.assertEqual(p["csv"], "sim/varactor-characterization/records/20260927-081226-f88eb89.csv")


@unittest.skipUnless(shutil.which("ngspice"), "ngspice not installed (the emitted expression is then untested here)")
class NgspiceExpression(unittest.TestCase):
    """The ngspice text must implement the same q(v_gw) the Python reference does:
    a slow voltage ramp on W with G at 0 V, bn tied to W (so the native junction
    carries no displacement current), gives i = C(v_rec) * dv/dt. i(Vg) is the current
    LEAVING the cell's G terminal: d q(v_gw)/dt = -C dv_rec/dt flows INTO G, so it is
    positive here, which pins the sign of the charge law."""

    def test_ramp_current_equals_fitted_c_times_slope(self):
        s = sur.load_series(CSV)[("tt", 27.0)]
        k = 1.1e9   # V/s : 0 -> 3.3 V in 3 ns
        deck = "\n".join([
            "* ramp test", sur.render_model_card(), sur.render_subckt(s),
            "Vw w 0 pwl(0 0 3n 3.3)", "Vg g 0 0", "X1 g w g 0 sg13_hv_svaricap_sur",
            "* bn tied to w", "", ".control", "set ngbehavior=hsa", "tran 5p 3n 0 5p",
            "let ig = i(Vg)", "wrdata ramp.txt ig", ".endc", ".end", ""])
        deck = deck.replace("X1 g w g 0 sg", "X1 g w g w sg")
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "t.cir"), "w") as fh:
                fh.write(deck)
            r = subprocess.run(["ngspice", "-b", "t.cir"], cwd=d, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stdout[-500:])
            with open(os.path.join(d, "ramp.txt")) as fh:
                data = [tuple(map(float, l.split()[:2])) for l in fh]
        checked = 0
        for t, i in data:
            v = k * t
            if 0.05 < v < 3.25 and t > 0.1e-9:
                rel = abs(i - s.c_at(v) * k) / (s.c_at(v) * k)
                self.assertLess(rel, 0.03, "v_rec=%g i=%g expected %g" % (v, i, s.c_at(v) * k))
                checked += 1
        self.assertGreater(checked, 100)


if __name__ == "__main__":
    unittest.main()
