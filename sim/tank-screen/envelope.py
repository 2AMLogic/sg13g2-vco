#!/usr/bin/env python3
"""envelope.py -- extended-envelope companion to tank_screen.py (issue #93).

SCREENING ARITHMETIC, NOT EVIDENCE.  Prints CSV to stdout (redirect it; this
script writes no files).  For each characterized inductor (p11, p13, p1) and
the minimum legal cap_cmim (1.14 um), it lists the cells-per-side N, well
beyond tank_screen.py's 8..48 grid, together with the lumped-LC band-centre
frequency and the f(Vctrl=0)/f(Vctrl=3.3) ratio, and flags whether row 1
(centre in 4.5..5.5 GHz) and row 2 (ratio >= 1.15) hold.  Also prints, as
comment lines, the cell-only ratio ceiling and the fixed-C budget row 2 needs.
Same model, calibration and limits as tank_screen.py (no HBT loading, no
parasitics, no loss/Q, cell scaling assumed).  Bounds are used as written.
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tank_screen as t

ind = t.load_inductors()
cell = t.calibrate(ind)
c0, c1 = cell[0.0], cell[3.3]
# lossless-limit: C_tot(Vctrl=3.3)/C_tot(0) = (F+x*c1/c0)/(F+x); ratio f = sqrt of that
k = c1 / c0
need = t.RATIO_MIN ** 2
print("# cell C_eff(Vctrl=0) = %.3f fF, (3.3) = %.3f fF, cell-only C ratio %.4f"
      % (c0 * 1e15, c1 * 1e15, k))
print("# constant-L, cell-only (zero fixed C) f ratio ceiling = sqrt(%.4f) = %.4f" % (k, math.sqrt(k)))
print("# constant-L necessary condition for row 2: F <= x*(k-%.4f)/(%.4f-1) = %.4f * x (x = N/2*c0); the EM L(f) dispersion lowers the realized ratio below this, see table"
      % (need, need, (k - need) / (need - 1)))
print("inductor,cells_per_side,mim_ff,fc_ghz,f0_vctrl0_ghz,f0_vctrl3p3_ghz,ratio,row1,row2")
cm = t.mim_c(1.14e-6)
for g in ("p11", "p13", "p1"):
    for n in (8, 16, 24, 32, 48, 64, 96, 128, 192, 256, 400, 600):
        r = t.evaluate(ind[g], n, 1.14e-6, cell)
        if r is None:
            print("%s,%d,%.4f,,,,,no-resonance-in-record-range," % (g, n, cm * 1e15))
            continue
        fa, fb, fc, ratio = r
        print("%s,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%s,%s" % (
            g, n, cm * 1e15, fc / 1e9, fa / 1e9, fb / 1e9, ratio,
            t.BAND[0] <= fc <= t.BAND[1], ratio >= t.RATIO_MIN))
