#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""floorplan.py -- the sg13g2-vco physical design, as code.

This module is the single source of truth for the block's floorplan.  It owns
three things and nothing else:

  1. ``DEVICES`` -- the device table: one entry per distinct PDK PCell
     instantiation this block needs, with the exact ``klt gen --pdk-pcell``
     params and the schematic devices it realises.
  2. the floorplan constants and the placement arithmetic derived from them.
  3. the request documents handed to ``klt gen-compose`` / ``klt draw``.

It draws nothing itself: every polygon that reaches the stream is either a PDK
PCell instance (via ``klt gen`` + ``klt gen-compose``) or an explicit rectangle
in the ``klt draw`` request this module emits.  ``generate.sh`` is the driver.

Coordinate frame: micron, origin at the tank's symmetry centre, +y toward the
spirals.  The two spirals occupy y > 0; the active core occupies y < 0.

Device terminal coordinates are never hard-coded here -- they are read from
``build/dev/<id>.ports.json``, which ``measure_ports.py`` derives from the
generated streams on every run (see that file's header for why).

NOT a sign-off flow.  `klt draw` is PDK-unaware by design and will emit
rule-violating geometry happily; DRC and LVS closure are the two sibling
phases' job (issues #61 and #62).  The spacing arithmetic below is written
against the curated `klayout_tools.decks.sg13g2` minimums (quoted inline at
each use) so that those phases start from a near-clean baseline, but nothing
here is a substitute for `klt drc`.
"""

from __future__ import annotations

import json
import os
import sys

# --------------------------------------------------------------------------
# Layers.  (layer, datatype) pairs, from klayout_tools.decks.sg13g2 and the
# PDK's own libs.tech/klayout/tech/lvs/rule_decks/layers_definitions.lvs.
# --------------------------------------------------------------------------
METAL1 = (8, 0)
METAL2 = (10, 0)
METAL3 = (30, 0)
METAL5 = (67, 0)
TOPMETAL1 = (126, 0)
TOPMETAL2 = (134, 0)
# NBL drawing layer (the PDK DRC deck's nbulay_drw = 32/0; IHP rule NBL.b:
# min NBL space or notch, same net, 1.5 um).  The SVaricap PCell draws one
# small NBL shape per cell; the composed banks draw one plate per bank over
# all 16 cells' shapes -- see wiring_request and PROVENANCE.md section 12.
NBULAY = (32, 0)

TEXT = {
    METAL1: (8, 25),
    METAL2: (10, 25),
    METAL3: (30, 25),
    METAL5: (67, 25),
    TOPMETAL1: (126, 25),
    TOPMETAL2: (134, 25),
}

# Curated-deck minimums actually leaned on below (micron):
#   metal1.width 0.16 / space 0.18        metal2-5.width 0.20 / space 0.21
#   via1-4.width 0.19 / space 0.22        metal1.enclosing.via1 0.01
#   topmetal1.width 1.64 / space 1.64     topmetal2.width 2.00 / space 2.00
#   topvia1 0.42, topvia2 0.90            activ.width 0.15 / space 0.21
M1_SP = 0.18
M2_SP = 0.21
TM1_SP = 1.64
TM2_SP = 2.00

# --------------------------------------------------------------------------
# Device table.  `params` go verbatim to `klt gen --pdk-pcell SG13_dev/<pcell>`.
# --------------------------------------------------------------------------
#
# Resistor sizing.  design/vco.spice instantiates RREF/RTE/RRE as *ideal*
# ngspice `R` elements, so the physical device class is this phase's choice;
# see layout/PROVENANCE.md for the reasoning behind `rppd`.  The PCell's
# `Calculate: 'l'` R-to-length solve needs a Tcl callback layer IHP-Open-PDK
# does not ship, so it is inert headlessly and `l` must be supplied directly.
# The length/resistance law was therefore *measured* from the PCell itself at
# w = 1.0 um by generating l = 5/10/20 um and reading its own `rppd r=...`
# annotation:  r(l) = 258.4492 * l_um + 70.001 ohm  (exact on all three
# points).  Inverting it gives the lengths below; generate.sh re-reads each
# generated device's own annotation and records it in the manifest, so a PCell
# change shows up as a value drift in the evidence rather than silently.
RPPD_W_UM = 1.0
RPPD_OHM_PER_UM = 258.4492
RPPD_HEAD_OHM = 70.001


def rppd_length_um(target_ohm: float) -> float:
    return round((target_ohm - RPPD_HEAD_OHM) / RPPD_OHM_PER_UM, 3)


L_RTE = rppd_length_um(2000.0)     # 7.466 um  -> 1999.59 ohm
L_RRE = rppd_length_um(4000.0)     # 15.202 um -> 3999.65 ohm
L_RREF = rppd_length_um(20500.0)   # 79.048 um -> 20500.0 ohm

# Spiral, verbatim from design/vco.spice's XL1/XL2 card.
IND_PARAMS = {"w": "8.22u", "s": "3.74u", "d": "141.975u", "nr_r": 4}

DEVICES = {
    # id            pcell         kind          params
    "ind": ("inductor2", "inductor2", dict(IND_PARAMS)),
    # cmim defaults to w=l=6.99u; Calculate='w&l' makes C derived, not driving.
    "cmim": ("cmim", "cmim", {"w": "3.65u", "l": "3.65u", "Calculate": "w&l"}),
    # SVaricap defaults already match design/vco.spice (w=3.74u, l=0.3u, Nx=1).
    # `bn` names the device's substrate node; design/vco.spice ties it to the
    # tank node, so it is overridden per bank -- see PROVENANCE.md section 6
    # "varactor well and substrate".
    #
    # The override is a faithful record of the intended node, NOT the mechanism
    # that isolates the two banks: measured, the all-layer XOR between the two
    # resulting cells is empty, so the PCell ignores `bn` when drawing.  The
    # isolation is a floorplan property -- the banks sit 67.2 um apart, so
    # their per-bank merged n-well islands cannot touch, and each island's
    # contacts are routed only to its own tank node (see varbank_request and
    # the bank buses in wiring_request).
    "svaricap_p": ("SVaricap", "SVaricap",
                   {"w": "3.74u", "l": "0.3u", "Nx": 1, "bn": "OUTP"}),
    "svaricap_n": ("SVaricap", "SVaricap",
                   {"w": "3.74u", "l": "0.3u", "Nx": 1, "bn": "OUTN"}),
    # NOTE the PCell capitalises the V (npn13G2V) while the model/netlist does
    # not (npn13G2v), and emitter length is `le`, not the netlist's `El`.
    "npn_le1": ("npn13G2V", "npn13G2V", {"le": "1.0u", "Nx": 1}),
    "npn_le2": ("npn13G2V", "npn13G2V", {"le": "2.0u", "Nx": 1}),
    "rppd_rte": ("rppd", "rppd",
                 {"Calculate": "l", "w": "%.1fu" % RPPD_W_UM, "l": "%.3fu" % L_RTE}),
    "rppd_rre": ("rppd", "rppd",
                 {"Calculate": "l", "w": "%.1fu" % RPPD_W_UM, "l": "%.3fu" % L_RRE}),
    "rppd_rref": ("rppd", "rppd",
                  {"Calculate": "l", "w": "%.1fu" % RPPD_W_UM, "l": "%.3fu" % L_RREF}),
    # Substrate taps: the guard ring is four PDK ptap1 bars, not drawn geometry.
    # The two vertical bars ABUT the horizontal ones rather than overlapping
    # them at the corners -- an overlap interleaves the two bars' own contact
    # arrays and `klt drc` reports ~600 cont.space/cont.width violations that
    # neither bar has on its own (measured both ways).
    "ptap_h": ("ptap1", "ptap1", {"w": "185.0u", "l": "2.0u"}),
    "ptap_v": ("ptap1", "ptap1", {"w": "2.0u", "l": "86.0u"}),
    # Via ladders.  SG13_dev/via_stack draws a complete, correctly-enclosed
    # Metal1..TopMetal2 stack from one PCell call, so no via or via-enclosure
    # geometry in this flow is hand-drawn.
    "vs_m1_m2": ("via_stack", "via_stack",
                 {"b_layer": "Metal1", "t_layer": "Metal2",
                  "vn_columns": 2, "vn_rows": 2}),
    # The varactor's n-well contact pad is only 0.53 um wide once it is kept
    # 0.20 um clear of the cell's own gate metal, so its drop needs a
    # single-column stack rather than the 2x2 default.
    "vs_m1_m2_slim": ("via_stack", "via_stack",
                      {"b_layer": "Metal1", "t_layer": "Metal2",
                       "vn_columns": 1, "vn_rows": 2}),
    "vs_m1_m3": ("via_stack", "via_stack",
                 {"b_layer": "Metal1", "t_layer": "Metal3",
                  "vn_columns": 2, "vn_rows": 2}),
    "vs_m2_m3": ("via_stack", "via_stack",
                 {"b_layer": "Metal2", "t_layer": "Metal3",
                  "vn_columns": 2, "vn_rows": 2}),
    "vs_m1_tm1": ("via_stack", "via_stack",
                  {"b_layer": "Metal1", "t_layer": "TopMetal1",
                   "vn_columns": 2, "vn_rows": 2,
                   "vt1_columns": 2, "vt1_rows": 2}),
    "vs_m1_tm2": ("via_stack", "via_stack",
                  {"b_layer": "Metal1", "t_layer": "TopMetal2",
                   "vn_columns": 2, "vn_rows": 2, "vt1_columns": 2,
                   "vt1_rows": 2, "vt2_columns": 2, "vt2_rows": 2}),
    "vs_tm1_tm2": ("via_stack", "via_stack",
                   {"b_layer": "TopMetal1", "t_layer": "TopMetal2",
                    "vt2_columns": 2, "vt2_rows": 2}),
}

# --------------------------------------------------------------------------
# Floorplan constants.
# --------------------------------------------------------------------------
# Tank.  d_out of the p11 spiral is 230.2 um; the PCell's own bbox is
# 290.26 x 291.26 um once its block/marker layers are counted.  SPIRAL_DX is
# the |x| of each spiral's local origin: 320 um centre-to-centre leaves ~60 um
# between the two coils' outer conductor edges (1.39 x d_out), which keeps the
# branch-to-branch mutual coupling small -- the netlist is two *independent*
# 3-terminal inductors (XL1 VDD OUTP 0, XL2 VDD OUTN 0), not one centre-tapped
# differential spiral, and the layout must not make them one.
SPIRAL_DX = 160.0

VDD_TM1_PAD_Y = (-10.0, 1.0)     # TopMetal1 riser under each LA (VDD) pin
VDD_TM2_Y = (-11.5, -3.5)        # TopMetal2 VDD trunk (8.0 um wide)
VDD_TM2_X = (-140.0, 140.0)
VDD_VIA_Y = -6.5                 # TopVia2 stack centre inside the pad/trunk

OUTP_TM1_Y = (-26.0, -22.0)      # TopMetal1 OUTP strap (4.0 um; min 1.64)
OUTN_TM1_Y = (-34.0, -30.0)      # ... and OUTN, 4.0 um clear of it
TANK_LADDER_X = 73.5             # |x| where each tank node drops to Metal1
TANK_M2_HW = 1.5                 # half-width of the Metal2 tank trunks

CAP_ORG = (-1.825, -34.0)        # cmim block origin (centres the cap on x=0)

VAR_PITCH = 2.15                 # = the SVaricap cell's own NWell width, so
                                 # the 16 cells of one bank merge into a single
                                 # n-well island at the bank's tank node
VAR_N = 16
BANK_Y = -52.0
BANK_P_X0 = -68.0
BANK_N_X0 = -(BANK_P_X0 + VAR_N * VAR_PITCH)   # +33.6: mirror of bank P
VCTRL_M3_Y = (-58.0, -56.0)      # VCTRL Metal3 trunk under both banks

Q12_Y = -72.0                    # cross-coupled pair
Q1_ORG_X = -14.0
Q2_ORG_X = 14.0                  # placed mirror_x, so both B/C/E columns face in
Q3_ORG = (-3.87, -86.0)          # tail source, B/C/E column on x = 0
Q4_ORG = (26.13, -76.0)          # bias reference, B/C/E column on x = 30
RTE_ORG = (-0.5, -98.0)
RRE_ORG = (41.5, -92.0)
RREF_ORG = (94.5, -100.0)

OUTP_XC_M3_Y = (-69.0, -68.0)    # OUTP's cross-couple reach to Q2's base
OUTN_XC_M3_Y = (-72.0, -71.0)    # OUTN's, on the same plane 2.0 um clear
XC_BRANCH_M2_Y = (-67.0, -66.0)  # OUTP->Q1.C / OUTN->Q2.C, Metal2
TAIL_M2_Y = (-68.9, -67.9)       # Q1.E/Q2.E strap

VDD_REF_VIA = (95.0, -22.0)      # Metal1..TopMetal2 stack feeding RREF
VDD_SPUR_X = (93.0, 97.0)

RING = (-80.0, -106.0, 105.0, -16.0)   # guard-ring Activ outer box
RING_W = 2.0
PTAP_M1_INSET = (0.2, 0.15)      # ptap1's own Metal1 inset from its Activ box

# Net names, exactly as design/vco.spice spells them (ground is literally `0`).
NETS = ["VDD", "OUTP", "OUTN", "VCTRL", "TAIL", "TE", "NBIAS", "RE", "0"]


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def load_ports(build: str, dev_id: str) -> dict:
    with open(os.path.join(build, "dev", dev_id + ".ports.json")) as fh:
        return json.load(fh)


def place(port: dict, org, mirror_x: bool = False) -> tuple:
    """Composed-frame (x, y) of a block-local port at block origin `org`."""
    x = -port["x_um"] if mirror_x else port["x_um"]
    return (round(x + org[0], 4), round(port["y_um"] + org[1], 4))


def pinbox(port: dict, org, mirror_x: bool = False) -> list:
    x0, y0, x1, y1 = port["box_um"]
    if mirror_x:
        x0, x1 = -x1, -x0
    return [round(x0 + org[0], 4), round(y0 + org[1], 4),
            round(x1 + org[0], 4), round(y1 + org[1], 4)]


def rect(layer, x0, y0, x1, y1, net=None):
    s = {"layer": list(layer), "rect_um": [round(x0, 4), round(y0, 4),
                                           round(x1, 4), round(y1, 4)]}
    if net:
        s["name"] = net
    return s


def label(layer, text, x, y):
    return {"layer": list(TEXT[layer]), "text": text,
            "at_um": [round(x, 4), round(y, 4)]}


def cell_block(bid, gds, cell, ports=None, orientation=None, abuts=None):
    c = {"gds_path": gds, "cell_name": cell}
    if ports:
        c["ports"] = ports
    b = {"id": bid, "cell": c}
    if orientation:
        b["orientation"] = orientation
    if abuts:
        b["abuts"] = abuts
    return b


def port_decl(p):
    """A `blocks[].cell.ports[]` entry from a measured port record."""
    return {"name": p["name"], "x_um": p["x_um"], "y_um": p["y_um"],
            "width_um": p["width_um"], "direction_deg": p["direction_deg"],
            "layer": p["layer"]}


# --------------------------------------------------------------------------
# the composition requests
# --------------------------------------------------------------------------
def varbank_request(build, side):
    """One 16-cell varactor bank, as a `klt gen-compose` array composition.

    `placement.strategy: "array"` emits the 16 tiles as a single hierarchical
    CellInstArray at the cell's own NWell pitch, so all 16 n-wells merge into
    one island -- which is correct, because all 16 share one tank node.  The
    two banks' islands are ~67 um apart and no n-well or n+ tap anywhere in
    this layout bridges them (see PROVENANCE.md).
    """
    dev = "svaricap_" + side
    x0 = BANK_P_X0 if side == "p" else BANK_N_X0
    return {
        "pdk": {"variant": "ihp-sg13g2", "root": "@PDK_ROOT@"},
        "blocks": [cell_block("cell", "../dev/%s.gds" % dev,
                              load_ports(build, dev)["cell_name"])],
        "placement": {"strategy": "array", "order": ["cell"],
                      "rows": 1, "cols": VAR_N,
                      "row_pitch_um": VAR_PITCH, "col_pitch_um": VAR_PITCH,
                      "origin_um": {"x": x0, "y": BANK_Y}},
        "connectivity": [],
        "options": {"cell_name": "vco_varbank_" + side,
                    "output": "@BUILD@/vco_varbank_%s.gds" % side},
    }


def core_request(build):
    """The bias/core devices, placed and partly routed by `klt gen-compose`.

    `connectivity[]` here carries the one net that lives entirely inside this
    composition's own clear region and can be left to klt's router without a
    via drop: NBIAS.  TE and RE would need router via1 drops, which klt draws
    at 0.22 um against IHP's fixed 0.19 um via1 (rule V1.a checks min AND
    max), so they are drawn explicitly in `wiring_request` with via_stack
    PCell ladders instead.  The remaining nets (VDD, OUTP, OUTN, VCTRL, TAIL,
    0) are also drawn in `wiring_request` -- not because the router could not
    be coaxed into them, but because each one either (a) terminates on a device
    pad the sg13g2 layer-role table cannot name (the spirals' TopMetal1 pins,
    the MIM cap's Metal5/TopMetal1 plates), or (b) needs deliberate,
    symmetric, wide differential metal that a point-to-point Manhattan router
    does not produce.  See PROVENANCE.md "what klt routed and what it did not".
    """
    q1 = load_ports(build, "npn_le1")
    q3 = load_ports(build, "npn_le2")
    rte, rre, rref = (load_ports(build, "rppd_" + n) for n in ("rte", "rre", "rref"))

    blocks = [
        cell_block("Q1", "../dev/npn_le1.gds", q1["cell_name"],
                   [port_decl(p) for p in q1["ports"].values()]),
        cell_block("Q2", "../dev/npn_le1.gds", q1["cell_name"],
                   [port_decl(p) for p in q1["ports"].values()],
                   orientation="mirror_x"),
        cell_block("Q3", "../dev/npn_le2.gds", q3["cell_name"],
                   [port_decl(p) for p in q3["ports"].values()]),
        cell_block("Q4", "../dev/npn_le1.gds", q1["cell_name"],
                   [port_decl(p) for p in q1["ports"].values()]),
        cell_block("RTE", "../dev/rppd_rte.gds", rte["cell_name"],
                   [port_decl(p) for p in rte["ports"].values()]),
        cell_block("RRE", "../dev/rppd_rre.gds", rre["cell_name"],
                   [port_decl(p) for p in rre["ports"].values()]),
        cell_block("RREF", "../dev/rppd_rref.gds", rref["cell_name"],
                   [port_decl(p) for p in rref["ports"].values()]),
    ]
    origins = {
        "Q1": {"x": Q1_ORG_X, "y": Q12_Y},
        "Q2": {"x": Q2_ORG_X, "y": Q12_Y},
        "Q3": {"x": Q3_ORG[0], "y": Q3_ORG[1]},
        "Q4": {"x": Q4_ORG[0], "y": Q4_ORG[1]},
        "RTE": {"x": RTE_ORG[0], "y": RTE_ORG[1]},
        "RRE": {"x": RRE_ORG[0], "y": RRE_ORG[1]},
        "RREF": {"x": RREF_ORG[0], "y": RREF_ORG[1]},
    }
    # Waypoints are derived from the measured terminal positions, not written
    # out as literals, so they follow the devices if a PCell changes.
    rref_lo = place(rref["ports"]["P_LO"], RREF_ORG)
    rref_box = pinbox(rref["ports"]["P_LO"], RREF_ORG)

    # TE and RE are NOT routed here.  klt's router draws its own via1 drops
    # at its PDK-independent 0.22 um contact size, but IHP's rule V1.a fixes
    # via1 at 0.19 um in BOTH directions (min and max), so the router's drop
    # is an automatic V1.a violation on this PDK.  Both nets are drawn in
    # wiring_request instead -- explicit Metal2 runs plus SG13_dev/via_stack
    # PCell ladders (PDK via1) at each resistor feed, the same pattern as
    # every other layer transition in this block.  See PROVENANCE.md
    # section 12.
    connectivity = [
        # NBIAS: Q4's own B-C diode strap is drawn (a Metal2 landing inside an
        # npn13G2V footprint would short to its emitter pad), so the router is
        # given the three *inter-device* pins only, with each leg steered clear
        # of the resistors' bodies.
        {"net": "NBIAS",
         "pins": [{"block": "Q3", "port": "B"},
                  {"block": "Q4", "port": "B"},
                  {"block": "RREF", "port": "P_LO"}],
         "legs": [
             {"from_pin": {"block": "Q3", "port": "B"},
              "to_pin": {"block": "Q4", "port": "B"},
              "waypoints_um": [[0.0, -88.0], [30.0, -88.0]]},
             # RREF's P_LO faces -y and the device is 79 um of poly standing
             # above it, so the approach has to come round below the body --
             # reaching the pin from any other side crosses that body.
             {"from_pin": {"block": "Q4", "port": "B"},
              "to_pin": {"block": "RREF", "port": "P_LO"},
              "waypoints_um": [[Q4_ORG[0] + 3.87, rref_box[1] - 2.5],
                               [rref_lo[0], rref_box[1] - 2.5]]},
         ]},
    ]
    return {
        "pdk": {"variant": "ihp-sg13g2", "root": "@PDK_ROOT@"},
        "blocks": blocks,
        "placement": {"strategy": "explicit", "order": list(origins),
                      "origins_um": origins},
        "connectivity": connectivity,
        "routing": {"layer_role": "metal", "width_um": 0.4},
        "options": {"cell_name": "vco_core", "output": "@BUILD@/vco_core.gds"},
    }


def wiring_request(build):
    """Every net klt's sg13g2 layer-role table cannot express, as `klt draw`.

    Ladders and via enclosures are NOT drawn here -- those are
    SG13_dev/via_stack PCell instances placed by the top composition.  What is
    drawn is the planar metal between them: the TopMetal2 VDD trunk, the
    TopMetal1 OUTP/OUTN tank straps, the Metal5 cap return, the Metal2 tank
    trunks and their cross-couple branches, the Metal3 cross-over, the Metal1
    varactor-bank buses, the per-bank NBL plates, the Metal3 VCTRL trunk, the
    substrate returns, the Q4 diode strap, and the nine net labels.
    """
    ind = load_ports(build, "ind")
    cap = load_ports(build, "cmim")
    q1 = load_ports(build, "npn_le1")
    q3 = load_ports(build, "npn_le2")
    rte = load_ports(build, "rppd_rte")
    rre = load_ports(build, "rppd_rre")
    rref = load_ports(build, "rppd_rref")

    s = []    # shapes
    t = []    # labels
    g = GEOM  # the shared derived-geometry record (filled by `geometry()`)

    # ---------------------------------------------------------------- VDD --
    # TopMetal2 trunk between the two spirals' LA (VDD) pins, plus a TopMetal1
    # riser under each pin for the TopVia2 stack to land in.
    for lax, _ in (g["L1_LA"], g["L2_LA"]):
        hw = ind["ports"]["LA"]["width_um"] / 2.0
        s.append(rect(TOPMETAL1, lax - hw, VDD_TM1_PAD_Y[0], lax + hw,
                      VDD_TM1_PAD_Y[1], "VDD"))
    s.append(rect(TOPMETAL2, VDD_TM2_X[0], VDD_TM2_Y[0], VDD_TM2_X[1],
                  VDD_TM2_Y[1], "VDD"))
    # spur down to the RREF feed, and the Metal1 riser onto RREF's top pin
    s.append(rect(TOPMETAL2, VDD_SPUR_X[0], VDD_REF_VIA[1] - 2.0,
                  VDD_SPUR_X[1], VDD_TM2_Y[1], "VDD"))
    # RREF stands 79 um tall; its VDD end (P_HI) is the topmost point of the
    # device, and the Metal1..TopMetal2 stack that feeds it sits just BELOW
    # that pin, so the riser runs downward from the pin to the stack.  (The
    # first cut ran it the other way and `klt extract` reported the pin as
    # dead metal -- the measured-geometry read-back is what caught it.)
    rref_hi = g["RREF_HI_BOX"]
    s.append(rect(METAL1, rref_hi[0] + 0.08, VDD_REF_VIA[1] - 0.4,
                  rref_hi[2] - 0.08, rref_hi[3], "VDD"))
    t.append(label(TOPMETAL2, "VDD", 0.0, sum(VDD_TM2_Y) / 2.0))

    # ----------------------------------------------------------- OUTP/OUTN --
    # Tank straps on TopMetal1: the spiral PCell puts its LA/LB pins on
    # TopMetal1 (126/2), so OUTP/OUTN need no via at the spiral end at all.
    hw = ind["ports"]["LB"]["width_um"] / 2.0
    capp = g["CAP_PLUS_BOX"]
    # OUTP: down from L1's LB pin, then in to the cap's TopMetal1 top plate.
    s.append(rect(TOPMETAL1, g["L1_LB"][0] - hw, OUTP_TM1_Y[0],
                  g["L1_LB"][0] + hw, VDD_TM1_PAD_Y[1], "OUTP"))
    s.append(rect(TOPMETAL1, g["L1_LB"][0] - hw, OUTP_TM1_Y[0],
                  capp[2], OUTP_TM1_Y[1], "OUTP"))
    s.append(rect(TOPMETAL1, capp[0], capp[3] - 0.6, capp[2],
                  OUTP_TM1_Y[1], "OUTP"))
    t.append(label(TOPMETAL1, "OUTP", -120.0, sum(OUTP_TM1_Y) / 2.0))
    # OUTN: down from L2's LB pin to its own strap, which stops short of the
    # cap; the cap's Metal5 bottom plate returns to OUTN on Metal5 instead.
    s.append(rect(TOPMETAL1, g["L2_LB"][0] - hw, OUTN_TM1_Y[0],
                  g["L2_LB"][0] + hw, VDD_TM1_PAD_Y[1], "OUTN"))
    s.append(rect(TOPMETAL1, TANK_LADDER_X - 3.5, OUTN_TM1_Y[0],
                  g["L2_LB"][0] + hw, OUTN_TM1_Y[1], "OUTN"))
    capm = g["CAP_MINUS_BOX"]
    m5y = (VDD_REF_VIA[1] * 0 + sum(OUTN_TM1_Y) / 2.0 - 0.3,
           sum(OUTN_TM1_Y) / 2.0 + 0.3)
    s.append(rect(METAL5, capm[2] - 1.4, m5y[0], TANK_LADDER_X + 0.73,
                  m5y[1], "OUTN"))
    t.append(label(TOPMETAL1, "OUTN", 120.0, sum(OUTN_TM1_Y) / 2.0))

    # Metal2 trunks from each tank ladder down into the core.
    for net, sgn, ybot in (("OUTP", -1.0, Q12_Y + 1.0), ("OUTN", 1.0, Q12_Y - 1.0)):
        x = sgn * TANK_LADDER_X
        s.append(rect(METAL2, x - TANK_M2_HW, ybot, x + TANK_M2_HW,
                      OUTP_TM1_Y[1] + 0.5 if net == "OUTP" else OUTN_TM1_Y[1] + 0.5,
                      net))

    # Cross-couple, half on Metal2 (collector side) and half on Metal3 (base
    # side).  A differential pair's cross-coupling is a crossing by
    # construction; putting the two halves on different planes is what makes
    # it drawable without a short.
    q1c = g["Q1_C_BOX"]
    q2c = g["Q2_C_BOX"]
    s.append(rect(METAL2, -TANK_LADDER_X - TANK_M2_HW, XC_BRANCH_M2_Y[0],
                  g["VS_Q1C"][0] + 0.35, XC_BRANCH_M2_Y[1], "OUTP"))
    s.append(rect(METAL2, g["VS_Q2C"][0] - 0.35, XC_BRANCH_M2_Y[0],
                  TANK_LADDER_X + TANK_M2_HW, XC_BRANCH_M2_Y[1], "OUTN"))
    s.append(rect(METAL3, -TANK_LADDER_X - 0.35, OUTP_XC_M3_Y[0],
                  g["VS_Q2B"][0] + 0.35, OUTP_XC_M3_Y[1], "OUTP"))
    s.append(rect(METAL3, g["VS_Q2B"][0] - 0.35, g["VS_Q2B"][1] - 0.31,
                  g["VS_Q2B"][0] + 0.35, OUTP_XC_M3_Y[1], "OUTP"))
    s.append(rect(METAL3, g["VS_Q1B"][0] - 0.35, OUTN_XC_M3_Y[0],
                  TANK_LADDER_X + 0.35, OUTN_XC_M3_Y[1], "OUTN"))
    s.append(rect(METAL3, g["VS_Q1B"][0] - 0.35, OUTN_XC_M3_Y[0],
                  g["VS_Q1B"][0] + 0.35, g["VS_Q1B"][1] + 0.31, "OUTN"))
    assert q1c and q2c   # measured, used via g[] above

    # ------------------------------------------------- varactor bank buses --
    for side, x0, net in (("p", BANK_P_X0, "OUTP"), ("n", BANK_N_X0, "OUTN")):
        var = load_ports(build, "svaricap_" + side)
        g1, g2, w = (var["ports"][k] for k in ("G1", "G2", "W"))
        # One same-net NBL plate per bank, spanning all 16 cells' own NBL
        # shapes.  IHP rule NBL.b requires 1.5 um between NBL regions (or a
        # notch-free union) even on the same net, and VAR_PITCH = the cell's
        # own NWell width leaves only ~0.48 um cell-to-cell -- the plate
        # unions the bank's NBL into one notch-free region at the bank's
        # tank node.  The two banks are 67.2 um apart (>> NBL.c's 3.2 um
        # different-net minimum), so the plates cannot bridge them.  Derived
        # from the measured nbl_box_um, never a transcribed constant.
        nbl = var["nbl_box_um"]
        s.append(rect(NBULAY, x0 + nbl[0], BANK_Y + nbl[1],
                      x0 + (VAR_N - 1) * VAR_PITCH + nbl[2],
                      BANK_Y + nbl[3], net))
        # Per-cell Metal1 landing pads over the n-well (W) contacts.  0.20 um
        # clear of the cell's own gate metal at local x = 0.75 (metal1.space
        # 0.18); 1.62 um clear of the neighbouring cell's pad.
        wy0, wy1 = w["box_um"][1] + BANK_Y, w["box_um"][3] + BANK_Y
        via_x = [x for (x, _y) in g["BANK_VIAS_" + side.upper()]]
        for k in range(VAR_N):
            bx = x0 + k * VAR_PITCH
            s.append(rect(METAL1, bx + 0.02, wy0, bx + 0.55, wy1, net))
        # one Metal2 bus over the whole bank, fed by the tank trunk
        bus_x0 = min(via_x) - 0.35
        bus_x1 = max(via_x) + 0.35
        if net == "OUTP":
            bus_x0 = -TANK_LADDER_X - TANK_M2_HW
        else:
            bus_x1 = TANK_LADDER_X + TANK_M2_HW
        s.append(rect(METAL2, bus_x0, wy0 + 0.195, bus_x1, wy1 - 0.195, net))
        # VCTRL rails over the 16 gate pads, bottom (G1) and top (G2)
        rail_x0 = x0 + g1["box_um"][0] - 0.05
        rail_x1 = x0 + (VAR_N - 1) * VAR_PITCH + g1["box_um"][2] + 0.05
        s.append(rect(METAL1, rail_x0, BANK_Y + g1["box_um"][1] - 0.21,
                      rail_x1, BANK_Y + g1["box_um"][3] + 0.03, "VCTRL"))
        s.append(rect(METAL1, rail_x0, BANK_Y + g2["box_um"][1] - 0.03,
                      rail_x1, BANK_Y + g2["box_um"][3] + 0.21, "VCTRL"))
        # riser carrying the top rail round the outboard end of the bank
        rx0, rx1 = g["VCTRL_RISER_" + side.upper()]
        s.append(rect(METAL1, min(rx0, rail_x0), BANK_Y + g2["box_um"][1] - 0.03,
                      max(rx1, rail_x1), BANK_Y + g2["box_um"][3] + 0.21, "VCTRL"))
        s.append(rect(METAL1, rx0, BANK_Y - 1.6, rx1,
                      BANK_Y + g2["box_um"][3] + 0.21, "VCTRL"))
        # Metal3 drops from both taps onto the VCTRL trunk
        for (vx, vy) in (g["VS_VCTRL_%s1" % side.upper()],
                         g["VS_VCTRL_%s2" % side.upper()]):
            s.append(rect(METAL3, vx - 0.35, VCTRL_M3_Y[1] - 1.0,
                          vx + 0.35, vy + 0.305, "VCTRL"))
    s.append(rect(METAL3, BANK_P_X0 - 2.0, VCTRL_M3_Y[0], -BANK_P_X0 + 2.0,
                  VCTRL_M3_Y[1], "VCTRL"))
    t.append(label(METAL3, "VCTRL", 0.0, sum(VCTRL_M3_Y) / 2.0))

    # ---------------------------------------------------------------- TAIL --
    # Q1.E / Q2.E are the npn PCell's own Metal2 pads, so the pair's emitter
    # strap is a single Metal2 rectangle; it drops to Q3's Metal1 collector
    # through one via_stack.
    s.append(rect(METAL2, g["Q1_E_BOX"][0], TAIL_M2_Y[0], g["Q2_E_BOX"][2],
                  TAIL_M2_Y[1], "TAIL"))
    q3c = g["Q3_C_BOX"]
    s.append(rect(METAL2, q3c[0], q3c[1] - 0.02, q3c[2], TAIL_M2_Y[1], "TAIL"))
    t.append(label(METAL1, "TAIL", *g["VS_Q3C"]))

    # ---------------------------------------------- NBIAS (Q4 diode strap) --
    # Around Q4's own footprint on Metal1: a Metal2 strap would short to the
    # emitter pad that covers most of the device.
    q4b, q4c = g["Q4_B_BOX"], g["Q4_C_BOX"]
    lx0, lx1 = Q4_ORG[0] - 1.6, Q4_ORG[0] - 1.0
    by = Q4_ORG[1] - 0.8
    s.append(rect(METAL1, q4b[0] + 0.22, by, q4b[2] - 0.22, q4b[3], "NBIAS"))
    s.append(rect(METAL1, lx0, by, q4b[2] - 0.22, by + 0.6, "NBIAS"))
    s.append(rect(METAL1, lx0, by, lx1, q4c[3], "NBIAS"))
    s.append(rect(METAL1, lx0, q4c[1] + 0.025, q4c[2] - 0.2, q4c[3], "NBIAS"))
    t.append(label(METAL1, "NBIAS", *g["Q4_B"]))
    t.append(label(METAL2, "RE", *g["Q4_E"]))
    t.append(label(METAL1, "TE", *g["RTE_HI"]))

    # ---------------------------------------------- TE / RE (drawn, not routed) --
    # The emitter-feed nets, previously left to klt's router: both start on
    # an npn Metal2 emitter pad (boxed in by that device's own Metal1 base
    # and collector, so the run escapes sideways before turning) and end on
    # a resistor's Metal1 P_HI pad, reached from above.  Drawn here so the
    # only via1 in each feed is a SG13_dev/via_stack PCell's own -- klt's
    # router via1 is 0.22 um, which IHP rule V1.a (min AND max 0.19) rejects
    # outright.  Waypoints follow the measured pads, not literals.
    for net, pad, emit, escape_x, drop_dy in (
            ("TE", g["RTE_HI"], g["Q3_E"], 5.5, 1.75),
            ("RE", g["RRE_HI"], g["Q4_E"], 5.5, 2.0)):
        wpx = round(emit[0] + escape_x, 4)      # sideways escape from the pad
        wpy = round(pad[1] + drop_dy, 4)        # approach plane above the pad
        s.append(rect(METAL2, emit[0] - 0.2, emit[1] - 0.2, wpx + 0.2,
                      emit[1] + 0.2, net))                       # pad escape
        s.append(rect(METAL2, wpx - 0.2, wpy, wpx + 0.2, emit[1] + 0.2, net))
        s.append(rect(METAL2, pad[0] - 0.2, wpy - 0.2, wpx + 0.2, wpy + 0.2, net))
        s.append(rect(METAL2, pad[0] - 0.2, pad[1], pad[0] + 0.2, wpy + 0.2, net))

    # ------------------------------------------------- substrate return (0) --
    # Each resistor's cold end returns to the guard ring on Metal3, chosen so
    # that the whole Metal1/Metal2 plane in the bias region stays available to
    # klt's router for NBIAS/TE/RE.
    ring_m1 = g["RING_M1"]
    for (rx, _ry) in (g["VS_RTE_LO"], g["VS_RRE_LO"]):
        s.append(rect(METAL3, rx - 0.35, ring_m1[1] + 0.35, rx + 0.35,
                      _ry + 0.305, "0"))
    # Metal1 straps closing the guard ring's four ptap1 bars at the corners.
    for cx in (ring_m1[0], ring_m1[2] - RING_W + 2 * PTAP_M1_INSET[0]):
        s.append(rect(METAL1, cx, ring_m1[1], cx + RING_W - 2 * PTAP_M1_INSET[0],
                      ring_m1[3], "0"))
    t.append(label(METAL1, "0", (RING[0] + RING[2]) / 2.0,
                   ring_m1[1] + (RING_W - 2 * PTAP_M1_INSET[1]) / 2.0))

    assert len(t) == len(NETS), "expected one label per net, got %d" % len(t)
    assert {lb["text"] for lb in t} == set(NETS)
    for name in ("rte", "rre", "rref", "cmim", "ind", "npn_le1", "npn_le2"):
        assert name  # all port records were loaded above
    del q1, q3, rte, rre, rref, cap, ind

    return {"dbu_um": 0.001, "shapes": s, "labels": t}


def top_request(build):
    """Final assembly: the spirals, the cap, the two banks, the core, the drawn
    wiring, the guard-ring taps and every via ladder, at explicit origins."""
    ind = load_ports(build, "ind")
    cap = load_ports(build, "cmim")
    g = GEOM
    blocks, origins = [], {}

    def add(bid, dev, org, orientation=None, cellname=None):
        rec = load_ports(build, dev)
        blocks.append(cell_block(bid, "../dev/%s.gds" % dev,
                                 cellname or rec["cell_name"],
                                 orientation=orientation))
        origins[bid] = {"x": org[0], "y": org[1]}

    add("L1", "ind", (-SPIRAL_DX, 0.0), orientation="mirror_x")
    add("L2", "ind", (SPIRAL_DX, 0.0))
    add("C1", "cmim", CAP_ORG)
    # guard-ring substrate taps
    assert float(DEVICES["ptap_v"][2]["l"].rstrip("u")) == RING[3] - RING[1] - 2 * RING_W
    assert float(DEVICES["ptap_h"][2]["w"].rstrip("u")) == RING[2] - RING[0]
    add("TAPB", "ptap_h", (RING[0], RING[1]))
    add("TAPT", "ptap_h", (RING[0], RING[3] - RING_W))
    add("TAPL", "ptap_v", (RING[0], RING[1] + RING_W))
    add("TAPR", "ptap_v", (RING[2] - RING_W, RING[1] + RING_W))
    # via ladders (interconnect, not schematic devices)
    for bid, dev, org in g["VIA_STACKS"]:
        add(bid, dev, org)

    for bid, gds, cell in (("BANKP", "../vco_varbank_p.gds", "vco_varbank_p"),
                           ("BANKN", "../vco_varbank_n.gds", "vco_varbank_n"),
                           ("CORE", "../vco_core.gds", "vco_core"),
                           ("WIRING", "../vco_wiring.gds", "vco_wiring")):
        blocks.append(cell_block(bid, gds, cell))
        origins[bid] = {"x": 0.0, "y": 0.0}

    # Everything overlaps WIRING by construction, and the taps/ladders abut
    # their targets on purpose; declare it so the clearance advisory reports
    # only genuinely unintended proximity.
    ids = list(origins)
    for b in blocks:
        if b["id"] == "WIRING":
            b["abuts"] = [i for i in ids if i != "WIRING"]
    assert ind and cap

    return {
        "pdk": {"variant": "ihp-sg13g2", "root": "@PDK_ROOT@"},
        "blocks": blocks,
        "placement": {"strategy": "explicit", "order": ids, "origins_um": origins},
        "connectivity": [],
        "options": {"cell_name": "vco", "output": "@BUILD@/vco.gds"},
    }


# --------------------------------------------------------------------------
# derived geometry shared between wiring_request() and top_request()
# --------------------------------------------------------------------------
GEOM: dict = {}


def geometry(build):
    """Resolve every composed-frame coordinate the two requests both need."""
    ind = load_ports(build, "ind")
    cap = load_ports(build, "cmim")
    q1 = load_ports(build, "npn_le1")
    q3 = load_ports(build, "npn_le2")
    rte = load_ports(build, "rppd_rte")
    rre = load_ports(build, "rppd_rre")
    rref = load_ports(build, "rppd_rref")
    var_p = load_ports(build, "svaricap_p")
    vs_m1m3 = load_ports(build, "vs_m1_m3")

    L1 = (-SPIRAL_DX, 0.0)
    L2 = (SPIRAL_DX, 0.0)
    g = {
        "L1_LA": place(ind["ports"]["LA"], L1, mirror_x=True),
        "L1_LB": place(ind["ports"]["LB"], L1, mirror_x=True),
        "L2_LA": place(ind["ports"]["LA"], L2),
        "L2_LB": place(ind["ports"]["LB"], L2),
        "CAP_PLUS_BOX": pinbox(cap["ports"]["PLUS"], CAP_ORG),
        "CAP_MINUS_BOX": pinbox(cap["ports"]["MINUS"], CAP_ORG),
        "Q1_C_BOX": pinbox(q1["ports"]["C"], (Q1_ORG_X, Q12_Y)),
        "Q1_B_BOX": pinbox(q1["ports"]["B"], (Q1_ORG_X, Q12_Y)),
        "Q1_E_BOX": pinbox(q1["ports"]["E"], (Q1_ORG_X, Q12_Y)),
        "Q2_C_BOX": pinbox(q1["ports"]["C"], (Q2_ORG_X, Q12_Y), mirror_x=True),
        "Q2_B_BOX": pinbox(q1["ports"]["B"], (Q2_ORG_X, Q12_Y), mirror_x=True),
        "Q2_E_BOX": pinbox(q1["ports"]["E"], (Q2_ORG_X, Q12_Y), mirror_x=True),
        "Q3_C_BOX": pinbox(q3["ports"]["C"], Q3_ORG),
        "Q4_B_BOX": pinbox(q1["ports"]["B"], Q4_ORG),
        "Q4_C_BOX": pinbox(q1["ports"]["C"], Q4_ORG),
        "Q4_B": place(q1["ports"]["B"], Q4_ORG),
        "Q4_E": place(q1["ports"]["E"], Q4_ORG),
        "Q3_E": place(q3["ports"]["E"], Q3_ORG),
        "RTE_HI": place(rte["ports"]["P_HI"], RTE_ORG),
        "RRE_HI": place(rre["ports"]["P_HI"], RRE_ORG),
        "RREF_HI_BOX": pinbox(rref["ports"]["P_HI"], RREF_ORG),
    }
    g["VS_Q1C"] = place(q1["ports"]["C"], (Q1_ORG_X, Q12_Y))
    g["VS_Q2C"] = place(q1["ports"]["C"], (Q2_ORG_X, Q12_Y), mirror_x=True)
    g["VS_Q1B"] = place(q1["ports"]["B"], (Q1_ORG_X, Q12_Y))
    g["VS_Q2B"] = place(q1["ports"]["B"], (Q2_ORG_X, Q12_Y), mirror_x=True)
    g["VS_Q3C"] = place(q3["ports"]["C"], Q3_ORG)
    g["VS_RTE_LO"] = place(rte["ports"]["P_LO"], RTE_ORG)
    g["VS_RRE_LO"] = place(rre["ports"]["P_LO"], RRE_ORG)

    # ptap1's drawn Metal1 ring, inset from the Activ box it was placed on.
    g["RING_M1"] = [RING[0] + PTAP_M1_INSET[0], RING[1] + PTAP_M1_INSET[1],
                    RING[2] - PTAP_M1_INSET[0], RING[3] - PTAP_M1_INSET[1]]

    # VCTRL risers: outboard of each bank, 0.9 um clear of the nearest cell pad
    g["VCTRL_RISER_P"] = (BANK_P_X0 - 1.6, BANK_P_X0 - 0.9)
    g["VCTRL_RISER_N"] = (BANK_N_X0 + VAR_N * VAR_PITCH + 0.9,
                          BANK_N_X0 + VAR_N * VAR_PITCH + 1.6)
    wbox = var_p["ports"]["W"]["box_um"]
    g1box = var_p["ports"]["G1"]["box_um"]
    wy_mid = round(BANK_Y + (wbox[1] + wbox[3]) / 2.0, 4)
    # The inboard VCTRL tap drops the bottom Metal1 rail onto the Metal3 trunk
    # through a vs_m1_m3 ladder whose Metal1 pad is 0.70 um wide (measured
    # below).  That pad sits in the gap BETWEEN two adjacent SVaricap cells' gate
    # metal, which the PCell draws at local x in [G1.x0, G1.x1] on every cell.
    # Placing it at a round offset instead left 0.09 um to the neighbouring
    # cell's metal and cost two `metal1.space.1` violations (one per bank) --
    # so the position is derived from the measured G1 box and centred in the
    # gap, and the remaining clearance is asserted rather than assumed.
    m1pad = vs_m1m3["pads"]["Metal1"]   # measured, not transcribed
    gap_lo = g1box[2]                   # right edge of cell k's gate metal
    gap_hi = VAR_PITCH + g1box[0]       # left edge of cell k+1's gate metal
    vctrl_tap_dx = round((gap_lo + gap_hi) / 2.0, 4)
    _clear = (gap_hi - gap_lo - (m1pad[2] - m1pad[0])) / 2.0
    assert _clear >= M1_SP, (
        "VCTRL tap pad clears the SVaricap gate metal by only %.3f um "
        "(metal1.space is %.2f um); the PCell's G1 box, the via stack's "
        "Metal1 pad, or VAR_PITCH changed" % (_clear, M1_SP))
    for side, x0 in (("P", BANK_P_X0), ("N", BANK_N_X0)):
        rx0, rx1 = g["VCTRL_RISER_" + side]
        g["VS_VCTRL_%s1" % side] = (round(x0 + vctrl_tap_dx, 4),
                                    round(BANK_Y + (g1box[1] + g1box[3]) / 2.0, 4))
        g["VS_VCTRL_%s2" % side] = (round((rx0 + rx1) / 2.0, 4),
                                    round(BANK_Y - 1.0, 4))
        # one Metal1->Metal2 drop per cell, centred in that cell's own
        # 0.53 um-wide n-well landing pad
        g["BANK_VIAS_" + side] = [(round(x0 + k * VAR_PITCH + 0.285, 4), wy_mid)
                                  for k in range(VAR_N)]

    # The via-ladder instance list, shared with the top composition.
    g["VIA_STACKS"] = [
        ("VS_VDD_L1", "vs_tm1_tm2", (g["L1_LA"][0], VDD_VIA_Y)),
        ("VS_VDD_L2", "vs_tm1_tm2", (g["L2_LA"][0], VDD_VIA_Y)),
        ("VS_VDD_REF", "vs_m1_tm2", VDD_REF_VIA),
        ("VS_OUTP", "vs_m1_tm1", (-TANK_LADDER_X, sum(OUTP_TM1_Y) / 2.0)),
        ("VS_OUTN", "vs_m1_tm1", (TANK_LADDER_X, sum(OUTN_TM1_Y) / 2.0)),
        ("VS_OUTP_M23", "vs_m2_m3", (-TANK_LADDER_X, sum(OUTP_XC_M3_Y) / 2.0)),
        ("VS_OUTN_M23", "vs_m2_m3", (TANK_LADDER_X, sum(OUTN_XC_M3_Y) / 2.0)),
        ("VS_Q1C", "vs_m1_m2", g["VS_Q1C"]),
        ("VS_Q2C", "vs_m1_m2", g["VS_Q2C"]),
        ("VS_Q1B", "vs_m1_m3", g["VS_Q1B"]),
        ("VS_Q2B", "vs_m1_m3", g["VS_Q2B"]),
        ("VS_Q3C", "vs_m1_m2", g["VS_Q3C"]),
        ("VS_RTE_LO", "vs_m1_m3", g["VS_RTE_LO"]),
        ("VS_RRE_LO", "vs_m1_m3", g["VS_RRE_LO"]),
        ("VS_TE", "vs_m1_m2", g["RTE_HI"]),
        ("VS_RE", "vs_m1_m2", g["RRE_HI"]),
        ("VS_RING_RTE", "vs_m1_m3", (g["VS_RTE_LO"][0], RING[1] + RING_W / 2.0)),
        ("VS_RING_RRE", "vs_m1_m3", (g["VS_RRE_LO"][0], RING[1] + RING_W / 2.0)),
        ("VS_VCTRL_P1", "vs_m1_m3", g["VS_VCTRL_P1"]),
        ("VS_VCTRL_P2", "vs_m1_m3", g["VS_VCTRL_P2"]),
        ("VS_VCTRL_N1", "vs_m1_m3", g["VS_VCTRL_N1"]),
        ("VS_VCTRL_N2", "vs_m1_m3", g["VS_VCTRL_N2"]),
    ] + [("VS_VAR_%s%d" % (side, k), "vs_m1_m2_slim", xy)
         for side in ("P", "N")
         for k, xy in enumerate(g["BANK_VIAS_" + side])]
    GEOM.clear()
    GEOM.update(g)
    return g


# --------------------------------------------------------------------------
# schematic <-> layout mapping, emitted into the manifest
# --------------------------------------------------------------------------
DEVICE_MAP = [
    # (schematic instance, netlist card, PCell, generated block, net map)
    ("XL1", "inductor w=8.22e-6 s=3.74e-6 d=141.975e-6 nr_r=4",
     "SG13_dev/inductor2", "ind", {"la": "VDD", "lb": "OUTP", "sub": "0"}),
    ("XL2", "inductor w=8.22e-6 s=3.74e-6 d=141.975e-6 nr_r=4",
     "SG13_dev/inductor2", "ind", {"la": "VDD", "lb": "OUTN", "sub": "0"}),
    ("XC1", "cap_cmim w=3.65e-6 l=3.65e-6", "SG13_dev/cmim", "cmim",
     {"PLUS": "OUTP", "MINUS": "OUTN"}),
    ("XCVP1..16", "sg13_hv_svaricap w=3.74e-6 l=0.3e-6 Nx=1",
     "SG13_dev/SVaricap", "svaricap_p",
     {"G1": "VCTRL", "G2": "VCTRL", "W": "OUTP (n-well island)",
      "bn": "0 (p-substrate via guard ring; netlist says OUTP -- deliberate "
            "deviation, see PROVENANCE.md section 6)"}),
    ("XCVN1..16", "sg13_hv_svaricap w=3.74e-6 l=0.3e-6 Nx=1",
     "SG13_dev/SVaricap", "svaricap_n",
     {"G1": "VCTRL", "G2": "VCTRL", "W": "OUTN (n-well island)",
      "bn": "0 (p-substrate via guard ring; netlist says OUTN -- deliberate "
            "deviation, see PROVENANCE.md section 6)"}),
    ("XQ1", "npn13G2v Nx=1 El=1.0", "SG13_dev/npn13G2V", "npn_le1",
     {"C": "OUTP", "B": "OUTN", "E": "TAIL", "sub": "0"}),
    ("XQ2", "npn13G2v Nx=1 El=1.0", "SG13_dev/npn13G2V", "npn_le1",
     {"C": "OUTN", "B": "OUTP", "E": "TAIL", "sub": "0"}),
    ("XQ3", "npn13G2v Nx=1 El=2.0", "SG13_dev/npn13G2V", "npn_le2",
     {"C": "TAIL", "B": "NBIAS", "E": "TE", "sub": "0"}),
    ("XQ4", "npn13G2v Nx=1 El=1.0", "SG13_dev/npn13G2V", "npn_le1",
     {"C": "NBIAS", "B": "NBIAS", "E": "RE", "sub": "0"}),
    ("RTE", "2k", "SG13_dev/rppd (res_rppd)", "rppd_rte",
     {"P_HI": "TE", "P_LO": "0"}),
    ("RREF", "20.5k", "SG13_dev/rppd (res_rppd)", "rppd_rref",
     {"P_HI": "VDD", "P_LO": "NBIAS"}),
    ("RRE", "4k", "SG13_dev/rppd (res_rppd)", "rppd_rre",
     {"P_HI": "RE", "P_LO": "0"}),
    ("VSUP", "dc 3.3 (testbench source)", "-- no layout counterpart --", None, {}),
    ("VCT", "dc 1.65 (testbench source)", "-- no layout counterpart --", None, {}),
]

EXPECTED_DEVICE_COUNTS = {
    "SG13_dev/inductor2": 2,
    "SG13_dev/cmim": 1,
    "SG13_dev/SVaricap": 32,
    "SG13_dev/npn13G2V": 4,
    "SG13_dev/rppd": 3,
}


def main(argv):
    if len(argv) != 3:
        print("usage: floorplan.py <build-dir> <stage>", file=sys.stderr)
        return 2
    build, stage = argv[1], argv[2]
    reqdir = os.path.join(build, "req")
    os.makedirs(reqdir, exist_ok=True)

    if stage == "devices":
        out = {k: {"pcell": "SG13_dev/" + v[0], "kind": v[1], "params": v[2]}
               for k, v in DEVICES.items()}
        with open(os.path.join(build, "devices.json"), "w") as fh:
            json.dump(out, fh, indent=2, sort_keys=True)
            fh.write("\n")
        for k, v in DEVICES.items():
            print("%s\t%s\t%s" % (k, v[1], json.dumps(v[2])))
        return 0

    geometry(build)
    if stage == "requests":
        writes = {
            "varbank_p.json": varbank_request(build, "p"),
            "varbank_n.json": varbank_request(build, "n"),
            "core.json": core_request(build),
            "wiring.json": wiring_request(build),
            "top.json": top_request(build),
        }
        for name, doc in writes.items():
            with open(os.path.join(reqdir, name), "w") as fh:
                json.dump(doc, fh, indent=2)
                fh.write("\n")
            print("wrote %s" % os.path.join(reqdir, name))
        with open(os.path.join(build, "mapping.json"), "w") as fh:
            json.dump({"device_map": [
                {"schematic": a, "card": b, "pcell": c, "block": d, "nets": e}
                for (a, b, c, d, e) in DEVICE_MAP],
                "expected_device_counts": EXPECTED_DEVICE_COUNTS,
                "nets": NETS,
                "resistor_sizing": {
                    "device_class": "SG13_dev/rppd (res_rppd)",
                    "width_um": RPPD_W_UM,
                    "measured_law_ohm": "r(l_um) = %.4f*l + %.3f" % (
                        RPPD_OHM_PER_UM, RPPD_HEAD_OHM),
                    "lengths_um": {"RTE": L_RTE, "RRE": L_RRE, "RREF": L_RREF},
                    "nominal_ohm": {
                        "RTE": round(RPPD_OHM_PER_UM * L_RTE + RPPD_HEAD_OHM, 2),
                        "RRE": round(RPPD_OHM_PER_UM * L_RRE + RPPD_HEAD_OHM, 2),
                        "RREF": round(RPPD_OHM_PER_UM * L_RREF + RPPD_HEAD_OHM, 2)},
                }},
                fh, indent=2)
            fh.write("\n")
        print("wrote %s" % os.path.join(build, "mapping.json"))
        return 0

    print("unknown stage %r" % stage, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
