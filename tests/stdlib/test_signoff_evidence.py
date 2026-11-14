"""Known-answer tests for signoff/_evidence.py (issue #334; stdlib unittest only).

`_evidence.py` holds the scaffolding both `signoff/` generators speak: the
`kind: "generic"` envelope shape, the prefixed sha256 convention, the JSON
spelling and the manifest pin. These cases pin that contract, and the last
class is the anti-drift gate the dedup exists for -- it fails if the two
generators ever stop emitting one envelope skeleton.

Nothing here writes into the repository: the manifest cases use a temp dir.
"""
import hashlib
import json
import os
import tempfile
import unittest

from _loader import load_module

ev = load_module("signoff_evidence", "signoff/_evidence.py")
ch = load_module("signoff_characterization", "signoff/characterization.py")
inv = load_module("signoff_inventories", "signoff/inventories.py")


def skeleton(obj):
    """Key layout with every leaf replaced by its type name, order preserved."""
    if isinstance(obj, dict):
        return {k: skeleton(v) for k, v in obj.items()}
    return type(obj).__name__


class HashConvention(unittest.TestCase):
    def test_sha256_bytes_is_prefixed(self):
        self.assertEqual(ev.sha256_bytes(b"abc"), "sha256:" + hashlib.sha256(b"abc").hexdigest())

    def test_sha256_of_reads_the_file_under_root(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "a.txt"), "wb") as fh:
                fh.write(b"payload")
            self.assertEqual(ev.sha256_of("a.txt", ev.Path(d)), ev.sha256_bytes(b"payload"))

    def test_prefix_is_what_distinguishes_it_from_a_bare_digest(self):
        """The bare-hexdigest convention (record_currency.py) must not match."""
        self.assertTrue(ev.sha256_bytes(b"x").startswith("sha256:"))
        self.assertNotEqual(ev.sha256_bytes(b"x"), hashlib.sha256(b"x").hexdigest())


class Dump(unittest.TestCase):
    def test_two_space_indent_and_trailing_newline(self):
        self.assertEqual(ev.dump({"a": 1}), '{\n  "a": 1\n}\n')

    def test_key_insertion_order_is_preserved(self):
        self.assertEqual(list(json.loads(ev.dump({"b": 1, "a": 2}))), ["b", "a"])


class GenericEnvelope(unittest.TestCase):
    def envelope(self):
        return ev.generic_envelope(
            item=9, source_rel="signoff/evidence/x.json", status="pass",
            summary="s", content_hash="sha256:deadbeef",
        )

    def test_nine_key_contract_in_order(self):
        env = self.envelope()
        self.assertEqual(
            list(env),
            ["schema_version", "kind", "t1_item", "status", "summary", "source", "provenance"],
        )
        self.assertEqual(
            list(env["provenance"]),
            ["klt_version", "klayout_version", "pdk", "deck", "input"],
        )
        self.assertEqual(list(env["provenance"]["input"]), ["path", "content_hash"])
        self.assertEqual(list(env["provenance"]["input"]["path"]), ["path", "scope"])

    def test_source_and_bound_input_path_are_the_same_artifact(self):
        env = self.envelope()
        self.assertEqual(env["source"], env["provenance"]["input"]["path"]["path"])
        self.assertEqual(env["provenance"]["input"]["path"]["scope"], "repo")

    def test_tool_provenance_is_null_because_no_tool_runs(self):
        prov = self.envelope()["provenance"]
        for k in ("klt_version", "klayout_version", "pdk", "deck"):
            self.assertIsNone(prov[k], k)

    def test_kind_and_schema_version(self):
        env = self.envelope()
        self.assertEqual(env["kind"], "generic")
        self.assertEqual(env["schema_version"], ev.SCHEMA_VERSION)


class PinManifest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = ev.Path(self._tmp.name)

    def write(self, evidence):
        (self.root / "manifest.json").write_text(json.dumps({"block": "b", "evidence": evidence}))

    def read(self):
        return json.loads((self.root / "manifest.json").read_text())

    def test_pin_is_added_and_existing_pins_kept(self):
        self.write({"1": {"file": "a", "content_hash": "sha256:1"}})
        ev.pin_manifest(self.root, "manifest.json", {"8": {"file": "b", "content_hash": "sha256:8"}})
        self.assertEqual(
            self.read()["evidence"],
            {"1": {"file": "a", "content_hash": "sha256:1"},
             "8": {"file": "b", "content_hash": "sha256:8"}},
        )

    def test_keys_sort_numerically_so_10_follows_9(self):
        self.write({})
        ev.pin_manifest(self.root, "manifest.json", {
            "10": {"file": "j", "content_hash": "sha256:a"},
            "1": {"file": "k", "content_hash": "sha256:b"},
            "9": {"file": "l", "content_hash": "sha256:c"},
        })
        self.assertEqual(list(self.read()["evidence"]), ["1", "9", "10"])

    def test_repin_replaces_the_stale_hash(self):
        self.write({"8": {"file": "b", "content_hash": "sha256:old"}})
        ev.pin_manifest(self.root, "manifest.json", {"8": {"file": "b", "content_hash": "sha256:new"}})
        self.assertEqual(self.read()["evidence"]["8"]["content_hash"], "sha256:new")

    def test_written_with_the_shared_dump_spelling(self):
        self.write({})
        ev.pin_manifest(self.root, "manifest.json", {"8": {"file": "b", "content_hash": "sha256:8"}})
        text = (self.root / "manifest.json").read_text()
        self.assertEqual(text, ev.dump(json.loads(text)))


class OneEnvelopeSkeleton(unittest.TestCase):
    """The gate the dedup exists for: both generators, one envelope shape."""

    def test_both_generators_emit_the_same_skeleton(self):
        a = ch.envelope_for("report\n", "fail", "1 pass, 0 fail.")
        b = inv.envelope_for(9, "{}\n", 3)
        # Compare as JSON text so key *order* is compared at every level too.
        self.assertEqual(ev.dump(skeleton(a)), ev.dump(skeleton(b)))

    def test_both_bind_their_own_artifact_hash(self):
        report = "report\n"
        a = ch.envelope_for(report, "fail", "1 pass.")
        self.assertEqual(a["provenance"]["input"]["content_hash"], ev.sha256_bytes(report.encode()))
        inv_text = '{"inventory": "x"}\n'
        b = inv.envelope_for(9, inv_text, 3)
        self.assertEqual(b["provenance"]["input"]["content_hash"], ev.sha256_bytes(inv_text.encode()))

    def test_committed_envelopes_still_match_the_shared_skeleton(self):
        """Every envelope on disk must have the shape _evidence.py now defines."""
        reference = skeleton(ev.generic_envelope(
            item=1, source_rel="x", status="pass", summary="s", content_hash="sha256:0",
        ))
        root = ev.Path(ch.REPO_ROOT)
        committed = sorted((root / "signoff/evidence").glob("t1-item-*.json"))
        self.assertTrue(committed, "no committed envelopes found")
        for path in committed:
            with self.subTest(envelope=path.name):
                self.assertEqual(
                    ev.dump(skeleton(json.loads(path.read_text()))), ev.dump(reference)
                )

    def test_generators_share_one_definition_not_two(self):
        """Both generators must resolve to the *same* function objects.

        A re-introduced local copy in either module passes every shape test
        above while silently forking the contract again; identity does not.
        """
        self.assertIs(ch.dump, inv.dump)
        self.assertIs(ch.sha256_bytes, inv.sha256_bytes)
        self.assertIs(ch.sha256_of, inv.sha256_of)


if __name__ == "__main__":
    unittest.main()
