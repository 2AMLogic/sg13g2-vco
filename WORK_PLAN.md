# Work Plan

This snapshot groups work by GitHub labels. Curated issues may still be
blocked or require an operator decision; curation does not approve dispatch.
See each issue for its current dependencies. The generated region changes
only when label state changes and the Guide debounce window has elapsed.

<!-- guide:plan-body:start -->
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

_None._

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

_None._

## Important

`loom:important`; taken before unlabelled work.

- **#94**: sim: regenerate design/run_elaborate.sh, sim/oscillator-core and sim/phase-noise for the post-#79 netlist (blocked: OSDI varactor cannot run locally or on the fleet)
- **#162**: lvs: runset strict top-port check logs 3 port-name findings ('LA,VDD' vs 'VDD') after the cross-reference matches
- **#252**: design/vco.spice at 17e49a8 fails DC operating point (NaN) with the OSDI varactor under ngspice-47

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

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
- **#144**: Auditor Capability Request: simulator-free validation tools missing on audit host *(curated)*
- **#244**: T1 item 6: declare the statistical spec rows and plan the klt yield campaign for the oscillator core *(curated)*

## Proposed (Architect / Hermit)

- **#198**: sim: bounded bn=substrate varactor cell characterization per DR-006 option (b) (gated on ratification) *(architect)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 3 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 0 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 0 |
| Curated | 5 |
| Architect / Hermit proposals | 1 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
