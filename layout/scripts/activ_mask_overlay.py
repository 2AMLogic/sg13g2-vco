# SPDX-License-Identifier: Apache-2.0
#
# activ_mask_overlay.py -- build the DIAGNOSTIC stream that isolates why the
# only violations `klt drc --deck sg13g2` still reports on layout/vco.gds are
# a deck artefact rather than a layout defect.
#
# THIS STREAM IS NOT A LAYOUT.  It is a controlled experiment and nothing
# else: never commit it, never ship it, never cite a check run against it as
# evidence about the block.  Copying Activ:mask geometry onto Activ:drawing
# would be falsifying mask data if it were done to the real stream.  The only
# thing a check against this copy establishes is which *rule term* the
# difference in verdict comes from.
#
# WHAT IS BEING ISOLATED.  klt's curated sg13g2 deck implements IHP rule
# `Cnt.c` ("Min. Activ enclosure of Cont is 0.07 um") as a plain
#
#     enclosing(Activ.drawing (1/0), Cont.drawing (6/0)) >= 0.07 um
#
# and documents that as an approximation in its own rule description.  IHP's
# deck of record (libs.tech/klayout/tech/drc/rule_decks/feol/5_14_cont.drc)
# writes the enclosing region as
#
#     cnt_c_act = act_nsram.join(activ_mask).not(digibnd_drw)
#
# The dropped `.join(activ_mask)` term is not a scope narrowing -- it makes
# the enclosing region SMALLER than the rule's.  IHP's HBT PCell draws its
# emitter/base windows on Activ:mask (1/20), not on Activ:drawing (1/0), so
# every HBT contact landing on such a window reports as under-enclosed under
# the approximation and is correctly enclosed under the rule.
#
# This script therefore supplies exactly that one missing term -- it copies
# 1/20 onto 1/0 and changes nothing else -- so that re-running the SAME deck,
# the SAME engine and the SAME layout answers the question with klt's own
# check primitive instead of a re-implementation of it.  layout/drc.sh runs
# `klt drc` against both streams and records the pair.
#
# A third difference exists and is deliberately NOT supplied here: the
# official rule checks `cont_sq` (square contacts only, `contbar =
# cont_nseal.non_squares` removed) while the approximation checks all of
# Cont.drawing.  Leaving it out keeps the experiment single-variable; if the
# join alone clears every violation, the bar term cannot be load-bearing.
#
# Run inside KLayout's interpreter (it needs `pya`):
#   klayout -zz -r activ_mask_overlay.py -rd gds=<in.gds> -rd out=<out.gds>

import sys

GDS = gds          # noqa: F821  (injected by klayout -rd)
OUT = out          # noqa: F821

LY_ACTIV = (1, 0)        # activ_drw
LY_ACTIV_MASK = (1, 20)  # activ_mask -- the term the approximation drops

layout = pya.Layout()  # noqa: F821
layout.read(GDS)

src = layout.find_layer(LY_ACTIV_MASK[0], LY_ACTIV_MASK[1])
if src is None:
    sys.stderr.write(
        "activ_mask_overlay: no Activ:mask (1/20) geometry in %s -- the "
        "experiment has no variable to supply, so the Cnt.c explanation in "
        "layout/PROVENANCE.md section 12 no longer applies\n" % GDS)
    raise SystemExit(1)

dst = layout.layer(LY_ACTIV[0], LY_ACTIV[1])
copied = 0
for cell in layout.each_cell():
    for shape in cell.shapes(src).each():
        cell.shapes(dst).insert(shape)
        copied += 1

layout.write(OUT)
print("  activ_mask_overlay: copied %d Activ:mask (1/20) shape(s) onto "
      "Activ:drawing (1/0) -> %s" % (copied, OUT))
