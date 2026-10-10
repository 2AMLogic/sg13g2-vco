# Work Log

Merged PRs and closed issues from the 30-day bootstrap window ending
2026-10-07. Entries record forge events; closure alone does not assert that
engineering acceptance criteria passed. Guide maintenance PRs are excluded.

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

### 2026-09-26

- **Issue #47** (closed): sim: oscillator-core testbench — start-up, f_osc/tuning range and large-signal supply current vs Vctrl over PVT, against design/vco.sch
- **Issue #49** (closed): sim: phase-noise measurement bench for design/vco.sch (spec row 4) — estimator choice, variance and stated limits
- **PR #51**: sim: add oscillator-core bench and its measured pilot subset for design/vco.sch
- **Issue #52** (closed): Dedup the MOS/diode sweep loop bodies in run_varactor_sweep.sh (the ~61 lines #29 left behind)
- **PR #54**: sim: ISF phase-noise bench for design/vco.sch — estimator, variance and stated limits (row 4)
- **PR #56**: sim: collapse the MOS/diode sweep loops in run_varactor_sweep.sh into sweep_family()
- **Issue #57** (closed): spec: target-spec ratification pass 2 (DR-004) — dispose rows 0, 3 and 7, whose DR-003 gates have all landed
- **PR #58**: spec: ratify target-spec rows 0, 3 and 7 in DR-004 (pass 2)

### 2026-09-25

- **Issue #44** (closed): design: author design/vco.sch (xschem) + derived netlist — LC-VCO core on DR-001/DR-002, with the tank sizing row 3 waits on
- **PR #45**: design: LC-VCO core schematic design/vco.sch + derived netlist
- **Issue #46** (closed): signoff: bump the klt pin 0.5.0 → released 0.6.0 and refresh the stale vendored tiers doc
- **PR #48**: signoff: bump the klt pin 0.5.0 → released 0.6.0 and refresh the stale vendored tiers doc

### 2026-09-21

- **Issue #33** (closed): Author negative-gm pair architecture decision record: device class/topology for the SG13G2 LC-VCO
- **Issue #34** (closed): Commit a klt signoff block manifest so this block's T1 state is graded, not hand-read
- **Issue #35** (closed): spec: ratify target-spec.md — it is DRAFT, which blocks T1 item 5 (and items 6/7/8 that grade against its rows)
- **PR #36**: docs: add DR-002 negative-gm pair device-class decision record
- **PR #38**: feat: add klt signoff block manifest with CI verdict-drift gate
- **PR #39**: docs: add DR-003 target-spec ratification (9 rows as targets, 3 open)
- **Issue #40** (closed): docs: signoff/README.md still says target-spec is DRAFT after DR-003 partial ratification
- **PR #41**: docs: reword signoff README all-unmet justification post DR-003

### 2026-09-15

- **Issue #15** (closed): [worker identifier redacted] wins the #9 dispatch lease repeatedly but leaves no build evidence (silent failure or timeout?)
- **Issue #31** (closed): Author the tuning-mechanism decision record: MOS accumulation varactor vs. junction-diode varactor
- **PR #32**: docs: add DR-001 tuning-mechanism decision record

### 2026-09-10

- **Issue #9** (closed): EM-extract the SG13G2 spiral-inductor PCell and fit a lumped model to replace the analytic screening model
- **Issue #20** (closed): Fix stale sim/README.md claim: env.sh is not sourced by every run script
- **PR #21**: docs: fix stale env.sh "sourced by every run script" claim in sim/README.md
- **Issue #22** (closed): Dedup ideal-RLC known-answer check into sim/lib.sh
- **PR #23**: sim: EM-extract the SG13G2 spiral-inductor PCell with openEMS, fit a lumped model
- **PR #24**: refactor: dedup ideal-RLC known-answer check into sim/lib.sh
- **Issue #25** (closed): Dedup sha256_of between sim/lib.sh and sim/tools/build-osdi.sh
- **PR #26**: sim: dedup sha256_of between sim/lib.sh and sim/tools/build-osdi.sh
- **Issue #27** (closed): Dedup sha256() between compare_analytic.py and run_openems.py
- **PR #28**: sim: dedup sha256() between compare_analytic.py and run_openems.py
- **Issue #29** (closed): Dedup Kvco-report block in run_varactor_sweep.sh (MOS vs diode sweeps)
- **PR #30**: sim: dedup Kvco-report block in run_varactor_sweep.sh (MOS vs diode sweeps)

### 2026-09-09

- **Issue #11** (closed): Provision an EM-solver toolchain (openEMS/Palace) for SG13G2 spiral-inductor extraction (#9 blocker)
- **Issue #12** (closed): Dedupe shared bash helpers between run_pvt_sweep.sh and run_model_check.sh
- **Issue #14** (closed): Extract shared record-scaffolding helpers out of sim/*/run_*.sh
- **Issue #16** (closed): Extract shared scaffolding out of the two sim run scripts into sim/lib.sh
- **PR #17**: sim: extract shared scaffolding into sim/lib.sh
- **Issue #18** (closed): sim: varactor characterization — C(V), dC/dV and Q(V, f) of `sg13_hv_svaricap` vs the junction-diode candidates over PVT, the tuning-mechanism evidence for target-spec rows 2/3 (independent of #9)
- **PR #19**: sim: varactor characterization — C(V), dC/dV, Q(V,f) of sg13_hv_svaricap vs junction diodes

### 2026-09-08

- **Issue #13** (closed): Champion: Merge-Risk Hold Digest
