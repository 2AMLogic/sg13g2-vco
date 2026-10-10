# `oscillator-core/` — start-up, `f_osc` / tuning range and large-signal supply current of `design/vco.sch`

> **Note (#79, 2026-10-09): the numbers in this directory describe the PRE-#79
> netlist.** `design/vco.sch` tied each varactor's `bn` (the p-substrate) to the
> tank node; it now ties it to `0`. That adds a well-to-substrate junction to
> both tank nodes and, measured on the passive tank (`../bn-substrate-tank/`),
> lowers f0 by 17-23 % and tank Q by 17-28 %. These records are append-only and
> are not edited; they could not be regenerated for #79 (this host cannot load
> the OSDI varactor; the batch runner cannot take an `osdi_preload` request).
> Do not read any frequency, tuning ratio or `Kvco` below as describing the
> current `design/vco.spice`.

The first experiment in this tree that contains an **oscillator**. The other
three characterize the devices an LC-VCO is built from
([`tank-characterization/`](../tank-characterization/),
[`inductor-model/`](../inductor-model/),
[`varactor-characterization/`](../varactor-characterization/)); this one
simulates the committed netlist and measures the circuit.

Issue #47. Step (3) of the operator's sequencing on #3, first half — the
phase-noise bench (row 4) is deliberately separate (#49), see "What this does
not show".

**Read this first.** The bench is complete and exercised against the real
netlist, and it has produced measured numbers — but **over a declared
*subset* of the corner grid, so it grades no `spec/target-spec.md` row.** The
graded grid is ~180 CPU-hours and could not be routed off-host; see "The
graded grid is a fleet job" below, and #50.

## What is measured, and which `spec/target-spec.md` rows it feeds

| Row | What this bench produces | Note |
|---|---|---|
| 1 — band 4.5 / **5.0** / 5.5 GHz | `f_osc` at the band-centre control voltage (1.65 V), per corner | |
| 2 — tuning range `f_max/f_min ≥ 1.15` (stretch 1.20) over the full 0.0–3.3 V `Vctrl` domain | the fractional ratio per corner, with its quantization floor stated alongside the verdict | a ratio landing inside the floor of the bound is recorded as `WITHIN QUANTIZATION FLOOR OF BOUND`, never as a bare pass |
| 3 — `Kvco` slope **and its linearity** | `Kvco(Vctrl)` as first differences of the measured `f_osc(Vctrl)` curve, plus a linearity number | **row 3 is OPEN.** This is the evidence it waits on. *Measuring a row is not ratifying it* — ratification is a `spec/decision-records/` PR and is out of scope here |
| 6 — startup / negative-g<sub>m</sub> margin `≥ 3.0`, at every bound corner of the row-10 set | the **tail-current-scaling threshold proxy**, bracketed | see "Row 6: what is actually measured" — "it oscillated" is *not* reported as a row-6 pass |
| 7 — output swing `Vpp_diff ≥ 0.40 V` (stretch 0.65 V) in `W`, no buffer, plus the HBT compliance `(VDD + Vpp_diff/4) − V(TAIL)_min ≤ 2.2 V` (RATIFIED, DR-004) | `vpp_diff_v` at the tank nodes per window point; per point, the **sampled cycle minimum** of `V(TAIL)`, the actual rail and `VCE_max` with its sampling bound | see "Row 7: swing and cycle-minimum compliance" — a compliance value inside its sampling bound of the limit is `WITHIN SAMPLING BOUND`, never a pass; the global verdict is stage-1 (nominal rail); the DR-004 supply sub-corners are graded per rail by the same grader and compared by `report_supply_stage2.sh` |
| 8 — core power `≤ 10 mW` at nominal rail, band centre, nominal temperature | the **large-signal** average supply current over the settled window, reported separately from the DC operating point's current | both are recorded, in distinct columns, and never conflated |
| 10 / 11 — PVT corner set and −40 … +125 °C | the grid `run_pvt_sweep.sh` declares and that every graded number must span | **not yet run** — see below |

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

- **Transient**: `tran 1p 5n 0 2p`. The 2 ps timestep ceiling is ~100 samples
  per period at the 5 GHz row-1 target.
- **Start-up**: a **10 mV differential initial condition**,
  `.ic v(OUTP)=3.305 v(OUTN)=3.295`. It is an *initial condition, not a drive*
  — it is never refreshed. A perfectly symmetric cross-coupled pair otherwise
  sits on its unstable DC equilibrium and never starts. `design/vco.spice`
  carries the same mechanism; the bench restates it explicitly so the deck
  reads on its own and so the margin bench can compare an envelope against a
  named perturbation amplitude.
- **Discarded startup window**: `0 … 2.5 ns`. **This number is derived from a
  measurement, not from an assertion.** `design/vco.spice`'s comments propose
  a 20 ns transient with a 10 ns discard on the reasoning that startup
  "completes inside the first nanosecond"; a 2 ns exploratory transient put
  the 90 %-envelope settling time at the nominal corner at **0.883 ns**, the
  window was sized from that, and the pilot then measured **0.487 … 1.256 ns**
  across its corners. The discard is therefore 2.0× the slowest settling
  actually observed. A corner that needs longer is not hidden by this: every
  point records its own `t_settle_s`, which comes back `nan` when the envelope
  never reached 90 % of its final amplitude and stayed there.
- **Measurement window**: `2.5 … 5 ns`, 10–13 settled periods at the measured
  4.6–5.4 GHz.
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
  floor would be without interpolation. Over the pilot these measured
  **0.082 – 0.092 %** and **7.7 – 10 %** respectively. A row-2 verdict within
  the floor of its bound says so. Sub-0.1 % is three decimal places below the
  tightest comparison this bench makes (row 2's 1.15 ratio), which is why a
  longer, 4× more expensive transient is not bought.
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
  `C(V)`, and the `Vctrl` values here are drawn from that study's own list, so
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
up a ladder (×1 … ×24), measures the tail current at each rung from the tail
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
   up in the recorded ladder rather than hiding inside it. The measured ladder
   confirms this is not academic: at ×8 the measured current ratio is 6.93,
   not 8.
2. G<sub>tank</sub> is treated as constant along the ladder. It is not exactly:
   `V(TAIL)`'s DC level moves as the current falls, which moves the varactor
   bank's bias and the pair's own loading. The recorded `v_tail_mean_v` per
   rung bounds that drift.
3. The threshold is **bracketed, never interpolated**: the record gives the
   last rung that oscillated and the first that did not, and the margin as the
   interval between the two ratios. The ladder keeps its finest spacing around
   the row-6 bound of 3.0 (rungs at ×2/×3/×4) and opens out geometrically
   above it, so a comfortably-passing corner's threshold is *found* rather
   than reported as an open-ended "greater than the last rung".
4. Near threshold the startup time constant diverges, so a rung still growing
   when the margin window ends is recorded as *not* oscillating. That biases
   the threshold current up and the margin **down** — the proxy is
   conservative. A row-6 `MET` from it is a lower bound; a row-6 `NOT MET` is
   recorded with the rung's envelope so a reader can see whether it is a
   window artifact. The margin deck therefore runs to 6 ns rather than the
   frequency bench's 5 ns, and evaluates the criterion over its last quarter.
5. The oscillation criterion is an **absolute** amplitude, but this is a
   **current-limited** oscillator whose steady-state amplitude falls roughly
   *with* `I_tail` — so walking the current down walks the amplitude through
   a fixed level before the circuit stops oscillating. The measured ladder
   below shows this happening. It biases the margin **down** as well, in the
   same direction as limit 4. Both bounds erring the same way is deliberate:
   a row-6 `MET` from this proxy can be trusted; a row-6 `NOT MET` has to be
   read against the recorded per-rung envelope before it is believed.

The oscillation criterion per rung is stated, not implied: the envelope's
peak-to-peak over the last quarter of the transient must reach **10 × the
10 mV differential initial condition**. An envelope that merely fails to decay
is not an oscillation.

Row 6 says *"at every bound corner of the row-10 set"*, so `run_pvt_sweep.sh`
runs the margin pass at MOS `{ss,ff,sf,fs}` × MIM `{bcs,wcs}` × HBT
`{bcs,wcs}` × T `{−40,125}` = 32 corners, plus the nominal corner as the
reference. MOS `sf`/`fs` are in that set for the same reason they are in the
main grid: `varactor-characterization` established by reading `cornerMOShv.lib`
that they carry *distinct* `sg13g2_hv_svaricap_{vfbo,toxo,dlq,dwq}` values, so
they are not interior to `ss`/`ff` for the device that does the tuning.
**Those 32 corners have not been run** (see below); what has been measured is
the nominal corner, which establishes that the proxy behaves as its derivation
says it should but grades nothing.

### Row 7: swing and cycle-minimum compliance

Row 7 is ratified by DR-004 (d)/(e) and graded by `osc_emit_row7` /
`osc_row7_summary` in `osc_bench.sh` (issue #112). Nothing here relaxes it.

- **Swing**: `vpp_diff_v` (`v(OUTP) − v(OUTN)` at the tank nodes, no buffer,
  no added load) must be ≥ 0.40 V (stretch ≥ 0.65 V) at **every** expected
  `Vctrl` in `W` = [1.65, 3.30] V — at least 5 window points including both
  endpoints. A window point that did not oscillate (`NOSC`) is a measured
  swing failure.
- **Compliance**: `VCE_max = (VDD + Vpp_diff/4) − V(TAIL)_min ≤ 2.2 V` at
  **every** expected `Vctrl` of the full 0.0–3.3 V domain (DR-004 (e) states
  it per bound corner with no window, and the largest swing sits at 0.0 V,
  outside `W`). Each point uses its **own** quantities: `vdd_v` is the sampled
  maximum of `V(VDD)` over the settled window (the actual rail, so a supply
  sub-corner needs no code change), and `v_tail_min_v` is the **sampled
  instantaneous minimum** of `V(TAIL)` over that window
  (`sim/lib.sh` `osc_trace_extrema`). `v_tail_dc_op_v` and `v_tail_mean_v`
  stay in the CSV but grade nothing — DR-004 names both as stand-ins.
- **Sampling limit, stated with every number.** Both extremes are samples of an
  adaptive-timestep trace: the sampled tail minimum can only read **high** and
  the sampled `vpp_diff` only **low**, and both understate `VCE_max`. Each is
  bounded as `A·(1 − cos(π·f·dt_max))` — the same peak-sampling bound
  `run_method_check.sh` already validates for amplitude — assuming the
  extremum is locally sinusoidal: the tail at `f = max(f_tail, 2·f_osc)` with
  `A` = half its ripple peak-to-peak, the output at `f_osc` with
  `A = vpp_diff/2` per extreme. At the 2 ps ceiling and ~5 GHz these are
  sub-millivolt. Compliance is `MET` only when `vce_max_upper_v` (both bounds
  applied) is ≤ 2.2 V; a measured value under the limit whose upper value is
  not is `WITHIN SAMPLING BOUND` — **not a pass**. An extremum sharper than a
  sinusoid at that `f` (a cusp) can exceed the bound: a stated limit, not a
  guarantee. For swing the error is in the safe direction, so the measured
  `vpp_diff_v` is used directly.
- **Inequality assumptions** (DR-004 (e), not tested here): each tank node
  swings ±`Vpp_diff/4` about `VDD` (rail-centred differential swing; the
  per-point `vpp_cm_over_diff` is the evidence); the pair emitters sit on
  `TAIL` (true in `design/vco.spice`, no degeneration); collector peak and
  tail minimum are combined as if simultaneous (over-states VCE —
  conservative); BVCEO is the base-open rating (conservative). The tail
  device XQ3's own VCE is **not** covered by this inequality.
- **Completeness**: a corner is `INCOMPLETE` (never a pass) when any expected
  `Vctrl` is missing, duplicated, at status `FAIL`/`NODATA`, has an `INVALID`
  measurement (any of the five traces vdiff/vcm/vtail/isup/vdd missing, empty,
  malformed, non-finite or truncated — #83's gate), comes from a pre-#112
  29-column record, or lacks a numeric swing/tail-minimum/rail; or when the
  `Vctrl` list lacks a window endpoint or has fewer than 5 window samples.
- **Aggregation**: `run_pvt_sweep.sh` requires one complete line for every
  row-10 **bound corner** (the same MOS `{ss,ff,sf,fs}` × MIM `{bcs,wcs}` ×
  HBT `{bcs,wcs}` × T `{−40,125}` set as row 6); a missing, duplicated or
  incomplete bound corner leaves row 7 `NOT GRADED`, and non-bound grid
  corners are reported as descriptors that never stand in for a missing one.
  Even a complete pass reads **`STAGE-1 MET`**: DR-004's stage-2 ±10 % supply
  sub-corners are part of row 7's coverage. `run_supply_stage2.sh` grades them
  per rail through the same `osc_emit_row7` and `report_supply_stage2.sh`
  compares them with the matching nominal corner (issue #119); this summary
  refuses a rail-tagged CSV rather than merging the two rails.
- **Rail identity** (issue #119): `osc_emit_row7` takes an optional rail (7th
  argument), exactly like `osc_emit_tuning`. A points CSV with a `vsup_v`
  column requires it and only that rail's rows are graded; a rail-less CSV
  refuses one. The grade line then carries a trailing `vsup_v` column
  (declared by `osc_row7_header` when `OSC_CSV_RAIL=1`). Nominal callers are
  unchanged byte for byte.
- **Records**: per point, columns 30–37 of `records/<id>.csv`
  (`v_tail_min_v, t_tail_min_s, v_tail_pp_v, v_tail_min_err_v,
  vpp_diff_err_v, vdd_v, vce_max_v, vce_max_upper_v`, appended so columns
  1–29 keep their meaning); per corner, `records/<id>-row7.csv`. Records made
  before #112 are unchanged and are not re-graded.
- **Known-answer checks** (PDK-free, in the CI `method-check` job):
  `tests/test_row7.sh` — an asymmetric tail ripple whose minimum differs from
  both its mean and `mean − amplitude`, a coarse-sampled minimum inside its
  stated bound, the exact compliance boundary with and without a sampling
  bound, the actual-rail dependence, insufficient swing, and missing, invalid,
  truncated, duplicated and legacy-layout data; and
  `run_validity_check.sh` — the real `osc_simulate_point` over stubbed traces
  writing the closed-form tail minimum, rail and `VCE_max`.

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

Latest result: **56/56 quantities within their derived tolerance**
(`records/20260926-010713-e391693*`). Worst measured frequency error
3.2 × 10⁻⁴ % (at the 20 ps ceiling; ≤ 1 × 10⁻⁷ % at the 2 ps ceiling the graded
sweep runs at). The 20 ps ceiling's amplitude error is 4.4 %, correctly
predicted by the `1−cos(π·dt·f)` bound.

That check measures the **estimator**. It says nothing about the *circuit
solution's* own discretization error with 32 OSDI varactors and four HBTs in
the loop, so `run_pilot_grid.sh` measures that separately by repeating the
nominal band-centre point at a coarser ceiling — see the results below.

## Restarting the graded sweep (issue #154)

`run_pvt_sweep.sh` with no argument is the unchanged cold start. After an
interrupted run, the completed work can be reused under a **new** record:

```bash
sim/oscillator-core/run_pvt_sweep.sh --resume-from <earlier-record-id>
```

The earlier record is read-only input; it is never reopened for writing. Every
run now writes, for each finished transient point (status `PASS` or `NOSC`
with `meas_status=VALID`), a completion checkpoint `corners/<id>/<point>.ckpt`
(plus the verbatim CSV row `<point>.row`) **after** the netlist, log and row are
final, by temp file and rename. It holds the point identity, the sha256 of the
netlist, log and row, and the run fingerprint: sha256 of the device body,
transient template and the model-input manifest (digests and bundle paths of
the captured bundle), the simulator version, the measurement settings
(`tstep/tstop/tmeas_start/settle`, `.ic`, rail, CSV layout), and the extractor
code (`sim/lib.sh` and `osc_bench.sh` as a whole), closed by `complete=1` and a
digest of the checkpoint itself. A restart imports a point only when all of that
re-verifies against the **current** run; otherwise it prints
`resume: NOT reusing <point> ...: <reason>` and simulates the point normally.
The default is to refuse: file existence or a zero exit status is never taken as
completion, records without checkpoints (everything before #154) are never
reusable, a failed/`NODATA`/`INVALID` point is never checkpointed, and a retained
`NOSC` stays a `NOSC` finding. Because the extractor files are hashed whole, any
edit to `sim/lib.sh` or `osc_bench.sh` makes older checkpoints non-reusable.

Reused artifacts are copied into the new record with their sources named in
`records/<id>-reuse.csv`; the record's `Execution` bullet and the console report
the executed, reused and refused counts separately, and the corner/global
summaries (including the full-grid row-3/row-7 coverage requirement) are
recomputed over the combined rows of the new record.

**Limitation: only completed transient points are reused.** The row-6 margin
ladders are always re-run in full, because no whole-ladder checkpoint contract
exists. Phase noise and the other runners are unaffected. Scratch traces are
not retained (the scratch workspace is removed on exit); reuse relies on the
retained CSV, netlist and log only. The fault-injection fixtures are
`sim/tests/test-resume-checkpoint.sh` (stub simulator, disposable tree).

## Reproducing it

Three no-argument entry points. The two PDK-dependent ones run their own
preflight (`design/netlist.sh --check`, then `sim/tools/build-osdi.sh`), so
there is no hidden manual step — `sim/README.md` rule 1.

```bash
sim/oscillator-core/run_method_check.sh   # ~1 min, no PDK required
sim/oscillator-core/run_pilot_grid.sh     # ~2 CPU-hours, a DECLARED SUBSET
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

## What has been measured

`run_pilot_grid.sh`, record `20260926-010627-e391693`. **A declared subset of
the corner grid: the typical process corner (`mos_tt` / `cap_typ` /
`hbt_typ`) only**, over the three row-11 temperatures — 13 transients plus a
9-rung margin ladder. It therefore grades **no** spec row: rows 1, 2, 3, 6 and
8 are all stated over the row-10 corner set, and row 6 over every *bound*
corner of it. The numbers below are findings about the circuit, quoted against
the row bounds for orientation.

Every transient point **PASSED** — 13/13 reached a countable oscillation, no
point failed to simulate and no point failed to start.

### `f_osc`, tuning range and the row-1 band

| T (°C) | `f(0.0 V)` | `f(1.65 V)` | `f(3.3 V)` | `f_max/f_min` | geometric centre | row-1 window 4.5–5.5 GHz |
|---|---|---|---|---|---|---|
| −40 | 5.448 GHz | 5.403 GHz | 4.622 GHz | **1.1788** | 5.018 GHz | both endpoints inside |
| 27 | 5.419 GHz | 5.384 GHz | 4.622 GHz | **1.1724** | 5.005 GHz | both endpoints inside |
| 125 | 5.342 GHz | 5.322 GHz | 4.607 GHz | **1.1594** | 4.961 GHz | both endpoints inside |

The 27 °C row is over the six-point `Vctrl` axis `{0.0, 0.6, 1.2, 1.65, 2.4,
3.3}` V; the temperature extremes are over `{0.0, 1.65, 3.3}` V. All three
ratios clear the row-2 bound of 1.15 **at this corner**, with the worst
(125 °C, 1.1594) sitting 0.8 % above it against a measured quantization floor
of 0.092 % — comfortably outside the floor, but by less than one part in a
hundred, which is exactly the kind of margin the MIM's ±10 % process spread
could eat. The stretch bound of 1.20 is **not** met anywhere measured.

### `Kvco` is strongly non-linear, and all of the tuning is at the top of the domain

At 27 °C the per-segment first differences are

| `Vctrl` segment | 0.0–0.6 | 0.6–1.2 | 1.2–1.65 | 1.65–2.4 | 2.4–3.3 |
|---|---|---|---|---|---|
| `Kvco` (MHz/V) | +1.0 | −2.8 | −73.9 | −247.4 | −640.4 |

— a linearity figure (peak-to-peak slope spread over mean slope) of **333 %**.
Below ~1.2 V the oscillator is essentially untuned; the entire 17 % range is
delivered between 1.2 V and 3.3 V.

That is a property of how `design/vco.sch` biases the varactor, not a
measurement artifact. The netlist ties both `sg13_hv_svaricap` gates to
`VCTRL` and both wells to the tank node (`XCVP1 VCTRL OUTP VCTRL OUTP …`,
against the PDK's `.subckt sg13_hv_svaricap G1 W G2 bn`), so the device sees
`V_GW = Vctrl − V(OUT)_dc`, which sweeps **−3.3 V … 0 V** as `Vctrl` goes
0 → 3.3 V. An accumulation-mode varactor's steep C–V region sits near
`V_GW ≈ 0`, so the whole domain below ~1.2 V is flat depletion-side
capacitance. This is evidence *for* row 3 (OPEN), not a verdict on it — and it
is a concrete note for whoever runs the graded grid: the declared 10-point
`Vctrl` axis spends six of its points in the flat region and only four where
`Kvco` actually moves.

### Start-up

All 13 points established oscillation from the 10 mV differential `.ic`; no
point recorded `NOSC`, and no point recorded `t_settle_s = nan` (the value
`osc_settle` returns when the envelope never reaches 90 % of its final
amplitude and stays there). Measured 90 %-envelope settling time across the
pilot: **0.487 ns … 1.256 ns**, fastest at −40 °C / 3.3 V, slowest at 27 °C.
The bench discards 2.5 ns, i.e. **2.0× the slowest settling observed**, before
it measures anything.

### Differential-mode check

Across all 13 points:

- `f(TAIL)/f_osc` = **2.0002 … 2.0005**
- `f(VCM)/f_osc` = **1.9979 … 2.0013**
- worst `Vpp(VCM)/Vpp(VDIFF)` = **1.06 %** (at −40 °C, `Vctrl` = 3.3 V)

The tank is pumping the fundamental entirely into the differential mode and
leaving the common mode and the tail node with the 2f component two
half-circuits in phase produce. No fundamental appears in the common mode at
any measured point, so every frequency, tuning and power number above is a
measurement of one differential oscillator rather than of two independently
resonating branches.

### Supply current and power — both numbers, distinguished

At `Vctrl` = 1.65 V:

| T (°C) | DC operating point | large-signal (settled window) |
|---|---|---|
| −40 | 0.9892 mW (299.8 µA) | 0.9897 mW |
| 27 | 1.0115 mW (306.5 µA) | 1.0119 mW |
| 125 | 1.0475 mW (317.4 µA) | 1.0479 mW |

Against a row-8 bound of 10 mW this is an order of magnitude under, at this
corner. The two numbers nearly coincide here because the tail current source
holds the core current essentially constant between the quiescent and the
switching state — that is a *result*, not a licence to conflate them: they
stay in separate CSV columns, and a topology whose average current moved under
large signal would be reported as such.

### Timestep convergence of the circuit solution

Repeating the 27 °C / 1.65 V point at a 5 ps ceiling instead of 2 ps moves
`f_osc` by **−0.192 %**, `Vpp(VDIFF)` by **+0.209 %** and large-signal core
power by **−0.004 %**. That is the *solver's* discretization error, which the
extractor known-answer check cannot see. It is also the reason the bench does
not run at 5 ps — and, separately, there would be nothing to gain if it did:
coarsening the ceiling was measured to produce no speedup at all (see below).

### Row-6 startup margin, nominal corner only

The tail-current ladder at `mos_tt` / `cap_typ` / `hbt_typ`, 27 °C,
`Vctrl` = 1.65 V. `I_tail` is **measured** at every rung from `V(TE)/R(RTE)`,
never inferred from the RREF multiplier — and the two diverge immediately,
which is the point of measuring it:

| RREF rung | measured `I_tail` | `I_nom/I_tail` | `Vpp(VDIFF)` over 4.5–6 ns | `f` over that window | oscillates? |
|---|---|---|---|---|---|
| ×1 (nominal) | 204.2 µA | 1.00 | 1.086 V | 5.384 GHz | yes |
| ×2 | 111.4 µA | 1.83 | 590 mV | 5.386 GHz | yes |
| ×3 | 76.4 µA | 2.67 | 397 mV | 5.377 GHz | yes |
| ×4 | 58.1 µA | 3.51 | 292 mV | 5.369 GHz | yes |
| ×6 | 39.2 µA | 5.21 | 174 mV | 5.355 GHz | yes |
| ×8 | 29.5 µA | 6.93 | 107 mV | 5.347 GHz | yes |
| ×12 | 19.7 µA | 10.39 | 44.8 mV | 5.347 GHz | no |
| ×16 | 14.7 µA | 13.88 | 24.2 mV | 5.350 GHz | no |
| ×24 | 9.76 µA | 20.92 | 11.7 mV | 5.354 GHz | no |

**Reported margin: the bracket [6.93, 10.39] against the row-6 bound of 3.0 —
`MET` at this corner**, as a *lower* bound (see limit 4 above, and limit 5
below). One corner is not row 6, which is stated at every bound corner of the
row-10 set.

Two things in that table are worth reading rather than skipping:

1. **The measured current does not track `1/RREF`.** At ×8 the current ratio
   is 6.93, not 8. Limit 1 above is why the ladder measures `I_tail` instead
   of assuming it — had the margin been computed from the multiplier it would
   have been overstated by ~15 % at that rung.
2. **The declared criterion is conservative, and the ladder shows by how
   much.** The criterion is an absolute amplitude — 10 × the 10 mV
   differential `.ic`. But this is a current-limited oscillator: its
   steady-state amplitude falls roughly *with* `I_tail`, so as the ladder
   walks the current down, the amplitude crosses a fixed 100 mV level well
   before the circuit stops oscillating. At ×24 the tank is still ringing
   coherently at 5.354 GHz with 11.7 mV — larger than the 10 mV perturbation
   it started from, i.e. not decaying — so the *true* threshold current is
   lower than the bracket's lower end and the *true* margin is higher than
   20. The bench reports the bracket its declared criterion produces and
   records `vpp_diff_late_v` and `f_late_hz` per rung so a reader can apply a
   different criterion to the same evidence without re-simulating. This is
   limit 5 in `testbench/tb_vco_core_margin.spice.tmpl`'s header.

## The graded grid is a fleet job, and it did not run here

`run_pvt_sweep.sh` declares MOS `{tt,ss,ff,sf,fs}` × MIM
`{cap_typ,cap_bcs,cap_wcs}` × HBT `{hbt_typ,hbt_bcs,hbt_wcs}` × T
`{−40,27,125} °C` = **135 PVT points**, × a 10-point `Vctrl` axis = **1350
transients**, plus 33 × 9 = **297 margin transients**.

Measured on the dispatch host (ngspice-46, one core, the 2 ps ceiling): this
netlist simulates at roughly **13 ps of circuit time per wall-clock second** —
32 OSDI varactor instances, four HBTs and two EM-fitted inductor ladders, all
stiff. A 2 ns transient took **169 s**, so one 5 ns point is ~6.5 CPU-minutes
and the declared grid is **~180 CPU-hours**. The script prints its own point
count and a cost estimate *derived* from that measured rate constant and its
declared axes, and every point writes its frozen netlist, raw log and CSV row
as it completes, so an interrupted run leaves usable partial evidence rather
than nothing.

**Three ways to make it cheaper were measured, not assumed. Two worked:**

| Lever | Result |
|---|---|
| Shorten the transient, 20 ns → 5 ns, with the window derived from the **measured** 0.883 ns settling time | ~4× — **taken** |
| Name the `save` set instead of `save all` | ~10 % (169 s → 153 s on the same 2 ns transient), bit-identical extracted `f_osc` and `Vpp` — **taken** |
| Coarsen the timestep ceiling, 2 ps → 5 ps | **no speedup at all**: 169 s vs 183 s. The cost is the Newton iterations per accepted point, not the number of accepted points. **Rejected** — it would buy only discretization error |

180 CPU-hours is what is left after both of the levers that worked.

**That grid was not run in this PR.** The host these agents run on is a shared
dispatch worker whose operating rules send any multi-corner SPICE grid to a
batch fleet via `klt sim`, and `klt sim` cannot express this deck: it has no way
to load the Verilog-A/OSDI varactor model, no way to set the `ngbehavior=hsa`
compatibility mode the PDK's model cards need, and
`remote_launcher.SUPPORTED_PDKS` is `("sky130A", "gf180mcu")` — the off-host
backends have no `ihp-sg13g2` image. All of that is **reproduced rather than
asserted** in [`klt-sim/`](klt-sim/), together with the request document to
submit once it closes, and filed upstream as
[2AMLogic/klayout-tools#2511](https://github.com/2AMLogic/klayout-tools/issues/2511)
under this repo's friction protocol. Running the grid is tracked as **#50**.

## What is here

```
oscillator-core/
  README.md                this file
  .spiceinit               ngbehavior=hsa, copied into every run's scratch dir
  osc_bench.sh             experiment-local shared driver (sourced, not run)
  run_pvt_sweep.sh         the graded row-10/11 grid + the row-6 margin pass
  run_pilot_grid.sh        the declared SUBSET that has actually been measured
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

### Tuning curves are graded only when `Vctrl` coverage is complete

`osc_emit_tuning` takes the expected `Vctrl` list as a required sixth
argument. A curve is graded (`row1`/`row2`/`row2_stretch`) only if every
expected voltage has exactly one row at the selected `tmax` and that row is
`PASS`. Otherwise those three columns read `INCOMPLETE`, `n_points` is the
number of surviving `PASS` points, linearity is `nan`, and `Kvco` is written
only for segments between voltages adjacent in the expected list (never a
slope across a gap). Fewer than two `PASS` points stays `INSUFFICIENT`. The
column layout is unchanged and a complete curve's output is byte-identical to
the earlier behaviour. The pilot passes its own sets (`PILOT_VCTRL`,
`PILOT_VCTRL_EDGE`) and remains ungraded. Records written before this change
are historical evidence and are not rewritten. PDK-free check:
`tests/test_emit_tuning.sh`.

## Records

| Record | What it is |
|---|---|
| `records/20260926-002254-9c26531*` and `records/20260926-010713-e391693*` from `run_method_check.sh` | the extractor validation, 56/56 quantities within their derived tolerances at both tree states. Grades no spec row and says nothing about `design/vco.sch`. |
| `records/20260926-010627-e391693*` from `run_pilot_grid.sh` | the measured pilot subset above: the typical process corner over the three row-11 temperatures, the timestep-convergence delta, and the nominal-corner row-6 margin ladder. **Grades no spec row** — one process corner is not row 10's PVT set, and one margin corner is not row 6's "every bound corner". |

## What this does **not** show

- **No graded PVT verdict.** The row 1 / 2 / 3 / 6 / 8 verdicts this bench is
  built to produce require `run_pvt_sweep.sh` to have run over the row-10/11
  grid. It has not (#50). Everything measured here is at the **typical**
  process corner: **whether the sizing still lands in the row-1 band at
  `mos_ss`/`cap_wcs`/`hbt_wcs`, whether row 2's 1.15 ratio survives the MIM's
  ±10 % process spread, and whether the row-6 margin holds at the bound
  corners are all unmeasured**, and this directory says so rather than
  implying otherwise.
- **No phase noise.** Row 4 is not graded here, and not because it is
  inconvenient: `CLAUDE.md` requires every phase-noise number to carry its
  transient length, window, estimator (or ISF derivation), variance and known
  limits, which is a method-design problem of its own size — and one that needs
  a working transient oscillator bench to build on. That is what this is. The
  phase-noise bench is #49.
- **No frequency here is a PDK-model result.** The PDK ships **no
  spiral-inductor ngspice model** (`sim/pdk.json` →
  `known_model_gaps.spiral_inductor`). Both tank inductors come from this
  repo's own EM-fitted `sim/inductor-model/sg13g2_inductor_em.spice`, named by
  path *and content sha256* in every record. **Every frequency in this tree
  inherits that model's stated error bars** — see
  [`../inductor-model/README.md`](../inductor-model/README.md), which is
  explicit that the EM fit is authoritative only for the three LVS-testcase
  geometries and that its analytic predecessor's SRF was 50–77 % optimistic.
- **This ratifies no `spec/target-spec.md` row**, including row 3, whose
  evidence it supplies. Ratification is a `spec/decision-records/` PR.
- **No layout, DRC, LVS or post-layout anything.** Later in the sequence.

## DR-004 stage 2: supply sub-corners (issue #113)

`spec/decision-records/DR-004-target-spec-ratification-pass-2.md` activates 18
supply sub-corners on top of the nominal-rail stage-1 grid:
`{2.970, 3.630} V x {SLOW, TYP, FAST} x {-40, 27, 125} C`, with the process
vertices *aggregate* (SLOW = `ss`/`hbt_wcs`/`cap_wcs`, TYP =
`tt`/`hbt_typ`/`cap_typ`, FAST = `ff`/`hbt_bcs`/`cap_bcs`), reporting rows
1/4/6/7/8. `run_pvt_sweep.sh` is unchanged and remains stage 1.

| File | Role |
|---|---|
| `supply_stage2.sh` | PDK-free definition: the 18 points, mappings, the margin-pass subset, and the escalation rule `s2_status` |
| `run_supply_stage2.sh` | rows 1/6/7/8 driver (`--list`/`--check` need no PDK; a real run is a ~27 CPU-hour fleet job -- **not for a shared dispatch host**) |
| `../phase-noise/run_supply_stage2.sh` | row 4: the existing ISF pilot per sub-corner via `PILOT_*` overrides (~14 CPU-hours) |
| `report_supply_stage2.sh` | PDK-free report: per-point row results, comparison with the matching stage-1 margin, `ESCALATION_REQUIRED` / `NO_ESCALATION` / `INSUFFICIENT`; row 7 as two separate comparisons (swing, compliance) |
| `tests/test_supply_stage2.sh` | CI check (`method-check.yml`): enumeration, rails in decks, nominal reproducibility, rail identity, fixtures |

**Rail parameterization.** `osc_bench.sh`'s `OSC_VSUP_V` (empty = nominal
3.3 V) is applied in exactly one place, `osc_render`, which rewrites the device
section's single `VSUP` line, the `Bvcm` common-mode offset and the startup
`.ic` (centred on the rail, same 10 mV perturbation); core power is current x
that rail. At the nominal rail decks are byte-identical to before. Stage-2 CSVs
gain a trailing `vsup_v` column (`OSC_CSV_RAIL=1`), point ids contain the rail,
and `osc_emit_tuning` and `osc_emit_row7` *require* the rail for a rail-tagged
CSV, so a curve or a row-7 grade can never be aggregated across rails.

**Escalation rule** (DR-004 stage 3). Margins are positive inside a bound.
Escalate when `|m2 - m1| > m1` (DR-004's "moves ... by more than the margin
stage 1 left", read literally; equality does not escalate), or, when stage 1 left no
margin (`m1 <= 0`), when stage 2 is worse. Escalation routes to a superseding
decision record; nothing here edits `spec/` or launches the 405-point cross.
The overall status is `NO_ESCALATION` only when every required (row, point) was
compared, so a missing baseline, an invalid/incomplete point or differing
design/model provenance reads `INSUFFICIENT_EVIDENCE`, never a pass.

**Row 7** (issue #119). `run_supply_stage2.sh` writes `records/<id>-row7.csv`:
one grade line per (sub-corner, rail) from `osc_emit_row7`, the issue-#112
grader stage 1 uses, unchanged. The report reads it (and the stage-1 record's
`-row7.csv`) and makes **two separate comparisons per point**, each with the
`s2_status` rule against the matching nominal process/temperature grade:

| Metric | Margin (V, positive = inside) |
|---|---|
| `row7_swing_margin_min_window_vpp` | min `Vpp_diff` over the complete window `[1.65, 3.30]` V − 0.40 V (a `NOSC` window point counts as 0 V of sustained swing) |
| `row7_compliance_margin_vce_upper` | 2.2 V − the conservative `VCE_max` over the full `Vctrl` domain (its sampling-bound upper value) |

Target (0.40 V) and stretch (0.65 V) swing verdicts and the compliance verdict
travel in the value columns and are counted in the markdown; the escalation
status uses the margins. **Insufficient, never a margin**: a grade that is
`INCOMPLETE` (missing/duplicated/unexpected `Vctrl`, `INVALID` waveform, legacy
29-column point rows), compliance `WITHIN SAMPLING BOUND` (the measured value
is under 2.2 V, its sampling bound is not), a missing or duplicated grade line,
a record without a `-row7.csv` (legacy baselines are not upgraded by
assumption), an unrecognised row-7 header, a stage-2 grade without its rail,
a grade whose verdict contradicts its value, or differing provenance. The
sampling bound assumes a locally sinusoidal waveform; a sharper cusp can hide
more (stated in the report). The overall status can read `NO_ESCALATION` only
when every row, including both row-7 metrics at all 18 points, was compared.

```
sim/oscillator-core/run_supply_stage2.sh --list     # the 18 points, no PDK
sim/oscillator-core/report_supply_stage2.sh --stage2-osc records/<s2-id> \
    --baseline-osc records/<stage1-id> [--stage2-pn ...] [--baseline-pn ...] --out records/<new-id>
```
