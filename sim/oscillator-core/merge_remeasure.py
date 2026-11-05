#!/usr/bin/env python3
"""Merge a fleet re-measure report into a per-unit CSV (issue #94). Read-only on inputs.
Usage: merge_remeasure.py OLD_UNITS.csv REPORT.json OUT_UNITS.csv
Units present in REPORT replace the same (process,vct,temp) rows of OLD; all other
rows (incl. every 125 C error) are carried unchanged. Prints replaced/repeat stats."""
import csv, json, sys
old = list(csv.DictReader(open(sys.argv[1])))
rep = json.load(open(sys.argv[2]))
new = {}
for c in rep["corners"]:
    m = {x["name"]: x.get("value") for x in c["measurements"]}
    t = m.get("t_10_periods")
    ok = c["status"] == "pass" and t
    new[(c["process"], "%.1f" % c["supply_v"]["vct"], str(c["temperature_c"]))] = {
        "status": "pass" if ok else "error",
        "t": "%g" % t if ok else "", "f": repr(10 / t / 1e9) if ok else "",
        "pp": repr(m["vdiff_max"] - m["vdiff_min"]) if ok and m.get("vdiff_max") is not None else "",
        "diag": ";".join(d.get("code", "") for d in c["diagnostics"])}
out = csv.writer(open(sys.argv[3], "w"), lineterminator="\n")
out.writerow(["process", "vct_V", "temp_C", "status", "t_10_periods_s", "f_osc_GHz_from_10_periods", "vdiff_pp_V", "diagnostic_codes"])
rep_n = same = diff = fixed = 0
maxrel = 0.0
for r in old:
    k = (r["process"], "%.1f" % float(r["vct_V"]), r["temp_C"])
    n = new.get(k)
    if n is None:
        out.writerow([r[h] for h in ["process", "vct_V", "temp_C", "status", "t_10_periods_s", "f_osc_GHz_from_10_periods", "vdiff_pp_V", "diagnostic_codes"]]); continue
    rep_n += 1
    if r["status"] == "pass" and n["status"] == "pass":
        maxrel = max(maxrel, abs(float(n["f"]) / float(r["f_osc_GHz_from_10_periods"]) - 1))
    if r["status"] != "pass" and n["status"] == "pass": fixed += 1
    out.writerow([r["process"], r["vct_V"], r["temp_C"], n["status"], n["t"], n["f"], n["pp"], n["diag"]])
print("replaced=%d fixed_by_remeasure=%d still_error=%d max_rel_f_change_on_prev_pass=%.3g" % (
    rep_n, fixed, sum(1 for v in new.values() if v["status"] != "pass"), maxrel))
