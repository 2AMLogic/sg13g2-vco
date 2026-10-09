"""Known-answer tests for the klayout macros snap_grid / break_ring /
prune_spirals on tiny synthetic streams (dbu = 1 nm, no PDK needed).
"""
import os
import tempfile
import unittest

import klayout.db as kdb

from _macro import run_macro

SNAP = "layout/scripts/snap_grid.py"
BREAK = "layout/scripts/break_ring.py"
PRUNE = "layout/scripts/prune_spirals.py"


def new_layout():
    ly = kdb.Layout()
    ly.dbu = 0.001
    return ly


def tmpdir(case):
    d = tempfile.TemporaryDirectory()
    case.addCleanup(d.cleanup)
    return d.name


class SnapGridTests(unittest.TestCase):
    def test_offgrid_vertices_and_instance_snap(self):
        d = tmpdir(self)
        ly = new_layout()
        top, leaf = ly.create_cell("TOP"), ly.create_cell("LEAF")
        li = ly.layer(1, 0)
        leaf.shapes(li).insert(kdb.Box(0, 0, 1003, 2002))   # off-grid corners
        top.insert(kdb.CellInstArray(leaf.cell_index(), kdb.Trans(kdb.Trans.R0, 1003, 2001)))
        gds = os.path.join(d, "in.gds")
        ly.write(gds)

        rc, out, err = run_macro(SNAP, gds=gds)
        self.assertEqual(rc, 0, err)
        self.assertIn("snap_grid:", out)

        res = kdb.Layout()
        res.read(gds)
        for cell in res.each_cell():
            for li2 in res.layer_indexes():
                for sh in cell.shapes(li2).each():
                    for p in sh.polygon.each_point_hull():
                        self.assertEqual((p.x % 5, p.y % 5), (0, 0), p)
        leaf2 = res.cell("LEAF")
        li2 = res.layer_indexes()[0]
        self.assertEqual(
            [(b.p1.x, b.p1.y, b.p2.x, b.p2.y) for b in
             (s.polygon.bbox() for s in leaf2.shapes(li2).each())],
            [(0, 0, 1005, 2000)])
        inst = next(res.cell("TOP").each_inst())
        self.assertEqual((inst.trans.disp.x, inst.trans.disp.y), (1005, 2000))

    def test_near_45_edge_made_exact(self):
        d = tmpdir(self)
        ly = new_layout()
        top = ly.create_cell("TOP")
        li = ly.layer(1, 0)
        # right triangle whose hypotenuse is 1 nm short of exactly 45 degrees
        top.shapes(li).insert(kdb.Polygon([kdb.Point(0, 0), kdb.Point(41588, 0),
                                           kdb.Point(41588, 41587)]))
        gds = os.path.join(d, "in.gds")
        ly.write(gds)
        rc, _, err = run_macro(SNAP, gds=gds)
        self.assertEqual(rc, 0, err)
        res = kdb.Layout()
        res.read(gds)
        poly = next(res.cell("TOP").shapes(res.layer_indexes()[0]).each()).polygon
        pts = list(poly.each_point_hull())
        self.assertTrue(all(p.x % 5 == 0 and p.y % 5 == 0 for p in pts), pts)
        diag = [(a, b) for a, b in zip(pts, pts[1:] + pts[:1])
                if a.x != b.x and a.y != b.y]
        self.assertEqual(len(diag), 1)
        a, b = diag[0]
        self.assertEqual(abs(b.x - a.x), abs(b.y - a.y))

    def test_ongrid_geometry_is_untouched(self):
        d = tmpdir(self)
        ly = new_layout()
        top = ly.create_cell("TOP")
        top.shapes(ly.layer(1, 0)).insert(kdb.Box(0, 0, 1000, 2000))
        gds = os.path.join(d, "in.gds")
        ly.write(gds)
        rc, out, err = run_macro(SNAP, gds=gds)
        self.assertEqual(rc, 0, err)
        self.assertIn("moved 0 vertices", out)
        self.assertIn("moved 0 instances", out)


def ring_layout(path, leaf_names):
    ly = new_layout()
    top = ly.create_cell("TOP")
    li = ly.layer(1, 0)
    for i, name in enumerate(leaf_names):
        leaf = ly.create_cell(name)
        leaf.shapes(li).insert(kdb.Box(0, 0, 100, 100))
        top.insert(kdb.CellInstArray(leaf.cell_index(),
                                     kdb.Trans(kdb.Trans.R0, 1000 * i, 0)))
    ly.write(path)


def instance_count(path):
    ly = kdb.Layout()
    ly.read(path)
    return sum(1 for c in ly.each_cell() for _ in c.each_inst())


class BreakRingTests(unittest.TestCase):
    def test_deletes_exactly_one_matching_instance(self):
        d = tmpdir(self)
        src, dst = os.path.join(d, "in.gds"), os.path.join(d, "out.gds")
        ring_layout(src, ["ptap1", "ptap1$1", "ptap1$2", "ptap1$3", "other"])
        rc, out, err = run_macro(BREAK, gds=src, out=dst, cell="ptap1")
        self.assertEqual(rc, 0, err)
        self.assertEqual(instance_count(src), 5)
        self.assertEqual(instance_count(dst), 4)
        self.assertIn("deleted one 'ptap1' instance", out)

    def test_no_matching_instance_exits_nonzero(self):
        d = tmpdir(self)
        src, dst = os.path.join(d, "in.gds"), os.path.join(d, "out.gds")
        ring_layout(src, ["other", "another"])
        rc, _, err = run_macro(BREAK, gds=src, out=dst, cell="ptap1")
        self.assertEqual(rc, 1)
        self.assertIn("negative control cannot be constructed", err)
        self.assertFalse(os.path.exists(dst))


class PruneSpiralsTests(unittest.TestCase):
    def test_removes_only_spiral_instances(self):
        d = tmpdir(self)
        src, dst = os.path.join(d, "in.gds"), os.path.join(d, "out.gds")
        ring_layout(src, ["inductor2", "inductor2$1", "cmim", "ptap1"])
        rc, _, err = run_macro(PRUNE, gds=src, out=dst, cell="inductor2")
        self.assertEqual(rc, 0, err)
        self.assertEqual(instance_count(src), 4)
        self.assertEqual(instance_count(dst), 2)
        res = kdb.Layout()
        res.read(dst)
        names = {i.cell.name for c in res.each_cell() for i in c.each_inst()}
        self.assertEqual(names, {"cmim", "ptap1"})

    def test_missing_stem_raises(self):
        d = tmpdir(self)
        src, dst = os.path.join(d, "in.gds"), os.path.join(d, "out.gds")
        ring_layout(src, ["cmim"])
        with self.assertRaises(RuntimeError):
            run_macro(PRUNE, gds=src, out=dst, cell="inductor2")


if __name__ == "__main__":
    unittest.main()
