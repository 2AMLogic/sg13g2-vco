#!/usr/bin/env python3
"""svaricap_overlay.py -- the sanctioned run-local PDK model overlay (issue #95).

IHP-Open-PDK v0.3.0 ships sg13g2_svaricaphv_mod.lib and
sg13g2_svaricaphv_mod_mismatch.lib with the well-to-substrate diode card
`dsubw` at `vj = 0.1`.  ngspice's junction-capacitance temperature scaling
turns that into NaN above ~52.5 C once bn sits on the substrate (IHP-Open-PDK
issue #1098).  Merged PR #1102 (commit 0243d867c6b7493526b141d2e4d74afa027e5b8e)
changed `vj = 0.1` to `vj = 0.3357` in both files.  This repo stays pinned to
v0.3.0 (sim/pdk.json), so it applies EXACTLY that substitution, and nothing
else, to a PRIVATE COPY of the two files.  $PDK_ROOT is never written.

Fail-closed: a file is patched only if its sha256 is the v0.3.0 digest AND the
expected card text occurs exactly once.  A file that already carries the
upstream fix (a PDK pin that includes PR #1102) is reported as such and
refused -- the overlay is then unnecessary and must be removed, not
double-applied.  Any other content is refused.

CLI (used by sim/lib.sh apply_svaricap_vj_overlay):
    svaricap_overlay.py apply <models_dir> [--spec FILE]
        patch both files in <models_dir> in place (they must be private
        copies), print one line per file:  <name> <pre_sha256> <post_sha256>
    svaricap_overlay.py card
        print the overlaid dsubw card used by inlined decks
"""
import hashlib
import json
import os
import sys

UPSTREAM = {
    "issue": "IHP-GmbH/IHP-Open-PDK#1098",
    "pull_request": "IHP-GmbH/IHP-Open-PDK#1102",
    "merge_commit": "0243d867c6b7493526b141d2e4d74afa027e5b8e",
    "change": "dsubw vj = 0.1 -> vj = 0.3357",
}
OLD = b" vj = 0.1 m = 0.1052 "
NEW = b" vj = 0.3357 m = 0.1052 "
# sha256 of the v0.3.0 files (tarball sha256 pinned in sim/pdk.json).
DEFAULT_SPEC = {
    "sg13g2_svaricaphv_mod.lib":
        "1462f67e80da7f5fa6f6b51efb0eb0e4dc7ef2da28d8bfde95a19ce2a780580a",
    "sg13g2_svaricaphv_mod_mismatch.lib":
        "16da7669ee7e963645a604f64770d2f8d871fa8483c34e3dddaa9fcf01c51f50",
}
# The v0.3.0 dsubw card, verbatim, for decks that inline it.
V030_DSUBW_CARD = (".model dsubw d is = 2.45E-17 jsw = 5.959E-10 n = 4 ns = 1.029 "
                   "cjo = 1.444E-15 vj = 0.1 m = 0.1052 cjp = 1.117E-09 php = 0.457 "
                   "mjsw = 0.2595 fc = 0.95 cta = 1E-06")


class OverlayError(Exception):
    pass


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def patch_bytes(name, data, spec=None):
    """Return the overlaid bytes for v0.3.0 file <name>, or raise OverlayError."""
    spec = DEFAULT_SPEC if spec is None else spec
    if name not in spec:
        raise OverlayError("%s: not a file this overlay covers" % name)
    n_old, n_new = data.count(OLD), data.count(NEW)
    if n_new and not n_old:
        raise OverlayError(
            "%s already carries the upstream fix (vj = 0.3357, IHP-Open-PDK PR #1102): "
            "the PDK pin includes it, so this overlay is unnecessary -- remove it "
            "instead of double-patching" % name)
    got = sha256(data)
    if got != spec[name]:
        raise OverlayError("%s: sha256 %s is not the expected v0.3.0 digest %s"
                           % (name, got, spec[name]))
    if n_old != 1 or n_new != 0:
        raise OverlayError("%s: expected exactly one '%s', found %d (and %d already-fixed)"
                           % (name, OLD.decode().strip(), n_old, n_new))
    out = data.replace(OLD, NEW)
    if out.count(NEW) != 1 or out.count(OLD) != 0 or len(out) != len(data) + (len(NEW) - len(OLD)):
        raise OverlayError("%s: substitution did not have the intended effect" % name)
    return out


def overlaid_card():
    return patch_bytes_card(V030_DSUBW_CARD)


def patch_bytes_card(card):
    b = (" " + card + " ").encode()
    if b.count(OLD) != 1:
        raise OverlayError("inline dsubw card does not match the v0.3.0 text")
    return b.replace(OLD, NEW).decode().strip()


def apply(models_dir, spec=None):
    """Patch every covered file in <models_dir> atomically (all or none)."""
    spec = DEFAULT_SPEC if spec is None else spec
    staged = []
    for name in sorted(spec):
        path = os.path.join(models_dir, name)
        if not os.path.isfile(path) or os.path.islink(path):
            raise OverlayError("%s is missing or a symlink (the overlay needs a private copy)" % path)
        if os.stat(path).st_nlink > 1:
            raise OverlayError("%s is hardlinked; refusing to write through to another tree" % path)
        with open(path, "rb") as fh:
            data = fh.read()
        staged.append((name, path, sha256(data), patch_bytes(name, data, spec)))
    results = []
    for name, path, pre, new in staged:
        tmp = path + ".overlay-tmp"
        with open(tmp, "wb") as fh:
            fh.write(new)
        os.replace(tmp, path)
        results.append((name, pre, sha256(new)))
    return results


def main(argv):
    if len(argv) >= 2 and argv[0] == "card":
        print(overlaid_card())
        return 0
    if len(argv) >= 2 and argv[0] == "apply":
        spec = None
        if "--spec" in argv:
            with open(argv[argv.index("--spec") + 1]) as fh:
                spec = json.load(fh)
        try:
            for name, pre, post in apply(argv[1], spec):
                print("%s\t%s\t%s" % (name, pre, post))
        except OverlayError as e:
            print("svaricap_overlay: refused: %s" % e, file=sys.stderr)
            return 1
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
