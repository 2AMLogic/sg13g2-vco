# DR-007: Which spec rows are statistical, and which are corner-bounded

- **Status**: **proposed** -- classification only. It is not binding on design
  work until ratified, and **no bound, status cell or other text of
  `spec/target-spec.md` is edited by it** (`git diff -- spec/target-spec.md`
  is empty for the PR that adds this record).
- **Date**: 2026-10-17
- **Decided by**: Builder agent, issue #244 (recommendation only; ratification
  follows the same Judge-review-plus-merge route DR-003 and DR-004 used)
- **Supersedes**: none. It classifies the rows DR-003 and DR-004 ratified and
  changes none of them.

## Context

T1 checklist item 6 (`signoff/design-evidence-tiers.md`) says an analog
partition always requires Monte Carlo evidence; "not applicable" is available
to digital partitions only. This block has no digital partition
(`signoff/README.md`, "The manifest contract"), so item 6 cannot be closed by
statement. Today `signoff/t1-report.json` renders it `unmet` /
`no_evidence`, `spec/target-spec.md` carries no Monte Carlo row, and `sim/`
holds no Monte Carlo campaign.

Several ratified rows already lean on process spread that no record here
measures:

- **Row 7**: 19 % of the 0.40 V target is "a stated allowance for the tail
  mirror's process spread, which no record here measures" (DR-004).
- **Row 1**: grades "inside the window at the corners row 10 settles" under
  MIM +/-10 % spread; the corners bound the global MIM shift, they do not
  sample it jointly with the HBT and varactor spreads.
- **Row 6**: the margin is a ratio of two quantities that both move with
  device spread.

The question this record answers is narrow: for each of the twelve rows
(0-11), is the quantity it bounds a **distribution** over process and mismatch
(statistical), or is it fixed by **construction or by an enumerated corner
set** (corner-bounded)? Choosing the sample count, models and run plan is the
campaign plan's job (`sim/oscillator-core/yield/README.md`), not this
record's.

## Decision

Classification, with the reason for each row. "Statistical" means the row
needs a `klt yield` report (confidence interval, sample-size verdict, negative
control) to be graded; "corner-bounded" means the enumerated row-10 corners
are the right grading instrument and a Monte Carlo sample adds nothing the
bound depends on.

| Row | Parameter | Class | Reason |
|---|---|---|---|
| 0 | Supply voltage / device flavor | corner-bounded | A declared rail and device choice (+/-10 % excursion enumerated by row 10), not a measured value; there is nothing to sample. |
| 1 | Center / target band | statistical | f0 is set by the tank C (MIM, 32 varactor cells, HBT junction capacitance), each with its own spread; the corners move them one family at a time, the row's own margin argument relies on their joint spread, and the shortfall in DR-006 shows the margin is thin. |
| 2 | Tuning range | statistical | A ratio whose achievability is a fixed-C-fraction argument (F against V, DR-003 Decision 2); varactor geometry and MIM area spread move F/V directly, and 15 % leaves little room. |
| 3 | Kvco and its linearity | statistical | Window coverage, mean slope and chord nonlinearity all derive from the varactor C(V) shape, which depends on the flat-band, oxide and w/l spread. |
| 4 | Phase noise | statistical | L(df) follows Q, swing and tank conductance, all spread quantities. **Not covered by the first campaign**: no per-sample estimator exists (row 4 states the method is open; the ISF route costs about 1.2 CPU-hours per corner), so this is declared as a gap rather than classified away. |
| 5 | Tank Q | statistical | 1/Q is a sum of shares from inductor, varactor, MIM and bias loading. The inductor has no statistical model (campaign plan, "Model gaps"), so the sampled Q is a lower-variance bound on the true spread until one exists. |
| 6 | Startup / negative-gm margin | statistical | The ratio of pair g_m (HBT is, beta, area spread, tail current) to tank loss; both sides move per sample. |
| 7 | Output swing | statistical | Current-limited: `Vpp = (4/pi) I_tail R_p`, and I_tail comes from a mirror whose area and resistor spread is exactly the 19 % allowance DR-004 states and no record measures. |
| 8 | Supply current / power | corner-bounded | Arithmetic headroom, not a thin margin: `I_tail` = 204.1 uA at 3.63 V is about 0.74 mW against a 10 mW ceiling, so power would have to rise about 13x. The current is still read from every Monte Carlo sample at no extra cost and reported as a cross-check; it grades nothing. |
| 9 | Supply sensitivity (pushing) | statistical | A small-signal slope df/dVDD through the varactor well/substrate junction and pair parasitics, which spread. It needs two supply points per sample, so it sits in the second tier of the campaign plan. |
| 10 | PVT corner set | corner-bounded | It *is* the enumerated corner definition; it carries no measured value. The Monte Carlo campaign pairs with it, it does not grade it. |
| 11 | Operating temperature range | corner-bounded | A stated environment envelope, enumerated by row 10's temperature triplet. |

**Statistical row set: 1, 2, 3, 4, 5, 6, 7, 9.** Corner-bounded: 0, 8, 10, 11.
Row 4 is statistical but explicitly outside the first campaign's reach, so it
appears in the declared gaps of the signoff coverage statement, not in the
campaign's covered rows.

The row set is recorded in `signoff/README.md` (the pinned `klt` 0.6.0 does
not grade a `spec_rows` manifest field; see that file for the move into
`signoff/manifest.json`).

## Alternatives considered

- **Classify only rows 7, 1 and 6 as statistical.** These are the ones the
  issue calls clearest. Rejected: rows 2, 3, 5 and 9 depend on exactly the
  same sampled devices, and leaving them out would let the report render
  covered while their spread stays unmeasured.
- **Classify row 8 as statistical for completeness.** Rejected: the
  headroom is 13x by arithmetic written out above, and a row graded by a
  campaign that cannot plausibly fail it is evidence of nothing.
- **Classify row 4 as corner-bounded because no estimator exists.** Rejected:
  that would settle a methods gap by relabelling it. It stays statistical and
  is declared uncovered.
- **Edit `target-spec.md` columns to mark each row.** Rejected: that touches
  the ratified spec. This record is the sanctioned path.

## Consequences

- Item 6 will render `partial_coverage` with `uncovered_rows` once a release
  that grades the field is pinned, instead of `no_evidence`; until then it
  stays `unmet`. Neither is `met`, and nothing here moves a row toward met.
- The campaign plan must produce a `klt yield` citation for rows 1, 2, 3, 5,
  6, 7 and 9, and row 4 stays an open gap until a per-sample phase-noise
  estimator exists.
- A row whose Monte Carlo result later contradicts its ratified bound is a
  separate superseding decision (DR-003's rule), never a quiet edit.
- The classification is an opinion about which instrument grades a row. If a
  reviewer disagrees about one row, only that row's entry changes; the
  campaign plan reads this table.
