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

- **#62**: layout: LVS closure + signoff manifest refresh for sg13g2-vco (T1 item 1/2, part 3/3)
- **#82**: sim: require complete voltage coverage before grading tuning curves
- **#83**: sim: reject missing transient measurements instead of reporting zero power

## In Progress

Issues currently being built (`loom:building`).

_None._

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#3**: Gap to T1 sim-validated: artifact-presence checklist (bootstrap tracker) *(curated)*
- **#59**: layout: draw and commit sg13g2-vco GDS/OASIS (T1 item 1/2, analog full-custom) — unblocked now that #57/DR-004 landed *(curated)*
- **#62**: layout: LVS closure + signoff manifest refresh for sg13g2-vco (T1 item 1/2, part 3/3) *(curated)*

## Proposed (Architect / Hermit)

_None._

## Epics

_None._

## Backlog Balance

| Tier | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Operator priority | 0 |
| Ready (`loom:issue`) | 3 |
| In Progress (`loom:building`) | 0 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 0 |
| Curated | 3 |
| Architect / Hermit proposals | 0 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
