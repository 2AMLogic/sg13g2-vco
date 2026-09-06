# LC-VCO target specification

- **Status: DRAFT — nothing below is ratified.** Per this repo's own
  `CLAUDE.md` ("Tank first"), numeric bounds stay blank until the
  spiral-inductor / MIM-cap tank-characterization study lands in `sim/`.
  This document's job at this stage is the **row structure** — what gets a
  min/typ/max, per corner, and what evidence closes it — not a set of
  numbers to defend. A future decision record (`spec/decision-records/
  DR-NNN-*.md`) ratifies each row once its supporting `sim/` evidence
  exists; ratification flows through the two-key mechanism (EE key +
  market key). A scope-only spec DR ratified with both keys needs no
  per-PR operator statement (generalized ruling, 2026-08-28, cited in
  issue #2).
- **Date**: 2026-09-06 (drafted, issue #2)
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

Every row states: the **parameter**, its **min/typ/max** (blank — pending
the tank study, per the Status note above), the **stated measurement
condition** required to fill it in (offset frequency for phase noise,
load for output swing, etc. — a number without its condition is not
fillable later without re-deriving the condition too), and a **status**
column that is uniformly `DRAFT — blank pending tank study` for every row
in this pass.

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

---

## Summary table

Every row's status is uniformly **DRAFT — blank pending tank study**.

| # | Parameter | Min | Typ | Max | Corner / condition (to be stated when filled) | Status |
|---|---|---|---|---|---|---|
| 0 | Supply voltage / device flavor | | | | SG13G2 offers 1.2 V core CMOS, 3.3 V thick-oxide CMOS, and SiGe HBT bias/tail options — this row picks the tank pair's own supply, which need not match a future digital domain | DRAFT — blank pending tank study |
| 1 | Center / target band | | | | Set by the characterized tank's self-resonant frequency (SRF) region, not chosen independently of it — see `spec/porting-plan.md` §2 | DRAFT — blank pending tank study |
| 2 | Tuning range (Kvco integral) | | | | Varactor choice (MOS accumulation vs. junction) and any band-switching scheme, stated together — see `spec/porting-plan.md` §3 | DRAFT — blank pending tank study |
| 3 | Kvco (small-signal slope) and its linearity across the tuning range | | | | Stated per band if band-switched; a single Kvco number without a stated Vctrl window is not fillable | DRAFT — blank pending tank study |
| 4 | Phase noise at a stated offset (e.g. `L(Δf)` at 1 MHz and 10 MHz offsets from carrier) | | | | **Must state its measurement method** per this repo's own CLAUDE.md — transient length, window, and spectral estimator, or an ISF/impulse-sensitivity derivation, plus the method's known variance and limits. ngspice has no PSS/pnoise; a number without its method is not a result | DRAFT — blank pending tank study; method not yet chosen |
| 5 | Tank quality factor (Q) at the target band | | | | Directly from the tank-characterization study (`sim/`); this is the input the tuning-range and phase-noise rows above depend on, not an independent claim | DRAFT — blank pending tank study |
| 6 | Startup / negative-gm margin (`g_m` provided vs. tank loss required to start and sustain oscillation) | | | | Stated across process/temperature corners since tank loss and active-device `g_m` both move with corner | DRAFT — blank pending tank study |
| 7 | Output swing (differential, into a stated load) | | | | Load capacitance and buffer topology (if any output buffer exists) must be stated alongside the swing number | DRAFT — blank pending tank study |
| 8 | Supply current / power | | | | Do not scale by V² from any other repo's ring-VCO number — different topology, different device class entirely (see `spec/porting-plan.md` §1) | DRAFT — blank pending tank study |
| 9 | Supply sensitivity (pushing, MHz/V) | | | | An LC tank's pulling/pushing mechanism (varactor Vctrl coupling to supply noise) differs structurally from a current-starved ring's; do not assume the PLL siblings' row/budget shape ports without re-deriving the mechanism | DRAFT — blank pending tank study |
| 10 | PVT corner set | | | | To be settled against SG13G2's own PDK corner model set (may not mirror the PLL siblings' corner counts) — see `spec/porting-plan.md` §1 | DRAFT — not yet settled |
| 11 | Operating temperature range | | | | | DRAFT — not yet settled |

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
