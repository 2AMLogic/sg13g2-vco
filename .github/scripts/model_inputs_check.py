#!/usr/bin/env python3
"""Committed model-input integrity gate (issue #139).

Stdlib only, no PDK, no git, no simulator. For every retained model-input
manifest  sim/<experiment>/records/<id>-model-inputs.json  (schema
sg13g2-vco/model-inputs/1, written by sim/oscillator-core/osc_bench.sh,
issue #133) this verifies the *committed* bytes:

  * the manifest is well-formed JSON of the documented schema, its record_id
    equals the id in its filename, digests are 64 lowercase hex characters,
    and (role, bundle_path) identities, bundle paths and retained snapshots
    are unique;
  * every non-null retained_snapshot is a safe repo-relative path that lies in
    the owning record's snapshot namespace
        sim/<experiment>/netlist-snapshots/<id>/model-inputs/<bundle_path>
    (no absolute path, backslash, '.'/'..' segment or symlink), exists as a
    regular file, and hashes to the declared sha256;
  * retained_snapshot null (external roles: PDK libraries, built OSDI binary)
    is accepted -- identified by digest only, never demanded.

Only the manifest and the retained snapshot files are ever read. Live model
files (the inductor model, PDK, `original_path`) are never opened, so editing
today's model cannot invalidate a historical capture. Records with no
manifest (written before #133, or unreserved runs) are reported as
"legacy / not checked" -- they are not counted as verified.

This gate is separate from record currency (record_currency.py), which
concerns design/vco.spice only and ignores these manifests.

Usage: model_inputs_check.py [--root DIR] check
Exit 0 = every present manifest verified; 1 = at least one finding.
"""
import argparse
import hashlib
import json
import os
import posixpath
import re
import sys

SCHEMA = "sg13g2-vco/model-inputs/1"
SUFFIX = "-model-inputs.json"
HEX64 = re.compile(r"^[0-9a-f]{64}$")
RECORD_ID = re.compile(
    r"^(\d{8}-\d{6}-[0-9a-f]{7,40}(?:-[0-9a-f]{8})?)(?=$|[-.])")
FULL_ID = re.compile(r"^\d{8}-\d{6}-[0-9a-f]{7,40}(?:-[0-9a-f]{8})?$")
TOP_KEYS = {"schema", "record_id", "note", "inputs"}
TOP_REQUIRED = {"schema", "record_id", "inputs"}
INPUT_KEYS = {"role", "bundle_path", "sha256", "original_path",
              "retained_snapshot"}


def _reject_dup(pairs):
    d = {}
    for k, v in pairs:
        if k in d:
            raise ValueError("duplicate JSON key %r" % k)
        d[k] = v
    return d


def _reject_const(c):
    raise ValueError("non-standard JSON constant %s" % c)


def safe_rel(rel):
    """True if rel is a normalised, relative, forward-slash path with no
    '.'/'..' segments and no NUL/backslash."""
    if not isinstance(rel, str) or not rel:
        return False
    if "\\" in rel or "\x00" in rel or rel.startswith("/"):
        return False
    if re.match(r"^[A-Za-z]:", rel):
        return False
    parts = rel.split("/")
    if any(p in ("", ".", "..") for p in parts):
        return False
    return posixpath.normpath(rel) == rel


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _no_symlinks(root, rel):
    cur = root
    for part in rel.split("/"):
        cur = os.path.join(cur, part)
        if os.path.islink(cur):
            return False
    return True


def find_manifests_and_legacy(root):
    """-> (manifests, legacy): manifests = [(rel_manifest, records_dir, id)],
    legacy = sorted record ids (with records dir) lacking a manifest."""
    manifests, legacy = [], []
    base = os.path.join(root, "sim")
    for dp, dns, fns in os.walk(base):
        dns.sort()
        if os.path.basename(dp) != "records":
            continue
        dns[:] = []
        rdir = os.path.relpath(dp, root).replace(os.sep, "/")
        names = sorted(os.listdir(dp))
        ids = set()
        for n in names:
            if n.endswith(SUFFIX):
                manifests.append((rdir + "/" + n, rdir, n[:-len(SUFFIX)]))
            m = RECORD_ID.match(n)
            if m:
                ids.add(m.group(1))
        have = {n[:-len(SUFFIX)] for n in names if n.endswith(SUFFIX)}
        legacy.extend((rdir, i) for i in sorted(ids - have))
    return sorted(manifests), sorted(legacy)


def check_manifest(root, rel, rdir, rid):
    """-> (errors, n_verified, n_external)."""
    errs = []

    def err(msg):
        errs.append("%s: %s" % (rel, msg))

    if not FULL_ID.match(rid):
        err("filename does not carry a record id "
            "(expected <YYYYMMDD-HHMMSS-commit>%s)" % SUFFIX)
        return errs, 0, 0
    try:
        with open(os.path.join(root, rel), "rb") as f:
            raw = f.read()
        doc = json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_dup,
                         parse_constant=_reject_const)
    except (OSError, UnicodeDecodeError, ValueError) as e:
        err("cannot parse as JSON (%s); regenerate it with osc_bench.sh" % e)
        return errs, 0, 0
    if not isinstance(doc, dict):
        err("top level must be a JSON object")
        return errs, 0, 0
    missing = sorted(TOP_REQUIRED - set(doc))
    extra = sorted(set(doc) - TOP_KEYS)
    if missing:
        err("missing key(s): %s" % ", ".join(missing))
    if extra:
        err("unknown key(s): %s" % ", ".join(extra))
    if doc.get("schema") != SCHEMA:
        err("schema is %r, expected %r" % (doc.get("schema"), SCHEMA))
    if "record_id" in doc and doc["record_id"] != rid:
        err("record_id %r does not match the record id %r in the filename"
            % (doc["record_id"], rid))
    if "note" in doc and not isinstance(doc["note"], str):
        err("note must be a string")
    inputs = doc.get("inputs")
    if not isinstance(inputs, list) or not inputs:
        err("inputs must be a non-empty list")
        return errs, 0, 0

    exp = posixpath.dirname(rdir)
    ns = "%s/netlist-snapshots/%s/model-inputs/" % (exp, rid)
    seen_id, seen_bp, seen_snap = set(), set(), set()
    verified = external = 0
    for i, ent in enumerate(inputs):
        w = "inputs[%d]" % i
        if not isinstance(ent, dict):
            err("%s must be an object" % w)
            continue
        miss = sorted(INPUT_KEYS - set(ent))
        ext = sorted(set(ent) - INPUT_KEYS)
        if miss:
            err("%s missing key(s): %s" % (w, ", ".join(miss)))
        if ext:
            err("%s unknown key(s): %s" % (w, ", ".join(ext)))
        ok_types = True
        for k in ("role", "bundle_path", "sha256", "original_path"):
            if k in ent and (not isinstance(ent[k], str) or not ent[k]):
                err("%s.%s must be a non-empty string" % (w, k))
                ok_types = False
        if "retained_snapshot" in ent and ent["retained_snapshot"] is not None \
                and not isinstance(ent["retained_snapshot"], str):
            err("%s.retained_snapshot must be a string or null" % w)
            ok_types = False
        if miss or not ok_types:
            continue
        role, bp, sha = ent["role"], ent["bundle_path"], ent["sha256"]
        snap = ent["retained_snapshot"]
        if not HEX64.match(sha):
            err("%s sha256 %r is not 64 lowercase hex characters" % (w, sha))
        if not safe_rel(bp):
            err("%s bundle_path %r is not a safe relative path" % (w, bp))
        if (role, bp) in seen_id:
            err("%s duplicate bundle identity (role %r, bundle_path %r)"
                % (w, role, bp))
        seen_id.add((role, bp))
        if bp in seen_bp:
            err("%s duplicate bundle_path %r" % (w, bp))
        seen_bp.add(bp)
        if snap is None:
            external += 1
            continue
        if not safe_rel(snap):
            err("%s retained_snapshot %r is absolute, contains '.', '..', "
                "empty or backslash segments, or is not normalised" % (w, snap))
            continue
        if not snap.startswith(ns) or len(snap) == len(ns):
            err("%s retained_snapshot %r is outside this record's snapshot "
                "namespace %s" % (w, snap, ns))
            continue
        if safe_rel(bp) and snap != ns + bp:
            err("%s retained_snapshot %r does not equal namespace + "
                "bundle_path (%s)" % (w, snap, ns + bp))
            continue
        if snap in seen_snap:
            err("%s duplicate retained_snapshot %r" % (w, snap))
            continue
        seen_snap.add(snap)
        full = os.path.join(root, snap)
        if not _no_symlinks(root, snap):
            err("%s retained_snapshot %r traverses a symlink" % (w, snap))
            continue
        if not os.path.isfile(full):
            err("%s retained snapshot %s is missing; commit it with the "
                "manifest (netlist-snapshots are append-only)" % (w, snap))
            continue
        try:
            got = sha256_file(full)
        except OSError as e:
            err("%s cannot read %s (%s)" % (w, snap, e))
            continue
        if HEX64.match(sha) and got != sha:
            err("%s retained snapshot %s hashes to %s but the manifest "
                "declares %s" % (w, snap, got, sha))
            continue
        if HEX64.match(sha):
            verified += 1
    return errs, verified, external


def run(root, out=sys.stdout, errout=sys.stderr):
    manifests, legacy = find_manifests_and_legacy(root)
    errors, ok_m, snaps, ext = [], 0, 0, 0
    for rel, rdir, rid in manifests:
        e, v, x = check_manifest(root, rel, rdir, rid)
        if e:
            errors.extend(e)
        else:
            ok_m += 1
        snaps += v
        ext += x
    for rdir, rid in legacy:
        print("legacy / not checked (no model-input manifest): %s/%s"
              % (rdir, rid), file=out)
    for e in errors:
        print("error: " + e, file=errout)
    print("model-inputs: %d manifest(s) verified (%d retained snapshot(s) "
          "hash-checked, %d external role(s) digest-only), %d legacy record(s) "
          "not checked, %d error(s)"
          % (ok_m, snaps, ext, len(legacy), len(errors)), file=out)
    return 1 if errors else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    ap.add_argument("cmd", choices=["check"])
    a = ap.parse_args(argv)
    return run(os.path.abspath(a.root))


if __name__ == "__main__":
    sys.exit(main())
