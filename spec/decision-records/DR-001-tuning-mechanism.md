# DR-001: Tuning mechanism — MOS accumulation-mode varactor over junction-diode varactors

- **Status**: proposed
- **Date**: 2026-09-15
- **Decided by**: Builder agent, issue #31
- **Related**: #3 (gap-to-T1 tracker — this record satisfies the operator's
  named step (1) of the 2026-09-15T00:00:29Z Builder sequence comment),
  #18/#19 (the `sim/varactor-characterization/` study this record consumes),
  #31 (this issue)
- **Consumes**: `sim/varactor-characterization/README.md` and its cited
  evidence record `20260909-231619-de50891` (commit `3428c68`, "sim: add
  varactor-characterization study for sg13_hv_svaricap and junction diodes
  (#18) (#19)"), specifically:
  - `sim/varactor-characterization/records/20260909-231619-de50891.md` —
    the narrative record (model/source content hashes, PVT grid, method
    validation).
  - `sim/varactor-characterization/records/20260909-231619-de50891-kvco.csv`
    — the per-device × corner × temperature × domain `Cmax`, `Cmin`,
    `Cmax/Cmin`, `dC/dV` table this record's numbers are read from directly
    (not restated from the README's prose).
  - `sim/varactor-characterization/records/20260909-231619-de50891.csv` and
    `...-method-check.csv` — the scalar summary and the known-answer check
    (0.1% arithmetic tolerance, 216/216 points passing) that back the
    `kvco.csv` numbers.
- `spec/porting-plan.md` §2's "Varactor / tuning mechanism" row (this
  record answers it) and `spec/target-spec.md` rows 0, 2, 3, 9 (this record
  is the citation those rows' "Corner / condition" columns now point to).

## Ratification note (per this repo's own two-key mechanism, unverified beyond its one-line description)

`spec/target-spec.md`'s own Status section states ratification "flows
through the two-key mechanism (EE key + market key)" and that "a
scope-only spec DR ratified with both keys needs no per-PR operator
statement (generalized ruling, 2026-08-28, cited in issue #2)." This
issue's own filing explicitly flags that mechanism as **not independently
verified by the curation pass that filed it**, and this record does not
independently verify it either: a search of this repo's own tree
(`.loom/docs/`, `spec/`) and of every other `2AMLogic` repo reachable from
this token (`gh api search/code`, `two-key` / `EE key` / `market key`,
0 hits anywhere in the org) found no document describing what "EE key" or
"market key" concretely are, who or what holds them, or how a PR would
demonstrate either key was applied. `2AMLogic/2am#689` — the operator
decision cited elsewhere in this repo's bootstrap issue (#2) as the
wave-5-standup authority — is not visible to this token (`2am` does not
appear in this org's repo listing), so it cannot be fetched to check
either.

Absent a mechanism this record can concretely satisfy, this record follows
the precedent `2AMLogic/sg13g2-pll`'s own `DR-002` states for the identical
situation ("this repo has no separate operator-ratification issue... merge
of the PR that lands this record is what makes it binding on #7's own
schematic work"): **this record stays `proposed`, not `ratified`, and this
PR does not assert that a single PR merge is sufficient to ratify it.**
Whatever operator-side "two-key" action this org's tooling performs (if
any) is left to happen through its own channel, independent of this
record's Status field — a future edit to this record (or a superseding
`DR-NNN`) should flip Status to `ratified` once that mechanism, whatever it
concretely is, is confirmed to have run against this specific record. This
record's job is to supply the grounded recommendation that mechanism has
something to act on; it does not manufacture the ratification event itself.

## Context

`spec/porting-plan.md` §2 names "Varactor / tuning mechanism (MOS
accumulation-mode vs. junction varactor; band-switching capacitor bank or
none)" as a design, open question, and `spec/target-spec.md` rows 0
(supply voltage / device flavor, i.e. the `Vctrl` domain), 2 (tuning range),
3 (Kvco and its linearity), and 9 (supply pushing) all name that same open
question as their gating condition. `sim/varactor-characterization/` (#18,
delivered by #19) produced the device-level `C(V)`, `dC/dV`, and `Q(V,f)`
evidence needed to close it, sweeping `sg13_hv_svaricap` (the MOS
accumulation-mode varactor) against `dantenna`/`dpantenna` (two
junction-diode candidates named informally in #18) across the full
non-statistical process-corner set for each device class, three
temperatures, and a shared 0.0–3.3 V control-voltage grid — 216 simulation
points, 864 device rows, all passing the study's own 0.1% known-answer
check. That evidence has existed on `main` since 2026-09-09 without being
turned into a decision; this record is that decision.

## Decision

**Adopt `sg13_hv_svaricap` (the MOS accumulation-mode varactor) as this
block's tuning device, driven over its full native 0.0–3.3 V thick-oxide
(HV) `Vctrl` domain, with no band-switching capacitor bank adopted in v1.**

### Device: `sg13_hv_svaricap`

Read directly from `records/20260909-231619-de50891-kvco.csv`
(`mos_tt`, 27 °C, full 0.0–3.3 V domain, 1 GHz):

| Geometry | `Cmax` (V=0) | `Cmin` | `Cmax/Cmin` |
|---|---|---|---|
| `mos_small` | 10.457 fF | 5.567 fF | 1.878 |
| `mos_mid` | 110.982 fF | 53.374 fF | 2.079 |
| `mos_large` | 489.264 fF | 260.609 fF | 1.877 |
| `mos_xlarge` | 1957.06 fF | 1042.44 fF | 1.877 |

against, from the same file (`dio_tt`, 27 °C, full domain, 1 GHz):

| Device | `Cmax` | `Cmin` | `Cmax/Cmin` |
|---|---|---|---|
| `dantenna` (`dasm`, 4 µm²) | 1.590 fF | 1.546 fF | 1.028 |
| `dantenna` (`dalg`, 400 µm²) | 146.529 fF | 141.231 fF | 1.038 |
| `dpantenna` (`dpsm`, 4 µm²) | 2.090 fF | 1.690 fF | 1.236 |
| `dpantenna` (`dplg`, 400 µm²) | 185.687 fF | 150.815 fF | 1.231 |

Every `sg13_hv_svaricap` geometry beats every `dantenna`/`dpantenna`
device/area combination on tuning ratio (1.88–2.08x vs. 1.03–1.24x), and
the README's Q comparison (§"Results" 1 and 2, same record) is not close
either: `sg13_hv_svaricap` reaches `Q` = 224 at its smallest geometry
(1 GHz), while `dantenna`/`dpantenna` never clear `Q` ≈ 1.7 at 1 GHz
regardless of area (`Q` is measured, in the same record, to be
area-independent for both diode devices — `dasm` vs. `dalg` and `dpsm` vs.
`dplg` differ by under 10% in `Q` despite a 100x area difference, because
`darea`'s per-area `cj0`/`rs` scaling keeps the `RC` time constant, and
therefore `Q`, constant with area). The study's own framing of
`dantenna`/`dpantenna` as ESD/antenna-protection devices IHP did not design
for RF tuning is borne out directly by these numbers, not merely asserted.

### `Vctrl` domain: full 0.0–3.3 V HV range, not a 1.2 V-only subset

`sg13_hv_svaricap` is inherently a thick-oxide (HV) device — there is no
1.2 V core-flavor variant of this model to choose instead. The open
question this record resolves for row 0 is therefore not "which flavor"
but "how much of the device's own native range to actually drive the well
node across." The study's core-vs-full domain slicing
(`records/20260909-231619-de50891-kvco.csv`'s `domain` column) answers
this directly: over the 0.0–1.2 V core-only subset, `mos_small` gives
1.69x, `mos_mid` 1.82x, `mos_large`/`mos_xlarge` 1.64x — roughly 85–90% of
each geometry's full-domain ratio, at the cost of the top ~30% of `Vctrl`
headroom (README §"Results" 1). Since the device is already HV-rated
regardless of how much of its range is used, restricting `Vctrl` to a
1.2 V-only subset would give up real tuning ratio (≈15% relative) for no
compensating benefit this study's evidence identifies — no other block
element is forced onto a 1.2 V rail by this choice, since the negative-gm
pair's own supply flavor is a separate, not-yet-made decision
(`spec/porting-plan.md` §2, negative-gm pair row). **This record therefore
adopts the full 0.0–3.3 V HV `Vctrl` domain.**

This record does not fix a bias polarity (which physical node — gate or
well/substrate — carries the swept `Vctrl` signal in the eventual tank).
The study's own testbench ties the gates (`G1`/`G2`) to a fixed DC potential
and sweeps the isolated well/substrate (`W`/`bn`) with `Vctrl`, matching
`libs.tech/xschem/sg13g2_tests/ac_svaricap_test.sch`'s own topology
(README, "Bias convention"); the study explicitly notes a real tank could
tune from the gate side instead, with the well fixed, recovering the
opposite sign of `dC/dV` without changing the magnitude/shape result cited
above. Which node is the tank's own AC node is a schematic-level decision
for the (out-of-scope-here) oscillator design, not a fact this device-level
sweep determines on its own.

### Band-switching capacitor bank: not adopted in v1, named as an open trigger

The evidence this record consumes says nothing about what tuning range
`spec/target-spec.md` row 2 will eventually require — row 1 (center/target
band) and row 5 (tank Q) are both still blank pending the
tank-characterization study, and neither this study nor
`tank-characterization/` states a target band width a 1.88–2.08x varactor
ratio must be checked against. Committing to a band-switching bank without
that number would repeat exactly the "numbers without methods are not
results" failure this repo's `CLAUDE.md` forbids, applied to a scope
decision instead of a numeric one. **This record does not adopt a
band-switching capacitor bank for v1.** Trigger to revisit: once
`spec/target-spec.md` row 1 (target band) and row 5 (tank Q, hence the
usable tank capacitance range) are filled in from the tank-characterization
study, if the required tuning range at the target band cannot be covered
by `sg13_hv_svaricap`'s measured 1.88–2.08x ratio alone (at whichever
geometry the tank sizing settles on) with adequate margin across the
process/temperature spread this record's evidence also quantifies (see
"Consequences" below), a switched capacitor bank becomes the next thing to
design — as its own decision record, not a retrofit to this one.

## Alternatives considered

- **`dantenna` or `dpantenna` as the tuning device.** Rejected: both give
  `Cmax/Cmin` of only 1.03–1.24x (vs. `sg13_hv_svaricap`'s 1.88–2.08x) and
  `Q` that never clears ≈1.7 at 1 GHz regardless of area (vs. up to 224 for
  the MOS varactor's smallest geometry) — an order-of-magnitude-plus
  disadvantage on both axes that dominates any secondary consideration
  (e.g. these diodes' process-corner invariance, README finding 6, which is
  a real but minor advantage next to the tuning-ratio and Q gap). These are
  ESD/antenna-protection devices IHP did not design for RF tuning, and the
  measured numbers confirm that framing directly rather than asserting it
  from the devices' names alone.
- **1.2 V-only `Vctrl` domain for `sg13_hv_svaricap`.** Rejected: gives up
  ≈15% relative tuning ratio (1.64–1.82x vs. 1.88–2.08x) for no identified
  compensating benefit — the device is HV-rated regardless, and no other
  block element is forced onto a narrower rail by using the device's full
  native range. See "`Vctrl` domain" above.
- **Adopting a band-switching capacitor bank now, on the reasoning that
  `sg13_hv_svaricap`'s own Q-vs-geometry tradeoff (README finding 1: `Q` at
  10 GHz drops from 22.4 at the smallest geometry to 0.19 at the largest)
  argues for using several small-geometry, high-Q varactor cells switched
  in banks rather than one large, low-Q cell.** This is a real argument the
  Q-vs-geometry data supports in shape, but this record does not have the
  one number it would need to size a bank against — the target tuning range
  (`spec/target-spec.md` row 2, still blank). Adopting a bank without that
  number would be sizing decision made ahead of its own evidence. Deferred,
  not rejected — see "Band-switching capacitor bank" above for the named
  trigger.

## Consequences

**What this fixes:**

- Closes `spec/porting-plan.md` §2's "Varactor / tuning mechanism" open
  question with a device choice and a `Vctrl` domain, grounded in measured
  `C(V)`/`Q(V,f)` data rather than an assumption.
- Gives `spec/target-spec.md` rows 0, 2, 3, and 9 a citable condition
  (this record) in place of "gated on an open design question" — though
  their numeric min/typ/max cells stay blank, per this issue's own scope,
  until the tank-characterization study supplies the absolute Kvco range
  those rows also depend on.
- Lets the (separately scoped, not this issue's job) negative-gm pair and
  tank-sizing work proceed against a named device and control-voltage
  window instead of an open menu of two device classes.

**What this costs, and hands to later design work:**

- **Temperature is not free to drop for this device**, unlike the MIM cap
  (`tank-characterization` finding 3): `records/20260909-231619-de50891-kvco.csv`
  and the README (§"Results" 3) show `Cmax` and `Cmin` moving in *opposite*
  directions over −40…125 °C, drifting `Cmax/Cmin` by ~7% relative
  (1.94 → 1.80) end to end for `mos_small`. Any Kvco-drift or frequency-drift
  budget this block later states (row 3, row 9) must carry this device's
  own temperature dependence as an explicit term, not assume it away.
- **Q falls steeply with geometry** (224 → 0.19 at 1 GHz → 10 GHz across
  the smallest-to-largest characterized geometries) — whichever geometry
  the tank-sizing work eventually picks to hit a target capacitance trades
  directly against tank Q (row 5), the same shape of tradeoff
  `tank-characterization` finding 3 already found for MIM cap sizing. This
  record does not resolve that tradeoff; it only names the device it must
  be resolved for.
- **The band-switching question is left open, not closed**, deliberately —
  see "Alternatives considered." A future decision record is still owed
  once row 1/row 5 exist, and design work should not assume the answer is
  "no bank" beyond v1 just because this record deferred it.
- **No schematic, negative-gm sizing, or capacitor-bank implementation is
  authorized by this record** — per this issue's own explicit scope
  boundary, this record recommends a device and a domain; it does not draw
  or size anything.

## Sources

- `sim/varactor-characterization/README.md` and its `records/
  20260909-231619-de50891{.md,.csv,-kvco.csv,-method-check.csv}` — the
  evidence this record consumes, cited by record ID and file path
  throughout rather than restated from memory (commit `3428c68`, "sim: add
  varactor-characterization study for sg13_hv_svaricap and junction diodes
  (#18) (#19)").
- `sim/tank-characterization/README.md` finding 6 — "all tuning must come
  from the varactor or a switched bank," the finding that named this open
  question in the first place.
- `spec/porting-plan.md` §2 — the "Varactor / tuning mechanism" row this
  record answers.
- `spec/target-spec.md` — rows 0, 2, 3, 9 (gated on this decision) and its
  own Status-section description of the two-key ratification mechanism
  (quoted and flagged as unverified above).
- `2AMLogic/sg13g2-pll` `spec/decision-records/DR-002-supply-device-flavor.md`
  — the sibling precedent this record follows for staying `proposed`
  absent a separate operator-ratification issue, and for the
  Decision/Alternatives considered/Consequences record shape generally
  (fetched directly via `gh api`, not reconstructed from memory).
- This repo's own `CLAUDE.md` — "State the tuning plan honestly," "no
  claim without a testbench," and the "numbers without methods are not
  results" discipline this record follows for the band-switching deferral.
