# SPDX-License-Identifier: Apache-2.0
#
# break_ring.py -- NEGATIVE CONTROL for the guard-ring continuity evidence.
#
# `klt ring-check` passing on the committed layout only means something if the
# same invocation FAILS on a layout whose ring is actually open.  Without that,
# a `continuous` verdict is indistinguishable from a check that cannot fail --
# and on a layer the ring shares with unrelated geometry, it genuinely cannot
# (see layout/PROVENANCE.md section 12).
#
# This script writes a copy of the input stream with exactly ONE of the guard
# ring's four `ptap1` bars deleted, which opens the annulus on one side and
# nothing else.  layout/drc.sh runs the same ring-check against it and records
# both verdicts side by side.
#
# Run inside KLayout's interpreter (it needs `pya`):
#   klayout -zz -r break_ring.py -rd gds=<in.gds> -rd out=<out.gds> \
#           -rd cell=ptap1

import sys

GDS = gds          # noqa: F821  (injected by klayout -rd)
OUT = out          # noqa: F821
CELL = cell        # noqa: F821

layout = pya.Layout()  # noqa: F821
layout.read(GDS)

removed = 0
for c in layout.each_cell():
    victims = [i for i in c.each_inst() if i.cell.name.startswith(CELL)]
    if victims:
        c.erase(victims[0])
        removed = 1
        break

if removed != 1:
    sys.stderr.write(
        "break_ring: found no '%s' instance to delete -- the negative "
        "control cannot be constructed, so the ring evidence is "
        "unsupported\n" % CELL)
    raise SystemExit(1)

layout.write(OUT)
print("  break_ring: deleted one '%s' instance -> %s" % (CELL, OUT))
