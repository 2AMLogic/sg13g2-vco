"""Known-answer tests for layout/scripts/floorplan.py geometry() (stdlib
unittest only).

geometry() needs no IHP deck and no generated stream: every measured input
it reads is a build/dev/<id>.ports.json file, so the tests synthesize that
tree in a temp dir -- the committed vs_m1_tm2 / vs_m3_tm2 pad boxes from
layout/vco_manifest.json verbatim, everything else stubbed -- and exercise
the ground-pin and VCTRL-pin placement arithmetic of issue #439: the pad
edges the derivation reads, and the rejections the assertions own.
Nothing here needs klayout, klt or the PDK, and nothing is written under
layout/.
"""
import copy
import json
import os
import tempfile
import unittest

from _loader import load_module

floorplan = load_module("vco_floorplan", "layout/scripts/floorplan.py")

# The committed vs_m1_tm2 / vs_m3_tm2 pad boxes (layout/vco_manifest.json,
# devices.vs_m1_tm2.pads / vs_m3_tm2.pads -- recorded for the stream the
# issue reproduces against).  Only the pads geometry() reads are carried;
# the intermediate Metal2..TopMetal1 boxes are irrelevant to placement.
VS_M1_TM2_PADS = {
    "Metal1": [-0.35, -0.31, 0.35, 0.31],
    "TopMetal2": [-1.93, -1.93, 1.93, 1.93],
}
VS_M3_TM2_PADS = {
    "TopMetal2": [-1.93, -1.93, 1.93, 1.93],
}
VS_M1_M3_PADS = {
    "Metal1": [-0.35, -0.31, 0.35, 0.31],
}

# SVaricap stubs: G1's local x span drives the VCTRL tap's gate-metal
# clearance assert (0.475 um >= metal1.space with these boxes); W only
# feeds unasserted riser positions.
VAR_PORTS = {
    "W": {"box_um": [-0.265, -0.265, 0.265, 0.265]},
    "G1": {"box_um": [0.5, -0.15, 1.0, 0.15]},
}


def _port(name, x=0.0, y=0.0, box=(-0.1, -0.1, 0.1, 0.1)):
    return {"name": name, "x_um": x, "y_um": y, "width_um": 0.2,
            "direction_deg": 0.0, "layer": "8/0", "box_um": list(box)}


def _terminals(names):
    return {n: _port(n) for n in names}


def make_build(root, gnd_tm2=None, vctrl_tm2=None):
    """A synthetic build/dev tree whose pins/pads geometry() can resolve."""
    b = os.path.join(root, "build")
    recs = {
        "ind": {"ports": _terminals(["LA", "LB"])},
        "cmim": {"ports": _terminals(["PLUS", "MINUS"])},
        "npn_le1": {"ports": _terminals(["C", "B", "E"])},
        "npn_le2": {"ports": _terminals(["C", "B", "E"])},
        "rppd_rte": {"ports": _terminals(["P_HI", "P_LO"])},
        "rppd_rre": {"ports": _terminals(["P_HI", "P_LO"])},
        "rppd_rref": {"ports": _terminals(["P_HI", "P_LO"])},
        "svaricap_p": {"ports": VAR_PORTS},
        "vs_m1_m3": {"pads": copy.deepcopy(VS_M1_M3_PADS)},
        "vs_m1_tm2": {"pads": copy.deepcopy(VS_M1_TM2_PADS)},
        "vs_m3_tm2": {"pads": copy.deepcopy(VS_M3_TM2_PADS)},
    }
    if gnd_tm2 is not None:
        recs["vs_m1_tm2"]["pads"]["TopMetal2"] = list(gnd_tm2)
    if vctrl_tm2 is not None:
        recs["vs_m3_tm2"]["pads"]["TopMetal2"] = list(vctrl_tm2)
    for dev_id, rec in recs.items():
        p = os.path.join(b, "dev", dev_id + ".ports.json")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            json.dump(rec, fh)
    return b


class GeometryPinTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name

    def test_committed_pads_reproduce_recorded_origins(self):
        b = make_build(self.root)
        g = floorplan.geometry(b)
        # the origins PROVENANCE.md sections 15/17 record
        self.assertEqual(g["VS_GND_PIN"], (66.0, -104.07))
        self.assertEqual(g["VS_VCTRL_PIN"], (-66.0, -57.0))
        # both placements are shared with the instance list verbatim
        self.assertIn(("VS_GND_PIN", "vs_m1_tm2", g["VS_GND_PIN"]),
                      g["VIA_STACKS"])
        self.assertIn(("VS_VCTRL_PIN", "vs_m3_tm2", g["VS_VCTRL_PIN"]),
                      g["VIA_STACKS"])

    def test_asymmetric_ground_pad_bottom_drives_height(self):
        # issue #439's reproduction: the pad's local bottom moves
        # -1.93 -> -2.03.  Reading the pad's *bottom* edge puts the centre
        # at -103.97 and the placed bottom exactly at the ring edge
        # (-106.00) while the Metal1 bite stays 0.13 um >= 0.10 (geometry
        # returning is that assert passing); reading the top edge, as the
        # pre-#439 code did, would leave y = -104.07 and the pad 0.10 um
        # past the edge with every assertion green.
        pad = [-1.93, -2.03, 1.93, 1.93]
        b = make_build(self.root, gnd_tm2=pad)
        g = floorplan.geometry(b)
        self.assertEqual(g["VS_GND_PIN"], (66.0, -103.97))
        self.assertEqual(round(g["VS_GND_PIN"][1] + pad[1], 4),
                         floorplan.GND_PIN_Y0)
        bite = round((floorplan.RING[1] + floorplan.RING_W
                      - floorplan.PTAP_M1_INSET[1])
                     - (g["VS_GND_PIN"][1] + VS_M1_TM2_PADS["Metal1"][1]), 4)
        self.assertGreaterEqual(bite, 0.10)

    def test_ground_pad_left_edge_escape_rejected(self):
        # only the left side extended across the bottom bar's strict limit
        pad = [-200.0, -1.93, 1.93, 1.93]
        b = make_build(self.root, gnd_tm2=pad)
        with self.assertRaises(AssertionError) as cm:
            floorplan.geometry(b)
        self.assertIn("escapes the bottom bar's Activ box",
                      str(cm.exception))

    def test_ground_pad_right_edge_escape_rejected(self):
        pad = [-1.93, -1.93, 200.0, 1.93]
        b = make_build(self.root, gnd_tm2=pad)
        with self.assertRaises(AssertionError) as cm:
            floorplan.geometry(b)
        self.assertIn("escapes the bottom bar's Activ box",
                      str(cm.exception))

    def test_vctrl_pad_bottom_extension_rejected(self):
        # the VCTRL stack's placement is trunk-centred, not pad-derived, so
        # its own assert is the live leg: a pad extended below the strap's
        # outboard end (placed bottom -107.0 < VCTRL_PIN_Y0 = -106.0) must
        # fail geometry()
        pad = [-1.93, -50.0, 1.93, 1.93]
        b = make_build(self.root, vctrl_tm2=pad)
        with self.assertRaises(AssertionError) as cm:
            floorplan.geometry(b)
        self.assertIn("VCTRL-pin stack's TopMetal2 pad passes",
                      str(cm.exception))


if __name__ == "__main__":
    unittest.main()
