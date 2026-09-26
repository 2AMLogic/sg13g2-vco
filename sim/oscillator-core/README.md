# `oscillator-core/` — start-up, `f_osc` / tuning range and large-signal supply current of `design/vco.sch`

The first experiment in this tree that contains an **oscillator**. The other
three characterize the devices an LC-VCO is built from
([`tank-characterization/`](../tank-characterization/),
[`inductor-model/`](../inductor-model/),
[`varactor-characterization/`](../varactor-characterization/)); this one
simulates the committed netlist and measures the circuit.

Issue #47. Step (3) of the operator's sequencing on #3, first half — the
phase-noise bench (row 4) is deliberately separate, see "What this does not
show".

## What is measured, and which `spec/target-spec.md` rows it feeds

| Row | What this bench produces | Note |
|---|---|---|
| 1 — band 4.5 / **5.0** / 5.5 GHz | `f_osc` at the band-centre control voltage (1.65 V), per corner | |
| 2 — tuning range `f_max/f_min ≥ 1.15` (stretch 1.20) over the full 0.0–3.3 V `Vctrl` domain | the fractional ratio per corner, with its quantization floor stated alongside the verdict | a ratio landing inside the floor of the bound is recorded as `WITHIN QUANTIZATION FLOOR OF BOUND`, never as a bare pass |
| 3 — `Kvco` slope **and its linearity** | `Kvco(Vctrl)` as first differences of the measured `f_osc(Vctrl)` curve, plus a linearity number | **row 3 is OPEN.** This is the evidence it waits on. *Measuring a row is not ratifying it* — ratification is a `spec/decision-records/` PR and is out of scope here |
| 6 — startup / negative-g<sub>m</sub> margin `≥ 3.0`, at every bound corner of the row-10 set | the **tail-current-scaling threshold proxy**, bracketed, at 33 bound corners | see "Row 6: what is actually measured" — "it oscillated" is *not* reported as a row-6 pass |
| 8 — core power `≤ 10 mW` at nominal rail, band centre, nominal temperature | the **large-signal** average supply current over the settled window, reported separately from the DC operating point's current | both are recorded, in distinct columns, and never conflated |
| 10 / 11 — PVT corner set and −40 … +125 °C | the grid every number here spans | |

Row 4 (phase noise) is **not** graded here.

## Method, in full

A frequency without its method is not a result (`CLAUDE.md`). Everything below
is also restated in each record, so a record is readable without this file.

**There is no PSS.** ngspice ships neither periodic steady-state nor `pnoise`,
so there is no harmonic-balance oscillator solve to ask for a frequency.
`f_osc` here is a **transient plus period count** — the same method
`design/run_elaborate.sh` uses for its nominal-corner smoke run, lifted and
graded. It is not a spectral estimate. It states no phase noise and no line
width, and nothing in this directory is a substitute for the row-4 method.

- **Transient**: `tran 1p 20n 0 2p`. The 2 ps timestep ceiling is ~100 samples
  per period at the 5 GHz row-1 target; 20 ns is ~100 periods.
- **Start-up**: a **10 mV differential initial condition**,
  `.ic v(OUTP)=3.305 v(OUTN)=3.295`. It is an *initial condition, not a drive*
  — it is never refreshed. A perfectly symmetric cross-coupled pair otherwise
  sits on its unstable DC equilibrium and never starts. `design/vco.spice`
  carries the same mechanism; the bench restates it explicitly so the deck
  reads on its own and so the margin bench can compare an envelope against a
  named perturbation amplitude.
- **Discarded startup window**: `0 … 10 ns`. Everything before 10 ns is thrown
  away, so the recorded frequency and amplitude are of the *settled*
  oscillation. The startup transient is not discarded as a measurement —
  `t_settle_s` reports when the envelope first reached 90 % of its final
  peak-to-peak and stayed there, from the same trace.
- **Measurement window**: `10 … 20 ns`, ~50 settled periods at 5 GHz.
- **Period counting**: rising crossings of `v(OUTP) - v(OUTN)` through the
  window's own **trapezoidal time average** (not through zero — the
  common-mode, tail and supply-current traces all ride on a DC level and
  counting about zero there counts nothing), with each crossing time
  **linearly interpolated** between the two bracketing samples, and
  `f = (N-1) / (t_last - t_first)` taken from the first and last crossing so
  per-cycle jitter averages out. Implemented once, in
  [`sim/lib.sh`](../lib.sh) `osc_metrics`.
- **Frequency quantization floor**: recorded per point, **both** bounds.
  `quant_floor_interp_pct` = `dt_max · f / cycles` is the bound on the
  estimator actually used; `quant_floor_count_pct` = `1/cycles` is what the
  floor would be without interpolation. At the bench's settings these are
  ≈ 0.02 % and ≈ 2 % respectively. A row-2 verdict within the floor of its
  bound says so.
- **Supply current, twice**: `isup_dc_op_a` / `p_core_dc_op_w` from the DC
  operating point, and `isup_ls_avg_a` / `p_core_ls_w`, the **large-signal**
  trapezoidal time average of `-i(VSUP)` over the settled window. Row 8 is the
  large-signal one — the pair's average current shifts once it is switching, so
  the operating point alone is not that number. Reporting only one of the two
  would hide which is which.
- **Differential-mode check, on every point**: `vpp_cm_over_diff`,
  `f_cm_over_diff` and `f_tail_over_diff`. A genuinely differential tank puts
  the whole fundamental into `v(OUTP)-v(OUTN)` and leaves the common mode and
  the tail node with only the 2f component the two half-circuits pump in phase,
  so both frequency ratios should land near 2 and the common-mode amplitude
  should be a small fraction of the differential one. **A fundamental in the
  common mode would mean two independently resonating branches**, and every
  frequency, tuning and power number above would be measuring the wrong
  circuit. The observation nodes are behavioural sources into 1 GΩ — they
  cannot load the tank.
- **`Kvco`**: first differences of the measured `f_osc` between consecutive
  swept `Vctrl` points. That is the same finite-difference derivation
  [`varactor-characterization`](../varactor-characterization/) applies to
  `C(V)`, and the `Vctrl` list here is that study's own list plus 1.65 V, so
  the two studies' `dC/dV` and `df/dV` share an abscissa and are comparable
  point for point rather than interpolated against each other. Linearity is
  the peak-to-peak spread of the per-segment slopes as a percentage of their
  mean; 0 % would be perfectly linear, and it is `nan` with fewer than three
  segments.
- **A corner that does not oscillate is a finding**, recorded with status
  `NOSC` and kept in the grid with its raw log. It is distinguished in the CSV
  and in the record from status `FAIL`, which means the *simulation* failed —
  they are different results and row 6 in particular is decided by which one
  it is.

### Row 6: what is actually measured

Row 6 is a **ratio** — total g<sub>m</sub> ≥ 3.0 × tank loss conductance — not
"it started". Oscillating proves the ratio exceeds 1, never that it exceeds 3.
This bench therefore measures the declared **proxy**: the oscillation
**threshold tail current**. It walks the bias mirror's reference resistor RREF
up a ladder (×1 … ×12), measures the tail current at each rung from the tail
device's own emitter resistor, and reports

```
margin_proxy  =  I_tail(nominal) / I_tail(threshold)
```

**Why that maps onto the row's quantity.** For a bipolar cross-coupled pair
each device carries `I_tail/2` at balance and `g_m = I_C/V_T`, so g<sub>m</sub>
is proportional to `I_tail` *exactly* in the forward-active exponential region
— not approximately, and with no geometry factor. Startup requires
g<sub>m</sub> ≥ G<sub>tank</sub>, so the current at which startup ceases is the
current at which g<sub>m</sub> = G<sub>tank</sub>, and the ratio of the nominal
current to it **is** g<sub>m,nom</sub>/G<sub>tank</sub>.

**Where the map is imperfect** — stated, because a proxy without its limits is
not better than no proxy:

1. `g_m ∝ I_tail` assumes the HBT stays forward-active and out of high
   injection. The run therefore **measures** `I_tail` at every rung from
   `V(TE)/R(RTE)` instead of assuming it tracks `1/RREF`, so a departure shows
   up in the recorded ladder rather than hiding inside it.
2. G<sub>tank</sub> is treated as constant along the ladder. It is not exactly:
   `V(TAIL)`'s DC level moves as the current falls, which moves the varactor
   bank's bias and the pair's own loading. The recorded `v_tail_mean_v` per
   rung bounds that drift.
3. The threshold is **bracketed, never interpolated**: the record gives the
   last rung that oscillated and the first that did not, and the margin as the
   interval between the two ratios.
4. Near threshold the startup time constant diverges, so a rung still growing
   when the 20 ns window ends is recorded as *not* oscillating. That biases the
   threshold current up and the margin **down** — the proxy is conservative. A
   row-6 `MET` from it is a lower bound; a row-6 `NOT MET` is recorded with the
   rung's envelope so a reader can see whether it is a window artifact.

The oscillation criterion per rung is stated, not implied: the envelope's
peak-to-peak over the last quarter of the transient must reach **10 × the
10 mV differential initial condition**. An envelope that merely fails to decay
is not an oscillation.

Row 6 says *"at every bound corner of the row-10 set"*, so the margin pass runs
at MOS `{ss,ff,sf,fs}` × MIM `{bcs,wcs}` × HBT `{bcs,wcs}` × T `{−40,125}` = 32
corners, plus the nominal corner as the reference. MOS `sf`/`fs` are in that set
for the same reason they are in the main grid: `varactor-characterization`
established by reading `cornerMOShv.lib` that they carry *distinct*
`sg13g2_hv_svaricap_{vfbo,toxo,dlq,dwq}` values, so they are not interior to
`ss`/`ff` for the device that does the tuning.

### The extractors are checked, not trusted

`run_method_check.sh` applies the same `osc_metrics` / `osc_settle` to
synthetic waveforms whose frequency, amplitude, time average and settling time
are known in **closed form**: pure sinusoids at 4.5 / 5.0 / 5.5 GHz (bracketing
the row-1 band), an exponentially settling sinusoid whose 90 % settling time is
`−τ·ln(0.1)`, and — the falsification case — a constant trace, where the
correct answer is `f = 0`, because a non-starting PVT corner is exactly the
finding the graded sweep must not misreport.

**Its tolerances are derived, not chosen.** Each is a closed-form bound on the
estimator's own discretization error at the timestep ceiling being checked,
times a stated ×1.5 headroom, and each row names its bound in a `tol_basis`
column: `dt·f/cycles` for frequency, `1−cos(π·dt·f)` for amplitude (peak
sampling), `amp/(π·cycles)` for the time average (non-integer-period residual),
half a period for settling time (`osc_settle` resolves to the nearest local
extremum by construction). The check runs at four ceilings (2 / 5 / 10 / 20 ps)
so the error *model* is validated over a range rather than at one point.

Latest result: **56/56 quantities within their derived tolerance.** Worst
measured frequency error 3.2 × 10⁻⁴ % (at the 20 ps ceiling; ≤ 1 × 10⁻⁷ % at
the 2 ps ceiling the graded sweep runs at). The 20 ps ceiling's amplitude error
is 4.4 %, correctly predicted by the `1−cos(π·dt·f)` bound — which is the
evidence for *not* running the grid that coarse.

## Reproducing it

Three no-argument entry points. Each runs its own preflight
(`design/netlist.sh --check`, then `sim/tools/build-osdi.sh`), so there is no
hidden manual step — `sim/README.md` rule 1.

```bash
sim/oscillator-core/run_method_check.sh   # seconds, no PDK required
sim/oscillator-core/run_probe.sh          # ~35 CPU-min, one nominal PVT point
sim/oscillator-core/run_pvt_sweep.sh      # the graded grid -- SEE THE COST BELOW
```

`osc_bench.sh` next to them is experiment-local shared code, sourced by the two
PDK-dependent scripts; it is not an entry point and has no shebang. The
genuinely reusable extractors live in [`sim/lib.sh`](../lib.sh) instead, because
`run_method_check.sh` has to validate *the same* functions the sweep grades
with — a private copy would be a copy the method check does not check.

If the PDK is not under one of the prefixes `sim/env.sh` probes:

```bash
export PDK_ROOT=/path/to/ihp-open-pdk PDK=ihp-sg13g2
```

**The netlist-freshness gate is load-bearing.** Every PDK-dependent run calls
`design/netlist.sh --check` *before* it generates anything and aborts on a
netlist that has drifted from `design/vco.sch`, so a record can never grade a
stale netlist. The testbench takes the device lines **verbatim** from
`design/vco.spice`'s device section, splitting at its
`**** begin user architecture code` marker and dropping exactly two things: the
`.save i(vsup)` card (a `.save` *restricts* the saved set, which would make
every node voltage unavailable and the differential-mode check impossible) and
the schematic's own elaboration `.control` block (this bench supplies its own
analysis). Nothing is rewritten. `design/` is read-only to this experiment.

### The graded grid is a fleet job, and it did not run here

`run_pvt_sweep.sh` declares MOS `{tt,ss,ff,sf,fs}` × MIM
`{cap_typ,cap_bcs,cap_wcs}` × HBT `{hbt_typ,hbt_bcs,hbt_wcs}` × T
`{−40,27,125} °C` = **135 PVT points**, × a 10-point `Vctrl` axis = **1350
transients**, plus 33 × 7 = **231 margin transients**.

Measured on the dispatch host (ngspice-46, one core, the 2 ps ceiling): this
netlist simulates at roughly **13 ps of circuit time per wall-clock second** —
32 OSDI varactor instances and four HBTs, all stiff — so one 20 ns point is
**~25 CPU-minutes** and the declared grid is **several hundred CPU-hours**.
(The rate is not uniform: edge-of-domain control voltages converge more slowly
than the band-centre point that number was measured at.) The script prints its
own point count and cost estimate before it starts, and every point writes its
frozen netlist, raw log and CSV row as it completes, so an interrupted run
leaves usable partial evidence rather than nothing.

**That grid was not run in this PR.** The host these agents run on is a shared
dispatch worker whose operating rules send any multi-corner SPICE grid to a
batch fleet via `klt sim`, and `klt sim` cannot express this deck: it has no way
to load the Verilog-A/OSDI varactor model, no way to set the `ngbehavior=hsa`
compatibility mode the PDK's model cards need, and the off-host backends have
no `ihp-sg13g2` image. All of that is **reproduced rather than asserted** in
[`klt-sim/`](klt-sim/), together with the request document to submit once it
closes, and filed upstream as
[2AMLogic/klayout-tools#2511](https://github.com/2AMLogic/klayout-tools/issues/2511)
under this repo's friction protocol. What is committed instead is the
single-point calibration probe below — and the honest statement that the graded
row verdicts are *not yet measured*.

## What is here

```
oscillator-core/
  README.md                this file
  .spiceinit               ngbehavior=hsa, copied into every run's scratch dir
  osc_bench.sh             experiment-local shared driver (sourced, not run)
  run_pvt_sweep.sh         the graded row-10/11 grid + the row-6 margin pass
  run_probe.sh             one nominal PVT point at two timestep ceilings
  run_method_check.sh      known-answer check of the extractors (no PDK)
  testbench/
    tb_vco_core_tran.spice.tmpl              startup / f_osc / supply current
    tb_vco_core_margin.spice.tmpl            the row-6 tail-current ladder
    tb_period_count_known_answer.spice.tmpl  the synthetic closed-form traces
  klt-sim/                 the corner-runner request, and why it does not run
  netlist-snapshots/<record-id>/   the exact deck simulated, per point
  corners/<record-id>/             the raw ngspice log, per point
  records/<record-id>*.{md,csv}    the append-only evidence
```

Nothing under `records/`, `netlist-snapshots/` or `corners/` is ever edited or
deleted: a re-run mints a new record ID (`sim/README.md`).

## Records

| Record | What it is |
|---|---|
| `records/<id>.md` + `records/<id>-method-check.csv` from `run_method_check.sh` | the extractor validation. 56/56 quantities within their derived tolerances. Grades no spec row and says nothing about `design/vco.sch`. |
| `records/<id>.md` + `records/<id>-probe.csv` from `run_probe.sh` | the single-point calibration probe: the nominal PVT corner at the band-centre control voltage, at two timestep ceilings, with the timestep-convergence delta. **Grades no spec row** — one corner is not row 10's PVT set, one control voltage is not row 2's domain, and an oscillation that happens is not row 6's ratio. |

## What this does **not** show

- **No phase noise.** Row 4 is not graded here, and not because it is
  inconvenient: `CLAUDE.md` requires every phase-noise number to carry its
  transient length, window, estimator (or ISF derivation), variance and known
  limits, which is a method-design problem of its own size — and one that needs
  a working, graded transient oscillator bench to build on. That is what this
  is. The phase-noise bench is separate, later work.
- **No frequency here is a PDK-model result.** The PDK ships **no
  spiral-inductor ngspice model** (`sim/pdk.json` →
  `known_model_gaps.spiral_inductor`). Both tank inductors come from this
  repo's own EM-fitted `sim/inductor-model/sg13g2_inductor_em.spice`, named by
  path *and content sha256* in every record. **Every frequency in this tree
  inherits that model's stated error bars** — see
  [`../inductor-model/README.md`](../inductor-model/README.md), which is
  explicit that the EM fit is authoritative only for the three LVS-testcase
  geometries and that its analytic predecessor's SRF was 50–77 % optimistic.
- **No graded PVT verdict yet.** The row 1 / 2 / 3 / 6 / 8 verdicts this bench
  is built to produce require `run_pvt_sweep.sh` to have run. It has not. Until
  it does, **whether the committed sizing lands in the row-1 band, whether
  row 2's 1.15 ratio is reachable, and whether the oscillator starts at any
  corner beyond the nominal one are all unmeasured** — and this directory says
  so rather than implying otherwise.
- **This ratifies no `spec/target-spec.md` row**, including row 3, whose
  evidence it supplies. Ratification is a `spec/decision-records/` PR.
- **No layout, DRC, LVS or post-layout anything.** Later in the sequence.
