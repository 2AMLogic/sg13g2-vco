#!/usr/bin/env python3
"""analyze.py <record-dir> -- fold the per-request klt sim reports of a
run_tank_ab.sh record into <record-dir>/tank-ab.csv and tank-ab-delta.csv.

Q here is the PHASE-BANDWIDTH Q of the differential impedance: f0/(f_m45-f_p45),
the frequencies where the phase of Z is -45/+45 degrees (the half-power points
of an ideal parallel RLC, but not exactly for this non-ideal tank).  f0 is the
zero-phase crossing.  Each value is one deterministic AC solve, so it has no
sampling variance; its numerical resolution is the sweep step (2 MHz) -- about
+-0.05 % on f0 and +-0.5 % on Q here.
"""
import csv, glob, json, os, sys
rec = sys.argv[1]
rows = []
for p in sorted(glob.glob(os.path.join(rec, "reports", "*.json"))):
    name = os.path.basename(p)[:-5]
    variant, point = name.split("__")
    try:
        d = json.load(open(p))
    except Exception:
        rows.append(dict(variant=variant, point=point, mim="", temp_c="", status="NO-REPORT"))
        continue
    cell = json.load(open(os.path.join(rec, "decks", name + ".cell.json")))
    for c in d.get("corners", []):
        m = {x["name"]: x["value"] for x in c["measurements"]}
        ok = c["status"] == "pass" and all(m.get(k) is not None for k in ("f0", "f_p45", "f_m45", "zpk"))
        q = m["f0"] / (m["f_m45"] - m["f_p45"]) if ok else None
        rows.append(dict(variant=variant, mos=cell["mos"], vctrl_v=cell["vctrl"],
                         mim=c["process"], temp_c=c["temperature_c"],
                         status="ok" if ok else "NO-VALUE (" + "; ".join(
                             x.get("message", "")[:60] for x in c.get("diagnostics", [])[:1]) + ")",
                         f0_ghz=None if not ok else round(m["f0"] / 1e9, 5),
                         zpk_ohm=m.get("zpk"), q_phase45=None if not ok else round(q, 3),
                         job=(d.get("environment", {}).get("remote") or {}).get("job_id")))
flds = ["variant", "mos", "vctrl_v", "mim", "temp_c", "status", "f0_ghz", "zpk_ohm", "q_phase45", "job"]
with open(os.path.join(rec, "tank-ab.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, flds, extrasaction="ignore"); w.writeheader(); w.writerows(rows)
key = lambda r: (r.get("mos"), r.get("vctrl_v"), r.get("mim"), r.get("temp_c"))
base = {key(r): r for r in rows if r["variant"] == "bn-tank" and r["status"] == "ok"}
out = []
for r in rows:
    if r["variant"] == "bn-tank" or r["status"] != "ok":
        continue
    b = base.get(key(r))
    if not b:
        continue
    out.append(dict(variant=r["variant"], mos=r["mos"], vctrl_v=r["vctrl_v"], mim=r["mim"],
                    temp_c=r["temp_c"], f0_old_ghz=b["f0_ghz"], f0_new_ghz=r["f0_ghz"],
                    df0_pct=round(100 * (r["f0_ghz"] / b["f0_ghz"] - 1), 2),
                    q_old=b["q_phase45"], q_new=r["q_phase45"],
                    dq_pct=round(100 * (r["q_phase45"] / b["q_phase45"] - 1), 2),
                    zpk_ratio=round(r["zpk_ohm"] / b["zpk_ohm"], 3),
                    q_scaling_db=round(20 * __import__("math").log10(r["q_phase45"] / b["q_phase45"]), 2)))
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
for (v, mim, t, vc), f in sorted(by.items()):
    if vc != 0.0 or (v, mim, t, 3.3) not in by:
        continue
    fmax, fmin = f, by[(v, mim, t, 3.3)]
    tun.append(dict(variant=v, mim=mim, temp_c=t, f0_vctrl0_ghz=fmax, f0_vctrl3p3_ghz=fmin,
                    fmax_over_fmin=round(fmax / fmin, 4)))
with open(os.path.join(rec, "tank-ab-tuning.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, list(tun[0])); w.writeheader(); w.writerows(tun)
