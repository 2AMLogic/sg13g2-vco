# SPDX-License-Identifier: Apache-2.0
#
# measure_ports.py -- read one `klt gen --pdk-pcell` output stream and report
# the device's terminal geometry, MEASURED from the stream rather than
# transcribed into this repo.
#
# Why measured.  Every port coordinate the composition step feeds to
# `klt gen-compose` (as `blocks[].cell.ports[]`) and every pad this flow drops
# a via on has to agree with what the PDK's own PCell actually drew.  Hard-coding
# those numbers would silently go stale the first time IHP-Open-PDK changes a
# PCell, and the failure would be an invisible open, not an error.  So they are
# re-derived on every run and written into layout/vco_manifest.json as evidence.
#
# Terminal naming rules, per device class (all three are documented, mechanical
# rules over measured geometry -- never a guess):
#
#   inductor2  -- the PCell emits two TopMetal1 pin boxes (126/2) plus its own
#                 "LA"/"LB" texts on 27/25.  Each pin box is named by the text
#                 whose anchor point it contains.  Netlist order is
#                 `.subckt inductor la lb sub`.
#   npn13G2V   -- the PCell emits its own "B"/"C"/"E" texts on 63/0 and pin
#                 boxes on 8/2 (Metal1: B, C) and 10/2 (Metal2: E).  Same
#                 containment rule.
#   SVaricap   -- three Metal1 pin boxes (8/2), no texts.  The PDK subckt is
#                 `.subckt sg13_hv_svaricap G1 W G2 bn`; geometrically the two
#                 poly-gate contacts sit at the bottom and top of the cell and
#                 the n-well (nSD) contact between them, offset in -x.  So:
#                 lowest-y box = G1, highest-y = G2, remaining = W.  Verified
#                 against the drawn layers: only the G1/G2 boxes overlap
#                 GatPoly (5/0); only the W box overlaps nSD (32/0).  That
#                 overlap test is ASSERTED here, so the naming cannot silently
#                 invert if the PCell is restructured.
#   rppd       -- two Metal1 pin boxes (8/2), no texts; named P_LO / P_HI by y.
#                 A resistor is symmetric, so which schematic terminal maps to
#                 which is the caller's choice (recorded in PROVENANCE.md).
#   cmim       -- no pin boxes at all.  Terminals are the two drawn plates:
#                 PLUS  = the TopMetal1 top plate (126/0), MINUS = the Metal5
#                 bottom plate (67/0), matching `.subckt cap_cmim PLUS MINUS`
#                 with PLUS the via-connected top plate.
#   ptap1      -- one Metal1 pin box (8/2); named TAP.
#   via_stack  -- interconnect, not a device: no terminals are reported, only
#                 the per-level pad extents, so the drawn wiring can verify it
#                 overlaps each pad it means to land on.
#
# Run inside KLayout's interpreter (it needs `pya`):
#   klayout -zz -r measure_ports.py -rd gds=<in.gds> -rd kind=<class> \
#           -rd out=<out.json>
#
# `kind` is the PCell cell name (inductor2 / cmim / SVaricap / npn13G2V /
# rppd / ptap1 / via_stack).  An unknown kind is an error, never a silent
# empty port list.

import json

GDS = gds          # noqa: F821  (injected by klayout -rd)
KIND = kind        # noqa: F821
OUT = out          # noqa: F821

LY_METAL1 = (8, 0)
LY_METAL1_PIN = (8, 2)
LY_METAL2_PIN = (10, 2)
LY_TM1_PIN = (126, 2)
LY_IND_TEXT = (27, 25)
LY_DEV_TEXT = (63, 0)
LY_GATPOLY = (5, 0)
LY_NSD = (32, 0)
LY_TM1 = (126, 0)
LY_METAL5 = (67, 0)

PAD_LEVELS = {
    "Metal1": (8, 0),
    "Metal2": (10, 0),
    "Metal3": (30, 0),
    "Metal4": (50, 0),
    "Metal5": (67, 0),
    "TopMetal1": (126, 0),
    "TopMetal2": (134, 0),
}

layout = pya.Layout()  # noqa: F821
layout.read(GDS)
top = layout.top_cell()
dbu = layout.dbu


def region(lay):
    li = layout.find_layer(*lay)
    if li is None:
        return pya.Region()  # noqa: F821
    return pya.Region(top.begin_shapes_rec(li))  # noqa: F821


def boxes(lay):
    """Merged shapes on `lay`, as [x0, y0, x1, y1] micron boxes."""
    out = []
    for p in region(lay).each_merged():
        b = p.bbox()
        out.append([round(b.left * dbu, 4), round(b.bottom * dbu, 4),
                    round(b.right * dbu, 4), round(b.top * dbu, 4)])
    return out


def texts(lay):
    """Text anchors on `lay`, as (string, x_um, y_um)."""
    li = layout.find_layer(*lay)
    if li is None:
        return []
    out = []
    it = top.begin_shapes_rec(li)
    while not it.at_end():
        s = it.shape()
        if s.is_text():
            t = s.text.transformed(it.trans())
            out.append((t.string, round(t.x * dbu, 4), round(t.y * dbu, 4)))
        it.next()
    return out


#: A PCell's pin boxes sit on the *pin* datatype (8/2, 10/2, 126/2), drawn on
#: top of the real conductor on the matching drawing layer.  A port must be
#: reported on the DRAWING layer: `klt gen-compose`'s router resolves a leg's
#: via-drop against the pin's own reported layer, and a pin datatype is not in
#: the PDK's metal stack -- so reporting 8/2 makes the router draw the backbone
#: and silently skip the via, leaving an open that still reports
#: `nets[].routed: true`.  (Found exactly that way: `klt extract` flagged the
#: resulting dead Metal1 pads.)
DRAWING_OF = {(8, 2): (8, 0), (10, 2): (10, 0), (126, 2): (126, 0)}


def port(name, box, layer, direction_deg):
    x0, y0, x1, y1 = box
    return {
        "name": name,
        "x_um": round((x0 + x1) / 2.0, 4),
        "y_um": round((y0 + y1) / 2.0, 4),
        "width_um": round(min(x1 - x0, y1 - y0), 4),
        "direction_deg": direction_deg,
        "layer": {"layer": DRAWING_OF.get(layer, layer)[0],
                  "datatype": DRAWING_OF.get(layer, layer)[1]},
        "pin_layer": {"layer": layer[0], "datatype": layer[1]},
        "box_um": box,
    }


def by_text(pin_boxes, text_anchors, directions):
    """Name each pin box by the text anchor it contains.

    `directions` maps the text string to the terminal's `direction_deg` -- the
    side `klt gen-compose`'s router is allowed to approach it from.  Getting it
    right matters: the router rejects a leg that reaches a pin "from behind"
    across the block's own interior (klayout-tools #1895), which for a
    three-terminal device stacked B/E/C is exactly the wrong side.
    """
    named = {}
    for s, tx, ty in text_anchors:
        for b in pin_boxes:
            (x0, y0, x1, y1), lay = b
            if x0 <= tx <= x1 and y0 <= ty <= y1:
                named[s] = port(s, [x0, y0, x1, y1], lay,
                                directions.get(s, 0) if isinstance(directions, dict)
                                else directions)
                break
    return named


ports = {}
extra = {}

if KIND == "inductor2":
    pins = [(b, LY_TM1_PIN) for b in boxes(LY_TM1_PIN)]
    # Both feeds leave the coil at its bottom edge, facing -y.
    ports = by_text(pins, texts(LY_IND_TEXT), {"LA": 270, "LB": 270})
    missing = sorted({"LA", "LB"} - set(ports))
    if missing:
        raise RuntimeError("inductor2: no pin box found for %s" % missing)
    extra["note"] = ("third terminal `sub` is the substrate; it has no drawn "
                     "pin box and is biased by the block's substrate taps")

elif KIND == "npn13G2V":
    pins = ([(b, LY_METAL1_PIN) for b in boxes(LY_METAL1_PIN)]
            + [(b, LY_METAL2_PIN) for b in boxes(LY_METAL2_PIN)])
    # The npn PCell stacks its terminals B (bottom, Metal1) / E (middle,
    # Metal2) / C (top, Metal1).  B and C face out of the footprint in -y/+y;
    # E is boxed in above and below, so its only clear approach is sideways.
    ports = by_text(pins,
                    [t for t in texts(LY_DEV_TEXT) if t[0] in ("B", "C", "E")],
                    {"B": 270, "E": 0, "C": 90})
    missing = sorted({"B", "C", "E"} - set(ports))
    if missing:
        raise RuntimeError("npn13G2V: no pin box found for %s" % missing)

elif KIND == "SVaricap":
    pins = sorted(boxes(LY_METAL1_PIN), key=lambda b: (b[1] + b[3]) / 2.0)
    if len(pins) != 3:
        raise RuntimeError("SVaricap: expected 3 Metal1 pin boxes, got %d" % len(pins))
    g1, w, g2 = pins[0], pins[1], pins[2]
    # Assert the geometric premise of the naming rule rather than trusting it.
    poly, nsd = region(LY_GATPOLY), region(LY_NSD)

    def hits(reg, b):
        bx = pya.Box(int(b[0] / dbu), int(b[1] / dbu),  # noqa: F821
                     int(b[2] / dbu), int(b[3] / dbu))
        return not (reg & pya.Region(bx)).is_empty()  # noqa: F821

    if not (hits(poly, g1) and hits(poly, g2)):
        raise RuntimeError("SVaricap: lowest/highest pin box does not overlap GatPoly")
    if hits(poly, w) or not hits(nsd, w):
        raise RuntimeError("SVaricap: middle pin box is not the nSD well contact")
    ports = {"G1": port("G1", g1, LY_METAL1_PIN, 270),
             "W": port("W", w, LY_METAL1_PIN, 180),
             "G2": port("G2", g2, LY_METAL1_PIN, 90)}

elif KIND == "rppd":
    pins = sorted(boxes(LY_METAL1_PIN), key=lambda b: (b[1] + b[3]) / 2.0)
    if len(pins) != 2:
        raise RuntimeError("rppd: expected 2 Metal1 pin boxes, got %d" % len(pins))
    ports = {"P_LO": port("P_LO", pins[0], LY_METAL1_PIN, 270),
             "P_HI": port("P_HI", pins[1], LY_METAL1_PIN, 90)}
    # The PCell annotates its own solved resistance as a text; carry it through
    # so the manifest records the device value the PDK itself computed.
    extra["pcell_annotations"] = [t[0] for t in texts(LY_DEV_TEXT)]

elif KIND == "ptap1":
    pins = boxes(LY_METAL1_PIN)
    if len(pins) != 1:
        raise RuntimeError("ptap1: expected 1 Metal1 pin box, got %d" % len(pins))
    ports = {"TAP": port("TAP", pins[0], LY_METAL1_PIN, 90)}

elif KIND == "cmim":
    tm1 = boxes(LY_TM1)
    m5 = boxes(LY_METAL5)
    if len(tm1) != 1 or len(m5) != 1:
        raise RuntimeError("cmim: expected 1 TopMetal1 and 1 Metal5 plate, got %d/%d"
                           % (len(tm1), len(m5)))
    ports = {"PLUS": port("PLUS", tm1[0], LY_TM1, 90),
             "MINUS": port("MINUS", m5[0], LY_METAL5, 270)}

elif KIND == "via_stack":
    for name, lay in PAD_LEVELS.items():
        bs = boxes(lay)
        if bs:
            extra.setdefault("pads", {})[name] = bs[0]

else:
    raise RuntimeError("measure_ports.py: unknown device kind %r" % KIND)

bb = top.dbbox()
result = {
    "gds": GDS,
    "kind": KIND,
    "cell_name": top.name,
    "dbu_um": dbu,
    "bbox_um": {"x0": round(bb.left, 4), "y0": round(bb.bottom, 4),
                "x1": round(bb.right, 4), "y1": round(bb.top, 4)},
    "ports": ports,
}
result.update(extra)

with open(OUT, "w") as fh:
    json.dump(result, fh, indent=2, sort_keys=True)
    fh.write("\n")
print("measure_ports: %s (%s) -> %d port(s)" % (KIND, top.name, len(ports)))
