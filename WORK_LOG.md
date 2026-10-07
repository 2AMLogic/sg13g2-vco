# Work Log

Merged PRs and closed issues from the 30-day bootstrap window ending
2026-10-07. Entries record forge events; closure alone does not assert that
engineering acceptance criteria passed. Guide maintenance PRs are excluded.

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
