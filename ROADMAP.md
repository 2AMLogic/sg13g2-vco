# Roadmap

sg13g2-vco is an LC voltage-controlled oscillator on IHP SG13G2, built with
klayout-tools and the open xschem + ngspice flow, whose job is to produce
recorded evidence for each row of its ratified target spec and to surface the
tool gaps met on the way.

Status as of 2026-11-13, `main` @ `127302d`; the upstream klayout-tools
states cited below were re-read 2026-11-14. The verdict of record is
[`signoff/t1-report.json`](signoff/t1-report.json); this file grades nothing.

## Where it stands

The graded report (klt 0.8.0, 11-item checklist vendored in
[`signoff/design-evidence-tiers.md`](signoff/design-evidence-tiers.md)) reads
**5 of 11 T1 items met**.

| Item | State | Evidence or owner |
|---|---|---|
| 1 Design sources | met | `design/vco.sch`, `design/vco.spice`; inventories (#243) |
| 2 Layout | met | `layout/vco.gds`, reproducible via `layout/generate.sh`; TopMetal2 `VCTRL` pin added in #316 |
| 3 DRC clean | met | IHP-native DRC report, coverage limits in `layout/PROVENANCE.md` §13 (#242) |
| 4 LVS clean | unmet, `no_evidence` | #62, #162 |
| 5 Corner verification vs the ratified spec | unmet, `no_evidence` | #50 (rows 1/2/3/6/8), #53 (row 4) |
| 6 Monte Carlo evidence | unmet, `no_evidence` | #244 (classification DR-007 and unrun requests are committed) |
| 7 Post-layout verification | unmet, `no_evidence` | #260 |
| 8 Characterization report | unmet, `check_failed` | `signoff/characterization.md` exists (#261): 0 pass, 0 fail, 9 pending, 3 condition |
| 9 Testbenches shipped | met | `sim/` benches with known-answer method checks |
| 10 Repo hygiene | met | `check-all.sh` gates, CI |
| 11 Power delivery (structural) | unmet, `no_evidence` | #37 |

What the unmet items already have behind them:

- **Spec.** All 12 rows of `spec/target-spec.md` are ratified as targets
  (DR-003, DR-004). DR-006 (row 2 shortfall), DR-007 (statistical row
  classification) and DR-008 (clock output interface statement, #320) are
  `proposed`.
- **Corner grid (rows 1/2/3/6/7/8).** The post-#79 netlist ran on the batch
  backend with the OSDI varactor. At −40 °C and 27 °C rows 1, 2 and 3 are
  not met on all 90 graded curves (the whole curve sits below 4.5 GHz) and
  row 7 swing is met, its BVCEO compliance ungraded
  (`sim/oscillator-core/records/20261105-180000-f6c364b-*`). Every 125 °C
  unit aborts at the first timepoint, traced to a NaN junction capacitance
  in the 27 °C-referenced `dsubw` diode card (#309; record
  `20261110-050317-2287682`): a model artefact, not a failure to oscillate.
- **Phase noise (row 4).** The ISF estimator is known-answer checked and has
  one post-#79 pilot corner. The graded 135-corner entry point, per-corner
  request generator and completeness grader landed in #326
  (`sim/phase-noise/run_pn_sweep.sh`, `grade_pn_grid.py`). The grid has not run.
- **LVS.** IHP's own runset pairs 43/43 devices, 10/10 nets and 9/9 pins after
  the reviewed label-order step (#80), with negative controls
  (`layout/PROVENANCE.md` §14). Its strict top-port check still logs three
  port-name findings (#162), and no `klt lvs` report exists: at klt 0.8.0 — the
  release this repo pins for claims (`signoff/README.md`) — the curated
  extraction recognises 4 of 42 devices. The curated deck is not the sanctioned
  path for this block; the `klayout-runset` engine is (klayout-tools#2870), and
  it has shipped — see Blocked for what that path still needs.

## Now

No open issue is ready for dispatch: all 13 are blocked or await a decision.
The four items below wait on none of those blocks; each is one pull request.

1. **Per-corner ISF reduction for the 135-corner grid** (#329, part of #53).
   `sim/phase-noise/klt-sim/reduce_isf_fleet.sh` reduces one corner and takes
   the carrier as an argument; `sim/phase-noise/README.md`
   lists the per-corner glue as open before the grid can be graded.
   Done when: a driver reduces a directory of returned corners into the CSV
   `grade_pn_grid.py` reads, reports `n_plateau` and `plateau_ripple` per
   corner, and has a simulator-free fixture test wired into `check-all.sh`.
2. **`klt erc` supply spec for `layout/vco.gds`** (#330; the ERC half of #37,
   item 11). #37 is parked on the layout, which is now committed; the two ERC
   gaps it cites (klayout-tools#2234, #2192) are recorded closed.
   Done when: a supply spec (supplies, stackup, taps) and a `klt erc`
   envelope are committed, or the exact refusal is recorded and added to the
   friction ledger. Item 11 stays `unmet` until item 4's LVS report exists.
3. **README status paragraph brought to this state** (#331). It predates the
   125 °C attribution and #326, and its row-7 wording differs from the graded
   record. Done when: it cites the records above and links this file.
4. **Bump the klt pin to a release carrying the runset digest allowlist**
   (part of #62, item 4; no issue of its own). Claims are pinned at klt 0.8.0,
   whose `signoff_runset.PINNED_RUNSETS` is `{}`; 0.9.1 pins the `ihp-sg13g2`
   runset digest (Blocked, below). This needs no PDK host — only the pinned
   release and the signoff bundle. Done when: the pin in `signoff/README.md`
   moves to a release whose allowlist carries the SG13G2 digest, the signoff
   bundle is re-rendered under it with the graded deltas recorded, and any
   refusal met on the way is added to the friction ledger.

## Next

- **Finish the row 1/2/3/6/8 corner grid** (#50). Unblocked by the pending
  decision on how 125 °C units are started. Done when: a graded record covers
  all 135 corners, the row-6 margin pass and DR-004 stage 2, and
  `signoff/characterization.md` shows a verdict per row.
- **Run and grade the row-4 phase-noise grid** (#53). Needs Now item 1, the
  same 125 °C decision, and a ruling on waveform volume (about 240 GB for 810
  units as currently saved). The #326 record also notes that `klt sim
  --attach` rejects a request after `--submit-only`, so an interrupted batch
  set can double-submit; report that upstream before a long submit. Done
  when: `grade_pn_grid.py` reports the grid complete with a row-4 verdict.
- **Monte Carlo campaign** (#244, item 6). Needs #50's corner pairing. `klt
  yield` is no longer a blocker: klayout-tools#2900 closed `completed`
  2026-10-29, `klt-yield-native` 0.1.0 is on PyPI with a
  `manylinux_2_28_x86_64` wheel, and `uvx --from
  'klayout-tools[yield]==0.8.0' klt yield --help` resolves and runs on a
  dispatch host (measured 2026-11-14). `.github/klt-friction-ledger.json`
  still records #2900 open; that staleness is tracked in #333, not here.
  Done when: a `klt yield` report is cited in `signoff/manifest.json` for
  item 6.
- **Post-layout verification** (#260, item 7). Needs extraction that
  recognises the inductor, varactor and HBT devices, and the #50/#53 grids as
  the schematic side. Done when: a `klt pex` report with its `body_bias`
  status is cited, or the exact refusal is recorded as the blocker.
- **Close or restate #266.** Commit `300df05` (#316) refreshed the DRC and
  LVS records under klt 0.8.0. Done when: its acceptance criteria are checked
  against that commit and the issue is closed or narrowed.

## Later

- **Rows 1 and 2 are missed by the committed netlist**, and the re-tune found
  no defensible candidate (#93). Question first: is DR-006 ratified with a
  numerical clearing rule so the bounded varactor-cell characterization
  (#198) can run, or are the rows superseded by a new decision record?
- **Row 4 margin.** The pre-#79 pilot corner read −102.28 dBc/Hz at 1 MHz
  against −105. Question first: what does the graded grid say, and how much
  of the gap is inside the non-PDK inductor model's error bar?

## Blocked and waiting

- **Decision, #50:** how 125 °C corners are started given the `dsubw` NaN
  capacitance (options are in the issue body). Gates #50, #53, #244, #260.
- **Decision, #53:** waveform volume for the grid, or a reduced save policy.
- **Ratification:** DR-006 (gates #198), DR-007, DR-008.
- **LVS, #62 and #162:** the ruling of 2026-10-19 requires a clean strict
  top-port result with no name exception, plus a native `klt lvs` report with
  power-connectivity evidence (the report is drafted in
  `layout/PROVENANCE.md` §14.6, marked not yet filed). **This is no longer
  waiting on klayout-tools.** #2849 closed `not_planned` 2026-10-17 when the
  `klayout-runset` engine landed, and its successors #3206, #2870 and #2864
  are all closed `completed`; `klt lvs --deck-file` for `request.engine
  'klayout-runset'` is present already at the pinned klt 0.8.0, and the digest
  allowlist is no longer empty — klt 0.9.1 pins `ihp-sg13g2` at IHP-Open-PDK
  `v0.3.0` (`sha256:e01bcb1e…` over
  `ihp-sg13g2/libs.tech/klayout/tech/lvs/sg13g2.lvs`, reviewed in
  klayout-tools#4309), where 0.8.0's `PINNED_RUNSETS` is `{}` (both measured
  2026-11-14 with `uvx --from klayout-tools==<v>`). What remains is in-repo:
  the pin bump of Now item 4, a PDK host to run the runset engine (#266), and
  #162's three port-name findings. The repo's recorded runset hash
  (`fd11fced…`) covers a different file set than the allowlist digest
  (`sg13g2.lvs` alone, per `layout/lvs/vco-lvs-ihp.json`'s `hash_scope`), so a
  pinnable report must be produced against the allowlisted revision. #59 and
  #37 wait on #62.
- **PDK on dispatch hosts, #266:** `layout/drc.sh`, `layout/lvs.sh` and
  `klt netlist design/vco.sch --check` need the IHP PDK and KLayout 0.30.12.

## Not planned

- A PLL around this oscillator (`spec/target-spec.md` scopes it out).
- Accepting, suppressing or hiding the three strict top-port findings (ruled
  out on #62).
- Editing a ratified bound to match a measurement; a contradicting result is
  a superseding decision record (DR-003's rule).
