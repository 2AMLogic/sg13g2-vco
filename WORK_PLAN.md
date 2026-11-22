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
- **#53**: sim: run the graded row-10/11 phase-noise grid for design/vco.sch (spec row 4) and widen the ISF impulse spacing *(held)*
- **#62**: layout: LVS closure + signoff manifest refresh for sg13g2-vco (T1 item 1/2, part 3/3) *(held)*
- **#162**: lvs: runset strict top-port check logs 3 port-name findings ('LA,VDD' vs 'VDD') after the cross-reference matches *(held)*

## Ready

Human-approved issues ready for implementation (`loom:issue`).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#417**: lvs: prepare the two IHP runset reports (inductor terminal order; LA/LB texts as net names) and the tool-fix proposal for operator review (preparation authorised by the #162 ruling)
- **#420**: layout: expose OUTP/OUTN as top-metal pins at the bbox edge (parent tank routes are 100+ um at the floor)
- **#422**: ci: friction-upstream has been red on main's daily schedule since 2026-11-17 and nothing repairs the drift
- **#426**: Remove the tuning fixture’s dependency on a local copy of the old bench
- **#427**: layout: expose VCO ground net `0` on top metal at the bottom edge for parent supply routing
- **#433**: Exercise the real overlay capture and remove the Python manifest-writer copy

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

- **#419**: docs(lvs): split the section 14.6 draft into two IHP runset reports with fix proposals
- **#428**: layout: expose OUTP/OUTN as TopMetal1 pins at the bbox edge
- **#429**: layout: add TopMetal2 ground chip-level pin on the bottom guard-ring bar
- **#432**: test: pin pre-change tuning row so the byte-identical check always runs
- **#434**: test: verify the emitted model-input capture with the production reader

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

_None._

## Proposed

Issues carrying `loom:curated`.

- **#3**: Gap to T1 sim-validated: artifact-presence checklist (bootstrap tracker) *(curated)* *(held)*
- **#50**: sim: run the oscillator-core graded row-10/11 PVT grid (~180 CPU-hours) and record the row 1/2/3/6/8 verdicts *(curated)*
- **#53**: sim: run the graded row-10/11 phase-noise grid for design/vco.sch (spec row 4) and widen the ISF impulse spacing *(curated)* *(held)*
- **#59**: layout: draw and commit sg13g2-vco GDS/OASIS (T1 item 1/2, analog full-custom) — unblocked now that #57/DR-004 landed *(curated)* *(held)*
- **#62**: layout: LVS closure + signoff manifest refresh for sg13g2-vco (T1 item 1/2, part 3/3) *(curated)* *(held)*
- **#144**: Auditor Capability Request: simulator-free validation tools missing on audit host *(curated)* *(held)*
- **#260**: T1 item 7 (post-layout verification): klt pex of layout/vco.gds against the ratified oscillator rows *(curated)* *(held)*
- **#417**: lvs: prepare the two IHP runset reports (inductor terminal order; LA/LB texts as net names) and the tool-fix proposal for operator review (preparation authorised by the #162 ruling) *(curated)*
- **#420**: layout: expose OUTP/OUTN as top-metal pins at the bbox edge (parent tank routes are 100+ um at the floor) *(curated)*
- **#422**: ci: friction-upstream has been red on main's daily schedule since 2026-11-17 and nothing repairs the drift *(curated)*
- **#427**: layout: expose VCO ground net `0` on top metal at the bottom edge for parent supply routing *(curated)*

## Proposed (Architect / Hermit)

- **#198**: sim: bounded bn=substrate varactor cell characterization per DR-006 option (b) (gated on ratification) *(architect)* *(held)*
- **#430**: Move the LVS record writer into the existing Python compile gate *(hermit)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 0 |
| Very important | 0 |
| Important | 4 |
| Ready (`loom:issue`) | 0 |
| In Progress (`loom:building`) | 6 |
| PRs awaiting review | 5 |
| Approved PRs awaiting merge | 0 |
| Curated | 11 |
| Architect / Hermit proposals | 2 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
