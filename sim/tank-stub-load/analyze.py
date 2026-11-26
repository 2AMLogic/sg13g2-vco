#!/usr/bin/env python3
"""analyze.py <record-dir> -- fold the per-request klt sim reports of a
run_stub_ab.sh record into <record-dir>/stub-ab.csv, stub-ab-delta.csv and
stub-ab-tuning.csv, with per-corner coverage validation.

Q here is the PHASE-BANDWIDTH Q of the differential impedance: f0/(f_m45-f_p45),
the frequencies where the phase of Z is -45/+45 degrees (the half-power
points of an ideal parallel RLC, but not exactly for this non-ideal tank).
f0 is the zero-phase crossing.  Each value is one deterministic AC solve, so
it has no sampling variance; its numerical resolution is the sweep step
(2 MHz) -- about +-0.05 % on f0 and +-0.5 % on Q here (same estimator and
resolution as ../bn-substrate-tank/analyze.py, whose README states them).

Validation and coverage follow ../bn-substrate-tank/analyze.py (issues #166
and #462: the request/report inventory and the missing-report coverage are
shared through ../tools/record_inventory.py): a corner is reduced to numbers
only if f0, f_p45, f_m45 and zpk are finite real numbers, positive and
ordered f_p45 < f0 < f_m45 with a positive Q; otherwise the row is
NO-VALUE(<reason>).  Every expected (variant, point, process, temperature)
appears exactly once in stub-ab-coverage.csv: the inventory is the union of
returned reports and submitted requests, so a unit whose report never came
back gets one NO-REPORT row per requested corner -- a coverage gap, which
--strict turns into exit 2.  Nothing is invented.  Model failures (corner
status != pass, e.g. the known +125 C dsubw NaN) never affect the exit
status: that is evidence, not tool health.

stub-ab-delta.csv joins the two variants per (mos, vctrl, process, temp)
and reports the f0 and Q shift the #420 stubs load onto the tank.
stub-ab-tuning.csv reduces the tt Vctrl triplet (0.0 / 1.5 / 3.3 V) to the
per-(process, temp) fractional tuning ratio f(0.0)/f(3.3), per variant, and
the stub's delta on it -- the quantity spec row 2 grades.  A ratio is
emitted only when both endpoints are 'ok' in that variant; a missing
endpoint leaves blanks, never an interpolation.
"""
import csv, importlib.util, json, os, sys

# Shared request/report inventory (issue #462): loaded by path because this
# script runs under python3 -I (isolated mode), like make_requests.py's
# svaricap_overlay import.
_spec = importlib.util.spec_from_file_location(
    "record_inventory", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     "..", "tools", "record_inventory.py"))
inventory = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(inventory)

# The identical helpers and request parsing now live in the shared inventory
# module; the aliases keep the call sites below unchanged.
isnum = inventory.isnum
fmt_t = inventory.fmt_t
split_name = inventory.split_name
expected_corners = inventory.expected_corners

strict = "--strict" in sys.argv[1:]
args = [a for a in sys.argv[1:] if a != "--strict"]
rec = args[0]


def validate_corner(m):
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


def corner_key(c):
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


def no_report(name, why):
    variant, point, entries = inventory.no_report_coverage(rec, name, why)
    rows.append(dict(variant=variant, mos="", vctrl_v="", point=point, process="", temp_c="",
                     status="NO-REPORT", f0_hz="", q="", zpk_ohm="", job=""))
    for pr, t, outcome, detail in entries:
        covrow(variant, point, pr, t, outcome, detail)


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
    keys = [corner_key(c) for c in corners]
    seen = {}
    for k in keys:
        if k is not None:
            seen[k] = seen.get(k, 0) + 1
    for c, k in zip(corners, keys):
        proc = c.get("process", "") if isinstance(c, dict) else ""
        temp = c.get("temperature_c", "") if isinstance(c, dict) else ""
        if k is None:
            proc = proc if isinstance(proc, str) else ""
            temp = temp if isnum(temp) else ""
            why = "malformed corner"
            if isinstance(c, dict):
                if not isinstance(c.get("process"), str):
                    why = "malformed corner: process not a string"
                else:
                    why = "malformed corner: temperature not a finite number"
            rows.append(dict(variant=variant, mos=mos, vctrl_v=vctrl, point=point,
                             process=proc, temp_c=temp, status="NO-VALUE (%s)" % why,
                             f0_hz="", q="", zpk_ohm="", job=job))
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
        if seen[k] > 1:
            status, ok = "DUPLICATE-CORNER", False
            covrow(variant, point, proc, temp, "DUPLICATE-CORNER", "appears %d times" % seen[k])
        elif exp is not None and k not in exp:
            status, ok = "UNEXPECTED-CORNER", False
            covrow(variant, point, proc, temp, "UNEXPECTED-CORNER", "not in request")
        else:
            status = "ok" if ok else ("NO-VALUE (%s)" % reason if invalid_pass
                                      else "NO-VALUE (" + diag + ")")
            if invalid_pass:
                covrow(variant, point, proc, temp, "INVALID", reason)
            elif exp is None:
                covrow(variant, point, proc, temp, "COVERAGE-UNCHECKED", "no request file")
            else:
                covrow(variant, point, proc, temp, "ok" if ok else "NO-VALUE", reason or diag)
        if req_err and exp is None:
            covrow(variant, point, proc, temp, "REQUEST-UNREADABLE", req_err)
        rows.append(dict(variant=variant, mos=mos, vctrl_v=vctrl, point=point,
                         process=proc, temp_c=fmt_t(temp), status=status,
                         f0_hz=("%.6g" % m["f0"]) if ok else "",
                         q=("%.6g" % q) if ok else "",
                         zpk_ohm=("%.6g" % m["zpk"]) if ok else "", job=job or ""))
    if exp is not None:
        for k2 in sorted(exp - set(x for x in keys if x is not None)):
            covrow(variant, point, k2[0], fmt_t(k2[1]), "MISSING-CORNER", "expected, not in report")


# Shared inventory discovery (issue #462): the union of returned reports and
# submitted requests, so a requested unit whose report never came back still
# gets one NO-REPORT coverage row per requested corner.
names = inventory.discover(rec)
if not names:
    covrow("", "", "", "", "EMPTY-INVENTORY", "no reports and no request files")
for name in names:
    p = os.path.join(rec, "reports", name + ".json")
    if not os.path.exists(p):
        no_report(name, "no report file")
        continue
    try:
        with open(p) as fh:
            txt = fh.read()
        d = json.loads(txt) if txt.strip() else None
    except ValueError:
        no_report(name, "report is not JSON")
        continue
    if not isinstance(d, dict):
        no_report(name, "report is empty")
        continue
    if "corners" not in d:
        no_report(name, "report has no corners")
        continue
    reduce_report(name, d)

with open(os.path.join(rec, "stub-ab.csv"), "w", newline="") as fh:
    w = csv.DictWriter(fh, ["variant", "mos", "vctrl_v", "point", "process", "temp_c",
                            "status", "f0_hz", "q", "zpk_ohm", "job"])
    w.writeheader()
    w.writerows(rows)

# ---- delta: join nostub/stub per (mos, vctrl, process, temp) --------------
ok_rows = {(r["variant"], r["mos"], r["vctrl_v"], r["process"], str(r["temp_c"])): r
           for r in rows if r["status"] == "ok"}
delta = []
for (v, mos, vc, pr, t) in sorted(ok_rows):
    if v != "nostub":
        continue
    key = ("stub", mos, vc, pr, t)
    if key not in ok_rows:
        continue
    a, b = ok_rows[(v, mos, vc, pr, t)], ok_rows[key]
    f0a, f0b = float(a["f0_hz"]), float(b["f0_hz"])
    qa, qb = float(a["q"]), float(b["q"])
    delta.append(dict(mos=mos, vctrl_v=vc, process=pr, temp_c=t,
                      f0_nostub_hz=a["f0_hz"], f0_stub_hz=b["f0_hz"],
                      df0_hz="%.6g" % (f0b - f0a),
                      df0_pct="%.4f" % (100.0 * (f0b - f0a) / f0a),
                      q_nostub=("%.4f" % qa), q_stub=("%.4f" % qb),
                      dq_pct="%.4f" % (100.0 * (qb - qa) / qa)))
with open(os.path.join(rec, "stub-ab-delta.csv"), "w", newline="") as fh:
    w = csv.DictWriter(fh, ["mos", "vctrl_v", "process", "temp_c", "f0_nostub_hz",
                            "f0_stub_hz", "df0_hz", "df0_pct", "q_nostub", "q_stub", "dq_pct"])
    w.writeheader()
    w.writerows(delta)

# ---- tuning ratio at tt: f(0.0)/f(3.3) per (process, temp), per variant ---
tuning = []
pros = sorted({r["process"] for r in rows if r["mos"] == "tt"})
temps = sorted({str(r["temp_c"]) for r in rows if r["mos"] == "tt"})
for pr in pros:
    for t in temps:
        entry = dict(process=pr, temp_c=t)
        for variant in ("nostub", "stub"):
            lo = ok_rows.get((variant, "tt", 0.0, pr, t))
            hi = ok_rows.get((variant, "tt", 3.3, pr, t))
            if lo and hi:
                ratio = float(lo["f0_hz"]) / float(hi["f0_hz"])
                entry["f0_%s_v0" % variant] = lo["f0_hz"]
                entry["f0_%s_v3p3" % variant] = hi["f0_hz"]
                entry["ratio_%s" % variant] = "%.5f" % ratio
            else:
                entry["f0_%s_v0" % variant] = ""
                entry["f0_%s_v3p3" % variant] = ""
                entry["ratio_%s" % variant] = ""
        if entry.get("ratio_nostub") and entry.get("ratio_stub"):
            entry["dratio_pct"] = "%.4f" % (100.0 * (float(entry["ratio_stub"])
                                                     / float(entry["ratio_nostub"]) - 1.0))
        else:
            entry["dratio_pct"] = ""
        tuning.append(entry)
with open(os.path.join(rec, "stub-ab-tuning.csv"), "w", newline="") as fh:
    w = csv.DictWriter(fh, ["process", "temp_c", "f0_nostub_v0", "f0_nostub_v3p3",
                            "ratio_nostub", "f0_stub_v0", "f0_stub_v3p3", "ratio_stub",
                            "dratio_pct"])
    w.writeheader()
    w.writerows(tuning)

with open(os.path.join(rec, "stub-ab-coverage.csv"), "w", newline="") as fh:
    w = csv.DictWriter(fh, ["variant", "point", "process", "temp_c", "outcome", "detail"])
    w.writeheader()
    w.writerows(cov)

n_ok = sum(1 for r in rows if r["status"] == "ok")
print("stub-ab: %d corner rows (%d ok), %d deltas, %d coverage rows, gap=%s"
      % (len(rows), n_ok, len(delta), len(cov), state["gap"]))
if state["gap"]:
    print("coverage gaps present; see stub-ab-coverage.csv", file=sys.stderr)
if strict and state["gap"]:
    sys.exit(2)
