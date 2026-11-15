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

- **#330**: layout: klt erc supply spec and run for layout/vco.gds (ERC half of T1 item 11, split from #37)

## Important

`loom:important`; taken before unlabelled work.

- **#50**: sim: run the oscillator-core graded row-10/11 PVT grid (~180 CPU-hours) and record the row 1/2/3/6/8 verdicts
- **#53**: sim: run the graded row-10/11 phase-noise grid for design/vco.sch (spec row 4) and widen the ISF impulse spacing
- **#62**: layout: LVS closure + signoff manifest refresh for sg13g2-vco (T1 item 1/2, part 3/3)
- **#162**: lvs: runset strict top-port check logs 3 port-name findings ('LA,VDD' vs 'VDD') after the cross-reference matches
- **#331**: docs: bring the README status paragraph up to the records on main and link ROADMAP.md

## Ready

Human-approved issues ready for implementation (`loom:issue`).

- **#330**: layout: klt erc supply spec and run for layout/vco.gds (ERC half of T1 item 11, split from #37)
- **#339**: Remove the os.walk fallback in check_klt_friction.tracked_files: it is the only path the self-test exercises, and it scans untracked files

## In Progress

Issues currently being built (`loom:building`).

- **#338**: Remove the dangling npm worktree:return alias from package.json (exits 127)

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#340**: chore: drop the dangling worktree:return npm alias

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
- **#330**: layout: klt erc supply spec and run for layout/vco.gds (ERC half of T1 item 11, split from #37) *(curated)*

## Proposed (Architect / Hermit)

- **#198**: sim: bounded bn=substrate varactor cell characterization per DR-006 option (b) (gated on ratification) *(architect)*
- **#341**: Consolidate the duplicated ISF reduce-and-publish block into pn_bench.sh *(hermit)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 1 |
| Important | 5 |
| Ready (`loom:issue`) | 2 |
| In Progress (`loom:building`) | 1 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 1 |
| Curated | 9 |
| Architect / Hermit proposals | 2 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
