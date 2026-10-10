"""Known-answer tests for sim/tools/svaricap_overlay.py (issue #95). No simulator."""
import hashlib
import os
import tempfile
import unittest

from _loader import load_module

ov = load_module("svaricap_overlay", "sim/tools/svaricap_overlay.py")

BODY = (b"* fixture\n.model dsubw d is = 2.45E-17 n = 4 vj = 0.1 m = 0.1052 cjp = 1e-09\n"
        b"* vj = 0.1 in a comment is not the card\n")


def spec_for(data):
    h = hashlib.sha256(data).hexdigest()
    return {"a.lib": h}


class PatchBytesTests(unittest.TestCase):
    def test_exact_single_substitution(self):
        out = ov.patch_bytes("a.lib", BODY, spec_for(BODY))
        self.assertEqual(out, BODY.replace(b"vj = 0.1 m", b"vj = 0.3357 m"))
        self.assertEqual(len(out), len(BODY) + 3)

    def test_unexpected_digest_refused(self):
        with self.assertRaisesRegex(ov.OverlayError, "not the expected v0.3.0 digest"):
            ov.patch_bytes("a.lib", BODY + b"* extra\n", spec_for(BODY))

    def test_already_fixed_detected_explicitly(self):
        fixed = BODY.replace(b"vj = 0.1 m", b"vj = 0.3357 m")
        with self.assertRaisesRegex(ov.OverlayError, "already carries the upstream fix"):
            ov.patch_bytes("a.lib", fixed, spec_for(fixed))

    def test_not_exactly_one_occurrence_refused(self):
        two = BODY + b".model d2 d vj = 0.1 m = 0.1052 x\n"
        with self.assertRaisesRegex(ov.OverlayError, "exactly one"):
            ov.patch_bytes("a.lib", two, spec_for(two))
        zero = BODY.replace(b"vj = 0.1 m", b"vj = 0.2 m")
        with self.assertRaisesRegex(ov.OverlayError, "exactly one"):
            ov.patch_bytes("a.lib", zero, spec_for(zero))

    def test_uncovered_file_refused(self):
        with self.assertRaises(ov.OverlayError):
            ov.patch_bytes("other.lib", BODY, spec_for(BODY))

    def test_inline_card(self):
        card = ov.overlaid_card()
        self.assertIn("vj = 0.3357 m = 0.1052", card)
        self.assertEqual(card, ov.V030_DSUBW_CARD.replace("vj = 0.1 ", "vj = 0.3357 "))

    def test_upstream_refs(self):
        self.assertEqual(ov.UPSTREAM["merge_commit"], "0243d867c6b7493526b141d2e4d74afa027e5b8e")
        self.assertTrue(ov.UPSTREAM["pull_request"].endswith("#1102"))


class ApplyTests(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.addCleanup(self._t.cleanup)
        self.d = self._t.name

    def write(self, name, data):
        with open(os.path.join(self.d, name), "wb") as fh:
            fh.write(data)

    def test_apply_is_all_or_none(self):
        other = BODY + b"* second\n"
        spec = {"a.lib": hashlib.sha256(BODY).hexdigest(),
                "b.lib": hashlib.sha256(other).hexdigest()}
        self.write("a.lib", BODY)
        self.write("b.lib", other + b"tamper")
        with self.assertRaises(ov.OverlayError):
            ov.apply(self.d, spec)
        with open(os.path.join(self.d, "a.lib"), "rb") as fh:
            self.assertEqual(fh.read(), BODY)    # a.lib not patched when b.lib refused
        self.write("b.lib", other)
        res = ov.apply(self.d, spec)
        self.assertEqual([r[0] for r in res], ["a.lib", "b.lib"])
        self.assertEqual(res[0][1], spec["a.lib"])

    def test_symlink_and_hardlink_refused(self):
        src = os.path.join(self._t.name + "-src")
        os.makedirs(src)
        self.addCleanup(lambda: __import__("shutil").rmtree(src, ignore_errors=True))
        real = os.path.join(src, "a.lib")
        with open(real, "wb") as fh:
            fh.write(BODY)
        spec = spec_for(BODY)
        os.symlink(real, os.path.join(self.d, "a.lib"))
        with self.assertRaises(ov.OverlayError):
            ov.apply(self.d, spec)
        os.unlink(os.path.join(self.d, "a.lib"))
        os.link(real, os.path.join(self.d, "a.lib"))
        with self.assertRaises(ov.OverlayError):
            ov.apply(self.d, spec)
        with open(real, "rb") as fh:
            self.assertEqual(fh.read(), BODY)    # the source was never written


if __name__ == "__main__":
    unittest.main()
