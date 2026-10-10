"""Failure contract and known-answer tests for the EM post/fit stages (#167)."""
import contextlib
import csv
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import numpy as np

import _em
from _em import (FIT_OUT, POST_OUT, EM, SCRIPTS, emlib, fit_lumped, postprocess)

GEOMS = emlib.GEOMS


def inputs_of(g):
    return ["results/inductor_%s.s2p" % g,
            "results/inductor_%s/port_information.json" % g,
            "gds/inductor_%s.json" % g]


class Base(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.root = os.path.join(self._td.name, "em")
        os.makedirs(self.root)
        self.model = os.path.join(self.root, "model", "sg13g2_inductor_em.spice")

    def run_stage(self, stage):
        """In-process run; returns (rc, stderr)."""
        err = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            if stage == "post":
                rc = postprocess.main(["--dir", self.root])
            else:
                rc = fit_lumped.main(["--dir", self.root, "--model-out", self.model])
        return rc, err.getvalue()

    def outs(self, stage):
        return POST_OUT if stage == "post" else FIT_OUT

    def assert_untouched(self, stage, seeded):
        self.assertEqual(_em.read_all(self.root, self.outs(stage)), seeded)
        self.assertEqual(_em.stray(self.root), [])

    def assert_fails_preserving(self, stage, msg_part=None):
        seeded = _em.seed_outputs(self.root, self.outs(stage))
        rc, err = self.run_stage(stage)
        self.assertNotEqual(rc, 0, err)
        if msg_part:
            self.assertIn(msg_part, err)
        self.assert_untouched(stage, seeded)
        return err


class TestPreflight(Base):
    def test_empty_input_tree(self):
        for stage in ("post", "fit"):
            with self.subTest(stage=stage):
                os.makedirs(os.path.join(self.root, "results"), exist_ok=True)
                err = self.assert_fails_preserving(stage)
                for g in GEOMS:
                    self.assertIn("geometry %s" % g, err)

    def test_each_omitted_input_of_each_geometry(self):
        for stage in ("post", "fit"):
            for g in GEOMS:
                for rel in _inputs(g):
                    with self.subTest(stage=stage, omitted=rel):
                        _reset(self.root)
                        _em.make_tree(self.root, omit=[rel])
                        err = self.assert_fails_preserving(stage, "geometry %s" % g)
                        self.assertIn("missing", err)
                        self.assertIn(os.path.basename(rel), err)

    def test_empty_files(self):
        for stage in ("post", "fit"):
            for rel in _inputs("p13"):
                with self.subTest(stage=stage, empty=rel):
                    _reset(self.root)
                    _em.make_tree(self.root)
                    open(os.path.join(self.root, rel), "w").close()
                    self.assert_fails_preserving(stage, "empty")

    def test_malformed_inputs(self):
        def put(rel, text):
            with open(os.path.join(self.root, rel), "w") as fh:
                fh.write(text)
        cases = {
            "gds not json": ("gds/inductor_p11.json", "{not json"),
            "gds missing key": ("gds/inductor_p11.json", json.dumps({"w_um": 1, "s_um": 1, "d_um": 1})),
            "gds non-numeric": ("gds/inductor_p11.json",
                                json.dumps({"w_um": "x", "s_um": 1, "d_um": 1, "nr_r": 1})),
            "gds nonpositive": ("gds/inductor_p11.json",
                                json.dumps({"w_um": 1, "s_um": 1, "d_um": 1, "nr_r": 0})),
            "ports not json": ("results/inductor_p1/port_information.json", "[[["),
            "ports missing list": ("results/inductor_p1/port_information.json", "{}"),
            "ports one port": ("results/inductor_p1/port_information.json",
                               json.dumps({"ports": [{"portnumber": 1, "length": 1, "width": 1}]})),
            "ports bad length": ("results/inductor_p1/port_information.json", json.dumps(
                {"ports": [{"portnumber": 1, "length": -1, "width": 1},
                           {"portnumber": 2, "length": 1, "width": 1}]})),
            "s2p garbage": ("results/inductor_p13.s2p", "# Hz S RI R 50\nthis is not numbers\n"),
            "s2p no header": ("results/inductor_p13.s2p", "1 2 3 4 5 6 7 8 9\n2 2 3 4 5 6 7 8 9\n"),
            "s2p one point": ("results/inductor_p13.s2p",
                              "# Hz S RI R 50\n1e9 0 0 1 0 1 0 0 0\n"),
            "s2p nan": ("results/inductor_p13.s2p",
                        "# Hz S RI R 50\n1e9 nan 0 1 0 1 0 0 0\n2e9 0 0 1 0 1 0 0 0\n"),
            "s2p 1-port": ("results/inductor_p13.s2p", "# Hz S RI R 50\n1e9 0 0\n2e9 0 0\n"),
        }
        for stage in ("post", "fit"):
            for name, (rel, text) in cases.items():
                with self.subTest(stage=stage, case=name):
                    _reset(self.root)
                    _em.make_tree(self.root)
                    put(rel, text)
                    self.assert_fails_preserving(stage, os.path.basename(rel))

    def test_incomplete_convergence_variant(self):
        _em.make_tree(self.root)
        add_convergence(self.root, with_variant_files=False)
        self.assert_fails_preserving("post", "p1_mesh0p5")


class TestFailureAfterWork(Base):
    def test_post_failure_after_first_geometry_written(self):
        _em.make_tree(self.root)
        calls = []
        real = emlib.write_snp

        def flaky(*a, **k):
            calls.append(a[0])
            if len(calls) == 2:
                raise RuntimeError("injected failure on second geometry")
            return real(*a, **k)

        seeded = _em.seed_outputs(self.root, POST_OUT)
        with mock.patch.object(emlib, "write_snp", flaky), self.assertRaises(RuntimeError):
            self.run_stage("post")
        self.assertEqual(len(calls), 2)
        self.assert_untouched("post", seeded)

    def test_fit_failure_after_first_geometry_fitted(self):
        _em.make_tree(self.root)
        n = []
        real = fit_lumped.fit_series

        def flaky(*a, **k):
            n.append(1)
            if len(n) == 2:
                raise RuntimeError("injected failure on second geometry")
            return real(*a, **k)

        seeded = _em.seed_outputs(self.root, FIT_OUT)
        with mock.patch.object(fit_lumped, "fit_series", flaky), self.assertRaises(RuntimeError):
            self.run_stage("fit")
        self.assertEqual(len(n), 2)
        self.assert_untouched("fit", seeded)

    def test_fit_failure_in_model_emission(self):
        _em.make_tree(self.root)
        seeded = _em.seed_outputs(self.root, FIT_OUT)
        with mock.patch.object(fit_lumped, "emit_spice", side_effect=KeyError("p1")), \
                self.assertRaises(KeyError):
            self.run_stage("fit")
        self.assert_untouched("fit", seeded)

    def test_publication_failure_reports_and_recovers(self):
        _em.make_tree(self.root)
        seeded = _em.seed_outputs(self.root, POST_OUT)
        real = os.replace
        n = []

        def flaky(src, dst):
            n.append(dst)
            if len(n) == 3:
                raise OSError("injected rename failure")
            return real(src, dst)

        with mock.patch.object(os, "replace", flaky):
            rc, err = self.run_stage("post")
        self.assertNotEqual(rc, 0)
        self.assertIn("publication failed after replacing 2 of", err)
        self.assertIn("re-run this stage", err)
        # Not atomic: the first two files are new, the rest are still the old ones.
        now = _em.read_all(self.root, POST_OUT)
        self.assertEqual(sum(now[r] != seeded[r] for r in POST_OUT), 2)
        # The staged complete set is kept for inspection ...
        self.assertEqual(len([s for s in _em.stray(self.root) if os.path.basename(s).startswith(".stage-")]), 1)
        # ... and a plain re-run republishes everything and cleans up.
        rc, err = self.run_stage("post")
        self.assertEqual(rc, 0, err)
        self.assertEqual(_em.stray(self.root), [])
        self.assertTrue(all(not v.startswith(b"PREVIOUS-RUN") for v in _em.read_all(self.root, POST_OUT).values()))


class TestKnownAnswer(Base):
    def test_post_publishes_complete_set(self):
        _em.make_tree(self.root)
        rc, err = self.run_stage("post")
        self.assertEqual(rc, 0, err)
        self.assertEqual(_em.stray(self.root), [])
        for rel in POST_OUT:
            self.assertGreater(os.path.getsize(os.path.join(self.root, rel)), 0, rel)
        with open(os.path.join(self.root, "results", "em_summary.csv")) as fh:
            rows = list(csv.DictReader(fh))
        self.assertEqual([r["geometry"] for r in rows], GEOMS)
        for r in rows:
            g = r["geometry"]
            zse = emlib.z_single_ended(_em.true_Z(g))
            L, Q = emlib.lq(_em.FREQ, zse)
            self.assertAlmostEqual(float(r["l_se_1g"]) / emlib.at(_em.FREQ, L, 1e9), 1.0, delta=1e-4)
            self.assertAlmostEqual(float(r["q_se_10g"]) / emlib.at(_em.FREQ, Q, 10e9), 1.0, delta=1e-3)
            self.assertEqual(float(r["nr_r"]), _em.GEOM[g][3])
        # the de-embedded Touchstone recovers the generating Z
        f, S, z0 = emlib.read_snp(os.path.join(self.root, "results", "inductor_p13_deembedded.s2p"))
        Z = emlib.s2z(S, z0)
        np.testing.assert_allclose(Z, _em.true_Z("p13"), rtol=1e-6, atol=1e-6)
        # no convergence variants -> no convergence.csv
        self.assertFalse(os.path.exists(os.path.join(self.root, "results", "convergence.csv")))

    def test_post_replaces_previous_outputs(self):
        _em.make_tree(self.root)
        _em.seed_outputs(self.root, POST_OUT)
        rc, err = self.run_stage("post")
        self.assertEqual(rc, 0, err)
        self.assertTrue(all(not v.startswith(b"PREVIOUS-RUN") for v in _em.read_all(self.root, POST_OUT).values()))

    def test_fit_publishes_summaries_and_model_together(self):
        _em.make_tree(self.root)
        _em.seed_outputs(self.root, FIT_OUT)
        rc, err = self.run_stage("fit")
        self.assertEqual(rc, 0, err)
        self.assertEqual(_em.stray(self.root), [])
        now = _em.read_all(self.root, FIT_OUT)
        self.assertTrue(all(v is not None and not v.startswith(b"PREVIOUS-RUN") for v in now.values()))
        fits = json.loads(now["fit/fit_parameters.json"])
        self.assertEqual(sorted(fits), sorted(GEOMS))
        for g in GEOMS:
            # data were generated from the analytic element values, so the
            # fitted/analytic ratios must come back as ~1 for the well-determined ones
            ratio = fits[g]["ratio_fitted_over_analytic"]
            for k in ("Rser", "Ltot"):
                self.assertAlmostEqual(ratio[k], 1.0, delta=0.02, msg="%s %s" % (g, k))
            self.assertLess(fits[g]["residual"]["fit_band"]["rms_rel_err_zse_pct"], 1.0)
        model = now["model/sg13g2_inductor_em.spice"].decode()
        self.assertIn(".subckt inductor la lb sub", model)
        # summary rows cover all three geometries
        rows = list(csv.DictReader(io.StringIO(now["fit/fit_summary.csv"].decode())))
        self.assertEqual({r["geometry"] for r in rows}, set(GEOMS))
        self.assertEqual(len(rows), 8 * len(GEOMS))


    def test_post_publishes_convergence_when_variants_complete(self):
        _em.make_tree(self.root)
        add_convergence(self.root, with_variant_files=True)
        rc, err = self.run_stage("post")
        self.assertEqual(rc, 0, err)
        with open(os.path.join(self.root, "results", "convergence.csv")) as fh:
            rows = list(csv.DictReader(fh))
        self.assertEqual([r["variant"] for r in rows], ["baseline", "p1_mesh0p5"])
        self.assertAlmostEqual(float(rows[1]["d_l_se_1g_pct"]), 0.0, places=6)


class TestCli(Base):
    """Exit status through the real command line (what run_extraction.sh sees)."""

    def cli(self, *args):
        return subprocess.run([sys.executable, "-I", "-B"] + list(args),
                              capture_output=True, text=True)

    def test_post_cli_exit_codes(self):
        script = os.path.join(SCRIPTS, "postprocess.py")
        r = self.cli(script, "--dir", self.root)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("nothing was written", r.stderr)
        _em.make_tree(self.root)
        r = self.cli(script, "--dir", self.root)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_fit_cli_exit_codes(self):
        script = os.path.join(SCRIPTS, "fit_lumped.py")
        r = self.cli(script, "--dir", self.root, "--model-out", self.model)
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(self.model))


def add_convergence(root, with_variant_files):
    """Baseline run_meta plus a p1_mesh0p5 variant (a copy of the baseline run)."""
    meta = {"settings": {"refined_cellsize": 1.0, "margin": 200}, "wall_seconds": 1}
    base = os.path.join(root, "results", "inductor_p1")
    with open(os.path.join(base, "run_meta.json"), "w") as fh:
        json.dump(meta, fh)
    var = os.path.join(root, "results", "convergence", "p1_mesh0p5")
    os.makedirs(var)
    if with_variant_files:
        meta["settings"]["refined_cellsize"] = 0.5
        with open(os.path.join(var, "run_meta.json"), "w") as fh:
            json.dump(meta, fh)
        shutil.copy(os.path.join(base, "port_information.json"), var)
        shutil.copy(os.path.join(root, "results", "inductor_p1.s2p"), var + ".s2p")


def _inputs(g):
    return inputs_of(g)


def _reset(root):
    for sub in os.listdir(root):
        p = os.path.join(root, sub)
        shutil.rmtree(p) if os.path.isdir(p) else os.unlink(p)


if __name__ == "__main__":
    unittest.main()
