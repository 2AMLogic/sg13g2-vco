# Work Log

Merged PRs and closed issues from the 30-day bootstrap window ending
2026-10-07. Entries record forge events; closure alone does not assert that
engineering acceptance criteria passed. Guide maintenance PRs are excluded.

### 2026-11-08

- **PR #307**: test: print mkdir implementation in record-id concurrency failure output
- **Issue #305** (closed): test flake: record-id-selftest 'concurrent distinct' fails on sim-append-only (recurrence of #273)
- **PR #407**: sim: probe the two Row 4b band-edge kickback rejects (supplement)
- **Issue #405** (closed): Probe the two Row 4b band-edge kickback rejects (DR-0004 gate)

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
- **PR #403**: sim: complete max-step supplement with vcm-p050 populations 60/60
- **PR #402**: sim: record partial max-step supplement re-run (4 of 6 populations 60/60)

### 2026-11-03

- **PR #281**: sim: classify 125 C start-up failure and reproduce OSDI varactor on fleet
- **Issue #280** (closed): sim: pinned VCO C-grid with the prescaler load: 0 of 162 corners in band, 125 C does not start, OSDI varactor runs on the fleet
- **PR #277**: design: add vco_core subcircuit, symbol and device-equivalence guard
- **Issue #276** (closed): design: export the VCO core as a subcircuit with a symbol (the pinned vco.spice is a flat bench, not instantiable)
- **PR #400**: sim(pex): record failed extracted offset MC at tt/-40C/1.32V, extracted side lost
- **PR #399**: sim(pex): record extracted whole-latch offset MC, 48 of 60 samples at tt/125C/1.32V via batch
- **PR #398**: sim(pex): record extracted offset MC at tt/125C/1.08V, 57 of 60 samples via batch
- **PR #397**: sim(pex): record extracted offset MC at tt/-40C/1.08V, 57 of 60 samples via batch
- **PR #396**: sim(pex): record extracted offset MC at sf/-40C/1.20V, 57 of 60 samples via batch
- **PR #395**: sim(pex): record extracted offset MC at sf/125C/1.20V, 57 of 60 samples via batch
- **PR #394**: sim(pex): record extracted offset MC, 60 of 60 samples at fs/-40C/1.20V via batch

### 2026-11-02

- **PR #392**: sim(pex): record extracted offset MC at fs/125C/1.20V, 60 of 60 samples via batch

### 2026-11-01

- **PR #389**: sim(pex): record extracted whole-latch noise MC, 80 of 80 trials at ff/27C/1.32V via batch
- **PR #388**: sim(pex): record extracted whole-latch offset MC at ff/27C/1.32V (60/60) via batch
- **PR #387**: sim(pex): extracted whole-latch MC at ss/27C/1.08V (offset 60/60, noise 76/80) via batch
- **PR #386**: sim(pex): add per-point roll-up of recorded extracted Monte Carlo results
- **PR #385**: sim(pex): record extracted whole-latch noise MC at ss/-40C/1.08V, 80 of 80 trials via batch
- **PR #384**: sim(pex): record extracted whole-latch offset MC, 60 of 60 samples at ss/-40C/1.08V via batch
- **PR #383**: sim(pex): record extracted whole-latch noise MC at ff/125C/1.32V, 77 of 80 trials
- **PR #382**: sim(pex): record extracted offset MC at ff/125C/1.32V, 45 of 60 samples via batch
- **PR #380**: sim(pex): record extracted whole-latch noise MC at tt/-40C/1.20V, 80 of 80 trials via batch
- **PR #379**: sim(pex): record extracted whole-latch offset MC at tt/-40C/1.20V, 60 of 60 samples
- **PR #378**: sim(pex): record extracted whole-latch noise MC at tt/125C/1.20V, 77 of 80 trials via batch
- **PR #376**: sim(pex): record extracted whole-latch offset MC at tt/125C/1.20V, 60 of 60 samples via batch
- **PR #375**: sim(pex): record extracted whole-latch noise MC, 78 of 80 trials at tt/27C/1.08V
- **PR #374**: sim(pex): record extracted whole-latch offset MC at tt/27C/1.08V, 57 of 60 samples via batch
- **PR #372**: sim(pex): record extracted whole-latch noise MC at tt/27C/1.32V, 77 of 80 trials (Part of #61)

### 2026-10-31

- **PR #371**: sim(pex): record extracted whole-latch offset MC, N=60 at tt/27C/1.32V via sharded batch
- **PR #370**: sim(pex): record extracted whole-latch transient-noise MC at fs/27C/1.20V, 77 of 80 trials (Part of #61)
- **PR #369**: sim(pex): record extracted whole-latch offset MC at fs/27C/1.20V, 57 of 60 compared (Part of #61)
- **PR #368**: sim(pex): record extracted whole-latch transient-noise MC, N=80 at sf/27C/1.20V
- **PR #367**: sim(pex): record extracted whole-latch offset MC, N=60 at sf/27C/1.20V via sharded batch
- **PR #366**: sim(pex): record failed extracted offset MC attempt at sf/27C/1.20V (extracted side lost)
- **PR #365**: sim(pex): record extracted whole-latch noise MC, N=80 at ff/-40C/1.32V via sharded batch
- **PR #364**: sim(pex): record extracted offset MC at ff/-40C/1.32V, 57 of 60 samples (Part of #61)
- **PR #363**: sim(pex): record extracted whole-latch transient-noise MC, N=80 at ss/125C/1.08V via sharded batch
- **PR #362**: sim(pex): record extracted whole-latch offset MC, N=60 at ss/125C/1.08V via sharded batch
- **PR #361**: sim(pex): record extracted whole-latch transient-noise MC, N=80 at tt/27C/1.20V via batch
- **PR #360**: refactor(sim): reuse cmband's CM-band Condition grid in kickback_cmband
- **PR #359**: sim(pex): record extracted whole-latch offset MC at nominal point, N=60 via batch
- **PR #358**: sim(pex): express whole-latch MC requests and probe them on the batch fleet
- **PR #357**: sim(pex): record extracted 45-corner kickback grid via sharded batch
- **PR #355**: sim(pex): record sharded 45-corner extracted regeneration grid, 42 of 45 corners
- **Issue #356** (closed): Remove duplicated CM-band Condition table from kickback_cmband: reuse cmband's

### 2026-10-30

- **PR #353**: refactor(sim): reuse kcli._submit_with_retry in kickback and memory runners
- **PR #352**: sim(pex): record 3-unit extracted batch sample with td_c post-layout error
- **PR #350**: sim(pex): record failed 45-unit extracted regeneration batch job
- **PR #349**: refactor(scripts): share git()/resolve_tree() across evidence checkers
- **PR #348**: refactor(sim): share CM-band source-line rewrite across bench modules
- **PR #347**: sim(pex): record stalled 45-unit extracted regeneration batch job
- **PR #345**: sim(pex): size regeneration request timeout from measured unit runtime
- **PR #343**: docs(sim): record failed full regeneration PVT batch job and refused split
- **PR #342**: fix(sim): emit pex PVT supply as corners.params and record passing batch probe
- **Issue #351** (closed): Dedupe _submit_with_retry: remove two copies of kcli._submit_with_retry
- **Issue #346** (closed): Simplify: dedupe git()/resolve_tree() across three CI check scripts
- **Issue #344** (closed): Consolidate duplicated CM-band apply_transform across cmband, cmdecision, kickback_cmband

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
- **PR #338**: build: pin klayout-tools to release 0.8.0 and accept release pins in the drift guard
- **PR #218**: sim: max-step supplement workflow for aborted CM-band offset points (#89, partial: batch run failed)
- **PR #212**: sim: kickback residue at dut_vcm -/+50 mV as klt sim corner campaigns (#165)
- **PR #171**: sim: memory/hysteresis characterization bench (paired-history switching boundary over PVT) (Closes #159)
- **Issue #337** (closed): Bump klayout-tools pin 3a75c3ae705b → 0.8.0
- **Issue #165** (closed): sim: kickback residue at dut_vcm -/+50 mV as klt sim corner campaigns (evidence for DR-0004 CM-range row)
- **Issue #159** (closed): Memory / hysteresis characterization bench: does the previous decision bias the next?

### 2026-10-26

- **PR #199**: PEX diagnostic: extracted-device-only leg to separate device geometry from routing RC
- **Issue #322** (closed): DR-0031 is stale after #318: evidence-size exception no longer in force

### 2026-10-25

- **Issue #325** (closed): Remove scripts/diagnostics: completed #188 guard handoff package, unwired
- **Issue #263** (closed): Validate timestep smoke evidence before computing noise convergence

### 2026-10-24

- **PR #324**: Retire per-PR evidence-size exceptions; count evidence bytes only
- **Issue #323** (closed): Squash the 27 evidence-size exception records into one superseding record; replace the cap with the artifact store

### 2026-10-23

- **PR #258**: feat(sim): store tank A/B outputs as per-unit archives and commit live manifest
- **PR #257**: feat(sim): store tank A/B raw outputs via the artifact writer
- **PR #256**: test: build no-python3 stub dir without readlink -f
- **PR #254**: feat(sim): manifest-forward evidence writer and offline manifest gate
- **Issue #255** (closed): CI lint: 'dispatcher no python3' self-test fails on main (rc=2 but 'python3 not found' not matched)
- **Issue #253** (closed): Adopt the common artifact store for sim evidence (manifests in git, bytes via klt artifact)
- **PR #321**: Evidence manifests: artifact:<key> URIs, drop the bucket setting (klt 7e3561f+)
- **PR #319**: Store new sim evidence through the artifact store; commit manifests only (#318)
- **PR #270**: Validate CM decision timing dimensions and physical domains
- **PR #268**: Reject invalid local PVT grid inputs before simulation
- **PR #248**: estimate: resolve reference offset/yield N from committed tree metadata (#247)
- **PR #238**: Validate clock-supply probes and reject ambiguous sample identities
- **Issue #320** (closed): Evidence manifests: use artifact:<key> URIs and drop the bucket setting (klt 7e3561f+)
- **Issue #318** (closed): Write sim evidence through the fleet artifact store; commit manifests; restore the size ceiling against manifests
- **Issue #266** (closed): Validate CM decision timing dimensions and physical domains
- **Issue #247** (closed): Derive evidence-size estimate denominators from selected reference campaigns

### 2026-10-22

- **PR #276**: Mirror gf180's supplemental reverse-polarity ladder fragment (#274)
- **Issue #274** (closed): Mirror gf180's supplemental reverse-polarity ladder fragment (bench-structure parity, gf180-comparator#158/#166)

### 2026-10-21

- **PR #317**: test: show captured git output when sparse-checkout sh() fails
- **PR #313**: ci: make sim evidence-size check report-only while suspended
- **Issue #316** (closed): test flake: test_append_only_and_size_job_from_sparse_clone fails on append-only sim evidence
- **Issue #312** (closed): Suspend the sim/ evidence-size ceiling (report-only) until the fleet S3 evidence store lands

### 2026-10-20

- **Issue #278** (closed): Every evidence PR rewrites the same total-ceiling line in sim/evidence-size-budget.json
- **Issue #245** (closed): Validate actual Monte Carlo populations before compliance grading

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
- **PR #292**: refactor: remove three zero-caller helpers from sim harness and kltsim
- **Issue #295** (closed): Remove dead _spec_meas and dedupe cmband/cmdecision undo_transform
- **Issue #291** (closed): Remove four zero-caller helpers in sim/harness and sim/kltsim
- **Issue #289** (closed): Consolidate duplicated klt-sim fleet-cap retry loop (4 copies) and local smoke runner (2 copies) across campaign drivers
- **Issue #286** (closed): Remove scripts/diagnostics: delivered #188 guard-repro handoff, unreferenced

### 2026-10-16

- **PR #71**: fix(netlist): pass -x to xschem so batch netlisting is headless

### 2026-10-15

- **PR #236**: ci: wire layout-evidence self-test into check-all.sh (fixes test-wiring on main)
- **Issue #235** (closed): CI: test-wiring fails on main — test-check-layout-evidence.sh has no check-all.sh target or test-wiring.tsv row
- **PR #243**: Preserve derived campaign report pairs before regeneration (#237)
- **Issue #237** (closed): Preserve derived campaign report pairs before regeneration

### 2026-10-14

- **Issue #43** (closed): README: embed the fleet burndown chart (one line)

### 2026-10-13

- **PR #108**: ci: gate layout records' GDS digests against committed vco.gds
- **Issue #106** (closed): ci: gate layout records' GDS digests against the committed layout/vco.gds (PDK-free)

### 2026-10-12

- **PR #273**: Reject mixed-geometry sizing finalists in candidate Target summaries
- **PR #259**: yield: re-derive the index in the engine-free consistency check
- **Issue #269** (closed): Reject mixed-geometry sizing finalists in candidate Target summaries
- **Issue #267** (closed): Validate bias mirror headroom screening probes before aggregation
- **Issue #260** (closed): Auditor process proposal: run final evidence-size preflight before requesting review
- **Issue #257** (closed): Run implant geometry regression tests in the KLayout-equipped CI job

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
- **PR #239**: noise_full: validate provenance per tn_full_* config before arithmetic (#236)
- **PR #234**: check_readme_claims: pin README kickback residue claims to the historical harness record
- **PR #233**: docs: require evidence size check on final HEAD before review (#223)
- **PR #229**: Supplemental DRC: count report items and reject malformed marker evidence
- **PR #225**: Reject incomplete reproduction and non-finite CM probes in decision-band validation
- **PR #222**: ci: fail closed when sparse checkout omits ruff lint inputs
- **PR #221**: Preflight CM-band run submissions and report failed parts
- **PR #219**: pex: require distinct physical corners and valid delay evidence
- **PR #206**: harness: record runtime SPICE model-source identity in PVT evidence (#203)
- **PR #202**: Record compiled OSDI model identity in local PVT evidence (#196)
- **PR #198**: Noise analysis: retain shared-draw disclosures and bound grid-mean uncertainty
- **PR #195**: test: unit tests for CM-band campaign runner retry and append-only guards
- **PR #190**: harness: freeze local PVT source inputs before executing the grid (Closes #179)
- **PR #189**: PEX delta table: separate measurement availability from compliance (#181)
- **PR #183**: Reject ambiguous repeated ngspice output in the local PVT harness
- **PR #182**: Validate local testbench check bounds before simulation
- **Issue #236** (closed): Bind full-noise analysis to verified configuration and submission provenance
- **Issue #232** (closed): README evidence: pin kickback residue claims to their historical measurement population
- **Issue #223** (closed): Builder preflight: check tracked sim size before requesting review
- **Issue #220** (closed): Supplemental DRC: count report items and reject malformed marker evidence
- **Issue #216** (closed): CI: fail when sparse checkout omits intended Ruff input files
- **Issue #211** (closed): PEX renderer: require distinct physical corners and valid delay evidence
- **Issue #197** (closed): Preserve partial ngspice diagnostics when local PVT points time out
- **Issue #196** (closed): Record compiled OSDI model identity in local PVT evidence
- **Issue #193** (closed): README claims: verify offset and full-noise figures against their own evidence populations
- **Issue #188** (closed): Guard telemetry: package alternate-index wrapper reproduction for upstream handoff
- **Issue #187** (closed): Docs: sim/README.md sparse-cone table omits harness-unit-tests' new pdk_drc inputs
- **Issue #186** (closed): Unit tests for the CM-band campaign runner (retry, resubmit and append-only guards)
- **Issue #181** (closed): PEX reporting: distinguish raw measurement success from circuit compliance
- **Issue #180** (closed): Layout: verify physical rules outside the curated DRC deck
- **Issue #178** (closed): Validate local testbench check bounds before simulation
- **Issue #164** (closed): sim: decision time / metastability at dut_vcm -/+50 mV as klt sim corner campaigns (evidence for DR-0004 CM-range row)

### 2026-10-10

- **PR #223**: fix(currency): history-independent record-currency index (#213)
- **Issue #213** (closed): Record currency depends on clone-local commit availability
- **PR #220**: ci: run raw-trace gate fixture in grading-fixture dispatcher
- **Issue #212** (closed): Guard telemetry: preserve stash scope protection
- **Issue #217** (closed): ci: run the phase-noise raw-trace regression in the shared grading fixtures
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
