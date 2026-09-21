# LC-VCO target specification

- **Status: PARTIALLY RATIFIED — 9 target rows, 3 explicitly open
  (DR-003, pass 1).** The tank study this table's 2026-09-06 draft waited
  on ("Tank first" per `CLAUDE.md`) has landed in `sim/`, and decision
  record `spec/decision-records/DR-003-target-spec-ratification.md`
  (issue #35) has disposed every row: **rows 1, 2, 4, 5, 6, 8, 9, 10, 11
  are RATIFIED as targets** — binding numbers derived from recorded
  device data and stated engineering arithmetic, **explicitly not met by
  any measurement** (no oscillator exists yet) — and **rows 0, 3, 7 are
  OPEN with named gates** (the #33 negative-gm pair architecture record,
  in flight; tank sizing) rather than silently DRAFT. Ratification
  flows per the 2026-08-19 ratification-via-PR ruling
  (2AMLogic/2am#357, cited by issue #35): the record PR's Judge review
  plus Champion/operator merge is the two-key mechanism, because this
  repo has no `ratification/` tree (2AMLogic/product#135). Per
  `CLAUDE.md`, agents do not relax a ratified row to make results pass —
  changing one requires a superseding decision record, in public.
- **Date**: 2026-09-06 (drafted, issue #2); 2026-09-21 partially ratified
  (DR-003, issue #35)
- **Written by**: Builder agent, issue #2
- **Block class**: single free-running LC voltage-controlled oscillator
  (not embedded in a PLL in this repo's own scope — see
  `spec/porting-plan.md` for how sg13g2-pll's PLL-embedded VCO subblock
  differs).
- **Port relationship**: **not a port.** No sibling repo in this catalog
  has an LC-tank VCO; the ring/CMOS VCOs inside `sg13g2-pll`, `sky130-pll`,
  and `gf180-pll` are architecturally different oscillators (see
  `spec/porting-plan.md` §1 for the disposition on why the ring topology
  itself does not carry over). Rows below are seeded from the LC-VCO
  literature (Hajimiri & Lee's ISF phase-noise framework — the canonical
  citation this repo's own `CLAUDE.md` names) and the general shape of
  what an LC-VCO spec table states, not from a measured sibling value.

---

## How to read this file

Every row states: the **parameter**, its **min/typ/max** (target bounds
where DR-003 ratified the row; blank where it left the row open), the
**stated measurement condition** required to grade it (offset frequency
for phase noise, load for output swing, etc. — a number without its
condition is not gradeable later without re-deriving the condition too),
and a **status** column: `RATIFIED (target) per DR-003` for the nine rows
pass 1 ratified, `OPEN per DR-003` for the three rows it gated
explicitly. DR-003 is the row-by-row record of every disposition.

**The cardinal rule for this file** (same rule sky130-pll's and
gf180-pll's own target-spec files state): no number is presented as
final, and no row is filled in by inventing a plausible value — every
cell is closed by a `sim/` evidence record and a decision record, or it
stays blank.

### Why every cell is blank in this pass

This repo's `CLAUDE.md` is explicit: *"Tank first. Characterize the PDK's
shipped spiral-inductor and MIM-cap models (L, Q, SRF across the band)
before sizing the pair; commit that study to `sim/` — every later
tuning-range and phase-noise claim leans on it."* No such study exists
yet (`sim/` contains only its scaffold `README.md` as of this issue). A
target-spec row that pre-committed a tuning range or a phase-noise number
ahead of that data would be exactly the "numbers without methods are not
results" failure this repo's own CLAUDE.md forbids — so this issue's
contribution is the table's **shape**, deliberately not its numbers.

**Updated 2026-09-21 (DR-003, issue #35).** The study this section waited
on has landed: `sim/tank-characterization/` (#5), `sim/inductor-model/`
including the openEMS EM extraction of the PDK's own inductor PCell
(#6/#8/#9/#11/#23), and `sim/varactor-characterization/` (#18/#19)
consumed by DR-001. The precondition for filling cells is therefore met,
and pass 1 of ratification (DR-003) filled the nine cells its recorded
device data and stated arithmetic support — as **targets**, per issue
#35, not as met values — leaving rows 0/3/7 explicitly open. The
paragraph above is kept verbatim for history: it was true as of the
2026-09-06 draft, and it is the reason no cell here was filled before its
supporting evidence existed. The rule itself stands unchanged and now
governs the open rows: no open cell is filled by inventing a plausible
value.

---

## Summary table

Nine rows are **RATIFIED (target) per DR-003** — binding, not met by any
measurement. Three rows are **OPEN per DR-003** with named gates. Every
disposition, its evidence, and its arithmetic is recorded in
`spec/decision-records/DR-003-target-spec-ratification.md`.

| # | Parameter | Min | Typ | Max | Corner / condition (to be stated when graded) | Status |
|---|---|---|---|---|---|---|
| 0 | Supply voltage / device flavor | | | | The tuning device's own `Vctrl` domain is decided: `spec/decision-records/DR-001-tuning-mechanism.md` — full 0.0–3.3 V HV thick-oxide range, driving `sg13_hv_svaricap`'s well/substrate node. The negative-gm pair's own supply flavor is a separate, not-yet-made decision (`spec/porting-plan.md` §2) and is not fixed by DR-001 — it is the pending #33 record's to make | **OPEN per DR-003** — pending the #33 negative-gm pair architecture record (device class + rail); its landing record sets this row |
| 1 | Center / target band | 4.5 GHz | 5.0 GHz | 5.5 GHz | Ratified from the EM extraction (record `20260910-052657-3896421`): measured SRF 9.42 GHz (`p11`) / 8.07 GHz (`p13`) excludes a ~10 GHz tank outright (a carrier there runs past the inductor's own SRF), and the multi-turn EM Q plateaus across 2–5 GHz instead (`p11`: 9.49 @ 2 GHz, 10.28 @ 5 GHz, ±10 % convergence bar). Window keeps ≥ 1.7× SRF margin at its top end over the geometry, ≥ 2.09× over `p13`'s SRF across the whole window. MIM ±10 % process spread on C (≈ ∓5 % on f₀) grades inside the window at the corners row 10 settles | **RATIFIED (target) per DR-003** — binding, not met |
| 2 | Tuning range (Kvco integral) | ≥ 15 % | | (≥ 20 % stretch) | Fractional tuning, f_max/f_min ≥ 1.15 (stretch ≥ 1.20), across the full 0.0–3.3 V domain (DR-001: `sg13_hv_svaricap`, measured `Cmax/Cmin` 1.88–2.08x, no band-switching bank in v1), band-center referenced. Achievability arithmetic (DR-003 §Decision 2): with fixed C `F` and varactor `V` at Vctrl=0, ≥ 15 % needs F ≤ 0.92·V — the fixed-C budget (MIM + parasitics) must stay under ~half of C_tot for the stretch, a named risk no `sim/` evidence measures yet | **RATIFIED (target) per DR-003** — binding, not met |
| 3 | Kvco (small-signal slope) and its linearity across the tuning range | | | | Device and `Vctrl` domain decided (`spec/decision-records/DR-001-tuning-mechanism.md`); the `dC/dV` kernel is measured per `sim/varactor-characterization/records/20260909-231619-de50891-kvco.csv`, but the absolute Kvco (Hz/V) follows from the fixed-C/varactor split the tank-sizing pass makes at schematic time — not yet performed. Stated per band if band-switched (DR-001: not adopted in v1); a single Kvco number without a stated Vctrl window is not fillable. Surviving requirement regardless: Kvco is graded as a Vctrl-window-referenced slope/curve, monotonic where the measured dC/dV is | **OPEN per DR-003** — pending tank sizing in the schematic pass; kernel data already recorded |
| 4 | Phase noise at a stated offset (e.g. `L(Δf)` at 1 MHz and 10 MHz offsets from carrier) | | | ≤ −105 dBc/Hz @ 1 MHz (target); ≤ −115 (stretch) | Primary offset 1 MHz from a band-center carrier; at 10 MHz offset the companion bounds are ≤ −125 target / ≤ −135 stretch (1/f² region). **Must state its measurement method** per this repo's own CLAUDE.md — transient length, window, and spectral estimator, or an ISF/impulse-sensitivity derivation, plus the method's known variance and limits; ngspice has no PSS/pnoise and the estimator choice is an explicit open item of the phase-noise testbench issue. Basis (DR-003 §Decision 4): Leeson first-pass over this tank's measured band and Q — ≈ −113 dBc/Hz @ 1 MHz at Q = 7, P ≈ 0.2 mW, F ≈ 2 — leaving ≈ 8 dB margin under the target; the stretch sits 2 dB beyond the estimate and is flagged revisit-likely | **RATIFIED (target) per DR-003** — binding, not met; method choice open |
| 5 | Tank quality factor (Q) at the target band | ≥ 6 | | (≥ 8 stretch) | Loaded tank Q at 5.0 GHz band center — including every element that loads the tank in the as-designed schematic (varactor, MIM, parasitics, bias network), over the corners row 10 settles. Basis (DR-003 §Decision 5): EM-measured inductor Q 10.28 @ 5 GHz (`p11`, ±10 % bar — a measured extraction, not the analytic upper bound) combined per 1/Q ≈ Σ share/Q with the parallel-small-cell varactor bank (Q 44.8 @ 5 GHz at V=0, preserved under parallelism per the `mos_xlarge` evidence) and MIM (Q ≳ 140 at band center) — ≈ 8.8 illustrative. **Named constraint**: tuning capacitance realized as parallel small-geometry cells; a `mos_mid`-class bank (Q 2.73 @ 5 GHz) loads the tank to ≈ 4 and misses this row — the row-2/range vs row-5/Q tension DR-003 records | **RATIFIED (target) per DR-003** — binding, not met |
| 6 | Startup / negative-gm margin (`g_m` provided vs. tank loss required to start and sustain oscillation) | ≥ 3.0 | | | Startup safety factor: the pair's total g_m ≥ 3.0 × the tank's loss conductance, **at every bound corner of the row-10 set** — tank loss and active-device g_m both move with corner, which is why the margin, not a nominal-current number, is the ratified quantity. At the illustrative sizing G_loss ≈ 1.0 mS (ωC/Q at 225 fF, Q 7), i.e. the pair owes ≈ 3 mS worst-corner; every device class in #33's decision space clears that well inside row 8's budget. Which device supplies the g_m is #33's decision, not this row's | **RATIFIED (target) per DR-003** — binding, not met |
| 7 | Output swing (differential, into a stated load) | | | | Load capacitance and buffer topology (if any output buffer exists) must be stated alongside the swing number. The swing regime itself (current-limited vs supply-clipped) depends on the pair rail row 0 gates on — 1.2/1.8/3.3 V CMOS classes clip at very different Vpp than an HV HBT pair, and a target picked now would bind a number to a topology the #33 record has not chosen yet | **OPEN per DR-003** — pending #33 (pair topology + rail) and the buffer decision; the stated-load requirement survives regardless |
| 8 | Supply current / power | | | ≤ 10 mW core (target); ≤ 5 mW (stretch) | Core (oscillator pair + tank bias, no output buffer) DC power at nominal rail, band center, nominal temperature. Do not scale by V² from any other repo's ring-VCO number — different topology, different device class entirely (see `spec/porting-plan.md` §1). Basis (DR-003 §Decision 8): row-6 start/hold current (≤ ~1 mA per side across all candidate device classes) plus swing-sustaining current — ≈ 3 mA available at 10 mW even on a 3.3 V rail, current-limiting well past 1 Vpp into R_p ≈ 1 kΩ — so the ceiling is demonstrated-plausible for both candidate topologies without depending on #33's outcome; rail itself pending row 0 | **RATIFIED (target) per DR-003** — binding, not met |
| 9 | Supply sensitivity (pushing, MHz/V) | | | ≤ 50 MHz/V (target); ≤ 20 MHz/V (stretch) | Band-center small-signal pushing, ≈ 1 % f₀ per volt — a conventional VCO pushing requirement level, scaled to the row-1 band by DR-003 (precedent-derived, not device-derived: the record says so explicitly). Coupling path per DR-001: supply disturbance entering chiefly through `sg13_hv_svaricap`'s well/substrate `Vctrl` node plus supply-dependent pair parasitics; the coupling path must be **stated with any measured number**, and the first measurement between the bounds triggers a supersede-or-uphold decision, not a quiet edit | **RATIFIED (target) per DR-003** — binding, not met |
| 10 | PVT corner set | (enumerated in condition) | | | The PDK's own non-statistical corner model set as already used across this repo's three `sim/` studies: MOS tt/ss/ff/sf/fs (5), junction-diode ×3, MIM `cap_typ`/`cap_bcs`/`cap_wcs` — the HBT family's own corner set joins iff #33 lands a topology using it — crossed with temperatures {−40, +27, +125} °C, and supply voltage at ±10 % of the row-0 rail once row 0 lands (sub-corners ride #33). The corner triplet exactly spans the row-11 range, so spec and environment envelope agree by construction; no PLL-sibling count is inherited (see `spec/porting-plan.md` §1) | **RATIFIED (target — set) per DR-003** — binding; supply sub-corners ride row 0 |
| 11 | Operating temperature range | −40 °C | | +125 °C | Ambient operating range; the triplet row 10 ratifies is exactly this envelope — the same temperatures over which the PDK's corner libraries are already characterized across the three `sim/` studies, so "meets bounds at the edges" is instantiated by a committed testbench per `spec/review-bar.md`, not by an invented colder/hotter bound the corner models can't grade | **RATIFIED (target) per DR-003** — binding, not met |

---

## Sources

- This repo's own `CLAUDE.md` — "Tank first," phase-noise measurement-method
  requirement, tuning-plan honesty requirement.
- Hajimiri, A. and Lee, T. H., "A General Theory of Phase Noise in
  Electrical Oscillators," *IEEE Journal of Solid-State Circuits*, 1998 —
  the ISF (impulse sensitivity function) framework named in this repo's
  `CLAUDE.md` as the canonical phase-noise frame; cited here as the
  intended derivation method for row 4, not yet applied.
- `2AMLogic/sg13g2-pll` `spec/porting-plan.md` §2.1 ("The VCO — the block
  BiCMOS changes most") — the sibling repo's own architecture-survey
  reasoning for why an LC-tank VCO's phase-noise advantage is exactly the
  number the ngspice-based flow cannot yet substantiate; see
  `spec/porting-plan.md` in this repo for the full citation and how this
  repo's own scope differs (a standalone LC-VCO, not a PLL subblock
  optimizing for a 20:1 tuning range).
- `2AMLogic/sky130-pll` `spec/target-spec.md` — table-shape and
  "blank until ratified" convention this file follows.
- `2AMLogic/gf180-bandgap` `sim/README.md` (via `2AMLogic/sg13g2-bandgap`,
  which cites it directly) — append-only evidence-record convention that
  will back every row here once filled.
