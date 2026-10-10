# Work Plan

This snapshot groups work by GitHub labels. Curated issues may still be
blocked or require an operator decision; curation does not approve dispatch.
See each issue for its current dependencies. The generated region changes
only when label state changes and the Guide debounce window has elapsed.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs stuck under a `loom:operator` merge-risk hold — implementation work is done, only a human merge decision is missing.

_None._

## Operator Priority

Issues the operator starred (`loom:operator-priority`); land these first.

_None._

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#221**: ci: validate retained model-overlay inputs from the current simulation writer

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#108**: ci: gate layout records' GDS digests against committed vco.gds

## Proposed

Issues carrying `loom:curated`.

- **#3**: Gap to T1 sim-validated: artifact-presence checklist (bootstrap tracker) *(curated)*
- **#59**: layout: draw and commit sg13g2-vco GDS/OASIS (T1 item 1/2, analog full-custom) — unblocked now that #57/DR-004 landed *(curated)*
- **#62**: layout: LVS closure + signoff manifest refresh for sg13g2-vco (T1 item 1/2, part 3/3) *(curated)*
- **#106**: ci: gate layout records' GDS digests against the committed layout/vco.gds (PDK-free) *(curated)*
- **#144**: Auditor Capability Request: simulator-free validation tools missing on audit host *(curated)*

## Proposed (Architect / Hermit)

- **#198**: sim: bounded bn=substrate varactor cell characterization per DR-006 option (b) (gated on ratification) *(architect)*

## Epics

_None._

## Backlog Balance

| Tier | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Operator priority | 0 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 1 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 1 |
| Curated | 5 |
| Architect / Hermit proposals | 1 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
