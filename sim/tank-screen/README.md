# tank-screen -- analytic screen for the #93 re-tune (issue #129)

**Screening arithmetic, not evidence.** Grades no row, writes no record, and is
not a substitute for the graded bench (#94 regenerates evidence).

```
python3 -I sim/tank-screen/tank_screen.py --out build/tank-screen   # ranked table
python3 -I sim/tank-screen/tank_screen.py --selfcheck                # known-answer JSON
```

`--out` refuses any path under `sim/` or a `records/` directory.

Inputs are committed records only: EM-fitted `p11`/`p13`/`p1` L(f)
(`sim/inductor-model/em-extraction/records/20260910-052657-3896421-em-vs-analytic.csv`),
the bn=substrate A/B f0 endpoints
(`sim/bn-substrate-tank/records/20261009-002323-383f22e/tank-ab-tuning.csv`),
the `mos_small` varactor C from `design/README.md`, and the `cmim_core`
CJ/CJSW quoted there. Method and limits are in the script docstring and are
repeated in every output file: lumped LC, no HBT pair loading, no parasitics
beyond what the records carry, per-cell C calibrated at one corner
(tt / cap_typ / 27 C) at the two Vctrl endpoints only, no loss/Q model.

Known answer (`tests/stdlib/test_tank_screen.py`): the forward lumped model
reproduces the A/B `bn-tank` f0 to ~0.33 % and the bn-tank -> bn-sub f0 deltas
to ~0.25 percentage points and the ratio delta (1.18 -> 1.11) to 0.0003.
The bn=substrate endpoints are reproduced by construction (the cell C is
inverted from them), so only the bn-tank forward check and the delta check are
independent.

Spec bounds (rows 1, 2) are used as written and are never relaxed here.
