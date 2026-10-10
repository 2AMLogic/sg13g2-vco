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

- **#95**: sim: PDK dsubw junction model (vj=0.1) goes NaN above ~52 C once bn is on the substrate -- row 11's +125 C cannot be simulated with the card as shipped
- **#143**: ci: reject paired simulation report/deck digest mismatches at evidence consumption
- **#167**: sim: preserve EM post/fit outputs when geometry inputs are incomplete

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#169**: sim: run-local svaricap dsubw vj overlay (IHP-Open-PDK PR #1102), retire tnom workaround
- **#170**: sim: EM post/fit preflight all geometries and publish staged outputs

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#108**: ci: gate layout records' GDS digests against committed vco.gds

## Proposed

Issues carrying `loom:curated`.

- **#3**: Gap to T1 sim-validated: artifact-presence checklist (bootstrap tracker) *(curated)*
- **#59**: layout: draw and commit sg13g2-vco GDS/OASIS (T1 item 1/2, analog full-custom) — unblocked now that #57/DR-004 landed *(curated)*
- **#62**: layout: LVS closure + signoff manifest refresh for sg13g2-vco (T1 item 1/2, part 3/3) *(curated)*
- **#95**: sim: PDK dsubw junction model (vj=0.1) goes NaN above ~52 C once bn is on the substrate -- row 11's +125 C cannot be simulated with the card as shipped *(curated)*
- **#106**: ci: gate layout records' GDS digests against the committed layout/vco.gds (PDK-free) *(curated)*
- **#143**: ci: reject paired simulation report/deck digest mismatches at evidence consumption *(curated)*
- **#144**: Auditor Capability Request: simulator-free validation tools missing on audit host *(curated)*

## Proposed (Architect / Hermit)

- **#143**: ci: reject paired simulation report/deck digest mismatches at evidence consumption *(architect)*
- **#167**: sim: preserve EM post/fit outputs when geometry inputs are incomplete *(architect)*

## Epics

_None._

## Backlog Balance

| Tier | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Operator priority | 0 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 3 |
| PRs awaiting review | 2 |
| Approved PRs awaiting merge | 1 |
| Curated | 7 |
| Architect / Hermit proposals | 2 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
