# 125 C start-up abort: is the ~16 nA `dsubw` leakage physical or a solver artefact? (issue #309)

Append-only. Follows `20261107-213000-fe779ef-hot-startup-trace.md` (#302/#303), which showed that referencing only the
PDK varactor subckt's `dsubw` diode to 125 C clears the first-timepoint abort on `xq1` (`rd` starts, `fd` aborts) and left
open *why* a ~0.5 nA/instance leakage decides convergence.
Testbench: `klt-sim/hot-startup-leakage/` (`run-probes.sh` regenerates every `body-*`, `svar-*`, `deck-*.cir` from the
#303 files, which are read-only; retained logs in `evidence/`). No spec row, PVT row, PDK file, `design/` file or existing
record is touched; the 125 C grid (#50) stays INCOMPLETE. Nothing here is adopted into the production bench.

## Verdict: **solver/model artefact**, mechanism identified at the model-card level
The leakage current is not what decides convergence. The 27-referenced `dsubw` diode has a **NaN junction capacitance at
125 C** (ngspice prints `cd = -nan`); the 125-referenced card gives a finite one. A NaN in a junction capacitance poisons
the transient start at the first timepoint. Evidence below; limits are stated in the last section (the NaN root cause is
read from the card and a hand calculation, not from an ngspice internal dump).

## 1. `dsubw` current against the tail and tank bias (converged 125 C `op`, quoted from `evidence/op-*-125.log`)
Unit: tt / hbt_typ / cap_typ, Vdd 3.3 V, Vctrl 1.65 V, `.temp 125`, `op`. The `op` converges (via "dynamic gmin
stepping", see Limits), consistent with #281.

| quantity (op-c0-125, no tnom option, dsubw follows global TNOM 27) | value |
|---|---|
| `dsubw` current per instance (`@d.xcvp1.dsubw[id]`, also `xcvn16`) | **-5.10375e-10 A** (reverse) |
| 32 instances | 1.633e-8 A (16.3 nA, hand multiplication) |
| tail current (`@q.xq3[ic]`) | 2.106966e-04 A |
| each tank inductor leg (`l.xl1.lk1#branch`, `l.xl2.lk1#branch`) | 1.053567e-04 A |
| `xq1` / `xq2` collector current (`[ic]`) | 1.051142e-04 A each |
| bias reference `xq4` (`[ic]`) | 1.059766e-04 A |
| total supply current (`vsup#branch`) | -3.17430e-04 A |

Ratios (hand division): per-instance leakage / tail = 2.4e-6; all 32 / tail = 7.7e-5; all 32 / total supply = 5.1e-5.
Correction to the issue text: the tank is biased at about **0.105 mA per leg (0.21 mA tail)**, not mA, so the ratio is
about 1e-4 rather than 1e-5/1e-6; the conclusion (leakage is a negligible fraction of the bias) is unchanged.
With `dsubw` at 125 C (`op-rd-125`) the same quantities are 3.30713e-12 A per instance, tank leg 1.053485e-04 A, total
3.17414e-04 A: the operating point differs by 5e-5 relative in total supply current (hand: 0.16 uA of 317.43 uA), i.e. the leakage does
not change the bias point in any way that could physically decide a start-up.

## 2. ngspice 47
**Not available.** Checked: `/home/ubuntu/.local/bin/ngspice` and `~/.local/opt/ngspice-46` are 46, `/usr/bin/ngspice` is 42,
no ngspice 47 anywhere on this worker (and the host rules forbid installing one). Every result below is ngspice 46
(banner in each log). The pinned-47 rerun of one failing unit remains **not done**; it is the one thing that could change
a solver-version statement, not the model-card observation in section 4.

## 3. Initial-state variants that keep the 27-referenced `dsubw` (all 125 C, tran `1p 2n 0 2p`, one unit each)
Controls reproduce #303 in the same run: `fd` aborts at the first timepoint, `rd` starts.

| variant | change | 125 C outcome |
|---|---|---|
| fd (control) | `tnom=125`, `dsubw` re-pinned to 27 | **abort**, `initial timepoint ... xq1` |
| rd (control) | no option, `dsubw` referenced to 125 | starts, vdiff_pp 0.5051628 V |
| fd-ramp | fd + supply ramped 0 to 3.3 V over 500 ps, 5 mV seed | **abort**, now at t = 8.656e-11 s, `xq1`, timestep 2.5e-24 |
| fd-icw | fd + `.ic` on the 64 internal well nodes (`w0`=3.3, `w1`=0) | **abort**, `initial timepoint ... xq1` |
| fd-ramp-icw | both | **abort**, t = 7.24e-13 s, node `xcvp1.w0` |
| rd-ramp (control for the ramp) | rd + same ramp | starts, 0.4490852 V |
| fd-nooff | fd, PDK's `off` flag removed from `dsubw` | **abort**, initial timepoint |

None of the initial-condition changes rescues the 27-referenced diode, and the ramp moves the abort from the first
timepoint into the ramp (a rd-ramp control with the identical ramp starts). So this is **not** a first-iteration
`.ic` / initial-state artefact that a better start removes; it is a property of the diode card at 125 C that stays
broken while the circuit moves.

## 4. What the leakage is *not*, and what it is
- **Not the leakage magnitude.** `fd-is0.0033` scales `jsw` (the term that carries the leakage: `jsw*pj`; `is*area` is
  about 1e-28 A) by 0.0033 so the 27-referenced diode leaks 4.97e-12 A per instance at 125 C (`op-fd-is0.0033-125`),
  the same size as `rd`'s 3.31e-12 A. It still **aborts**, as do 0.1 and 0.01 scales. (An earlier attempt that
  scaled `is` had no effect on the leakage and is not reported as a result.)
- **Not the junction capacitance value.** `fd-nocj` (`cjo = cjp = 0`, still tnom 27) still **aborts**.
- **The capacitance is NaN.** A bare two-diode probe (`deck-diode-tvj.cir`, `evidence/diode-cd-125.log`, same card,
  125 C, 1.65 V reverse, `show d : id cd`) prints `cd = 9.76683e-15` for the 125-referenced card and **`cd = -nan` for the
  27-referenced card**. That also explains why zeroing `cjo`/`cjp` does not help: ngspice still evaluates the
  temperature-adjusted junction-potential terms, and 0 x NaN = NaN.
- **Why NaN (hand calculation, not an ngspice dump).** The card has `vj = 0.1`. Using the SPICE3 junction-potential
  temperature relation (`vj*T/Tnom - 3*Vt*ln(T/Tnom) - Eg(Tnom)*T/Tnom + Eg(T)`, Eg by the Varshni form 1.16 - 7.02e-4 T^2/(T+1108)),
  the adjusted `vj` at 125 C referenced to 27 C is about **-0.29 V**; referenced to 125 C it is 0.1 V. A negative junction
  potential makes the depletion-capacitance term `(1 - V/vj)^-m` take a negative base: NaN. (`php = 0.457` stays
  positive, 0.18 V.) The relation is the textbook one; ngspice's own `tvj` is not exposed (`show` prints `?????????`),
  so the number is a consistency check, the NaN itself is the measurement.
- **Confirming variant.** `fd-vj` changes only `vj` 0.1 to 0.5 (tnom still 27, everything else as `fd`): **starts**,
  vdiff_pp 0.6138699 V. The 27-referenced card is fine once its adjusted junction potential cannot go negative.

## Conclusion
The abort is a **model-card / solver artefact, not a physical failure**: a 27-referenced `dsubw` with `vj = 0.1` produces a
NaN junction capacitance at 125 C when ngspice's global `TNOM` is not 125, independent of how little current it leaks
(3.3 to 5.1e-10 A) and independent of initial conditions. Consequences for the open question:
- The consumer's "`dsubw` at 125 C" approximation is working through the junction-potential scaling, not through
  leakage; its bound should be stated in those terms. That remains the consumer's call (sg13g2-lc-pll#173); this record
  does not change how any corner is graded.
- Physical hot-corner behaviour of the varactor well diode (leakage, capacitance) is still not characterised by any
  run here; a model that returns a finite capacitance at 125 C is a precondition, not evidence about the part.

## Limits
Single process/Vdd/Vctrl corner, one 2 ns window, one unit per variant, ngspice **46** only (47 unavailable, see 2).
Local runs on this worker (PDK `~/share/pdk/ihp-sg13g2`), not the fleet; the `rd` control gives vdiff_pp 0.5051628 V
against the fleet's 0.5051826 V in #303 (2e-5 V difference, platform/PDK-install dependent; abort-or-start outcomes of
all controls match #303). The negative-`vj` explanation is a hand calculation plus a measured NaN and one confirming
variant (`fd-vj`), not an inspection of ngspice's internal `tVJ`; a different card whose `vj` is also low would be
expected to show the same, which was not tested. The op converges only after "dynamic gmin stepping" and prints a
"temperature limiting function received NaN" self-heating note at 125 C in **every** 125 C unit, starting ones
included, so that note does not discriminate the aborts (checked in the #303 logs and here); its origin is untraced.
Probes are single `ngspice -b` runs launched sequentially from `run-probes.sh`; no batch grid was used, no fleet job
exists for this record, and `deck-*.cir` carry absolute paths from the run host.
