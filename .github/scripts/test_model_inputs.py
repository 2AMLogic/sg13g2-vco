#!/usr/bin/env python3
"""Self-test for model_inputs_check.py (issue #139). PDK-free, stdlib unittest,
throwaway fixture trees; never touches the real tree.

Run: python3 -I .github/scripts/test_model_inputs.py
"""
import builtins
import hashlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import model_inputs_check as mic  # noqa: E402

RID = "20260926-010627-e391693"
OTHER = "20260926-010713-e391693"
EXP = "sim/oscillator-core"
RDIR = EXP + "/records"
NS = "%s/netlist-snapshots/%s/model-inputs/" % (EXP, RID)
IND = b"* captured inductor model v1\n"
INIT = b"set ngbehavior=hsa\n"
LIVE_OLD = b"* live inductor model, as of capture\n"
LIVE_NEW = b"* live inductor model, edited since\n"
LIVE = "sim/inductor-model/sg13g2_inductor_em.spice"


def sha(b):
    return hashlib.sha256(b).hexdigest()


def good_doc(rid=RID):
    ns = "%s/netlist-snapshots/%s/model-inputs/" % (EXP, rid)
    return {
        "schema": mic.SCHEMA, "record_id": rid, "note": "n",
        "inputs": [
            {"role": "pdk-library", "bundle_path": "models/cornerHBT.lib",
             "sha256": "a" * 64, "original_path": "/opt/pdk/cornerHBT.lib",
             "retained_snapshot": None},
            {"role": "inductor-model",
             "bundle_path": "inductor/sg13g2_inductor_em.spice",
             "sha256": sha(IND), "original_path": LIVE,
             "retained_snapshot": ns + "inductor/sg13g2_inductor_em.spice"},
            {"role": "simulator-init", "bundle_path": "init/.spiceinit",
             "sha256": sha(INIT), "original_path": EXP + "/.spiceinit",
             "retained_snapshot": ns + "init/.spiceinit"},
        ]}


def put(root, rel, data):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode())


def write_valid(root, rid=RID, doc=None):
    ns = "%s/netlist-snapshots/%s/model-inputs/" % (EXP, rid)
    put(root, ns + "inductor/sg13g2_inductor_em.spice", IND)
    put(root, ns + "init/.spiceinit", INIT)
    put(root, "%s/%s%s" % (RDIR, rid, mic.SUFFIX),
        json.dumps(doc or good_doc(rid), indent=2) + "\n")


class Base(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="mi-test-")
        self.addCleanup(shutil.rmtree, self.root, True)

    def run_gate(self):
        out, err = io.StringIO(), io.StringIO()
        rc = mic.run(self.root, out, err)
        return rc, out.getvalue(), err.getvalue()

    def mutate(self, fn):
        doc = good_doc()
        fn(doc)
        write_valid(self.root, doc=doc)
        return self.run_gate()

    def assertRejected(self, fn, needle):
        rc, out, err = self.mutate(fn)
        self.assertEqual(rc, 1, out + err)
        self.assertIn(needle, err)
        self.assertIn("error(s)", out)
        return err


class TestValid(Base):
    def test_valid_capture_with_external_roles(self):
        write_valid(self.root)
        rc, out, err = self.run_gate()
        self.assertEqual((rc, err), (0, ""))
        self.assertIn("1 manifest(s) verified (2 retained snapshot(s) "
                      "hash-checked, 1 external role(s) digest-only)", out)

    def test_all_external_manifest_ok(self):
        doc = good_doc()
        for e in doc["inputs"]:
            e["retained_snapshot"] = None
        write_valid(self.root, doc=doc)
        self.assertEqual(self.run_gate()[0], 0)

    def test_no_records_at_all(self):
        os.makedirs(os.path.join(self.root, "sim"))
        rc, out, _ = self.run_gate()
        self.assertEqual(rc, 0)
        self.assertIn("0 manifest(s) verified", out)

    def test_two_records_independent(self):
        write_valid(self.root)
        write_valid(self.root, OTHER)
        rc, out, _ = self.run_gate()
        self.assertEqual(rc, 0)
        self.assertIn("2 manifest(s) verified", out)


class TestLegacy(Base):
    def test_legacy_reported_not_verified(self):
        write_valid(self.root)
        put(self.root, "%s/20260906-160637-a73c3c7.md" % (RDIR), "old")
        put(self.root, "%s/20260906-160637-a73c3c7.csv" % (RDIR), "old")
        put(self.root, "sim/inductor-model/records/20260906-160637-a73c3c7.md",
            "old")
        rc, out, err = self.run_gate()
        self.assertEqual(rc, 0, err)
        self.assertIn("legacy / not checked (no model-input manifest): "
                      "%s/20260906-160637-a73c3c7" % RDIR, out)
        self.assertIn("sim/inductor-model/records/20260906-160637-a73c3c7",
                      out)
        self.assertIn("1 manifest(s) verified", out)
        self.assertIn("2 legacy record(s) not checked", out)
        self.assertNotIn("verified", [l for l in out.splitlines()
                                      if l.startswith("legacy")][0])

    def test_only_legacy_verifies_nothing(self):
        put(self.root, RDIR + "/20260906-160637-a73c3c7.md", "old")
        rc, out, _ = self.run_gate()
        self.assertEqual(rc, 0)
        self.assertIn("0 manifest(s) verified", out)
        self.assertIn("1 legacy record(s) not checked", out)

    def test_companion_files_of_manifest_record_not_legacy(self):
        write_valid(self.root)
        put(self.root, "%s/%s.md" % (RDIR, RID), "narrative")
        _, out, _ = self.run_gate()
        self.assertIn("0 legacy record(s)", out)


class TestMalformed(Base):
    def put_raw(self, text):
        put(self.root, "%s/%s%s" % (RDIR, RID, mic.SUFFIX), text)
        return self.run_gate()

    def test_not_json(self):
        rc, _, err = self.put_raw("{nope")
        self.assertEqual(rc, 1)
        self.assertIn("cannot parse as JSON", err)

    def test_duplicate_json_key(self):
        rc, _, err = self.put_raw('{"schema": "x", "schema": "y"}')
        self.assertEqual(rc, 1)
        self.assertIn("duplicate JSON key", err)

    def test_nan_constant(self):
        rc, _, err = self.put_raw('{"schema": NaN}')
        self.assertEqual(rc, 1)
        self.assertIn("non-standard JSON constant", err)

    def test_top_level_not_object(self):
        rc, _, err = self.put_raw("[]")
        self.assertEqual(rc, 1)
        self.assertIn("top level must be a JSON object", err)

    def test_bad_filename_id(self):
        put(self.root, RDIR + "/not-an-id" + mic.SUFFIX, "{}")
        rc, _, err = self.run_gate()
        self.assertEqual(rc, 1)
        self.assertIn("does not carry a record id", err)

    def test_wrong_schema(self):
        self.assertRejected(lambda d: d.update(schema="other/2"), "schema is")

    def test_missing_key(self):
        self.assertRejected(lambda d: d.pop("inputs"), "missing key(s): inputs")

    def test_unknown_top_key(self):
        self.assertRejected(lambda d: d.update(extra=1), "unknown key(s): extra")

    def test_empty_inputs(self):
        self.assertRejected(lambda d: d.update(inputs=[]),
                            "inputs must be a non-empty list")

    def test_entry_missing_field(self):
        self.assertRejected(lambda d: d["inputs"][0].pop("sha256"),
                            "inputs[0] missing key(s): sha256")

    def test_entry_unknown_field(self):
        self.assertRejected(lambda d: d["inputs"][0].update(x=1),
                            "inputs[0] unknown key(s): x")

    def test_entry_not_object(self):
        self.assertRejected(lambda d: d["inputs"].append("str"),
                            "inputs[3] must be an object")

    def test_snapshot_wrong_type(self):
        self.assertRejected(
            lambda d: d["inputs"][0].update(retained_snapshot=3),
            "retained_snapshot must be a string or null")

    def test_bad_digest_syntax(self):
        for bad in ("A" * 64, "a" * 63, "g" * 64, ""):
            self.assertRejected(lambda d, b=bad: d["inputs"][0].update(sha256=b),
                                "sha256")


class TestIdentity(Base):
    def test_record_id_mismatch(self):
        self.assertRejected(lambda d: d.update(record_id=OTHER),
                            "does not match the record id")

    def test_duplicate_bundle_identity(self):
        self.assertRejected(lambda d: d["inputs"].append(dict(d["inputs"][0])),
                            "duplicate bundle identity")

    def test_duplicate_bundle_path_other_role(self):
        def f(d):
            e = dict(d["inputs"][0])
            e["role"] = "other"
            d["inputs"].append(e)
        self.assertRejected(f, "duplicate bundle_path")

    def test_duplicate_retained_snapshot(self):
        def f(d):
            e = dict(d["inputs"][1])
            e["role"] = "dup"
            e["bundle_path"] = "inductor/sg13g2_inductor_em.spice"
            d["inputs"].append(e)
        err = self.assertRejected(f, "duplicate")
        self.assertIn("duplicate bundle_path", err)


class TestPaths(Base):
    def snap(self, value):
        return lambda d: d["inputs"][1].update(retained_snapshot=value)

    def test_absolute(self):
        self.assertRejected(self.snap("/etc/passwd"), "absolute")

    def test_traversal(self):
        self.assertRejected(self.snap(NS + "../../x"), "'..'")

    def test_traversal_normalised_away(self):
        self.assertRejected(self.snap(NS + "inductor/../inductor/"
                                      "sg13g2_inductor_em.spice"), "'..'")

    def test_dot_segment(self):
        self.assertRejected(self.snap(NS + "./inductor/x"), "'.'")

    def test_backslash(self):
        self.assertRejected(self.snap(NS.replace("/", "\\") + "x"), "absolute")

    def test_empty_string(self):
        self.assertRejected(self.snap(""), "retained_snapshot")

    def test_drive_letter(self):
        self.assertRejected(self.snap("C:/x"), "absolute")

    def test_other_records_namespace(self):
        other = NS.replace(RID, OTHER) + "inductor/sg13g2_inductor_em.spice"
        self.assertRejected(self.snap(other), "outside this record's snapshot "
                            "namespace")

    def test_other_experiment_namespace(self):
        other = ("sim/phase-noise/netlist-snapshots/%s/model-inputs/"
                 "inductor/sg13g2_inductor_em.spice" % RID)
        self.assertRejected(self.snap(other), "outside")

    def test_design_snapshot_not_a_model_input(self):
        self.assertRejected(self.snap(
            "%s/netlist-snapshots/%s/design-vco.spice" % (EXP, RID)),
            "outside")

    def test_namespace_only(self):
        self.assertRejected(self.snap(NS), "retained_snapshot")

    def test_not_namespace_plus_bundle_path(self):
        self.assertRejected(self.snap(NS + "init/.spiceinit"),
                            "does not equal namespace + bundle_path")

    def test_unsafe_bundle_path(self):
        self.assertRejected(
            lambda d: d["inputs"][0].update(bundle_path="../escape"),
            "bundle_path")

    def test_symlink_component(self):
        write_valid(self.root)
        real = os.path.join(self.root, NS + "inductor")
        moved = real + "-real"
        os.rename(real, moved)
        os.symlink(moved, real)
        rc, _, err = self.run_gate()
        self.assertEqual(rc, 1)
        self.assertIn("symlink", err)

    def test_symlink_file_leaf(self):
        write_valid(self.root)
        leaf = os.path.join(self.root, NS + "init/.spiceinit")
        os.rename(leaf, leaf + ".real")
        os.symlink(leaf + ".real", leaf)
        rc, _, err = self.run_gate()
        self.assertEqual(rc, 1)
        self.assertIn("symlink", err)


class TestSnapshots(Base):
    def test_wrong_hash(self):
        write_valid(self.root)
        put(self.root, NS + "inductor/sg13g2_inductor_em.spice", IND + b"x")
        rc, _, err = self.run_gate()
        self.assertEqual(rc, 1)
        self.assertIn("hashes to %s but the manifest declares %s"
                      % (sha(IND + b"x"), sha(IND)), err)

    def test_missing_snapshot(self):
        write_valid(self.root)
        os.remove(os.path.join(self.root, NS + "init/.spiceinit"))
        rc, _, err = self.run_gate()
        self.assertEqual(rc, 1)
        self.assertIn("is missing; commit it with the manifest", err)

    def test_snapshot_is_directory(self):
        write_valid(self.root)
        p = os.path.join(self.root, NS + "init/.spiceinit")
        os.remove(p)
        os.makedirs(p)
        rc, _, err = self.run_gate()
        self.assertEqual(rc, 1)
        self.assertIn("is missing", err)

    def test_one_bad_manifest_does_not_hide_another(self):
        write_valid(self.root)
        write_valid(self.root, OTHER)
        os.remove(os.path.join(self.root, NS + "init/.spiceinit"))
        rc, out, err = self.run_gate()
        self.assertEqual(rc, 1)
        self.assertIn("1 manifest(s) verified", out)
        self.assertIn(RID, err)


class TestLiveBytesNeverRead(Base):
    def test_live_edit_does_not_invalidate_and_is_never_opened(self):
        write_valid(self.root)
        put(self.root, LIVE, LIVE_OLD)
        put(self.root, LIVE, LIVE_NEW)  # model edited after capture
        os.makedirs(os.path.join(self.root, "pdk"), exist_ok=True)
        opened = []
        real_open, real_os_open = builtins.open, os.open

        def spy_open(f, *a, **k):
            opened.append(os.fspath(f))
            return real_open(f, *a, **k)

        def spy_os_open(f, *a, **k):
            opened.append(os.fspath(f))
            return real_os_open(f, *a, **k)

        builtins.open, os.open = spy_open, spy_os_open
        try:
            rc, out, err = self.run_gate()
        finally:
            builtins.open, os.open = real_open, real_os_open
        self.assertEqual((rc, err), (0, ""))
        self.assertTrue(opened)
        allowed = (os.path.join(self.root, RDIR) + os.sep,
                   os.path.join(self.root, EXP, "netlist-snapshots") + os.sep)
        for p in opened:
            self.assertTrue(p.startswith(allowed), "unexpected read: " + p)
        self.assertNotIn(os.path.join(self.root, LIVE), opened)

    def test_live_file_deleted_or_unreadable_irrelevant(self):
        write_valid(self.root)  # LIVE and PDK paths do not exist at all
        self.assertEqual(self.run_gate()[0], 0)


class TestCli(Base):
    def test_cli_exit_codes(self):
        import subprocess
        write_valid(self.root)
        cmd = [sys.executable, "-I", os.path.join(HERE, "model_inputs_check.py"),
               "--root", self.root, "check"]
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(p.returncode, 0, p.stderr)
        os.remove(os.path.join(self.root, NS + "init/.spiceinit"))
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(p.returncode, 1)
        self.assertIn(b"error:", p.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
