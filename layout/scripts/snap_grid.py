# SPDX-License-Identifier: Apache-2.0
#
# snap_grid.py -- put a stream on the manufacturing grid, in place.
#
#   klayout -zz -r snap_grid.py -rd gds=<in.gds>
#
# IHP's own DRC rule deck requires every drawn vertex on a 5 nm grid
# (rule 3.1 offgrid) and every edge on a 0/45/90 degree angle (rule 3.2
# angle).  PCell arithmetic does not promise either: the inductor2 PCell
# computes its octagon from d = 141.975 um, which lands vertices on
# arbitrary nanometre coordinates and leaves "45 degree" edges one
# nanometre short of exact (dx = 41588, dy = 41587 -> 44.9993 degrees),
# and the rppd PCell's solved serpentine length lands its rows the same
# way.  Rule 3.2 has no angle tolerance, so a nanometre off exact 45 is a
# violation, not a rounding footnote.
#
# This script is the generator's mask-grid step, run inside the same
# scripted flow as everything else (never a GUI edit).  Per cell and per
# layer it:
#
#   1. MERGES the layer's shapes first.  PCells build wide traces and
#      pads from overlapping pieces, and snapping pieces independently
#      moves a shared seam by a few nanometres -- the union then carries
#      a slanted pseudo-edge inside solid metal, which the deck's
#      Euclidian width checks (TM2.a and friends) flag.  Merging removes
#      the seams before any coordinate is touched; the electrical shape
#      (the union) is what gets snapped, unchanged in topology.
#   2. Rounds every merged vertex to the nearest multiple of 5 dbu
#      (5 nm at this stream's dbu = 1 nm).
#   3. Restores edge DIRECTIONS: an edge that was exactly axis-aligned
#      before the snap stays exactly axis-aligned (its end vertex is
#      pinned to the start vertex's row/column), and an edge within
#      0.05 degrees of 45/135 gets |dy| == |dx| exactly, moving its end
#      vertex by at most one grid step.  Independent vertex rounding
#      would otherwise tilt a 5 nm-correct horizontal edge by ~0.035
#      degrees -- acute geometry the Euclidian width checks flag.
#   4. Rounds every instance origin to the same grid.
#
# Vertices move by at most 2.5 nm; no edge changes direction; sizes and
# topology are preserved to the nearest grid step.  Geometry that is
# already on-grid and exactly angled is untouched (the rounding is a
# no-op), which is why this is safe to run over PCell output: the PDK's
# own npn13G2V, cmim, ptap1 and via_stack cells come out of `klt gen`
# on-grid and pass through unchanged.  Text labels are not touched:
# rule 3.1 checks polygon layers only, never label layers.
#
# Deterministic by construction: same input stream -> same output stream,
# so the reproducible-build check (two cold `generate.sh` runs,
# byte-identical vco.gds) covers this step too.

import math

GDS = gds  # noqa: F821  (injected by klayout -rd)

GRID_UM = 0.005          # IHP rule 3.1: all features on a 5 nm grid
ANGLE_TOL_DEG = 0.05     # "meant to be diagonal" window (rule 3.2 has none)

layout = pya.Layout()  # noqa: F821
layout.read(GDS)
dbu = layout.dbu
grid = int(round(GRID_UM / dbu))
assert grid >= 1 and GRID_UM / dbu == grid, "dbu does not divide the grid"

stats = {"layers_merged": 0, "vertices_moved": 0, "edges_straightened": 0,
         "points_dropped": 0, "instances_moved": 0}


def snap_c(v):
    """Round one scalar coordinate to the grid."""
    return int(round(float(v) / grid)) * grid


def snap_ring(pts):
    """Snap one point ring, preserving the raw ring's edge directions.

    Edge i is (pts[i] -> pts[i+1]).  Classification uses the RAW (pre-snap)
    edge: axis-aligned stays axis-aligned, near-45/135 becomes exact, and
    anything else keeps its rounded self (this layout has no such edges,
    but the rule is stated anyway -- never "correct" a direction that was
    not near a target to begin with).  Processing is sequential: adjusting
    edge i's end vertex fixes the start vertex of edge i+1, so each vertex
    is settled exactly once.
    """
    n = len(pts)
    if n < 3:
        return pts
    raw = [(pts[i].x, pts[i].y, pts[(i + 1) % n].x, pts[(i + 1) % n].y)
           for i in range(n)]
    out = [snap_pt(p) for p in pts]
    for i in range(n):
        ax, ay, bx, by = raw[i]
        dx0, dy0 = bx - ax, by - ay
        j = (i + 1) % n
        if dy0 == 0:                       # was exactly horizontal
            if out[j].y != out[i].y:
                out[j] = pya.Point(out[j].x, out[i].y)      # noqa: F821
                stats["edges_straightened"] += 1
            continue
        if dx0 == 0:                       # was exactly vertical
            if out[j].x != out[i].x:
                out[j] = pya.Point(out[i].x, out[j].y)      # noqa: F821
                stats["edges_straightened"] += 1
            continue
        a0 = math.degrees(math.atan2(dy0, dx0)) % 180.0
        meant_45 = abs(a0 - 45.0) <= ANGLE_TOL_DEG
        meant_135 = abs(a0 - 135.0) <= ANGLE_TOL_DEG
        if not (meant_45 or meant_135):
            continue
        a, b = out[i], out[j]
        dx, dy = b.x - a.x, b.y - a.y
        if dx == 0 or dy == 0 or abs(dy) == abs(dx):
            continue                      # collapsed or already exact
        want_dy = dx if meant_45 else -dx
        if abs(want_dy - dy) > 2 * grid:
            continue                      # never move more than one grid step
        out[j] = pya.Point(b.x, a.y + want_dy)              # noqa: F821
        stats["edges_straightened"] += 1
    # Drop vertices collapsed onto their predecessor by the rounding.
    dedup = [out[0]]
    for p in out[1:]:
        if p != dedup[-1]:
            dedup.append(p)
    if len(dedup) > 1 and dedup[0] == dedup[-1]:
        dedup.pop()
    stats["points_dropped"] += n - len(dedup)
    return dedup


def snap_pt(p):
    q = pya.Point(snap_c(p.x), snap_c(p.y))                # noqa: F821
    if q != p:
        stats["vertices_moved"] += 1
    return q


def snapped_polygon(poly):
    """Snapped pya.Polygon from a pya.Polygon, or None if it collapses."""
    hull = snap_ring(list(poly.each_point_hull()))
    if len(hull) < 3:
        return None
    out = pya.Polygon()                                    # noqa: F821
    out.assign_hull(hull)
    for h in range(poly.holes()):
        ring = snap_ring(list(poly.each_point_hole(h)))
        if len(ring) >= 3:
            out.insert_hole(ring)
    if out.area() == 0:
        return None
    return out


def snap_cell_layer(cell, li):
    """Merge + snap one cell's shapes on one layer, in place.

    Only polygon-bearing shapes participate; texts on a mixed layer are
    kept as they are (rule 3.1 never checks labels).  If every merged
    polygon snaps back to exactly the original geometry, nothing is
    rewritten and the layer keeps its original shape inventory.
    """
    shapes = cell.shapes(li)
    region = pya.Region()                                  # noqa: F821
    n_shapes = 0
    for sh in list(shapes.each()):
        if sh.is_polygon():
            region.insert(sh.polygon)
            n_shapes += 1
        elif sh.is_simple_polygon():
            region.insert(sh.simple_polygon.polygon)
            n_shapes += 1
        elif sh.is_box():
            region.insert(sh.box)
            n_shapes += 1
        elif sh.is_path():
            region.insert(sh.path)
            n_shapes += 1
    if n_shapes == 0:
        return
    merged = region.merged()
    before = (stats["vertices_moved"], stats["edges_straightened"],
              stats["points_dropped"])
    snapped = [snapped_polygon(p) for p in merged.each()]
    snapped = [p for p in snapped if p is not None]
    after = (stats["vertices_moved"], stats["edges_straightened"],
             stats["points_dropped"])
    if after == before:
        return                      # nothing moved: keep the original shapes
    stats["layers_merged"] += 1
    for sh in list(shapes.each()):
        if not sh.is_text():
            sh.delete()
    for p in snapped:
        shapes.insert(p)


for cell in layout.each_cell():
    for li in layout.layer_indexes():
        snap_cell_layer(cell, li)
    for inst in list(cell.each_inst()):
        d = inst.trans.disp
        nd = pya.Vector(snap_c(d.x), snap_c(d.y))          # noqa: F821
        if (nd.x, nd.y) != (d.x, d.y):
            inst.trans = pya.Trans(pya.Trans.R0, nd)        # noqa: F821
            stats["instances_moved"] += 1

opts = pya.SaveLayoutOptions()                           # noqa: F821
opts.gds2_write_timestamps = False
# Byte-deterministic output: no wall-clock timestamps in the GDS header or
# structure records, so two cold `generate.sh` runs from empty build dirs
# still produce byte-identical streams with this step in the flow.
layout.write(GDS, opts)
print("snap_grid: %s  grid=%d dbu  rewrote %d cell/layers, moved %d vertices,"
      " straightened %d edges, dropped %d points, moved %d instances"
      % (GDS, grid, stats["layers_merged"], stats["vertices_moved"],
         stats["edges_straightened"], stats["points_dropped"],
         stats["instances_moved"]))
