#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""lvsdb_summary.py -- read a KLayout .lvsdb and print its compare verdict as JSON.

    lvsdb_summary.py <run.lvsdb>

IHP's run_lvs.py exits 0 whether or not the netlists match, and its log only
says "Netlists don't match".  The verdict of record therefore comes from the
comparison database KLayout itself wrote: this reads it back through
klayout.db.LayoutVsSchematic and reports, per circuit pair, every net, device
and pin cross-reference entry that is not a plain match, plus the device
census of each side (by device class), plus the comparer's own log messages
(`compare_log`: e.g. the "Port mismatch" findings of the runset's strict
top-port check, `flag_missing_ports`, which the klayout.db API does not
expose, so they are read from the file's cross-reference section).  Nothing
is inferred: every field is read from the database.
"""

from __future__ import annotations

import collections
import json
import re
import sys

import klayout.db as kdb

ST = kdb.NetlistCrossReference
_STATUS = {ST.Match: "match", ST.Mismatch: "mismatch", ST.NoMatch: "nomatch",
           ST.Skipped: "skipped", ST.MatchWithWarning: "match_with_warning",
           ST.None_: "none"} if hasattr(ST, "None_") else None


def status_name(s) -> str:
    if _STATUS is not None and s in _STATUS:
        return _STATUS[s]
    return str(s).split(".")[-1].lower()


def dev_desc(d):
    if d is None:
        return None
    dc = d.device_class()
    terms = {}
    for t in dc.terminal_definitions():
        n = d.net_for_terminal(t.id())
        terms[t.name] = n.expanded_name() if n is not None else None
    prm = {p.name: round(d.parameter(p.id()), 6) for p in dc.parameter_definitions()}
    return {"name": d.expanded_name(), "class": dc.name, "terminals": terms,
            "parameters": prm}


def census(circuit):
    c = collections.Counter()
    if circuit is not None:
        for d in circuit.each_device():
            c[d.device_class().name] += 1
    return dict(sorted(c.items()))


# Short form (what KLayout's LVS DSL writes): Z( ... M(E B('msg')) ...);
# long form (LayoutVsSchematic.write): xref( ... entry(error description('msg'))).
_MSG = re.compile(r"(?:M|entry)\((E|W|I|error|warning|info)\b[^'()]*?"
                  r"(?:B|description)\('((?:[^'\\]|\\.)*)'\)")
_SEV = {"E": "error", "W": "warning", "I": "info",
        "error": "error", "warning": "warning", "info": "info"}


def compare_log(text):
    """The comparer's log messages: every M(<sev> B('<msg>')) entry of the
    cross-reference section (the top-level `Z(` / `xref(` block of an .lvsdb)."""
    m = re.search(r"^(?:Z|xref)\($", text, re.M)
    if not m:
        return []
    return [{"severity": _SEV[sev], "message": re.sub(r"\\(.)", r"\1", msg)}
            for sev, msg in _MSG.findall(text[m.end():])]


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    lvs = kdb.LayoutVsSchematic()
    lvs.read(argv[1])
    xref = lvs.xref()
    circuits = []
    all_match = True
    for cp in xref.each_circuit_pair():
        a, b = cp.first(), cp.second()
        cstat = status_name(xref.circuit_pair_status(cp) if hasattr(
            xref, "circuit_pair_status") else cp.status())
        entry = {"layout": a.name if a else None,
                 "reference": b.name if b else None,
                 "status": cstat,
                 "devices": {"layout": census(a), "reference": census(b)},
                 "nets": {"matched": 0, "pairs": [], "not_matched": []},
                 "device_pairs": {"matched": 0, "not_matched": []},
                 "pins": {"matched": 0, "not_matched": []}}
        for np_ in xref.each_net_pair(cp):
            s = status_name(np_.status())
            if s == "match":
                entry["nets"]["matched"] += 1
                entry["nets"]["pairs"].append({
                    "layout": np_.first().expanded_name(),
                    "reference": np_.second().expanded_name()})
            else:
                entry["nets"]["not_matched"].append({
                    "status": s,
                    "layout": np_.first().expanded_name() if np_.first() else None,
                    "reference": np_.second().expanded_name() if np_.second() else None})
        for dp in xref.each_device_pair(cp):
            s = status_name(dp.status())
            if s == "match":
                entry["device_pairs"]["matched"] += 1
            else:
                entry["device_pairs"]["not_matched"].append({
                    "status": s, "layout": dev_desc(dp.first()),
                    "reference": dev_desc(dp.second())})
        for pp in xref.each_pin_pair(cp):
            s = status_name(pp.status())
            if s == "match":
                entry["pins"]["matched"] += 1
            else:
                entry["pins"]["not_matched"].append({
                    "status": s,
                    "layout": pp.first().expanded_name() if pp.first() else None,
                    "reference": pp.second().expanded_name() if pp.second() else None})
        if cstat != "match":
            all_match = False
        circuits.append(entry)
    with open(argv[1], encoding="utf-8", errors="replace") as f:
        log = compare_log(f.read())
    out = {"verdict": "match" if (all_match and circuits) else "mismatch",
           "circuits": circuits, "compare_log": log}
    json.dump(out, sys.stdout, indent=2, sort_keys=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
