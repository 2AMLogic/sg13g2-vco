# LC-VCO target specification

- **Status: RATIFIED — 12 target rows, none open (DR-003 pass 1, nine
  rows; DR-004 pass 2, rows 0/3/7).** The tank study this table's
  2026-09-06 draft waited on ("Tank first" per `CLAUDE.md`) has landed in
  `sim/`, and two decision records have disposed every row.
  `spec/decision-records/DR-003-target-spec-ratification.md` (issue #35,
  pass 1) ratified **rows 1, 2, 4, 5, 6, 8, 9, 10, 11 as targets** —
  binding numbers derived from recorded device data and stated
  engineering arithmetic, **explicitly not met by any measurement** (no
  graded corner grid exists yet) — and left **rows 0, 3, 7 OPEN with
  named gates** rather than silently DRAFT.
  `spec/decision-records/DR-004-target-spec-ratification-pass-2.md`
  (issue #57, pass 2) disposes those three, each gate having landed:
  **row 0** from DR-002's device class and 3.3 V rail plus
  `design/vco.spice`'s own instantiation, **row 3** from the committed
  tank sizing (a stated `Vctrl` window plus a grid-convergent linearity
  measure), **row 7** from the explicit "no output buffer in v1"
  decision and the current-limited swing arithmetic that follows from it.
  Rows 0/3/7 are likewise ratified **as targets, not met**. DR-004 also
  states how row 10's ±10 % supply sub-corners — now active, since row 0
  has landed — cross the graded 135-point corner grid, **without
  changing row 10's ratified corner set**. Ratification flows per the
  2026-08-19 ratification-via-PR ruling (2AMLogic/2am#357, cited by
  issue #35): the record PR's Judge review plus Champion/operator merge
  is the two-key mechanism, because this repo has no `ratification/`
  tree (2AMLogic/product#135). Per `CLAUDE.md`, agents do not relax a
  ratified row to make results pass — changing one requires a
  superseding decision record, in public.
- **Date**: 2026-09-06 (drafted, issue #2); 2026-09-21 partially ratified
  (DR-003, issue #35); 2026-09-26 fully ratified (DR-004, issue #57)
- **Written by**: Builder agent, issue #2
- **Block class**: single free-running LC voltage-controlled oscillator
  (not embedded in a PLL in this repo's own scope — see
  `spec/porting-plan.md` for how sg13g2-pll's PLL-embedded VCO subblock
  differs).
- **Port relationship**: **not a port.** No sibling repo in this catalog
  has an LC-tank VCO; the ring/CMOS VCOs inside `sg13g2-pll`, `sky130-pll`,
  and `gf180-pll` are architecturally different oscillators (see
  `spec/porting-plan.md` §1 for the disposition on why the ring topology
  itself does not carry over). Rows below are seeded from the LC-VCO
  literature (Hajimiri & Lee's ISF phase-noise framework — the canonical
  citation this repo's own `CLAUDE.md` names) and the general shape of
  what an LC-VCO spec table states, not from a measured sibling value.

---

## How to read this file

Every row states: the **parameter**, its **min/typ/max** (target bounds,
or a pointer into the condition cell where the bound is a defined measure
rather than a single scalar), the **stated measurement condition**
required to grade it (offset frequency for phase noise, load for output
swing, the `Vctrl` window for Kvco, etc. — a number without its condition
is not gradeable later without re-deriving the condition too), and a
**status** column: `RATIFIED (target) per DR-003` for the nine rows pass 1
ratified, and `RATIFIED (target) per DR-004` for rows 0, 3 and 7, which
pass 1 gated explicitly and pass 2 disposed. No row is open. DR-003 and
DR-004 are the row-by-row records of every disposition; a row's own
record is the one named in its status cell.

**The cardinal rule for this file** (same rule sky130-pll's and
gf180-pll's own target-spec files state): no number is presented as
final, and no row is filled in by inventing a plausible value — every
cell is closed by a `sim/` evidence record and a decision record, or it
stays blank.

### Why every cell is blank in this pass

This repo's `CLAUDE.md` is explicit: *"Tank first. Characterize the PDK's
shipped spiral-inductor and MIM-cap models (L, Q, SRF across the band)
before sizing the pair; commit that study to `sim/` — every later
tuning-range and phase-noise claim leans on it."* No such study exists
yet (`sim/` contains only its scaffold `README.md` as of this issue). A
target-spec row that pre-committed a tuning range or a phase-noise number
ahead of that data would be exactly the "numbers without methods are not
results" failure this repo's own CLAUDE.md forbids — so this issue's
contribution is the table's **shape**, deliberately not its numbers.

**Updated 2026-09-21 (DR-003, issue #35).** The study this section waited
on has landed: `sim/tank-characterization/` (#5), `sim/inductor-model/`
including the openEMS EM extraction of the PDK's own inductor PCell
(#6/#8/#9/#11/#23), and `sim/varactor-characterization/` (#18/#19)
consumed by DR-001. The precondition for filling cells is therefore met,
and pass 1 of ratification (DR-003) filled the nine cells its recorded
device data and stated arithmetic support — as **targets**, per issue
#35, not as met values — leaving rows 0/3/7 explicitly open. The
paragraph above is kept verbatim for history: it was true as of the
2026-09-06 draft, and it is the reason no cell here was filled before its
supporting evidence existed. The rule itself stands unchanged and now
governs the open rows: no open cell is filled by inventing a plausible
value.

**Updated 2026-09-26 (DR-004, issue #57).** The last three gates have
landed too — DR-002's device class and rail (#33), the committed tank
sizing in `design/vco.sch` / `design/vco.spice` (#44), and the explicit
buffer decision — so rows 0, 3 and 7 are now ratified as targets and no
row is open. The rule above still governs: every cell DR-004 filled is
closed by a landed decision record, the committed netlist's own sizing,
or arithmetic written out in DR-004 itself, and the pilot measurements
in `sim/oscillator-core/` and `sim/phase-noise/` grade no row — they are
cited there as orientation and cross-check only, which each of those
records states about itself.

---

## Summary table

All twelve rows are ratified as **targets** — binding numbers, **not met
by any measurement**: no graded corner grid has been run (#50, #53). Nine
rows are **RATIFIED (target) per DR-003** (pass 1); rows 0, 3 and 7 are
**RATIFIED (target) per DR-004** (pass 2), which disposed the three gates
pass 1 left open. Every disposition, its evidence, and its arithmetic is
recorded in `spec/decision-records/DR-003-target-spec-ratification.md`
and `spec/decision-records/DR-004-target-spec-ratification-pass-2.md`.

| # | Parameter | Min | Typ | Max | Corner / condition (to be stated when graded) | Status |
|---|---|---|---|---|---|---|
| 0 | Supply voltage / device flavor | 2.97 V | 3.30 V | 3.63 V | Single supply rail for the oscillator core, graded over ±10 % of nominal (the excursion row 10's own condition cell names; 3.30 × 0.9 / 1.1). **Device flavor**: SiGe HBT `npn13G2v` cross-coupled pair, tail-current biased, per `spec/decision-records/DR-002-negative-gm-pair-device-class.md`; tuning device `sg13_hv_svaricap` over the full 0.0–3.3 V HV domain with no band-switching bank in v1, per `DR-001-tuning-mechanism.md`; **HV** MOS corner family (`cornerMOShv.lib`), which is what the committed netlist loads. `Vctrl` remains a control node, **not** a supply — the two domains are separate decisions and neither constrains the other (DR-002 §"Supply flavor"). Committed instantiation, not an intention: `design/vco.spice` carries `VSUP VDD 0 dc 3.3` with `XQ1`/`XQ2`/`XQ3`/`XQ4` = `npn13G2v`. Not decided by this row: the tail-current value and the bias network's sizing (schematic-time work, graded by rows 6/7/8) | **RATIFIED (target) per DR-004** — binding, not met |
| 1 | Center / target band | 4.5 GHz | 5.0 GHz | 5.5 GHz | Ratified from the EM extraction (record `20260910-052657-3896421`): measured SRF 9.42 GHz (`p11`) / 8.07 GHz (`p13`) excludes a ~10 GHz tank outright (a carrier there runs past the inductor's own SRF), and the multi-turn EM Q plateaus across 2–5 GHz instead (`p11`: 9.49 @ 2 GHz, 10.28 @ 5 GHz, ±10 % convergence bar). Window keeps ≥ 1.7× SRF margin at its top end over the geometry, ≥ 2.09× over `p13`'s SRF across the whole window. MIM ±10 % process spread on C (≈ ∓5 % on f₀) grades inside the window at the corners row 10 settles | **RATIFIED (target) per DR-003** — binding, not met |
| 2 | Tuning range (Kvco integral) | ≥ 15 % | | (≥ 20 % stretch) | Fractional tuning, f_max/f_min ≥ 1.15 (stretch ≥ 1.20), across the full 0.0–3.3 V domain (DR-001: `sg13_hv_svaricap`, measured `Cmax/Cmin` 1.88–2.08x, no band-switching bank in v1), band-center referenced. Achievability arithmetic (DR-003 §Decision 2): with fixed C `F` and varactor `V` at Vctrl=0, ≥ 15 % needs F ≤ 0.92·V — the fixed-C budget (MIM + parasitics) must stay under ~half of C_tot for the stretch, a named risk no `sim/` evidence measures yet | **RATIFIED (target) per DR-003** — binding, not met |
| 3 | Kvco (small-signal slope) and its linearity across the tuning range | \|Kvco\|_mean ≥ 381 MHz/V over `W` | | chord nonlinearity ≤ 30 % of span (≤ 20 % stretch) | **Graded over the ratified `Vctrl` window `W` = [1.65, 3.30] V**, not over the full 0.0–3.3 V domain: below ≈ 1.5 V the `sg13_hv_svaricap` C(V) has saturated (1.1 % of C over 1.5 V of control, per record `20260909-231619-de50891`) and Kvco is not defined to useful precision there. Four requirements, all at every bound corner of the row-10 set (DR-004 §Row 3 carries each one's arithmetic): **(1)** Kvco single-signed at every sampled segment in `W`; **(2)** window coverage — `f(1.65) − f(3.3)` ≥ 90 % of the **same corner's own** full-domain span `f(0.0) − f(3.3)` (this does **not** re-specify row 2, which stays stated over the full domain); **(3)** \|Kvco\|_mean ≡ (`f(1.65) − f(3.3)`)/1.65 V ≥ 381 MHz/V — a **derived** floor (row 2's ≥ 15 % geometrically centred in row 1's window × 90 % coverage ÷ 1.65 V), stated so the row grades as a number, not as a pointer; **(4)** linearity as **chord (integral) nonlinearity**, `100 × max_{V∈W} \|f(V) − chord(V)\| / \|f(3.3) − f(1.65)\|` with the chord joining the window endpoints, graded on ≥ 5 `Vctrl` points in `W` including both endpoints — which the committed 10-point bench axis already supplies (1.65/1.8/2.4/3.0/3.3 V). The chord measure is used **because** it converges under grid refinement (22.3 % at 5 points, 22.9 % at 12) whereas the bench's `kvco_linearity_pct` column (peak-to-peak segment spread over mean) does not (116.8 %→137.5 % over `W` for the same curve) and is `nan` on two of the pilot's own three temperature rows: that column stays a reported descriptor and **grades nothing** — in particular its full-domain 332.8 % pilot value is not a row-3 result. No \|Kvco\| **ceiling** is ratified: this block is not PLL-embedded in this repo's scope, so no control-line noise budget exists to derive one from | **RATIFIED (target) per DR-004** — binding, not met |
| 4 | Phase noise at a stated offset (e.g. `L(Δf)` at 1 MHz and 10 MHz offsets from carrier) | | | ≤ −105 dBc/Hz @ 1 MHz (target); ≤ −115 (stretch) | Primary offset 1 MHz from a band-center carrier; at 10 MHz offset the companion bounds are ≤ −125 target / ≤ −135 stretch (1/f² region). **Must state its measurement method** per this repo's own CLAUDE.md — transient length, window, and spectral estimator, or an ISF/impulse-sensitivity derivation, plus the method's known variance and limits; ngspice has no PSS/pnoise and the estimator choice is an explicit open item of the phase-noise testbench issue. Basis (DR-003 §Decision 4): Leeson first-pass over this tank's measured band and Q — ≈ −113 dBc/Hz @ 1 MHz at Q = 7, P ≈ 0.2 mW, F ≈ 2 — leaving ≈ 8 dB margin under the target; the stretch sits 2 dB beyond the estimate and is flagged revisit-likely | **RATIFIED (target) per DR-003** — binding, not met; method choice open |
| 5 | Tank quality factor (Q) at the target band | ≥ 6 | | (≥ 8 stretch) | Loaded tank Q at 5.0 GHz band center — including every element that loads the tank in the as-designed schematic (varactor, MIM, parasitics, bias network), over the corners row 10 settles. Basis (DR-003 §Decision 5): EM-measured inductor Q 10.28 @ 5 GHz (`p11`, ±10 % bar — a measured extraction, not the analytic upper bound) combined per 1/Q ≈ Σ share/Q with the parallel-small-cell varactor bank (Q 44.8 @ 5 GHz at V=0, preserved under parallelism per the `mos_xlarge` evidence) and MIM (Q ≳ 140 at band center) — ≈ 8.8 illustrative. **Named constraint**: tuning capacitance realized as parallel small-geometry cells; a `mos_mid`-class bank (Q 2.73 @ 5 GHz) loads the tank to ≈ 4 and misses this row — the row-2/range vs row-5/Q tension DR-003 records | **RATIFIED (target) per DR-003** — binding, not met |
| 6 | Startup / negative-gm margin (`g_m` provided vs. tank loss required to start and sustain oscillation) | ≥ 3.0 | | | Startup safety factor: the pair's total g_m ≥ 3.0 × the tank's loss conductance, **at every bound corner of the row-10 set** — tank loss and active-device g_m both move with corner, which is why the margin, not a nominal-current number, is the ratified quantity. At the illustrative sizing G_loss ≈ 1.0 mS (ωC/Q at 225 fF, Q 7), i.e. the pair owes ≈ 3 mS worst-corner; every device class in #33's decision space clears that well inside row 8's budget. Which device supplies the g_m is #33's decision, not this row's | **RATIFIED (target) per DR-003** — binding, not met |
| 7 | Output swing (differential, into a stated load) | 0.40 V Vpp (0.65 V stretch) | | (no maximum ratified — see condition) | **Buffer decision, ratified: there is no output buffer in v1** (what `design/vco.spice` already implements and `design/README.md` states). **Stated load**: graded on `v(OUTP) − v(OUTN)` at the tank nodes — the bench's existing `vpp_diff_v` — with **no load beyond the netlist's own** tank: `L_diff` = 11.4478 nH, `C_tot` = 88.51 fF, `R_p,diff` = 1/`G_tank` = 3.418 kΩ at 5.0 GHz band centre (2.936 kΩ / 3.937 kΩ at the band edges). v1 therefore makes **no claim of driving a 50 Ω instrument**. Any probe/pad/buffer capacitance a grading bench adds must be declared, and is not free: an added 3 % of `C_tot` (≈ 2.1 fF) shifts f₀ by 1.5 %, which is exactly the margin the committed high endpoint (5.41854 GHz) holds under row 1's 5.5 GHz ceiling — so adding a buffer re-grades rows 1 and 2 and supersedes this row. **Regime is current-limited, by arithmetic**: `Vpp_diff = (4/π)·I_tail·R_p,diff` with `I_tail` = 204.1 µA gives 0.763 / 1.023 V at the two band edges against the pilot's measured 0.808 / 1.098 V (+6 % / +7 %), while the supply-clipped boundary sits at `Vpp_diff` ≈ 3.1 V at 27 °C (`VDD − V(TAIL)` ≈ 0.78 V of headroom per node, from the pilot's `v_tail_dc_op_v`), ≈ 3× above. The ≥ 0.40 V target is that same arithmetic at **row 5's ratified Q floor (6, vs nominal 9.5)** at the window's worst point → 0.492 V, with the residual 19 % a **stated allowance** for the tail mirror's process spread, which no record here measures. **Compliance condition, from DR-002's named burden**: `(VDD + Vpp_diff/4) − V(TAIL)_min ≤ BVCEO(min) = 2.2 V` at every bound corner — worst 1.155 V (53 % of the limit) across the pilot's three temperatures at its largest measured swing, using each point's `v_tail_dc_op_v` as a stand-in because no record carries the cycle minimum of `V(TAIL)`. The over-corner check, including the +10 % supply sub-corners and the per-corner cycle minimum, is owed to the graded pass — DR-004 does not perform it | **RATIFIED (target) per DR-004** — binding, not met; VCE compliance check owed to the graded pass |
| 8 | Supply current / power | | | ≤ 10 mW core (target); ≤ 5 mW (stretch) | Core (oscillator pair + tank bias, no output buffer) DC power at nominal rail, band center, nominal temperature. Do not scale by V² from any other repo's ring-VCO number — different topology, different device class entirely (see `spec/porting-plan.md` §1). Basis (DR-003 §Decision 8): row-6 start/hold current (≤ ~1 mA per side across all candidate device classes) plus swing-sustaining current — ≈ 3 mA available at 10 mW even on a 3.3 V rail, current-limiting well past 1 Vpp into R_p ≈ 1 kΩ — so the ceiling is demonstrated-plausible for both candidate topologies without depending on #33's outcome; rail itself pending row 0 | **RATIFIED (target) per DR-003** — binding, not met |
| 9 | Supply sensitivity (pushing, MHz/V) | | | ≤ 50 MHz/V (target); ≤ 20 MHz/V (stretch) | Band-center small-signal pushing, ≈ 1 % f₀ per volt — a conventional VCO pushing requirement level, scaled to the row-1 band by DR-003 (precedent-derived, not device-derived: the record says so explicitly). Coupling path per DR-001: supply disturbance entering chiefly through `sg13_hv_svaricap`'s well/substrate `Vctrl` node plus supply-dependent pair parasitics; the coupling path must be **stated with any measured number**, and the first measurement between the bounds triggers a supersede-or-uphold decision, not a quiet edit | **RATIFIED (target) per DR-003** — binding, not met |
| 10 | PVT corner set | (enumerated in condition) | | | The PDK's own non-statistical corner model set as already used across this repo's three `sim/` studies: MOS tt/ss/ff/sf/fs (5), junction-diode ×3, MIM `cap_typ`/`cap_bcs`/`cap_wcs` — the HBT family's own corner set joins iff #33 lands a topology using it — crossed with temperatures {−40, +27, +125} °C, and supply voltage at ±10 % of the row-0 rail once row 0 lands (sub-corners ride #33). The corner triplet exactly spans the row-11 range, so spec and environment envelope agree by construction; no PLL-sibling count is inherited (see `spec/porting-plan.md` §1) | **RATIFIED (target — set) per DR-003** — binding; supply sub-corners ride row 0 |
| 11 | Operating temperature range | −40 °C | | +125 °C | Ambient operating range; the triplet row 10 ratifies is exactly this envelope — the same temperatures over which the PDK's corner libraries are already characterized across the three `sim/` studies, so "meets bounds at the edges" is instantiated by a committed testbench per `spec/review-bar.md`, not by an invented colder/hotter bound the corner models can't grade | **RATIFIED (target) per DR-003** — binding, not met |

---

## Sources

- This repo's own `CLAUDE.md` — "Tank first," phase-noise measurement-method
  requirement, tuning-plan honesty requirement.
- Hajimiri, A. and Lee, T. H., "A General Theory of Phase Noise in
  Electrical Oscillators," *IEEE Journal of Solid-State Circuits*, 1998 —
  the ISF (impulse sensitivity function) framework named in this repo's
  `CLAUDE.md` as the canonical phase-noise frame; cited here as the
  intended derivation method for row 4, not yet applied.
- `2AMLogic/sg13g2-pll` `spec/porting-plan.md` §2.1 ("The VCO — the block
  BiCMOS changes most") — the sibling repo's own architecture-survey
  reasoning for why an LC-tank VCO's phase-noise advantage is exactly the
  number the ngspice-based flow cannot yet substantiate; see
  `spec/porting-plan.md` in this repo for the full citation and how this
  repo's own scope differs (a standalone LC-VCO, not a PLL subblock
  optimizing for a 20:1 tuning range).
- `2AMLogic/sky130-pll` `spec/target-spec.md` — table-shape and
  "blank until ratified" convention this file follows.
- `2AMLogic/gf180-bandgap` `sim/README.md` (via `2AMLogic/sg13g2-bandgap`,
  which cites it directly) — append-only evidence-record convention that
  will back every row here once filled.
