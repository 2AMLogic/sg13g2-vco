# `phase-noise/` — `L(Δf)` for `design/vco.sch` by a measured ISF, with its variance and its limits

The second half of the oscillator bench. [`oscillator-core/`](../oscillator-core/)
measures what the circuit *does* — start-up, `f_osc`, tuning, power, the row-6
margin — and deliberately leaves `spec/target-spec.md` **row 4** ungraded.
This directory is row 4: the one number in the table whose own condition column
says it **must state its measurement method**, and whose estimator choice that
column calls "an explicit open item of the phase-noise testbench issue."

Issue #49. Depends on #47 (`oscillator-core/`, merged as PR #51), whose
extractors, settling-time measurement, device-section derivation and cost model
this bench is built directly on top of.

**Read this first.** The estimator is shipped, known-answer checked against
closed-form algebra, and run against the real netlist — but at **one declared
corner**, so it **grades no `spec/target-spec.md` row**. The graded row-10/11
grid is a fleet job that could not be routed off-host; see "The graded grid is
a fleet job" below.

---

## The estimator, and why it is this one

`CLAUDE.md`: *"ngspice has no PSS/pnoise. Every phase-noise number states how
it was produced (transient length, window, estimator — or ISF derivation), its
variance, and the method's known limits."* The choice below is made in the
open, against the alternatives, with the compute cost of each stated — because
on this netlist the cost **is** part of the argument.

### Why not a periodogram: the fact that decides it

**ngspice's transient analysis runs with device noise sources switched off.**
There is no `.tran` noise model for the HBTs, the MOS varactors, or the
resistors in the tank; the only stochastic sources ngspice offers in a
transient are the `trnoise()` / `trrandom()` generators on *independent*
sources, and `design/vco.sch` contains none.

A transient of this deck is therefore **deterministic**. Re-run it and you get
a bit-identical trace. That is not a small caveat about a spectral method — it
is disqualifying for the whole family of them, at any transient length:

> A periodogram of this deck's own tank voltage, or a period-jitter extraction
> from it, measures the **solver's truncation error**. It does not measure the
> circuit's phase noise, because there is no circuit noise in the simulation to
> measure.

This bench demonstrates rather than asserts that: the reference run and the
perturbed run are the *same deck* with the impulse amplitude set to zero, so
they take identical timesteps until the first impulse and their crossing-time
difference over that stretch is **exactly 0.000 s** (recorded per realisation
as `null_floor_s`, and checked in `run_method_check.sh` as `null_floor`). A
deterministic simulator has no jitter to find.

### The four candidates, costed

The cost model is `oscillator-core`'s measured rate constant for this netlist:
**~13 ps of circuit time per wall-clock second on one core** at the 2 ps
timestep ceiling, and coarsening the ceiling was measured *not* to help (169 s
at 2 ps vs 183 s at 5 ps for the same 2 ns transient — the cost is Newton
iterations per accepted point, not the count of accepted points).

| Candidate | What it needs | Cost per corner | Disposition |
|---|---|---|---|
| **Windowed periodogram / Welch of the tank voltage** | ≳ 1 µs of transient to put a resolution bin at the 1 MHz offset at all; ~30 averaged segments to bring a single periodogram bin's **5.57 dB** standard deviation down to ±1 dB | **~640 CPU-hours** (30 × 21 h) | **Rejected.** It would cost ~530× the chosen method *and measure nothing physical* — see above. Close-in offsets would additionally be contaminated by the carrier's own drift. |
| **Zero-crossing / period-jitter extraction, converted to `L(Δf)`** | the same long record (jitter must accumulate over ≳ 1/Δf), plus an assumed noise shape for the conversion | ~21 CPU-hours per realisation | **Rejected**, for the same disqualifying reason. It is tempting because it reuses `sim/lib.sh`'s already-validated interpolated crossing extractor — but a validated extractor applied to a noiseless waveform returns a validated zero. |
| **Inject `trnoise()` current sources of a `.noise`-derived PSD, then periodogram** | a `.noise` analysis to get the PSD (the same one the ISF route needs), *plus* the µs transient, *plus* the ~30 realisations | **~640 CPU-hours** | **Rejected.** It adds no information the ISF route does not already have — the noise PSD is the same input — and pays ~530× more for a χ²-distributed estimate of it. ngspice's `trnoise` is also a piecewise-constant generator whose PSD is only flat well below `1/(2·NT)`, so its band would itself need justifying. |
| **ISF (Hajimiri–Lee), measured by impulse response** | one reference transient plus one transient per realisation, each a few tens of carrier periods; one small-signal `noise` analysis per port | **~1.2 CPU-hours** | **Chosen.** Its cost is independent of the offset frequency it reports at, because it never estimates a spectrum. It is also the frame `CLAUDE.md` names as canonical. |

The decisive property of the ISF route under this repo's compute constraint:
**`L(Δf)` comes out of a closed-form kernel, not out of a frequency bin, so
reporting at a 1 MHz offset costs exactly what reporting at a 100 MHz offset
costs.** The transient length is set by how long the oscillator takes to forget
an amplitude perturbation (a few periods), not by `1/Δf`.

What the choice gives up is stated honestly in "What this does **not** show".

---

## The method, in full

Every record restates this, so a record is readable without this file.

### 1. What is measured

For a charge impulse of `dq` coulombs injected into a port at carrier phase
`φ`, the oscillator acquires a **permanent** excess phase `dφ`. The
**unnormalised impulse sensitivity function** is

```
Gq(φ)  =  dφ / dq          [rad / coulomb]
```

and the 1/f²-region phase noise from a one-sided equivalent noise-current PSD
`S_i` [A²/Hz] entering that port is

```
L(Δf)  =  Gq_rms² · S_i / ( 2 · (2π·Δf)² )
```

with `Gq_rms² = (1/2π) ∮ Gq(φ)² dφ`.

**`q_max` is never measured, on purpose.** The conventional dimensionless ISF
is `Γ = Gq · q_max`, with `q_max = C_node · V_swing`; `q_max` then cancels out
of the kernel. Measuring it separately on a tank loaded by 32 `sg13_hv_svaricap`
instances, two EM-fitted inductor ladders and a MIM would have introduced an
error bar larger than the ISF's own, to produce a number that cancels.

### 2. The kernel's factor of two is named, not assumed

The form above counts noise folding down to the offset from **both** `ω₀+Δω`
and `ω₀−Δω`; those are independent, so their powers add. Hajimiri & Lee's 1998
paper (eq. 14) as literally written substitutes a noise band at the upper
sideband only and is therefore **3 dB lower**. This is a real and documented
ambiguity in the literature, not an arithmetic slip, and `sim/lib.sh`'s
`pn_l_dbc` prints **both** numbers.

This repo quotes the both-sideband form, for two stated reasons:

1. it reproduces **Leeson's linear-tank kernel exactly** for an ideal LC
   (`Γ = cos`, `Gq_rms = 1/(√2·C·A)`, `S_i = 4kTG`; both reduce to
   `kTG/(C²A²Δω²)`), which is an independent derivation — and
   `run_method_check.sh` verifies that identity *numerically*, end to end,
   as check KA-4;
2. it is the more pessimistic of the two, and row 4 is a maximum.

### 3. The impulse train — one transient, many phases

A single transient carries a train of `N` triangular charge impulses spaced
`(n + 1/N)` carrier periods apart at a declared nominal carrier frequency.

- The **fractional** part walks the carrier phase by `T₀/N` per impulse, so one
  run samples the whole ISF instead of one point of it.
- The **integer** part is what separates the impulses in time, so the amplitude
  perturbation each one also excites has decayed before the next arrives.
- The nominal carrier is a **grid-design parameter only** (taken from
  `oscillator-core`'s measured 5.384 GHz at this same corner, record
  `20260926-010627-e391693`). The phase at which each impulse *actually* landed
  is measured from the run's own crossing times, so a carrier off that nominal
  degrades the uniformity of the phase grid — recorded per realisation as
  `max_phase_gap_rad` — and changes no measured quantity.
- A **triangular** pulse rather than a rectangular one: its injected charge
  (`amp · half-width`) and its centroid are both exact under trapezoidal
  integration once the solver takes the PWL's breakpoints, so neither depends
  on the timestep. Its cost is that it is not a delta; it attenuates the ISF's
  n-th harmonic by about `1 − (n·π·w/T₀)²/6`, which is the `width` term in the
  method check's derived tolerance and is < 0.1 % at the widths used.

### 4. The reference run is the same deck with zero-amplitude impulses

Both PWL sources are present in **every** deck this bench generates, with the
same breakpoint times; only their amplitudes change. Because PWL breakpoints
enter the timestep schedule whatever the values are, the reference and the
perturbed run take **identical timesteps** until the first non-zero impulse.

Two things follow, and both are load-bearing:

- the crossing-time difference before the first impulse is an **exact null**,
  and its residual is this method's own noise floor — measured, not asserted,
  and recorded per realisation as `null_floor_s`;
- after the first impulse the two runs' step sequences diverge only because of
  the genuine perturbation. A reference run *without* the PWL sources would
  have had a different schedule from the start and would have mixed the
  solver's own step-sequence divergence into every measured step.

The crossing threshold is likewise **one** value — the reference run's
trapezoidal time average over the measurement window — applied to both runs. A
per-run mean would fold any DC shift the perturbation caused into the very
crossing times being measured.

### 5. The plateau, and why the step is not read immediately

An impulse excites both a phase step and an amplitude transient. Only the phase
step is permanent, so `dφ` is read off a **plateau** taken over the last
fraction of each inter-impulse interval, with the amplitude transient excluded
by construction rather than assumed absent. The plateau's own **ripple** is
recorded per impulse, so an amplitude transient that had *not* decayed appears
in the evidence instead of biasing a step silently.

Crossings are matched between the two runs by **nearest time**, not by index,
and any crossing whose partner is further than a quarter period away is counted
(`n_crossings_unmatched`) rather than used.

### 6. The noise side

`S_i` comes from ngspice's small-signal `noise` analysis with a unit AC current
probe **across the port** and the port voltage as the output. The gain is then
`Z_port`, so ngspice's input-referred `inoise_spectrum` is exactly the port's
Norton-equivalent noise current density — a ratio in which `Z_port` cancels, so
it stays well conditioned even where `Z_port` is large or (as at an
oscillator's unstable equilibrium) has a negative real part. That referral is
checked against `sqrt(4kT/R)` on a bare `R‖C` port in `run_method_check.sh`
(KA-3).

It is read over a **band**, not at a point, and the band spread is recorded, so
a referral that was ill conditioned somewhere is visible rather than hidden
inside a scalar.

**Its limit is the largest one this bench carries** and is restated in every
record: `noise` is a small-signal analysis about the **DC operating point**,
which for an oscillator is its *unstable equilibrium* — each device of the
cross-coupled pair carrying half the tail current continuously. The running
oscillator's noise sources are cyclostationary. This bench does not correct
that; it states it.

---

## What the variance here is, and what it is not

Row 4's condition column and `CLAUDE.md` both require the number to carry its
variance. **This estimator has no random input**, so the variance it reports is
not, and is not presented as, a Monte Carlo variance over noise realisations.
Saying "±0.0 dB, the method is deterministic" would be true and useless.

What the records report instead is the spread over **independent
determinations of the same quantity under varied nuisance parameters**: the
same `Gq_rms` and the same `L(Δf)`, re-measured with

- **both signs** of the injected charge, which cancels any even-order term in
  the phase response (a first-order ISF is odd in `dq`); and
- **two magnitudes** of it, which is the linearity test the entire first-order
  ISF assumption stands on. The spread between magnitudes is reported
  separately as `isf_linearity_spread_pct`, because it is the one that would
  indicate the impulse was too large rather than that the estimate is noisy.

The sample standard deviation across that ensemble is what appears as the `±`
on every `L(Δf)` this directory reports. Two things it does **not** cover, and
which the record says it does not cover: the systematic error of the
DC-operating-point noise assumption (§6 above), and corner spread (there is
one corner).

For contrast, and as part of the estimator justification: a **single**
periodogram bin is χ²₂-distributed, i.e. carries a **5.57 dB** standard
deviation in dB terms, needing ~31 independent averages to reach ±1 dB. That
is a property of the estimator, not of the circuit, and it is the reason the
periodogram route's cost in the table above is multiplied by 30.

---

## The extractors are checked, not trusted

A broken phase-noise estimator does not announce itself: a wrong sign, a
plateau read before the amplitude transient decayed, a factor of two in the
kernel, or an ISF sampled too coarsely all produce a perfectly plausible
`L(Δf)` in dBc/Hz. `run_method_check.sh` therefore measures the estimator
against algebra, on synthetic oscillators, with **no PDK install**:

| Check | What it compares | Closed form |
|---|---|---|
| **KA-1** `isf_highq` | the measured ISF of a high-Q limit-cycle LC oscillator, at every sampled phase and as `Gq_rms` | `Gq(φ) = cos(φ)/(C·A)`, from the phase-plane geometry of an LC resonator (derived in the testbench header). Includes the **falsification case**: at `φ = π/2` and `3π/2` the ISF is exactly zero, so a purely-amplitude perturbation must move the phase by *nothing*. An estimator reporting a phase shift there would be reporting amplitude noise as phase noise. |
| **KA-2** `isf_fastamp` | the same, on an oscillator whose amplitude relaxes as fast as `design/vco.sch`'s | the same closed form, to `O(ε)` with `ε = (Gn−G)/(ω₀C)` — so this case carries a looser, *derived* tolerance. Its job is to stress the plateau extraction, not to be tight. |
| **KA-3** `portnoise` | ngspice's input-referred `noise` output on a bare `R‖C` port | `sqrt(4kT/R)` exactly, frequency-independent. The capacitor is in the deck precisely so `Z_port` is *not* flat: a deck with constant `Z_port` could not distinguish a correct input-referral from a scaled output-noise reading. |
| **KA-4** `kernel` | the **whole pipeline**: measured `Gq_rms` and measured `S_i` from the same deck, through `pn_l_dbc` | Leeson's linear-tank kernel `kTG/(C²A²Δω²)`, derived without reference to the ISF formalism, so agreement is not circular. This is also what settles the kernel's factor of two. |

**The tolerances are derived, not chosen.** Each is the sum of closed-form
bounds on named error terms times a stated ×1.5 headroom, and each row names
its terms in a `tol_basis` column: `eps` (the closed form is exact only as
`ε → 0`), `interp` (`ω₀dt²/8` relative to the crossing-time step actually being
measured), `2nd` (`dq/2q_max`, the second-order phase response a finite impulse
carries), `width` (a triangular impulse is not a delta).

A lossless resonator is deliberately **not** one of the cases, even though its
ISF is exactly closed-form: it has no limit cycle, so each impulse's amplitude
component is never restored and an impulse *train* walks `q_max = C·A` as it
goes — the closed form would drift underneath the measurement. Both cases used
are genuine limit cycles.

Latest result: **42/42 checked quantities within their derived tolerance**
(`records/20260926-071150-7a02483*`). `Gq_rms` recovered to **+0.06 %** on the
high-Q case against a 4.36 % derived tolerance; the null floor came back
**exactly 0.0 s**; KA-4 agreed with the independently-derived Leeson kernel to
**0.005 dB**.

---

## Reproducing it

Two no-argument entry points. The PDK-dependent one runs its own preflight
(`design/netlist.sh --check`, then `sim/tools/build-osdi.sh`), so there is no
hidden manual step — `sim/README.md` rule 1.

```bash
sim/phase-noise/run_method_check.sh   # ~1 min, NO PDK required
sim/phase-noise/run_isf_pilot.sh      # ~1.2 CPU-hours, ONE declared corner
```

If the PDK is not under one of the prefixes `sim/env.sh` probes:

```bash
export PDK_ROOT=/path/to/ihp-open-pdk PDK=ihp-sg13g2
```

`pn_bench.sh` next to them is experiment-local shared code, sourced by
`run_isf_pilot.sh`; it is not an entry point and has no shebang. The genuinely
reusable extractors live in [`sim/lib.sh`](../lib.sh) instead, because
`run_method_check.sh` has to validate *the same* functions the measured run
grades with — a private copy would be a copy the method check does not check.

**`pn_bench.sh` sources `sim/oscillator-core/osc_bench.sh` on purpose.** This
experiment measures the same netlist as that one, so it reuses that file's PDK
preflight, `design/vco.spice` device-section derivation and template rendering
verbatim rather than reimplementing them. That is a correctness property, not
just less code: a phase-noise number and a frequency number that claim to be
about the same circuit are only about the same circuit if they came from the
same derived device section, by the same code, behind the same netlist-freshness
gate. The visible consequence is that a phase-noise run prints
`oscillator-core: ...` preflight lines; they are accurate and are left as they
are so the reuse is visible in the log.

---

## What has been measured

`run_isf_pilot.sh`, record `20260926-071903-7a02483`. **One declared corner**:
`mos_tt` / `cap_typ` / `hbt_typ`, 27 °C, `Vctrl` = 1.65 V (band centre),
`V_DD` = 3.3 V. Six transients of 9.258 ns plus two small-signal noise
analyses, 2870 s of wall clock in total. **It therefore grades no spec row** —
row 4 is stated over the row-10/11 corner set and this is one of its 135
points. The numbers below are findings about the circuit, quoted against the
row-4 bounds for orientation.

The carrier reproduced `oscillator-core`'s pilot exactly: `f_osc` =
**5.38425 GHz**, `Vpp(VDIFF)` = **1.0868 V**, which is the same netlist
measured by a different bench through a different code path.

### The headline

| Offset | Measured `L(Δf)` | Row-4 target | Row-4 stretch | Verdict **at this corner** |
|---|---|---|---|---|
| 1 MHz | **−102.28 ± 0.30 dBc/Hz** | ≤ −105 | ≤ −115 | **TARGET NOT MET**, by 2.7 dB |
| 10 MHz | **−122.28 ± 0.30 dBc/Hz** | ≤ −125 | ≤ −135 | **TARGET NOT MET**, by 2.7 dB |

plus a **≤ ±0.42 dB** systematic bar from the non-PDK inductor model (see
below), and the stated method limits, which are **not** folded into the ±.

**This is a recorded result, not a problem to tune away.** `CLAUDE.md` forbids
relaxing a ratified row to make a result pass, and nothing in this PR touches
`spec/target-spec.md`. DR-003's basis for row 4 was a Leeson first pass at
≈ −113 dBc/Hz @ 1 MHz with `Q = 7`, `P ≈ 0.2 mW`, `F ≈ 2`, leaving ≈ 8 dB of
margin under the target; the measurement is 10.7 dB adrift of that first pass.
Attributing the gap between tank loss, the pair's noise and the varactor bank
is **not** something this bench measures — it measures the total, referred to
one port.

The 10 MHz row is 20 dB below the 1 MHz row **by construction** (same 1/f²
kernel), not by an independent measurement. See the limits.

### The ingredients

| Quantity | Measured | Note |
|---|---|---|
| `S_i` at the differential tank port | **2.645 × 10⁻²³ A²/Hz** (5.14 pA/√Hz) | 9.3 % peak-to-peak across 3–9 GHz, i.e. the input-referral is flat where it matters. As an equivalent noise conductance that is `S_i/4kT` ≈ **1.60 mS** (627 Ω). |
| `S_i` at the tail node | 5.98 × 10⁻²³ A²/Hz | 56.7 % across the same band — *not* flat, which is itself why the tail port is used only as a sensitivity indicator and not as a primary number. |
| `Gq_rms` at the tank port | **1.330 × 10¹³ ± 0.046 × 10¹³ rad/C** over 4 realisations | ISF fundamental `c1` ≈ 1.85 × 10¹³ rad/C, i.e. an implied `q_max` ≈ 54 fC. |
| `Gq_rms` at the tail node | 4.16 × 10¹² rad/C | **10.1 dB** below the tank port's. |

### What the realisation ensemble actually showed

The declared ensemble was ±4 fC and ±8 fC of injected charge at the tank port.

- The **±4 fC pair agree to 0.19 %** — the sign flip, which cancels any
  even-order term in the phase response, changes essentially nothing.
- The **−8 fC realisation** lands 0.5 % from them.
- The **+8 fC realisation** is the outlier at +7.2 %, **and the estimator's own
  diagnostic says why**: its recorded ISF harmonic content is `c3/c1` = 0.57
  against ≤ 0.05 for the other three, i.e. the response at that charge is no
  longer the first-order one the ISF is defined as. That is exactly the failure
  mode `pn_gamma_stats` records `c1..c3` in order to expose.

The reported ± is the sample standard deviation over the **whole declared
ensemble**, outlier included. Dropping the realisation after seeing it would be
choosing the answer, so it is not dropped — but the reading a user should take
is that the three in-regime realisations agree to **0.55 % peak-to-peak**
(≈ 0.05 dB), and the reported ±0.30 dB is therefore conservative.

The tail-port realisation is a single run: its own reproducibility is *not*
separately determined, and it is used only for the port-assignment indicator
below.

### The port-assignment indicator

The primary number refers the circuit's **whole** Norton-equivalent noise to
the tank port and weights it by the *tank* port's ISF. Noise physically
originating in the tail branch should be weighted by the *tail* port's ISF,
which measured **10.1 dB lower**; carrying the tail port's own measured noise
through its own measured ISF gives **−108.82 dBc/Hz**.

That is an indicator of how much the single-port assumption could matter. It is
**not** a correction and **not** a rigorous bound: the two ports'
input-referred noises are not disjoint contributions, so the two numbers cannot
simply be added or bracketed.

### Method-health evidence from the same run

| Diagnostic | Result |
|---|---|
| `null_floor_s` — pre-impulse crossing-offset residual | **exactly 0.0 s** on all five perturbed runs. The reference-deck construction (§4) holds: the comparison contributes no floor of its own. |
| `n_crossings_unmatched` | **0** on all five runs — no crossing was further than a quarter period from its partner. |
| Phase-grid uniformity | 10 phases per realisation, largest gap 0.71–0.97 rad against an ideal 0.63 rad. The measured carrier sat 0.005 % from the nominal the train was designed around, so the grid is set by the spacing arithmetic, not by carrier error. |
| Measured simulation rate | **11.19 ps of circuit time per wall-clock second** on one (shared, contended) core — consistent with `oscillator-core`'s 13 ps/s and the number the cost table above is built on. |

**One honest weakness in this run's settings**, visible in the recorded CSV and
not papered over: at a 3.1-period impulse spacing with a 0.35 plateau fraction,
most plateaus contain a **single** crossing, so `plateau_ripple_s` is mostly
degenerate (0 by construction at `n_plateau` = 1) and is *not* doing the
amplitude-transient policing it is there to do. What does the policing in this
record instead is indirect: the ISF's agreement with the closed-form cosine
shape, the 0.19 % sign-flip agreement, and the method check's `isf_fastamp`
case, which has a comparable spacing-to-relaxation ratio and recovers the
closed form to 0.62 %. Widening the spacing to put three or four crossings in
each plateau is the obvious next refinement and costs linearly in transient
length.

---

## The graded grid is a fleet job, and it did not run here

Row 4 is stated at a band-centre carrier over the corner set rows 10 and 11
settle: MOS `{tt,ss,ff,sf,fs}` × MIM `{cap_typ,cap_bcs,cap_wcs}` × HBT
`{hbt_typ,hbt_bcs,hbt_wcs}` × T `{−40, +27, +125} °C` = **135 PVT points**.
This directory has measured **one**.

The pilot's own record prints the graded grid's cost derived from that run's
measured rate constant rather than from an assumption. It is of order
**110 CPU-hours** (the pilot's own record printed ~108 from its measured rate) — smaller than `oscillator-core`'s ~180, because the ISF
bench needs six short transients per corner instead of ten long ones plus a
nine-rung ladder, but still far past what a shared dispatch host may run.

`klt sim` cannot route this deck off-host at all: no OSDI device loading, no
`ngbehavior` selection, and `remote_launcher.SUPPORTED_PDKS` is
`("sky130A", "gf180mcu")` with no `ihp-sg13g2` image. That is reproduced rather
than asserted in [`../oscillator-core/klt-sim/`](../oscillator-core/klt-sim/)
and filed upstream as
[2AMLogic/klayout-tools#2511](https://github.com/2AMLogic/klayout-tools/issues/2511)
under this repo's friction protocol.

So this directory does what `oscillator-core/run_pilot_grid.sh` does: it
measures the subset that fits, labels it a subset everywhere it appears, and
**grades no row**.

---

## The non-PDK inductor model's error bars travel with every number here

`sim/README.md` rule 6. The PDK ships **no spiral-inductor ngspice model**
(`sim/pdk.json` → `known_model_gaps.spiral_inductor`), so both tank inductors
come from this repo's own EM-fitted
[`../inductor-model/sg13g2_inductor_em.spice`](../inductor-model/sg13g2_inductor_em.spice),
named by path **and content sha256** in every record.

`design/vco.sch` instantiates `w=8.22 µm`, `s=3.74 µm`, `d=141.975 µm`,
`nr_r=4` — which **is** one of the three geometries the openEMS extraction
actually covered (`p11`), so that geometry's own bars apply rather than an
extrapolation. How each propagates into `L(Δf)`:

| Model bar | Path into `L(Δf)` | Propagated |
|---|---|---|
| ±10 % on the EM-measured `Q` | `L ∝ S_i`, and the tank's loss noise is `4kT·G_p`. If the inductor is the dominant tank loss — the usual case for an LC VCO, and why row 5 is stated on tank `Q` at all — a ±10 % bar on its `Q` is at most a ∓10 % bar on `G_p` | **≤ ±0.41 dB** |
| 0.90 % rms lumped-fit residual on `Zse` over the 0.3–8.008 GHz fit band (which covers the measured carrier) | `L ∝ Gq_rms² ∝ 1/(C·A)²`; a ±0.9 % bar on the modelled reactance is at most ±0.9 % on the resonating `C` | **≤ ±0.08 dB** |
| | **in quadrature** | **≤ ±0.42 dB** |

Both are *upper* bounds: a loss the inductor does not dominate moves `G_p` by
less than its own bar.

Two of that model's stated limits are **not** quantifiable as a dB bar and
therefore do **not** appear in that ±0.42 dB: the EM solve was run at **one
process point and one temperature** (all corner and temperature dependence in
the file is inherited from its analytic predecessor's physics), and **no
measured silicon backs any of it**.

---

## What is here

```
phase-noise/
  README.md                this file
  .spiceinit               ngbehavior=hsa, copied into every run's scratch dir
  pn_bench.sh              experiment-local shared driver (sourced, not run)
  run_isf_pilot.sh         the measured ISF + L(df) at ONE declared corner
  run_method_check.sh      known-answer check of the estimator (no PDK)
  testbench/
    tb_vco_isf_impulse.spice.tmpl        the impulse-train bench on design/vco.sch
    tb_vco_port_noise.spice.tmpl         input-referred S_i at one injection port
    tb_isf_known_answer.spice.tmpl       synthetic oscillators with a closed-form ISF
    tb_portnoise_known_answer.spice.tmpl closed-form check of the noise referral
  netlist-snapshots/<record-id>/   the exact deck simulated, per run
  corners/<record-id>/             the raw ngspice log, per run
  records/<record-id>*.{md,csv}    the append-only evidence
```

Nothing under `records/`, `netlist-snapshots/` or `corners/` is ever edited or
deleted: a re-run mints a new record ID (`sim/README.md`).

---

## Records

| Record | What it is |
|---|---|
| `records/20260926-071150-7a02483*` from `run_method_check.sh` | the estimator validation: 42/42 checked quantities within their derived tolerances, including the end-to-end kernel identity against Leeson. Grades no spec row and says nothing about `design/vco.sch`. |
| `records/20260926-071903-7a02483*` from `run_isf_pilot.sh` | the measured ISF and `L(Δf)` above, at one corner: `L(1 MHz)` = −102.28 ± 0.30 dBc/Hz, **row-4 target NOT MET by 2.7 dB at this corner**. **Grades no spec row** — one process corner at one temperature is not row 10's PVT set. |

---

## What this does **not** show

- **No graded row-4 verdict.** One corner is not the row-10/11 grid. Whether
  the tank's loss, the pair's noise or the varactor bank's `Q` move this number
  at `mos_ss`/`cap_wcs`/`hbt_wcs` or at −40/+125 °C is unmeasured.
- **The noise is taken at the DC operating point, not over the cycle.** The
  single largest stated limit; see §6 of the method. The running oscillator's
  noise sources are cyclostationary and this bench treats them as stationary
  and white at the unstable-equilibrium bias. Correcting it needs the full
  Hajimiri–Lee noise-modulation function, which needs per-device noise
  waveforms over the cycle that ngspice cannot produce.
- **All circuit noise is referred to one port.** The primary number weights the
  whole Norton-equivalent noise by the *tank* port's ISF. Noise physically
  originating in the tail branch should be weighted by the tail port's ISF
  instead. The tail port's ISF is measured, and the record reports the
  difference in dB as an indicator of how much the assumption could matter —
  that is an indicator, **not** a correction and **not** a rigorous bound.
- **Only the 1/f² region.** The kernel used is the white-noise one. The 1/f³
  corner — set by the ISF's DC coefficient `c0` acting on device flicker noise
  — is not evaluated. `c0` *is* recorded per realisation, so the ingredient is
  there; the flicker-noise side is not.
- **The 10 MHz number is not independent evidence.** It comes from the same
  1/f² kernel as the 1 MHz number and is therefore 20 dB below it *by
  construction*, not by measurement. Row 4 states both offsets, so both are
  reported, with this said.
- **No AM-to-PM conversion**, no supply or substrate noise path, and no noise
  from anything outside the netlist (no buffer, no bias filtering, no package).
- **No frequency here is a PDK-model result** — see the inductor-model section
  above.
- **This ratifies no `spec/target-spec.md` row.** Ratification is a
  `spec/decision-records/` PR. Measuring a row is not ratifying it, and a
  number that misses a bound is recorded as a miss rather than tuned away or
  legislated away: `CLAUDE.md` forbids relaxing a ratified row to make a result
  pass.
- **No layout, and therefore no layout parasitics** in any number here.
