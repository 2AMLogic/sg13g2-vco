#!/usr/bin/env python3
"""Grade rows 1/2/3/7 (partial) from a fleet per-unit CSV (issue #94).

Reads a records/*-pvt-grid-units.csv (columns: process,vct_V,temp_C,status,
t_10_periods_s,f_osc_GHz_from_10_periods,vdiff_pp_V,diagnostic_codes) and
applies the SAME bounds as osc_bench.sh (spec/target-spec.md rows 1,2,3,7),
read-only. A curve is graded only when COMPLETE; anything else is INCOMPLETE,
never graded on a partial curve. Row 7's BVCEO compliance needs the cycle
minimum of V(TAIL), which the fleet report does not carry: NOT graded here.
Usage: grade_fleet_grid.py UNITS.csv OUT.csv
"""
import csv, sys, collections
F1 = (4.5, 5.5); R2 = 1.15; R2S = 1.20  # copies of spec rows 1,2
W = ["1.65", "1.8", "2.4", "3.0", "3.3"]
FULL = ["0.0", "0.3", "0.6", "0.9", "1.2", "1.65", "1.8", "2.4", "3.0", "3.3"]
COV, KMEAN, INL, VPP = 0.90, 381.0, 30.0, 0.40  # KMEAN in MHz/V
pts = collections.defaultdict(dict)
for r in csv.DictReader(open(sys.argv[1])):
    pts[(r["process"], r["temp_C"])][r["vct_V"]] = r
out = csv.writer(open(sys.argv[2], "w"), lineterminator="\n")
out.writerow(["process", "temp_C", "n_pass", "full_complete", "f_min_GHz", "f_max_GHz",
              "row1", "row2_ratio", "row2", "row2_stretch", "W_complete", "row3_single_signed",
              "row3_coverage", "row3_kvco_mean_MHz_per_V", "row3_chord_inl_pct", "row3",
              "row7_vpp_min_in_W_V", "row7_swing", "row7_bvceo_compliance"])
tally = collections.Counter()
for (proc, temp), d in sorted(pts.items()):
    ok = {v: x for v, x in d.items() if x["status"] == "pass"}
    f = {v: float(x["f_osc_GHz_from_10_periods"]) for v, x in ok.items()}
    full = all(v in ok for v in FULL); wc = all(v in ok for v in W)
    row = [proc, temp, len(ok), full]
    row += ["%.4f" % min(f.values()), "%.4f" % max(f.values())] if f else ["nan", "nan"]
    if not full:
        row += ["INCOMPLETE", "nan", "INCOMPLETE", "INCOMPLETE"]
    else:
        inside = F1[0] <= min(f.values()) and max(f.values()) <= F1[1]
        ratio = max(f.values()) / min(f.values())
        row += ["BOTH ENDPOINTS INSIDE" if inside else "AN ENDPOINT OUTSIDE", "%.5f" % ratio,
                "MET" if ratio >= R2 else "NOT MET", "MET" if ratio >= R2S else "NOT MET"]
    if not wc:
        row += [wc, "nan", "nan", "nan", "nan", "INCOMPLETE", "nan", "INCOMPLETE", "NOT GRADED"]
    else:
        fw = [f[v] for v in W]; vw = [float(v) for v in W]
        sl = [(fw[i+1]-fw[i])/(vw[i+1]-vw[i]) for i in range(4)]
        single = all(s < 0 for s in sl) or all(s > 0 for s in sl)
        span_w = f["1.65"] - f["3.3"]
        cov = span_w / (f["0.0"] - f["3.3"]) if full and f["0.0"] != f["3.3"] else float("nan")
        kmean = abs(span_w) / 1.65 * 1000.0
        chord = [fw[0] + (fw[4]-fw[0])*(v-vw[0])/(vw[4]-vw[0]) for v in vw]
        inl = 100*max(abs(a-b) for a, b in zip(fw, chord))/abs(fw[4]-fw[0]) if fw[4] != fw[0] else float("nan")
        good = single and cov == cov and cov >= COV and kmean >= KMEAN and inl == inl and inl <= INL
        vm = min(float(ok[v]["vdiff_pp_V"]) for v in W)
        row += [wc, single, "%.4f" % cov if cov == cov else "nan", "%.1f" % kmean,
                "%.2f" % inl if inl == inl else "nan", "MET" if good else "NOT MET",
                "%.4f" % vm, "MET" if vm >= VPP else "NOT MET", "NOT GRADED"]
    out.writerow(row)
    tally[(temp, row[6], row[8], row[15])] += 1
for k, n in sorted(tally.items()):
    print("temp=%s row1=%s row2=%s row3=%s : %d corners" % (*k, n))
