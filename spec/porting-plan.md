# Porting / design plan: sg13g2-vco

- **Status**: planning document, produced by issue #2. It is not itself a
  ratified spec and it binds no numeric value — it names what transfers as
  *methodology* from mature siblings, what must be designed from scratch,
  and the honest reasons behind each disposition, so a future architecture
  decision record (`spec/decision-records/DR-001-*.md`) has a starting
  point instead of a blank page.
- **Date**: 2026-09-06
- **Written by**: Builder agent, issue #2
- **Sources reviewed**: `2AMLogic/sg13g2-pll` `spec/porting-plan.md`
  (in full, including §1.1 "Architecture decisions," §1.3
  "Testbench / corner-harness structure," and §2.1 "The VCO — the block
  BiCMOS changes most"); `2AMLogic/sky130-pll` `spec/target-spec.md` (table
  shape, ratification-status convention); `2AMLogic/gf180-pll`
  `spec/pll.md` and `design/README.md` (cited via sg13g2-pll's own
  citations, for the ring-VCO's constant-gm bias / geometric-band-cascade
  techniques named in §1 below); this repo's own `CLAUDE.md` and `README.md`.
- **Consumes**: nothing yet ratified in this repo (this is the first
  planning document in `spec/`, alongside `spec/target-spec.md` from the
  same issue).
- **Does not**: size any circuit, ratify any spec number, or commit to a
  varactor/band-switching choice beyond naming the open questions. Per
  issue #2: this is documentation/spec scaffolding, not design work.

---

## How to read this document

**This is explicitly not a port in the way sg13g2-pll is a port of
gf180-pll/sky130-pll.** No sibling repo in this catalog has an LC-tank
VCO — the PLL siblings' VCOs are single-ended, current-starved CMOS ring
oscillators, an architecturally different device. What *does* transfer
from the siblings is not circuit topology but **methodology**:
testbench/evidence conventions, the PVT-corner-sweep discipline, and —
most directly load-bearing for this repo's very first design decision —
an argument sg13g2-pll's own architecture survey already ran and this
repo should cite rather than re-derive from scratch.

Three sections, matching the issue's shape:

1. [What sg13g2-pll's own VCO analysis already settled for us](#1-what-sg13g2-plls-own-vco-analysis-already-settled-for-us)
   — the LC-tank-vs-ring tradeoff and the phase-noise-evidence-gap
   argument, cited directly rather than re-derived.
2. [What is design, not port](#2-what-is-design-not-port) — the tank,
   the negative-gm pair, and the tuning mechanism, none of which has a
   sibling schematic to start from.
3. [What does carry over as methodology](#3-what-does-carry-over-as-methodology)
   — testbench structure, evidence conventions, and PVT-sweep discipline,
   per-decision, with an as-is / re-derive / device-swap disposition.

---

## 1. What sg13g2-pll's own VCO analysis already settled for us

`2AMLogic/sg13g2-pll` `spec/porting-plan.md` §2.1 ("The VCO — the block
BiCMOS changes most") already ran the exact architecture-survey question
this repo would otherwise have to open from scratch: **whether a
tank-based (LC) oscillator using SG13G2's SiGe HBTs is worth considering
against a ported current-starved CMOS ring**, for a *PLL's* VCO subblock.
Its answer, quoted directly because this repo's own scope decision leans
on it:

> "SiGe HBTs are the textbook enabling device for negative-gm LC-tank
> VCOs ... at frequencies well above what a ring of the same process
> typically reaches cleanly, with materially better phase-noise
> potential — the same phase-noise advantage that made both siblings'
> `DR-001`s reject sub-sampling/injection-locked architectures
> specifically because 'the flow cannot substantiate a phase-noise
> number' ... That same evidentiary objection applies to an LC-tank VCO
> argument for SG13G2 as much as it did to sub-sampling on gf180mcu ...
> An LC-tank VCO's headline advantage is therefore exactly the number
> this flow still cannot evidence directly — so choosing it purely for
> phase noise reproduces the argument both siblings' architecture surveys
> already rejected once, on a different justification."

This repo's own `CLAUDE.md` independently states the same position
("Phase noise carries its measurement method... Numbers without methods
are not results"), arrived at without reference to sg13g2-pll's document
— the two are independent confirmations of the same evidentiary limit,
not one copying the other.

**Why this repo exists as a standalone LC-VCO anyway, despite that
objection**: sg13g2-pll's own analysis is scoped to *a PLL's VCO
subblock*, where the requirement is a wide (≈20:1), continuous tuning
range (`sg13g2-pll` `spec/porting-plan.md` §1.2 row 1, citing gf180-pll's
10–200 MHz measured band) — a range an LC tank cannot reach (a
varactor-tuned tank "commonly reaches 1.3–2:1 before quality/linearity
degrade badly," per the same §2.1). That tuning-range requirement is
what sg13g2-pll's own document names as the disqualifying factor for an
LC tank *in a PLL context*, separately from the phase-noise-evidence
objection above. This repo has no such wide-tuning-range requirement: it
exists specifically to demonstrate the LC-tank / negative-gm / SiGe-HBT
techniques that neither `sg13g2-pll` nor any ring/CMOS oscillator in this
catalog exercises (see this repo's own `README.md`: "nothing in the
catalog yet demonstrates an LC tank, a cross-coupled negative-gm pair, or
a phase-noise budget"). **Disposition, named explicitly rather than
silently assumed**: this repo commits to the LC tank *not* because it
sidesteps the phase-noise-evidence gap (it does not — see row 4 of
`spec/target-spec.md`, deliberately left with no numeric bound and an
explicit "method not yet chosen" status) but because the block's stated
purpose is to build and honestly report against exactly that gap, using
open tools, the way a canary is supposed to surface friction rather than
avoid it. Every phase-noise claim this repo ever publishes must carry its
measurement method per the objection above — this plan does not resolve
that; `spec/target-spec.md` row 4 tracks it as still open.

---

## 2. What is design, not port

None of the following has a sibling schematic anywhere in this catalog to
start from. Naming them here is scoping, not sizing — no number is
committed.

| Item | Disposition | Why no port exists | Where the design work lands |
|---|---|---|---|
| LC tank (spiral inductor + MIM cap) | **Design, from PDK passive models directly** | No sibling repo has an LC tank; this is the study this repo's own `CLAUDE.md` requires first ("Tank first") | A `sim/` tank-characterization study (L, Q, SRF across the candidate band) — not yet started as of this issue |
| Negative-gm cross-coupled pair (device class: CMOS pair vs. SiGe HBT pair vs. Colpitts) | **Design, from LC-VCO literature** | No sibling has a negative-gm topology of any kind; the ring VCOs' constant-gm bias core (§3 below) is a different circuit function entirely | A future architecture decision record, informed by the tank study's Q and SRF data (a low-Q tank needs more gm margin, which favors a device class with more gm per unit bias current) |
| Varactor / tuning mechanism (MOS accumulation-mode vs. junction varactor; band-switching capacitor bank or none) | **Design, open question** | Neither ring-VCO sibling has a varactor at all (ring tuning is via current starving, an unrelated mechanism) | Named as an open row (`spec/target-spec.md` row 2) — this issue states the *question* honestly, does not answer it |
| Phase-noise measurement method (long transient + spectral estimator, vs. ISF/impulse derivation) | **Design, open question, explicitly deferred** | ngspice has no PSS/pnoise for any oscillator, ring or tank; sg13g2-pll's own `DR-002` Decision 5 (cited via its `porting-plan.md` §1.2 row 9) "deliberately not spec'd" phase noise for exactly this reason, and this repo's `CLAUDE.md` doubles down: a number without its method is not a result | Named as an open row (`spec/target-spec.md` row 4), no method chosen in this pass |

---

## 3. What does carry over as methodology

This is the only category where "port" is the right word — none of it is
circuit-specific, and every item below is a convention both PLL siblings
(and `sg13g2-bandgap`) already converged on independently, per
`sg13g2-pll` `spec/porting-plan.md` §1.3 ("the highest-confidence 'as-is'
category in the whole document — it is methodology, not circuit data").

| Item | Disposition | Basis | Citation |
|---|---|---|---|
| Append-only evidence records: `sim/<slug>/{testbench,netlist-snapshots,corners,records}/`, a new record ID per run, records never edited in place | **As-is** | This repo's own `CLAUDE.md`: "`sim/` results are append-only evidence" — independently states the identical convention | `sg13g2-pll` `spec/porting-plan.md` §1.3, citing `gf180-pll` `sim/README.md` (itself from `gf180-bandgap`) |
| One experiment directory per distinct claim under test (tank study, tuning-range sweep, startup-margin sweep, phase-noise method study, each its own `sim/` slug) | **As-is** | Methodology-only; independent of device class | `sg13g2-pll` `spec/porting-plan.md` §1.3 |
| Full PVT corner matrix as the default sweep, with an explicit stated reason for any subset | **As-is as a policy; the actual corner set is process-specific** — SG13G2's own PDK corner model set may not mirror the PLL siblings' bundle/corner counts, and this repo has no active/digital-logic corner axis a ring VCO's divider chain would add | This repo's own `CLAUDE.md`: "PVT corners on every recorded result" | `sg13g2-pll` `spec/porting-plan.md` §1.3 |
| Netlist provenance discipline: every record freezes the exact netlist it simulated, independent of the live `design/` export | **As-is** | Generic evidence-integrity convention | `sg13g2-pll` `spec/porting-plan.md` §1.3 |
| Per-block file organization: one `.sch`/`.sym` per cell, matching `tb_<block>` testbenches | **As-is** | Generic xschem/ngspice-flow convention, independent of topology | `sg13g2-pll` `spec/porting-plan.md` §1.3 |
| Constant-gm (beta-multiplier) style bias-core *technique* | **Device-swap, re-derive sizing — informational only, not assumed to apply** | A negative-gm LC pair's own bias needs may differ from a ring's current-starving bias; named here as a technique worth evaluating, not a commitment | `sg13g2-pll` `spec/porting-plan.md` §1.4, citing `gf180-pll` `design/README.md` § "The VCO" |
| Geometric (not binary-weighted) band-cascade technique, if band-switching is adopted | **Device-swap, re-derive — conditional on the varactor/band-switching decision (§2 above) landing on a switched-capacitor bank at all** | Same rationale gf180-pll's ring used it for (uniform coverage across steps) transfers structurally to a capacitor bank, but is not assumed without the tuning-mechanism decision first | `sg13g2-pll` `spec/porting-plan.md` §1.4 |

---

## 4. Review-bar note

See `spec/review-bar.md` for the one-command-characterization +
README-reproducibility bar this block commits to from day one, and the
gap-to-T1 tracker issue (linked below) for how it is checked.

## 5. Gap-to-T1 tracker

The artifact-presence checklist against the klayout-tools design-evidence
ladder (T1 — sim-validated) for this block is tracked as a separate
GitHub issue, filed via `./.loom/scripts/create-issue.sh` per this repo's
forge-write convention: **#3** (opened from this issue, `loom:triage`).
It cross-links back to this document; this document cross-links to it
here rather than duplicating its checklist.

---

## Sources

- `2AMLogic/sg13g2-pll` `spec/porting-plan.md` — §1.1, §1.3, §1.4, and
  especially §2.1 ("The VCO — the block BiCMOS changes most"), cited
  directly and at length in §1 above.
- `2AMLogic/sky130-pll` `spec/target-spec.md` — table-shape and
  ratification-status convention.
- `2AMLogic/gf180-pll` `spec/pll.md` and `design/README.md` — cited via
  sg13g2-pll's own citations for the ring-VCO bias/band-cascade
  techniques named in §3.
- `2AMLogic/sg13g2-bandgap#4` — the gap-to-T1 tracker shape this repo's
  own tracker (#3) follows, including its "a checked box means the
  artifact exists, not that it passes" framing and its append-only
  "Verified corrections" convention.
- `klayout-tools/docs/design-evidence-tiers.md` (`2AMLogic/klayout-tools`,
  `main`) — the T1 definition the gap-to-T1 tracker checks against.
- This repo's own `CLAUDE.md` and `README.md`.
