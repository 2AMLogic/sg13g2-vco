#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""lvs_break.py -- write a SCRATCH copy of a stream with top-level instances removed.

    lvs_break.py <in.gds> <out.gds> <instance-cell-prefix> [...]

Negative-control helper for layout/lvs.sh.  Every top-level instance whose
cell name starts with one of the given prefixes (the generator names each
placed block `<ID>__<cell>`, e.g. `VS_VDD_REF__vco_vs_m1_tm2`) is deleted from
a copy of the stream; nothing else changes.  Exits non-zero unless every
prefix removed at least one instance, so a renamed block cannot turn a
control into a silent no-op.

Like break_ring.py and activ_mask_overlay.py, the output is an experiment, not
a layout: it lives under layout/build/ (gitignored) and is never committed or
cited as evidence about the block.  The committed stream is only ever read.
"""

from __future__ import annotations

import sys

import klayout.db as kdb


def main(argv):
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    src, dst, prefixes = argv[1], argv[2], argv[3:]
    ly = kdb.Layout()
    ly.read(src)
    top = ly.top_cell()
    hits = {p: 0 for p in prefixes}
    doomed = []
    for inst in top.each_inst():
        for p in prefixes:
            if inst.cell.name.startswith(p):
                hits[p] += 1
                doomed.append(inst)
                break
    for inst in doomed:
        inst.delete()
    missing = [p for p, n in hits.items() if n == 0]
    if missing:
        print("error: no top-level instance matches %s" % missing, file=sys.stderr)
        return 1
    opt = kdb.SaveLayoutOptions()
    opt.gds2_write_timestamps = False
    ly.write(dst, opt)
    print("removed %s" % ", ".join("%s x%d" % kv for kv in hits.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
