# Post-#79 PVT grid — GRADING of the existing fleet CSV (issue #94, partial deliverable)

Append-only; supersedes nothing. No simulation was run for this record (nothing local, nothing submitted to the fleet):
it is a deterministic read of `20261105-152054-a6be03f-pvt-grid-units.csv` (1350 rows, record
`20261105-152054-a6be03f-pvt-grid-post79.md`). Output: `20261105-170000-ecc6aeb-pvt-grid-graded.csv` (135 rows =
45 process corners x 3 temperatures). Grader: `grade_fleet_grid.py` (same bounds as `osc_bench.sh`, read-only copies of
spec rows 1/2/3/7); known-answer check `tests/test_grade_fleet_grid.sh` (11 assertions, synthetic CSV).

## Method and limits
- Rule inherited from `osc_emit_tuning`: a curve is graded **only when complete** (every expected Vctrl has a PASS
  unit). Row 2 needs all 10 voltages, row 3/7 need the five-point window W = {1.65, 1.8, 2.4, 3.0, 3.3} V. Nothing is
  graded from a partial curve and no unit was re-run or interpolated.
- Frequencies are the fleet's 10-period estimator (2.5-5 ns window); its variance was not estimated (one `.ic`, no
  seeds), as the source record says.

## Result: every one of the 135 PVT points is INCOMPLETE — no row 1/2/3/7 verdict can be issued from this CSV
| Temp | corners | PASS units / corner | why the curve is incomplete |
|---|---|---|---|
| -40 C | 45 | 8 of 10 | Vctrl 3.0 and 3.3 V error (`t_10_periods` out of interval) on all 45 |
| 27 C | 45 | 8 (26 corners) / 7 (19 corners) | same, plus 2.4 V on 19 corners |
| 125 C | 45 | 0 of 10 | `timestep_too_small` at the first timepoint (HBT), all units — recorded error, not dropped |

W needs 3.0 V and 3.3 V, so the **row 3 and row 7 window grades are INCOMPLETE at every point**, and row 2 (full
domain) likewise. Row 7's HBT BVCEO compliance half is **not graded at all**: it needs the cycle minimum of V(TAIL),
which the fleet report does not carry.

## Observations that need no curve (descriptive, not verdicts)
- All 701 passing units have f_osc 4.102-4.310 GHz — **none is inside row 1's 4.5-5.5 GHz window** (the quantization
  floor, ~0.1 %, is far below the ~4 % shortfall). Row 1 is binding and was already "not met"; this is the first post-#79
  full-oscillator frequency evidence and it does not support it. The row-1 *verdict* stays INCOMPLETE under the bench rule.
- On the surviving points the largest f_max/f_min at any corner is 1.029 (<< row 2's 1.15), but those points exclude
  the high-Vctrl end where the tuning range would come from, so this is a lower bound of the observable range only.
- The surviving points' vdiff_pp is 0.576-0.680 V (>= row 7's 0.40 V); this grades nothing (W incomplete).

## What would let these rows be graded (not done here)
The 199 non-hot errors (Vctrl >= 2.4 V) are attributed in the source record to the 21-crossing/5 ns estimator, unverified.
Grading needs those units re-measured with a longer window or retained waveforms — a new fleet request, not a
re-grade of this CSV. 125 C stays blocked on the HBT first-timepoint abort (#280/#281). No spec row was relaxed.

## Not done in this increment (issue #94 stays open)
`design/run_elaborate.sh` on the post-#79 netlist, the `sim/phase-noise` ISF pilot, and removal of the pre-#79
banners (README.md, sim/README.md, design/README.md): none of the replacing records exists, so every banner stays.
