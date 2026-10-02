# SPDX-License-Identifier: Apache-2.0
#
# verify.py -- post-generation checks on the composed stream, read back from
# the stream itself rather than asserted from the request that produced it.
#
# Reports (as JSON, for layout/vco_manifest.json):
#   * flattened instance count per PDK PCell leaf cell -- the acceptance
#     criterion "2 spirals, 1 MIM cap, 32 varactors, 4 HBTs, 3 resistors"
#     is checked against this, not against the request.
#   * every (layer, datatype) present, so the "no EM-only layers" criterion
#     (201/0 LA, 202/0 LB, 210/0 SUBGND) is a measurement.
#   * every text label, so the nine-net criterion is a measurement.
#   * the top cell's bbox.
#
# Run: klayout -zz -r verify.py -rd gds=<in.gds> -rd out=<out.json>

import json
import re

GDS = gds        # noqa: F821
OUT = out        # noqa: F821

# EM-extraction-only layers that must NOT reach the sign-off stream.  They are
# real in sim/inductor-model/em-extraction/gds/inductor_p11.gds (openEMS port
# footprints and a substrate-ground patch) and would surface in issue #61 as
# coverage.layers_in_stream_without_rules.
EM_ONLY = [(201, 0), (202, 0), (210, 0)]

# Leaf cells the PDK's own PCell library emits.  KLayout uniquifies colliding
# names on read (`npn13G2V$1`), so match on the stem.
PCELL_STEMS = ["inductor2", "cmim", "SVaricap", "npn13G2V", "rppd", "ptap1",
               "via_stack"]

layout = pya.Layout()  # noqa: F821
layout.read(GDS)
tops = layout.top_cells()
if len(tops) != 1:
    raise RuntimeError("expected exactly 1 top cell, got %d: %s"
                       % (len(tops), [c.name for c in tops]))
top = tops[0]


def stem(name):
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*?)(\$\d+)?$", name)
    return m.group(1) if m else name


def inst_size(inst):
    """Number of array elements in `inst` (a KLayout array instance counts as
    rows*cols placements, which is what an instance count has to mean here).
    `Instance.size` is a method on some KLayout builds and a property on
    others, so accept both rather than pinning a version."""
    n = inst.size
    return n() if callable(n) else n


def count_flat(cell, target_index, seen=None):
    """Total flattened instances of `target_index` beneath `cell`."""
    total = 0
    for inst in cell.each_inst():
        n = inst_size(inst)
        if inst.cell.cell_index() == target_index:
            total += n
        else:
            total += n * count_flat(inst.cell, target_index)
    return total


counts = {}
for c in layout.each_cell():
    if c.cell_index() == top.cell_index():
        continue
    st = stem(c.name)
    if st in PCELL_STEMS:
        counts[st] = counts.get(st, 0) + count_flat(top, c.cell_index())

layers = []
for li in layout.layer_indexes():
    info = layout.get_info(li)
    shapes = 0
    texts = 0
    it = top.begin_shapes_rec(li)
    while not it.at_end():
        if it.shape().is_text():
            texts += 1
        else:
            shapes += 1
        it.next()
    if shapes or texts:
        layers.append({"layer": info.layer, "datatype": info.datatype,
                       "polygons": shapes, "texts": texts})

labels = []
for li in layout.layer_indexes():
    info = layout.get_info(li)
    it = top.begin_shapes_rec(li)
    while not it.at_end():
        s = it.shape()
        if s.is_text():
            t = s.text.transformed(it.trans())
            labels.append({"text": t.string,
                           "layer": info.layer, "datatype": info.datatype,
                           "x_um": round(t.x * layout.dbu, 4),
                           "y_um": round(t.y * layout.dbu, 4)})
        it.next()

present = {(d["layer"], d["datatype"]) for d in layers}
em_found = [list(p) for p in EM_ONLY if p in present]

bb = top.dbbox()
result = {
    "gds": GDS,
    "top_cell": top.name,
    "dbu_um": layout.dbu,
    "bbox_um": {"x0": round(bb.left, 4), "y0": round(bb.bottom, 4),
                "x1": round(bb.right, 4), "y1": round(bb.top, 4)},
    "area_mm2": round(bb.width() * bb.height() / 1e6, 6),
    "pcell_instance_counts": counts,
    "layers_present": sorted(layers, key=lambda d: (d["layer"], d["datatype"])),
    "labels": sorted(labels, key=lambda d: d["text"]),
    "em_only_layers_found": em_found,
}
with open(OUT, "w") as fh:
    json.dump(result, fh, indent=2, sort_keys=True)
    fh.write("\n")

print("verify: top=%s  bbox=%.1f x %.1f um  area=%.4f mm2"
      % (top.name, bb.width(), bb.height(), result["area_mm2"]))
for k in sorted(counts):
    print("  %-12s %d" % (k, counts[k]))
print("  labels: %s" % sorted({d["text"] for d in labels}))
if em_found:
    raise RuntimeError("EM-only layers present in the sign-off stream: %s" % em_found)
