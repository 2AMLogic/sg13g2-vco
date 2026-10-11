"""Record-ownership tests for the EM comparison writer (issue #225).

No PDK, openEMS or ngspice: only bash (sim/lib.sh) and numpy are needed.
"""
import concurrent.futures
import contextlib
import io
import os
import sys
import tempfile
import unittest
from unittest import mock

import _em  # noqa: F401  (puts the EM scripts dir on sys.path)

ca = _em.load("compare_analytic")

TS, SHA = "20261011-010203", "abc1234"


class Base(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.root = os.path.join(self._td.name, "em")
        os.makedirs(os.path.join(self.root, "results"))
        env = mock.patch.dict(os.environ, {"SIM_RECORD_TS": TS, "SIM_RECORD_SHA": SHA})
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("SIM_RECORD_SUFFIX", None)

    def corners(self):
        d = os.path.join(self.root, "corners")
        return sorted(os.listdir(d)) if os.path.isdir(d) else []

    def run_main(self):
        argv = ["compare_analytic.py", "--dir", self.root, "--analytic", "a", "--fitted", "f"]
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, "argv", argv), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            return ca.main(), err.getvalue()


class TestAllocation(Base):
    def test_frozen_clock_sequential_ids_distinct(self):
        ids = [ca.reserve_record_id(self.root) for _ in range(5)]
        self.assertEqual(len(set(ids)), 5)
        for i in ids:
            self.assertTrue(i.startswith("%s-%s-" % (TS, SHA)))
        self.assertEqual(self.corners(), sorted(ids))

    def test_frozen_clock_concurrent_ids_distinct(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
            ids = list(ex.map(lambda _: ca.reserve_record_id(self.root), range(12)))
        self.assertEqual(len(set(ids)), 12)

    def test_historical_flat_evidence_and_existing_reservation_survive(self):
        rec = os.path.join(self.root, "records")
        os.makedirs(rec)
        hist = "%s-%s-deadbeef" % (TS, SHA)
        sentinels = {}
        for suffix in (".md", "-env.json", "-em-vs-analytic.csv"):
            p = os.path.join(rec, hist + suffix)
            with open(p, "w") as fh:
                fh.write("SENTINEL" + suffix)
            sentinels[p] = "SENTINEL" + suffix
        held = "%s-%s-cafe0001" % (TS, SHA)
        os.makedirs(os.path.join(self.root, "corners", held))
        keep = os.path.join(self.root, "corners", held, "k")
        with open(keep, "w") as fh:
            fh.write("KEEP")
        sentinels[keep] = "KEEP"
        for forced in (hist.rsplit("-", 1)[1], held.rsplit("-", 1)[1]):
            with mock.patch.dict(os.environ, {"SIM_RECORD_SUFFIX": forced}):
                rid = ca.reserve_record_id(self.root)
            self.assertNotIn(rid, (hist, held))
        for p, data in sentinels.items():
            with open(p) as fh:
                self.assertEqual(fh.read(), data)

    def test_legacy_flat_id_without_suffix_is_not_reusable(self):
        # historical ids had no suffix; the new ones are strictly longer, so
        # a new id can never equal or prefix-collide-overwrite a flat record.
        rec = os.path.join(self.root, "records")
        os.makedirs(rec)
        with open(os.path.join(rec, "%s-%s.md" % (TS, SHA)), "w") as fh:
            fh.write("OLD")
        rid = ca.reserve_record_id(self.root)
        self.assertNotEqual(rid, "%s-%s" % (TS, SHA))


class TestMain(Base):
    def test_reservation_failure_opens_nothing(self):
        with mock.patch.object(ca, "preflight", return_value=({}, {}, [])), \
                mock.patch.object(ca, "reserve_record_id", side_effect=ca.ReservationError("boom")):
            rc, err = self.run_main()
        self.assertEqual(rc, 1)
        self.assertIn("boom", err)
        self.assertFalse(os.path.exists(os.path.join(self.root, "records")))
        self.assertFalse(os.path.exists(os.path.join(self.root, "results", "latest_record_id.txt")))

    def test_no_record_dir_before_ownership_and_failed_run_keeps_id(self):
        seen = {}
        real = ca.reserve_record_id

        def spy(root):
            seen["records_before"] = os.path.exists(os.path.join(root, "records"))
            seen["id"] = real(root)
            return seen["id"]

        latest = os.path.join(self.root, "results", "latest_record_id.txt")
        with open(latest, "w") as fh:
            fh.write("PREVIOUS\n")
        with mock.patch.object(ca, "preflight", return_value=({}, {}, [])), \
                mock.patch.object(ca, "reserve_record_id", spy), \
                mock.patch.object(ca, "run_ngspice", side_effect=RuntimeError("ngspice died")):
            with self.assertRaises(RuntimeError):
                self.run_main()
        self.assertFalse(seen["records_before"])
        self.assertEqual(self.corners(), [seen["id"]])       # id stays reserved
        with open(latest) as fh:
            self.assertEqual(fh.read(), "PREVIOUS\n")        # pointer not advanced
        recs = os.path.join(self.root, "records")
        self.assertEqual(os.listdir(recs) if os.path.isdir(recs) else [], [])
        # a later run cannot be handed the failed run's id, even with frozen clock
        with mock.patch.dict(os.environ, {"SIM_RECORD_SUFFIX": seen["id"].rsplit("-", 1)[1]}):
            self.assertNotEqual(ca.reserve_record_id(self.root), seen["id"])


if __name__ == "__main__":
    unittest.main()
