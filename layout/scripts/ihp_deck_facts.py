# SPDX-License-Identifier: Apache-2.0
#
# ihp_deck_facts.py -- the two stream FACTS that decide whether IHP's
# primary DRC runset declares its two data-dependent rule categories
# (see layout/scripts/ihp_deck_categories.py, CONDITIONAL):
#
#   edgeseal_boundary_shapes  shapes on EdgeSeal:boundary (39/4) anywhere in
#                             the hierarchy  -> Seal.l declared iff > 0
#   mim_area_um2              merged, flattened MIM (36/0) area under the top
#                             cell, um^2     -> MIM.gR declared iff > Mim_gR
#   mim_gr_um2                Mim_gR read from the deck's own default rule
#                             table (rule_decks/sg13g2_tech_default.json)
#
# These are read from the STREAM and the deck's rule table, never from a DRC
# report, so the expected category count they feed stays independent of the
# run it is asserted against.
#
# Run inside KLayout's interpreter (it needs `pya`):
#   klayout -zz -r ihp_deck_facts.py -rd gds=<in.gds> -rd deck=<.drc> \
#           -rd out=<facts.json>

import json
import os

GDS = gds    # noqa: F821  (injected by klayout -rd)
DECK = deck  # noqa: F821
OUT = out    # noqa: F821

layout = pya.Layout()  # noqa: F821
layout.read(GDS)
tops = list(layout.top_cells())
if len(tops) != 1:
    raise SystemExit("expected exactly one top cell, got %d" % len(tops))
top = tops[0]


def layer(l, d):
    return layout.find_layer(l, d)


seal = 0
li = layer(39, 4)
if li is not None:
    for c in layout.each_cell():
        seal += c.shapes(li).size()

mim_area = 0.0
li = layer(36, 0)
if li is not None:
    reg = pya.Region(top.begin_shapes_rec(li))  # noqa: F821
    reg.merge()
    mim_area = reg.area() * layout.dbu * layout.dbu

with open(os.path.join(os.path.dirname(DECK), "rule_decks",
                       "sg13g2_tech_default.json")) as fh:
    mim_gr = float(json.load(fh)["drc_rules"]["Mim_gR"])

with open(OUT, "w") as fh:
    json.dump({"top_cell": top.name,
               "edgeseal_boundary_shapes": seal,
               "mim_area_um2": round(mim_area, 6),
               "mim_gr_um2": mim_gr}, fh, indent=2, sort_keys=True)
    fh.write("\n")
