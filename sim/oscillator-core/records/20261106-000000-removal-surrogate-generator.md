# Removal of the OSDI-free varactor surrogate generator (issue #292)

Append-only. This record adds a removal; it edits no earlier record. Every
`records/*-surrogate-pre79*` and `records/*-surrogate-corrected*` file (issue #179) stays as
evidence and is unchanged.

## What was removed
Removed in the PR for #292 (last present at `5c36a99`; recover with `git show 5c36a99:<path>`):

- `sim/tools/svaricap_surrogate.py`
- `sim/oscillator-core/surrogate_bench.py`
- `tests/stdlib/test_svaricap_surrogate.py`
- `tests/stdlib/test_surrogate_bench_traces.py`
- `tests/stdlib/test_surrogate_bench_reserve.py`

The `sim/oscillator-core/README.md` row for the surrogate records now points here and at git history.

## Why
The surrogate was a screening-only stop-gap (#179) while #94 blocked the real OSDI varactor. It graded no
specification row and omitted OSDI device noise. The OSDI-on-fleet route now runs the real `mosvar.osdi` via
`options.osdi_preload` (`20261105-190000-ac2481d-elaborate-post79.md`, `20261105-152054-a6be03f-pvt-grid-post79.md`).
Nothing outside the surrogate's own bench and tests called the code at `5c36a99`. Operator ruling r7-q11
(2026-11-05) covers the removal.

## What this does and does not change
- The OSDI-on-fleet route is the only varactor path for graded evidence. Nothing here grades a specification row.
- The old surrogate records can no longer be regenerated from the tree. They remain valid as the historical
  runs they describe, produced at the commits named in their filenames.
- `sim/tools/svaricap_overlay.py` is still used by other code and was not touched.
