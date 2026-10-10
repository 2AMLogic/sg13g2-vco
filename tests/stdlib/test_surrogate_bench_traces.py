"""Trace-validation and orchestration tests for sim/oscillator-core/surrogate_bench.py
(issue #192). No PDK, no simulator: synthetic wrdata traces and a fake ngspice.

SCREENING ONLY -- the surrogate grades no specification row.
"""
import contextlib
import glob
import io
import math
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

from _loader import load_module

sb = load_module("surrogate_bench", "sim/oscillator-core/surrogate_bench.py")
sur = sb.sur
STEP = 1e-12


def grid(t_end=5e-9, step=STEP):
    n = int(round(t_end / step))
    return [i * step for i in range(n + 1)]


def write(path, ts, vs, fmt="%.9e %.9e\n"):
    with open(path, "w") as fh:
        for t, v in zip(ts, vs):
            fh.write(fmt % (t, v))


class TraceBase(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix="t192-")
        self.addCleanup(shutil.rmtree, self.d, True)
        self.ts = grid()
        self.p = os.path.join(self.d, "w")

    def put(self, name, vs, ts=None):
        write("%s_%s" % (self.p, name), self.ts if ts is None else ts, vs)

    def put_all(self, vrec=1.65, bad=None):
        self.put("vdiff", [0.1 * math.sin(i * 0.3) for i in range(len(self.ts))])
        for k in ("p1", "p16", "n1", "n16"):
            self.put("vrec_" + k, [vrec + 0.5 * math.sin(i * 0.3) for i in range(len(self.ts))])


class ReadTrace(TraceBase):
    def check_rejects(self, text):
        f = self.p + "_x"
        with open(f, "w") as fh:
            fh.write(text)
        with self.assertRaises(sb.TraceError):
            sb.trace_extrema(f)

    def body(self, vs, ts=None):
        ts = self.ts if ts is None else ts
        return "".join("%.9e %s\n" % (t, v) for t, v in zip(ts, vs))

    def vals(self):
        return ["1.0"] * len(self.ts)

    def test_valid_extrema_unchanged(self):
        vs = [1.0 + 0.5 * math.sin(i * 0.01) for i in range(len(self.ts))]
        write(self.p + "_x", self.ts, vs)
        lo, hi, n = sb.trace_extrema(self.p + "_x")
        self.assertEqual(n, len(vs))
        self.assertAlmostEqual(lo, min(vs), places=8)
        self.assertAlmostEqual(hi, max(vs), places=8)

    def test_nan_mid_trace(self):
        v = self.vals(); v[2500] = "nan"
        self.check_rejects(self.body(v))

    def test_nan_mid_trace_would_have_fooled_min_max(self):
        self.assertEqual((min([1.0, float("nan"), 2.0]), max([1.0, float("nan"), 2.0])), (1.0, 2.0))

    def test_all_nan(self):
        self.check_rejects(self.body(["nan"] * len(self.ts)))

    def test_inf_and_overflow(self):
        for tok in ("inf", "-inf", "1e999", "-1e999"):
            v = self.vals(); v[10] = tok
            self.check_rejects(self.body(v))

    def test_malformed_rows(self):
        v = self.vals()
        body = self.body(v).splitlines()
        self.check_rejects("\n".join(body[:100] + ["7.0e-10"] + body[100:]) + "\n")  # short row
        self.check_rejects("\n".join(body[:100] + ["a b"] + body[100:]) + "\n")      # non-numeric
        self.check_rejects("\n".join(body[:100] + ["1 2 3"] + body[100:]) + "\n")    # extra column

    def test_bad_timestamps(self):
        ts = list(self.ts); ts[50] = float("nan")
        self.check_rejects(self.body(self.vals(), ts))
        ts = list(self.ts); ts[50] = float("inf")
        self.check_rejects(self.body(self.vals(), ts))
        self.check_rejects(self.body(self.vals()).replace("0.000000000e+00", "zero", 1))

    def test_decreasing_and_duplicate_times(self):
        ts = list(self.ts); ts[100] = ts[99]
        self.check_rejects(self.body(self.vals(), ts))
        ts = list(self.ts); ts[100], ts[101] = ts[101], ts[100]
        self.check_rejects(self.body(self.vals(), ts))

    def test_truncated_coverage_and_late_start_and_gap(self):
        n = len(self.ts)
        self.check_rejects(self.body(self.vals()[:n // 2], self.ts[:n // 2]))      # truncated end
        self.check_rejects(self.body(self.vals()[100:], self.ts[100:]))            # late start
        ts = self.ts[:1000] + self.ts[1100:]                                       # dropped rows
        self.check_rejects(self.body(["1.0"] * len(ts), ts))
        self.check_rejects("")

    def test_coverage_tolerance_boundary(self):
        ts = self.ts[:-1]  # ends one TMAX-step (1 ps) short: within the 2 ps tolerance
        write(self.p + "_x", ts, [1.0] * len(ts))
        self.assertEqual(sb.trace_extrema(self.p + "_x")[2], len(ts))

    def test_grid_mismatch_between_probes(self):
        self.put_all()
        ts2 = [t + 1e-13 for t in self.ts]
        write(self.p + "_vrec_n16", ts2, [1.0] * len(ts2))
        with self.assertRaises(sb.TraceError):
            sb.validated_vrec_extrema(self.p)

    def test_all_nan_later_probe_rejected(self):
        self.put_all()
        self.put("vrec_n16", [float("nan")] * len(self.ts))
        with self.assertRaises(sb.TraceError):
            sb.validated_vrec_extrema(self.p)

    def test_in_domain_and_out_of_domain_classification(self):
        self.put_all(1.65)
        lo, hi = sb.validated_vrec_extrema(self.p)
        self.assertEqual(sur.classify_domain(lo, hi), sur.STATUS_OK)
        self.put_all(3.2)  # valid waveform, swings to 3.7 V
        lo, hi = sb.validated_vrec_extrema(self.p)
        self.assertEqual(sur.classify_domain(lo, hi), sur.STATUS_INVALID)
        self.put_all(1.65)
        self.put("vrec_p1", [3.3015] * len(self.ts))  # just beyond 1 mV
        lo, hi = sb.validated_vrec_extrema(self.p)
        self.assertEqual(sur.classify_domain(lo, hi), sur.STATUS_INVALID)
        self.put("vrec_p1", [3.3009] * len(self.ts))  # within 1 mV
        lo, hi = sb.validated_vrec_extrema(self.p)
        self.assertEqual(sur.classify_domain(lo, hi), sur.STATUS_OK)


class Orchestration(TraceBase):
    """Run sb.main with a fake ngspice that writes synthetic traces."""

    def run_bench(self, vrec=1.65, corrupt=None):
        rec = os.path.join(self.d, "rec")
        snap = os.path.join(self.d, "snap")
        real_run = subprocess.run
        real_mkdtemp = tempfile.mkdtemp
        ts = self.ts
        fx = 3.0e9  # 3 GHz differential oscillation

        def fake_run(cmd, cwd=None, **kw):
            if cmd[0] != "ngspice":
                return real_run(cmd, **kw) if cwd is None else real_run(cmd, cwd=cwd, **kw)
            pre = os.path.join(cwd, "w")
            write(pre + "_vdiff", ts, [0.4 * math.sin(2 * math.pi * fx * t) for t in ts])
            for k in ("p1", "p16", "n1", "n16"):
                write("%s_vrec_%s" % (pre, k), ts, [vrec + 0.5 * math.sin(2 * math.pi * fx * t) for t in ts])
            if corrupt:
                corrupt(pre)
            return subprocess.CompletedProcess(cmd, 0, "", "")

        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sb, "models_dir", lambda: "/nonexistent"), \
                mock.patch.object(sb, "ngspice_version", lambda: "ngspice-fake"), \
                mock.patch.object(sb.subprocess, "run", fake_run), \
                mock.patch.object(sb.tempfile, "mkdtemp", lambda prefix="": real_mkdtemp(prefix=prefix, dir=self.d)), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = sb.main(["--point", "corrected", "--allow-dirty", "--records-dir", rec, "--snapshots-dir", snap])
        return rc, out.getvalue(), err.getvalue(), rec

    def test_valid_in_domain_publishes_screening_only(self):
        rc, out, err, rec = self.run_bench()
        self.assertEqual(rc, 0, err)
        csvs = glob.glob(rec + "/*.csv")
        self.assertEqual(len(csvs), 1)
        text = open(csvs[0]).read()
        self.assertIn("f_osc_hz", text)
        self.assertIn("SCREENING ONLY", text)
        f = float(open(csvs[0]).read().splitlines()[1].split(",")[text.splitlines()[0].split(",").index("f_osc_hz")])
        self.assertAlmostEqual(f / 3e9, 1.0, places=2)

    def test_out_of_domain_exit_3_no_metrics(self):
        rc, out, err, rec = self.run_bench(vrec=3.2)
        self.assertEqual(rc, 3)
        text = open(glob.glob(rec + "/*.csv")[0]).read()
        self.assertIn(sur.STATUS_INVALID, text)
        self.assertNotIn("f_osc_hz", text)

    def corrupted(self, fn):
        rc, out, err, rec = self.run_bench(corrupt=fn)
        self.assertEqual(rc, 2, err)
        self.assertIn("invalid measurement", err)
        self.assertEqual(glob.glob(rec + "/*"), [])  # nothing published
        self.assertNotIn("f_osc", out)
        self.assertTrue(glob.glob(os.path.join(self.d, "sur179-*")))  # scratch kept

    def test_all_nan_later_probe_blocks_publication(self):
        self.corrupted(lambda pre: write(pre + "_vrec_n16", self.ts, [float("nan")] * len(self.ts)))

    def test_interior_nan_blocks_publication(self):
        def c(pre):
            v = [1.65] * len(self.ts); v[1234] = float("nan")
            write(pre + "_vrec_p1", self.ts, v)
        self.corrupted(c)

    def test_truncated_vdiff_blocks_publication(self):
        n = len(self.ts) // 2
        self.corrupted(lambda pre: write(pre + "_vdiff", self.ts[:n], [0.0] * n))

    def test_malformed_row_blocks_publication(self):
        def c(pre):
            with open(pre + "_vrec_p16", "a") as fh:
                fh.write("garbage\n")
        self.corrupted(c)


if __name__ == "__main__":
    unittest.main()
