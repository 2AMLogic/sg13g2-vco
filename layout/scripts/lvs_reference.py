#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""lvs_reference.py -- derive the LVS reference netlist from design/vco.spice.

    lvs_reference.py <design/vco.spice> <out.cir> <out.json> [--swap-inductor=<name>]

design/vco.spice is the netlist of record (xschem's simulation netlist of
design/vco.sch).  It is a *simulation* deck: subcircuit-call device cards,
testbench sources, model includes and a .control block.  IHP's own KLayout LVS
runset (libs.tech/klayout/tech/lvs/sg13g2.lvs) compares against a CDL-style
reference instead.  This script rewrites the one into the other, line by
line, and never edits design/vco.spice.

Every rewrite is one of the transformations T1..T6 below.  Each is recorded
in the JSON sidecar against the source line it came from, so any reference
line can be traced back to a design/vco.spice line (and its sha256).

  T1  drop simulation-only content: the VSUP/VCT testbench sources (no
      layout counterpart, layout/PROVENANCE.md section 4), .save/.lib/.include/
      .ic cards, the .control block, comments.
  T2  wrap the flat netlist in `.SUBCKT vco <ports>`; the ports are the nine
      named nets, which the layout labels on its pin layers (PROVENANCE.md
      section 9), so every one of them is a name-anchored compare point.
  T3  device-card form, per the PDK's own xschem symbols' `lvs_format`
      attribute (libs.tech/xschem/sg13g2_pr/*.sym) -- the mapping IHP's flow
      itself applies when xschem netlists for LVS:
        npn13G2v         XQ.. Nx El   ->  Q.. le=<El>u we=120.0n m=<Nx>
        inductor         XL..         ->  L.. w s d nr_r m
        cap_cmim         XC..         ->  C.. w l m
        sg13_hv_svaricap XC..         ->  C.. w l Nx
      Units are written with explicit suffixes; values are unchanged.
  T4  ideal resistor -> the physical device the layout draws (PROVENANCE.md
      section 5: rppd, w = 1.0 um).  l comes from the generator's own
      R-to-length law, layout/scripts/floorplan.py:rppd_length_um() (measured
      from the PCell, r(l) = 258.4492*l + 70.001 ohm), then placed on the 5 nm
      manufacturing grid exactly as layout/scripts/snap_grid.py places every
      drawn vertex (IHP rule 3.1).  b=0, m=1 (one unbent body, as drawn).
  T5  substrate.  IHP's runset extracts the p-substrate as its own net, joined
      to the `0` ground net only through the ptap1 tie device; ngspice
      simulation models ignore that tie, so the schematic writes the
      substrate as `0`.  This script therefore (a) moves every *substrate*
      terminal the schematic ties to `0` -- HBT 4th terminal, inductor 3rd,
      the varactor 4th (`bn`, tied to `0` since issue #79), the rppd body
      added by T4 -- onto a net `sub`, and (b) adds the one
      ptap1 tie the layout draws: the guard ring.  Its A/P come from the
      generator's ring specification (floorplan.py RING, RING_W: four
      abutting ptap1 bars that merge into one annulus), not from extraction.
  T6  substrate terminals the schematic ties to anything OTHER than `0` are
      left exactly as written (none remain: the varactor `bn` pins were tied
      to the tank node until issue #79 corrected design/vco.sch; that
      difference used to be kept visible here and is now gone).

`--swap-inductor=<name>` is a DIAGNOSTIC ONLY switch used by layout/lvs.sh
for its single-variable control.  It swaps the two winding terminals of one
inductor card, to test whether that spiral's remaining difference is exactly a
terminal-order one (layout/PROVENANCE.md section 14).  Its output is written
to scratch, is never committed, and is never a reference of record.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import floorplan  # generator constants: rppd law, guard ring

GRID_UM = 0.005          # IHP rule 3.1 manufacturing grid (snap_grid.py)
HBT_WE = "120.0n"        # npn13G2v.sym lvs_format: we=120.0n (fixed device)
PORTS = ["0", "VDD", "OUTP", "OUTN", "VCTRL", "TAIL", "NBIAS", "TE", "RE"]
SUB = "sub"
TESTBENCH_SOURCES = {"VSUP", "VCT"}

_SI = {"t": 1e12, "g": 1e9, "meg": 1e6, "k": 1e3, "m": 1e-3, "u": 1e-6,
       "n": 1e-9, "p": 1e-12, "f": 1e-15}


def si(tok: str) -> float:
    m = re.fullmatch(r"([-+]?[0-9.]+(?:e[-+]?\d+)?)(meg|[tgkmunpf])?", tok.lower())
    if not m:
        raise ValueError(f"not a SPICE number: {tok!r}")
    return float(m.group(1)) * _SI.get(m.group(2) or "", 1.0)


def um(meters: float) -> str:
    """Metres -> explicit-micrometre literal, without float noise."""
    return "%gu" % round(meters * 1e6, 6)


def params(toks):
    out = {}
    for t in toks:
        k, _, v = t.partition("=")
        out[k] = v
    return out


def snap(x_um: float) -> float:
    return round(round(x_um / GRID_UM) * GRID_UM, 6)


def sub_of(net: str) -> tuple[str, bool]:
    """T5(a): a substrate terminal the schematic ties to ground -> `sub`."""
    return (SUB, True) if net == "0" else (net, False)


def derive(src_text: str, swap_inductors=()):
    out, trace = [], []
    in_control = False
    for lineno, raw in enumerate(src_text.splitlines(), 1):
        line = raw.strip()
        low = line.lower()
        if low.startswith(".control"):
            in_control = True
        if in_control:
            if low.startswith(".endc"):
                in_control = False
            continue                                            # T1
        if not line or line.startswith(("*", ".")):
            continue                                            # T1
        toks = line.split()
        name = toks[0]
        if name.upper() in TESTBENCH_SOURCES:
            trace.append({"line": lineno, "source": line, "dropped": True,
                          "transforms": ["T1"]})
            continue
        tr = []
        if name[0] in "Xx":
            model = toks[-1 - sum("=" in t for t in toks[1:])]
            nodes = toks[1:toks.index(model)]
            p = params(toks[toks.index(model) + 1:])
            inst = name[1:]
            if model == "npn13G2v":
                c, b, e, s = nodes
                s, moved = sub_of(s)
                tr += ["T3"] + (["T5a"] if moved else [])
                card = (f"Q{inst} {c} {b} {e} {s} npn13G2v "
                        f"le={um(float(p['El']) * 1e-6)} we={HBT_WE} m={p['Nx']}")
            elif model == "inductor":
                a, b2, s = nodes
                s, moved = sub_of(s)
                tr += ["T3"] + (["T5a"] if moved else [])
                if inst in swap_inductors:
                    a, b2 = b2, a
                    tr += ["DIAGNOSTIC-swap-inductor-terminals"]
                card = (f"L{inst} {a} {b2} {s} inductor w={um(si(p['w']))} "
                        f"s={um(si(p['s']))} d={um(si(p['d']))} "
                        f"nr_r={p['nr_r']} m={p['m']}")
            elif model == "cap_cmim":
                a, b2 = nodes
                tr += ["T3"]
                card = (f"C{inst} {a} {b2} cap_cmim w={um(si(p['w']))} "
                        f"l={um(si(p['l']))} m={p['m']}")
            elif model == "sg13_hv_svaricap":
                g1, w, g2, bn = nodes
                bn, moved = sub_of(bn)
                tr += ["T3"] + (["T5a"] if moved else ["T6"])
                card = (f"C{inst} {g1} {w} {g2} {bn} sg13_hv_svaricap "
                        f"w={um(si(p['w']))} l={um(si(p['l']))} Nx={p['Nx']}")
            else:
                raise SystemExit(f"line {lineno}: no LVS mapping for {model!r}")
        elif name[0] in "Rr":
            a, b2, val = toks[1:4]
            ohm = si(val)
            l_um = snap(floorplan.rppd_length_um(ohm))
            tr += ["T4", "T5a"]
            card = (f"{name} {a} {b2} {SUB} rppd w={um(floorplan.RPPD_W_UM * 1e-6)} "
                    f"l={l_um:g}u b=0 m=1")
        else:
            raise SystemExit(f"line {lineno}: unhandled element {line!r}")
        out.append(card)
        trace.append({"line": lineno, "source": line, "reference": card,
                      "transforms": tr})

    # T5(b): the guard ring, four abutting ptap1 bars = one annulus.
    x0, y0, x1, y1 = floorplan.RING
    w = floorplan.RING_W
    ow, oh = x1 - x0, y1 - y0
    iw, ih = ow - 2 * w, oh - 2 * w
    area = ow * oh - iw * ih
    perim = 2 * (ow + oh) + 2 * (iw + ih)
    tap = f"Rtap_ring 0 {SUB} ptap1 A={area:g}p P={perim:g}u"
    out.append(tap)
    trace.append({"line": None, "source": "layout/scripts/floorplan.py RING=%r "
                  "RING_W=%r" % (floorplan.RING, floorplan.RING_W),
                  "reference": tap, "transforms": ["T5b"]})
    return out, trace


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    swaps = tuple(a.split("=", 1)[1] for a in argv[1:]
                  if a.startswith("--swap-inductor="))
    if len(args) != 3:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    src, out_cir, out_json = args
    with open(src, "rb") as f:
        raw = f.read()
    cards, trace = derive(raw.decode(), swaps)
    diag = bool(swaps)
    src_rel = os.path.relpath(os.path.abspath(src),
                              os.path.dirname(os.path.dirname(
                                  os.path.dirname(os.path.abspath(__file__)))))
    digest = hashlib.sha256(raw).hexdigest()
    head = [
        "* LVS reference for sg13g2-vco -- DERIVED, do not edit.",
        f"* source: {src_rel} @ sha256:{digest}",
        "* by: layout/scripts/lvs_reference.py (transformations T1..T6 in its",
        "*     header; per-line trace in the JSON sidecar)",
    ]
    if diag:
        head.append("* DIAGNOSTIC CONTROL ONLY (swap_inductor=%s). "
                    "NOT a reference of record." % (",".join(swaps) or "none"))
    text = "\n".join(head + ["", ".SUBCKT vco " + " ".join(PORTS)]
                     + cards + [".ENDS vco", ""])
    with open(out_cir, "w") as f:
        f.write(text)
    with open(out_json, "w") as f:
        json.dump({"source": {"file": src_rel, "sha256": digest},
                   "diagnostic": {"swap_inductor": list(swaps)},
                   "ports": PORTS,
                   "constants": {
                       "grid_um": GRID_UM, "hbt_we": HBT_WE,
                       "rppd_w_um": floorplan.RPPD_W_UM,
                       "rppd_ohm_per_um": floorplan.RPPD_OHM_PER_UM,
                       "rppd_head_ohm": floorplan.RPPD_HEAD_OHM,
                       "ring": list(floorplan.RING), "ring_w": floorplan.RING_W},
                   "output_sha256": hashlib.sha256(text.encode()).hexdigest(),
                   "lines": trace}, f, indent=2)
        f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
