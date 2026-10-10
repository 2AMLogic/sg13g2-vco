#!/usr/bin/env python3
"""Classify sim/**/records/ as current | superseded | unknown against the
bytes of design/vco.spice (issue #122).

Currency is narrow: "was the design/vco.spice consumed by this run byte-equal
to today's design/vco.spice?" It says nothing about simulation validity,
grading completeness, or PDK/model currency. Records are append-only evidence
and are never edited; currency is computed here, outside the records, and
published as the derived index sim/record-currency.json.

Python stdlib only. Output is deterministic: sorted, no timestamps, and no
dependence on HEAD (the filename-commit context only names blobs of commits
that the record's own filename cites).

Usage (all take --root DIR, default: the repository containing this script):
  record_currency.py write            regenerate sim/record-currency.json
  record_currency.py check            fresh classification == committed index
  record_currency.py cite PATH...     validate citations of record files
  record_currency.py cite --manifest signoff/manifest.json
  record_currency.py show             print the fresh index on stdout
  record_currency.py integrity        fail on any known paired report/deck
                                      sha256 mismatch (issue #143)

See sim/README.md "Record currency" for states, limits and the schema.
"""

import hashlib
import json
import os
import posixpath
import re
import subprocess
import sys

SCHEMA = "sg13g2-vco/record-currency/1"
PROVENANCE_SCHEMA = "sg13g2-vco/source-provenance/1"
SOURCE = "design/vco.spice"
INDEX = "sim/record-currency.json"
SIDECAR_SUFFIX = "-source-provenance.json"
SIDECAR_NAME = "source-provenance.json"  # inside a directory record

# Experiment families whose runs derive their device section from SOURCE.
# Everything else (component/model characterization, synthetic A/B decks) is
# unknown unless a record carries explicit, documented source provenance.
DESIGN_DERIVED_FAMILIES = ("sim/oscillator-core", "sim/phase-noise")

HEX64 = re.compile(r"^[0-9a-f]{64}$")
RECORD_ID = re.compile(
    r"^(\d{8}-\d{6}-[0-9a-f]{7,40}(?:-[0-9a-f]{8})?)(?=$|[-.])")
COMMIT_PART = re.compile(r"^\d{8}-\d{6}-([0-9a-f]{7,40})")


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    with open(path, "rb") as f:
        return sha256_bytes(f.read())


def _git(root, *args):
    try:
        p = subprocess.run(["git", "-C", root] + list(args),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError:
        return 127, b"", b"git not available"
    return p.returncode, p.stdout, p.stderr


def is_shallow(root):
    rc, out, _ = _git(root, "rev-parse", "--is-shallow-repository")
    return rc == 0 and out.strip() == b"true"


# ---------------------------------------------------------------- enumerate

def record_roots(root):
    """Sorted repo-relative paths of every directory named records below sim/."""
    found = []
    base = os.path.join(root, "sim")
    for dp, dns, _ in os.walk(base):
        dns.sort()
        if os.path.basename(dp) == "records":
            found.append(os.path.relpath(dp, root).replace(os.sep, "/"))
            dns[:] = []  # records are leaves for root discovery
    return sorted(found)


def _files_under(root, rel):
    full = os.path.join(root, rel)
    if os.path.isdir(full) and not os.path.islink(full):
        out = []
        for dp, dns, fns in os.walk(full):
            dns.sort()
            for fn in sorted(fns):
                out.append(os.path.relpath(os.path.join(dp, fn),
                                           root).replace(os.sep, "/"))
        return out
    return [rel]


def group_records(root):
    """{(records_dir, id_or_None, entry_name_if_unmapped): [files]}."""
    groups = {}
    for rdir in record_roots(root):
        for name in sorted(os.listdir(os.path.join(root, rdir))):
            m = RECORD_ID.match(name)
            rid = m.group(1) if m else None
            key = (rdir, rid, None if rid else name)
            groups.setdefault(key, []).extend(
                _files_under(root, rdir + "/" + name))
    return {k: sorted(v) for k, v in groups.items()}


def family_of(rdir):
    return posixpath.dirname(rdir)


# ------------------------------------------------------------- provenance

def _walk_keys(obj, key):
    if isinstance(obj, dict):
        for k in sorted(obj):
            if k == key:
                yield obj[k]
            for v in _walk_keys(obj[k], key):
                yield v
    elif isinstance(obj, list):
        for v in obj:
            for x in _walk_keys(v, key):
                yield x


def _load_json(root, rel):
    try:
        with open(os.path.join(root, rel), "rb") as f:
            return json.loads(f.read().decode("utf-8")), None
    except (OSError, ValueError) as e:
        return None, str(e).splitlines()[0]


def _safe_rel(rel):
    if not isinstance(rel, str) or not rel or os.path.isabs(rel):
        return None
    n = posixpath.normpath(rel)
    if n == ".." or n.startswith("../") or n == ".":
        return None
    return n


def explicit_provenance(root, files):
    """Gather explicit design_netlist_sha256 values.

    Returns (values, snapshots, problems): values {hash: [origin files]},
    snapshots [(sidecar, rel-path)], problems [str] (malformed provenance).
    """
    values, snaps, problems = {}, [], []
    for rel in files:
        if not rel.endswith(".json"):
            continue
        data, err = _load_json(root, rel)
        is_sidecar = rel.endswith(SIDECAR_SUFFIX) or \
            posixpath.basename(rel) == SIDECAR_NAME
        if err is not None:
            if is_sidecar:
                problems.append("%s: unparsable provenance sidecar (%s)"
                                % (rel, err))
            continue
        found = list(_walk_keys(data, "design_netlist_sha256"))
        if is_sidecar and not found:
            problems.append("%s: provenance sidecar has no "
                            "design_netlist_sha256" % rel)
        for v in found:
            if not isinstance(v, str) or not HEX64.match(v):
                problems.append("%s: design_netlist_sha256 is not 64 "
                                "lowercase hex digits" % rel)
            else:
                values.setdefault(v, []).append(rel)
        if is_sidecar and isinstance(data, dict):
            p = data.get("design_netlist_path")
            if p is not None and p != SOURCE:
                problems.append("%s: design_netlist_path %r is not %s"
                                % (rel, p, SOURCE))
            s = data.get("source_snapshot")
            if s is not None:
                sp = _safe_rel(s)
                if sp is None:
                    problems.append("%s: source_snapshot %r is not a "
                                    "repository-relative path" % (rel, s))
                else:
                    snaps.append((rel, sp))
    return values, snaps, problems


def filename_commit(root, rid):
    """Context only: what the commit named in the filename says about SOURCE."""
    m = COMMIT_PART.match(rid or "")
    if not m:
        return {"id": None, "resolution": "absent", "source_sha256": None}
    c = m.group(1)
    rc, out, err = _git(root, "rev-parse", "--verify", c + "^{commit}")
    if rc != 0:
        text = err.decode("utf-8", "replace").lower()
        if "ambiguous" in text:
            res = "ambiguous"
        elif is_shallow(root):
            res = "unresolved-shallow-history"
        else:
            res = "unresolved"
        return {"id": c, "resolution": res, "source_sha256": None}
    full = out.decode().strip()
    rc, blob, _ = _git(root, "show", full + ":" + SOURCE)
    if rc != 0:
        return {"id": c, "resolution": "resolved-no-source",
                "source_sha256": None}
    return {"id": c, "resolution": "resolved",
            "source_sha256": sha256_bytes(blob)}


def deck_integrity(root, files):
    """Verify report netlist_sha256 only against an identified paired deck:
    <dir>/reports/<stem>.json <-> <dir>/decks/<stem>.spice."""
    fileset = set(files)
    checked = matched = unpaired = 0
    mismatched = []
    for rel in files:
        if not rel.endswith(".json"):
            continue
        d, base = posixpath.split(rel)
        if posixpath.basename(d) != "reports":
            continue
        data, err = _load_json(root, rel)
        if err is not None:
            continue
        hashes = sorted(set(x for x in _walk_keys(data, "netlist_sha256")
                            if isinstance(x, str)))
        if not hashes:
            continue
        deck = paired_deck(rel)
        if deck not in fileset:
            unpaired += 1
            continue
        checked += 1
        if hashes == [sha256_file(os.path.join(root, deck))]:
            matched += 1
        else:
            mismatched.append(rel)
    if not (checked or unpaired):
        return None
    return {"checked": checked, "matched": matched,
            "mismatched": sorted(mismatched), "unpaired": unpaired}


# Known paired report/deck mismatches in frozen historical evidence that are
# accepted by the integrity gate and by citation validation (issue #143).
# Maps the mismatched report path -> justification. Records are append-only
# and never edited, so a historical hit is dispositioned here, explicitly;
# an unjustified entry is itself an error. Empty: today's tree has no hits.
INTEGRITY_ALLOWLIST = {}


def paired_deck(report):
    d = posixpath.dirname(report)
    base = posixpath.basename(report)
    return posixpath.join(posixpath.dirname(d), "decks",
                          base[:-len(".json")] + ".spice")


def integrity_errors(entry, allowlist=None):
    """Error strings for known paired report/deck mismatches of an index
    entry, independent of its currency state. Unpaired reports are
    'unchecked', never an error."""
    allow = INTEGRITY_ALLOWLIST if allowlist is None else allowlist
    di = entry.get("deck_integrity")
    if not di:
        return []
    return ["record %s: report %s netlist_sha256 does not match its paired "
            "deck %s (report/deck integrity mismatch)"
            % (entry["record_id"], rep, paired_deck(rep))
            for rep in di["mismatched"] if not allow.get(rep)]


def integrity_scan(index, allowlist=None):
    """(errors, notes) over all index entries: errors are non-allowlisted
    mismatches; notes list verified/unchecked/allowlisted counts."""
    allow = INTEGRITY_ALLOWLIST if allowlist is None else allowlist
    errors, notes = [], []
    verified = unchecked = 0
    for e in index["records"]:
        errors.extend(integrity_errors(e, allow))
        di = e.get("deck_integrity")
        if not di:
            continue
        verified += di["matched"]
        if di["unpaired"]:
            unchecked += di["unpaired"]
            notes.append("UNCHECKED: record %s: %d report(s) carry "
                         "netlist_sha256 but have no paired deck "
                         "(legacy/unpaired; not verified, not a failure)"
                         % (e["record_id"], di["unpaired"]))
        for rep in di["mismatched"]:
            if allow.get(rep):
                notes.append("ALLOWLISTED: %s: %s" % (rep, allow[rep]))
    notes.append("verified pairs: %d; unchecked unpaired reports: %d"
                 % (verified, unchecked))
    return errors, notes


def primary_path(rdir, rid, name, files):
    if rid is None:
        return rdir + "/" + name
    for cand in (rdir + "/" + rid + ".md", rdir + "/" + rid):
        if cand in files or any(f.startswith(cand + "/") for f in files):
            return cand
    return files[0]


def classify_group(root, key, files, current):
    rdir, rid, name = key
    entry = {
        "record_id": rid,
        "path": primary_path(rdir, rid, name, files),
        "family": family_of(rdir),
        "file_count": len(files),
        "state": "unknown", "basis": "none", "reason": "",
        "design_netlist_sha256": None,
    }
    if rid is None:
        entry["reason"] = ("entry name carries no record id "
                           "(YYYYMMDD-HHMMSS-<commit>); cannot group or date it")
        return entry
    fc = filename_commit(root, rid)
    entry["filename_commit"] = fc
    di = deck_integrity(root, files)
    if di is not None:
        entry["deck_integrity"] = di

    values, snaps, problems = explicit_provenance(root, files)
    if problems:
        entry["basis"] = "malformed-explicit-provenance"
        entry["reason"] = "malformed explicit provenance: " + "; ".join(problems)
        return entry
    if len(values) > 1:
        entry["basis"] = "conflicting-explicit-provenance"
        entry["reason"] = ("conflicting design_netlist_sha256 values: " +
                           "; ".join("%s in %s" % (v[:12], ",".join(sorted(set(o))))
                                     for v, o in sorted(values.items())))
        return entry
    if values:
        (val, origins), = values.items()
        entry["design_netlist_sha256"] = val
        basis = "explicit-source-hash"
        for sidecar, sp in sorted(snaps):
            full = os.path.join(root, sp)
            if not os.path.isfile(full):
                entry["basis"] = "explicit-source-hash"
                entry["reason"] = ("%s declares source_snapshot %s but it is "
                                   "absent; explicit hash cannot be checked "
                                   "against the captured bytes" % (sidecar, sp))
                return entry
            if sha256_file(full) != val:
                entry["basis"] = "explicit-source-hash"
                entry["reason"] = ("explicit design_netlist_sha256 %s conflicts "
                                   "with captured source snapshot %s (%s)"
                                   % (val[:12], sp, sha256_file(full)[:12]))
                return entry
            basis = "explicit-source-hash+snapshot"
        entry["basis"] = basis
        note = ""
        if fc["source_sha256"] is not None and fc["source_sha256"] != val:
            note = (" The filename commit %s holds a different %s blob; "
                    "accepted as a dirty run because the consumed source is "
                    "identified by the explicit hash." % (fc["id"], SOURCE)
                    if basis.endswith("snapshot") else
                    " The filename commit %s holds a different %s blob "
                    "(dirty run?); the explicit hash is taken as the consumed "
                    "source." % (fc["id"], SOURCE))
        if val == current:
            entry["state"] = "current"
            entry["reason"] = ("explicit design_netlist_sha256 equals the "
                               "current %s." % SOURCE) + note
        else:
            entry["state"] = "superseded"
            entry["reason"] = ("explicit design_netlist_sha256 %s differs from "
                               "the current %s (%s)." % (val[:12], SOURCE,
                                                         current[:12])) + note
        return entry

    # No explicit source provenance.
    if entry["family"] not in DESIGN_DERIVED_FAMILIES:
        entry["basis"] = "not-applicable"
        entry["reason"] = ("component/model characterization or synthetic "
                           "comparison: not derived from %s and no documented "
                           "source provenance; currency does not apply."
                           % SOURCE)
        return entry
    if fc["resolution"] == "resolved":
        entry["basis"] = "filename-commit"
        entry["reason"] = ("filename-only provenance: the commit %s proves at "
                           "most the checkout the writer named, not a clean "
                           "tree or the inputs consumed; %s at that commit "
                           "hashes to %s (context, not currency)."
                           % (fc["id"], SOURCE, fc["source_sha256"][:12]))
    elif fc["resolution"] == "absent":
        entry["basis"] = "none"
        entry["reason"] = "no explicit source hash and no commit id in the name."
    else:
        entry["basis"] = "filename-commit"
        entry["reason"] = ("no explicit source hash; filename commit %s is %s"
                           % (fc["id"], fc["resolution"]))
    return entry


# ------------------------------------------------------------------ index

def build_index(root):
    src = os.path.join(root, SOURCE)
    if not os.path.isfile(src):
        raise SystemExit("record_currency: missing %s under %s" % (SOURCE, root))
    current = sha256_file(src)
    entries = [classify_group(root, k, f, current)
               for k, f in sorted(group_records(root).items(),
                                  key=lambda kv: (kv[0][0], kv[0][1] or "",
                                                  kv[0][2] or ""))]
    entries.sort(key=lambda e: e["path"])
    counts = {s: sum(1 for e in entries if e["state"] == s)
              for s in ("current", "superseded", "unknown")}
    return {"schema": SCHEMA, "source": SOURCE, "source_sha256": current,
            "counts": counts, "records": entries}


def render(index):
    return json.dumps(index, indent=2, sort_keys=True) + "\n"


def _strip_commit_context(index):
    idx = json.loads(json.dumps(index))
    for e in idx["records"]:
        e.pop("filename_commit", None)
        if e["basis"] == "filename-commit":
            e["reason"] = "<history-dependent>"
    return idx


def committed_matches_fresh(root, fresh):
    """(ok, message). In a shallow clone the filename-commit context cannot be
    resolved, so only history-independent fields are compared there."""
    path = os.path.join(root, INDEX)
    if not os.path.isfile(path):
        return False, "%s is missing; regenerate it with: %s write" % (
            INDEX, _cmd())
    with open(path, "rb") as f:
        raw = f.read()
    if raw == render(fresh).encode():
        return True, "%s is current" % INDEX
    if is_shallow(root):
        try:
            old = json.loads(raw.decode("utf-8"))
            if _strip_commit_context(old) == _strip_commit_context(fresh):
                return True, ("%s matches (shallow clone: filename-commit "
                              "context not compared)" % INDEX)
        except ValueError:
            pass
    return False, ("%s is stale or hand-edited (does not match the fresh "
                   "classification); regenerate it with: %s write"
                   % (INDEX, _cmd()))


def _cmd():
    return "python3 .github/scripts/record_currency.py"


# --------------------------------------------------------------- citations

def normalize_citation(p):
    if not isinstance(p, str):
        return None
    p = p.replace("\\", "/")
    n = posixpath.normpath(p)
    if n.startswith("./"):
        n = n[2:]
    if os.path.isabs(n) or n == ".." or n.startswith("../"):
        return None
    return n


def sim_record_root(n):
    """The `sim/**/records` directory a normalized path lies under, or None."""
    parts = n.split("/")
    if parts[0] != "sim":
        return None
    for i in range(1, len(parts) - 1):
        if parts[i] == "records":
            return "/".join(parts[:i + 1])
    return None


def validate_citations(root, paths, index=None):
    """Return list of error strings; empty means every sim citation is current
    (or there are none). Uses freshly computed currency, and additionally
    rejects a stale committed index."""
    cited = []
    for p in paths:
        n = normalize_citation(p)
        if n is not None and sim_record_root(n):
            cited.append((p, n))
        elif n is None and re.search(r"(^|[\\/])sim[\\/].*records[\\/]", str(p)):
            cited.append((p, None))
    if not cited:
        return []
    if index is None:
        index = build_index(root)
    errors = []
    ok, msg = committed_matches_fresh(root, index)
    if not ok:
        errors.append(msg)
    by_key = {}
    for e in index["records"]:
        rdir = posixpath.dirname(e["path"])
        by_key[(rdir, e["record_id"])] = e
    for orig, n in cited:
        if n is None:
            errors.append("%s: not a normalizable repository-relative path" % orig)
            continue
        rdir = sim_record_root(n)
        if not os.path.exists(os.path.join(root, n)):
            errors.append("%s: cited sim record file is missing" % n)
            continue
        first = n[len(rdir) + 1:].split("/")[0]
        m = RECORD_ID.match(first)
        e = by_key.get((rdir, m.group(1))) if m else None
        if e is None:
            errors.append("%s: ambiguous or unmapped: cannot map to exactly "
                          "one record id under %s" % (n, rdir))
            continue
        if e["state"] != "current":
            errors.append("%s: record %s is %s (basis %s): %s"
                          % (n, e["record_id"], e["state"], e["basis"],
                             e["reason"]))
        # Report/deck integrity is independent of source currency.
        errors.extend("%s: %s" % (n, m) for m in integrity_errors(e))
    return errors


def manifest_files(path):
    with open(path, "rb") as f:
        data = json.loads(f.read().decode("utf-8"))
    ev = data.get("evidence", {}) if isinstance(data, dict) else {}
    out = []
    if isinstance(ev, dict):
        for k in sorted(ev):
            v = ev[k]
            items = v if isinstance(v, list) else [v]
            for it in items:
                if isinstance(it, dict) and isinstance(it.get("file"), str):
                    out.append(it["file"])
    return out


# ------------------------------------------------------------------- main

def main(argv):
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    args = list(argv)
    if len(args) >= 2 and args[0] == "--root":
        root = os.path.abspath(args[1])
        args = args[2:]
    if not args:
        sys.stderr.write(__doc__)
        return 2
    cmd, rest = args[0], args[1:]
    if cmd == "show":
        sys.stdout.write(render(build_index(root)))
        return 0
    if cmd == "write":
        text = render(build_index(root))
        with open(os.path.join(root, INDEX), "w", encoding="utf-8") as f:
            f.write(text)
        print("wrote %s" % INDEX)
        return 0
    if cmd == "check":
        fresh = build_index(root)
        ok, msg = committed_matches_fresh(root, fresh)
        print(("OK: " if ok else "FAIL: ") + msg,
              file=sys.stdout if ok else sys.stderr)
        return 0 if ok else 1
    if cmd == "integrity":
        errors, notes = integrity_scan(build_index(root))
        for n in notes:
            print(n)
        for e in errors:
            print("FAIL: deck integrity: " + e, file=sys.stderr)
        if not errors:
            print("OK: no known report/deck integrity mismatches")
        return 1 if errors else 0
    if cmd == "cite":
        if len(rest) == 2 and rest[0] == "--manifest":
            try:
                files = manifest_files(os.path.join(root, rest[1]))
            except (OSError, ValueError) as e:
                print("FAIL: cannot read manifest %s: %s" % (rest[1], e),
                      file=sys.stderr)
                return 1
        elif rest and rest[0] != "--manifest":
            files = rest
        else:
            sys.stderr.write(__doc__)
            return 2
        errs = validate_citations(root, files)
        for e in errs:
            print("FAIL: sim citation: " + e, file=sys.stderr)
        if not errs:
            print("OK: no non-current sim record citations")
        return 1 if errs else 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
