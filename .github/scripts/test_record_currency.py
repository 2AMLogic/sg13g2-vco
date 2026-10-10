#!/usr/bin/env python3
"""Self-test for record_currency.py (issue #122). PDK-free, stdlib unittest,
runs against throwaway git repos and never touches the real tree.

Run: python3 -I .github/scripts/test_record_currency.py
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import record_currency as rc  # noqa: E402

SRC_V1 = b"* v1 design\nXL1 a b ind\n"
SRC_V2 = b"* v2 design\nXL1 a b ind\n"
H1 = hashlib.sha256(SRC_V1).hexdigest()
H2 = hashlib.sha256(SRC_V2).hexdigest()
OSC = "sim/oscillator-core/records"
PN = "sim/phase-noise/records"
TANK = "sim/tank-characterization/records"
BN = "sim/bn-substrate-tank/records"


def git(root, *a):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    return subprocess.run(["git", "-C", root] + list(a), check=True, env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE
                          ).stdout.decode().strip()


class Fixture(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.d)
        git(self.d, "init", "-q", "-b", "main")
        self.write("design/vco.spice", SRC_V1)
        git(self.d, "add", "-A")
        git(self.d, "commit", "-q", "-m", "v1")
        self.c1 = git(self.d, "rev-parse", "--short", "HEAD")

    def write(self, rel, data):
        p = os.path.join(self.d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode())

    def j(self, rel, obj):
        self.write(rel, json.dumps(obj))

    def sidecar(self, rdir, rid, h, **extra):
        o = {"schema": rc.PROVENANCE_SCHEMA, "record_id": rid,
             "design_netlist_path": "design/vco.spice",
             "design_netlist_sha256": h}
        o.update(extra)
        self.j("%s/%s%s" % (rdir, rid, rc.SIDECAR_SUFFIX), o)

    def rec(self, rdir, rid, md=True):
        if md:
            self.write("%s/%s.md" % (rdir, rid), "# record\n")

    def idx(self):
        return rc.build_index(self.d)

    def get(self, rid, rdir=None):
        hits = [e for e in self.idx()["records"] if e["record_id"] == rid
                and (rdir is None or e["path"].startswith(rdir))]
        self.assertEqual(len(hits), 1, hits)
        return hits[0]

    def rid(self, c=None, ts="20261001-000000"):
        return "%s-%s" % (ts, c or self.c1)


class TestStates(Fixture):
    def test_explicit_current(self):
        r = self.rid(); self.rec(OSC, r); self.sidecar(OSC, r, H1)
        e = self.get(r)
        self.assertEqual((e["state"], e["basis"]), ("current", "explicit-source-hash"))
        self.assertTrue(e["reason"])

    def test_explicit_stale(self):
        r = self.rid(); self.rec(OSC, r); self.sidecar(OSC, r, H2)
        e = self.get(r)
        self.assertEqual(e["state"], "superseded")
        self.assertIn("differs", e["reason"])

    def test_current_source_with_different_deck_hash(self):
        r = self.rid(); self.rec(BN, r)
        self.sidecar(BN, r, H1)
        self.j("%s/%s/reports/c.json" % (BN, r),
               {"environment": {"netlist_sha256": "a" * 64}})
        self.write("%s/%s/decks/c.spice" % (BN, r), "deck")
        self.assertEqual(self.get(r)["state"], "current")
        di = self.get(r)["deck_integrity"]
        self.assertEqual((di["checked"], di["matched"]), (1, 0))
        self.assertEqual(len(di["mismatched"]), 1)

    def test_deck_only_is_unknown_and_unpaired_not_checked(self):
        r = self.rid(); self.rec(BN, r)
        self.j("%s/%s/reports/c.json" % (BN, r),
               {"environment": {"netlist_sha256": H1}})  # equals source: irrelevant
        e = self.get(r)
        self.assertEqual(e["state"], "unknown")
        self.assertEqual(e["deck_integrity"]["unpaired"], 1)
        self.assertEqual(e["deck_integrity"]["checked"], 0)

    def test_deck_hash_equal_to_source_is_not_provenance(self):
        r = self.rid(); self.rec(OSC, r)
        self.j("%s/%s-x.json" % (OSC, r), {"netlist_sha256": H1})
        self.assertEqual(self.get(r)["state"], "unknown")

    def test_filename_only_unknown_with_context(self):
        r = self.rid(); self.rec(OSC, r)
        e = self.get(r)
        self.assertEqual((e["state"], e["basis"]), ("unknown", "filename-commit"))
        self.assertEqual(e["filename_commit"]["source_sha256"], H1)
        # even when the commit's blob equals the current source
        self.assertNotEqual(e["state"], "current")

    def test_filename_commit_stale_blob_still_unknown(self):
        self.write("design/vco.spice", SRC_V2)
        git(self.d, "commit", "-qam", "v2")
        r = self.rid(); self.rec(OSC, r)
        self.assertEqual(self.get(r)["state"], "unknown")

    def test_unresolvable_commit(self):
        r = "20261001-000000-abcdef1"; self.rec(OSC, r)
        e = self.get(r)
        self.assertEqual(e["state"], "unknown")
        self.assertEqual(e["filename_commit"]["resolution"], "unresolved")
        self.assertIn("unresolved", e["reason"])

    def test_ambiguous_commit(self):
        # Two objects sharing a 7-char prefix cannot be forged, so stub git.
        orig = rc._git

        def fake(root, *a):
            if a[:2] == ("rev-parse", "--verify"):
                return 128, b"", b"error: short object ID abcdef1 is ambiguous"
            return orig(root, *a)
        rc._git = fake
        self.addCleanup(setattr, rc, "_git", orig)
        r = "20261001-000000-abcdef1"; self.rec(OSC, r)
        e = self.get(r)
        self.assertEqual(e["filename_commit"]["resolution"], "ambiguous")
        self.assertEqual(e["state"], "unknown")

    def test_shallow_history_missing_is_unknown(self):
        orig = rc._git

        def fake(root, *a):
            if a[:2] == ("rev-parse", "--verify"):
                return 128, b"", b"fatal: bad revision"
            if a[:1] == ("rev-parse",) and "--is-shallow-repository" in a:
                return 0, b"true\n", b""
            return orig(root, *a)
        rc._git = fake
        self.addCleanup(setattr, rc, "_git", orig)
        r = "20261001-000000-abcdef1"; self.rec(OSC, r)
        self.assertEqual(self.get(r)["filename_commit"]["resolution"],
                         "unresolved-shallow-history")
        self.assertEqual(self.get(r)["state"], "unknown")

    def test_commit_without_source(self):
        git(self.d, "rm", "-q", "design/vco.spice")
        git(self.d, "commit", "-qm", "rm")
        c = git(self.d, "rev-parse", "--short", "HEAD")
        self.write("design/vco.spice", SRC_V1)
        r = self.rid(c); self.rec(OSC, r)
        self.assertEqual(self.get(r)["filename_commit"]["resolution"],
                         "resolved-no-source")

    def test_malformed_explicit(self):
        for bad in ("XYZ", "A" * 64, H1[:63], 5, None):
            with self.subTest(bad=bad):
                shutil.rmtree(os.path.join(self.d, "sim"), ignore_errors=True)
                r = self.rid(); self.rec(OSC, r); self.sidecar(OSC, r, bad)
                e = self.get(r)
                self.assertEqual(e["state"], "unknown")
                self.assertIn("malformed", e["reason"])
                self.assertEqual(e["basis"], "malformed-explicit-provenance")

    def test_unparsable_sidecar(self):
        r = self.rid(); self.rec(OSC, r)
        self.write("%s/%s%s" % (OSC, r, rc.SIDECAR_SUFFIX), "{nope")
        self.assertEqual(self.get(r)["state"], "unknown")

    def test_wrong_source_path(self):
        r = self.rid(); self.rec(OSC, r)
        self.sidecar(OSC, r, H1, design_netlist_path="design/other.spice")
        self.assertEqual(self.get(r)["state"], "unknown")

    def test_conflicting_explicit(self):
        r = self.rid(); self.rec(OSC, r); self.sidecar(OSC, r, H1)
        self.j("%s/%s-extra.json" % (OSC, r), {"design_netlist_sha256": H2})
        e = self.get(r)
        self.assertEqual(e["state"], "unknown")
        self.assertIn("conflicting", e["reason"])

    def test_dirty_matches_snapshot(self):
        # Run consumed a dirty source (H2) while the filename commit holds H1.
        snap = "sim/oscillator-core/netlist-snapshots/r/design-vco.spice"
        r = self.rid(); self.rec(OSC, r)
        self.write(snap, SRC_V2)
        self.sidecar(OSC, r, H2, source_snapshot=snap)
        e = self.get(r)
        self.assertEqual(e["basis"], "explicit-source-hash+snapshot")
        self.assertEqual(e["state"], "superseded")  # source is still V1
        self.assertIn("dirty", e["reason"])
        # once the working source is the dirty one, the record is current
        self.write("design/vco.spice", SRC_V2)
        e = self.get(r)
        self.assertEqual(e["state"], "current")
        self.assertIn("dirty", e["reason"])

    def test_snapshot_conflict_and_missing(self):
        snap = "sim/oscillator-core/netlist-snapshots/r/design-vco.spice"
        r = self.rid(); self.rec(OSC, r)
        self.write(snap, SRC_V2)
        self.sidecar(OSC, r, H1, source_snapshot=snap)
        e = self.get(r)
        self.assertEqual(e["state"], "unknown")
        self.assertIn("conflicts", e["reason"])
        os.remove(os.path.join(self.d, snap))
        e = self.get(r)
        self.assertEqual(e["state"], "unknown")
        self.assertIn("absent", e["reason"])

    def test_snapshot_path_escape(self):
        r = self.rid(); self.rec(OSC, r)
        self.sidecar(OSC, r, H1, source_snapshot="../../etc/passwd")
        self.assertEqual(self.get(r)["state"], "unknown")

    def test_synthetic_component_unknown(self):
        r = self.rid(); self.rec(TANK, r)
        e = self.get(r)
        self.assertEqual((e["state"], e["basis"]), ("unknown", "not-applicable"))
        self.assertIn("synthetic", e["reason"])

    def test_synthetic_with_explicit_provenance_counts(self):
        r = self.rid(); self.rec(TANK, r); self.sidecar(TANK, r, H1)
        self.assertEqual(self.get(r)["state"], "current")

    def test_no_commit_in_name_unmapped(self):
        self.write(OSC + "/notes.txt", "x")
        e = [x for x in self.idx()["records"] if x["record_id"] is None][0]
        self.assertEqual(e["state"], "unknown")


class TestEnumeration(Fixture):
    def test_flat_companions_group_once_and_nested(self):
        r = self.rid()
        for n in ("%s.md", "%s-pilot.csv", "%s-method-check.csv",
                  "%s-curves/a.csv", "%s-curves/sub/b.csv"):
            self.write("%s/%s" % (OSC, n % r), "x")
        r2 = self.rid(ts="20261002-000000")
        self.write("%s/%s/reports/a.json" % (BN, r2), "{}")
        self.write("sim/inductor-model/em-extraction/records/%s.md" % r, "x")
        recs = self.idx()["records"]
        self.assertEqual(len([e for e in recs if e["path"].startswith(OSC)]), 1)
        self.assertEqual(self.get(r, OSC)["file_count"], 5)
        self.assertEqual(self.get(r2)["file_count"], 1)
        self.assertEqual(self.get(r, "sim/inductor-model/em-extraction")["family"],
                         "sim/inductor-model/em-extraction")
        self.assertEqual([e["path"] for e in recs], sorted(e["path"] for e in recs))

    def test_suffixed_ids(self):
        r = "20261001-000000-%s-0123abcd" % self.c1
        self.write("%s/%s.md" % (OSC, r), "x")
        self.write("%s/%s-pilot.csv" % (OSC, r), "x")
        self.assertEqual(self.get(r)["file_count"], 2)

    def test_deterministic_after_unrelated_commit(self):
        r = self.rid(); self.rec(OSC, r); self.rec(TANK, r)
        self.sidecar(OSC, r, H1)
        a = rc.render(self.idx())
        self.write("README.md", "unrelated")
        git(self.d, "add", "-A"); git(self.d, "commit", "-qm", "unrelated")
        self.assertEqual(a, rc.render(self.idx()))
        self.assertNotIn("timestamp", a)


class TestCitations(Fixture):
    def setUp(self):
        super().setUp()
        self.good = self.rid(); self.rec(OSC, self.good)
        self.sidecar(OSC, self.good, H1)
        self.stale = self.rid(ts="20261002-000000"); self.rec(OSC, self.stale)
        self.sidecar(OSC, self.stale, H2)
        self.unk = self.rid(ts="20261003-000000"); self.rec(OSC, self.unk)
        self.publish()

    def publish(self):
        self.write(rc.INDEX, rc.render(self.idx()))

    def cite(self, *paths):
        return rc.validate_citations(self.d, list(paths))

    def test_current_passes_including_companion(self):
        self.assertEqual(self.cite("%s/%s.md" % (OSC, self.good),
                                   "./%s/%s%s" % (OSC, self.good, rc.SIDECAR_SUFFIX)), [])

    def test_non_current_and_missing_rejected(self):
        for rid in (self.stale, self.unk):
            errs = self.cite("%s/%s.md" % (OSC, rid))
            self.assertEqual(len(errs), 1, errs)
        errs = self.cite("%s/20269999-000000-%s.md" % (OSC, self.c1))
        self.assertIn("missing", errs[0])

    def test_unmapped_rejected(self):
        self.write(OSC + "/notes.txt", "x")
        self.publish()
        errs = self.cite(OSC + "/notes.txt")
        self.assertIn("unmapped", errs[0])

    def test_non_sim_citation_ignored(self):
        self.assertEqual(self.cite("layout/drc/vco-drc-ihp.json"), [])

    def test_stale_index_rejected(self):
        self.write(rc.INDEX, "{}\n")
        errs = self.cite("%s/%s.md" % (OSC, self.good))
        self.assertTrue(any("stale" in e for e in errs))
        os.remove(os.path.join(self.d, rc.INDEX))
        errs = self.cite("%s/%s.md" % (OSC, self.good))
        self.assertTrue(any("missing" in e for e in errs))

    def test_fresh_not_index_decides(self):
        # Index committed while record was current; source then changes.
        self.write("design/vco.spice", SRC_V2)
        errs = self.cite("%s/%s.md" % (OSC, self.good))
        self.assertTrue(any("superseded" in e for e in errs))

    def test_manifest_files(self):
        self.j("m.json", {"evidence": {"2": {"file": "a", "content_hash": "x"},
                                       "3": {"file": "sim/x/records/y"}}})
        self.assertEqual(rc.manifest_files(os.path.join(self.d, "m.json")),
                         ["a", "sim/x/records/y"])

    def test_cli(self):
        script = os.path.join(HERE, "record_currency.py")
        run = lambda *a: subprocess.run(
            [sys.executable, "-I", script, "--root", self.d] + list(a),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode
        self.assertEqual(run("check"), 0)
        self.assertEqual(run("cite", "%s/%s.md" % (OSC, self.good)), 0)
        self.assertEqual(run("cite", "%s/%s.md" % (OSC, self.stale)), 1)
        self.write("design/vco.spice", SRC_V2)
        self.assertEqual(run("check"), 1)
        self.assertEqual(run("write"), 0)
        self.assertEqual(run("check"), 0)
        self.assertEqual(run("bogus"), 2)


class TestDeckIntegrity(Fixture):
    """Issue #143: report/deck integrity is independent of source currency."""

    def pair(self, r, stem, report_hash, deck="deck"):
        self.j("%s/%s/reports/%s.json" % (BN, r, stem),
               {"environment": {"netlist_sha256": report_hash}})
        self.write("%s/%s/decks/%s.spice" % (BN, r, stem), deck)

    def mismatched(self):
        r = self.rid(); self.rec(BN, r); self.sidecar(BN, r, H1)
        self.pair(r, "c", "a" * 64)
        self.write(rc.INDEX, rc.render(self.idx()))
        return r

    def cite(self, r):
        return rc.validate_citations(
            self.d, ["%s/%s.md" % (BN, r)])

    def test_matching_pair_passes(self):
        r = self.rid(); self.rec(BN, r); self.sidecar(BN, r, H1)
        self.pair(r, "c", hashlib.sha256(b"deck").hexdigest())
        self.write(rc.INDEX, rc.render(self.idx()))
        self.assertEqual(self.cite(r), [])
        errs, notes = rc.integrity_scan(self.idx())
        self.assertEqual(errs, [])
        self.assertIn("verified pairs: 1; unchecked unpaired reports: 0", notes)

    def test_mismatch_stays_current_but_fails(self):
        r = self.mismatched()
        self.assertEqual(self.get(r)["state"], "current")
        errs = self.cite(r)
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("reports/c.json", errs[0])
        self.assertIn("decks/c.spice", errs[0])
        self.assertTrue(rc.integrity_scan(self.idx())[0])

    def test_regenerating_index_does_not_clear_it(self):
        r = self.mismatched()
        self.write(rc.INDEX, rc.render(self.idx()))  # regenerate
        self.assertEqual(len(self.cite(r)), 1)
        self.assertTrue(rc.integrity_scan(self.idx())[0])

    def test_unpaired_is_unchecked_not_failure(self):
        r = self.rid(); self.rec(BN, r); self.sidecar(BN, r, H1)
        self.j("%s/%s/reports/c.json" % (BN, r),
               {"environment": {"netlist_sha256": "a" * 64}})
        self.write(rc.INDEX, rc.render(self.idx()))
        self.assertEqual(self.cite(r), [])
        errs, notes = rc.integrity_scan(self.idx())
        self.assertEqual(errs, [])
        self.assertTrue(any(n.startswith("UNCHECKED") for n in notes))
        self.assertIn("verified pairs: 0; unchecked unpaired reports: 1", notes)

    def test_justified_allowlist_only(self):
        r = self.mismatched()
        rep = self.get(r)["deck_integrity"]["mismatched"][0]
        idx = self.idx()
        self.assertEqual(rc.integrity_scan(idx, {rep: "historical, frozen"})[0], [])
        self.assertTrue(rc.integrity_scan(idx, {rep: ""})[0])

    def test_cli_integrity(self):
        script = os.path.join(HERE, "record_currency.py")
        run = lambda: subprocess.run(
            [sys.executable, "-I", script, "--root", self.d, "integrity"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode
        self.assertEqual(run(), 0)
        self.mismatched()
        self.assertEqual(run(), 1)


class TestRealTreeIndex(unittest.TestCase):
    def test_committed_index_is_wellformed(self):
        root = os.path.abspath(os.path.join(HERE, "..", ".."))
        p = os.path.join(root, rc.INDEX)
        if not os.path.exists(p):
            self.skipTest("no committed index")
        d = json.load(open(p))
        self.assertEqual(d["schema"], rc.SCHEMA)
        self.assertEqual(d["source_sha256"],
                         rc.sha256_file(os.path.join(root, rc.SOURCE)))


if __name__ == "__main__":
    unittest.main(verbosity=1)
