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

- **#50**: sim: run the oscillator-core graded row-10/11 PVT grid (~180 CPU-hours) and record the row 1/2/3/6/8 verdicts
- **#53**: sim: run the graded row-10/11 phase-noise grid for design/vco.sch (spec row 4) and widen the ISF impulse spacing
- **#62**: layout: LVS closure + signoff manifest refresh for sg13g2-vco (T1 item 1/2, part 3/3)
- **#162**: lvs: runset strict top-port check logs 3 port-name findings ('LA,VDD' vs 'VDD') after the cross-reference matches

## Ready

Human-approved issues ready for implementation (`loom:issue`).

- **#337**: docs: ROADMAP.md and characterization-rows.json disagree on which spec rows #50 owes

## In Progress

Issues currently being built (`loom:building`).

- **#333**: ci: klt-friction-ledger.json upstream states go stale (2 of 31 entries wrong), and nothing re-checks them
- **#346**: pn_summary_rows_common emits nothing, and exits 0, on an unrecognized section name
- **#354**: docs: run_pilot_grid.sh omits row 7 from the graded row set, in a sha256-pinned file (split from #337)

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#351**: ci: compare friction-ledger statuses against the klayout-tools tracker
- **#353**: fix: pn_summary_rows_common fails loudly on an unknown section name
- **#355**: fix: include row 7 in run_pilot_grid.sh's graded-row list and refresh signoff pins

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#3**: Gap to T1 sim-validated: artifact-presence checklist (bootstrap tracker) *(curated)*
- **#50**: sim: run the oscillator-core graded row-10/11 PVT grid (~180 CPU-hours) and record the row 1/2/3/6/8 verdicts *(curated)*
- **#53**: sim: run the graded row-10/11 phase-noise grid for design/vco.sch (spec row 4) and widen the ISF impulse spacing *(curated)*
- **#59**: layout: draw and commit sg13g2-vco GDS/OASIS (T1 item 1/2, analog full-custom) — unblocked now that #57/DR-004 landed *(curated)*
- **#62**: layout: LVS closure + signoff manifest refresh for sg13g2-vco (T1 item 1/2, part 3/3) *(curated)*
- **#144**: Auditor Capability Request: simulator-free validation tools missing on audit host *(curated)*
- **#244**: T1 item 6: declare the statistical spec rows and plan the klt yield campaign for the oscillator core *(curated)*
- **#260**: T1 item 7 (post-layout verification): klt pex of layout/vco.gds against the ratified oscillator rows *(curated)*
- **#333**: ci: klt-friction-ledger.json upstream states go stale (2 of 31 entries wrong), and nothing re-checks them *(curated)*
- **#337**: docs: ROADMAP.md and characterization-rows.json disagree on which spec rows #50 owes *(curated)*
- **#346**: pn_summary_rows_common emits nothing, and exits 0, on an unrecognized section name *(curated)*
- **#354**: docs: run_pilot_grid.sh omits row 7 from the graded row set, in a sha256-pinned file (split from #337) *(curated)*

## Proposed (Architect / Hermit)

- **#198**: sim: bounded bn=substrate varactor cell characterization per DR-006 option (b) (gated on ratification) *(architect)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 4 |
| Ready (`loom:issue`) | 1 |
| In Progress (`loom:building`) | 3 |
| PRs awaiting review | 3 |
| Approved PRs awaiting merge | 0 |
| Curated | 12 |
| Architect / Hermit proposals | 1 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
