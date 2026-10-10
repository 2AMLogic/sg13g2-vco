"""Evidence-ownership tests for sim/oscillator-core/surrogate_bench.py (issue #191).

No PDK, no simulator: the bench's own reservation / publication code is driven
through the real sim/lib.sh reserve_record_id helper, and sb.main is run with
a fake ngspice that writes synthetic traces.  Timestamp and commit are frozen
(SIM_RECORD_TS / SIM_RECORD_SHA) so only the reservation decides uniqueness.

SCREENING ONLY -- the surrogate grades no specification row.
"""
import contextlib
import glob
import hashlib
import io
import math
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from unittest import mock

from _loader import load_module

sb = load_module("surrogate_bench", "sim/oscillator-core/surrogate_bench.py")
sur = sb.sur
TS, SHA = "20260101-000000", "abc1234"
FROZEN = {"SIM_RECORD_TS": TS, "SIM_RECORD_SHA": SHA}
STEP = 1e-12


def write(path, ts, vs):
    with open(path, "w") as fh:
        for t, v in zip(ts, vs):
            fh.write("%.9e %.9e\n" % (t, v))


def slurp(path, mode="r"):
    with open(path, mode) as fh:
        return fh.read()


def tree_digest(*dirs):
    """{relative path: sha256} of every file and directory under dirs."""
    out = {}
    for d in dirs:
        for base, subdirs, files in os.walk(d):
            for s in subdirs:
                out[os.path.join(base, s)] = "dir"
            for f in files:
                p = os.path.join(base, f)
                with open(p, "rb") as fh:
                    out[p] = hashlib.sha256(fh.read()).hexdigest()
    return out


class Base(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix="t191-")
        self.addCleanup(shutil.rmtree, self.d, True)
        env = mock.patch.dict(os.environ, FROZEN)
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("SIM_RECORD_SUFFIX", None)

    def layout(self, custom=False):
        if custom:  # arbitrary custom dirs, not <R>/records + <R>/netlist-snapshots
            return os.path.join(self.d, "rec"), os.path.join(self.d, "elsewhere", "snaps")
        exp = os.path.join(self.d, "exp")
        return os.path.join(exp, "records"), os.path.join(exp, "netlist-snapshots")

    def plant(self, rec, snap, suffix="deadbeef", point="corrected"):
        """Pre-existing evidence under the id a frozen SIM_RECORD_SUFFIX would mint."""
        base = "%s-%s-%s-surrogate-%s" % (TS, SHA, suffix, point)
        os.makedirs(rec, exist_ok=True)
        os.makedirs(os.path.join(snap, base))
        for p, text in ((os.path.join(rec, base + ".md"), "sentinel-md\n"),
                        (os.path.join(rec, base + ".csv"), "sentinel,csv\n1,2\n"),
                        (os.path.join(snap, base, "surrogate_%s.spice" % point), "* sentinel deck\n"),
                        (os.path.join(snap, base, "surrogate_%s.log" % point), "sentinel log\n")):
            with open(p, "w") as fh:
                fh.write(text)
        return base

    def run_bench(self, rec, snap, point="corrected"):
        """sb.main with a fake ngspice; returns (rc or exception, stdout, stderr, ngspice calls)."""
        real_run = subprocess.run
        real_mkdtemp = tempfile.mkdtemp
        scratch = os.path.join(self.d, "scratch")
        os.makedirs(scratch, exist_ok=True)
        n = int(round(5e-9 / STEP))
        ts = [i * STEP for i in range(n + 1)]
        calls = []

        def fake_run(cmd, cwd=None, **kw):
            if cmd[0] != "ngspice":
                return real_run(cmd, **kw) if cwd is None else real_run(cmd, cwd=cwd, **kw)
            calls.append(cmd)
            pre = os.path.join(cwd, "w")
            write(pre + "_vdiff", ts, [0.4 * math.sin(2 * math.pi * 3e9 * t) for t in ts])
            for k in ("p1", "p16", "n1", "n16"):
                write("%s_vrec_%s" % (pre, k), ts, [1.65 + 0.5 * math.sin(2 * math.pi * 3e9 * t) for t in ts])
            return subprocess.CompletedProcess(cmd, 0, "", "")

        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sb, "models_dir", lambda: "/nonexistent"), \
                mock.patch.object(sb, "ngspice_version", lambda: "ngspice-fake"), \
                mock.patch.object(sb.subprocess, "run", fake_run), \
                mock.patch.object(sb.tempfile, "mkdtemp",
                                  lambda prefix="": real_mkdtemp(prefix=prefix, dir=scratch)), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                res = sb.main(["--point", point, "--allow-dirty", "--records-dir", rec, "--snapshots-dir", snap])
            except sur.SurrogateError as e:
                res = e
        return res, out.getvalue(), err.getvalue(), calls


class Allocation(Base):
    def test_same_point_frozen_ts_commit_distinct_namespaces(self):
        for custom in (False, True):
            rec, snap = self.layout(custom)
            a = sb.reserve_publication(rec, snap, "pre79")
            b = sb.reserve_publication(rec, snap, "pre79")
            self.assertNotEqual(a["reserved_id"], b["reserved_id"])
            for o in (a, b):
                self.assertTrue(o["record_id"].startswith("%s-%s-" % (TS, SHA)), o)
                self.assertTrue(o["record_id"].endswith("-surrogate-pre79"), o)
                self.assertTrue(os.path.isdir(os.path.join(o["root"], "corners", o["reserved_id"])))
            self.assertFalse({a[k] for k in ("md", "csv", "snap", "deck", "log")}
                             & {b[k] for k in ("md", "csv", "snap", "deck", "log")})
            # reservation alone writes no evidence
            self.assertFalse(os.path.exists(rec) and os.listdir(rec))
            self.assertFalse(os.path.exists(snap) and os.listdir(snap))

    def test_default_dirs_reserve_in_the_experiment_namespace(self):
        root = sb.reservation_root(os.path.join(sb.HERE, "records"))
        self.assertEqual(root, os.path.realpath(sb.HERE))

    def test_concurrent_allocations_never_share_paths(self):
        rec, snap = self.layout()
        got, errs = [], []

        def go():
            try:
                got.append(sb.reserve_publication(rec, snap, "corrected"))
            except Exception as e:  # pragma: no cover - reported below
                errs.append(e)
        th = [threading.Thread(target=go) for _ in range(4)]
        for t in th:
            t.start()
        for t in th:
            t.join()
        self.assertEqual(errs, [])
        paths = [o[k] for o in got for k in ("md", "csv", "snap")]
        self.assertEqual(len(got), 4)
        self.assertEqual(len(set(paths)), len(paths))

    def test_custom_dir_collision_is_skipped(self):
        # The helper only sees <root>/records and <root>/netlist-snapshots; the
        # bench must itself reject an id already used in custom dirs.
        rec, snap = self.layout(custom=True)
        planted = self.plant(rec, snap)
        with mock.patch.dict(os.environ, {"SIM_RECORD_SUFFIX": "deadbeef"}):
            o = sb.reserve_publication(rec, snap, "corrected")
        self.assertNotEqual(o["record_id"], planted)
        self.assertNotIn("deadbeef", o["reserved_id"])

    def test_snapshot_only_collision_in_custom_dir_is_skipped(self):
        rec, snap = self.layout(custom=True)
        os.makedirs(os.path.join(snap, "%s-%s-cafe0001-surrogate-pre79" % (TS, SHA)))
        with mock.patch.dict(os.environ, {"SIM_RECORD_SUFFIX": "cafe0001"}):
            o = sb.reserve_publication(rec, snap, "pre79")
        self.assertNotIn("cafe0001", o["reserved_id"])


class BenchIntegration(Base):
    def check_collision_preserves_sentinels(self, custom):
        rec, snap = self.layout(custom)
        planted = self.plant(rec, snap)
        before = tree_digest(rec, snap)
        with mock.patch.dict(os.environ, {"SIM_RECORD_SUFFIX": "deadbeef"}):
            rc, out, err, calls = self.run_bench(rec, snap)
        self.assertEqual(rc, 0, err)
        after = tree_digest(rec, snap)
        for p, h in before.items():
            self.assertEqual(after.get(p), h, "pre-existing evidence changed: %s" % p)
        new_md = [p for p in glob.glob(os.path.join(rec, "*.md")) if planted not in p]
        new_csv = [p for p in glob.glob(os.path.join(rec, "*.csv")) if planted not in p]
        self.assertEqual((len(new_md), len(new_csv)), (1, 1))
        base = os.path.basename(new_md[0])[:-3]
        self.assertTrue(base.startswith("%s-%s-" % (TS, SHA)) and base.endswith("-surrogate-corrected"))
        self.assertTrue(os.path.isfile(os.path.join(snap, base, "surrogate_corrected.spice")))
        self.assertTrue(os.path.isfile(os.path.join(snap, base, "surrogate_corrected.log")))
        text = slurp(new_md[0]) + slurp(new_csv[0])
        self.assertIn("SCREENING ONLY", text)
        self.assertIn("netlist-snapshots/%s/" % base, text)

    def test_collision_standard_layout_sentinels_byte_identical(self):
        self.check_collision_preserves_sentinels(custom=False)

    def test_collision_custom_dirs_sentinels_byte_identical(self):
        self.check_collision_preserves_sentinels(custom=True)

    def test_two_runs_same_point_same_second_both_published(self):
        rec, snap = self.layout()
        for _ in range(2):
            rc, out, err, calls = self.run_bench(rec, snap)
            self.assertEqual(rc, 0, err)
        self.assertEqual(len(glob.glob(os.path.join(rec, "*-surrogate-corrected.csv"))), 2)
        self.assertEqual(len(os.listdir(snap)), 2)

    def assert_refused_before_any_write(self, res, calls, rec, snap):
        self.assertIsInstance(res, sb.PublicationError)
        self.assertIsInstance(res, sur.SurrogateError)  # CLI maps this to a nonzero exit
        self.assertEqual(calls, [], "ngspice must not start without a reservation")
        for d in (rec, snap):
            self.assertFalse(os.path.exists(d) and os.listdir(d), "%s written" % d)
        self.assertEqual(glob.glob(os.path.join(self.d, "scratch", "*")), [])

    def test_reservation_failure_unwritable_namespace(self):
        rec = "/dev/null/nope/records"
        snap = os.path.join(self.d, "snaps")
        res, out, err, calls = self.run_bench(rec, snap)
        self.assert_refused_before_any_write(res, calls, rec, snap)
        self.assertIn("reservation failed", str(res))

    def test_reservation_failure_helper_unavailable(self):
        rec, snap = self.layout()
        with mock.patch.object(sb, "LIB_SH", os.path.join(self.d, "missing-lib.sh")):
            res, out, err, calls = self.run_bench(rec, snap)
        self.assert_refused_before_any_write(res, calls, rec, snap)

    def test_reservation_failure_garbage_id(self):
        rec, snap = self.layout()
        fake_lib = os.path.join(self.d, "lib.sh")
        with open(fake_lib, "w") as fh:
            fh.write("reserve_record_id() { echo ''; return 0; }\n")
        with mock.patch.object(sb, "LIB_SH", fake_lib):
            res, out, err, calls = self.run_bench(rec, snap)
        self.assert_refused_before_any_write(res, calls, rec, snap)

    def test_misconfigured_reservation_cannot_truncate(self):
        # Reservation integration broken so that it hands out an id whose paths
        # already exist: exclusive publication still refuses, nothing changes.
        for custom in (False, True):
            rec, snap = self.layout(custom)
            planted = self.plant(rec, snap, suffix="0000000%d" % custom)
            before = tree_digest(rec, snap)
            rid = planted[:-len("-surrogate-corrected")]
            with mock.patch.object(sb, "_reserve_id", lambda root, first: rid), \
                    mock.patch.object(sb, "_taken", lambda *a: False):
                res, out, err, calls = self.run_bench(rec, snap)
            self.assertIsInstance(res, sb.PublicationError)
            self.assertIn("refusing to overwrite", str(res))
            self.assertEqual(tree_digest(rec, snap), before)


class Publish(Base):
    def paths(self):
        rec, snap = self.layout(custom=True)
        return sb.reserve_publication(rec, snap, "pre79")

    def test_exclusive_race_rolls_back_only_own_files(self):
        p = self.paths()
        os.makedirs(os.path.dirname(p["csv"]), exist_ok=True)
        real_open = open
        state = {"n": 0}

        def racing_open(path, mode="r", *a, **kw):
            # a competitor creates the CSV between the pre-check and our create
            if path == p["csv"] and "x" in mode and not state["n"]:
                state["n"] = 1
                with real_open(path, "w") as fh:
                    fh.write("competitor\n")
            return real_open(path, mode, *a, **kw)
        with mock.patch("builtins.open", racing_open):
            with self.assertRaises(sb.PublicationError):
                sb.publish(p, b"deck", b"log", "md", {"a": "1"})
        self.assertEqual(slurp(p["csv"]), "competitor\n")
        for k in ("md", "deck", "log", "snap"):
            self.assertFalse(os.path.exists(p[k]), k)

    def test_publish_writes_all_artifacts_once(self):
        p = self.paths()
        sb.publish(p, b"deck", b"log", "md", {"label": sur.LABEL})
        self.assertEqual(slurp(p["deck"], "rb"), b"deck")
        self.assertEqual(slurp(p["log"], "rb"), b"log")
        self.assertIn("SCREENING ONLY", slurp(p["csv"]))
        with self.assertRaises(sb.PublicationError):
            sb.publish(p, b"other", b"other", "other", {"label": "x"})
        self.assertEqual(slurp(p["deck"], "rb"), b"deck")


if __name__ == "__main__":
    unittest.main()
