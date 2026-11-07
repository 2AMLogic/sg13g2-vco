# 125 C start-up abort: which element's TNOM dependence clears it (issue #302)

Append-only. Follows `20261106-055147-c9d7e70-hot-startup-bisect.md` (#297), which found that only `.options tnom=125`
(variant e) removes the first-timepoint abort on `xq1`, and left open which element's TNOM dependence did it.
Testbench: `klt-sim/hot-startup-trace/` (`gen.sh` regenerates every `body-*`, `request-*`, `ind-*`, `svar-*` file from the
#297 base `../hot-startup-bisect/body-e.spice` + `request-e.json`; per unit the generated deck `corner.cir` and the
retained `ngspice.log` are under `evidence/units/request-<v>/<unit>/`; reports and batch receipts beside them;
submit transcript `evidence/batch-set-stderr.txt`, envelope `evidence/batch-set-stdout.json`).
No spec row, PVT row, `design/` file or existing record is touched; the 125 C grid (#50) stays INCOMPLETE.

## Step 1: which elements follow the global TNOM (quoted from the pinned PDK files and the inductor subckt)
Global TNOM is the reference temperature of any element that has temperature coefficients but no `tnom` of its own.

| class | element(s) in the deck | evidence (file:line) | follows global TNOM? |
|---|---|---|---|
| inductor series loss | `Rser`, `Rk1..Rk10` (11 resistors; the Curator's "Rk1..Rk7" and the issue's "Rk1..Rk4" are both short) | `sg13g2_inductor_em.spice:156-175`, e.g. `Rk1  n02 n03 r={em_rlad} tc1={ind_tc2}`; `ind_tc2 = 3.8e-3` (:91); no `.model`, so no `tnom` | **yes** |
| varactor-subckt well/substrate diode | `dsubw` in each of the 32 `sg13_hv_svaricap` instances | `sg13g2_svaricaphv_mod.lib:56` `.model dsubw d is = 2.45E-17 ... cta = 1E-06` : **no `tnom`** | **yes** |
| OSDI varactor | `nmvcap1/2` (`mosvar`, level 1000) | same lib `+ tr = 27` (the model's nominal temperature, a literal) | **no** (pinned); checked by converse variant `ro` |
| HBT | `xq1..xq4` | `sg13g2_hbt_mod.lib:526` `+ tnom = 27` (literal, `.model npn13G2v_NX_vbic`); its `Rsub`, `Rt` are plain resistors | **no** (pinned) |
| MIM cap | `xc1` `cap_cmim` | `capacitors_mod.lib:45` `.model cmim_core C (TC1=3.6E-6 TC2=2E-9 TNOM=27 ...)`; series `R1 PLUS 1 r=55m` has no `tc1`/`tc2` | **no**, dropped |
| plain resistors | `RTE`, `RREF`, `RRE`; varactor-subckt `rww`, `rsubw`, `rk`, `rdummy1/2` | no `tc1`/`tc2`/`tce`/model on any of them | **no**, dropped |

"Dropped" for the last two rows is **by reading the netlists, not by simulation** (ngspice gives a resistor or
capacitor without a temperature coefficient a unit temperature factor). The HBT row is pinned by its card; no
HBT converse variant (card re-referenced to 125 C) was run, so the HBT's own TNOM behaviour is **not traced**.
The `.options tnom` is also a no-op for the OSDI `tr` (checked below, not assumed).

## Step 2/3: mechanism for each variant (all in the netlist; no PDK file edited)
- **Inductor class re-pin**: `ind-<v>.spice` is `ind_orig.spice` (byte copy of the #297 inductor) with the 11 resistors
  moved onto `.model rindm R (tnom=<27|125> tc1={ind_tc2})` and the instance `tc1=` dropped. A model's `tnom` overrides the
  global option for those resistors. Control `ci0` (model `tnom=27`, no global option) must equal the base, and does.
- **Diode / OSDI class**: `svar-<v>.spice` is a verbatim copy of the PDK subckt (`sg13g2_svaricaphv_mod.lib:27-152`)
  renamed `svar_loc` / `svar_loc_mod`, with only `dsubw` given `tnom = N` and/or `mosvar` `tr = N`. Controls `c1`/`e1`
  (copy, nothing changed, tnom off / on) must equal `c0`/`e0`, and do, so the copy is a faithful stand-in.
- **OSDI forward variant**: not run. `tr` is already the literal 27 under `.options tnom=125`, so the forward variant
  is variant (e) itself (`e0`); only the converse (`ro`, `tr=125`, no global option) is informative.

## Result (all 11 requests x {27 C, 125 C} on the batch fleet)
Fleet: runner klt 0.9.0, client klt 0.9.2.dev246, **ngspice-46** (banner in every `ngspice.log`), `c7i.4xlarge` Spot,
us-east-1, about 9 s per job. Same corner as #297: tt / hbt_typ / cap_typ, Vdd 3.3 V, Vctrl 1.65 V, `.ic`,
`tran 1p 2n 0 2p`. `vdiff_pp` = full-window pk-pk incl. start-up (a "does it start" figure, not a spec number).

| v | one change vs the base (no `tnom` option; all else PDK default) | fleet job id | 27 C vdiff_pp | 125 C outcome |
|---|---|---|---|---|
| c0 | none (control = #297 base) | `klt-sim-663c8abf3d22` | 0.5844139 V | **abort**, `xq1`, first timepoint |
| e0 | `.options tnom=125` (control = #297 variant e) | `klt-sim-46e8f2bd4c41` | 0.8127489 V | starts, 0.5920953 V |
| c1 | varactor subckt replaced by local copy (control) | `klt-sim-4ca7d0645526` | 0.5844139 V | **abort**, `xq1` |
| e1 | local copy + `tnom=125` (control) | `klt-sim-2de53bb5ca59` | 0.8127489 V | starts, 0.5920953 V |
| ci0 | inductor R model `tnom=27` (control) | `klt-sim-e6700f0d1457` | 0.5844139 V | **abort**, `xq1` |
| fi | `tnom=125`, inductor resistors re-pinned to 27 | `klt-sim-35ce2fffe63c` | 0.5858467 V | **starts, 0.5051826 V** |
| fd | `tnom=125`, `dsubw` re-pinned to 27 | `klt-sim-0d7641cc6803` | 0.8118898 V | **abort**, `xq1` |
| fid | `tnom=125`, inductor and `dsubw` both re-pinned to 27 | `klt-sim-a654df15a5a6` | 0.5844139 V | **abort**, `xq1` |
| ri | no option, inductor resistors referenced to 125 | `klt-sim-8f4c38124c12` | 0.8118898 V | **abort**, `xq1` |
| rd | no option, `dsubw` referenced to 125 | `klt-sim-49870272e038` | 0.5858467 V | **starts, 0.5051826 V** |
| ro | no option, OSDI `tr=125` | `klt-sim-6af8b7e67415` | 0.5844208 V | **abort**, `xq1` |

Every abort is the verbatim #297 text, `doAnalyses: TRAN:  Timestep too small; initial timepoint: trouble with xq1:...`,
in that unit's `ngspice.log`. The four starting 125 C units (e0, e1, fi, rd) have no such line.

## Conclusions (measured)
1. **The `dsubw` diode class alone reproduces (e)'s cure**: `rd` (the only change is `dsubw` referenced to 125 C, global
   TNOM left at 27) starts at 125 C. **Pinning it back to 27 C removes the cure**: `fd` aborts although `tnom=125` is on.
   `fi` and `rd` return identical numbers (0.5858467 V / 0.5051826 V) and so do `fd` and `ri`
   (0.8118898 V / abort), which is consistent with the two classes acting independently.
2. **The inductor resistor class does not cure the abort**: `ri` aborts, and `fi` (inductor pinned, diode following 125)
   starts. It is what moves the **27 C** control: with the resistors referenced to 125 C the 27 C amplitude is
   0.8119 V (`ri`, `fd`) against 0.5844 V; with them at 27 C it is 0.5844-0.5858 V. This is the cause of the 0.5844 to
   0.8127 V shift #297 left unexplained.
3. **The OSDI varactor is not the cure**: `ro` aborts. `tr` is a literal in the card, so the global option never
   reached it (the 27 C value moves 7e-6 V with `tr` 27 to 125: real, tiny, irrelevant here).
4. Nothing else reproduces the cure: `fid` (both TNOM-following classes pinned at 27) equals the base (`c0`) in all
   digits. The remaining deck elements are TNOM-independent (Step 1; the plain-R and MIM rows are by reading).

## Physical quantity or solver artefact?
- **The 27 C shift is physical**: the inductor series loss at 27 C is scaled from its 125 C reference, a factor
  `1 + 3.8e-3 x (27 - 125) = 0.628` (hand calculation from the `tc1` in line 91), so `Rser` and the ladder resistors at
  27 C are about 37 % lower and the oscillation amplitude rises. The `ri` / `fd` rows confirm the direction.
- **The cure is a change in the `dsubw` diode's parameters at 125 C, not a tolerance/conditioning option.** A
  single-point local probe (one `ngspice -b`, no grid; `evidence/local-diode-probe/`, ngspice-46) puts one instance's
  `dsubw` at 125 C, reverse 1.65 V: **5.09e-10 A with `tnom=27`, 1.66e-12 A with `tnom=125`, a factor of about 300**
  (the 27-referenced diode leaks about 300 x more at 125 C). That is an operating-point difference in a real device
  parameter, in the direction "more reverse leakage at 125 C aborts". It is not a gmin/itl change (variant d in #297 did
  not help).
- **NOT traced**: *why* a well-to-substrate leakage of ~0.5 nA per instance (~16 nA over the 32 instances) decides
  convergence at `xq1`'s first timepoint. The probe shows the parameter moved and the run shows the outcome moved with
  it; it does not show the mechanism (leakage path, junction capacitance scaling, or a pivot/Jacobian effect at the
  `op`). Whether the abort is therefore a physical failure of the circuit at 125 C or an initial-condition convergence
  failure that the diode merely perturbs is **not established**. Also not traced: the HBT card's own TNOM role; and the
  bench ties `bn` to ground, so the substrate-diode path is the one #198 (bn=substrate, gated) would change.

## Is (e) legitimate? What this does and does not license
The trace narrows #297's open question: `.options tnom=125` works through two independent effects, a physical
re-referencing of the inductor loss (moves the 27 C control, does not cure) and a re-referencing of the PDK varactor
subckt's substrate diode (cures). Adopting `tnom=125` in the production bench would therefore re-reference the
inductor loss for **every** temperature and silently re-baseline the 27 C results, while the only thing that clears the
abort is the diode's reference; that is a decision for a separate issue and this record **adopts nothing**. No claim is
made that any spec row is met at 125 C and no PVT row is re-graded; the 125 C grid (#50) is not yet gradeable on the
strength of this record.

## Limits
One process corner, one Vdd/Vctrl, one 2 ns window, one ngspice build (46), one unit per variant (no repeats; ngspice is
deterministic for a fixed netlist, and the controls reproduce #297 to all printed digits). The local varactor copy equals
the PDK subckt for this deck (c1/e1), not necessarily for other biases. The diode probe is a single hand-built
operating point, not the circuit's own bias. Job/instance details are in each `batch-receipt.json` / `report.json`.
