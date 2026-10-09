# spec/

Target specification and decision records. Spec changes require a decision record.

Enforcement: `.github/scripts/check-spec-change-has-dr.sh` (run in the `signoff`
workflow, self-tested by `.github/scripts/test-check-spec-change-has-dr.sh`)
fails a PR that modifies `spec/target-spec.md` without adding or modifying a
`spec/decision-records/DR-NNN-slug.md` (not `TEMPLATE.md`) in the same diff. It
is a presence check only; whether the record justifies the change is a review
question.

## Grader/spec agreement

The simulation graders copy ratified numbers into shell constants
(`OSC_ROW*` in `sim/oscillator-core/osc_bench.sh`, `PN_ROW4_*` in
`sim/phase-noise/pn_bench.sh`, `S2_*` and `OSC_VDD_NOM` for the supply, process
and temperature sets). `.github/scripts/check-grader-spec-agreement.py` (run as
`.github/scripts/check-all.sh grader-spec`, part of `npm test` / `npm run
check:ci` and the `lint` workflow) parses `spec/target-spec.md` and DR-004's
stage-2 condition directly and fails when a constant disagrees, when a spec
field cannot be located or parsed, or when a new `ROW`-numbered grader constant
has no mapping. Units are normalised (GHz/Hz, %/ratio, mW/W, V/mV, MHz/V vs
Hz/V, dBc/Hz), so `4.5e9` and `4.5 GHz` or `2.970` and `2.97` compare equal.
The expected values come from the spec text, never from the graders. Its mapping
table (`MAPPING`) lists each spec row/field against file and shell variable;
rows 5 and 9 and the row 8 stretch have no grader constant and are recorded as
not consumed, so a newly added constant for them fails until it is mapped.
Grader policy knobs that are not ratified bounds (`OSC_ROW7_MIN_WINDOW_SAMPLES`)
are listed in `OUT_OF_SCOPE`.

This is an agreement check only. It does not ratify or authorise a changed
requirement and never regenerates historical `sim/` evidence.

### Updating after an authorized spec revision

A revision is authorised by a superseding decision record (public PR, Judge
review, Champion/operator merge); the checker does not substitute for that.
In the same PR as the revision:

1. Edit `spec/target-spec.md` and add the superseding `DR-NNN` record (the
   presence gate in `check-spec-change-has-dr.sh` requires it).
2. Update the grader constant(s) the change affects, in the file named by
   `MAPPING` in `check-grader-spec-agreement.py`. Do not touch committed
   `sim/` records; they stay as evidence of the earlier contract.
3. If the wording of a row changed so an extractor no longer parses it (the
   gate then fails with the row, cell and text it could not read), or a row
   gained or lost a graded field, or DR-004's stage-2 condition moved to a
   newer record, update the field extractor or the `MAPPING` / `DR_GLOB` /
   `UNCONSUMED_*` entries in the same PR.
4. Run `.github/scripts/check-all.sh grader-spec grader-spec-selftest` (one at
   a time) and, if an extractor changed, add or adjust a mutation fixture in
   `.github/scripts/test-check-grader-spec-agreement.sh`.
