# sim/ — ngspice testbenches and append-only evidence records

Per this repo's `CLAUDE.md`: **verification is the product, no claim without a
testbench, PVT corners on every recorded result**, and everything here is
**append-only evidence** — a re-run mints a new, timestamped record; nothing
under `records/`, `netlist-snapshots/` or `corners/` is ever edited or deleted
after it lands. The convention follows `spec/porting-plan.md` §3, which names
it as the one category that transfers to this block from the catalog's more
mature siblings unchanged.

## Experiments

| Directory | Claim under test | Status |
|---|---|---|
| [`tank-characterization/`](tank-characterization/) | L / Q / SRF of the passives an LC tank on this PDK would be built from, over a wide candidate band | MIM cap characterized over the full PVT grid from the PDK's own models; **the spiral inductor cannot be characterized from the PDK — v0.3.0 ships no ngspice inductor model** (see that README's "The inductor gap"). The inductor half is covered by the model below, whose error bars travel with every number it produces. |
| [`inductor-model/`](inductor-model/) | that the analytic spiral-inductor model this repo ships implements the closed form it claims to, over a process × temperature grid; **and** ([`em-extraction/`](inductor-model/em-extraction/), #9) an openEMS extraction of the PDK's own inductor PCell, measured against it | Analytic: 27/27 known-answer points pass to 0.003 %. **This validates the implementation, not the physics** — the model is an *analytic screening* model with stated error bars (±5 % on L, Q an upper bound, 0.5–20 GHz), **not** a PDK model and **not** an EM extraction. EM extraction (openEMS v0.37.0-rc2, FDTD, 0.1–30 GHz): fit residual < 1 % rms within its fit band for all 3 LVS-testcase geometries; now the authoritative model for those 3 geometries — measured L within +5–8 % of the analytic model (confirms its bar), Q +17–35 % (confirms its "upper bound" direction), **SRF 50–77 % lower than analytic predicted** for the two multi-turn geometries. |
| [`varactor-characterization/`](varactor-characterization/) | C(V), dC/dV (Kvco) and Q(V,f) of the MOS varactor (`sg13_hv_svaricap`) and the two junction-diode candidates (`dantenna`, `dpantenna`) — the tuning-mechanism evidence `tank-characterization`'s finding 6 hands off | 216/216 simulation points PASS across 5 MOS × 3 diode process corners × 3 temperatures × 9 control-voltage points; known-answer method check passes to 0.1 % at every point. MOS varactor: `Cmax/Cmin` up to 2.08×, `Q` 224 down to 0.19 depending on geometry and frequency. Junction diodes: `Cmax/Cmin` only 1.03–1.24×, `Q` ~1–1.7 — not competitive tuning devices. Ratifies no `spec/target-spec.md` row. |
| [`oscillator-core/`](oscillator-core/) | the first experiment here that contains an **oscillator**: start-up from the differential initial condition, `f_osc` over the full 0.0–3.3 V `Vctrl` domain (hence the row-2 tuning ratio and the row-3 `Kvco` curve), the large-signal supply current, the differential-mode check, and the row-6 startup margin — all against the committed `design/vco.spice`, over the row-10/11 PVT grid | Bench and method shipped and exercised against the real netlist; **the graded PVT grid has not run, so no row is graded.** Extractor known-answer check: 56/56 quantities within tolerances *derived* from the estimator's own discretization bounds. Measured **pilot subset** (typical process corner, three row-11 temperatures, 13 transients + a 9-rung margin ladder): the oscillator starts at every point from the 10 mV `.ic` (settling 0.49–1.26 ns), is cleanly differential (`f(TAIL)/f_osc` = 2.000, common-mode amplitude ≤ 1.1 % of differential), tunes 4.61–5.45 GHz with a geometric band centre of 4.96–5.02 GHz, and draws 0.99–1.05 mW large-signal. **`Kvco` is strongly non-linear** — at 27 °C the per-segment slope runs from ~0 to −640 MHz/V, all of the tuning sitting above `Vctrl` ≈ 1.2 V. The remaining 134 PVT points (~180 CPU-hours) are blocked on `klt sim`, which cannot express this deck (no OSDI device loading, no `ngbehavior` selection, no `ihp-sg13g2` off-host image) — reproduced in [`oscillator-core/klt-sim/`](oscillator-core/klt-sim/), filed as [klayout-tools#2511](https://github.com/2AMLogic/klayout-tools/issues/2511), tracked as #50. No phase-noise (row 4) claim is made (#49). Ratifies no `spec/target-spec.md` row. |

## PDK pin

Every record in this tree is generated against the PDK revision pinned in
[`pdk.json`](pdk.json) (IHP-Open-PDK tag `v0.3.0`, with its tarball sha256).
Each record additionally states the exact `PDK_ROOT`, the ngspice version, and
the **content sha256 of every model library the run loaded**, so a reader can
confirm their own install matches without re-deriving it from the pin file
alone.

`pdk.json` also carries a `known_model_gaps` block. A device the PDK does not
ship a simulatable model for is a first-class constraint on what this repo can
evidence, not a footnote.

## Environment

`source env.sh` resolves `PDK_ROOT`/`PDK` — an explicit export wins, otherwise
the usual open_pdks install prefixes are probed. `run_pvt_sweep.sh` sources it
because it needs the PDK's model libraries; `run_model_check.sh` deliberately
does not, so it keeps its no-PDK-install cold start (see its own header and
`sim/lib.sh`'s header for why). An interactive `ngspice` session can source it
too, so nothing here can silently drift onto a different install than a
PDK-dependent script used.

## Directory / naming convention

```
sim/
  README.md                  this file — the authoritative convention
  pdk.json                   pinned PDK revision + known model gaps
  env.sh                     PDK_ROOT/PDK resolution, sourced by run scripts
                             that need the PDK (not all of them — see
                             "Environment" above)
  <experiment-slug>/         one directory per distinct claim under test
    README.md                what was measured, over what band and corners,
                             how to reproduce it, and what it does NOT show
    run_*.sh                 THE cold-start entry point: one command, no args
                             (e.g. run_pvt_sweep.sh, run_model_check.sh)
    .spiceinit               ngspice init copied into the run's scratch dir, so
                             a run never depends on $HOME/.spiceinit existing
    testbench/
      tb_<name>.spice.tmpl   the testbench template (@@PLACEHOLDER@@ form)
    netlist-snapshots/
      <record-id>/
        <corner-id>.spice    the exact generated netlist for that PVT point
    corners/
      <record-id>/
        <corner-id>.log      raw ngspice batch output for that PVT point
    records/
      <record-id>.md         narrative record: claim, method, corners, PDK
      <record-id>.csv        parsed scalar summary, one row per corner × device
      <record-id>-curves/    per-corner curve data vs. frequency, where the
                             curve rather than a scalar is the product
```

`<record-id>` is `<UTC yyyymmdd-HHMMSS>-<git short sha of the tree that ran>`.
`<corner-id>` names the PVT point (e.g. `mimcap_wcs_125c_1.5v`).

## Rules a record must satisfy

1. **One command, cold start.** `spec/review-bar.md` item 1: a single
   documented invocation regenerates the evidence from the committed netlist
   and the pinned PDK, with no hidden manual steps. If a run needs a build
   step, that step belongs *inside* the run script.
2. **Stated corners.** Every recorded result names the process/voltage/
   temperature points it was taken at, and states an explicit reason for any
   axis deliberately not swept.
3. **Frozen netlist.** A record freezes the exact netlist it simulated, so it
   stays readable after the template moves on.
4. **A failure is a result.** A model that does not exist, a point that does
   not converge, or a measurement that misses is recorded with its raw log —
   never dropped so the summary looks clean.
5. **Method before number.** A derived quantity states how it was derived. Where
   the derivation can be checked against closed-form algebra, it is (see
   `tank-characterization/`'s reference network); where it cannot — phase
   noise, per `CLAUDE.md` — the method, its variance and its limits are stated
   with the number or the number is not a result.
6. **A non-PDK model is labelled as one, everywhere it is used.** Where a
   device model does not come from the pinned PDK (e.g.
   `inductor-model/sg13g2_inductor_analytic.spice`, an analytic model standing
   in for a device v0.3.0 ships no model for), the record names that file by
   **repo-relative path and content sha256**, and the model's own stated
   accuracy limits propagate to every number derived from it. A reader must
   never have to guess whether a number came from the PDK or from a
   substitute.
