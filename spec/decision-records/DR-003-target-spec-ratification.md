# DR-003: Target-spec ratification pass 1 — nine rows ratified as targets, three left explicitly open

- **Status**: **proposed** — a recommendation for two-key ratification via this
  PR (Judge review + Champion/operator merge), per the 2026-08-19
  ratification-via-PR ruling (2AMLogic/2am#357, cited by issue #35), which is
  the path this repo's own spec-ratification issue selects while the
  fleet-standard `ratification/` tree remains uninstalled here
  (2AMLogic/product#135: this repo is one of nine 2026-09-06-wave canaries
  scaffolded without it). Nothing here is binding until this PR merges. Upon
  merge, the per-row dispositions in "Decision" below take effect exactly as
  stated — this is a **partial** ratification by design: nine rows move
  DRAFT → RATIFIED **as targets** (binding numbers, explicitly **not met by
  any measurement** — no oscillator exists yet), three rows stay explicitly
  OPEN.
- **Known wart, handled in text (2AMLogic/product#135, per issue #35's own
  instruction)**: nothing updates a record's own `Status:` line when its
  ratification PR merges — `sky130-comparator`'s DR-002 still reads
  `proposed` five days after its merge (verified live there, 2026-09-20).
  This record therefore states its operative post-merge status here, in
  prose, unambiguously: **once the PR carrying this record is merged, the
  nine dispositions marked RATIFIED below are binding on design work, and
  the three marked OPEN are binding as explicitly-open.** A later record or
  edit that flips the field itself is welcome; a reader must not take the
  stale `Status: proposed` field as evidence the record never took effect.
- **Date**: 2026-09-21
- **Decided by**: Builder agent, issue #35
- **Supersedes**: none — third decision record in this repo. Does not
  supersede DR-001 or the pending negative-gm-pair record (#33, in flight);
  this record disposes the target-spec table's own rows, which no earlier
  record touched (DR-001 explicitly ratified no row, and #33's record is
  still being authored).
- **Superseded by**: (none while this record stands)
- **Related**: #35 (this issue), #3 (gap-to-T1 tracker — item 5 is the gate
  this record clears; item 5's note is updated on merge, per this issue's
  own acceptance criteria and #3's append-in-place convention), #33
  (negative-gm pair architecture decision record — **in flight while this
  record is drafted**; it is the topology input this ratification follows,
  and the three OPEN rows below are exactly the rows gated on it),
  #31 / DR-001 (tuning-device decision this record builds on),
  2AMLogic/product#135 (two-key mechanism uninstalled fleet-wide; the
  `Status:`-staleness wart), 2AMLogic/2am#357 (ratification-via-PR ruling),
  `2AMLogic/sky130-comparator` DR-002 (this fleet's worked example for a
  partial target-spec ratification, merged via its PR #29)
- **Consumes**:
  - `sim/inductor-model/em-extraction/` — record
    `20260910-052657-3896421` (openEMS v0.37.0-rc2 FDTD extraction of the
    PDK's three LVS-testcase inductor PCells): measured `L` and `Q` at
    1/2/5/10 GHz and **measured SRF 8.07 GHz (`p13`) / 9.42 GHz (`p11`)**,
    50–77 % below the analytic estimate. Per
    `sim/tank-characterization/README.md`, this is now "the authoritative
    model for those three geometries."
  - `sim/tank-characterization/` — records `20260906-135025-d3410d1` and
    `20260906-160246-a73c3c7` (MIM cap over the full corner grid):
    finding 2 (use `cap_rfcmim`, never `cap_cmim`, at RF), finding 3
    (`Q_C` at 10 GHz falls from 68 at 0.6 pF to 6.3 at 3.8 pF — tank wants
    small C), finding 4 (50×50 µm MIM SRF 16.1 GHz), finding 5 (MIM
    temperature drift ±0.06 % over 165 °C; process spread ±10 % on C ≈ ∓5 %
    on center frequency), finding 7 (at 10 GHz the tank-Q limiter is the
    **inductor**).
  - `sim/varactor-characterization/` — record `20260909-231619-de50891`
    (216/216 points PASS, 0.1 % known-answer check), via DR-001: per-geometry
    `Cmax`/`Cmin`/`Cmax/Cmin` (1.878–2.079×) and `Q(V,f)` — including
    **`Q` at 5 GHz of 44.8 for `mos_small` at V=0, rising to 76 at V=1.2,
    vs 2.73 for `mos_mid`** — plus the finding that four parallel identical
    cells keep the single cell's `Q` (the `mos_xlarge` = 4×`mos_large`
    evidence).
- **Numbering note (per `TEMPLATE.md`'s collision rule)**: this record takes
  DR-003, deliberately leaving DR-002 to the in-flight #33 negative-gm pair
  record, whose own issue body (filed 2026-09-15, five days before #35)
  names `DR-002-<slug>.md` as its target file. Two records racing for one
  number is the documented failure mode the collision rule exists to
  prevent; `spec/decision-records/` was re-checked immediately before this
  PR (DR-001 was the only record present, zero open PRs) and is re-checked
  after the pre-push rebase.

## Context

T1 item 5 (gap-to-T1 tracker #3) requires "full PVT corner simulation vs a
**ratified** spec" — "verdicts against a draft spec are provisional by
construction" — and items 6, 7 and 8 all grade against spec rows. Until the
table binds, no amount of simulation can be cited toward bronze. Every row
of `spec/target-spec.md` has sat DRAFT since issue #2 drafted it
(2026-09-06), its numeric cells deliberately blank pending the
tank-characterization study this repo's `CLAUDE.md` requires first ("Tank
first").

Three things have since landed on `main` that change what an honest
ratification can say:

1. **The tank study landed, and it moved the numbers.**
   `sim/tank-characterization/` (#5) characterized the MIM cap over the full
   PVT grid from the PDK's own models, and — because SG13G2 v0.3.0 ships no
   ngspice inductor model — the inductor half was filled by
   `sim/inductor-model/` (#6/#8/#11/#23): an analytic screening model with
   stated error bars, then an openEMS EM extraction of the PDK's own
   inductor PCell. The EM extraction is the decisive input: measured SRF is
   **50–77 % lower** than the analytic estimate (8.07/9.42 GHz for `p13`/
   `p11`), which rules out the "~10 GHz, likely low-GHz" plan that both the
   README's thin target list and the analytic-only study implied, and the
   multi-turn EM Q plateaus at ≈ 7.6–10.3 across 2–5 GHz rather than
   peaking at 10 GHz.
2. **The tuning device is decided.** DR-001 (merged via PR #32, closing #31)
   adopts `sg13_hv_svaricap` over its full 0.0–3.3 V HV domain, with no
   band-switching bank in v1, on measured `Cmax/Cmin` = 1.88–2.08× and
   measured `Q(V,f)`. Its per-geometry Q data is the input rows 2 and 5
   below consume.
3. **The ratification mechanism is decided.** DR-001 declined to self-ratify
   because its search found no document describing what the spec's stated
   "two-key (EE key + market key)" mechanism concretely is. Since then:
   2AMLogic/product#135 confirmed the mechanism is **uninstalled fleet-wide**
   across the nine newest canaries (this repo included — no `ratification/`
   tree), and the 2026-08-19 ratification-via-PR ruling (2AMLogic/2am#357)
   declared ratification to be "the act of a decision-record PR being
   approved and merged, not the act of drafting it" — with
   `sky130-comparator`'s DR-002 ratifying exactly this way via its PR #29.
   Issue #35 (this record's issue) selects that path explicitly.

**This record is the ratification decision for `spec/target-spec.md`'s
rows.** Issue #35's own scope constrains it: "For any row with no measured
evidence, ratify it as a **target** and say so. Do not ratify a row as met
on a placeholder." No oscillator, schematic, or oscillator measurement
exists anywhere in this repo as of this record — so every RATIFIED row
below is a **binding target**, derived from recorded device data and
stated engineering arithmetic, and **not one of them is met**. Per
`CLAUDE.md`'s guardrail, these targets are set now, deliberately **before**
simulation exists to be tempted by; relaxing one later to make a result
pass requires superseding this record, in public, with the audit trail
`TEMPLATE.md`'s append-only rule preserves.

**The one input this record must wait for is named, not guessed.** Issue
#35 states issue #33's negative-gm-pair architecture record "is the
topology input this ratification should follow." That record is still
being authored by another sweep as this one is drafted (#33: OPEN,
`loom:building`) — so the rows that depend on it (the pair's supply
flavor, and the rows downstream of the rail/topology) stay **explicitly
open** here rather than being ratified on a guessed outcome. This follows
`sky130-comparator` DR-002's precedent: a partial ratification, "explicitly,
not silently."

## Ratification note

`spec/target-spec.md`'s own header states ratification "flows through the
two-key mechanism (EE key + market key)" and that "a scope-only spec DR
ratified with both keys needs no per-PR operator statement (generalized
ruling, 2026-08-28, cited in issue #2)." No `ratification/` tree exists in
this repo (2AMLogic/product#135), so no key can be recorded anywhere a
reader could find it — the exact gap DR-001 documented from inside its own
filing. What has changed since DR-001 is not the tree (still absent) but
the ruling: 2AMLogic/2am#357 (2026-08-19) establishes that **a
decision-record PR reviewed by Judge and merged by Champion/operator is
the two-key evaluation** — the key-holders act through the review/merge,
not through a file. Issue #35 invokes exactly this path, and
`sky130-comparator` ratified its target spec this way (DR-002, merged PR
#29). This record follows suit.

One consequence is handled in text: nothing updates a `Status:` field on
merge (the `Status:`-staleness wart, 2AMLogic/product#135, reproduced live
on `sky130-comparator` five days post-merge). See the second Status bullet
above: the operative post-merge state of this record is what its prose
says, not what its `Status:` field fails to say. Whichever pass next edits
this record (or supersedes it with a DR that flips the field) is doing
bookkeeping, not re-deciding.

## Decision

Row by row, against the 12-row table in `spec/target-spec.md` (rows
numbered 0–11). Dispositions marked **RATIFIED (target)** bind the stated
number as a target — the design must meet it for T1 item 5 to record a
pass, and no current measurement claims it met. Dispositions marked **OPEN**
bind nothing numerically and say why, explicitly.

### Row 0 — Supply voltage / device flavor: OPEN, explicitly

The varactor-side `Vctrl` domain is settled (DR-001: full 0.0–3.3 V HV,
driving `sg13_hv_svaricap`'s well/substrate node). What is not settled is
the negative-gm pair's own supply flavor — CMOS pair on 1.2/1.8/3.3 V vs a
SiGe HBT pair on its own rail — and that is precisely the open question
issue #33's in-flight record exists to decide from the now-available
tank-Q evidence. Ratifying a rail here would either guess #33's outcome or
preempt it; both are what "explicitly, not silently" forbids. **OPEN
pending the #33 record's topology/supply decision**, which lands as its own
DR and amends this row (or is folded into the first PVT pass, whichever its
record states).

### Row 1 — Center / target band: RATIFIED (target) — 4.5 / 5.0 / 5.5 GHz min/typ/max

**Target**: center frequency 5.0 GHz nominal; accepted window 4.5–5.5 GHz
across the tuning range and the MIM ±10 % process spread. The design must
demonstrate oscillation inside this window at every bound corner.

**Device data**: measured EM SRF is 9.42 GHz on `p11` (4-turn) and 8.07 GHz
on `p13` (5-turn) — record `20260910-052657-3896421`. The extraction's own
"What this means for the tank" section states a tank on either geometry
for a ~10 GHz carrier "would be running **past**, not below, its own
inductor's SRF" — the reverse of what the analytic-only study implied, and
the reason the older "likely ~10 GHz" framing is dead. Multi-turn EM Q
plateaus instead across 2–5 GHz: `p11` Q = 9.49 at 2 GHz and 10.28 at
5 GHz (measured, ±10 % convergence bar), `p13` 7.82/7.62 — flat-to-rising
across exactly this window, so nothing is bought by going lower and Q is
not yet collapsing near the top.

**Arithmetic**: the window's top end sits at 9.42/5.5 ≈ 1.7× (58 % of) the
lowest geometry-bounding SRF, and ≥ 2.09× above `p13`'s 8.07 GHz for any
in-window frequency — comfortably inside the conventional "tank center
below ~2/3 of inductor SRF" operating margin. At the illustrative tank
sizing of row 2 (L ≈ 4.28 nH `p11`, C_tot ≈ 225 fF at Vctrl = 0), the
resonance lands at ≈ 5.13 GHz, in-window without trimming.

**What is explicitly not decided here**: which testcase geometry (or a new
PCell) the final layout uses; the window binds the **band**, not the
inductor. A geometry change requires re-reading this row against that
geometry's own EM SRF/Q before the band is re-graded.

### Row 2 — Tuning range (Kvco integral): RATIFIED (target) — ≥ 15 % fractional (≥ 20 % stretch)

**Target**: ≥ 15 % fractional tuning (f_max/f_min ≥ 1.15) across varactor
DR-001's full 0.0–3.3 V domain, band-center referenced; stretch ≥ 20 %.
No band-switching bank — DR-001 already decided none is adopted in v1, with
a named revisit trigger (this row's own achieved range vs. requirement).

**Device data**: measured `Cmax/Cmin` = 1.878 (`mos_small`) and 2.079
(`mos_mid`) at tt/27 °C over the full domain (record
`20260909-231619-de50891`, via DR-001).

**Arithmetic**: with fixed tank capacitance `F` and varactor `V` at Vctrl=0
shrinking to 0.53·V at the domain's high end, the frequency ratio is
√((F+V)/(F+0.53·V)). ≥ 15 % needs F ≤ 0.92·V; ≥ 20 % needs F ≤ 0.53·V.
Illustration at 5 GHz on `p11` (L 4.28 nH): twelve `mos_small` cells in
parallel (V = 125 fF at V=0, 67 fF at V=3.3 V — parallel cells keep the
single cell's parameters per the `mos_xlarge` evidence) over F ≈ 100 fF
(MIM + parasitics) gives 225 → 167 fF, f ratio 1.163, **16.3 %** — target
met in principle with F at 80 % of V.

**The named risk**: the stretch bound requires the fixed-C budget
(MIM + pad/device/interconnect parasitics) to stay under ~half the total —
a lean budget a 5 GHz layout can plausibly deliver but no evidence in this
repo yet measures. The 15 % target keeps explicit margin against it and is
the binding number; 20 % is stretch.

### Row 3 — Kvco (small-signal slope) and linearity: OPEN, explicitly

The absolute Kvco (Hz/V) follows from the same fixed-C/varactor split row
2's illustration only guesses at — it is set at tank-sizing time, in the
schematic, whose own issue tracks #33. The kernel data is measured and
already recorded (per-cell dC/dV in
`records/20260909-231619-de50891-kvco.csv`), and the row's own condition
cell states "a single Kvco number without a stated Vctrl window is not
fillable" — the stated window does not exist yet because the sizing has
not been done. Proposing a Hz/V figure now would be a number assumed, not
derived. **OPEN pending tank sizing** (the same gate as rows 0/7 loses
once #33 lands and the schematic work begins); qualitative requirement
that survives this record regardless: **Kvco must be stated as a
Vctrl-window-referenced curve or slope, monotonic where dC/dV is
monotonic, with the corner movement of the whole row-1 window measured** —
per DR-001's own "state the tuning plan honestly" inheritance.

### Row 4 — Phase noise: RATIFIED (target) — ≤ −105 dBc/Hz @ 1 MHz (≤ −115 stretch)

**Target**: single-sideband phase noise ≤ −105 dBc/Hz at 1 MHz offset from
a band-center carrier (stretch ≤ −115), the primary offset; at 10 MHz
offset, ≤ −125 (stretch ≤ −135). **Every phase-noise number this repo ever
publishes against this row carries its measurement method** (per
`CLAUDE.md`: transient length, window, spectral estimator or ISF
derivation, variance, known limits) — that requirement is part of the
bound, already in the row's condition cell, and is restated here so the
target cannot be read as severable from its method.

**External precedent shown as arithmetic (Leeson's first-pass model)**:
taking the loaded-tank Q target of row 5 (7), a modest current-limited
carrier power of ≈ 0.2 mW, F ≈ 2, and f₀ = 5.0 GHz at Δf = 1 MHz:

L(Δf) ≈ 10·log₁₀[ (F·kT/P) · ( f₀ / (2·Q·Δf) )² ]
      = 10·log₁₀[ (2·4.0e-21/2e-4) · (5e9/(2·7·1e6))² ]
      = 10·log₁₀[ 4.0e-17 · 1.28e5 ] ≈ **−113 dBc/Hz**

At 10 MHz the 1/f² region continues 20 dB/decade lower, ≈ −133. The
Leeson frame is the standard first-pass estimate and is the
frequency-domain simplification of the ISF framework this repo's
`CLAUDE.md` names as canonical (Hajimiri & Lee 1998); it is external
precedent applied to **this** tank's measured Q and band, with the
assumptions (F ≈ 2, P = 0.2 mW) stated so a reviewer can re-derive or
repute them.

**Margins**: target −105 holds ≈ 8 dB over the estimate — margin across
flicker-corner upconversion near 1 MHz, the ±10 % bar on EM-tank Q
(≈ ±0.5 dB), temperature, and F/P uncertainty. Stretch −115 sits 2 dB
**beyond** the point estimate: it demands either double the carrier power
or Q ≈ 9 sustained, i.e. it presumes a healthy current-limited swing inside
row 8's stretch power budget. The stretch bound is therefore the
revisit-likely one (mirroring how `sky130-comparator` DR-002 flags its
tighter noise bound), not the target.

**What is explicitly not decided here**: the measurement method. ngspice
has no PSS/pnoise; the estimator (long-transient FFT/parametric, or
ISF-derived) is the phase-noise testbench's own later decision, tracked
in issue #3's item-1 pipeline. This row binds a number plus
method-transparency; the method choice lands with the testbench that
first measures it.

### Row 5 — Tank quality factor: RATIFIED (target) — ≥ 6 loaded at band center (≥ 8 stretch)

**Target**: loaded tank Q ≥ 6 at 5.0 GHz band center, including every
element that loads the tank in the as-designed schematic (varactor, MIM
fixed C, parasitic losses, any bias network); stretch ≥ 8. Evaluated at
the corners row 10 settles.

**Device data**: EM-measured inductor Q at 5 GHz is 10.28 (`p11`, the
band's reference geometry; ±10 % openEMS convergence bar — this is a
measured extraction, not the analytic upper-bound that DR-001's generation
of numbers used), falling to 7.82 at 2 GHz on `p13`. MIM `cap_rfcmim` Q at
10 GHz at 0.6 pF is 68 (finding 3) and rises at lower f and smaller C, so
the capacitive fixed-C branch is a negligible Q load at band center.

**Arithmetic**: at the row-2 illustrative split (varactor ≈ 56 % of total C
at Vctrl = 0), loaded Q combines as 1/Q ≈ Σ share_i/Q_i:
1/Q ≈ 1/10.3 + 0.56/44.8 + 0.44/(≈140) ≈ 0.097 + 0.0125 + 0.003 →
**Q ≈ 8.8**; mid-tune (Vctrl ≈ 1.2, share 43 %, Q_var 76) ≈ 9.1.

**The named constraint**: that arithmetic holds only if the tuning
capacitance is realized as **parallel small-geometry `mos_small` cells** —
the evidence-carrying Q observations are `mos_small`'s 44.8(5 GHz, V=0)
vs `mos_mid`'s 2.73 and `mos_large`'s ≪, and the `mos_xlarge`-identical-Q
finding that parallel copies preserve single-cell Q. A tank sized on
`mos_mid`-class cells loads Q to ≈ 4 and busts this row's target — that
trade (rows 2's absolute capacitance appetite vs 5's Q) is exactly the
coupling DR-001 flagged ("bigger geometries buy more absolute tuning
capacitance at a steep Q cost") and is the single most likely way a later
design defers this row, though DR-001's per-cell data already says the
parallel-small-cell route holds both.

The ≥ 6 target keeps explicit room under the ≈ 8.8 illustration for Q
erosion the bars name (EM ±10 %; unmodelled substrate coupling openEMS
does not capture) — while ≥ 8 stretch demands the illustration realized.
Both are targets; nothing meets them yet; row 6's gm budget and row 4's
noise estimate assume the target (Q = 7) case.

### Row 6 — Startup / negative-gm margin: RATIFIED (target) — pair gm ≥ 3.0× tank loss at every corner

**Target**: the negative-gm pair must present total transconductance
g_m ≥ 3.0 × the tank's loss conductance **at every bound corner of row 10**
— the design-time large-signal-robust startup safety factor, evaluated
small-signal as the standard first-pass margin (loop gain: gm·R_p ≥ SF).

**Device data + arithmetic**: at the illustrative sizing (C_tot ≈ 225 fF,
loader Q 6-8, band center): tank loss G_loss = ωC/Q ≈ 3.14e10 · 2.25e-13 /
7 ≈ 1.0 mS (R_p ≈ 1.0–1.3 kΩ), so the pair owes ≈ 3 mS of negative
conductance at worst. Every candidate device class in #33's decision
space clears that: an SiGe HBT's gm/I of ≈ 20–38/V at moderate bias needs
≪ 1 mA per side, and a CMOS pair's ≈ 8–15/V clears it within ~0.2–0.5 mA —
both far inside row 8's budget, which is precisely why the margin, not a
current number, is the ratifiable thing here. The corner erosion that
motivates 3.0 (slow-silicon gm loss up to tens of percent; tank loss
moving with temperature) is the same movement the spec table's existing
condition cell names as the reason this row must be stated across corners.

**Precedent**: loop-gain ≥ 2–3 over corners is the standard
startup-robustness convention (Razavi's oscillator start-condition
treatment; Ham & Hajimiri's design-margin passes) — the bar between
"oscillates on paper, stalls on silicon" and later file friction this
spec cannot afford. This row ratifies the **requirement** (the SF); which
device supplies the gm — HBT vs CMOS, and its bias — is #33's decision,
not this record's.

### Row 7 — Output swing: OPEN, explicitly

Differential swing into a stated load depends on the pair topology's
current-limited-vs-supply-clipped regime (row 0/ issue #33's device class
and rail) and on the buffer presence the row's condition cell itself
demands as a stated assumption. Ratifying a Vpp figure before the rail
decision — 1.2/3.3 V CMOS clips near half the supply differential; an HV
HBT pair on a wider rail may not clip at 1 V at all — binds a number to a
topology that doesn't exist yet. **OPEN pending #33** (the next record
that touches this table will likely set this one and its supply parent
together), with the survives-regardless requirement that the row was
already written with: the load and buffer state must be stated alongside
any eventual swing number, or the number is void.

### Row 8 — Supply current / power: RATIFIED (target) — ≤ 10 mW core (≤ 5 mW stretch)

**Target**: core (oscillator pair + tank bias, no output buffer) DC power
≤ 10 mW at nominal rail ±10 %, band center, nominal temperature; stretch
≤ 5 mW. Bias/off-state legs of a sleep-banked variant don't exist in DR-001's
v1 scope, so "core" is unambiguous here.

**Arithmetic**: the two currents that set power, grounded above: start/hold
gm from row 6 (≈ 3 mS worst-corner small-signal, ≤ ~1 mA per side across
all candidate device classes) plus the current that sustains the swing
row 4's estimate presumes — at 10 mW even a 3.3 V-rail design has ≈ 3 mA
available, which current-limits well past ≈ 1 Vpp differential into R_p of
≈ 1 kΩ; at the 1.2 V rail (all-HVT CMOS variant), ≈ 8 mA — the same swing
at half the I. The ≤ 10 mW ceiling is thereby demonstrated-plausible from
both candidate topologies with margin, without depending on #33's choice,
and matches the 2–10 mW band published 5 GHz-class 130 nm LC-VCO
demonstrators commonly report — set at the demonstration-class end, per
this canary's purpose.

**What is explicitly not decided here**: the absolute supply rail (row 0),
buffer inclusion (row 7), whether the stretch is reachable with HBT bias
headroom at low rail — those ride #33.

### Row 9 — Supply sensitivity (pushing): RATIFIED (target) — ≤ 50 MHz/V (≤ 20 MHz/V stretch)

**Target**: f₀ shift per volt of supply perturbation ≤ 50 MHz/V
(≈ 1 % of f₀ per volt) at band center, small-signal pushing measure;
stretch ≤ 20 MHz/V.

**Precedent + mechanism**: ≤ ~1 % f₀/V is a conventional VCO pushing
requirement level (what a VCO feeding a PLL loop budget generally must
not exceed), set here as a flat MHz/V number scaled to the row-1 band.
The pushing mechanism is topologically specific — DR-001 already names
its main path for THIS design (supply disturbance coupling through the
varactor's Vctrl node into the tank), and the rest comes through
supply-dependent device parasitics of a pair selected in #33 — the row's
condition cell already requires the coupling path to be *stated with any
eventual measured number*, and that requirement stays.

**The named uncertainty**: this is one of two rows (with row 4's
estimator half) where the mechanism can be named but no component of the
measurement exists in this repo yet — the target is precedent-derived and
scaled, not device-derived, and this record says so. If the first
measured pushing figure lands between 20 and 50 and an operator wants the
tighter number as the binding target — that's a supersede + re-ratify, not
a quiet edit.

### Row 10 — PVT corner set: RATIFIED (target) — the PDK's own non-statistical corner grid + {-40, +27, +125} °C, supply at ±10 %

**Target**: the binding corner set is the PDK's own non-statistical corner
model set as it is already enumerated across this repo's three `sim/`
studies' PVT grids — device families: 5 MOS corners
(tt/ss/ff/sf/fs), 3 junction-diode, 3 MIM (`cap_typ`/`cap_bcs`/`cap_wcs`)
— the HBT family's own corner set (the PDK ships one; the studies pin its
library by content-hash in every record) joins this list when and only
when #33 lands a topology that uses it — crossed with temperatures
{−40, +27, +125} °C, and supply voltage at ±10 % of the row-0 rail once
row 0 lands (the supply sub-corners ride #33).

**Ground**: these are not chosen corners — they are the corner models the
PDK v0.3.0 actually ships and the three studies already used, so every
ratified row's "at every bound corner" means a corner a committed
testbench can actually instantiate, per `spec/review-bar.md`'s
reproducibility bar, verified across every study — and the temperature
triplet exactly matches row 11's range, so the spec and its environment
envelope agree by construction.

### Row 11 — Operating temperature range: RATIFIED (target) — −40 °C to +125 °C

**Target**: ambient operating range −40 to +125 °C (the corner triplet
row 10 ratifies) — so "does it still tune/start/meet its bounds at the
edges" is a specified-and-derivable claim (the PVT corners row 10 settles
are exactly range-referenced).

**Ground**: the temperature triplet the studies already swept, over the
PDK's own library heads, is exactly this range; nothing else in this repo
characterizes devices to a different envelope. Choosing a narrower
physical (e.g., automotive freeze-out) bound would orphan the very corner
models row 10 ratified.

## Alternatives considered

- **Ratify all 12 rows now, closing the table fully.** Rejected. Rows
  0/3/7 are gated on decisions that do not exist yet (#33's topology is
  being authored concurrently; tank sizing is schematic-time work;
  the buffer decision rides the same gate). Ratifying numbers for them
  would be inventing values to fill a table — exactly what this repo's
  `CLAUDE.md` cardinal rule ("no number is presented as final ... every
  cell is closed by a `sim/` evidence record and a decision record, or it
  stays blank") forbids, applied to the row level.
- **Leave all 12 rows DRAFT until every one is measurable.** Rejected for
  the same reason `sky130-comparator` DR-002 rejected it: the ratification
  prerequisite (the tank study the spec table was parked on) has landed,
  nine rows are now derivable from recorded device data + shown
  arithmetic + stated precedent, and the issue itself names the cost of
  waiting ("until the table binds, no amount of simulation can be cited
  toward bronze"). Blocking nine grounded rows on three gated ones is
  exactly the silence-first posture this issue was filed to end.
- **Ratify only the rows with direct device data (1, 2, 5, 10, 11) and
  leave rows 4/6/8/9 open as "not yet derivable".** Rejected. Each of
  4/6/8/9 is derivable today by named, standard, re-checkable engineering
  arithmetic from the same recorded data (Leeson over measured-Q tank;
  startup-SF from the ωC/Q loss arithmetic demonstrated above; power
  ceiling beneath both #33 options; pushing convention scaled to band),
  and the issue is explicit that unmeasured rows should be **ratified as
  targets and said so** — these four are precisely that case. Deferring
  them would soften the guardrail's stated purpose: "set the targets
  **now**, before simulation exists to be tempted by."
- **Guess the row-0 supply/rail from HBT-bias precedent and ratify it
  anyway.** Rejected — issue #33 is actively deciding exactly this with
  the same data (a low-Q tank demanding gm margin is its stated deciding
  factor), and ratifying ahead of it would manufacture the appearance of
  a decided topology where none exists.
- **Use the analytic model's inductor Q (Q@10 GHz ≈ 5) instead of the EM
  extraction, to ratify a 10 GHz band.** Rejected — the EM record exists
  precisely because the analytic model overstates Q and understates SRF
  in this band, its own error bars predicted both directions, and its
  "10 GHz is fine SRF-wise" answer is the exact claim the EM extraction
  reversed. Ratifying against the superseded model would be building the
  spec on a number the repo already measured as wrong.

## Spec lines affected

`spec/target-spec.md`:

- **Header Status field**: changes from "DRAFT — nothing below is
  ratified" to a partial-ratification statement citing this record, with
  the mechanism path (ratification-via-PR per 2am#357) named in the header
  alongside the still-absent two-key tree.
- **"How to read this file" / "Why every cell is blank" prose**: the
  status-column description in "How to read this file" is rewritten to the
  RATIFIED (target) / OPEN statuses; the "Why every cell is blank in this
  pass" section is kept verbatim for history with a dated
  "Updated 2026-09-21 (DR-003)" paragraph appended marking it
  superseded-in-part; the cardinal rule itself is unchanged.
- **Summary table rows** (per dispositions above):
  - **Rows 1/2/4/5/6/8/9/10/11**: numeric target cells filled (or
    enumerated-set cell for row 10), each condition cell completed, status
    cell changes DRAFT → **"RATIFIED (target) per DR-003"** — binding,
    no measurement claimed.
  - **Rows 0/3/7**: status cell changes DRAFT → **"OPEN per DR-003"**
    with its gate (row 0: #33's supply choice; row 3: tank sizing at
    schematic time; row 7: #33 + buffer) named in the condition cell —
    explicitly not silently DRAFT.
- No other file in the repo is edited by this PR. In particular the
  **gap-to-T1 tracker (#3) is not edited as part of its diff** — issue
  #35's "update the tracker's item-5 row" criterion is satisfied by this
  sweep's post-merge pass (issue #3's own convention checkboxes update
  **after** evidence lands, and a merged PR is the evidence), not by
  pre-checking against an unmerged draft.

## Consequences

1. **T1 item 5's spec-ratification precondition is cleared for nine
   rows.** Verdicts against a draft spec were provisional; verdicts
   against these nine targets are meaningful once their PVT pass exists,
   with rows 0/3/7 carrying explicit gates rather than blocking the
   table. Items 6/7/8 grading against spec rows can point at the bound
   rows they actually grade against.
2. **The design now has committed numbers to be held to.** The first
   `design/vco.sch` pass inherits the 5 GHz-class band, the 6-loaded /
   7-central-Q budget, the 3.0 gm safety factor, the phase-noise and
   pushing ceilings, and the corner grid — sim-first design work can
   start grading itself before its first oscillator measurement exists,
   which is the point of ratification-before-measurement.
3. **Two rows are now bound in a specific tension the record names.**
   Row 2's stretch (a 20 % range) and row 5's target (Q ≥ 6) compete for
   the same fixed-C/varactor split; the parallel-small-cell route through
   the measured data (44.8-varactor-Q preserved under parallelism) is the
   constraint this record places on how a later design resolves it.
   Resolving the tension differently is a supersede, not a re-interpretation.
4. **The three OPEN rows are procedurally bound, not just parked.** Row 0
   cannot silently appear in a later schematic PR's netlist as a decided
   1.2 V/3.3 V number without a decision record behind it — which forces
   the #33 record and any rail it touches to be explicit, the same
   discipline `spec/README.md`'s one-DR-per-change rule provides.
5. **No measurement is downgraded.** Nothing here asserts any measured
   performance of any oscillator; every RATIFIED (target) row labels
   itself a target, and rows rated against them (future PVT passes graded
   under T1 items 5/6/7) cite their own per-corner evidence records — the
   append-only convention `sim/README.md` already enforces.
6. **This record explicitly does not self-ratify.** Its merge is the
   two-key mechanism acting (Judge review = the review key held by
   Champion/operator processes; Champion/operator merge = the deciding
   key), per the 2AMLogic/2am#357 ruling cited by issue #35 — the status
   prose and the known-wart handling above carry that, so a later reader
   is not misled by whatever the `Status:` field itself fails to say.

## Open items

- **Row 0 (supply) + row 7 (swing)**: gated on #33's negative-gm pair
  architecture record, in flight as this one is drafted. Its landing
  record supersedes-in-part this one for rows 0/7 or amends them explicitly.
- **Row 3 (Kvco absolute)**: lands with the tank-sizing pass in the
  schematic issue (the same issue that consumes #33's decision); the
  qualitative monotonicity + Vctrl-window requirement stands regardless.
- **Row 4 (estimator method choice)**: the transient-spectral vs ISF
  choice is made by the phase-noise testbench issue when it is filed,
  with CLAUDE.md's method-requirement closing around whichever lands.
- **Row 4/9 stretch bounds**: flagged revisit-likely in their sections;
  stretch bounds should be re-examined once the first measurements exist
  rather than discarded quietly.
- **Row 10: HBT corner enumeration** joins the ratified list only when a
  topology that uses the PDK's bipolar devices is actually chosen.
- **The two-key tree** remains absent repo-wide (2AMLogic/product#135,
  fleet-scoped); nothing here installs it, and nothing here needs it —
  but a future pass that installs it fleet-wide should state whether the
  ratification-via-PR path (the one exercised here) is retired by it.
- **The `Status:`-staleness wart**: whether a merged ratification PR
  should update the record's own `Status:` field is a
  2AMLogic/product#135 decision, not this repo's; until settled, this
  record's prose (see Status bullets) is the operative statement.

## Sources

- `spec/target-spec.md` (the table this record disposes, rows 0-11 and
  its Status header)
- `spec/decision-records/DR-001-tuning-mechanism.md` (tuning device,
  Vctrl domain, band-switching decision, per-geometry C/Q data and
  the parallel-cell Q-preservation evidence its record cites)
- `spec/decision-records/TEMPLATE.md` (numbering/collision rule — see
  Numbering note; status lifecycle)
- `sim/tank-characterization/README.md` + records `20260906-135025-d3410d1`,
  `20260906-160246-a73c3c7` (findings 1-7; MIM Q/SRF/temp/process data)
- `sim/inductor-model/em-extraction/README.md` + record
  `20260910-052657-3896421` (EM-measured L/Q/SRF for `p1`/`p11`/`p13`;
  "What this means for the tank")
- `sim/varactor-characterization/` + record `20260909-231619-de50891`
  (per-geometry Cmax/Cmin, dC/dV, Q(V,f), including Q at 5 GHz for
  `mos_small`/`mos_mid`)
- `sim/pdk.json` (PDK v0.3.0 pin and known model gaps, including the
  absent ngspice inductor model that forced the EM route)
- 2AMLogic/2am#357 (2026-08-19 ratification-via-PR ruling) — the
  two-key mechanism path this record exercises
- 2AMLogic/product#135 (two-key tree absent fleet-wide; `Status:` staleness
  wart; `sky130-comparator` PR #29 as the documented prior ratification
  via PR)
- `2AMLogic/sky130-comparator` `spec/decision-records/DR-002-target-spec-ratification.md`
  (this fleet's worked example for a partial ratification: three rows
  ratified, two left open "explicitly, not silently")
- Leeson, D. B., "A Simple Model of Feedback Oscillator Noise Spectrum,"
  *Proceedings of the IEEE*, 1966 — the first-pass phase-noise model row
  4's arithmetic uses
- Hajimiri, A. and Lee, T. H., "A General Theory of Phase Noise in
  Electrical Oscillators," *IEEE JSSC*, 1998 — the ISF framework this
  repo's CLAUDE.md names canonical, of which Leeson's model is the
  frequency-domain simplification, row 4 eventually grades against
- Issues #2 (target-spec draft), #3 (gap-to-T1 tracker, item 5), #31
  (DR-001's issue), #33 (in-flight pair topology record), #35 (this
  record's issue; scope and guardrail quotes above are its text)
