#!/usr/bin/env python3
"""tank_screen.py -- PDK-free analytic tank SCREEN for the #93 re-tune (issue #129).

    tank_screen.py --out DIR            write ranked table (csv + md) into DIR
    tank_screen.py --selfcheck          print the known-answer reproduction (JSON)

SCREENING ARITHMETIC, NOT EVIDENCE.  Nothing here is a simulation or a graded
result; it only prunes candidates before spending a graded-grid run.  It writes
only to a directory you name, and refuses any path inside sim/ or any
records/ directory (sim/ results are append-only evidence, CLAUDE.md).

METHOD.  Lumped parallel LC resonance of the differential tank:
    L_diff(f) * w * ... :  w^2 * 2*L(f) * C_diff = 1,   w = 2 pi f
  * L(f): the EM-fitted `l_fitted_h` column (inductor geometry rows p1/p13/p11)
    of sim/inductor-model/em-extraction/records/20260910-052657-3896421-
    em-vs-analytic.csv, linearly interpolated (so L rises with f, as in the
    record); two inductors in series -> 2 L(f).
  * C_diff = C_mim + (N/2) * C_cell(Vctrl): N varactor cells per side, all to
    the (AC-grounded) control node, the two sides in series.
  * C_mim = 1.5 fF/um^2 * W*L + 40 aF/um * 2(W+L)  (PDK cmim_core CJ/CJSW as
    quoted in design/README.md; 3.65 x 3.65 um -> 20.57 fF).
  * C_cell(Vctrl) with bn = substrate (post-#79): an EFFECTIVE per-cell value,
    inverted from the committed A/B record
    sim/bn-substrate-tank/records/20260909-... tank-ab-tuning.csv (bn-sub,
    cap_typ, 27 C, f0 at Vctrl 0 and 3.3 V) with the same lumped model and the
    record's 16 cells per side and 20.57 fF MIM.  It therefore contains the
    cell's core C, the dsubw junction C and everything else the record carries.
    The two Vctrl endpoints are all the record gives: no interior points.
  * Centre f_c = geometric mean of the f0 at the two Vctrl endpoints; tuning
    ratio = f0(Vctrl=0)/f0(3.3).  Rows 1 (4.5-5.5 GHz) and 2 (>= 1.15).

LIMITS (stated next to every number).  Lumped LC only; NO HBT pair loading
(no Cbe/Cbc/Ccs of the cross-coupled pair), NO wiring/layout parasitics beyond
what the records carry; the per-cell effective C is calibrated at one corner
(tt/cap_typ/27 C) and assumed to scale linearly with cell count; it assumes f0
is monotonic in Vctrl between the endpoints and that the centre of the band is
the endpoint geometric mean (not a transient-measured centre); loss/Q is not
modelled, so rows 3-11 are not screened.  Known-answer error against the A/B
record is reported by --selfcheck (about 0.3 % in f0).  The graded bench decides.
"""
import argparse, csv, glob, math, os, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EM_CSV = os.path.join(REPO, "sim/inductor-model/em-extraction/records/"
                      "20260910-052657-3896421-em-vs-analytic.csv")
AB_CSV = os.path.join(REPO, "sim/bn-substrate-tank/records/"
                      "20261009-002323-383f22e/tank-ab-tuning.csv")
# mos_small cell, tt, 27 C, 5 GHz, c_5ghz_f at record V_rec 3.3 / 0.0, i.e.
# Vctrl 0.0 / 3.3 (V_rec = 3.3 - Vctrl); values quoted in design/README.md and
# committed in sim/varactor-characterization/records/20260909-231619-de50891.csv
CELL_BN_TANK_F = {0.0: 5.56899e-15, 3.3: 10.4522e-15}
CJ, CJSW = 1.5e-15 / 1e-12, 40e-18 / 1e-6      # F/m^2, F/m (cmim_core)
MIM_REF_SIDE_M = 3.65e-6
N_REF = 16                                       # cells per side in the A/B record
BAND = (4.5e9, 5.5e9)                            # row 1
RATIO_MIN = 1.15                                 # row 2
SRF_FRAC = 0.85                                  # usable ceiling, x SRF proxy (L zero crossing)

ROW_LABEL = "SCREENING ARITHMETIC, NOT EVIDENCE"
METHOD = ("lumped LC resonance (2 L(f) EM-fitted, C = MIM + N/2 effective cells); "
          "no HBT pair loading, no parasitics beyond what the records carry; "
          "cell C calibrated on the bn=substrate A/B record (tt, cap_typ, 27 C), "
          "endpoints only; no loss/Q model")


def load_inductors(path=EM_CSV):
    ind = {}
    with open(path) as fh:
        for r in csv.DictReader(fh):
            ind.setdefault(r["geometry"], []).append(
                (float(r["f_hz"]), float(r["l_fitted_h"])))
    for g in ind:
        ind[g].sort()
    return ind


def l_of_f(curve, f):
    for (f0, l0), (f1, l1) in zip(curve, curve[1:]):
        if f0 <= f <= f1:
            return l0 + (f - f0) / (f1 - f0) * (l1 - l0)
    raise ValueError("f outside the record's frequency range")


def ceiling(curve):
    """SRF proxy: interpolated zero crossing of L(f) (or the last sample if L
    never changes sign); usable ceiling = SRF_FRAC of it.  p11 -> ~8.1 GHz,
    against the record's own 8.008 GHz fit-band ceiling."""
    for (f0, l0), (f1, l1) in zip(curve, curve[1:]):
        if l0 > 0 >= l1:
            return SRF_FRAC * (f0 + l0 / (l0 - l1) * (f1 - f0))
    return SRF_FRAC * curve[-1][0]


def mim_c(side_m):
    return CJ * side_m * side_m + CJSW * 4 * side_m


def f0_of(curve, c_diff, lo=3e8):
    """Lowest f with w^2 * 2L(f) * C = 1 below the usable ceiling, else None."""
    hi = ceiling(curve)
    g = lambda f: (2 * math.pi * f) ** 2 * 2 * l_of_f(curve, f) * c_diff - 1
    if g(lo) > 0 or g(hi) < 0:
        return None
    for _ in range(100):
        m = 0.5 * (lo + hi)
        if g(m) > 0:
            hi = m
        else:
            lo = m
    return 0.5 * (lo + hi)


def c_diff_for(curve, f):
    return 1.0 / ((2 * math.pi * f) ** 2 * 2 * l_of_f(curve, f))


def read_ab(path=AB_CSV):
    out = {}
    with open(path) as fh:
        for r in csv.DictReader(fh):
            if r["mim"] == "cap_typ" and r["temp_c"] == "27":
                out[r["variant"]] = (float(r["f0_vctrl0_ghz"]) * 1e9,
                                     float(r["f0_vctrl3p3_ghz"]) * 1e9)
    return out


def calibrate(ind=None, ab=None):
    """Effective bn=substrate per-cell C at Vctrl 0 and 3.3 V, from the A/B record."""
    ind = ind or load_inductors()
    ab = ab or read_ab()
    cur, cm = ind["p11"], mim_c(MIM_REF_SIDE_M)
    return {vc: (c_diff_for(cur, f) - cm) / (N_REF / 2.0)
            for vc, f in zip((0.0, 3.3), ab["bn-sub"])}


def evaluate(curve, n_side, mim_side_m, cell, mim_scale=1.0):
    cm = mim_c(mim_side_m) * mim_scale
    fa = f0_of(curve, cm + n_side / 2.0 * cell[0.0])
    fb = f0_of(curve, cm + n_side / 2.0 * cell[3.3])
    if fa is None or fb is None:
        return None
    return fa, fb, math.sqrt(fa * fb), fa / fb


def selfcheck():
    ind, ab = load_inductors(), read_ab()
    cur, cm = ind["p11"], mim_c(MIM_REF_SIDE_M)
    # (1) independent forward model: bn-tank cell C from the varactor record
    fwd = [f0_of(cur, cm + N_REF / 2.0 * CELL_BN_TANK_F[v]) for v in (0.0, 3.3)]
    # (2) calibrated bn-sub reproduces its own endpoints (inversion check)
    cell = calibrate(ind, ab)
    sub = evaluate(cur, N_REF, MIM_REF_SIDE_M, cell)
    rec_t, rec_s = ab["bn-tank"], ab["bn-sub"]
    rt, rs = rec_t[0] / rec_t[1], rec_s[0] / rec_s[1]
    return {
        "label": ROW_LABEL, "method": METHOD,
        "bn_tank_forward_f0_ghz": [x / 1e9 for x in fwd],
        "bn_tank_record_f0_ghz": [x / 1e9 for x in rec_t],
        "bn_tank_f0_err_pct": [100 * (a / b - 1) for a, b in zip(fwd, rec_t)],
        "bn_sub_cell_c_eff_ff": {str(k): v * 1e15 for k, v in cell.items()},
        "bn_sub_model_f0_ghz": [sub[0] / 1e9, sub[1] / 1e9],
        "bn_sub_record_f0_ghz": [x / 1e9 for x in rec_s],
        "ratio_model_tank": fwd[0] / fwd[1], "ratio_record_tank": rt,
        "ratio_model_sub": sub[3], "ratio_record_sub": rs,
        # the A/B record's own deltas vs the screen's predicted deltas
        "df0_pct_record": [100 * (s / t - 1) for s, t in zip(rec_s, rec_t)],
        "df0_pct_model": [100 * (s / t - 1) for s, t in zip(sub[:2], fwd)],
        "dratio_record": rs - rt, "dratio_model": sub[3] - fwd[0] / fwd[1],
    }


def refuse_graded(path):
    p = os.path.realpath(path)
    simdir = os.path.realpath(os.path.join(REPO, "sim"))
    parts = p.split(os.sep)
    if p == simdir or p.startswith(simdir + os.sep) or "records" in parts:
        sys.exit("refusing to write under sim/ or a records/ directory: " + path)


def build_table():
    ind = load_inductors()
    cell = calibrate(ind)
    rows = []
    sides_um = (1.14, 2.0, 3.0, 3.65, 4.5, 6.0, 8.0)
    for g in ("p11", "p13", "p1"):
        for n in range(8, 49, 2):
            for su in sides_um:
                r = evaluate(ind[g], n, su * 1e-6, cell)
                if r is None:
                    continue
                fa, fb, fc, ratio = r
                lo = evaluate(ind[g], n, su * 1e-6, cell, 0.9)
                hi = evaluate(ind[g], n, su * 1e-6, cell, 1.1)
                m1 = min(fc - BAND[0], BAND[1] - fc) / fc
                m2 = ratio / RATIO_MIN - 1
                rows.append({
                    "inductor": g, "cells_per_side": n, "mim_side_um": su,
                    "mim_ff": mim_c(su * 1e-6) * 1e15,
                    "f0_vctrl0_ghz": fa / 1e9, "f0_vctrl3p3_ghz": fb / 1e9,
                    "fc_ghz": fc / 1e9, "tuning_ratio": ratio,
                    "row1_margin": m1, "row2_margin": m2,
                    "row1_pass": m1 >= 0, "row2_pass": m2 >= 0,
                    "row1_pass_mim_pm10": bool(lo and hi and all(
                        BAND[0] <= x[2] <= BAND[1] for x in (lo, hi))),
                    "score": min(m1, m2)})
    rows.sort(key=lambda r: -r["score"])
    for i, r in enumerate(rows, 1):
        r["rank"] = i
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--out")
    ap.add_argument("--selfcheck", action="store_true")
    a = ap.parse_args()
    if a.selfcheck:
        import json
        print(json.dumps(selfcheck(), indent=2, sort_keys=True))
        return
    if not a.out:
        ap.error("--out DIR or --selfcheck required")
    refuse_graded(a.out)
    os.makedirs(a.out, exist_ok=True)
    rows = build_table()
    cols = ["rank", "inductor", "cells_per_side", "mim_side_um", "mim_ff",
            "f0_vctrl0_ghz", "f0_vctrl3p3_ghz", "fc_ghz", "tuning_ratio",
            "row1_pass", "row2_pass", "row1_pass_mim_pm10",
            "row1_margin", "row2_margin", "score"]
    with open(os.path.join(a.out, "tank-screen.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for r in rows:
            w.writerow([("%.5g" % r[c]) if isinstance(r[c], float) else r[c]
                        for c in cols])
    both = [r for r in rows if r["row1_pass"] and r["row2_pass"]]
    sc = selfcheck()
    with open(os.path.join(a.out, "tank-screen.md"), "w") as fh:
        fh.write("# Tank screen -- %s\n\n" % ROW_LABEL)
        fh.write("Method: %s.\n\nLimits: lumped LC only, no HBT loading, "
                 "known-answer f0 error vs the A/B record %s %% (bn-tank "
                 "forward model, Vctrl 0 / 3.3).\n\n"
                 % (METHOD, ", ".join("%+.2f" % x for x in sc["bn_tank_f0_err_pct"])))
        fh.write("%d candidates; %d pass rows 1 and 2 under this arithmetic.\n\n"
                 % (len(rows), len(both)))
        fh.write("Best tuning ratio in the grid: %.4f (row 2 needs %.2f); "
                 "if no candidate passes both rows, that is the input the "
                 "#93 spec-question decision record anticipates -- still "
                 "screening arithmetic, not a finding.\n\n"
                 % (max(r["tuning_ratio"] for r in rows), RATIO_MIN))
        fh.write("| " + " | ".join(cols) + " |\n|" + "---|" * len(cols) + "\n")
        for r in rows[:25]:
            fh.write("| " + " | ".join(("%.4g" % r[c]) if isinstance(r[c], float)
                                       else str(r[c]) for c in cols) + " |\n")
    print("ok %s: %d candidates, %d pass rows 1+2 (%s)"
          % (a.out, len(rows), len(both), ROW_LABEL))


if __name__ == "__main__":
    main()
