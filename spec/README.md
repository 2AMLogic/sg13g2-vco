# spec/

Target specification and decision records. Spec changes require a decision record.

Enforcement: `.github/scripts/check-spec-change-has-dr.sh` (run in the `signoff`
workflow, self-tested by `.github/scripts/test-check-spec-change-has-dr.sh`)
fails a PR that modifies `spec/target-spec.md` without adding or modifying a
`spec/decision-records/DR-NNN-slug.md` (not `TEMPLATE.md`) in the same diff. It
is a presence check only; whether the record justifies the change is a review
question.
