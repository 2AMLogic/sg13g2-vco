# DR-006: Row-1/row-2 shortfall for the bn=substrate varactor -- bounded option (b) first, row-2 supersession (a) as the stated fallback

- **Status**: **proposed** -- awaits operator ratification. Nothing in this
  record is binding on design work and **no row of `spec/target-spec.md` is
  edited by it**. Every spec-text change below is proposed text only.
- **Date**: 2026-10-10
- **Decided by**: Builder agent, issue #184 (recommendation only; only the
  operator can ratify a change to row 2)
- **Supersedes**: none. It resolves the handoff `design/README.md:526`
  ("Decision needed (separate decision record; not made here)") left by the
  #93 re-tune, and builds on DR-005 (which created the shortfall) and
  DR-003 §Decision 2 (whose achievability arithmetic it re-derives).

## Context

DR-005 tied each varactor's `bn` to the p-substrate, as the layout must have
it. That put the PDK's `dsubw`/`rsubw` well-to-substrate junction on the tank
(`sim/bn-substrate-tank/README.md`). The #93 re-tune then searched for a
sizing that recovers rows 1 and 2 and found none
(`design/README.md`, "Re-tune against the corrected netlist (#93)";
`sim/bn-substrate-tank/records/20261009-2100-2eb3659-candidate-screen/`):

- 0 of 374 screened candidates pass rows 1 and 2; best row-1-passing ratio
  1.122; the benched candidates measure 1.122 / 1.117 against the baseline's
  1.113 (`sim/bn-substrate-tank/README.md` "Candidate re-tune (#93)").
- The one screen-arithmetic pass (`p1`, 600 cells/side) is rejected as an
  assessed limitation, not a measurement.
- The current netlist's band centre is 4.05 GHz (endpoint mean; row 1 floor
  4.5 GHz). The corrected-topology screening smoke oscillates at 4.19 GHz
  (`sim/oscillator-core/records/20261010-060510-edf5eb5-surrogate-corrected.md`;
  screening only, grades no row).

`spec/README.md` requires a superseding decision record for a spec revision,
and `CLAUDE.md` forbids agents relaxing the ratified spec to make results
pass. A search of open and closed issues found no tracker for this decision
(#184 is it), so the downstream blocked work (#50, #53, #59, #62, #94) is
being prepared against a netlist whose ratified targets it cannot meet.

### Required Cmax/Cmin for row 2, with arithmetic

Notation: `r` = varactor-cell `Cmax/Cmin` (Vctrl 0 vs 3.3 V); `V` = varactor
capacitance at Vctrl = 0 (the `Cmax` end, junction included); `F` = all
fixed tank capacitance (MIM + parasitics); `x` = 1/`r`. Constant L, so
`f ~ 1/sqrt(C)`. Row 2 needs f_max/f_min >= 1.15, i.e. a capacitance ratio

    R = 1.15^2 = 1.3225

and the ratio of tank capacitance is (F + V)/(F + x V) >= R. Solving:

    F <= V (1 - R x)/(R - 1) = V (1 - 1.3225/r)/0.3225        (1)
    r >= 1 / ((1 + f)/R - f),  f = F/V                         (2)

Checks of (1) against the two records that already state numbers:

- DR-003 §Decision 2 convention (`V` at Vctrl = 0, DR-001 `r` = 1.88):
  (1 - 1.3225/1.88)/0.3225 = **0.920**, reproducing "F <= 0.92·V". Good.
- Floor with F = 0: `r >= 1.3225`. The measured bn=substrate cell is **1.350**
  (14.07 -> 18.99 fF effective, `design/README.md:480`), whose F = 0 ceiling
  is sqrt(1.350) = **1.162**, as the README states. Row 2 passes only in a
  2 % sliver above the floor.
- Same arithmetic at r = 1.350: F <= (1 - 0.97963)/0.3225 = **0.0632·V**, with
  `V` the Vctrl = 0 (`Cmax`) capacitance. `design/README.md:526` writes this
  as "F <= 0.085 V" and `:503` as 0.0848 x (300 x 14.07 fF). Those are the same
  budget referenced to the **Cmin end** (14.07 fF): 0.0632 x 1.350 = 0.0853.
  The two statements agree numerically (0.0848 vs 0.0853 is the 1.3497 vs 1.350
  rounding) but use a different reference capacitance from DR-003's 0.92, so
  the "11x tighter" comparison is really 0.92 / 0.0632 = **14.6x** in a
  like-for-like (Cmax-referenced) convention. The qualitative conclusion is
  unchanged; this record uses the Cmax convention throughout.

Required ratio as a function of the fixed-C fraction (from (2)):

| F / V (at Vctrl = 0) | required r | note |
|---|---|---|
| 0 | 1.3225 | structural floor |
| 0.02 | 1.331 | |
| 0.05 | 1.344 | |
| 0.0632 | 1.350 | measured cell: zero margin |
| 0.10 | 1.367 | |
| 0.227 | 1.427 | |
| 0.25 | 1.438 | |
| 0.50 | 1.577 | |
| 0.92 | 1.880 | DR-003's premise |

For the stretch (1.20, R = 1.44): `r >= 1.44` even at F = 0; the measured cell
cannot reach the stretch at any F.

Absolute scale (derived, not measured): row 7 gives C_tot of about 88.5 fF at
5 GHz band centre, so V is of order 90 fF; at r = 1.350 the F budget is about
5.6 fF, against the baseline's `cap_cmim` alone at 20.57 fF
(`design/README.md:112`; the PDK's smallest `cap_cmim` is about 2 fF at
1.14 um) before any HBT-pair parasitic or routing. That is why the question
is not only "what ratio" but "what ratio at a fixed-C budget the layout can
plausibly meet": that budget is unmeasured and is the dominant unknown.

### What the junction does to the ratio (derived)

The effective cell is the intrinsic MOS core plus a roughly constant
junction capacitance J: 18.99 - 10.46 = 8.53 fF and 14.07 - 5.567 = 8.50 fF,
so J ~ 8.5 fF per `mos_small` cell (`sim/varactor-characterization/README.md`
finding 1 for 10.46 / 5.567 fF; `sim/bn-substrate-tank/README.md` for the
effective values). J is about 1.53 x the intrinsic `Cmin`. A constant
additive J maps `r_eff = (r_int + j)/(1 + j)` with j = J / `Cmin_int`:
1.88 -> 1.348 (reproduces the measured 1.350). **If** j were unchanged for
another geometry (an assumption, not a measurement; J scales with well area
and that area-to-intrinsic-C relation is unknown for other `w`, `l`, `Nx`),
`mos_mid`'s 2.08 would map to 1.427. That is the only reason option (b) is
worth a bounded characterization: the ratio is geometry-dependent in the
intrinsic device and the junction is not obviously proportional.

## Decision

Proposed, for operator ratification.

1. **Adopt option (b) as the first, bounded step.** A follow-up
   characterization/retune issue (to be filed on ratification; not a
   schematic change and not part of this record) measures, at bn = substrate
   and via a `klt sim` request (any grid goes to the fleet, per host rules):
   `Cmax`, `Cmin`, J, `r_eff` and Q at 5 GHz for the `sg13_hv_svaricap`
   geometries that the shipped model allows (`w` 3.74-9.74 um, `l`
   0.3-0.8 um, `Nx` 1-10; `sg13g2_svaricaphv_mod.lib`). Exit criterion,
   stated now so the outcome cannot be negotiated afterward: a cell
   **clears** iff, with the *measured* J, `r_eff >= 1.367` (F/V = 0.10, i.e.
   a fixed-C budget of ~9 fF at V ~ 90 fF) **and** the bank meets row 5
   (loaded Q >= 6 by DR-003's 1/Q rule, parallel small cells) **and** the
   resulting centre can be brought into row 1 by cell count/MIM. The 0.10
   threshold is a proposal; the operator may set it differently, but it must
   be fixed before the measurement.
2. **If a cell clears**, the follow-up retunes the tank around it as a design
   task; rows 1 and 2 stand unchanged; this DR stays proposed -> ratified
   without a spec edit.
3. **If none clears**, this record's fallback is option (a). Proposed
   supersession text for row 2 (not applied): "Row 2 (tuning range), for the
   substrate-`bn` `sg13_hv_svaricap` of DR-005: target f_max/f_min >= X,
   stretch >= Y, across 0.0-3.3 V, band-centre referenced; X and Y fixed by
   the operator from system need, not from measured results." This record
   does **not** pick X. For orientation only, the measured baseline tuning
   ratio is 1.113-1.122 and the F = 0 ceiling for the current cell is 1.162.
   A bound chosen to be just under what was measured would be a relaxation
   made to pass; the number needs a requirement behind it, and this block has
   no PLL-embedded consumer to supply one (target-spec row 3: "not
   PLL-embedded").
4. **Option (c) stays out of scope for v1** (DR-001 excluded band switching
   and a larger-ratio varactor; DR-001 §"Band-switching capacitor bank" names
   a trigger to revisit that this shortfall arguably meets, so (c) is
   deferred to an operator call, not rejected on the merits).
5. **Row 1 is treated separately from row 2.** The benched `n14` retune puts
   the endpoint-mean centre at 4.50 GHz (row 1's floor, no margin) and `n12`
   at 4.77 GHz at ratio 1.117, so row 1 is plausibly recoverable by a retune
   even if row 2 is not. Nothing here proposes a row-1 change.

## Alternatives considered

- **(a) Supersede row 2 now** (`design/README.md:526`). Not chosen first:
  the evidence does not yet exclude every geometry. Only `mos_small` has been
  characterized at bn = substrate (the 1.35x in `sim/bn-substrate-tank/`);
  the other three DR-001 geometries (`sim/varactor-characterization/README.md`
  finding 1: `mos_mid` 2.08, `mos_large`/`mos_xlarge` 1.88) have only the
  bn-tied ratio. Relaxing a ratified row on a one-device sample would be the
  "relax to pass" move `CLAUDE.md` forbids. It remains the stated fallback.
- **(b) Characterize an in-between inductor and a larger-ratio cell at
  bn = substrate.** Chosen as the bounded first step, narrowed to the
  varactor half. The inductor half is already searched: the `p11`/`p13`/`p1`
  envelope (`.../records/20261009-2100-2eb3659-candidate-screen/
  envelope-p11-p13-p1-mim1p14.csv`) shows ratio is limited by the cell's C
  swing, not by L; `p1` is rejected on row 5 (EM Q 6.46 vs 10.28 for `p11`,
  `sim/inductor-model/em-extraction/records/
  20260910-052657-3896421-em-vs-analytic.csv`). Further inductor work adds
  little until a cell with a larger `r_eff` exists.
- **(c) Change topology** (band switching / larger-ratio varactor;
  `spec/decision-records/DR-001-tuning-mechanism.md`). Out of scope for v1.
  Also: the issue text names `sg13_lv_svaricap`, but the PDK ships only
  `sg13_hv_svaricap` in `sg13g2_svaricaphv_mod.lib`. `sg13_lv_svaricap`
  appears only as an output-file prefix in the PDK's
  `sp_svaricap_test.sch`, whose instance is `sg13_hv_svaricap`. There is no
  low-voltage varactor model to substitute, so the "larger-ratio varactor"
  of (c) is not an available part. DR-005's other idea, an isolated-well
  structure to recover a floating `bn`, would trade the J capacitance for a
  deep-n-well-to-substrate junction, and it is a layout change DR-005
  already declined.
- **Edit `spec/target-spec.md` in this PR.** Rejected: ratification is the
  operator's, `spec/README.md` makes the grader-agreement gate part of the
  same change, and `.github/scripts/check-spec-change-has-dr.sh` would
  correctly require a ratified record.

## Consequences

Dependencies on the outcome:

- **#94** (regenerate `design/run_elaborate.sh`, `sim/oscillator-core`,
  `sim/phase-noise` for the post-#79 netlist; blocked on OSDI paths). Under
  (b)-success the schematic changes (cell count/geometry/MIM), so regenerating
  against today's netlist would spend its fleet and unblock effort on a
  netlist that is about to change: sequence #94 after the follow-up. Under
  (a) the netlist can stand, and #94 may proceed unchanged. The surrogate
  smoke (#179) is screening only and does not substitute.
- **#50** (graded row-10/11 PVT grid, ~180 CPU-hours, row 1/2/3/6/8 verdicts).
  It grades against whatever row 2 says at run time. Running it before this
  is resolved yields a row-1 and row-2 FAIL that is already known, at full
  cost. It should wait for the final netlist. Under (a) it grades against the
  superseding bound, and the grader constants must be updated in the same PR
  as the ratified supersession (`spec/README.md` "Updating after an
  authorized spec revision").
- **#53** (graded phase-noise grid, row 4). The carrier moves with any retune
  (4.05-4.19 GHz now vs 5.0 GHz centre); the row-4 estimate and the ISF
  impulse spacing depend on it, and the Q of the retuned bank enters the
  Leeson bracket. Run against the final netlist; the +0.5 to +5.5 dB
  inference in DR-005 is not a measurement.
- **#59 / #62** (layout / LVS). Unaffected only if the schematic is unchanged.
  Option (b)-success changes the varactor geometry and cell count and so the
  layout; option (a) does not.
- **Row 3 is coupled to row 2.** Its |Kvco| floor (381 MHz/V) is derived
  from row 2's 15 % (5.0 GHz geometric centre, x 0.9 coverage / 1.65 V:
  5 (sqrt(1.15) - 1/sqrt(1.15)) x 0.9 / 1.65 = 381 MHz/V). Under (a) it must be
  re-derived, not carried: e.g. 1.10 gives 260 MHz/V; the baseline's 1.113
  gives 292 MHz/V. (Illustrations of the dependency, not proposed values.)
- **Bad consequences.** (b) costs a characterization that may find nothing,
  and it is bounded to the shipped model's range; the J-transfer assumption
  above may be false, in which case the answer is (a) with little lost.
  Cell-scaling (cells in parallel keep per-cell C and Q) is assumed, not
  proven, outside the calibrated 12-16 cell range, and the +125 C corner
  cannot be simulated until the `dsubw` NaN problem (#95) is resolved, so
  neither clearing nor failing is graded at row 11 by this path.
- **Nothing is measured here.** No simulation was run. Every number above is
  arithmetic on committed records; the per-geometry bn = substrate ratios, the
  true fixed-C budget and the HBT-pair parasitics are all unmeasured.
- **Operator decision required** on: the F/V clearing threshold (0.10
  proposed), whether to authorize the follow-up, and, on failure, the value of
  X and Y. Row 2 stays binding as written until then.
