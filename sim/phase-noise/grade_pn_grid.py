#!/usr/bin/env python3
"""Grade spec row 4 (phase noise) over the 135-point row-10/11 corner set (issue #53).

Usage: grade_pn_grid.py CORNERS.csv [--out GRADED.csv]

CORNERS.csv, one row per corner the sweep attempted:
  process,temp_c,status,l_1mhz_dbc,l_10mhz_dbc,l_1mhz_sd_db,inductor_bar_db,
  n_plateau_min,plateau_ripple_max_s,f0_hz,job_id,raw_log
status is `pass` (the reducer published a valid summary) or anything else
(`sim_error`, `no_oscillation`, `invalid`, ...) for a corner that did not yield one --
those rows keep their raw_log and are LISTED, never dropped (sim/README.md rule 4).

THE RULE: row 4 is graded ONLY when all 135 expected corners are present, each
`pass`, and each has n_plateau_min >= 3 (the amplitude-transient evidence the widened
spacing exists to provide). Anything else prints `INCOMPLETE` and grades nothing; a
partial grid is evidence about the circuit, not a verdict on the row. Bounds are copies
of spec/target-spec.md row 4 (target / stretch), read-only.

When complete, the verdict is on the WORST corner's mean L(df); the non-PDK inductor
model's bar (sim/README.md rule 6) is reported and flags a verdict `BAR-SENSITIVE` when
the margin is smaller than the bar. The method statement and limits are the pilot's
(sim/phase-noise/README.md) and are restated in the record, not here.
"""
import csv, math, sys

MOS = ["tt", "ss", "ff", "sf", "fs"]; CAP = ["typ", "bcs", "wcs"]; HBT = ["typ", "bcs", "wcs"]
TEMPS = [-40, 27, 125]
ROW4 = {"l_1mhz_dbc": (-105.0, -115.0), "l_10mhz_dbc": (-125.0, -135.0)}  # (target, stretch)
MIN_N_PLATEAU = 3
EXPECTED = [(f"{m}_{c}_{h}", t) for m in MOS for c in CAP for h in HBT for t in TEMPS]
COLS = ["process", "temp_c", "status", "l_1mhz_dbc", "l_10mhz_dbc", "l_1mhz_sd_db", "inductor_bar_db",
        "n_plateau_min", "plateau_ripple_max_s", "f0_hz", "job_id", "raw_log"]


def fin(x):
    try:
        v = float(x)
    except (TypeError, ValueError):
        return None
    return v if math.isfinite(v) else None


def verdict(worst, target, stretch, bar):
    if worst is None:
        return "UNDETERMINED"
    v = ("TARGET AND STRETCH BOTH MET" if worst <= stretch
         else "TARGET MET / STRETCH NOT MET" if worst <= target else "TARGET NOT MET")
    margin = min(abs(worst - target), abs(worst - stretch)) if bar is not None else None
    if bar is not None and margin is not None and margin < bar:
        v += " (BAR-SENSITIVE: margin to the nearest bound < inductor-model bar)"
    return v


def grade(rows):
    """-> (graded: bool, report: list[str], per_corner: list[dict])"""
    by = {}
    dup = []
    for r in rows:
        k = (r["process"], int(r["temp_c"]))
        if k in by:
            dup.append(k)
        by[k] = r
    rep = []
    missing = [k for k in EXPECTED if k not in by]
    extra = [k for k in by if k not in set(EXPECTED)]
    bad = []  # (key, reason)
    for k in EXPECTED:
        r = by.get(k)
        if r is None:
            continue
        if r["status"] != "pass":
            bad.append((k, f"status={r['status']} raw_log={r.get('raw_log', '')}"))
        elif fin(r["l_1mhz_dbc"]) is None or fin(r["l_10mhz_dbc"]) is None:
            bad.append((k, "pass row with non-finite L"))
        elif (fin(r["n_plateau_min"]) or 0) < MIN_N_PLATEAU:
            bad.append((k, f"n_plateau_min={r['n_plateau_min']} < {MIN_N_PLATEAU}"))
    rep.append(f"corners expected {len(EXPECTED)}, present {len(by) - len(extra)}, "
               f"valid {len(EXPECTED) - len(missing) - len(bad)}")
    if dup:
        rep.append(f"duplicate rows for {len(dup)} corner(s): {dup[:5]}")
    if extra:
        rep.append(f"unexpected corners (not in the 135-point set): {extra[:5]}")
    for k in missing:
        rep.append(f"MISSING  {k[0]} {k[1]}C")
    for k, why in bad:
        rep.append(f"INVALID  {k[0]} {k[1]}C: {why}")
    if missing or bad or dup or extra:
        rep.append("row 4: INCOMPLETE -- not graded (a partial grid grades no row)")
        return False, rep, []
    per = []
    for off, key in (("1 MHz", "l_1mhz_dbc"), ("10 MHz", "l_10mhz_dbc")):
        target, stretch = ROW4[key]
        vals = [(float(by[k][key]), k) for k in EXPECTED]
        worst, wk = max(vals)
        best, bk = min(vals)
        bars = [fin(by[k]["inductor_bar_db"]) for k in EXPECTED]
        bar = max(b for b in bars if b is not None) if any(b is not None for b in bars) else None
        rep.append(f"row 4 @ {off}: worst {worst:.2f} dBc/Hz at {wk[0]} {wk[1]}C, best {best:.2f} at {bk[0]} {bk[1]}C; "
                   f"target {target:.0f} / stretch {stretch:.0f}; inductor-model bar "
                   f"{'n/a' if bar is None else '+-%.2f dB' % bar}: {verdict(worst, target, stretch, bar)}")
        per.append({"offset": off, "worst_dbc": worst, "worst_corner": f"{wk[0]}_{wk[1]}C",
                    "verdict": verdict(worst, target, stretch, bar)})
    return True, rep, per


def main(argv):
    if not argv:
        sys.exit(__doc__)
    rows = list(csv.DictReader(open(argv[0])))
    for c in COLS:
        if rows and c not in rows[0]:
            sys.exit(f"error: {argv[0]} lacks column {c}")
    graded, rep, per = grade(rows)
    print("\n".join(rep))
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
        try:
            fh = open(out, "x", newline="")
        except FileExistsError:
            sys.exit(f"error: {out} exists (records are append-only)")
        with fh:
            w = csv.writer(fh, lineterminator="\n")
            w.writerow(["graded", "offset", "worst_dbc", "worst_corner", "verdict"])
            if graded:
                for p in per:
                    w.writerow([True, p["offset"], f"{p['worst_dbc']:.3f}", p["worst_corner"], p["verdict"]])
            else:
                w.writerow([False, "", "", "", "INCOMPLETE"])


if __name__ == "__main__":
    main(sys.argv[1:])
