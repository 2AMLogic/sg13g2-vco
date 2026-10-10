#!/usr/bin/env python3
"""analyze.py <record-dir> -- fold the per-request klt sim reports of a
run_tank_ab.sh record into <record-dir>/tank-ab.csv and tank-ab-delta.csv.

Q here is the PHASE-BANDWIDTH Q of the differential impedance: f0/(f_m45-f_p45),
the frequencies where the phase of Z is -45/+45 degrees (the half-power points
of an ideal parallel RLC, but not exactly for this non-ideal tank).  f0 is the
zero-phase crossing.  Each value is one deterministic AC solve, so it has no
sampling variance; its numerical resolution is the sweep step (2 MHz) -- about
+-0.05 % on f0 and +-0.5 % on Q here.

Validation and coverage (issue #166).  A corner is reduced to numbers only if
f0, f_p45, f_m45 and zpk are finite real numbers (not bool), positive, ordered
f_p45 < f0 < f_m45, and the resulting Q is finite and positive; otherwise the
row is "NO-VALUE (<reason>)" with blank derived columns.  When the record has
decks/<name>.request.json, every expected (variant, point, process,
temperature) gets exactly one outcome in tank-ab-coverage.csv: ok, NO-VALUE,
NO-REPORT, MISSING-CORNER, DUPLICATE-CORNER or UNEXPECTED-CORNER.  Records
without request files get one COVERAGE-UNCHECKED row per report; a request file
that is present but unreadable/malformed gets REQUEST-UNREADABLE instead.
Nothing is invented.  A corner whose process is not a string or whose
temperature_c is not a finite real number (not bool/str/NaN/inf) is INVALID
("NO-VALUE (malformed corner: ...)") and never affects the other corners.  A record with
neither report JSON nor request JSON gets one EMPTY-INVENTORY row (a gap, also
reported on stderr).  Exit status: 0 whenever the analysis completes (gaps are in the
CSVs and a stderr summary); with --strict, 2 if any coverage gap or invalid
"pass" corner was found.  Model failures (corner status != pass, e.g. the
known +125 C dsubw NaN) never affect the exit status: that is spec/evidence,
not tool health.
"""
import csv, glob, json, math, os, sys

args = [a for a in sys.argv[1:] if a != "--strict"]
strict = "--strict" in sys.argv[1:]
rec = args[0]


def isnum(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def validate_corner(m):
    """m: measurement name -> value.  Returns (ok, reason, q)."""
    for k in ("f0", "f_p45", "f_m45", "zpk"):
        if m.get(k) is None:
            return False, "missing " + k, None
        if not isnum(m[k]):
            return False, "non-numeric or non-finite " + k, None
        if m[k] <= 0:
            return False, "non-positive " + k, None
    if not (m["f_p45"] < m["f0"] < m["f_m45"]):
        return False, "violates f_p45 < f0 < f_m45", None
    q = m["f0"] / (m["f_m45"] - m["f_p45"])
    if not (isnum(q) and q > 0):
        return False, "invalid Q", None
    return True, "", q


def fmt_t(t):
    return int(t) if float(t).is_integer() else t


def expected_corners(rec, name):
    """(set of (process, float temp), None) from decks/<name>.request.json.

    Returns (None, None) when the request file is absent (legacy record) and
    (None, why) when it is present but unreadable or malformed."""
    p = os.path.join(rec, "decks", name + ".request.json")
    if not os.path.exists(p):
        return None, None
    try:
        with open(p) as fh:
            cs = json.load(fh)["corners"]
        procs = [x["name"] for x in cs["process"]]
        temps = list(cs["temperature_c"])
        if not procs or not temps:
            raise ValueError("empty corner list")
        if not all(isinstance(pr, str) for pr in procs):
            raise ValueError("non-string process name")
        if not all(isnum(t) for t in temps):
            raise ValueError("non-numeric or non-finite temperature")
        return {(pr, float(t)) for pr in procs for t in temps}, None
    except Exception as e:
        return None, "request unreadable: %s" % type(e).__name__


def corner_key(c):
    """(process, float temp) for a well-formed corner dict, else None."""
    if not isinstance(c, dict):
        return None
    proc, temp = c.get("process"), c.get("temperature_c")
    if not isinstance(proc, str) or not isnum(temp):
        return None
    return (proc, float(temp))


rows = []
cov = []
state = {"gap": False}


def covrow(variant, point, process, temp, outcome, detail=""):
    cov.append(dict(variant=variant, point=point, process=process, temp_c=temp,
                    outcome=outcome, detail=detail))
    if outcome in ("NO-REPORT", "MISSING-CORNER", "DUPLICATE-CORNER", "UNEXPECTED-CORNER",
                   "COVERAGE-UNCHECKED", "REQUEST-UNREADABLE", "INVALID",
                   "EMPTY-INVENTORY"):
        state["gap"] = True


def split_name(name):
    parts = name.split("__")
    return (parts[0], parts[1]) if len(parts) == 2 else (name, "")


def no_report(name, why):
    variant, point = split_name(name)
    rows.append(dict(variant=variant, point=point, mim="", temp_c="", status="NO-REPORT"))
    exp, req_err = expected_corners(rec, name)
    if req_err:
        covrow(variant, point, "", "", "REQUEST-UNREADABLE", req_err)
    if exp is None:
        covrow(variant, point, "", "", "NO-REPORT", why)
    else:
        for pr, t in sorted(exp):
            covrow(variant, point, pr, fmt_t(t), "NO-REPORT", why)


def reduce_report(name, d):
    variant, point = split_name(name)
    try:
        cell = json.load(open(os.path.join(rec, "decks", name + ".cell.json")))
        mos, vctrl = cell["mos"], cell["vctrl"]
        cell_err = None if isnum(vctrl) and isinstance(mos, str) else "bad cell.json values"
    except Exception:
        mos = vctrl = ""
        cell_err = "cell.json unreadable"
    job = (d.get("environment", {}).get("remote") or {}).get("job_id") if isinstance(
        d.get("environment"), dict) else None
    exp, req_err = expected_corners(rec, name)
    corners = d.get("corners", [])
    if not isinstance(corners, list):
        corners = []
    # corner_key only ever returns None or a (str, finite float) tuple, so the
    # counting below cannot raise on odd input (unhashable process etc.).
    keys = [corner_key(c) for c in corners]
    seen = {}
    for k in keys:
        if k is not None:
            seen[k] = seen.get(k, 0) + 1
    for c, k in zip(corners, keys):
        try:
            proc = c.get("process", "") if isinstance(c, dict) else ""
            temp = c.get("temperature_c", "") if isinstance(c, dict) else ""
            if k is None:
                # only echo scalar identifiers; never write NaN/inf/lists to CSV
                proc = proc if isinstance(proc, str) else ""
                temp = temp if isnum(temp) else ""
                why = "malformed corner"
                if isinstance(c, dict):
                    if not isinstance(c.get("process"), str):
                        why = "malformed corner: process not a string"
                    else:
                        why = "malformed corner: temperature not a finite number"
                rows.append(dict(variant=variant, mos=mos, vctrl_v=vctrl, mim=proc, temp_c=temp,
                                 status="NO-VALUE (%s)" % why, job=job))
                covrow(variant, point, proc, temp, "INVALID", why)
                continue
            m = {}
            for x in c.get("measurements", []) if isinstance(c.get("measurements"), list) else []:
                if isinstance(x, dict) and "name" in x:
                    m[x["name"]] = x.get("value")
            diag = "; ".join(str(x.get("message", ""))[:60] for x in (c.get("diagnostics") or [])[:1]
                             if isinstance(x, dict)) if isinstance(c.get("diagnostics"), list) else ""
            passed = c.get("status") == "pass"
            ok, reason, q = validate_corner(m) if passed else (False, "", None)
            invalid_pass = passed and not ok
            if passed and ok and cell_err:
                ok, reason = False, cell_err
                invalid_pass = True
            outcome_detail = reason
            if seen[k] > 1:
                status, ok = "DUPLICATE-CORNER", False
                covrow(variant, point, proc, temp, "DUPLICATE-CORNER", "appears %d times" % seen[k])
            elif exp is not None and k not in exp:
                status, ok = "UNEXPECTED-CORNER", False
                covrow(variant, point, proc, temp, "UNEXPECTED-CORNER", "not in request")
            else:
                if ok:
                    status = "ok"
                elif invalid_pass:
                    status = "NO-VALUE (%s)" % reason
                else:
                    status = "NO-VALUE (" + diag + ")"
                if invalid_pass:
                    covrow(variant, point, proc, temp, "INVALID", outcome_detail)
                elif exp is None:
                    pass
                else:
                    covrow(variant, point, proc, temp, "ok" if ok else "NO-VALUE", outcome_detail or diag)
            zpk = m.get("zpk")
            rows.append(dict(variant=variant, mos=mos, vctrl_v=vctrl, mim=proc, temp_c=temp,
                             status=status,
                             f0_ghz=round(m["f0"] / 1e9, 5) if ok else None,
                             zpk_ohm=zpk if isnum(zpk) else None,
                             q_phase45=round(q, 3) if ok else None, job=job))
        except Exception as e:  # one bad corner must not stop the others
            rows.append(dict(variant=variant, mos=mos, vctrl_v=vctrl, status="NO-VALUE (error: %s)" % type(e).__name__))
            covrow(variant, point, "", "", "INVALID", "error: %s" % type(e).__name__)
    if req_err:
        covrow(variant, point, "", "", "REQUEST-UNREADABLE", req_err)
    elif exp is None:
        covrow(variant, point, "", "", "COVERAGE-UNCHECKED", "no decks/%s.request.json" % name)
    else:
        for pr, t in sorted(exp):
            if (pr, t) not in seen:
                covrow(variant, point, pr, fmt_t(t), "MISSING-CORNER", "")


names = set()
for p in sorted(glob.glob(os.path.join(rec, "reports", "*.json"))):
    names.add(os.path.basename(p)[:-5])
for p in sorted(glob.glob(os.path.join(rec, "decks", "*.request.json"))):
    names.add(os.path.basename(p)[:-len(".request.json")])
if not names:
    covrow("", "", "", "", "EMPTY-INVENTORY",
           "no reports/*.json and no decks/*.request.json found in " + rec)
    print("EMPTY-INVENTORY: no report or request evidence in %s" % rec, file=sys.stderr)
for name in sorted(names):
    p = os.path.join(rec, "reports", name + ".json")
    if not os.path.exists(p):
        no_report(name, "no report file")
        continue
    try:
        d = json.load(open(p))
        if not isinstance(d, dict):
            raise ValueError("not an object")
    except Exception:
        no_report(name, "unparseable report")
        continue
    reduce_report(name, d)

flds = ["variant", "mos", "vctrl_v", "mim", "temp_c", "status", "f0_ghz", "zpk_ohm", "q_phase45", "job"]
with open(os.path.join(rec, "tank-ab.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, flds, extrasaction="ignore"); w.writeheader(); w.writerows(rows)
key = lambda r: (r.get("mos"), r.get("vctrl_v"), r.get("mim"), r.get("temp_c"))
base = {key(r): r for r in rows if r["variant"] == "bn-tank" and r["status"] == "ok"}
out = []
skipped = 0
for r in rows:
    if r["variant"] == "bn-tank" or r["status"] != "ok":
        continue
    b = base.get(key(r))
    if not b:
        continue
    if not all(isnum(b[k]) and b[k] > 0 for k in ("f0_ghz", "q_phase45", "zpk_ohm")):
        skipped += 1
        continue
    d = dict(variant=r["variant"], mos=r["mos"], vctrl_v=r["vctrl_v"], mim=r["mim"],
             temp_c=r["temp_c"], f0_old_ghz=b["f0_ghz"], f0_new_ghz=r["f0_ghz"],
             df0_pct=round(100 * (r["f0_ghz"] / b["f0_ghz"] - 1), 2),
             q_old=b["q_phase45"], q_new=r["q_phase45"],
             dq_pct=round(100 * (r["q_phase45"] / b["q_phase45"] - 1), 2),
             zpk_ratio=round(r["zpk_ohm"] / b["zpk_ohm"], 3),
             q_scaling_db=round(20 * math.log10(r["q_phase45"] / b["q_phase45"]), 2))
    if not all(isnum(v) for k, v in d.items() if k.endswith(("_pct", "_ratio", "_db"))):
        skipped += 1
        continue
    out.append(d)
if skipped:
    covrow("", "", "", "", "DELTA-SKIPPED", "%d pair(s) with zero/invalid baseline" % skipped)
flds2 = ["variant", "mos", "vctrl_v", "mim", "temp_c", "f0_old_ghz", "f0_new_ghz", "df0_pct",
         "q_old", "q_new", "dq_pct", "zpk_ratio", "q_scaling_db"]
with open(os.path.join(rec, "tank-ab-delta.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, flds2); w.writeheader(); w.writerows(out)
print(len(rows), "rows;", len(out), "paired deltas")

# tuning ratio at the two ends of the Vctrl domain (tt MOS corner only: the
# other MOS corners were run at band-centre Vctrl 1.5 only)
by = {}
for r in rows:
    if r["status"] == "ok" and r.get("mos") == "tt":
        by[(r["variant"], r["mim"], r["temp_c"], r["vctrl_v"])] = r["f0_ghz"]
tun = []
try:
    items = sorted(by.items())
except TypeError:  # mixed-type keys from odd inputs: stable textual order
    items = sorted(by.items(), key=lambda kv: tuple(map(str, kv[0])))
for (v, mim, t, vc), f in items:
    if vc != 0.0 or (v, mim, t, 3.3) not in by:
        continue
    fmax, fmin = f, by[(v, mim, t, 3.3)]
    if not (isnum(fmin) and fmin > 0 and isnum(fmax)):
        skipped += 1
        continue
    tun.append(dict(variant=v, mim=mim, temp_c=t, f0_vctrl0_ghz=fmax, f0_vctrl3p3_ghz=fmin,
                    fmax_over_fmin=round(fmax / fmin, 4)))
with open(os.path.join(rec, "tank-ab-tuning.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, list(tun[0]) if tun else ["variant", "mim", "temp_c", "f0_vctrl0_ghz", "f0_vctrl3p3_ghz", "fmax_over_fmin"]); w.writeheader(); w.writerows(tun)
with open(os.path.join(rec, "tank-ab-coverage.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, ["variant", "point", "process", "temp_c", "outcome", "detail"])
    w.writeheader(); w.writerows(cov)

counts = {}
for c in cov:
    counts[c["outcome"]] = counts.get(c["outcome"], 0) + 1
print("coverage:", ", ".join("%s=%d" % kv for kv in sorted(counts.items())) or "(none)",
      file=sys.stderr)
if strict and state["gap"]:
    print("--strict: coverage/validity gaps found (see tank-ab-coverage.csv)", file=sys.stderr)
    sys.exit(2)
