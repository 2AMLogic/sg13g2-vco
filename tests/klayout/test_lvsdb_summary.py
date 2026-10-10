"""Known-answer tests for layout/scripts/lvsdb_summary.py.

A tiny NMOS layout is extracted with klayout's built-in MOS3 extractor and
compared against a hand-built reference netlist, then written as a real
.lvsdb -- the same file format IHP's run_lvs.py produces. The script is run as
a subprocess (isolated mode) like its production use.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

import klayout.db as kdb

from _macro import ROOT

SCRIPT = os.path.join(ROOT, "layout", "scripts", "lvsdb_summary.py")


def write_lvsdb(path, ref_devices):
    ly = kdb.Layout()
    ly.dbu = 0.001
    top = ly.create_cell("TOP")
    poly, diff = ly.layer(1, 0), ly.layer(2, 0)
    top.shapes(diff).insert(kdb.Box(0, 0, 1000, 3000))
    top.shapes(poly).insert(kdb.Box(-500, 1000, 1500, 2000))
    lvs = kdb.LayoutVsSchematic(kdb.RecursiveShapeIterator(ly, top, []))
    rp, rd = lvs.make_layer(poly, "poly"), lvs.make_layer(diff, "diff")
    gate, sd = rp & rd, rd - rp
    lvs.extract_devices(kdb.DeviceExtractorMOS3Transistor("NMOS"),
                        {"SD": sd, "G": gate, "P": rp})
    for layer in (sd, rp, gate):
        lvs.connect(layer)
    lvs.extract_netlist()

    ref = kdb.Netlist()
    cls = kdb.DeviceClassMOS3Transistor()
    cls.name = "NMOS"
    ref.add(cls)
    circuit = kdb.Circuit()
    circuit.name = "TOP"
    ref.add(circuit)
    nets = {t: circuit.create_net(t.lower() + "n") for t in ("S", "G", "D")}
    for i in range(ref_devices):
        dev = circuit.create_device(cls, "M%d" % (i + 1))
        dev.set_parameter("L", 1.0)
        dev.set_parameter("W", 1.0)
        for t, net in nets.items():
            dev.connect_terminal(t, net)
    lvs.reference = ref
    lvs.compare(kdb.NetlistComparer())
    lvs.write(path)


def summarize(path):
    return subprocess.run([sys.executable, "-I", SCRIPT, path],
                          capture_output=True, text=True)


class LvsdbSummaryTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = self._tmp.name

    def test_matching_netlists(self):
        p = os.path.join(self.dir, "ok.lvsdb")
        write_lvsdb(p, 1)
        r = summarize(p)
        self.assertEqual(r.returncode, 0, r.stderr)
        out = json.loads(r.stdout)
        self.assertEqual(out["verdict"], "match")
        circ = out["circuits"][0]
        self.assertEqual((circ["layout"], circ["reference"]), ("TOP", "TOP"))
        self.assertEqual(circ["devices"], {"layout": {"NMOS": 1}, "reference": {"NMOS": 1}})
        self.assertEqual(circ["device_pairs"]["matched"], 1)
        self.assertEqual(circ["device_pairs"]["not_matched"], [])

    def test_mismatching_netlists(self):
        p = os.path.join(self.dir, "bad.lvsdb")
        write_lvsdb(p, 2)       # reference has an extra device
        r = summarize(p)
        self.assertEqual(r.returncode, 0, r.stderr)   # the verdict is data, not exit code
        out = json.loads(r.stdout)
        self.assertEqual(out["verdict"], "mismatch")
        self.assertEqual(out["circuits"][0]["devices"],
                         {"layout": {"NMOS": 1}, "reference": {"NMOS": 2}})

    def test_compare_log_long_form(self):
        # LayoutVsSchematic.write's own form: the comparer's ambiguity warnings.
        p = os.path.join(self.dir, "ok.lvsdb")
        write_lvsdb(p, 1)
        out = json.loads(summarize(p).stdout)
        self.assertTrue(out["compare_log"])
        self.assertTrue(all(e["severity"] == "warning" and "ambiguous" in e["message"]
                            for e in out["compare_log"]))

    def test_compare_log_short_form(self):
        # The form KLayout's LVS DSL (IHP's runset) writes, with the strict
        # top-port check's finding; the database must still read back.
        p = os.path.join(self.dir, "ok.lvsdb")
        write_lvsdb(p, 1)
        text = open(p).read()
        head, xref = text.split("\nxref(\n", 1)
        xref = xref.replace("  log(\n", "  log(\n   M(E B('Port mismatch \\'LA,VDD\\' vs. \\'VDD\\''))\n", 1)
        open(p, "w").write(head + "\nZ(\n" + xref)
        r = summarize(p)
        self.assertEqual(r.returncode, 0, r.stderr)
        log = json.loads(r.stdout)["compare_log"]
        self.assertIn({"severity": "error", "message": "Port mismatch 'LA,VDD' vs. 'VDD'"}, log)

    def test_usage_error(self):
        r = subprocess.run([sys.executable, "-I", SCRIPT],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("lvsdb_summary.py", r.stderr)


if __name__ == "__main__":
    unittest.main()
