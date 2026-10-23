#!/usr/bin/env python3
"""Offline gate for manifests/artifacts/*.manifest.json (issue #253).

Evidence bytes live in the fleet artifact store; git keeps only a manifest
naming each object by sha256. This checker needs no broker and no `klt`
(the pinned klt predates `klt artifact`); `klt artifact verify <manifest>`
stays a fleet-worker step. It fails when

  * a manifest is not {"schema_version": 1, "entries": [...]} or an entry
    departs from the klt artifact entry shape (exactly sha256, size, kind,
    producer{tool,version,loom.repo,commit}, uri, optional name/media_type),
  * an entry's uri is not `artifact:<key>` with <key> ending in its sha256,
  * a manifest names a storage location (s3://, arn:aws:),
  * the bytes of a stored object are also committed: any git-tracked file
    outside manifests/ whose size and sha256 match an entry.

Usage: check_artifact_manifests.py [--root DIR]
Exit:  0 pass (zero manifests is a pass), 1 failure, 2 usage error.
Stdlib only; run with `python3 -I`.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

MANIFEST_DIR = "manifests/artifacts"
REQUIRED = ("sha256", "size", "kind", "producer", "uri")
OPTIONAL = ("name", "media_type")
PRODUCER = ("tool", "version", "loom.repo", "commit")
KINDS = ("evidence", "transcript", "log", "pdk")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
URI_RE = re.compile(r"^artifact:([^/\s]\S*)$")
LOCATION_RE = re.compile(r"s3://|arn:aws:")


def entry_problems(entry):
    if not isinstance(entry, dict):
        return ["entry is not an object"]
    out = []
    missing = [f for f in REQUIRED if f not in entry]
    extra = sorted(set(entry) - set(REQUIRED) - set(OPTIONAL))
    if missing:
        out.append("missing " + ", ".join(missing))
    if extra:
        out.append("unknown field(s) " + ", ".join(extra))
    sha = entry.get("sha256")
    if not isinstance(sha, str) or not SHA_RE.match(sha):
        out.append("sha256 must be 64 lowercase hex digits")
    size = entry.get("size")
    if not isinstance(size, int) or isinstance(size, bool) or size < 1:
        out.append("size must be a positive integer")
    if entry.get("kind") not in KINDS:
        out.append("kind must be one of " + ", ".join(KINDS))
    prod = entry.get("producer")
    if not isinstance(prod, dict):
        out.append("producer is not an object")
    else:
        if set(prod) != set(PRODUCER):
            out.append("producer must carry exactly " + ", ".join(PRODUCER))
        for k in PRODUCER[:3]:
            if not isinstance(prod.get(k), str) or not prod.get(k):
                out.append("producer.%s must be a non-empty string" % k)
        if prod.get("commit") is not None and not isinstance(prod.get("commit"), str):
            out.append("producer.commit must be a string or null")
    uri = entry.get("uri")
    m = URI_RE.match(uri) if isinstance(uri, str) else None
    if not m:
        out.append("uri must be artifact:<key>")
    elif m.group(1).rsplit("/", 1)[-1] != sha:
        out.append("uri key does not end in the entry's sha256")
    for k in OPTIONAL:
        if k in entry and not isinstance(entry[k], str):
            out.append("%s must be a string" % k)
    return out


def manifest_problems(text):
    """(problems, entries) for one manifest's text."""
    if LOCATION_RE.search(text):
        return ["names a storage location (s3:// or arn:aws:)"], []
    try:
        doc = json.loads(text)
    except ValueError as exc:
        return ["not valid JSON: %s" % exc], []
    if (not isinstance(doc, dict) or doc.get("schema_version") != 1
            or set(doc) != {"schema_version", "entries"}
            or not isinstance(doc["entries"], list)):
        return ['not {"schema_version": 1, "entries": [...]}'], []
    out = []
    for i, e in enumerate(doc["entries"]):
        out += ["entries[%d]: %s" % (i, p) for p in entry_problems(e)]
    return out, ([] if out else doc["entries"])


def file_sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def tracked_files(root):
    res = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                         capture_output=True)
    if res.returncode != 0:
        raise RuntimeError("git ls-files failed in %s" % root)
    return [p.decode() for p in res.stdout.split(b"\0") if p]


def check(root):
    """List of failure strings for the tree at root."""
    failures = []
    mdir = os.path.join(root, MANIFEST_DIR)
    stored = {}  # (size, sha256) -> manifest path
    names = sorted(os.listdir(mdir)) if os.path.isdir(mdir) else []
    for name in names:
        rel = "%s/%s" % (MANIFEST_DIR, name)
        if name == "README.md":
            continue
        if not name.endswith(".manifest.json"):
            failures.append("%s: not a *.manifest.json file" % rel)
            continue
        with open(os.path.join(mdir, name), encoding="utf-8") as f:
            probs, entries = manifest_problems(f.read())
        failures += ["%s: %s" % (rel, p) for p in probs]
        for e in entries:
            stored[(e["size"], e["sha256"])] = rel
    if stored:
        for rel in tracked_files(root):
            if rel.startswith("manifests/"):
                continue
            path = os.path.join(root, rel)
            try:
                if os.path.islink(path) or not os.path.isfile(path):
                    continue
                size = os.path.getsize(path)
            except OSError:
                continue
            if not any(s == size for s, _ in stored):
                continue
            hit = stored.get((size, file_sha256(path)))
            if hit:
                failures.append("%s: bytes are committed but stored by %s" % (rel, hit))
    return failures


def main(argv):
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    args = argv[1:]
    if args[:1] == ["--root"] and len(args) == 2:
        root = os.path.abspath(args[1])
    elif args:
        print(__doc__.split("\n\n")[0] + "\nusage: check_artifact_manifests.py [--root DIR]",
              file=sys.stderr)
        return 2
    failures = check(root)
    for f in failures:
        print("FAIL: " + f, file=sys.stderr)
    print("artifact manifests: %d failure(s)" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
