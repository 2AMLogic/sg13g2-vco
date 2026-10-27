#!/usr/bin/env python3
"""Aggregated characterization report behind T1 item 8 (issue #261).

Item 8 asks for "one aggregated, current artifact summarizing per-spec-row
performance across conditions, with the evidence record each verdict rests
on". This module is its only writer and verifier:

* `build_report` derives `signoff/characterization.md` from three inputs and
  nothing else: the ratified table in `spec/target-spec.md`, the committed row
  map `signoff/characterization-rows.json` (row -> records, extractor,
  blocking issues) and the currency index `sim/record-currency.json`.
  It never parses free-form record markdown.
* A row is `pass`/`fail` only when every record its extractor reads is
  `current` in the index. Anything else is `pending`, and says why (the
  record's state, or the issue that still owes the graded run). Rows that are
  conditions of the others (device flavor, corner set, temperature range) are
  rendered `condition` and do not feed the verdict.
* The generic envelope's `status` is derived: `pass` only when at least one
  row is graded and every graded row is `pass`; otherwise `fail`. That is the
  finding while the graded runs (#50, #53) and the statistical/post-layout
  rows (#244, #260) are outstanding.
* `verify` regenerates everything in memory and names the row whose line no
  longer matches, so a changed record state, spec target or dropped row fails
  by name.

Pure stdlib. Reads `sim/` and never writes there.

    python3 -I signoff/characterization.py --check   # CI: fail on drift (default)
    python3 -I signoff/characterization.py --regen   # rewrite report, envelope, manifest pin
    (either accepts --root DIR, used by the drift tests)
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import operator
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

REPORT = "signoff/characterization.md"
ROW_MAP = "signoff/characterization-rows.json"
ENVELOPE = "signoff/evidence/t1-item-8-characterization.json"
MANIFEST = "signoff/manifest.json"
SPEC = "spec/target-spec.md"
CURRENCY = "sim/record-currency.json"

OPS = {">=": operator.ge, "<=": operator.le}
AGG = {"min": min, "max": max}


def sha256_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def sha256_of(rel: str, root: Path) -> str:
    return sha256_bytes((root / rel).read_bytes())


def _cells(line: str) -> list[str]:
    return [c.strip() for c in re.split(r"(?<!\\)\|", line.strip())[1:-1]]


def spec_rows(root: Path) -> dict[int, dict]:
    """Ratified rows of the summary table in spec/target-spec.md."""
    rows: dict[int, dict] = {}
    for line in (root / SPEC).read_text().splitlines():
        if not re.match(r"^\|\s*\d+\s*\|", line):
            continue
        c = _cells(line)
        if len(c) != 7:
            raise SystemExit(f"characterization: spec row has {len(c)} cells, want 7: {line[:60]}")
        n = int(c[0])
        if n in rows:
            raise SystemExit(f"characterization: spec row {n} appears twice")
        if "RATIFIED" not in c[6]:
            raise SystemExit(f"characterization: spec row {n} is not RATIFIED")
        target = "; ".join(f"{k} {v}" for k, v in zip(("min", "typ", "max"), c[2:5]) if v)
        rows[n] = {"parameter": c[1], "target": target or "(see condition)"}
    if not rows:
        raise SystemExit(f"characterization: no ratified rows found in {SPEC}")
    return rows


def _md(text: str) -> str:
    return re.sub(r"(?<!\\)\|", r"\\|", text).replace("\n", " ")


def _load_map(root: Path) -> dict[int, dict]:
    raw = json.loads((root / ROW_MAP).read_text())
    out: dict[int, dict] = {}
    for e in raw["rows"]:
        if e["row"] in out:
            raise SystemExit(f"characterization: row {e['row']} mapped twice in {ROW_MAP}")
        out[e["row"]] = e
    return out


def _index(root: Path) -> dict[str, dict]:
    return {r["path"]: r for r in json.loads((root / CURRENCY).read_text())["records"]}


def _grade(entry: dict, root: Path, index: dict[str, dict]) -> tuple[str, str, str, str]:
    """-> (verdict, measured, binding corner, why-pending)."""
    g = entry.get("grade")
    blocked = ", ".join(f"#{n}" for n in entry.get("blocked_by", []))
    if not g:
        return "pending", "-", "-", f"no graded record yet; owed by {blocked}" if blocked else "no graded record"
    state = index[g["record"]]["state"]
    if state != "current":
        return "pending", "-", "-", f"record {index[g['record']]['record_id'] or g['record']} is {state}"
    with open(root / g["csv"], newline="") as f:
        data = [r for r in csv.DictReader(f)]
    vals = []
    for r in data:
        try:
            v = float(r[g["column"]])
        except (KeyError, ValueError):
            continue
        if math.isfinite(v):
            vals.append((v, r))
    if not vals:
        return "pending", "-", "-", f"no finite {g['column']} values in {g['csv']}"
    worst, r = AGG[g["aggregate"]](vals, key=lambda t: t[0])
    corner = ", ".join(f"{c}={r[c]}" for c in g.get("corner_columns", []))
    ok = OPS[g["op"]](worst, g["limit"])
    unit = g.get("unit", "")
    return (
        "pass" if ok else "fail",
        f"{worst:.6g} {unit} ({g['aggregate']} of {len(vals)} corner rows, limit {g['op']} {g['limit']})".replace(" )", ")"),
        corner or "-",
        "",
    )


def row_lines(root: Path) -> tuple[dict[int, str], dict[int, str]]:
    """-> (n -> markdown table line, n -> verdict)."""
    spec, rmap, index = spec_rows(root), _load_map(root), _index(root)
    if spec.keys() - rmap.keys():
        raise SystemExit(f"characterization: spec rows with no entry in {ROW_MAP}: {sorted(spec.keys() - rmap.keys())}")
    if rmap.keys() - spec.keys():
        raise SystemExit(f"characterization: {ROW_MAP} cites rows the spec lacks: {sorted(rmap.keys() - spec.keys())}")
    lines: dict[int, str] = {}
    verdicts: dict[int, str] = {}
    for n in sorted(spec):
        e = rmap[n]
        links = []
        for rec in e.get("records", []):
            if rec not in index:
                raise SystemExit(f"characterization: row {n}: {rec} is not in {CURRENCY}")
            if not (root / rec).exists():
                raise SystemExit(f"characterization: row {n}: {rec} does not exist")
            links.append(f"[{index[rec]['record_id'] or Path(rec).name}](../{rec}) ({index[rec]['state']})")
        for p in e.get("evidence", []):
            if not (root / p).exists():
                raise SystemExit(f"characterization: row {n}: {p} does not exist")
            links.append(f"[{Path(p).name}](../{p})")
        g = e.get("grade")
        if g and (g["record"] not in e.get("records", []) or g["record"] not in index):
            raise SystemExit(f"characterization: row {n}: grade.record must be one of the row's records")
        if e["kind"] == "condition":
            verdict, measured, corner = "condition", "-", "-"
            why = ""
        else:
            verdict, measured, corner, why = _grade(e, root, index)
        verdicts[n] = verdict
        shown = f"{verdict}: {why}" if why and verdict != "condition" else verdict
        lines[n] = (
            f"| {n} | {_md(spec[n]['parameter'])} | {_md(spec[n]['target'])} | {_md(measured)} | "
            f"{_md(corner)} | {_md(shown)} | {'<br>'.join(links) or 'none yet'} |"
        )
    return lines, verdicts


HEADER = """# Characterization report (T1 item 8)

<!-- GENERATED by signoff/characterization.py --regen. Do not edit by hand:
     `--check` (check-all.sh signoff-characterization) fails CI on any drift. -->

One line per ratified row of `spec/target-spec.md`. The target is copied from
that table; the measured value and verdict come only from a record that
`sim/record-currency.json` classifies `current` (see
`signoff/characterization-rows.json`). Every other state renders `pending`
with the reason, never a number. Records linked on a `pending` row are the
orientation records for that row, shown with their currency state; they grade
nothing. A `condition` row is a condition of the others, not a measured
quantity.

| Row | Parameter | Target | Measured (binding value over corner rows) | Binding corner | Verdict | Evidence record |
|---|---|---|---|---|---|---|
"""


def derived_status(verdicts: dict[int, str]) -> str:
    graded = [v for v in verdicts.values() if v != "condition"]
    return "pass" if graded and all(v == "pass" for v in graded) else "fail"


def build_report(root: Path) -> tuple[str, str]:
    lines, verdicts = row_lines(root)
    counts = {k: sum(1 for v in verdicts.values() if v == k) for k in ("pass", "fail", "pending", "condition")}
    status = derived_status(verdicts)
    body = HEADER + "\n".join(lines[n] for n in sorted(lines)) + "\n"
    body += (
        f"\n**Summary:** {counts['pass']} pass, {counts['fail']} fail, {counts['pending']} pending, "
        f"{counts['condition']} condition. Envelope status (derived): `{status}`.\n"
        f"\n**Inputs:** `{SPEC}` {sha256_of(SPEC, root)[:19]}, `{ROW_MAP}` {sha256_of(ROW_MAP, root)[:19]}, "
        f"`{CURRENCY}` {sha256_of(CURRENCY, root)[:19]}.\n"
    )
    return body, status


def dump(obj: dict) -> str:
    return json.dumps(obj, indent=2) + "\n"


def envelope_for(report_text: str, status: str, counts_line: str) -> dict:
    return {
        "schema_version": 1,
        "kind": "generic",
        "t1_item": 8,
        "status": status,
        "summary": (
            "Aggregated characterization report for T1 item 8: one line per ratified spec row "
            f"(signoff/characterization.md), generated from spec/target-spec.md and "
            "sim/record-currency.json. " + counts_line.rstrip(".") + "." + " A row grades only from a record "
            "whose currency is `current`; status is `pass` only when every graded row passes. "
            "A `fail` here means the graded evidence is not yet current and passing, "
            "not that a row was measured and missed."
        ),
        "source": REPORT,
        "provenance": {
            "klt_version": None,
            "klayout_version": None,
            "pdk": None,
            "deck": None,
            "input": {
                "path": {"path": REPORT, "scope": "repo"},
                "content_hash": sha256_bytes(report_text.encode()),
            },
        },
    }


def _counts_line(report_text: str) -> str:
    m = re.search(r"\*\*Summary:\*\* ([^\n]*?) Envelope status", report_text)
    return (m.group(1) if m else "") + "."


def regen(root: Path = REPO_ROOT) -> None:
    text, status = build_report(root)
    (root / REPORT).write_text(text)
    (root / ENVELOPE).parent.mkdir(parents=True, exist_ok=True)
    (root / ENVELOPE).write_text(dump(envelope_for(text, status, _counts_line(text))))
    manifest = json.loads((root / MANIFEST).read_text())
    manifest["evidence"]["8"] = {"file": ENVELOPE, "content_hash": sha256_bytes(text.encode())}
    manifest["evidence"] = dict(sorted(manifest["evidence"].items(), key=lambda kv: int(kv[0])))
    (root / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")


def verify(root: Path = REPO_ROOT) -> list[str]:
    errors: list[str] = []
    try:
        fresh, status = build_report(root)
    except SystemExit as exc:
        return [str(exc)]
    if not (root / REPORT).is_file():
        return [f"{REPORT} missing (run --regen)"]
    committed = (root / REPORT).read_text()
    if committed != fresh:
        old = {int(m.group(1)): l for l in committed.splitlines() if (m := re.match(r"^\| (\d+) \|", l))}
        new = {int(m.group(1)): l for l in fresh.splitlines() if (m := re.match(r"^\| (\d+) \|", l))}
        for n in sorted(old.keys() | new.keys()):
            if n not in new:
                errors.append(f"row {n}: in the report but no longer a ratified spec row")
            elif n not in old:
                errors.append(f"row {n}: ratified in the spec but missing from the report")
            elif old[n] != new[n]:
                errors.append(f"row {n}: report line no longer matches its inputs (spec target, record or currency state changed)")
        if not errors:
            errors.append("report header, summary or input digests no longer match its inputs")
    env_path = root / ENVELOPE
    if not env_path.is_file():
        errors.append(f"{ENVELOPE} missing (run --regen)")
        return errors
    env = json.loads(env_path.read_text())
    rhash = sha256_bytes(committed.encode())
    if env.get("t1_item") != 8 or env.get("kind") != "generic":
        errors.append("envelope is not a generic t1_item 8 envelope")
    if env["status"] != status:
        errors.append(f"envelope status is '{env['status']}' but the rows derive '{status}'")
    if env["provenance"]["input"]["content_hash"] != rhash:
        errors.append("envelope is not bound to the current report bytes")
    cited = json.loads((root / MANIFEST).read_text())["evidence"].get("8", {})
    if cited.get("file") != ENVELOPE or cited.get("content_hash") != rhash:
        errors.append("signoff/manifest.json does not cite item 8 at the current report hash")
    return errors


def main(argv: list[str]) -> int:
    args = argv[1:]
    root = REPO_ROOT
    if "--root" in args:
        i = args.index("--root")
        root = Path(args[i + 1]).resolve()
        del args[i : i + 2]
    mode = args[0] if args else "--check"
    if mode == "--regen":
        regen(root)
        print("regenerated signoff/characterization.md, the item 8 envelope and its manifest pin")
        return 0
    if mode != "--check":
        print(__doc__, file=sys.stderr)
        return 2
    errors = verify(root)
    for e in errors:
        print(f"FAIL: {e}", file=sys.stderr)
    if errors:
        print(
            "Refresh deliberately with: python3 -I signoff/characterization.py --regen, then re-render "
            "signoff/t1-report.json (see signoff/README.md).",
            file=sys.stderr,
        )
        return 1
    print("OK: signoff/characterization.md matches its inputs (T1 item 8)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
