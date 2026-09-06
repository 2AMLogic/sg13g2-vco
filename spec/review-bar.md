# Review bar: one-command characterization + reproducibility

- **Status**: standing convention, adopted at repo bootstrap (issue #2).
  Not itself a numeric spec row — this is a process requirement every
  future PR against this block is held to.
- **Date**: 2026-09-06
- **Written by**: Builder agent, issue #2

## The bar

Per this repo's own `CLAUDE.md` ("Verification is the product: no claim
without a testbench; PVT corners on every recorded result"), and because
this block — like every canary in this catalog — is a candidate to be
entered in a design challenge, it must clear a review bar that does not
depend on a reviewer re-deriving how to reproduce a result:

1. **One-command characterization.** For any spec row this repo claims a
   number against, there must be a single, documented, cold-start
   invocation (an `sim/<slug>/run_pvt_sweep.sh` or equivalent script) that
   regenerates that row's evidence from the committed netlist and a
   pinned PDK revision, without hidden manual steps. A number that can
   only be reproduced by someone who remembers an undocumented sequence
   of commands is not a reproducible result.
2. **README reproducibility.** This repo's own `README.md` (and each
   `sim/<slug>/README.md` once evidence exists) must state what the block
   is, its current spec status, and how to reproduce every claimed
   result — the same bar `sg13g2-bandgap`'s own gap-to-T1 tracker (`#4`
   in that repo, item 10 "Repo hygiene") holds itself to.
3. **No claim without its measurement method.** Specific to this block:
   any phase-noise number states its measurement method (transient
   length, window, spectral estimator, or ISF derivation), its variance,
   and the method's known limits, per this repo's own `CLAUDE.md`. A
   phase-noise number without a stated method fails this bar regardless
   of how it was produced.

## Why this is stated now, before any design work exists

Stating the bar at bootstrap — rather than after the first `sim/` result
lands — means every future PR is reviewed against a standing convention,
not a bar invented after the fact to justify whatever the first result
happened to look like. This mirrors `sg13g2-bandgap#4`'s own framing: an
artifact-presence checklist "necessary but not sufficient" until it is
also fresh and passing.

## How this is checked

This bar is wired into the gap-to-T1 tracker (issue **#3** in this
repo) as an explicit checklist item under "Repo hygiene" — the same
placement `sg13g2-bandgap#4` item 10 uses. A future characterization
report (`sim/` aggregate summary, per the T1 ladder's own item 8) is
where this bar's item 1 (one-command characterization) gets verified in
practice, not asserted here.

## Sources

- This repo's own `CLAUDE.md` — "Verification is the product," phase-noise
  measurement-method requirement.
- `2AMLogic/sg13g2-bandgap#4` — item 10 "Repo hygiene" framing, and the
  "necessary but not sufficient" artifact-presence caveat this note
  borrows.
- `klayout-tools/docs/design-evidence-tiers.md` (`2AMLogic/klayout-tools`)
  — the T1 ladder this bar feeds into via the gap-to-T1 tracker.
