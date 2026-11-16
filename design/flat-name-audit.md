# Flat device/node-name dependency audit — `design/vco.spice`

**Issue**: #379 (operator ruling 2026-11-15, option a: audit first, then decide).
**Deliverable**: read-only enumeration of every dependency on the flat device or
node names of `design/vco.spice`, per consumer, to inform the deferred question
of collapsing `design/vco.sch` onto `design/vco_core.sym`. The collapse itself
is **out of scope** here and returns as its own decision with this audit
attached.

**All counts and `file:line` references in this document were taken at commit
`4f7a4edf9550b486ffff53345fe30edf2738ff04` (`4f7a4ed`, 2026-11-16).** No file
was modified to produce it; this document is new and unpinned (it appears in no
`signoff/evidence/inventory-*.json`).

## The names

`design/vco.spice` is a flat elaboration deck (no `.subckt`; the `**.subckt vco`
wrapper is commented out). Its names:

- **Devices (44 distinct instances)**: `XL1`, `XL2`, `XC1`,
  `XCVP1`–`XCVP16`, `XCVN1`–`XCVN16`, `XQ1`, `XQ2`, `XQ3`, `XQ4`,
  `RTE`, `RREF`, `RRE`, `VSUP`, `VCT`
  (arithmetic: XL 2 + XC1 1 + XCVP 16 + XCVN 16 + XQ 4 + `RTE`/`RREF`/`RRE` 3
  + `VSUP`/`VCT` 2 = 44).
- **Nodes (8 named + ground)**: `VDD`, `OUTP`, `OUTN`, `VCTRL`, `TAIL`,
  `NBIAS`, `TE`, `RE` (plus `0`).
- **The deck also resolves its own names** in `.ic v(OUTP)… v(OUTN)…`,
  `print v(NBIAS) v(TE) v(TAIL) v(OUTP) v(OUTN) i(VSUP)`, `alter VCT dc`,
  `save i(vsup)`, and the `v(OUTP)/v(OUTN)/v(TAIL)/i(VSUP)` expressions of its
  `.control` block.

Under the deferred collapse these device names and node references would
become hierarchical (prefixed by the core instance, e.g. `x1.OUTP`), which is
why the consumers below matter.

## Method (re-runnable)

1. Names extracted by reading `design/vco.spice` directly (list above).
2. Consumer search: `git grep -nE '<name>' -- <consumer-path>` per name, and
   word-boundary form
   `\b(XL1|XL2|XC1|XCVP[0-9]+|XCVN[0-9]+|XQ[1-4]|RTE|RREF|RRE|VSUP|VCT|VDD|OUTP|OUTN|VCTRL|TAIL|NBIAS|TE|RE)\b`
   for the deck-form scan (case-sensitive: netlist names are upper case).
3. Evidence scan (frozen artifacts): the deck-form scan **plus** the
   simulator-printed forms ngspice emits in lower case:
   `v(outp|outn|tail|nbias|te|re|vdd)`, `i(vsup)`, `vsup#branch`, and
   line-start operating-point rows (`^nbias`, `^outp`, …). Counts are unique
   files matching either form. Two exclusions apply, both checked: **no
   evidence file matches only via the short tokens `TE`/`RE`** (i.e. no false
   positives from them), and the line-start row form is applied to simulator
   logs and deck outputs only — **not to `*.csv`**, where the same short
   tokens occur as column values (`port=tail` cells in the phase-noise pilot
   CSVs: `*-pilot-isf.csv`, `*-portnoise.csv`, `*-realizations.csv`,
   `diagnostic-pilot-*.csv` are CSV column values, not operating-point rows).
   Without that CSV exclusion the literal scan over-counts the phase-noise
   families (files matching only via CSV column values); with it, every
   family reproduces the table below.
4. Classes used below:
   - **breaks under hierarchy** — the reference stops resolving and no local
     rename fixes it; the mechanism needs redesign, or the consumer fails
     loudly/silently at run time if the collapse lands unchanged.
   - **adaptable (how)** — a contained, mechanical edit or regeneration
     restores it; the edit is described.
   - **evidence-only** — frozen/append-only artifact; cannot be edited, stays
     as the record of the flat-naming era.

## Consumers with zero flat-name dependencies

- **`.github/scripts/record_currency.py`** — depends on `design/vco.spice` as
  a **whole-file sha256** (`SOURCE = "design/vco.spice"`,
  `record_currency.py:41`, hashed at `build_index()`/`classify_group()`), and
  on the file *path*, which the collapse does not change. No device or node
  name appears in it. (Command: `git grep -nE '<each name>' -- .github/scripts/record_currency.py`
  — no hits.)
- **`.github/scripts/check-signoff.sh`** — no flat-name hits; it touches
  `design/vco.spice` only through the signoff inventories' whole-file sha256
  pins and by delegating record currency to `record_currency.py`
  (`CLASSIFIER=…/record_currency.py` at `check-signoff.sh:60`; the delegation
  fail message at `:111`). Note for the *collapse* decision (not a
  flat-name dependency): any edit to `design/vco.spice` breaks the sha pins and
  requires `.github/scripts/regen-signoff.sh`.
- **`design/netlist.sh`** — generates `design/vco.spice` from `design/vco.sch`
  and runs the schematic-level drift guard (`netlist.sh:97-111`); no netlist
  device/node name appears in it.
- **`design/run_core_smoke.sh`** — already instantiates the core
  (`XDUT VCTRL OUTP OUTN VDD VSS vco_core`, `run_core_smoke.sh:57`); its
  `OUTP`/`OUTN`/`VCTRL` names are its own bench namespace over the core ports,
  not references into `design/vco.spice`. (Its flat-vs-core comparison becoming
  tautological after a collapse is a purpose question for the collapse decision,
  not a name dependency.)
- **Component-characterization benches** (standalone decks, local namespaces):
  `sim/inductor-model/testbench/*`, `sim/tank-characterization/testbench/*`,
  `sim/varactor-characterization/testbench/*`. The string `Vctrl` in the
  varactor benches (`tb_diode_varactor_vscan.spice.tmpl:77`,
  `tb_mos_varactor_vscan.spice.tmpl:98`) is a template token / local source
  named for the *quantity*, not the design node; `ctrl` is their local node.
  Zero hits for every design name in their `testbench/`, `records/`,
  `netlist-snapshots/` and `corners/` trees.
- **Synthetic known-answer benches** (no design body): `tb_period_count_known_answer.spice.tmpl`
  (local `PURE_LO`/`PURE_MID`/`PURE_HI`/`RAMP`/`DC_ONLY`), `tb_isf_known_answer.spice.tmpl`
  (local `TANK`), `tb_portnoise_known_answer.spice.tmpl` (local `PNODE`).

## Consumers that would break under hierarchy

Items 1–6 are the design-derived bench machinery. They embed the device section
of `design/vco.spice` verbatim (`@@VCO_BODY@@`, spliced by
`osc_derive_body()`, `osc_bench.sh:558-618`) and then resolve flat names
against that embedded namespace from the top level. Item 7, `layout/lvs.sh`,
is the LVS runner: it does not embed the body, but it carries its own
flat-name gate and its own copies of the flat port list and drop rules.

1. **`sim/oscillator-core/testbench/tb_vco_core_tran.spice.tmpl`** —
   9 design names (`OUTP`, `OUTN`, `TAIL`, `NBIAS`, `TE`, `RE`, `VDD`, `VSUP`,
   `VCT`):
   `:98-100` (B-sources `V = V(OUTP) - V(OUTN)`, `V(OUTP) + V(OUTN)`, `V(TAIL)`),
   `:105` (`.ic v(OUTP)=… v(OUTN)=…`),
   `:123` (`save … i(VSUP) v(NBIAS) v(TE) v(RE) v(TAIL) v(OUTP) v(OUTN) v(VDD)`),
   `:124` (`alter VCT dc`), `:131` (`print v(NBIAS)… i(VSUP) v(VDD)`),
   `:140` (`let isup_w = -i(VSUP)`), `:145` (`v(VDD)`).
   Failure mode if unadapted: `alter` errors loudly; saved/printed flat vectors
   come back empty → each point FAILs; the `.ic` silently stops reaching the
   tank nodes, so the symmetric equilibrium holds and the point fails later at
   settle/crossing extraction (detectable, but not at the .ic itself).
2. **`sim/oscillator-core/testbench/tb_vco_core_margin.spice.tmpl`** —
   same class, plus the ladder mechanism `alter @RREF[resistance] = $rr`
   (`:105`) against an instance that would be internal to the core subckt;
   `:84-85`, `:89`, `:96-97`, `:108`.
3. **`sim/phase-noise/testbench/tb_vco_isf_impulse.spice.tmpl`** —
   impulse sources wired onto internal nodes: `IISFD OUTN OUTP PWL(…)`,
   `IISFT 0 TAIL PWL(…)` (`:120-121`), B-source `V(OUTP) - V(OUTN)` (`:116`),
   `.ic v(OUTP)… v(OUTN)…` (`:123`), `alter VCT dc` (`:136`). Top-level
   instances cannot connect to subckt-internal nodes in SPICE; this needs the
   ports exposed or the injectors moved inside — not a rename.
4. **`sim/phase-noise/testbench/tb_vco_port_noise.spice.tmpl`** —
   `alter VCT dc` (`:66`), `print v(NBIAS) v(TE) v(TAIL) v(OUTP) v(OUTN) i(VSUP)`
   (`:69`), and the probe/output pair substituted by `pn_bench.sh` (below).
5. **`sim/oscillator-core/osc_bench.sh`** —
   - device-section asserts `^XL1 `, `^XC1 `, `^XQ1 `, `^XQ3 `, `^RREF `,
     `^RTE `, `^VSUP `, `^VCT ` (`:602`) and the `^XCV*` varactor-prefix check
     (`:607-611`) — fail loudly by design;
   - `osc_body_r_ohm` reads `RREF`/`RTE` values out of the derived body by
     instance name and positional field (`:614-615`, `:624-643` — field `$4`);
   - the supply-rail rewrite keys on the exact line shape
     `^VSUP[ \t]+VDD[ \t]+0[ \t]+dc[ \t]+…` and requires exactly one sub
     (`:686-707`, exit 3 otherwise);
   - `osc_op_value` extracts `v(tail)` and `i(vsup)` from the ngspice log by
     vector name (`:952-953`; miss returns empty — semi-silent).
6. **`sim/phase-noise/pn_bench.sh`** — injection-port wiring substituted into
   the deck: `IPROBE OUTN OUTP dc 0 ac 1` + output `v(OUTP,OUTN)` (tank port),
   `IPROBE 0 TAIL dc 0 ac 1` + output `v(TAIL)` (tail port) (`:233-234`).
7. **`layout/lvs.sh`** — the LVS runner, with two flat-name dependencies of its
   own, independent of the reference pipeline of adaptable item 1 (re-running
   `lvs_reference.py` never touches this script):
   - the xschem-version detector `grep -q '^XQ1 '
     "${SCRATCH}/ref/xschem/vco.spice"` (`:150`) gates the independent T3
     cross-check: a flat `XQ1` card present ⇒ this xschem ignored
     `lvs_netlist 1` ⇒ skip. Under the collapse the regenerated xschem-side
     deck has no `^XQ1 ` line, so the gate takes the other branch and accepts
     a simulation-form netlist as a valid LVS-form cross-check — a **silent
     wrong verdict**, not a loud failure;
   - the inline Python feeding the klt LVS leg carries its own copy of the T1
     drop rule (`s.split()[0] in ("VSUP", "VCT")`, `:279`) and its own
     hard-coded nine-port header `.SUBCKT vco 0 VDD OUTP OUTN VCTRL TAIL
     NBIAS TE RE` (`:281`) — mechanically adaptable in the same edit, but
     maintained independently of `lvs_reference.py`, so adaptable item 1's
     regeneration step does not cover them.

## Consumers that are adaptable (how)

1. **`layout/lvs/vco-reference.cir` + its generator `layout/scripts/lvs_reference.py`**
   (counted as one pipeline) — the `.cir` is *derived* ("DERIVED, do not edit",
   `vco-reference.cir:1`) from `design/vco.spice` by transformations T1–T6 and
   carries all nine flat node names in its `.SUBCKT vco 0 VDD OUTP OUTN VCTRL
   TAIL NBIAS TE RE` port list (`:6`) plus the T3-renamed devices
   (`LL1/LL2`, `CC1`, `CCVP1-16`, `CCVN1-16`, `QQ1-4`, `RTE`, `RREF`, `RRE`,
   `Rtap_ring`). Adaptation: update the generator's hard-coded flat port list
   (`PORTS`, `lvs_reference.py:73`), its T1 drop rules for `VSUP`/`VCT`
   (`:18-21`, `:121-123`) and its T3 device-line parsing, then re-run
   `lvs_reference.py` to regenerate the `.cir` + JSON sidecar and re-run LVS.
   The runner `layout/lvs.sh` carries further independent copies of the same
   rules — see break item 7; regenerating the `.cir` does not adapt them.
2. **`design/run_elaborate.sh`** — reads only `wrdata` *file names* the deck's
   own `.control` writes (`vco_tran_*`/`vco_cm_*`/`vco_tail_*`/`vco_isup_*`,
   `:169-207`) plus one log-format read `awk '/^v\(tail\)/'` (`:207`). The
   deck's `.control` block is inside `design/vco.spice`, so any collapse edits
   it in the same change; this script's two read patterns adapt in that same
   edit.
3. **`sim/bn-substrate-tank/make_requests.py`** — builds standalone tank decks
   that re-declare the design's devices by hand as a documented mirror:
   `XL1`/`XL2`/`XC1`/`VCT` and nodes `VDD`/`VCTRL`/`OUTP`/`OUTN`
   (`:97`, `:120-127`; mirror stated in `sim/bn-substrate-tank/README.md:14`).
   Nothing includes the design netlist, so execution never resolves against
   it; the mirror is a fidelity claim, and it already diverges deliberately
   (lumped `svar` varactors, no core). Adaptation: update the mirror strings if
   the design's naming convention changes — including the mirror asserts in
   `tests/stdlib/test_tank_ab.py:68-71` (`assertIn("XCVP1 VCTRL OUTP OUTP
   svar", …)` and the `\nXCV` count), which pin the same mirror strings —
   decks keep running meanwhile.
4. **`sim/tests/test-source-capture.sh`** (`:29-36`) and
   **`sim/tests/test-model-bundle.sh`** (`:83-90`) — synthetic fixture bodies
   built from the flat names specifically to exercise `osc_derive_body()`'s
   device asserts. Adaptation: rewrite the fixture device lines alongside the
   asserts they test.
5. **`sim/oscillator-core/tests/test_supply_stage2.sh`** — greps generated
   decks for flat-name shapes: `^VSUP ` count, the exact `VSUP VDD 0 dc <rail>`
   line, and `.ic v(OUTP)=… v(OUTN)=…` (`:193-200`, `:243`). Adaptation: update
   the three grep patterns to the new deck shape.
6. **Report prose in the runner/report scripts** —
   `run_pilot_grid.sh:263,273,287`, `run_pvt_sweep.sh:401,407,430,454-468`,
   `run_supply_stage2.sh:186,199-200`, `report_supply_stage2.sh:633`,
   `run_isf_pilot.sh:354`, and the `vsup_v` CSV column name
   (`osc_bench.sh:1397,1467`; `pn_bench.sh:389`) echo the flat names in
   human-readable method descriptions and a derived column label. No execution
   resolves against the netlist. Adaptation: prose/column-label edits, or leave
   as historical method text with the records that cite them.

### Other mentions (enumerated; not additional tally entries)

The sweep also found the flat names in files that are not load-bearing
consumers — none of them resolves a name against `design/vco.spice` at run
time. They are listed here so the audit's exhaustiveness claim is explicit
rather than sampled:

- **Report/method prose** (same disposition as adaptable item 6):
  `sim/oscillator-core/run_validity_check.sh:67` (synthetic-trace comment
  "the netlist's ideal VSUP"), `design/README.md:60-66` (core-sym port list
  and node table — the core ports the collapse keeps),
  `layout/PROVENANCE.md:41,129,173` (pin/routing history, `XL1` device
  table), `layout/README.md:40-42` ("all 9 nets of `design/vco.spice`").
- **Ratified record prose**: `spec/target-spec.md:119` (states the committed
  instantiation `VSUP VDD 0 dc 3.3`, `XQ1`–`XQ4`),
  `spec/decision-records/DR-004-target-spec-ratification-pass-2.md:53-55`,
  `spec/decision-records/DR-005-varactor-bn-substrate.md:18`. These are
  ratified spec/decision text, not executable consumers: they stay correct as
  history, or change through the spec process — never as a side effect of the
  collapse edit.
- **Layout-side net namespaces**: `layout/vco_manifest.json:37-43` (expected
  layout net list) and `layout/scripts/floorplan.py:123-125` (svaricap PCell
  `bn= OUTP/OUTN`). These mirror the same net names on the layout side; they
  move with the same collapse change as the layout itself, not against
  `design/vco.spice` at run time.

None of these is load-bearing the way the break-class entries are; they are
mentions, not dependencies, and are deliberately not counted in the tally
below.

## Evidence-only (append-only / frozen; cannot be edited)

The rename gate (`.github/scripts/check-sim-append-only.sh:61`) freezes
`sim/**/records/`, `sim/**/netlist-snapshots/` and `sim/**/corners/` (any
depth). The `klt-sim/` and `yield/` trees are not covered by that gate but are
frozen experiment evidence / campaign inputs cited by append-only records
(`sim/oscillator-core/yield/README.md`, record
`20261115-190000-0b056b1-yield-anchor1-run.md`), so they get the same
disposition. Files containing at least one flat name (deck-form and/or
simulator-printed form; method above), **at `4f7a4ed`**:

| evidence family | files with flat names | tracked files |
|---|---|---|
| `sim/oscillator-core/records/` | 13 | 31 |
| `sim/phase-noise/records/` | 4 | 14 |
| `sim/bn-substrate-tank/records/` | 37 | 201 |
| `sim/inductor-model/records/` | 0 | 93 |
| `sim/tank-characterization/records/` | 0 | 114 |
| `sim/varactor-characterization/records/` | 0 | 440 |
| `sim/oscillator-core/netlist-snapshots/` | 16 | 28 |
| `sim/phase-noise/netlist-snapshots/` | 8 | 13 |
| `sim/oscillator-core/corners/` | 14 | 26 |
| `sim/phase-noise/corners/` | 8 | 13 |
| `sim/oscillator-core/klt-sim/` | 107 | 320 |
| `sim/phase-noise/klt-sim/` | 10 | 98 |
| `sim/oscillator-core/yield/` | 59 | 169 |
| **total (nonzero families)** | **276** | — |

The `records/` copies include frozen deck copies (the embedded device section,
e.g. `sim/bn-substrate-tank/records/20261009-002323-383f22e/decks/*.spice:206-243`),
ngspice logs carrying the lower-cased operating-point vectors
(`v(nbias)`, `vsup#branch`, `i(vsup)`), and `netlist-snapshots/*/design-vco.spice`
whole-source snapshots. These stay correct as history; under a collapsed
design they simply document the flat era, which is what append-only evidence
is for.

## Tally

At commit `4f7a4edf9550b486ffff53345fe30edf2738ff04` (2026-11-16): **13
consumers carry flat-name dependencies — 7 break under hierarchy** (the four
design-derived testbench templates `tb_vco_core_tran`, `tb_vco_core_margin`,
`tb_vco_isf_impulse`, `tb_vco_port_noise`, plus the two bench generators
`sim/oscillator-core/osc_bench.sh` and `sim/phase-noise/pn_bench.sh` — every
one of them resolves flat names top-level against the embedded `@@VCO_BODY@@`
namespace, with top-level `.ic`/`alter`/injection-wiring being the
not-rename-fixable cases — and the LVS runner `layout/lvs.sh`, break item 7,
whose xschem-version gate would silently accept a simulation-form netlist as
an LVS-form cross-check), **6 are adaptable** (the LVS reference pipeline via
regeneration — its runner-script copies are break item 7's separate fix,
`design/run_elaborate.sh` in the same edit that rewrites the deck's
`.control`, the `bn-substrate-tank` deck mirror with its `test_tank_ab.py`
asserts, the two test-fixture files and the stage-2 deck-pattern test, and
report prose), and **276 frozen evidence files across five families are
evidence-only** (records 54, netlist-snapshots 24, corners 22, klt-sim 117,
yield 59), while **10 consumers in six groups have zero flat-name
dependencies** (four individual consumers — `record_currency.py`,
`check-signoff.sh`, `design/netlist.sh`, `design/run_core_smoke.sh` — plus
the three component-characterization bench families, `inductor-model`,
`tank-characterization` and `varactor-characterization`, and the three
synthetic known-answer benches, `tb_period_count_known_answer`,
`tb_isf_known_answer` and `tb_portnoise_known_answer`: 4 + 3 + 3 = 10,
grouped into the six bullets of the zero-dependency section).

No recommendation is made here; whether to collapse `design/vco.sch` onto
`design/vco_core.sym` remains its own decision (operator ruling, 2026-11-15),
to be taken with this audit attached.
