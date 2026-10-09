#!/usr/bin/env python3
"""Friction-ledger gate (issue #146). Stdlib only, offline, PDK-free.

Reads .github/klt-friction-ledger.json and enforces:
  1. every citation of an upstream tool-tracker issue in a tracked authored
     file (the forms "klayout-tools" + "#N", "klayout-tools #N" and
     "klayout-tools/issues/N") has a ledger entry;
  2. every ledger entry's workaround paths exist in the tree;
  3. every entry was verified against the klt version in .github/klt-version,
     unless its "reverified" field names that same version.

sim/**/records/ files are read for citations but never edited: historical
evidence is append-only, so the ledger covers their citations instead.
The upstream tracker is never queried; statuses are hand-maintained.

Usage: check_klt_friction.py [--root DIR]
Exit 0 clean, 1 violations, 2 usage / unreadable ledger.
"""
import json
import os
import re
import subprocess
import sys

LEDGER = ".github/klt-friction-ledger.json"
PIN = ".github/klt-version"
STATUSES = {"open", "closed", "merged"}
CITE = re.compile(r"klayout-tools(?:\s?#|/issues/)(\d+)")
SKIP_PREFIXES = (".loom/", ".git/", "node_modules/")
VERSION = re.compile(r"^\d+(\.\d+)*$")


def tracked_files(root):
    if os.path.isdir(os.path.join(root, ".git")):
        try:
            out = subprocess.run(
                ["git", "-C", root, "ls-files", "-z"],
                check=True, capture_output=True).stdout
            return [p for p in out.decode().split("\0") if p]
        except (OSError, subprocess.CalledProcessError):
            pass
    found = []
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in (".git", "node_modules", ".loom")]
        for f in files:
            found.append(os.path.relpath(os.path.join(d, f), root))
    return sorted(found)


def citations(root):
    """Return {issue number: sorted list of files citing it}."""
    cites = {}
    for rel in tracked_files(root):
        rel = rel.replace(os.sep, "/")
        if rel == LEDGER or rel.startswith(SKIP_PREFIXES):
            continue
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (UnicodeDecodeError, OSError):
            continue
        for m in CITE.finditer(text):
            cites.setdefault(int(m.group(1)), set()).add(rel)
    return {n: sorted(v) for n, v in cites.items()}


def check(root):
    errors = []
    try:
        with open(os.path.join(root, PIN), encoding="utf-8") as fh:
            pin = fh.read().strip()
        with open(os.path.join(root, LEDGER), encoding="utf-8") as fh:
            ledger = json.load(fh)
    except (OSError, ValueError) as exc:
        return None, ["cannot read %s / %s: %s" % (PIN, LEDGER, exc)]
    entries = ledger.get("entries") if isinstance(ledger, dict) else None
    if not isinstance(entries, list):
        return None, ["%s: top level must be an object with an 'entries' list" % LEDGER]

    numbers = set()
    for i, e in enumerate(entries):
        where = "%s entry %d" % (LEDGER, i)
        if not isinstance(e, dict) or not isinstance(e.get("number"), int):
            errors.append("%s: needs an integer 'number'" % where)
            continue
        n = e["number"]
        where = "ledger entry #%d" % n
        if n in numbers:
            errors.append("%s: duplicate entry" % where)
        numbers.add(n)
        if not isinstance(e.get("gap"), str) or not e["gap"].strip():
            errors.append("%s: missing one-line 'gap' description" % where)
        if e.get("status") not in STATUSES:
            errors.append("%s: status must be one of %s" % (where, sorted(STATUSES)))
        if not isinstance(e.get("status_checked_on"), str) or not e["status_checked_on"]:
            errors.append("%s: missing 'status_checked_on' date" % where)
        ver = e.get("klt_version_verified")
        if not isinstance(ver, str) or not VERSION.match(ver):
            errors.append("%s: 'klt_version_verified' must be a version string" % where)
        elif ver != pin and e.get("reverified") != pin:
            errors.append(
                "%s: STALE - verified against klt %s but %s pins %s; re-check "
                "the upstream status and workarounds, then update "
                "klt_version_verified (or set reverified to %s)"
                % (where, ver, PIN, pin, pin))
        wk = e.get("workarounds")
        if not isinstance(wk, list) or not all(isinstance(p, str) for p in wk):
            errors.append("%s: 'workarounds' must be a list of paths" % where)
            continue
        for p in wk:
            if not os.path.exists(os.path.join(root, p)):
                errors.append("%s: workaround path does not exist: %s" % (where, p))

    for n, files in sorted(citations(root).items()):
        if n not in numbers:
            errors.append(
                "uncited-in-ledger: upstream issue #%d is cited in %s but has no "
                "entry in %s" % (n, ", ".join(files), LEDGER))
    return len(entries), errors


def main(argv):
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    args = argv[1:]
    if args[:1] == ["--root"] and len(args) == 2:
        root = args[1]
    elif args:
        sys.stderr.write(__doc__.split("Usage:")[1].split("\n")[0].strip() + "\n")
        return 2
    root = os.path.abspath(root)
    count, errors = check(root)
    if count is None:
        sys.stderr.write("FAIL: %s\n" % errors[0])
        return 2
    for e in errors:
        sys.stderr.write("FAIL: %s\n" % e)
    if errors:
        return 1
    print("friction ledger OK: %d entries, all citations covered, all verified against klt %s"
          % (count, open(os.path.join(root, PIN)).read().strip()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
