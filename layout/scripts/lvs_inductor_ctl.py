#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""lvs_inductor_ctl.py -- write a SCRATCH copy of a stream with ONE spiral changed.

    lvs_inductor_ctl.py <in.gds> <out.gds> flip        <cell>
    lvs_inductor_ctl.py <in.gds> <out.gds> swap-labels <cell>
    lvs_inductor_ctl.py <in.gds> <out.gds> move-la     <cell>

Negative-control helper for layout/lvs.sh's label-ordered inductor terminal
step (issue #80).  <cell> is the spiral's cell (the generator names each placed
block `<ID>__<cell>`, e.g. `L1__vco_ind`); it must be placed exactly once, at
top level, so a change to it changes exactly one inductor.

  flip         re-place the instance mirrored about its own vertical axis
               (instance transformation * M90; for L1, `m90` becomes `r0`).
               The spiral's two ports are symmetric about that axis, so both
               stay connected to the same wires -- but the port carrying LA
               now lands on the wire LB used to land on: the winding is
               GENUINELY wired the other way round.
  swap-labels  swap the strings of the cell's LA and LB texts (27/25): each
               label now sits on the other port, i.e. LA is on the wrong net.
  move-la      move the cell's LA text onto its LB text (both labels on one
               port, LA on the wrong net, the other port unlabelled).

Like lvs_break.py, the output is an experiment, not a layout: it lives under
layout/build/ (gitignored) and is never committed or cited as evidence about
the block.  The committed stream is only ever read.  Exits non-zero, writing
nothing, unless the requested change applied exactly as described.
"""

from __future__ import annotations

import sys

import klayout.db as kdb

LABEL_LAYER = (27, 25)  # IHP layers_definitions.lvs: ind_text = labels(27, 25)


def _labels(ly, cell):
    """LA/LB texts in <cell> and the cells below it (the PCell sub-cell holds
    them), refusing any holder cell that is also used outside <cell>'s tree --
    editing it would then change another inductor too."""
    li = ly.find_layer(*LABEL_LAYER)
    out = {}
    if li is None:
        return out
    tree = {cell.cell_index()} | set(cell.called_cells())
    for ci in sorted(tree):
        c = ly.cell(ci)
        texts = [s for s in c.shapes(li).each() if s.is_text()
                 and s.text_string.upper() in ("LA", "LB")]
        if texts and ci != cell.cell_index() and not set(c.caller_cells()) <= tree | set(cell.caller_cells()):
            raise ValueError("label cell %r is shared outside %r" % (c.name, cell.name))
        for s in texts:
            out.setdefault(s.text_string.upper(), []).append(s)
    return out


def main(argv):
    if len(argv) != 5 or argv[3] not in ("flip", "swap-labels", "move-la"):
        print(__doc__, file=sys.stderr)
        return 2
    src, dst, mode, name = argv[1:]
    ly = kdb.Layout()
    ly.read(src)
    top = ly.top_cell()
    cell = ly.cell(name)
    if cell is None:
        print("error: no cell %r" % name, file=sys.stderr)
        return 1
    insts = [i for i in top.each_inst() if i.cell_index == cell.cell_index()]
    if len(insts) != 1 or cell.parent_cells() != 1:
        print("error: %r must be placed exactly once, at top level (found %d top-level "
              "instances, %d parent cells)" % (name, len(insts), cell.parent_cells()),
              file=sys.stderr)
        return 1
    if mode == "flip":
        inst = insts[0]
        before = str(inst.trans)
        inst.trans = inst.trans * kdb.Trans.M90
        what = "%s placement %s -> %s" % (name, before, inst.trans)
    else:
        try:
            lab = _labels(ly, cell)
        except ValueError as e:
            print("error: %s" % e, file=sys.stderr)
            return 1
        la, lb = lab.get("LA", []), lab.get("LB", [])
        if len(la) != 1 or len(lb) != 1 or la[0].cell.cell_index() != lb[0].cell.cell_index():
            print("error: %r has %d LA and %d LB texts on %d/%d, need exactly one each"
                  % (name, len(la), len(lb), *LABEL_LAYER), file=sys.stderr)
            return 1
        ta, tb = la[0].text, lb[0].text
        if mode == "swap-labels":
            na, nb = ta.dup(), tb.dup()
            na.string, nb.string = tb.string, ta.string
            la[0].text, lb[0].text = na, nb
            what = "%s LA<->LB texts swapped (LA now at %s, LB at %s, cell coordinates)" % (
                name, tb.trans.disp, ta.trans.disp)
        else:
            na = ta.dup()
            na.trans = tb.trans
            la[0].text = na
            what = "%s LA text moved %s -> %s (onto LB, cell coordinates)" % (
                name, ta.trans.disp, tb.trans.disp)
    opt = kdb.SaveLayoutOptions()
    opt.gds2_write_timestamps = False
    ly.write(dst, opt)
    print(what)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
