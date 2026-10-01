# SPDX-License-Identifier: Apache-2.0
#
# prune_spirals.py -- write a copy of the composed layout with the two spiral
# instances removed, for the connectivity evidence described below.
#
# WHY.  A spiral inductor is a continuous piece of TopMetal1/TopMetal2 from one
# terminal to the other, and `klayout_tools.decks.sg13g2`'s extraction deck has
# no inductor device class (its EXTRACTION_DECK declares no `inductors` field
# at all), so `klt extract` on the full layout correctly reports VDD, OUTP and
# OUTN as ONE net -- XL1 shorts VDD to OUTP and XL2 shorts VDD to OUTN at DC,
# exactly as design/vco.spice says they do.
#
# That is the right answer, but it hides the thing this phase has to show: that
# the three tank nodes are joined ONLY through the windings and nowhere else.
# Extracting the same layout with the two inductor instances deleted answers
# that directly -- VDD, OUTP and OUTN must come back as three distinct nets.
#
# The pruned stream is evidence only.  It is written under build/ and is never
# the committed artifact.
#
# Run: klayout -zz -r prune_spirals.py -rd gds=<in> -rd out=<out> \
#              -rd cell=<spiral leaf cell stem>

import re

GDS = gds     # noqa: F821
OUT = out     # noqa: F821
STEM = cell   # noqa: F821

layout = pya.Layout()  # noqa: F821
layout.read(GDS)
top = layout.top_cells()[0]


def stem(name):
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*?)(\$\d+)?$", name)
    return m.group(1) if m else name


targets = set()
for c in layout.each_cell():
    if stem(c.name) == STEM:
        targets.add(c.cell_index())
if not targets:
    raise RuntimeError("no cell with stem %r in %s" % (STEM, GDS))


def prune(cell):
    doomed = [i for i in cell.each_inst() if i.cell.cell_index() in targets]
    for i in doomed:
        cell.erase(i)
    return len(doomed)


removed = 0
for c in layout.each_cell():
    if c.cell_index() not in targets:
        removed += prune(c)

# The emptied spiral cells are now parentless top cells; drop them so the
# pruned stream still has exactly one top for `klt extract`.
for ci in sorted(targets, reverse=True):
    layout.delete_cell_rec(ci)

layout.write(OUT)
print("prune_spirals: removed %d instance(s) of %r -> %s" % (removed, STEM, OUT))
if removed == 0:
    raise RuntimeError("expected to remove at least one %r instance" % STEM)
