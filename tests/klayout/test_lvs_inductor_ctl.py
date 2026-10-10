"""Known-answer tests for layout/scripts/lvs_inductor_ctl.py (issue #80).

A synthetic stream mirrors the block's structure: a top cell placing two
spiral cells, each holding a PCell-like sub-cell with LA/LB texts on 27/25,
one placed `m90` and one `r0`.  The script is run as a subprocess (isolated
mode) like its production use in layout/lvs.sh.
"""
import os
import subprocess
import sys
import tempfile
import unittest

import klayout.db as kdb

from _macro import ROOT

SCRIPT = os.path.join(ROOT, "layout", "scripts", "lvs_inductor_ctl.py")


def write_stream(path, shared_pcell=False):
    ly = kdb.Layout()
    ly.dbu = 0.001
    top = ly.create_cell("vco")
    lab = ly.layer(27, 25)
    pin = ly.layer(27, 2)

    def pcell(name):
        c = ly.create_cell(name)
        for s, x in (("LA", -25315), ("LB", 25315)):
            c.shapes(pin).insert(kdb.Box(x - 4110, 0, x + 4110, 1000))
            c.shapes(lab).insert(kdb.Text(s, kdb.Trans(x, 0)))
        return c

    p1 = pcell("inductor2")
    p2 = p1 if shared_pcell else pcell("inductor2$1")
    for name, p, trans in (("L1__vco_ind", p1, kdb.Trans(kdb.Trans.M90, -160000, 0)),
                           ("L2__vco_ind", p2, kdb.Trans(160000, 0))):
        c = ly.create_cell(name)
        c.insert(kdb.CellInstArray(p.cell_index(), kdb.Trans()))
        top.insert(kdb.CellInstArray(c.cell_index(), trans))
    ly.write(path)


def run(*args):
    return subprocess.run([sys.executable, "-I", SCRIPT, *args],
                          capture_output=True, text=True)


def top_labels(path):
    """{(label, x, y)} in top coordinates."""
    ly = kdb.Layout()
    ly.read(path)
    top = ly.top_cell()
    it = top.begin_shapes_rec(ly.find_layer(27, 25))
    out = set()
    while not it.at_end():
        s = it.shape()
        if s.is_text():
            p = (it.trans() * s.text).trans.disp
            out.add((s.text_string, p.x, p.y))
        it.next()
    return out


def placements(path):
    ly = kdb.Layout()
    ly.read(path)
    return {i.cell.name: str(i.trans) for i in ly.top_cell().each_inst()}


INTACT = {("LB", -185315, 0), ("LA", -134685, 0), ("LA", 134685, 0), ("LB", 185315, 0)}


class LvsInductorCtlTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.src = os.path.join(self._tmp.name, "in.gds")
        self.dst = os.path.join(self._tmp.name, "out.gds")
        write_stream(self.src)

    def test_fixture_is_mirrored(self):
        self.assertEqual(top_labels(self.src), INTACT)

    def test_flip_moves_l1_la_onto_the_other_port(self):
        r = run(self.src, self.dst, "flip", "L1__vco_ind")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(placements(self.dst)["L1__vco_ind"], "r0 -160000,0")
        self.assertEqual(placements(self.dst)["L2__vco_ind"], "r0 160000,0")
        self.assertEqual(top_labels(self.dst),
                         {("LA", -185315, 0), ("LB", -134685, 0),
                          ("LA", 134685, 0), ("LB", 185315, 0)})

    def test_swap_labels_touches_only_the_named_spiral(self):
        r = run(self.src, self.dst, "swap-labels", "L2__vco_ind")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(top_labels(self.dst),
                         {("LB", -185315, 0), ("LA", -134685, 0),
                          ("LB", 134685, 0), ("LA", 185315, 0)})

    def test_move_la_puts_both_labels_on_one_port(self):
        r = run(self.src, self.dst, "move-la", "L1__vco_ind")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(top_labels(self.dst),
                         {("LB", -185315, 0), ("LA", -185315, 0),
                          ("LA", 134685, 0), ("LB", 185315, 0)})

    def test_refuses_a_shared_label_cell(self):
        write_stream(self.src, shared_pcell=True)
        r = run(self.src, self.dst, "swap-labels", "L1__vco_ind")
        self.assertEqual(r.returncode, 1)
        self.assertIn("shared", r.stderr)
        self.assertFalse(os.path.exists(self.dst))

    def test_refuses_an_unknown_cell(self):
        r = run(self.src, self.dst, "flip", "L9__vco_ind")
        self.assertEqual(r.returncode, 1)
        self.assertFalse(os.path.exists(self.dst))

    def test_usage_error(self):
        r = run(self.src, self.dst, "rotate", "L1__vco_ind")
        self.assertEqual(r.returncode, 2)
        self.assertIn("lvs_inductor_ctl.py", r.stderr)


if __name__ == "__main__":
    unittest.main()
