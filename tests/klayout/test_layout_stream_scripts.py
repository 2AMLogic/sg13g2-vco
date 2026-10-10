"""Known-answer tests for layout/scripts/{verify,lvs_break,ihp_deck_facts}.py
(issue #161) on tiny synthetic streams (dbu = 1 nm, no PDK, no IHP deck).

verify.py and ihp_deck_facts.py are klayout macros (run via _macro.run_macro);
lvs_break.py is a CLI script run as a `python -I` subprocess. Every file is
written under a temp dir, never under layout/ or sim/.
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest

import klayout.db as kdb

from _macro import ROOT, run_macro

VERIFY = "layout/scripts/verify.py"
FACTS = "layout/scripts/ihp_deck_facts.py"
LVS_BREAK = os.path.join(ROOT, "layout", "scripts", "lvs_break.py")


def tmpdir(case):
    d = tempfile.TemporaryDirectory()
    case.addCleanup(d.cleanup)
    return d.name


def new_layout():
    ly = kdb.Layout()
    ly.dbu = 0.001
    return ly


def um(v):
    return int(round(v * 1000))


class VerifyTests(unittest.TestCase):
    def build(self, extra_layer=None):
        ly = new_layout()
        top = ly.create_cell("TOP")
        npn = ly.create_cell("npn13G2V")
        var = ly.create_cell("SVaricap$1")     # uniquified name -> stem match
        other = ly.create_cell("not_a_pcell")
        wrap = ly.create_cell("WRAP")
        m1, tm1 = ly.layer(8, 0), ly.layer(126, 2)
        txt = ly.layer(27, 25)
        npn.shapes(m1).insert(kdb.Box(0, 0, um(1), um(1)))
        var.shapes(m1).insert(kdb.Box(0, 0, um(1), um(1)))
        other.shapes(m1).insert(kdb.Box(0, 0, um(1), um(1)))
        wrap.shapes(tm1).insert(kdb.Box(0, 0, um(2), um(2)))
        wrap.shapes(txt).insert(kdb.Text("LA", kdb.Trans(um(1), um(1))))
        for _ in range(3):
            wrap.insert(kdb.CellInstArray(var.cell_index(), kdb.Trans()))
        # npn as a 2x2 array plus one single placement
        # WRAP: a 2x1 array (so nested counts must multiply) plus one single
        top.insert(kdb.CellInstArray(wrap.cell_index(), kdb.Trans(um(10), um(20)),
                                     kdb.Vector(um(20), 0), kdb.Vector(0, um(20)), 2, 1))
        top.insert(kdb.CellInstArray(wrap.cell_index(), kdb.Trans(um(70), um(20))))
        top.insert(kdb.CellInstArray(npn.cell_index(), kdb.Trans(),
                                     kdb.Vector(um(5), 0), kdb.Vector(0, um(5)), 2, 2))
        top.insert(kdb.CellInstArray(npn.cell_index(), kdb.Trans(um(50), um(50))))
        top.insert(kdb.CellInstArray(other.cell_index(), kdb.Trans()))
        if extra_layer:
            top.shapes(ly.layer(*extra_layer)).insert(kdb.Box(0, 0, um(1), um(1)))
        d = tmpdir(self)
        gds = os.path.join(d, "toy.gds")
        ly.write(gds)
        return gds, os.path.join(d, "out.json")

    def test_counts_layers_labels_bbox(self):
        gds, out = self.build()
        rc, stdout, _ = run_macro(VERIFY, gds=gds, out=out)
        self.assertEqual(rc, 0)
        r = json.load(open(out))
        self.assertEqual(r["top_cell"], "TOP")
        self.assertEqual(r["pcell_instance_counts"],
                         {"npn13G2V": 5, "SVaricap": 9})   # npn: 2x2+1; 3 wraps x3
        self.assertEqual(r["em_only_layers_found"], [])
        self.assertEqual(
            [(d["layer"], d["datatype"], d["polygons"], d["texts"])
             for d in r["layers_present"]],
            [(8, 0, 15, 0), (27, 25, 0, 3), (126, 2, 3, 0)])
        self.assertEqual([(l["text"], l["x_um"], l["y_um"]) for l in r["labels"]],
                         [("LA", 11.0, 21.0), ("LA", 31.0, 21.0), ("LA", 71.0, 21.0)])
        self.assertEqual(r["bbox_um"], {"x0": 0.0, "y0": 0.0, "x1": 72.0, "y1": 51.0})
        self.assertEqual(r["area_mm2"], round(72 * 51 / 1e6, 6))
        self.assertIn("npn13G2V", stdout)

    def test_em_only_layer_is_reported_and_fatal(self):
        gds, out = self.build(extra_layer=(201, 0))
        with self.assertRaises(RuntimeError) as cm:
            run_macro(VERIFY, gds=gds, out=out)
        self.assertIn("EM-only", str(cm.exception))
        # the evidence file is written before the failure
        self.assertEqual(json.load(open(out))["em_only_layers_found"], [[201, 0]])

    def test_two_top_cells_rejected(self):
        ly = new_layout()
        ly.create_cell("A")
        ly.create_cell("B")
        d = tmpdir(self)
        gds = os.path.join(d, "two.gds")
        ly.write(gds)
        with self.assertRaises(RuntimeError):
            run_macro(VERIFY, gds=gds, out=os.path.join(d, "o.json"))


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


class LvsBreakTests(unittest.TestCase):
    def setUp(self):
        self.dir = tmpdir(self)
        ly = new_layout()
        top = ly.create_cell("TOP")
        l1 = ly.layer(1, 0)
        for name, n in (("VS_A__blk", 2), ("VS_B__blk", 1), ("KEEP__blk", 1)):
            c = ly.create_cell(name)
            c.shapes(l1).insert(kdb.Box(0, 0, 100, 100))
            for i in range(n):
                top.insert(kdb.CellInstArray(c.cell_index(), kdb.Trans(i * 1000, 0)))
        self.src = os.path.join(self.dir, "in.gds")
        ly.write(self.src)
        self.dst = os.path.join(self.dir, "out.gds")

    def run_break(self, *args):
        return subprocess.run([sys.executable, "-I", LVS_BREAK, *args],
                              capture_output=True, text=True)

    def names(self, path):
        ly = kdb.Layout()
        ly.read(path)
        return sorted(i.cell.name for i in ly.cell("TOP").each_inst())

    def test_removes_exactly_matching_instances(self):
        before = sha(self.src)
        r = self.run_break(self.src, self.dst, "VS_A__")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.names(self.dst), ["KEEP__blk", "VS_B__blk"])
        self.assertIn("VS_A__ x2", r.stdout)
        self.assertEqual(sha(self.src), before)       # input untouched
        self.assertEqual(self.names(self.src).count("VS_A__blk"), 2)

    def test_multiple_prefixes(self):
        r = self.run_break(self.src, self.dst, "VS_A__", "VS_B__")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.names(self.dst), ["KEEP__blk"])

    def test_unmatched_prefix_exits_nonzero_and_writes_nothing(self):
        r = self.run_break(self.src, self.dst, "VS_A__", "NOPE__")
        self.assertEqual(r.returncode, 1)
        self.assertIn("NOPE__", r.stderr)
        self.assertFalse(os.path.exists(self.dst))

    def test_usage_error(self):
        r = self.run_break(self.src, self.dst)
        self.assertEqual(r.returncode, 2)
        self.assertIn("lvs_break.py", r.stderr)


class DeckFactsTests(unittest.TestCase):
    def build(self, seal=True, mim=True, mim_gr=5.5):
        d = tmpdir(self)
        os.makedirs(os.path.join(d, "rule_decks"))
        with open(os.path.join(d, "rule_decks", "sg13g2_tech_default.json"), "w") as fh:
            json.dump({"drc_rules": {"Mim_gR": str(mim_gr)}}, fh)
        deck = os.path.join(d, "ihp-sg13g2.drc")
        open(deck, "w").close()
        ly = new_layout()
        top = ly.create_cell("TOP")
        sub = ly.create_cell("SUB")
        top.insert(kdb.CellInstArray(sub.cell_index(), kdb.Trans(um(100), 0)))
        top.insert(kdb.CellInstArray(sub.cell_index(), kdb.Trans(um(200), 0)))
        if seal:
            ls = ly.layer(39, 4)
            top.shapes(ls).insert(kdb.Box(0, 0, um(5), um(5)))
            sub.shapes(ls).insert(kdb.Box(0, 0, um(1), um(1)))
            sub.shapes(ls).insert(kdb.Box(um(2), 0, um(3), um(1)))
        if mim:
            lm = ly.layer(36, 0)
            # two overlapping 10x10 boxes in TOP: merged 15x10 = 150 um2
            top.shapes(lm).insert(kdb.Box(0, 0, um(10), um(10)))
            top.shapes(lm).insert(kdb.Box(um(5), 0, um(15), um(10)))
            # 2x2 in SUB placed twice: +8 um2 (flattened)
            sub.shapes(lm).insert(kdb.Box(0, um(50), um(2), um(52)))
        ly.write(os.path.join(d, "toy.gds"))
        return d, deck, os.path.join(d, "toy.gds"), os.path.join(d, "facts.json")

    def facts(self, **kw):
        d, deck, gds, out = self.build(**kw)
        rc, _, _ = run_macro(FACTS, gds=gds, deck=deck, out=out)
        self.assertEqual(rc, 0)
        return json.load(open(out))

    def test_with_seal_and_mim(self):
        f = self.facts()
        self.assertEqual(f["top_cell"], "TOP")
        self.assertEqual(f["edgeseal_boundary_shapes"], 3)   # per cell, not per instance
        self.assertEqual(f["mim_area_um2"], 158.0)
        self.assertEqual(f["mim_gr_um2"], 5.5)

    def test_without_seal_and_mim(self):
        f = self.facts(seal=False, mim=False, mim_gr=7)
        self.assertEqual(f["edgeseal_boundary_shapes"], 0)
        self.assertEqual(f["mim_area_um2"], 0.0)
        self.assertEqual(f["mim_gr_um2"], 7.0)

    def test_two_top_cells_rejected(self):
        d, deck, gds, out = self.build()
        ly = kdb.Layout()
        ly.read(gds)
        ly.create_cell("OTHER")
        ly.write(gds)
        rc, _, _ = run_macro(FACTS, gds=gds, deck=deck, out=out)
        self.assertNotEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
