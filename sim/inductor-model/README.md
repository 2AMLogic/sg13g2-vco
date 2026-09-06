# sim/inductor-model — an analytic spiral-inductor model for SG13G2

**What this is.** IHP-Open-PDK v0.3.0 ships no ngspice-simulatable spiral
inductor (established by search in [`../tank-characterization/`](../tank-characterization/),
§ "The inductor gap", and recorded as `MODEL_ABSENT` evidence there). This
directory chooses a route to a usable inductor model, implements it, and holds
it to a known answer over a process × temperature grid.

**The route chosen is an analytic model with stated error bars** —
[`sg13g2_inductor_analytic.spice`](sg13g2_inductor_analytic.spice), a
`.subckt inductor la lb sub` with `w`/`s`/`d`/`nr_r` parameters, drop-in for
the instance card the PDK's own xschem symbol and LVS netlists already emit.
Section [Route decision](#route-decision-why-analytic) states why, against the
two alternatives.

> **This is a screening model, not a PDK model and not an EM extraction.** It
> is good enough to size a tank and rank candidate geometries. It is **not**
> good enough to be the final number behind a taped-out phase-noise claim.
> Every number it produces inherits the error bars in
> [Accuracy limits](#accuracy-limits). Per this repo's `CLAUDE.md` — *"numbers
> without methods are not results"* — an inductance from this file must be
> quoted with its method and its limits, exactly like a phase-noise number.

Nothing here ratifies a `spec/target-spec.md` row. Ratification is a separate
decision-record step; this directory only produces evidence it would cite.

---

## Reproducing it

```bash
sim/inductor-model/run_model_check.sh
```

That is the entire cold-start invocation — no arguments, no build step. It
takes about 25 s.

**Requirements**: `ngspice` on `PATH`, `bash`, `awk`. Unlike
`../tank-characterization/`, this experiment **does not need the PDK
installed**: the model is self-contained (its PDK constants are transcribed
into its header with each one's source cited) and it loads no PDK library.
That is deliberate — the model has to be checkable by a reader who has this
repository but not a PDK tarball.

To use the model in the tank study, which is what it exists for:

```bash
export SG13G2_IND_MODEL_LIB=$PWD/sim/inductor-model/sg13g2_inductor_analytic.spice
sim/tank-characterization/run_pvt_sweep.sh     # needs the PDK, for the MIM half
```

That fills in `records/<record-id>-inductor.csv` in the tank study with real
L/Q/SRF instead of `MODEL_ABSENT`, and the tank record then names this file by
repo-relative path **and content sha256**, so a reader can tell exactly which
model produced the numbers.

Records land under `records/`, `corners/`, `netlist-snapshots/` keyed by a
fresh record ID per run, append-only, per [`../README.md`](../README.md).

---

## Route decision (why analytic)

Issue #6 named three candidate routes. All three were evaluated against what
is actually available in this flow today.

| Route | Verdict | Why |
|---|---|---|
| **1. EM-extract the PDK's own PCell** (openEMS / Palace) and fit a lumped subcircuit to the extracted S-parameters | **Rejected for now, and it remains the right long-term answer** | This is IHP's own documented route (`libs.doc/doc/EM_Simulation_Overview.pdf`). It is blocked twice over: `libs.tech/openems/openems_ihp_sg13g2` and `libs.tech/palace/` are **git submodules that are empty in the v0.3.0 release tarball** (GitHub source tarballs never carry submodule contents), and neither openEMS nor Palace is installed in this environment. Beyond fetching them, the route needs a 3-D mesh of the PCell, an EM solve per geometry, and an S-to-lumped fitting step this repo does not have. That is a multi-day tool-bring-up, not a model choice — so it is **filed as its own issue** rather than done badly here. |
| **2. Published or measured data for a process-matched spiral** | **Rejected** | No citable measured spiral inductor **on SG13G2** with a stated geometry was found in the PDK's own documentation, and this repo's evidence bar does not permit importing a number from a *different* process and calling it this process's. A measurement is only usable if it is traceable to a geometry and a stack; an untraceable "typical 130 nm BiCMOS spiral" number would be exactly the invented number `../tank-characterization/` refused to write. |
| **3. Analytic model with explicit error bars** | **Chosen** | Every input is either a *published closed-form expression* (Mohan et al. 1999, whose error vs. 3-D field solvers and vs. measurement the authors themselves quantify) or a *PDK-published process constant* (transcribed with its source, and cross-checked between two independent PDK files — see [Where the constants come from](#where-the-constants-come-from)). It has no fitted parameters. Its error bars can therefore be stated rather than guessed, which is the property that makes it admissible here at all. |

**The honest framing of route 3**: it is not a first-principles PDK number and
this repository never presents it as one. It is a *documented approximation
with a stated error budget*, admitted because a tank cannot be sized without
some L, and an approximation whose error is stated beats both a silent
placeholder and indefinite paralysis. When the EM route lands, this model
should be superseded, and every number derived from it re-derived.

---

## The model

```
       la o--[ Rdc+Rcross ]--[ 10-section skin ladder ]--[ Lmain ]--o lb
              |         `------------------ Cs ------------------'   |
           [Coxa]                                                 [Coxb]
              |                                                      |
        [Rsia||Csia]                                          [Rsib||Csib]
              |                                                      |
              +----------------------o sub -------------------------+
```

The standard 2-π lumped spiral topology. Element by element:

| Element | What it is | Where it comes from |
|---|---|---|
| `Lmain` + ladder `L`s | total series inductance = `L_mw` | Mohan et al. 1999 eq. (1), modified Wheeler, octagonal `K1 = 2.25`, `K2 = 3.55` |
| `Rdc` | `R_sh · len / w_eff` | PDK `RSTM2` = 11 mΩ/sq, `DWTM2` = −140 nm; `len` from the PCell's own octagon geometry |
| skin ladder | exact vertical (through-thickness) skin effect | closed-form partial fraction of `ξ·coth ξ`, truncated at 10 sections — **not a fit** |
| `Rcross` | crossunder vias + TopMetal1 bridges | PCell's `nr_vias` rule, PDK `RTV2` = 1.1 Ω/via, `RSTM1` = 18 mΩ/sq |
| `Cs` | turn-to-bridge feed-through capacitance | PDK `CATOPMET2` = 13 aF/µm² |
| `Coxa`/`Coxb` | oxide capacitance to substrate, split half per port | magic `defaultareacap` 3.233 aF/µm² + `defaultperimeter` 31.175 aF/µm |
| `Rsi`/`Csi` | substrate spreading loss | PDK `RSBLK` = 50 Ω·cm, disk-on-half-space `ρ/(4a)`, with `Rsi·Csi = ε_si·ρ_sub` |

### Geometry is read off the PCell, not assumed

`libs.tech/klayout/python/sg13g2_pycell_lib/ihp/inductors_code.py` draws an
**octagonal** spiral in TopMetal2. Two lines in it fix the whole geometric
interpretation:

- `lat_sm = GridFix(d/(2*var))*2` with `var = 1+sqrt(2)` — the innermost turn's
  inner edge is an octagon whose **flat-to-flat width is exactly the passed
  `d`**, so `d` is the inner diameter, not the outer and not the average.
- `d = d + 2*(s+w+grid)` at the end of the turn loop (`grid = 0.01 µm`) — so
  the radial pitch is `s + w + grid`, not `s + w`.

Hence `d_out = d + 2(n−1)·pitch + 2w`, `d_avg = (d_in+d_out)/2`, and, since a
regular octagon of flat-to-flat width `D` has perimeter `8·tan(π/8)·D =
3.3137·D`, the conductor centre-line length is
`len = 3.3137 · n · (d + w + (n−1)·pitch)`.

That reading is **independently confirmed** below: it reproduces IHP's own
shipped `lEstim` for the default device to 0.05 %.

### The skin ladder is exact algebra, not a curve fit

The 1-D internal impedance of a slab of thickness `t` driven on both faces is
`Z_int = R_dc · ξ·coth ξ`, `ξ = (1+j)·t/(2δ)`. Its exact partial-fraction
expansion, with `ξ² = j·u/2` and `u = f/f_skin`, is term-for-term a chain of
parallel `R‖L` sections with

```
R_m = 2·R_dc          (independent of m)
L_m = µ0·len·t / (2·π²·m²·w_eff)
```

so the ladder has **no free parameters**. Truncating at `m = 10` reproduces
`Re(ξ·coth ξ)` to 0.03 % below 20 GHz. Because `R_m` scales with `R_dc` while
`L_m` does not, giving every ladder resistor the PDK's `TC1RSTM2` makes the
ladder's corner frequencies scale as `ρ_m(T)` automatically — the temperature
dependence of the skin effect is exact and comes free from ngspice's native
`tc1`.

`f_skin` (where δ = t) is **0.93 GHz** for TopMetal2, so the skin effect is
already active across the whole plausible LC-VCO band. It is not optional.

### Where the constants come from

Every process constant is transcribed into the model header with its source,
and each was re-verified against the PDK install for this PR:

| Constant | Value | Source, verified |
|---|---|---|
| `TTM2` | 3000 nm | `SG13G2_os_process_spec.pdf` §2.16; **and** `xsect/sg13g2_for_EM.xs` `t_tm2 = 3` |
| `RSTM2` | 7.5 / **11** / 14.5 mΩ/sq | process spec §2.13; **and** magic `resist (allm7)/metal7` = 7 / 11 / 15 in the three corner sections |
| `RSTM1` | 18 mΩ/sq | process spec §2.13 |
| `DWTM2` | −140 nm | process spec §2.13 |
| `TC1RSTM2` | 3800 ppm/K | process spec §2.13 |
| `RTV2` | 1.1 Ω/via | process spec §2.14 |
| `RSBLK` | 37.5 / **50** / 62.5 Ω·cm | process spec §2.13 |
| `CATOPMET2` | 13 aF/µm² | process spec §2.17 |
| oxide height to TM2 | 11.23 µm | summed from `xsect/sg13g2_for_EM.xs` (IHP's own EM stack) |
| TM2→substrate area cap | 3.233 aF/µm² | magic `ihp-sg13g2-extract.tech` `defaultareacap allm7 metal7` |
| TM2→substrate fringe | 31.175 aF/µm | magic `defaultperimeter allm7 metal7` |

**Two independent internal consistency checks fall out of that table**, and
both pass:

- `ε0·4.1 / 11.23 µm = 3.2325 aF/µm²` vs. magic's `3.233` — **0.02 %**. So the
  xsect stack height and an oxide `ε_r ≈ 4.1` are mutually consistent, and the
  capacitance constant used here is the PDK's own rather than a fit.
- `ε0·4.1 / 2.8 µm = 12.96 aF/µm²` vs. the process spec's `CATOPMET2` target
  of `13` — **0.3 %**, using the *same* `ε_r` and the `t_topvia2 = 2.8` from
  the same xsect file.

---

## Validation evidence

Two different questions get two different answers, and this directory is
careful not to let one stand in for the other.

### 1. Does the netlist implement the algebra it claims? — yes, to 0.003 %

`run_model_check.sh` re-derives the complex driving-point impedance
independently in awk ([`testbench/closed_form_z.awk`](testbench/closed_form_z.awk)),
evaluating `ξ·coth ξ` directly in complex arithmetic rather than as the
netlist's 10-section ladder, and fails the run if the two disagree by more
than **0.5 %** at 1, 5, 10 and 20 GHz.

Record `20260906-160637-a73c3c7`: **27/27** simulation points pass, 3
geometries each. The **worst** disagreement anywhere in the grid is
**0.003 %** (`rhi_shi`, −40 °C, `p11`, 10 GHz). That bounds the ladder
truncation error as well as the netlist's correctness — it is the same
known-answer discipline `../tank-characterization/` applies to its extraction
arithmetic.

This says nothing whatsoever about whether the *model* is right.

### 2. Is the model a good description of a real spiral? — partially answerable

Without EM extraction or silicon this cannot be settled. Three checks are
available and all three are recorded in
`records/<record-id>-geometry-check.csv`:

**(a) IHP's own `lEstim`.** `inductor2_code.py` ships a default inductance
estimate of **33.303 pH** for `w=2 µm, s=2.1 µm, nr_r=1` at the PCell's own
computed minimum `d`. This model gives **33.287 pH** — **−0.05 %**.

> This is the single most valuable check available. It is an *external*
> number, published by IHP for its own PCell, and it simultaneously confirms
> (i) the geometric reading of `d` as the **inner** flat-to-flat diameter,
> (ii) the octagonal `K1`/`K2` constants, and (iii) that IHP themselves size
> this device with a Wheeler-family expression. Two caveats keep it honest: it
> is one geometry, at the very bottom of the size range; and evaluated at the
> PCell's *shipped* `DMIN = 15.48 µm` rather than at the `inductor_minD()`
> value of 14.76 µm, the same comparison reads **+5.5 %** — which is a fair
> statement of how sharply small-geometry `L` moves with `d`, and why the
> single-turn error bar below is ±10 % and not ±5 %.

**(b) Mohan's three mutually independent expressions.** Modified Wheeler,
current sheet, and the data-fitted monomial agree with each other to:

| Geometry | `d_out` | `L` (mod. Wheeler) | spread of the 3 expressions |
|---|---|---|---|
| `p1` — 1 turn, `w=8.22 s=3.29 d=47.65` | 64.1 µm | 103.8 pH | 1.7 % |
| `p13` — 5 turns, `w=6.10 s=3.29 d=110.11` | 197.5 µm | 5.413 nH | 1.1 % |
| `p11` — 4 turns, `w=8.22 s=3.74 d=141.975` | 230.2 µm | 4.571 nH | 0.6 % |

Agreement among three expressions is a **consistency** check, not an accuracy
check — they share a common ancestry in the same measured/simulated data set.
It bounds the *expression-choice* contribution to the error, nothing more.

**(c) The classical single-loop formula**, for the one-turn case only:
`L = µ0·a·(ln(8a/GMD) − 2)` with an equal-perimeter circle and the geometric
mean distance of a `w × t` strip gives **94.2 pH** for `p1` vs. this model's
**103.8 pH** — a 10 % gap. That is the origin of the wider single-turn error
bar.

---

## Accuracy limits

These are the same limits stated in the model file's own header, restated here
with the supporting arithmetic. **Read them before quoting any number this
model produced.**

### Frequency: trust 0.5 GHz … 20 GHz, and only below the device's own SRF

- Below ~0.3 GHz nothing is wrong; the model is simply uninteresting there.
- Above 20 GHz the ladder truncation error grows (0.03 % at 20 GHz, 0.6 % at
  100 GHz, 1.7 % at 300 GHz on the series resistance) and — far more
  seriously — the lumped 2-π topology itself stops being valid once the
  conductor length approaches a wavelength. `p13`'s conductor is **2.55 mm**
  long; at `ε_r ≈ 4.1` that is a quarter wavelength at roughly **15 GHz**,
  which is essentially where this model reports that device's SRF (14.3 GHz).
  **So the reported SRF of the large multi-turn geometries should be read as
  an order-of-magnitude marker, not a number** — it lands exactly where a
  lumped model loses the right to answer the question. **The lumped model has
  no way to signal that it has stopped being a lumped problem.**
- Above the reported SRF, the extracted `Leff` is not an inductance at all —
  exactly as for the PDK's MIM model. Check the `srf_hz` column first.

The full 100 MHz … 300 GHz band is swept anyway, and committed, so the record
shows *where* the model stops being credible instead of stopping short of it
and leaving the reader to guess.

### Inductance: ±5 % multi-turn, ±10 % single-turn

Mohan et al. report a typical error of 1–2 % vs. a 3-D field solver and ~5 %
vs. measurement for the modified-Wheeler expression, over a fitted family
spanning `d_out` 100–480 µm, `L` 0.5–100 nH, `w` from 2 µm to `0.3·d_out`, `s`
from 2 µm to `3w`, and `d_in/d_out` 0.1–0.9.

| Geometry | Inside Mohan's fitted family? |
|---|---|
| `p13` (5 turns, `d_out` 197.5 µm, 5.4 nH) | **yes** |
| `p11` (4 turns, `d_out` 230.2 µm, 4.6 nH) | **yes** |
| `p1` (1 turn, `d_out` 64.1 µm, 104 pH) | **no — outside on two axes at once** (`d_out` < 100 µm and `L` < 0.5 nH) |

So `p1` is an **extrapolation**, cross-checked in (c) above against the
single-loop formula to a 10 % gap. Treat single-turn `L` as ±10 %.

### Quality factor: this model's Q is an UPPER BOUND

Q is the largest uncertainty here and it is **systematic, one-directional
error, not scatter**. Three named mechanisms, all of which can only lower Q:

**(a) Lateral current crowding between turns is not modelled.** Only the
vertical (through-thickness) skin effect is, and for these traces `w > t`, so
crowding — not vertical skin effect — is the dominant AC loss mechanism above
a few GHz in a multi-turn spiral. Every record row therefore carries a
`qlow_*` column beside `q_*`: the Q that follows from the one-sided
effective-conduction-depth assumption `t_eff = δ·(1−exp(−t/δ))`, which is
empirically closer to measured spirals precisely *because* it overstates
vertical skin effect and thereby partly stands in for crowding. **Read the
pair as a bracket.** At `typ`, 27 °C:

| Geometry | Q @ 1 GHz | Q @ 5 GHz | Q @ 10 GHz |
|---|---|---|---|
| `p1` (1 turn, 104 pH) | 2.57 … **1.61** | 11.2 … **5.0** | 16.9 … **7.5** |
| `p13` (5 turns, 5.45 nH) | 5.26 … **3.67** | 11.1 … **8.0** | 4.95 … **4.63** |
| `p11` (4 turns, 4.61 nH) | 6.66 … **4.55** | 12.3 … **9.1** | 5.00 … **4.73** |

(optimistic … pessimistic; the truth is expected between, and the gap widens
with turn count and with frequency.)

**(b) Magnetically induced substrate eddy-current loss is not modelled at
all.** At 50 Ω·cm and ≤20 GHz it is usually second-order, but it is a one-way
error.

**(c) The substrate branch is a two-element lumped stand-in** for a
distributed half-space, sized from `RSBLK` and the classical `ρ/(4a)`
spreading resistance. Expect a factor-of-~2 uncertainty on `Rsi`. The `slo`
/`shi` corners (±25 % on `RSBLK`) move `p13`'s Q @ 10 GHz from 3.94 to 5.84 —
i.e. **±19 %**, which is *larger* than the ±10 % the metal-resistance corners
`rlo`/`rhi` produce there. Substrate loss dominates Q at the top of the band;
metal loss dominates at the bottom.

### Self-resonance: ±15 %

SRF rides on the back of the `L` and `C` uncertainties. The oxide capacitance
treats the coil band as a **solid octagonal annulus**, which is right while
the turn spacing is much smaller than the 11.23 µm oxide height (true for
every PDK testcase geometry: `s ≤ 9 µm`) and overstates C once `s` approaches
`h_ox`.

### The PCell's feed lines are deliberately excluded — and here is their cost

`inductors_code.py` draws two feed paths from the coil down to the LA/LB pin
boxes, of length `nr_r·w + (nr_r−1)·s + 30 µm` each, in **TopMetal2 for the
1-turn device and TopMetal1 for multi-turn**. They are excluded because the
subcircuit's parameter list (`w, s, d, nr_r`) has no feed-length parameter, so
folding in a fixed PCell drawing constant would bake a layout artifact into
every downstream tank number. Their cost, at `typ`/27 °C:

| Geometry | feed length | feed layer | `R_feed` | `R_dc+R_cross` | added series R |
|---|---|---|---|---|---|
| `p1` | 76.4 µm | TM2 | 0.104 Ω | 0.252 Ω | **+41 %** |
| `p13` | 147.3 µm | TM1 | 0.445 Ω | 6.250 Ω | **+7 %** |
| `p11` | 148.2 µm | TM1 | 0.330 Ω | 4.142 Ω | **+8 %** |

So the exclusion matters a lot for a small single-turn coil and very little
for a large multi-turn one. **A tank design must add the feed resistance of
its own drawn layout back in**; the numbers above are how.

An independent bracket on this, again from IHP's own PCell: `inductor2_code.py`
ships `rEstim = 577.7 mΩ` for its default device. This model's coil-only
`R_dc` for that geometry is **328 mΩ**, and coil + drawn feed is **707 mΩ**.
IHP's number sits between the two. That is a *bracket*, not a confirmation —
it says the coil-only resistance understates the drawn device by roughly a
factor 1.5–2 at that (smallest) size, consistent with the table above, and it
is reported that way rather than dressed up as agreement.

### Not modelled, deliberately

Any patterned ground shield; the `inductor3` centre-tapped variant (this
subcircuit is the 2-terminal `inductor` device only); the PCell's substrate
etching (`subE`) option; statistical / mismatch spread. Temperature enters
only through the metal sheet resistance — the PDK publishes no temperature
coefficient for `RSBLK`, so substrate resistivity is held constant and that
perturbs only the substrate-loss term.

---

## Results

From record `20260906-160637-a73c3c7`, at `typ` (`RSTM2` = 11 mΩ/sq,
`RSBLK` = 50 Ω·cm), 27 °C. Full grid in that record's CSVs.

| Geometry | `L` @ 1 GHz | SRF | Q @ 1 GHz | Q @ 5 GHz | Q @ 10 GHz |
|---|---|---|---|---|---|
| `p1` — 1 turn, `d_out` 64.1 µm | 103.8 pH | 240 GHz | 2.57 | 11.19 | 16.90 |
| `p13` — 5 turns, `d_out` 197.5 µm | 5.451 nH | **14.31 GHz** | 5.26 | 11.14 | 4.95 |
| `p11` — 4 turns, `d_out` 230.2 µm | 4.606 nH | **14.11 GHz** | 6.66 | 12.34 | 5.00 |

Read alongside the `qlow_*` bracket in [Accuracy limits](#accuracy-limits) —
these Q values are upper bounds.

**Temperature** (`p13`, `typ`): Q @ 1 GHz falls **7.0 → 5.26 → 3.86** across
−40 / 27 / 125 °C, i.e. **−27 %** from 27 °C to 125 °C, tracking `TC1RSTM2`
directly. `L` moves by **0.1 %** over the same span. So the spiral, unlike the
MIM cap (which `../tank-characterization/` measured as flat to ±0.06 %), is a
**strong** temperature contributor to tank Q and a negligible one to tank
centre frequency.

**Process** (`p13`, 27 °C, Q @ 10 GHz): `rlo`/`rhi` (metal) spans 4.77–5.14;
`slo`/`shi` (substrate) spans 3.94–5.84. The worst case is at a corner of
*both* axes (`rhi_slo`: 3.82), which is why the two are swept independently
rather than as one "slow/fast" knob.

### What this means for the tank, read against the MIM data

`../tank-characterization/` bounded `Q_tank ≤ Q_C` and found small-C/large-L
strongly favoured. This model now bounds the other side, and the two together
say something concrete: at 10 GHz, `p13`'s **Q_L ≈ 5** (upper bound, ≈4.6
lower) sits *well below* the 20×20 µm `cap_rfcmim`'s `Q_C = 68`, so **the
inductor, not the capacitor, is the tank-Q limiter** for these geometries at
the top of the band. Both 4- and 5-turn PDK testcase spirals also
self-resonate at ~14 GHz, which is *inside* the plausible band — so a 10 GHz
tank built on either would be running at 70 % of the inductor's SRF, where
`Leff` has already risen to **10.25 nH, +88 %** above its 1 GHz value. (And,
per the frequency caveat above, a 14 GHz SRF on a 2.55 mm conductor is
precisely where a lumped model stops being entitled to a precise answer — so
that is a warning flag on these geometries, not a measurement of them.)

None of that is a ratified spec row, and this PR does not make any of it one.

---

## What this does **not** establish

1. **That a real SG13G2 spiral behaves this way.** No EM extraction, no
   measurement, no silicon. Every check in
   [Validation evidence](#validation-evidence) is either internal
   (netlist-vs-algebra) or a consistency check among expressions with a common
   ancestry — except IHP's `lEstim`, which is one geometry at the bottom of the
   size range.
2. **Any Q number to better than the bracket.** The `q_*`/`qlow_*` pair is not
   decoration; unmodelled crowding and substrate eddy currents are real and
   one-directional.
3. **Anything above 20 GHz**, or above a device's own SRF.
4. **Anything about the drawn layout's parasitics** beyond the coil itself —
   feeds, ground shielding, and neighbouring structures are all out.

The follow-up that would settle (1) — EM-extracting the PDK's own PCell with
openEMS or Palace and fitting a lumped subcircuit to the extracted
S-parameters — is filed separately as **#9**.

---

## Sources

- **[MOH]** S. S. Mohan, M. del Mar Hershenson, S. P. Boyd, T. H. Lee, "Simple
  Accurate Expressions for Planar Spiral Inductances", *IEEE J. Solid-State
  Circuits*, vol. 34, no. 10, pp. 1419–1424, Oct. 1999.
  [DOI 10.1109/4.792620](https://doi.org/10.1109/4.792620). Modified-Wheeler
  expression (1) + Table I; current-sheet (2) + Table II; monomial (3) +
  Table III.
- IHP-Open-PDK v0.3.0 (pinned in [`../pdk.json`](../pdk.json)):
  `libs.doc/doc/SG13G2_os_process_spec.pdf`;
  `libs.tech/klayout/tech/xsect/sg13g2_for_EM.xs`;
  `libs.tech/magic/ihp-sg13g2-extract.tech`;
  `libs.tech/klayout/python/sg13g2_pycell_lib/ihp/inductors_code.py` +
  `inductor2_code.py` + `utility_functions.py`;
  `libs.tech/klayout/tech/lvs/testing/testcases/unit/ind_devices/`.
- [`../tank-characterization/README.md`](../tank-characterization/README.md)
  § "The inductor gap" — the negative result this directory answers.
- This repo's `CLAUDE.md` — "Tank first", "numbers without methods are not
  results"; [`../README.md`](../README.md) — the append-only record convention;
  `spec/review-bar.md` items 1 and 2.
