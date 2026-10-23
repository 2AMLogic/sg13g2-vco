"""Known-answer tests for the artifact-manifest gate and sim/store-evidence.sh
(issue #253; stdlib unittest only).

The checker is driven on disposable git trees; the writer runs against a stub
`klt` on PATH, so nothing here needs the broker, the real klt or the PDK.
"""
import hashlib
import json
import os
import stat
import subprocess
import tempfile
import unittest

from _loader import ROOT, load_module

chk = load_module("check_artifact_manifests",
                  ".github/scripts/check_artifact_manifests.py")
WRITER = os.path.join(ROOT, "sim", "store-evidence.sh")


def entry(data, **over):
    sha = hashlib.sha256(data).hexdigest()
    e = {"sha256": sha, "size": len(data), "kind": "evidence",
         "producer": {"tool": "klt", "version": "0.7.1", "loom.repo": "o/r",
                      "commit": "abc"},
         "uri": "artifact:evidence/o__r/" + sha, "name": "x.raw"}
    e.update(over)
    return e


def manifest(*entries):
    return json.dumps({"schema_version": 1, "entries": list(entries)})


def git(root, *args):
    subprocess.run(["git", "-C", root, "-c", "user.email=t@t", "-c", "user.name=t",
                    *args], check=True, capture_output=True)


class CheckerTree(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = tmp.name
        git(self.root, "init", "-q")
        os.makedirs(os.path.join(self.root, "manifests", "artifacts"))

    def put(self, rel, data, text=False):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w" if text else "wb") as f:
            f.write(data)

    def run_check(self):
        git(self.root, "add", "-A")
        return chk.check(self.root)

    def test_no_manifests_passes(self):
        self.assertEqual(self.run_check(), [])

    def test_valid_manifest_passes(self):
        self.put("manifests/artifacts/b-1.manifest.json", manifest(entry(b"raw1")), True)
        self.assertEqual(self.run_check(), [])

    def test_non_artifact_uri_fails(self):
        e = entry(b"raw1", uri="https://example.com/" + "0" * 64)
        self.put("manifests/artifacts/b-1.manifest.json", manifest(e), True)
        self.assertTrue(any("artifact:<key>" in f for f in self.run_check()))

    def test_missing_sha256_fails(self):
        e = entry(b"raw1")
        del e["sha256"]
        self.put("manifests/artifacts/b-1.manifest.json", manifest(e), True)
        self.assertTrue(any("missing sha256" in f for f in self.run_check()))

    def test_uri_key_must_end_in_sha(self):
        e = entry(b"raw1", uri="artifact:evidence/o__r/" + "1" * 64)
        self.put("manifests/artifacts/b-1.manifest.json", manifest(e), True)
        self.assertTrue(any("does not end in" in f for f in self.run_check()))

    def test_unknown_field_and_bad_schema_fail(self):
        self.put("manifests/artifacts/a.manifest.json",
                 manifest(entry(b"raw1", extra=1)), True)
        self.put("manifests/artifacts/b.manifest.json", '{"entries": []}', True)
        fails = self.run_check()
        self.assertTrue(any("unknown field" in f for f in fails))
        self.assertTrue(any("b.manifest.json" in f and "schema_version" in f for f in fails))

    def test_storage_location_fails(self):
        for bad in ("s3://bucket/key", "arn:aws:s3:::bucket"):
            e = entry(b"raw1", name=bad)
            self.put("manifests/artifacts/b-1.manifest.json", manifest(e), True)
            self.assertTrue(any("storage location" in f for f in self.run_check()), bad)

    def test_committed_bytes_of_stored_object_fail(self):
        data = b"raw bytes that must not be committed"
        self.put("manifests/artifacts/b-1.manifest.json", manifest(entry(data)), True)
        self.put("sim/b/run.raw", data)
        self.put("sim/b/other.raw", b"same size is not same bytes".ljust(len(data), b"."))
        fails = self.run_check()
        self.assertEqual(len(fails), 1)
        self.assertIn("sim/b/run.raw", fails[0])

    def test_untracked_scratch_bytes_are_not_flagged(self):
        data = b"scratch bytes"
        self.put("manifests/artifacts/b-1.manifest.json", manifest(entry(data)), True)
        git(self.root, "add", "manifests")
        self.put("sim/build/run.raw", data)  # untracked: git-ignored scratch
        self.assertEqual(chk.check(self.root), [])

    def test_non_manifest_file_in_dir_fails(self):
        self.put("manifests/artifacts/notes.txt", "x", True)
        self.assertTrue(any("notes.txt" in f for f in self.run_check()))


class LiveTree(unittest.TestCase):
    def test_this_repo_passes(self):
        self.assertEqual(chk.check(ROOT), [])


class Writer(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = tmp.name
        self.root = os.path.join(self.tmp, "repo")
        os.makedirs(self.root)
        git(self.root, "init", "-q")
        self.data = os.path.join(self.tmp, "run.raw")
        with open(self.data, "wb") as f:
            f.write(b"raw")
        self.dest = os.path.join(self.root, "manifests", "artifacts", "b-1.manifest.json")

    def stub_klt(self, body):
        bindir = os.path.join(self.tmp, "bin")
        os.makedirs(bindir, exist_ok=True)
        path = os.path.join(bindir, "klt")
        with open(path, "w") as f:
            f.write("#!/usr/bin/env bash\n" + body)
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        return bindir

    def run_writer(self, bindir, broker="https://broker.invalid"):
        env = {"PATH": bindir + ":/usr/bin:/bin", "STORE_EVIDENCE_ROOT": self.root}
        if broker is not None:
            env["KLT_ARTIFACT_BROKER"] = broker
        return subprocess.run(["bash", WRITER, "b", "1", self.data],
                              env=env, capture_output=True, text=True)

    def test_success_writes_manifest_only(self):
        # the stub emulates `put --manifest PATH FILE`: it writes a manifest
        stub = ('[ "$3" = --help ] && exit 0\n'
                'm="$4"; printf \'{"schema_version":1,"entries":[]}\' > "$m"\n')
        res = self.run_writer(self.stub_klt(stub))
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertTrue(os.path.isfile(self.dest))
        self.assertNotIn("broker.invalid", res.stdout + res.stderr)

    def test_broker_unset_fails_closed(self):
        res = self.run_writer(self.stub_klt("exit 0\n"), broker=None)
        self.assertEqual(res.returncode, 1)
        self.assertFalse(os.path.exists(self.dest))

    def test_klt_without_artifact_put_fails_closed(self):
        res = self.run_writer(self.stub_klt("exit 2\n"))
        self.assertEqual(res.returncode, 1)
        self.assertIn("no 'artifact put'", res.stderr)
        self.assertFalse(os.path.exists(self.dest))

    def test_unreachable_broker_fails_closed_and_prints_no_url(self):
        stub = '[ "$3" = --help ] && exit 0\necho "cannot reach $KLT_ARTIFACT_BROKER" >&2; exit 1\n'
        res = self.run_writer(self.stub_klt(stub))
        self.assertEqual(res.returncode, 1)
        self.assertFalse(os.path.exists(self.dest))
        self.assertNotIn("broker.invalid", res.stdout + res.stderr)

    def test_tracked_file_refused(self):
        tracked = os.path.join(self.root, "run.raw")
        with open(tracked, "wb") as f:
            f.write(b"raw")
        git(self.root, "add", "run.raw")
        env = {"PATH": self.stub_klt("exit 0\n") + ":/usr/bin:/bin",
               "STORE_EVIDENCE_ROOT": self.root, "KLT_ARTIFACT_BROKER": "x"}
        res = subprocess.run(["bash", WRITER, "b", "1", tracked], env=env,
                             capture_output=True, text=True)
        self.assertEqual(res.returncode, 1)
        self.assertIn("already tracked", res.stderr)
        self.assertFalse(os.path.exists(self.dest))


if __name__ == "__main__":
    unittest.main()
