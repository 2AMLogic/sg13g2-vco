# 125 C start-up abort: single-change variant bisect on the batch fleet (issue #297)

Append-only. Follows `20261103-185500-666800d-hot-startup.md` (issue #280), which left the cause of the 125 C
abort "inferred, not traced" and listed the variants it did not try. This record runs those variants.
Testbench: `klt-sim/hot-startup-bisect/` (`body-<v>.spice`, `request-<v>.json`, and for every unit the generated
deck `corner.cir` and the **retained `ngspice.log`** under `evidence/units/request-<v>/<unit>/`; klt reports and
batch receipts beside them; submit transcript in `evidence/batch-set-stderr.txt`).

## Method
- Base: the `hot-startup/` recipe, unchanged (`vco_core_body.spice` = device section of `design/vco.spice` plus
  `.ic v(OUTP)=3.305 v(OUTN)=3.295`; same `sg13g2_inductor_em.spice`; tt / hbt_typ / cap_typ; Vdd 3.3 V; Vctrl 1.65 V;
  OSDI varactor via `options.osdi_preload`; `tran 1p 2n 0 2p`). **Each variant changes exactly one thing** against that
  base. T = 27 C and 125 C in every request (two units per request).
- Submission: `klt sim --backend batch --batch-set request-{a..f}.json --max-in-flight 3`, all six on the Spot fleet
  (runner klt 0.9.0, client klt 0.9.2.dev47, ngspice-46 on the runner: `environment.remote.worker_environment.simulator.version_banner` in each `report.json`, and the last line of every `ngspice.log`; the earlier "ngspice-42" wording was wrong). **Nothing ran as a local ngspice grid.**
  No Spot refusal and no `--resume` was needed. The job-bound warning in the transcript (6120 s vs a 3600 s ceiling) is
  klt's conservative serial bound; every job finished in about 7 s of runtime.
- Runner PDK at `/opt/pdk` (the same fleet PDK as #280; not comparable by stamp to a host PDK).

| v | one change | fleet job id | 27 C unit | 125 C unit |
|---|---|---|---|---|
| a | `.ic` line removed | `klt-sim-3dbcc6036d2e` | runs; Vdiff pk-pk 9.1e-10 V (does **not** oscillate, no kick) | **abort**, first timepoint, `xq1` |
| b | `.ic` kept, `tran ... uic` | `klt-sim-09fdfb46f23f` | **abort**, first timepoint, `xq1` | **abort**, first timepoint, `xq1` |
| c | `.nodeset` (same voltages) instead of `.ic` | `klt-sim-c289b57bd30d` | runs; 1.2e-5 V (does **not** oscillate) | **abort**, first timepoint, `xq1` |
| d | `.options gmin=1e-10 itl4=100` (ngspice defaults: gmin 1e-12, itl4 10) | `klt-sim-6a7d4a97ad83` | starts; 0.5844 V (= base) | **abort**, first timepoint, `xq1` |
| e | `.options tnom=125` | `klt-sim-81aea7ca0a1e` | starts; **0.8127 V** (base was 0.5844) | **starts; 0.5921 V pk-pk**, no abort |
| f | `selft=0` on XQ1-XQ4 | `klt-sim-cf0e7f48ce58` | starts; 0.5822 V | **abort**, first timepoint, `xq1` |

Abort text, verbatim, from every failing unit's `ngspice.log` and report:
`doAnalyses: TRAN:  Timestep too small; initial timepoint: trouble with xq1:npn13g2v_nx_vbic-instance q.xq1.qnpn13g2v`.
Vdiff pk-pk values are the `vdiff_pp` measurement over the full 2 ns (includes the start-up transient; it is a
"does it start" figure, not a spec number).

## How each variant was expressed
- (a)(c)(d)(e) are lines in the netlist body (`.ic` removal, `.nodeset`, `.options`). (b) is `analysis.args` =
  `1p 2n 0 2p uic`. All five fit a stock `klt sim` request; no klt gap was hit, so no klt issue was filed.
- (f): the `npn13G2v` subcircuit in `sg13g2_hbt_mod.lib` takes `selft` (default 1; `rth = selft*1.55E+03*...`), so
  self-heating is switched off with instance parameter `selft=0` on the four `XQ` lines. Expressible; not dropped.
- (e): the model card pins `tnom = 27` as a literal (`sg13g2_hbt_mod.lib`, `.model npn13G2v_NX_vbic`), so the PDK
  exposes **no** card-level TNOM override; `.options tnom=125` is the global option only. That it nevertheless changed
  the 27 C result (0.5844 V to 0.8127 V) shows it reaches something in this deck (not traced which element).

## Does any variant isolate the cause? (measured, not inferred)
Measured single-change outcomes at 125 C: **only (e) removes the abort.** (a), (b), (c), (d) and (f) all keep the
identical first-timepoint abort on `xq1`.

- **The NaN is not the cause of the abort.** The committed log `evidence/units/request-a/tt_typ_typ_1p650V_125C/ngspice.log`
  (line 12) reads `The temperature limiting function received NaN. Please check your power dissipation and improve
  your heat sink Rth!`, printed once before the `op`, followed by dynamic gmin stepping (lines 16-17) and the abort
  (line 320). It does **not name a device**. The message is the self-heating (Rth) thermal-node limiter. Two measured
  facts break the "NaN causes the abort" chain from #280: (f) `request-f/.../125C/ngspice.log` has **no NaN line and no
  gmin stepping and still aborts at the same device**; and (e) `request-e/.../125C/ngspice.log` prints the NaN line
  (line 12) and **still runs**. So the NaN is present without the abort and the abort is present without the NaN.
  The #280 claim that it was the inferred cause is **refuted**; the line is a co-symptom of 125 C. (#280's log-only
  observation of the line is now backed by committed logs.)
- **Self-heating off (f) does not cure it**, so the abort is not caused by the Rth/thermal node.
- **`uic` (b) is not a usable bench change:** it aborts at 27 C too (the 27 C log shows the NaN line there, line 14),
  so it removes the `op` and fails everywhere. It is not a start-up fix and not a 125 C-specific result.
- **gmin/itl4 (d), `.nodeset` (c), no `.ic` (a)** do not cure it.
- **(a) and (c) show a control weakness:** without `.ic`'s differential kick the 27 C control does not oscillate within
  2 ns (9e-10 V and 1.2e-5 V). They test only "does the 125 C abort survive", and it does.
- **The abort device is `xq1`** (the first cross-coupled HBT; ngspice names the first instance that fails, not
  necessarily the root cause). Which instance parameter, node or temperature relation in `xq1`'s VBIC card drives it
  was **not traced**; (e) says the abort depends on the global TNOM option, not why.

## Is (e) a legitimate bench change or a numerical mask?
**Not established; recorded as neither yet, and not adopted.** What is measured: `.options tnom=125` makes the 125 C
unit start (0.5921 V) but also moves the 27 C control (0.8127 V vs 0.5844 V), so it changes the circuit being
simulated rather than only conditioning the solver. Against "legitimate": it redefines the reference temperature of
every element that follows the global TNOM, and the HBT card keeps `tnom = 27`, so the device that aborts is not
re-referenced by the card. Against "numerical mask": it is not a tolerance/gmin loosening (that was (d), which did not
help). The resolution needs a trace of which element's TNOM dependence changed, which this record does not have.
**No claim is made that rows 1-3 (or any spec row) are met at 125 C**, no PVT row is re-graded, and the 125 C grid
(#50) stays INCOMPLETE.

## Limits
One process corner, one Vdd/Vctrl, 2 ns window, one ngspice build: this classifies a start-up abort, it is not a PVT
result. A pass at 125 C for (e) is a single unit. Instance/zone for each job is in its `batch-receipt.json` / report.
