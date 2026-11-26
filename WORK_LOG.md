# Work Log

Merged PRs and closed issues, newest first. Entries record forge events;
closure alone does not assert that engineering acceptance criteria passed.
Guide maintenance PRs are excluded.

## Archives

- [2026-09](work_log/WORK_LOG_2026-09.md)

### 2026-11-26

- **PR #424**: ci: file a loom:triage repair issue from scheduled friction-upstream drift
- **Issue #422** (closed): ci: friction-upstream has been red on main's daily schedule since 2026-11-17 and nothing repairs the drift
- **PR #464**: fix: share the tank A/B record inventory so strict mode catches missing reports
- **Issue #462** (closed): Share tank A/B report discovery so strict mode catches missing reports

### 2026-11-25

- **PR #453**: test: add fixture and gate for the tank-stub A/B runner
- **Issue #447** (closed): sim/tank-stub-load/run_stub_ab.sh has no simulator-free fixture test (its sibling runner does)
- **PR #459**: test: check every PROVENANCE outline restatement against EXPECTED_BBOX_UM
- **Issue #456** (closed): layout: PROVENANCE §18 restates the artifact outline but the new drift gate only covers §§15/17
- **PR #455**: test: gate EXPECTED_BBOX_UM against the PROVENANCE outline; print bounds on failed checks
- **Issue #445** (closed): layout: the artifact-outline gate's expected value is an unchecked transcription, and a failed acceptance check never prints its bounds

### 2026-11-23

- **PR #451**: signoff: gate T1 met-item regressions against the merge-base verdict
- **PR #428**: layout: expose OUTP/OUTN as TopMetal1 pins at the bbox edge
- **Issue #449** (closed): signoff: CI accepts a t1_met_count regression — check-signoff.sh only compares the render, never the met count
- **Issue #448** (closed): layout/PROVENANCE.md §18 misstates the label-count assertion change; tank-stub make_requests.py docstring lists a flag it does not accept
- **Issue #420** (closed): layout: expose OUTP/OUTN as top-metal pins at the bbox edge (parent tank routes are 100+ um at the floor)
- **PR #446**: docs(layout): state 0.8.0 diagnostic counts in drc.sh header
- **PR #443**: fix(layout): derive pin placements from measured pad edges and gate the artifact outline
- **PR #442**: fix(layout): bound the curated-deck allowlist to exact artefact counts
- **PR #441**: docs(layout): state the three DRC control outcomes and the per-strap VDD trunk gaps
- **PR #434**: test: verify the emitted model-input capture with the production reader
- **PR #432**: test: pin pre-change tuning row so the byte-identical check always runs
- **PR #429**: layout: add TopMetal2 ground chip-level pin on the bottom guard-ring bar
- **Issue #444** (closed): docs(layout): drc.sh file header still states the 0.6.0 `8 Cnt.c hits` story as present fact
- **Issue #440** (closed): docs(layout): two measurable claims in PROVENANCE §17 / README do not match the committed records
- **Issue #439** (closed): layout: ground-pin stack height assumes via_stack pad symmetry, and generate.sh never asserts the artifact bbox
- **Issue #438** (closed): layout: drc.sh curated-deck gate permits activ.enclosing.cont.1 at any count
- **Issue #433** (closed): Exercise the real overlay capture and remove the Python manifest-writer copy
- **Issue #427** (closed): layout: expose VCO ground net `0` on top metal at the bottom edge for parent supply routing
- **Issue #426** (closed): Remove the tuning fixture’s dependency on a local copy of the old bench

### 2026-11-22

- **PR #437**: layout: extract LVS gate/record Python from lvs.sh heredoc into tracked lvs_record.py
- **PR #419**: docs(lvs): split the section 14.6 draft into two IHP runset reports with fix proposals
- **Issue #430** (closed): Move the LVS record writer into the existing Python compile gate
- **Issue #417** (closed): lvs: prepare the two IHP runset reports (inductor terminal order; LA/LB texts as net names) and the tool-fix proposal for operator review (preparation authorised by the #162 ruling)
- **PR #421**: build: bump pinned klt to 0.9.2 (ihp-sg13g2 runset allowlist) and re-render signoff
- **Issue #416** (closed): Bump the klt pin 0.8.0 -> 0.9.2 (release carrying the ihp-sg13g2 runset digest allowlist) and re-render the signoff bundle

### 2026-11-18

- **PR #413**: docs(yield): state the row-6 cross-netlist pairing claim and its re-derived correlations
- **Issue #244** (closed): T1 item 6: declare the statistical spec rows and plan the klt yield campaign for the oscillator core
- **PR #412**: ci: add merge_group trigger and adapt the PR-metadata gates
- **Issue #410** (closed): Merge queue: add the merge_group trigger and adapt the PR-metadata gates
- **PR #408**: gitignore: ignore klt run scratch (.klt/) at any depth
- **Issue #407** (closed): gitignore: .klt/ scratch under sim/ is untracked and un-ignored
- **PR #406**: sim: run the AC 4c yield stages and cover statistical rows 3 and 6

### 2026-11-17

- **PR #373**: docs: quote band-centre mismatch sigma_f0 (3.6 MHz) in yield summary lines
- **Issue #367** (closed): Record's summary sigma_f0 for the mismatch instrument (~4 MHz) is the Vctrl=0 endpoint spread, not the graded band-centre sigma (3.57 MHz)
- **PR #400**: fix: dedup unmerged git-ls-files paths in signoff inventory candidates
- **Issue #399** (closed): signoff inventories: git ls-files duplicates an unmerged path, so a conflicted tree can inventory a member 3x
- **PR #398**: fix: derive signoff inventory candidates from git-tracked files
- **Issue #397** (closed): signoff/inventories.py: _tracked_files() globs the filesystem, so an untracked file can join (or break) an inventory
- **PR #396**: docs: drop closed 30-day-window clause from WORK_LOG preamble
- **Issue #395** (closed): WORK_LOG.md header still claims a 30-day window ending 2026-10-07 while entries run to 2026-11-17
- **PR #393**: fix: count and name unpaired decks in the deck-integrity gate
- **Issue #392** (closed): deck-integrity verifies 36 of 37 tracked decks, and its unpaired counter cannot show the gap
- **PR #391**: docs: add signoff/pin-safety.md, the hash-pinned surface audit and edit runbook
- **PR #390**: fix(signoff): pin item-6 yield citations to the samples documents, not the envelopes
- **PR #388**: chore(loom): resync installed Loom to v0.19.1306

### 2026-11-16

- **PR #375**: chore(loom): resync installed Loom to v0.19.1302
- **PR #383**: docs: audit flat device/node-name dependencies on design/vco.spice
- **Issue #379** (closed): Audit flat device/node-name dependencies on design/vco.spice (read-only; collapse deferred)
- **PR #377**: fix: run signoff/layout heredoc gates with python3 -I so PYTHONOPTIMIZE cannot strip their asserts
- **Issue #374** (closed): check-signoff.sh's payload gate runs under a bare `python3 -`: cwd on sys.path, PYTHONOPTIMIZE can strip its asserts
- **PR #378**: docs: wire #362/#363 ownership of spec rows 5 and 9 into the signoff row map
- **Issue #361** (closed): signoff: spec rows 5 (tank Q) and 9 (pushing) have no owning issue after #337's attribution fix
- **PR #372**: docs: make signoff README build-identity prose pin-derived
- **Issue #369** (closed): signoff/README.md quotes stale per-pin build-identity values (git_tag v0.7.0, grading_ruleset_id) that no check validates
- **PR #371**: Gate regen-signoff render on build identity: release, clean, pinned tag
- **Issue #368** (closed): regen-signoff.sh ambient-match path cannot tell a pinned release from a dev build that reports the pin
- **PR #357**: docs: reconcile the row set owed by #50 across ROADMAP and the signoff row map
- **Issue #337** (closed): docs: ROADMAP.md and characterization-rows.json disagree on which spec rows #50 owes
- **PR #366**: signoff: guarded atomic regen for t1-report.json (klt-pin helper + wrapper)
- **Issue #360** (closed): signoff regen path has no version guard: a mismatched klt silently rewrites the verdict-of-record

### 2026-11-15

- **PR #364**: sim: run the anchor-1 Monte Carlo yield campaign and cite it for T1 item 6
- **PR #358**: docs: pin the signoff regen's klt invocation via uvx at the klt-version pin
- **Issue #352** (closed): docs: the new CLAUDE.md/AGENTS.md signoff bullet states the klt pin but not how to invoke it
- **PR #353**: fix: pn_summary_rows_common fails loudly on an unknown section name
- **PR #351**: ci: compare friction-ledger statuses against the klayout-tools tracker
- **Issue #346** (closed): pn_summary_rows_common emits nothing, and exits 0, on an unrecognized section name
- **Issue #333** (closed): ci: klt-friction-ledger.json upstream states go stale (2 of 31 entries wrong), and nothing re-checks them
- **PR #355**: fix: include row 7 in run_pilot_grid.sh's graded-row list and refresh signoff pins
- **Issue #354** (closed): docs: run_pilot_grid.sh omits row 7 from the graded row set, in a sha256-pinned file (split from #337)
- **PR #350**: docs: point agent instructions at the signoff inventory regen requirement
- **PR #345**: docs: correct README status paragraph against graded records and link ROADMAP.md
- **Issue #347** (closed): docs: warn that editing README.md requires regenerating the T1 item 10 signoff inventory
- **Issue #331** (closed): docs: bring the README status paragraph up to the records on main and link ROADMAP.md
- **PR #348**: fix(friction): enumerate tracked files with git only in check_klt_friction
- **PR #344**: sim: consolidate the duplicated ISF reduce-and-publish block into pn_bench.sh
- **PR #343**: layout: add klt erc supply-spec evidence for vco.gds (ERC half of T1 item 11)
- **Issue #341** (closed): Consolidate the duplicated ISF reduce-and-publish block into pn_bench.sh
- **Issue #339** (closed): Remove the os.walk fallback in check_klt_friction.tracked_files: it is the only path the self-test exercises, and it scans untracked files
- **Issue #330** (closed): layout: klt erc supply spec and run for layout/vco.gds (ERC half of T1 item 11, split from #37)

### 2026-11-14

- **PR #340**: chore: drop the dangling worktree:return npm alias
- **Issue #338** (closed): Remove the dangling npm worktree:return alias from package.json (exits 127)
- **PR #336**: sim: reduce the 135-corner ISF grid per corner, with its own carrier, spacing and port noise
- **PR #335**: refactor(signoff): consolidate the evidence-envelope scaffolding into _evidence.py
- **PR #328**: docs: roadmap as of 2026-11-13
- **Issue #329** (closed): sim/phase-noise: per-corner ISF reduction driver for the 135-corner grid (part of #53)
- **Issue #334** (closed): Dedup the signoff evidence-envelope scaffolding shared by signoff/characterization.py and signoff/inventories.py

### 2026-11-12

- **PR #326**: sim: graded phase-noise grid entry point, per-corner generator and completeness grader

### 2026-11-11

- **PR #322**: refactor(design): netlist via klt netlist instead of raw xschem wrapper
- **PR #320**: docs(spec): state clock output swing, load and common mode against a downstream need
- **Issue #321** (closed): Simplify design/netlist.sh: replace raw xschem wrapper with klt netlist
- **Issue #319** (closed): spec: state clock output swing and load for a downstream TX mux

### 2026-11-10

- **PR #318**: ci: add 50-loop record-id-selftest confirmation job for the runner image
- **PR #317**: drc: record nwell.enclosing.pactiv.1 x64 as curated-rule artefact
- **PR #316**: layout: add TopMetal2 VCTRL chip-level pin on the bbox bottom edge
- **PR #313**: fix: decide record-id ownership with an O_EXCL lock, not mkdir
- **PR #310**: sim: attribute 125 C dsubw start-up abort to NaN junction capacitance
- **Issue #315** (closed): DRC: nwell.enclosing.pactiv.1 reported on varactor banks (BANKP/BANKN) when placed in an integrated top
- **Issue #314** (closed): layout: expose VCTRL as a top-metal pin at the bbox edge (parent keep-out forbids Metal3-5 access)
- **Issue #312** (closed): test flake: record-id-selftest concurrent reservation fails on sim-append-only (recurrence of #273, #305)
- **Issue #309** (closed): sim: trace why ~16 nA of dsubw leakage aborts the 125 C first timepoint at xq1 (physical vs solver artefact)

### 2026-11-08

- **PR #307**: test: print mkdir implementation in record-id concurrency failure output
- **Issue #305** (closed): test flake: record-id-selftest 'concurrent distinct' fails on sim-append-only (recurrence of #273)

### 2026-11-07

- **PR #306**: test: trace record-id reservation attempts and force the collision path
- **PR #303**: sim: trace dsubw diode TNOM reference as the cure for the 125 C start-up abort
- **Issue #302** (closed): sim: trace which element's TNOM dependence clears the 125 C start-up abort (variant e)

### 2026-11-06

- **PR #298**: sim: bisect 125 C start-up abort with single-change fleet variants
- **Issue #297** (closed): sim: bisect the 125 C VBIC start-up abort with the untried start-up variants on the fleet
- **PR #296**: remove OSDI-free varactor surrogate generator and tests
- **Issue #292** (closed): Remove OSDI-free varactor surrogate (#179): stop-gap for blocker that fleet runs now bypass

### 2026-11-05

- **PR #295**: signoff: declare item-6 statistical row set in manifest spec_rows
- **PR #293**: sim: record post-#79 ISF phase-noise pilot from the fleet and update pre-#79 pointers
- **PR #291**: sim: record post-#79 elaboration/start-up check on the fleet with the OSDI varactor
- **PR #290**: sim: re-measure 199 estimator-errored post-#79 units on the fleet and grade rows 1-3/7 at -40/27 C
- **PR #289**: sim: grade existing post-#79 fleet PVT grid CSV (all curves incomplete)
- **PR #288**: sim: add post-#79 PVT grid request and ungraded fleet sweep record
- **Issue #94** (closed): sim: regenerate design/run_elaborate.sh, sim/oscillator-core and sim/phase-noise for the post-#79 netlist (blocked: OSDI varactor cannot run locally or on the fleet)
- **PR #285**: sim: record OSDI op-only run at 27 C on ngspice-46 (NaN not reproduced)
- **Issue #252** (closed): design/vco.spice at 17e49a8 fails DC operating point (NaN) with the OSDI varactor under ngspice-47

### 2026-11-03

- **PR #281**: sim: classify 125 C start-up failure and reproduce OSDI varactor on fleet
- **Issue #280** (closed): sim: pinned VCO C-grid with the prescaler load: 0 of 162 corners in band, 125 C does not start, OSDI varactor runs on the fleet
- **PR #277**: design: add vco_core subcircuit, symbol and device-equivalence guard
- **Issue #276** (closed): design: export the VCO core as a subcircuit with a symbol (the pinned vco.spice is a flat bench, not instantiable)

### 2026-10-28

- **PR #274**: test(sim): capture per-caller output in the concurrent record-id self-test
- **Issue #273** (closed): test flake: record-id-selftest concurrent distinct count fails on sim-append-only
- **PR #271**: chore(signoff): vendor klt 0.8.0 tiers checklist and re-render t1-report
- **Issue #270** (closed): T1 grading: re-vendor the v0.8.0 checklist doc (signoff/design-evidence-tiers.md is still klt v0.6.0's) and re-render t1-report.json

### 2026-10-27

- **PR #269**: docs(friction): rerun runnable ledger workarounds at 0.8.0 and dry-run supply_v requests
- **Issue #264** (closed): Bump klayout-tools pin 0.6.0, 0.7.0, 70dee3b679a6 → 0.8.0
- **PR #265**: build: bump klayout-tools pin to 0.8.0 and re-verify friction ledger
- **PR #262**: feat(signoff): generate and gate the T1 item 8 characterization report
- **Issue #261** (closed): T1 item 8 (characterization report): aggregate the 12 ratified rows into one current characterization record

### 2026-10-23

- **PR #258**: feat(sim): store tank A/B outputs as per-unit archives and commit live manifest
- **PR #257**: feat(sim): store tank A/B raw outputs via the artifact writer
- **PR #256**: test: build no-python3 stub dir without readlink -f
- **PR #254**: feat(sim): manifest-forward evidence writer and offline manifest gate
- **Issue #255** (closed): CI lint: 'dispatcher no python3' self-test fails on main (rc=2 but 'python3 not found' not matched)
- **Issue #253** (closed): Adopt the common artifact store for sim evidence (manifests in git, bytes via klt artifact)

### 2026-10-17

- **PR #251**: docs(friction): record klt 0.7.0 batch runs reaching the fleet
- **PR #249**: docs(friction): record klt 0.7.0 retirement attempts and keep six workarounds
- **PR #247**: docs(spec,sim): classify statistical spec rows and plan the Monte Carlo yield campaign
- **PR #246**: feat(signoff): cite T1 items 1, 9, 10 with artifact-anchored inventories
- **PR #245**: feat(signoff): cite DRC envelope for T1 item 3 with coverage disclosure
- **PR #241**: refactor: share one IHP-Open-PDK resolver across layout and EM extraction
- **Issue #250** (closed): Investigate: klt sim --backend batch ran locally with no environment.remote job id (klt 0.7.0)
- **Issue #248** (closed): Follow-on from PR #246: retire klt-friction workarounds for ledger entries now closed upstream in 0.7.0
- **Issue #243** (closed): T1 items 1, 9 and 10: cite artifact-anchored evidence (design-source, testbench and hygiene inventories)
- **Issue #242** (closed): T1 item 3: cite the clean IHP-native DRC report in signoff/manifest.json, with its coverage disclosed
- **Issue #240** (closed): Consolidate the four copied IHP-Open-PDK resolution blocks (layout + EM extraction) into one sourced helper

### 2026-10-16

- **PR #71**: fix(netlist): pass -x to xschem so batch netlisting is headless

### 2026-10-15

- **PR #236**: ci: wire layout-evidence self-test into check-all.sh (fixes test-wiring on main)
- **Issue #235** (closed): CI: test-wiring fails on main — test-check-layout-evidence.sh has no check-all.sh target or test-wiring.tsv row

### 2026-10-14

- **Issue #43** (closed): README: embed the fleet burndown chart (one line)

### 2026-10-13

- **PR #108**: ci: gate layout records' GDS digests against committed vco.gds
- **Issue #106** (closed): ci: gate layout records' GDS digests against the committed layout/vco.gds (PDK-free)

### 2026-10-11

- **PR #231**: ci: fail when a shell self-test is not wired into check-all test (orphan-test guard)
- **Issue #228** (closed): ci: fail when a self-test script is not wired into any check-all gate (orphan-test guard)
- **Issue #218** (closed): Guard parity: clock sleep tool blocked as unknown
- **PR #230**: ci: accept optional model-overlay role in model-inputs gate
- **Issue #221** (closed): ci: validate retained model-overlay inputs from the current simulation writer
- **PR #227**: sim: validate complete EM comparison inputs before publishing evidence
- **Issue #224** (closed): sim: validate complete EM comparison inputs before publishing evidence
- **PR #226**: sim: reserve EM comparison record ownership before opening outputs
- **Issue #225** (closed): sim: reserve EM comparison record ownership before opening outputs

### 2026-10-10

- **PR #223**: fix(currency): history-independent record-currency index (#213)
- **Issue #213** (closed): Record currency depends on clone-local commit availability

### 2026-10-10

- **PR #220**: ci: run raw-trace gate fixture in grading-fixture dispatcher
- **Issue #212** (closed): Guard telemetry: preserve stash scope protection
- **Issue #217** (closed): ci: run the phase-noise raw-trace regression in the shared grading fixtures

### 2026-10-10

- **PR #216**: sim: validate passive-tank candidate paths and finite sizing
- **PR #215**: sim: propagate passive-tank fleet collection failures to exit status
- **PR #214**: fix(sim): reserve surrogate bench evidence before publication
- **PR #211**: ci: run the OSDI staging regression through the shared check runner
- **PR #208**: sim: preserve suffixed directory identities in currency citation lookup
- **PR #207**: sim: reject empty tank evidence inventories in strict analysis
- **PR #204**: sim: reserve tank A/B record namespaces before fleet submission
- **PR #205**: ci: fail Python test gates when discovery finds zero tests
- **PR #201**: Install ratification reviewer trees; correct DR-003/004/005 Status (#99)
- **PR #200**: docs: README status points to DR-006 gate, not closed #93
- **PR #197**: ci: scan paired deck integrity for unrecognized record names
- **Issue #210** (closed): sim: propagate passive-tank fleet collection failures to exit status
- **Issue #209** (closed): sim: validate passive-tank candidate paths and finite sizing
- **Issue #206** (closed): sim: reject empty tank evidence inventories in strict analysis
- **Issue #203** (closed): sim: reserve tank A/B record namespaces before fleet submission
- **Issue #202** (closed): ci: fail Python test gates when discovery finds zero tests
- **Issue #199** (closed): docs: README/sim README still describe closed #93 as in-flight; point to DR-006 gate
- **Issue #195** (closed): sim: preserve suffixed directory identities in currency citation lookup
- **Issue #194** (closed): ci: scan paired deck integrity even when a record name is unrecognized
- **Issue #191** (closed): sim: reserve surrogate bench evidence before publication
- **Issue #190** (closed): Review temporary-fixture write guards
- **Issue #189** (closed): Review temporary-directory cleanup guards
- **Issue #182** (closed): ci: run the OSDI staging regression through the shared check runner
- **Issue #99** (closed): Install ratification/ee-key and ratification/market-key reviewer trees (product#151)

### 2026-10-10

- **PR #193**: sim: validate every surrogate probe sample before domain classification
- **PR #188**: fix(supply-stage2): validate finite numbers before grading (#175)
- **PR #187**: sim: compare complete captured model identities in the supply report
- **PR #186**: spec: DR-006 (proposed) resolving the row-1/row-2 shortfall for the bn=substrate varactor
- **PR #185**: docs: reconcile current LVS, supply and OSDI blocker descriptions
- **PR #181**: sim: OSDI-free charge-based varactor surrogate for transient screening (#179)
- **PR #180**: sim: stage, validate and atomically publish OSDI outside the PDK (#96)
- **PR #178**: sim: apply the fleet guard to DR-004 stage-2 parent drivers (#176)
- **PR #174**: ci: reject malformed paired simulation reports in the deck integrity gate
- **PR #169**: sim: run-local svaricap dsubw vj overlay (IHP-Open-PDK PR #1102), retire tnom workaround
- **PR #172**: ci: reject paired report/deck digest mismatches at evidence consumption
- **PR #170**: sim: EM post/fit preflight all geometries and publish staged outputs
- **Issue #192** (closed): sim: validate every surrogate probe sample before domain classification
- **Issue #175** (closed): sim: reject malformed numeric inputs before supply escalation arithmetic
- **Issue #177** (closed): sim: compare complete captured model identities in the supply report
- **Issue #184** (closed): spec: author DR-006 resolving the row-1/row-2 shortfall for the bn=substrate varactor (#93 handoff)
- **Issue #183** (closed): docs: reconcile current LVS, supply and OSDI blocker descriptions
- **Issue #179** (closed): sim: OSDI-free charge-based varactor surrogate for transient/ISF screening while #94 is blocked
- **Issue #96** (closed): sim/tools/build-osdi.sh overwrites the shared PDK's mosvar.osdi without checking the host ngspice's OSDI ABI
- **Issue #176** (closed): sim: apply the fleet guard to DR-004 stage-2 parent drivers
- **Issue #173** (closed): ci: reject malformed paired simulation reports in the deck integrity gate
- **Issue #95** (closed): sim: PDK dsubw junction model (vj=0.1) goes NaN above ~52 C once bn is on the substrate -- row 11's +125 C cannot be simulated with the card as shipped
- **Issue #143** (closed): ci: reject paired simulation report/deck digest mismatches at evidence consumption
- **Issue #167** (closed): sim: preserve EM post/fit outputs when geometry inputs are incomplete
- **Issue #166** (closed): sim: validate passive-tank measurements and retained request corner coverage
- **PR #168**: analyze.py: validate tank corners and report request coverage (#166)
- **PR #164**: sim: refuse local multi-point grids when batch backend is exported
- **PR #165**: tests: known-answer tests for verify, lvs_break, ihp_deck_facts
- **PR #163**: feat(layout): label-ordered inductor terminal step for LVS (L1 mirrored spiral, #80)
- **PR #159**: sim: validated checkpoint reuse when restarting the PVT sweep
- **PR #158**: sim: validate phase-noise raw waveforms before ISF extraction
- **Issue #160** (closed): sim: refuse local multi-point PVT grids when the batch backend is exported
- **Issue #161** (closed): ci: known-answer tests for verify.py, lvs_break.py, ihp_deck_facts.py and measure_ports.py
- **Issue #80** (closed): lvs: IHP sg13g2.lvs orders inductor terminals by x position, so mirrored spiral L1 compares with its windings reversed (blocks #62 LVS match)
- **Issue #154** (closed): sim: reuse validated completed points when restarting the long PVT sweep
- **Issue #157** (closed): sim: validate phase-noise raw waveforms before ISF extraction

### 2026-10-09

- **PR #156**: sim: require exact corner identities for the global row-3 verdict
- **PR #152**: sim: reject decimal overflow in oscillator waveform validity (#151)
- **PR #150**: ci: require PDK and OSDI identities in model-input captures
- **Issue #153** (closed): sim: require exact corner identities for the global row-3 verdict
- **Issue #151** (closed): sim: reject decimal overflow in oscillator waveform validity checks
- **Issue #148** (closed): ci: require PDK and OSDI identities in model-input captures

### 2026-10-09

- **Issue #146** (closed): docs: track filed klayout-tools friction in a checked ledger tied to the klt pin
- **PR #147**: docs: track filed klayout-tools friction in a checked ledger tied to the klt pin
- **Issue #93** (closed): design: re-tune the tank against the corrected varactor bn=substrate netlist (band centre fell to ~4.3 GHz, tuning ratio ~1.11; #79 follow-up)
- **PR #145**: design: #93 tank re-tune vs bn=substrate netlist -- no defensible candidate, decision needed
- **Issue #139** (closed): ci: verify retained model-input manifests against committed snapshots
- **PR #142**: ci: verify retained model-input manifests against committed snapshots
- **Issue #138** (closed): ci: verify grader constants agree with ratified spec bounds
- **PR #141**: ci: verify grader constants agree with ratified spec bounds
- **Issue #137** (closed): sim: reject non-finite and incomplete phase-noise measurements
- **PR #140**: sim: reject non-finite and incomplete phase-noise measurements
- **Issue #122** (closed): ci: compute which sim records are current vs superseded against design/vco.spice
- **PR #128**: ci: compute sim record currency against design/vco.spice (#122)
- **Issue #129** (closed): analysis: PDK-free analytic tank screen to prune the #93 re-tune while the OSDI path (#94) is blocked
- **PR #130**: analysis: PDK-free analytic tank screen with A/B known-answer test
- **Issue #126** (closed): ci: add job timeouts and SHA-pinned actions to all workflows
- **PR #131**: ci: add job timeouts and SHA-pinned actions (#126)
- **Issue #132** (closed): ci: run simulator-free grading fixtures in the lightweight gate aggregate
- **Issue #133** (closed): sim: capture stable model inputs before long oscillator and phase-noise runs
- **PR #134**: ci: run simulator-free grading fixtures in test/ci aggregates (#132)
- **PR #135**: sim: capture stable model inputs before oscillator and phase-noise runs (#133)
- **Issue #79** (closed): design: varactor bn (p-substrate) is tied to the tank node in design/vco.sch -- physically unrealizable; correct the schematic and re-run the evidence it moves (blocks #62 LVS match)
- **Issue #88** (closed): ci: enforce append-only sim/ evidence (records, netlist-snapshots, corners) at PR time
- **Issue #89** (closed): ci: require a decision record in the same PR as any spec/target-spec.md edit
- **PR #91**: ci: enforce append-only sim/ evidence at PR time
- **PR #92**: ci: require a decision record with any spec/target-spec.md edit
- **PR #97**: design: tie varactor bn to the substrate (0), correct LVS bn difference, measure tank effect (#79)
- **Issue #98** (closed): ci: shellcheck gate for repo-owned shell scripts
- **PR #100**: ci: shellcheck warning+ gate over tracked scripts (#98)
- **PR #101**: layout: re-run LVS after #79 and re-check the klt gap at 0.7.0 (still mismatch; Part of #62)
- **Issue #102** (closed): sim: reserve unique record namespaces before writing append-only evidence
- **Issue #103** (closed): ci: run PDK-free known-answer measurement checks
- **PR #104**: sim: reserve unique record namespaces before writing append-only evidence
- **PR #105**: ci: run PDK-free known-answer measurement checks
- **Issue #107** (closed): ci: single-source the pinned klayout-tools version
- **PR #109**: ci: single-source the pinned klayout-tools version
- **Issue #110** (closed): Guard telemetry: preserve worktree write confinement
- **Issue #111** (closed): sim: grade ratified row-3 window coverage, slope and chord linearity
- **Issue #112** (closed): sim: grade row-7 swing and cycle-minimum HBT compliance
- **Issue #113** (closed): sim: implement DR-004 stage-2 supply sub-corners and escalation report
- **PR #114**: sim: grade ratified row-3 window coverage, slope and chord linearity
- **PR #115**: sim: grade row-7 swing and cycle-minimum HBT compliance (#112)
- **PR #116**: sim: DR-004 stage-2 supply sub-corners and escalation report
- **Issue #117** (closed): ci: replace package.json test/check:ci/check:all placeholders with the real PDK-free gates
- **Issue #118** (closed): ci: gate the layout and sim Python with py_compile and PDK-free known-answer tests
- **Issue #119** (closed): sim: integrate landed row-7 compliance grading into stage-2 supply comparisons
- **PR #120**: ci: route npm test/check:ci/check:all and CI steps through one gate runner
- **PR #121**: sim: grade row 7 per rail in DR-004 stage-2 supply comparisons
- **PR #123**: ci: python workflow with py_compile, stdlib and klayout known-answer tests (#118)
- **Issue #124** (closed): docs: mark pre-#79 simulation numbers in sim/README.md, design/README.md and README.md
- **PR #125**: docs: mark pre-#79 simulation numbers in READMEs (#124)

### 2026-10-08

- **Issue #82** (closed): sim: require complete voltage coverage before grading tuning curves
- **Issue #83** (closed): sim: reject missing transient measurements instead of reporting zero power
- **PR #86**: sim: reject missing transient measurements instead of reporting zero power
- **PR #87**: sim: require complete voltage coverage before grading tuning curves
- **PR #81**: feat(layout): device-aware LVS runner and record (verdict: mismatch) + signoff item 2

### 2026-10-07

- **Issue #61** (closed): layout: DRC closure for sg13g2-vco GDS (T1 item 1/2, part 2/3)
- **PR #76**: feat(layout): close native DRC with a reviewed coverage assertion

### 2026-10-02

- **Issue #60** (closed): layout: floorplan, device placement and routing — draw sg13g2-vco GDS/OASIS (T1 item 1/2, part 1/3)
- **PR #73**: feat: draw sg13g2-vco layout as a reproducible klt-generated GDS
- **PR #74**: fix: clear the VCTRL tap metal1.space violations and commit DRC evidence
- **PR #75**: fix: drive IHP's own DRC runset to zero findings on the vco layout

### 2026-10-01

- **Issue #63** (closed): Dedup design/run_elaborate.sh's read_osc() into sim/lib.sh's method-checked osc_metrics()
- **PR #72**: refactor: dedup run_elaborate.sh extractors into sim/lib.sh helpers

### 2026-09-27

- **Issue #55** (closed): Consolidate the six copied ngspice model-resolution-error greps into one sim/lib.sh helper
- **Issue #64** (closed): Consolidate the triplicated PDK-digest provenance block into osc_bench.sh
- **Issue #65** (closed): Wire failed_points into the exit gates of the three sim/*/run_*.sh scripts (they report device-row failures but exit 0 on them)
- **Issue #66** (closed): Extract the triplicated ideal-RLC reference network out of the three SPICE testbench templates (the half #22 left behind)
- **PR #67**: sim: consolidate the triplicated PDK-digest provenance block into osc_bench.sh
- **PR #68**: sim: extract the triplicated ideal-RLC reference network into sim/testbench-common/ref-network.inc
- **PR #69**: refactor: consolidate ngspice model-resolution-error greps into sim/lib.sh
- **PR #70**: fix: make sim evidence-script exit gates honor failed_points
