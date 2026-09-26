# DR-004: Target-spec ratification pass 2 — rows 0, 3 and 7 disposed, and how row 10's supply sub-corners cross the graded grid

- **Status**: **proposed** — a recommendation for two-key ratification via
  this PR (Judge review + Champion/operator merge), the same path DR-003 took,
  per the 2026-08-19 ratification-via-PR ruling (2AMLogic/2am#357) that
  `spec/target-spec.md`'s Status section cites while the fleet-standard
  `ratification/` tree remains uninstalled here (2AMLogic/product#135).
  Nothing here is binding until this PR merges. Upon merge, the three
  dispositions in "Decision" below take effect exactly as stated: rows 0, 3
  and 7 move **OPEN → RATIFIED as targets** — binding numbers, derived from
  landed decision records, the committed schematic's own sizing, and
  arithmetic written out in this record, and **not one of them met by any
  measurement**. With them, all twelve rows of `spec/target-spec.md` are
  ratified and none is open.
- **Known wart, handled in text exactly as DR-003 handled it**
  (2AMLogic/product#135): nothing updates a record's own `Status:` line when
  its ratification PR merges. This record therefore states its operative
  post-merge status here, in prose, unambiguously: **once the PR carrying
  this record is merged, the three dispositions marked RATIFIED below are
  binding on design work.** A reader must not take a stale
  `Status: proposed` field as evidence the record never took effect — the
  same reading DR-003 §Status and DR-002's ratification note establish for
  their own fields.
- **Date**: 2026-09-26
- **Decided by**: Builder agent, issue #57
- **Supersedes**: none. This record does **not** supersede DR-003 and does
  not touch, relax, re-open or re-word any of the nine rows DR-003 ratified.
  It disposes exactly the three rows DR-003 left explicitly OPEN, and states
  one consequence of row 0's landing that row 10's own ratified condition
  cell already provides for (the ±10 % supply sub-corners) without changing
  row 10's ratified corner set.
- **Superseded by**: (none while this record stands)
- **Related**: #57 (this issue), #3 (gap-to-T1 tracker; this is step (4) of
  the operator's 2026-09-15T00:00:29Z sequence on that tracker), #35 /
  DR-003 (pass 1 — the record that created the three gates this one closes),
  #33 / DR-002 (negative-gm pair device class + rail — row 0's gate),
  #31 / DR-001 (tuning device and `Vctrl` domain), #44 (`design/vco.sch` +
  derived netlist — row 3's tank-sizing gate and row 7's committed
  no-buffer assumption), #47 (`sim/oscillator-core` bench and its pilot),
  #49 (`sim/phase-noise` ISF bench and its pilot), **#50** and **#53** (the
  two graded row-10/11 grids whose declared corner sets the row-10
  sub-corner disposition below speaks to), 2AMLogic/2am#357,
  2AMLogic/product#135
- **Consumes** (every number in this record traces to one of these, or to
  arithmetic written out in the record itself):
  - `spec/decision-records/DR-002-negative-gm-pair-device-class.md` — the
    SiGe HBT `npn13G2v` cross-coupled pair **biased from the 3.3 V supply
    rail**, tail-current biased; `npn13G2v`'s PDK-table BVCEO of **2.5 V
    (2.2 V min)**. Row 0's device flavor and rail are this record's, quoted.
  - `spec/decision-records/DR-001-tuning-mechanism.md` — `sg13_hv_svaricap`
    over the full 0.0–3.3 V HV `Vctrl` domain, no band-switching bank in v1.
  - `design/vco.spice` (derived from `design/vco.sch`, #44) — the committed
    instantiation: `VSUP VDD 0 dc 3.3`; `XQ1`/`XQ2` (pair), `XQ3` (tail) and
    `XQ4` (mirror diode) all `npn13G2v`; `RTE` 2 kΩ, `RREF` 20.5 kΩ,
    `RRE` 4 kΩ; two `inductor` PCells (w = 8.22 µm, s = 3.74 µm,
    d = 141.975 µm, nr_r = 4); one `cap_cmim` 3.65 × 3.65 µm; 32
    `sg13_hv_svaricap` cells (16 per side, w = 3.74 µm, l = 0.3 µm);
    `.lib …/cornerMOShv.lib mos_tt` — the **HV** MOS corner library, not the
    core one; and **no output buffer stage of any kind**.
  - `design/README.md` — the schematic's own committed arithmetic, read here
    rather than re-derived: `L_diff` = 10.8636 / 11.4478 / 12.2419 nH at
    4.62260 / 5.0 / 5.41854 GHz; `G_tank` = 0.3406 / 0.2926 / 0.2540 mS at
    the same three frequencies (`Q_loaded` 9.31 / 9.50 / 9.45);
    `I_tail` = 204.1 µA from the operating point (`V(TE)` = 0.40811 V across
    `RTE` = 2 kΩ); `F` = 25.5–25.9 fF fixed tank capacitance measured out of
    the elaboration run; and lines 99–100, *"`VSUP` is an ideal 3.3 V source;
    there is no output buffer (row 7 is OPEN, and adding a buffer would bind
    it)."*
  - `sim/oscillator-core/records/20260926-010627-e391693*` (#47) — the
    **pilot** subset: `f_osc(Vctrl)`, `vpp_diff_v`, `isup_ls_avg_a`,
    `v_tail_dc_op_v` (2.4553 / 2.5157 / 2.6122 V at −40 / 27 / 125 °C),
    `kvco_hz_per_v` per segment, `kvco_linearity_pct` = 332.821 at 27 °C.
    **This record is a declared subset of one process corner and grades no
    `spec/target-spec.md` row — its own `.md` says so in those words.** It
    is used here only as orientation for choosing targets, exactly as DR-003
    used device data for the nine rows it ratified while declaring them "not
    met by any measurement".
  - `sim/varactor-characterization/records/20260909-231619-de50891.csv` —
    per-cell `c_5ghz_f` and `q_5ghz` for `device_key=small` over
    `vctrl_v ∈ {0, 0.3, 0.6, 0.9, 1.2, 1.8, 2.4, 3.0, 3.3}` V at five MOS
    corners × three temperatures. Row 3's closed-form curve below is built
    from this column, mapped through `design/README.md`'s own axis relation
    `vctrl_v = 3.3 − V(VCTRL)`.
  - `sim/inductor-model/em-extraction/records/20260910-052657-3896421-em-vs-analytic.csv`
    — `p11`'s `l_fitted_h` across frequency (the EM-fitted subckt the
    netlist actually instantiates), used for the `L_diff(f)` the row-3
    closed form solves self-consistently.
  - `sim/phase-noise/records/20260926-071903-7a02483.md` (#49) — the ISF
    pilot at `mos_tt`/`cap_typ`/`hbt_typ`, 27 °C, `Vctrl` = 1.65 V:
    carrier `f_osc` = 5.384250 GHz, `Vpp(VDIFF)` = 1.086791 V,
    `L(1 MHz)` = **−102.2763 ± 0.2953 dBc/Hz**. One corner; grades no row.
    Cited in "Consequences" only, and it changes nothing about row 4.
- **Numbering note (per `TEMPLATE.md`'s collision rule)**: this record takes
  DR-004. `spec/decision-records/` was re-read immediately before this PR
  (DR-001, DR-002, DR-003 and `TEMPLATE.md` were the only files present) and
  is re-read after the pre-push rebase; no other open PR in this repo adds a
  decision record.

## Context

DR-003 (pass 1, issue #35) ratified nine of `spec/target-spec.md`'s twelve
rows as targets and left **rows 0, 3 and 7 explicitly OPEN with named
gates** rather than silently DRAFT. Each gate has now landed on `main`:

| Row | DR-003's gate | What landed |
|---|---|---|
| 0 — Supply voltage / device flavor | "pending the #33 negative-gm pair architecture record (device class + rail); its landing record sets this row" | **DR-002** (#33, closed 2026-09-21): SiGe HBT `npn13G2v` cross-coupled pair, tail-current biased, **from the 3.3 V rail**. `design/vco.spice` instantiates exactly that. |
| 3 — Kvco slope **and its linearity** | "pending tank sizing in the schematic pass; kernel data already recorded" | **`design/vco.sch` + `design/vco.spice`** (#44, closed 2026-09-25): the concrete fixed-C/varactor split — 32 `mos_small`-geometry `sg13_hv_svaricap` cells against a **measured** fixed capacitance `F` = 25.5–25.9 fF — plus `design/README.md`'s self-consistent `L_diff(f)` solution that reproduces both measured band endpoints to better than 0.2 %. |
| 7 — Output swing | "pending #33 (pair topology + rail) and the buffer decision" | #33's half as above. **The buffer half is decided here**, and it is the decision the committed schematic already assumes (`design/README.md:99-100`). |

DR-003's Status prose settles the one question a reader might otherwise raise
about DR-002: both records are merged on `main`, and merge is what binds them
under the ratification-via-PR ruling — a stale `Status: proposed` field is the
known fleet-wide wart (2AMLogic/product#135), not evidence that a record never
took effect.

**What this record is for.** DR-003's own model applies unchanged: no
oscillator measurement grades any row yet, because no graded corner grid
exists (#50 and #53 are both blocked on the `klt sim` compute gap, filed
upstream as 2AMLogic/klayout-tools#2511). So every row disposed here is
ratified **as a target, explicitly not met**, set now — deliberately before
the grading evidence exists to be tempted by. Per `CLAUDE.md`, relaxing one
later to make a result pass requires superseding this record, in public.

### What the pilot evidence is, and what it is not

Two pilot records now measure this netlist: `sim/oscillator-core`'s
`20260926-010627-e391693` (13 transients at the nominal process corner over
three temperatures) and `sim/phase-noise`'s `20260926-071903-7a02483` (one
corner, one `Vctrl`). **Neither grades any row, and this record does not use
them as if they did.** Both say so themselves; the oscillator-core record's
header is explicit: *"This record grades NO `spec/target-spec.md` row."*

Where a pilot number appears below it is doing exactly one of two jobs, and
the text says which:

1. **Orientation** — telling this record what *shape* the design actually
   has, so a target is chosen against the real curve instead of an imagined
   one. The row-3 disposition exists in its stated form because of a pilot
   number (`kvco_linearity_pct` = **332.821 %** at 27 °C, with per-segment
   `Kvco` running from **+0.975 MHz/V** over 0.0–0.6 V to **−640.41 MHz/V**
   over 2.4–3.3 V): a single Hz/V figure over 0.0–3.3 V would have been
   gradeable-looking and meaningless against that shape.
2. **A cross-check on this record's own arithmetic** — where a closed form
   derived from committed device records is compared against what the pilot
   measured at the one corner it covers, so the reader can see the arithmetic
   is the right model before a bound is built on it.

Neither job is grading. No verdict column, `row1_verdict`/`row2_verdict`
included, is cited as evidence that a row is met.

## Decision

Row by row, against the 12-row table in `spec/target-spec.md`. Rows 1, 2, 4,
5, 6, 8, 9, 10 and 11 are **untouched** — their bounds, conditions and status
cells are exactly as DR-003 ratified them.

### Row 0 — Supply voltage / device flavor: RATIFIED (target) — 2.97 / 3.30 / 3.63 V, SiGe HBT `npn13G2v` pair on the HV domain

**Target.** The oscillator core runs from a **single nominal 3.30 V supply
rail**, graded over **2.97 V (min) to 3.63 V (max)** — the ±10 % excursion
row 10's own ratified condition cell already names. The **device flavor** is
fixed in the same cell:

- **Active pair**: SiGe HBT, PDK flavor **`npn13G2v`** (the high-BVCEO
  flavor), cross-coupled differential, tail-current biased — DR-002.
- **Tuning device**: **`sg13_hv_svaricap`** over the full 0.0–3.3 V HV
  `Vctrl` domain, no band-switching bank in v1 — DR-001.
- **MOS corner family**: the **HV** MOS libraries (`cornerMOShv.lib`), which
  is what the committed netlist loads — consistent with the HV class, and the
  family the graded grids' `{tt,ss,ff,sf,fs}` axis refers to for this block.
- **`Vctrl` is a control node, not a supply.** DR-002 already separates the
  two explicitly; this row binds the rail and leaves `Vctrl`'s domain exactly
  where DR-001 put it.

**Basis.** Nothing is derived here: the rail and the device flavor are
DR-002's decision, and the committed netlist instantiates them
(`VSUP VDD 0 dc 3.3`; `XQ1`/`XQ2`/`XQ3`/`XQ4` = `npn13G2v`;
`cornerMOShv.lib`; 32 `sg13_hv_svaricap`). What this row adds is that the
decision is now **binding on the spec table**, with its graded excursion
stated, so a later schematic PR cannot quietly move the rail — the procedural
point DR-003 §Consequences item 4 made about exactly this row. The ±10 %
figure is quoted from row 10, not invented here; 3.30 V × 0.9 = 2.97 V and
3.30 V × 1.1 = 3.63 V.

**What is explicitly not decided here.** The tail-current value, the bias
network's own topology, and whether a future revision adds a supply
regulator. `design/vco.spice`'s `RREF`/`Q4`/`RRE` mirror is schematic-time
sizing, not a ratified spec quantity; a change to it is a `design/` PR and
grades against rows 6/7/8, not against this row.

### Row 3 — Kvco slope and its linearity: RATIFIED (target) — a stated window, a stated linearity measure and bound

Row 3's own surviving requirement from DR-003 is that "Kvco is graded as a
**Vctrl-window-referenced** slope/curve, monotonic where the measured dC/dV
is". This row therefore ratifies a window and a gradeable definition, not a
bare Hz/V number.

#### (a) The ratified window

**`W` = Vctrl ∈ [1.65 V, 3.30 V]** — the upper half of DR-001's domain.

Three reasons, in order of force:

1. **Below ≈ 1.5 V the varactor is not tuning at all.** In the
   characterization record's own column (`small`, `tt`, 27 °C, `c_5ghz_f`),
   mapped through `design/README.md`'s axis relation, the per-cell C moves
   from 5.56899 fF at Vctrl = 0.0 V to 5.63033 fF at Vctrl = 1.5 V — **1.1 %
   of C over 1.5 V of control range** — because the accumulation-mode
   device's steep C–V knee sits near `V_GB ≈ 0`, i.e. near Vctrl = 3.3 V as
   this schematic biases it. The pilot measures the consequence directly:
   +0.975 MHz/V over 0.0–0.6 V and −2.827 MHz/V over 0.6–1.2 V, i.e. ≤ 0.5 %
   of the same curve's steepest segment (−640.41 MHz/V). A window that
   includes that region is a window in which Kvco is not defined to any
   useful precision.
2. **1.65 V is where the committed benches already sample**, so this window
   costs no new instrumentation: `sim/oscillator-core/run_pvt_sweep.sh` sets
   `BAND_CENTRE_VCTRL="1.65"` and its declared 10-point axis is
   `{0.0 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0 3.3}` V — five of those points lie
   in `W`, including both endpoints; the phase-noise pilot's operating point
   is 1.65 V as well.
3. **It is the last axis point at which the window still contains a
   row-2-compliant range.** Solving `f = 1/(2π√(L_diff(f)·(F + C_var(V))))`
   self-consistently — `L_diff(f)` from `p11`'s `l_fitted_h`, `C_var(V)` from
   the varactor record's `c_5ghz_f` (8 cells' worth differentially, per
   `design/README.md`), `F` = 25.71 fF — the fractional range **inside** the
   window is 16.50 % over [1.65, 3.3] but 15.87 % over [1.8, 3.3] and 12.68 %
   over [2.4, 3.3]; and at the slow/hot varactor corner (`ss`, +125 °C) the
   same form gives 14.72 % over [1.65, 3.3], so [1.8, 3.3] would not hold
   15 % there. The pilot's measured 27 °C endpoints agree with the closed form
   over `W` to 0.02 pp (measured 5.384375 → 4.622456 GHz = **16.48 %**;
   closed form 16.50 %), which is the cross-check that the form is the right
   model before a window is chosen with it.

#### (b) What is graded over `W`, and against what bounds

All four are stated **at every bound corner of the row-10 set**, like every
other ratified row. `f(V_lo)`, `f(V_hi)` are the measured `f_osc` at the
window's endpoints (`V_lo` = 1.65 V, `V_hi` = 3.30 V).

1. **Monotonicity (binding, no numeric bound).** `Kvco` must be single-signed
   at every sampled segment inside `W`. *Basis*: the varactor record's own
   `C(Vctrl)` is strictly monotonic across the mapped interval (per cell:
   5.630 → 6.204 → 6.678 → 7.426 → 8.783 → 10.452 fF at Vctrl = 1.5 → 3.3 V),
   and the pilot measures one sign across `W` at all three temperatures.
   DR-003's "monotonic where the measured dC/dV is" is exactly this, now with
   the window it was missing.
2. **Window coverage ≥ 90 %** — `(f(V_lo) − f(V_hi))` must be ≥ 90 % of the
   **same corner's own** full-domain span `(f(0.0) − f(3.3))`. *Basis*: the
   closed form gives 93.35–95.53 % over all five MOS corners × three
   temperatures (worst `ss`/−40 °C = 93.35 %), and the pilot measures
   94.57 % / 95.68 % / 97.21 % at −40 / 27 / 125 °C. A 90 % floor keeps
   ≥ 3.4 pp of margin against the worst modelled value. Stating coverage
   *relative to the same corner's own range* is deliberate: it says "the
   window is where the tuning is" without re-specifying row 2's ≥ 15 %, which
   stays exactly as DR-003 ratified it, over the full 0.0–3.3 V domain.
3. **Mean slope magnitude ≥ 381 MHz/V** over `W`, where
   `|Kvco|_mean ≡ (f(V_lo) − f(V_hi)) / 1.65 V`. *This bound is not
   independent information* and is stated only so a row-3 grade is a
   checkable number rather than a pointer: it is row 2's ≥ 15 % range,
   geometrically centred in row 1's window (f = 5.0/√1.15 → 5.0·√1.15, span
   0.69938 GHz), times requirement 2's 90 % coverage, divided by the window's
   1.65 V width — 0.90 × 0.69938 GHz / 1.65 V = **381 MHz/V**. The closed
   form and the pilot both give ≈ 462 MHz/V at 27 °C (21 % above the floor);
   the closed form spans 418–499 MHz/V over the fifteen varactor
   corner/temperature combinations.
4. **Linearity: chord (integral) nonlinearity ≤ 30 % of span (target),
   ≤ 20 % (stretch).** Defined, once, so it is gradeable:

   ```
   chord(V)  = f(V_lo) + (f(V_hi) - f(V_lo)) * (V - V_lo) / (V_hi - V_lo)
   INL_pct   = 100 * max over sampled V in W of |f(V) - chord(V)|
                     / |f(V_hi) - f(V_lo)|
   ```

   **Grading grid**: at least five `Vctrl` points inside `W` including both
   endpoints. The committed 10-point axis already supplies exactly five
   (1.65, 1.8, 2.4, 3.0, 3.3 V), so no extra simulation is needed to grade
   this row.

   *Basis*. On that same five-point axis the closed form gives **22.3 %** at
   `tt`/27 °C, with the deviation peaking at Vctrl = 2.4 V, and **21.8 %
   (`ss`/27 °C) to 23.4 % (`ff`/−40 °C)** across all fifteen varactor
   corner/temperature combinations. The measure is nearly grid-independent —
   22.3 % on the committed five points, 22.3 % on a uniform 0.275 V grid
   (7 points), 22.9 % on a uniform 0.15 V grid (12 points) — and it inherits
   only ≈ 0.6 % of span from the pilot's own measured 0.09 % frequency
   quantization floor (0.0009 × 5 GHz ÷ 0.762 GHz of span). A **≤ 30 %**
   target therefore holds 6.6 pp (28 % relative) over the worst modelled
   corner, absorbing the two things this closed form does **not** sweep — the
   MIM corners and the EM inductor model's own ±10 % Q / ≈ 0.5 % rms ΔL bars —
   and the residual nonlinearity the model cannot see. **≤ 20 % sits below
   every modelled value**, so it demands a sizing change (more varactor, less
   `F`, or a C–V with a longer knee) rather than corner luck: it is the
   revisit-likely stretch, flagged here the same way DR-003 flagged rows 4
   and 9's stretch bounds.

5. **No upper bound on `|Kvco|` is ratified, deliberately.** An absolute
   Hz/V ceiling for a VCO comes from a loop's control-line noise budget, and
   `spec/target-spec.md`'s own Block class declares this block *not* embedded
   in a PLL in this repo's scope — there is no budget here to derive one
   from, so any ceiling would be an invented number. Requirement 4 already
   bounds the peak relative to the mean, which is the part of "Kvco is too
   peaky" that this block's own evidence can speak to.

#### (c) What the pilot's 332.8 % number is, and what it is not

`kvco_linearity_pct` — the bench's peak-to-peak per-segment slope spread over
the mean — is **not** the ratified measure, for two stated reasons, and its
332.821 % value at 27 °C **grades nothing**:

- It is **grid-dependent by construction**. Over `W`, the closed form gives
  116.8 % on three uniform segments, 125.6 % on six, 134.0 % on eleven and
  137.5 % on twenty-two — the same curve, four different numbers. A bound on
  it would have to pin the grid to mean anything, and the committed 10-point
  axis is non-uniform inside `W` (segments of 0.15, 0.6, 0.6, 0.3 V), so it
  cannot supply a uniform grid without new simulation.
- It is **already degenerate in the committed evidence**: the pilot's own
  tuning CSV reports `kvco_linearity_pct` = `nan` at both −40 °C and +125 °C,
  because those rows carry only three `Vctrl` points. Even as orientation it
  exists at one temperature only.
- Its 332.8 % value is a statement about the **full 0.0–3.3 V domain**, where
  it is dominated by the dead zone requirement (a) excludes: the same closed
  form gives 319.8 % over the full domain against 126.5 % over `W`. The two
  numbers are not comparable, and reading the full-domain figure as a row-3
  result is the specific error this window exists to prevent.

A graded pass may keep reporting the column — it is a useful descriptor of
shape. It is not a verdict, and `sim/oscillator-core/README.md`'s own framing
("This is evidence *for* row 3 (OPEN), not a verdict on it") stays correct
under this ratification, with "OPEN" now reading "RATIFIED as a target, not
met".

### Row 7 — Output swing: RATIFIED (target) — no output buffer in v1; ≥ 0.40 V Vpp differential at the tank nodes, into the stated load

Row 7's condition cell requires the load **and** the buffer state stated
alongside any swing number. Both are stated here; the row is not left
half-decided.

#### (a) The buffer decision, made explicitly

**No output buffer in v1.** This ratifies what the committed schematic
already assumes — `design/vco.spice` contains no buffer stage, and
`design/README.md:99-100` says so in as many words ("there is no output
buffer (row 7 is OPEN, and adding a buffer would bind it)"). The decision is
made here rather than left implicit because the row cannot be ratified
without it: the buffer is what would otherwise set the load.

Consequence, stated rather than buried: **v1 has no capability to drive a
50 Ω instrument, and this row makes no such claim.** It is a
simulation-graded differential swing at the tank nodes. Adding a buffer in a
later revision changes the load and therefore requires its own decision
record superseding this row, which must state the buffer topology, its input
capacitance, and the load it drives.

#### (b) The stated load

The row is graded on `v(OUTP) − v(OUTN)` at the tank nodes — the bench's
existing `vpp_diff_v`, reported per point already — with **no load beyond
what `design/vco.spice` itself carries**: `L_diff` = 11.4478 nH,
`C_tot` = 88.51 fF and `R_p,diff` = 1/`G_tank` = **3.418 kΩ** at 5.0 GHz band
centre (2.936 kΩ at the 4.62260 GHz low edge, 3.937 kΩ at the 5.41854 GHz
high edge), the varactor bank, and the pair itself.

**Any probe, pad or buffer capacitance a grading bench adds must be declared
with the measurement**, and it is not free: because `f ∝ C^(−1/2)`, an added
capacitance of 3 % of `C_tot` (≈ **2.1 fF** against the 70.3 fF `C_tot` at
the high endpoint) shifts f₀ by 1.5 % — which is exactly the margin the
committed high endpoint (5.41854 GHz) has under row 1's 5.5 GHz ceiling.
So a buffer cannot be hung on a grading bench without re-grading rows 1
and 2 as well. That is the concrete content of "adding a buffer would bind
it".

#### (c) The regime is current-limited, and this is arithmetic, not assertion

For a fully commutating cross-coupled pair the tail current is a square wave
into the differential tank, giving

```
Vpp_diff = (4/pi) * I_tail * R_p,diff
```

with `I_tail` = 204.1 µA (`design/README.md`, from the elaboration operating
point: `V(TE)` = 0.40811 V across `RTE` = 2 kΩ). Evaluated at the two band
edges, against what the pilot measured there:

| Point | `R_p,diff` | `(4/π)·I_tail·R_p` | Pilot `vpp_diff_v` (27 °C) | Δ |
|---|---|---|---|---|
| Vctrl = 3.3 V, 4.62260 GHz | 2.936 kΩ | 0.763 V | 0.8077 V | +5.9 % |
| Vctrl = 0.0 V, 5.41854 GHz | 3.937 kΩ | 1.023 V | 1.0980 V | +7.4 % |

The arithmetic tracks the measurement to better than 8 % at both edges, and
the pilot's own differential-mode evidence is what licenses the
"fully commutating" premise (`Vpp(cm)/Vpp(diff)` ≤ 1.06 % and
`f_tail/f_osc` = 2.000 at every measured point — one differential resonator
with TAIL a virtual ground at the fundamental). The **supply-clipped**
boundary is far away: per-node headroom is `VDD − V(TAIL)`, and the pilot's
own `v_tail_dc_op_v` is 2.5157 V at 27 °C (2.4553–2.6122 V across its three
temperatures), so the headroom is ≈ 0.78–0.84 V per node, i.e.
`Vpp_diff` ≈ 3.1–3.4 V — about 3× the operating point. **The regime is
current-limited**, so the swing is set by `I_tail · R_p` — which is why the
bound below is derived from those two quantities and not from the rail.

#### (d) The ratified bounds

**Target `Vpp_diff` ≥ 0.40 V; stretch ≥ 0.65 V** — everywhere in the row-3
window `W`, at every bound corner of the row-10 set, into the load of (b).

*Basis for 0.40 V.* Evaluate (c) not at the nominal tank Q but at **row 5's
own ratified floor** (`Q_loaded` ≥ 6, against the nominal 9.5), at the
window's worst point (Vctrl = 3.3 V, where `R_p` is smallest):
`ω·L_diff` = 2π × 4.62260 GHz × 10.8636 nH = 315.5 Ω, so `R_p` = 6 × 315.5 =
1.893 kΩ and `(4/π)·204.1 µA·1.893 kΩ` = **0.492 V**. A ≥ 0.40 V target
leaves **19 %** under that, which is the stated allowance for the one term no
record in this repo measures: the process spread of the resistor-programmed
tail mirror. (What *is* measured is only its temperature movement at the
nominal process corner — total core current −2.2 % / +3.6 % over the row-11
range, pilot `isup_ls_avg_a`.) That allowance is named as an allowance, not
dressed up as a derivation.

*Basis for the 0.65 V stretch.* 15 % erosion from the nominal band-worst
0.763 V of (c) — the same order of erosion allowance row 5's own stretch
carries (≥ 8 against a nominal 9.5, i.e. 16 %). Like row 5's, it demands the
illustration substantially realized across the corner set.

**No `Vpp_diff` maximum is ratified as a target.** The two ceilings that
exist are both far above the operating point and are arithmetic, not choices:
the voltage-limited boundary of (c) (≈ 3.1 V) and the BVCEO compliance
condition of (e) (≈ 4.3 V under its stated assumptions). Picking a number
between them would bind nothing and would be exactly the plausible-looking
filler `spec/target-spec.md`'s cardinal rule forbids.

#### (e) The compliance condition row 7 now carries, from DR-002

DR-002 handed forward one named verification burden: the 3.3 V rail with
`npn13G2v`'s **BVCEO 2.5 V (2.2 V min)** is only safe if the tail drop keeps
the worst-case VCE excursion inside breakdown. Row 7 is the row where swing
is graded, so the condition is attached here and made gradeable:

```
VCE_max = (VDD + Vpp_diff/4) - V(TAIL)_min  <=  BVCEO(min) = 2.2 V
```

at every bound corner (BVCEO, base-open, is the conservative rating; a
driven-base pair is rated higher). Evaluated across the pilot's three
temperatures at Vctrl = 0.0 V, where the measured swing is largest, using
each point's own `v_tail_dc_op_v`:

| Pilot point | `vpp_diff_v` | `v_tail_dc_op_v` | `VCE_max` | of 2.2 V |
|---|---|---|---|---|
| −40 °C | 1.24198 V | 2.45533 V | **1.155 V** | 53 % |
| 27 °C | 1.09800 V | 2.51567 V | 1.059 V | 48 % |
| 125 °C | 0.93589 V | 2.61225 V | 0.922 V | 42 % |

Inverted at the worst of those (`V(TAIL)` = 2.4553 V, `VDD_max` = 3.63 V),
the condition would permit `Vpp_diff` up to 4 × (2.2 + 2.4553 − 3.63) =
**4.1 V** — which is why (d) ratifies no maximum.

**This record does not perform that check over the row-10 corner set**, and
says so twice over. First, at the +10 % supply sub-corner both `V(TAIL)` and
the collector DC move (the mirror is rail-referenced), and `V(TAIL)` over the
row-10 set is recorded nowhere in this repo — the three values above are one
process corner. Second, the table above substitutes `v_tail_dc_op_v` for the
**instantaneous minimum of `V(TAIL)` over the cycle**, which nothing records:
the pilot reports only the DC operating point and the large-signal mean
(`v_tail_mean_v` = 2.6317 / 2.6649 / 2.7286 V at the same three points —
*higher* than the operating point, since the tail settles upward once the pair
switches), and the cycle's own 2f ripple amplitude is not in any CSV. Using
the lower of the two available stand-ins is the conservative choice for this
inequality, but it is still a stand-in. The check is owed to the graded pass,
which should report the per-corner cycle minimum rather than either average —
the improvement over DR-002's prose, where it was a note; it is now a stated
row-7 condition with an inequality a testbench can evaluate.

### Row 10's ±10 % supply sub-corners: how they cross the declared 135-point grid

Row 0 landing activates the clause row 10's ratified condition cell already
carries: *"supply voltage at ±10 % of the row-0 rail once row 0 lands
(sub-corners ride #33)"*. **This section states the crossing. It does not
change row 10's ratified corner set, and row 10's cells are not edited.**

**Reading DR-003 §Decision 10 before deciding.** Its own words are
"sub-corners", twice, and never "dimension" or "cross". Its Ground paragraph
binds the set to "the corner models the PDK v0.3.0 actually ships and the
three studies already used", so that "at every bound corner" means a corner
a committed testbench can instantiate. Supply is not one of those: **no PDK
corner library carries a rail axis.** ±10 % is a bias *condition* applied to
whichever model set is loaded, which is what makes "sub-corner" the right
word and a full third factor a reading the record does not support. I did not
find the question resolved anywhere else in DR-003, and this record is
therefore deciding it — explicitly, with its cost stated, and with a
falsifier.

**The disposition, in three stages:**

1. **Stage 1 — the declared 135-point model grid, at the nominal rail
   (3.300 V) only.** MOS `{tt,ss,ff,sf,fs}` × MIM
   `{cap_typ,cap_bcs,cap_wcs}` × HBT `{hbt_typ,hbt_bcs,hbt_wcs}` × T
   `{−40,+27,+125}` °C. **#50's and #53's declared grids and their cost
   estimates stand exactly as filed** — nothing about stage 1 changes.
2. **Stage 2 — the supply sub-corner set: 18 points.**
   `{2.970, 3.630} V` × `{SLOW, TYP, FAST}` × `{−40, +27, +125} °C`, where
   the three process vertices are aggregate, not a cross:
   - **SLOW** = MOS `ss` + HBT `hbt_wcs` + MIM `cap_wcs`
   - **TYP** = MOS `tt` + HBT `hbt_typ` + MIM `cap_typ`
   - **FAST** = MOS `ff` + HBT `hbt_bcs` + MIM `cap_bcs`

   Enumerable now, costable now, and every point is new (stage 1 is nominal
   rail only). Stage 2 reports the rows the rail actually moves: **1, 4, 6, 7
   and 8** — the rail sets `I_tail`, `I_tail` sets swing (row 7) and startup
   margin (row 6) and power (row 8) and, through swing, the carrier power
   row 4's noise depends on; and the rail moves f₀ itself (row 1, below).
3. **Stage 3 — conditional, and it is the falsifier.** If stage 2 moves any
   row's margin, at any of the 18 points, by **more than the margin stage 1
   left on that row**, the full 3-way cross (135 × 3 = 405 model-grid points)
   becomes required, and this reading of row 10 is superseded by a record
   that says so. The cheap reading is thereby falsifiable by its own
   evidence rather than merely asserted.

**Why the sub-corners cannot simply be skipped**, quantified: at row 9's
ratified pushing bound of ≤ 50 MHz/V, the full 2.97 → 3.63 V excursion is
allowed to move f₀ by up to 0.66 V × 50 MHz/V = **33 MHz** = 0.66 % of
5.0 GHz. The committed sizing's high endpoint (5.41854 GHz) sits **1.50 %**
under row 1's 5.5 GHz ceiling — so a rail excursion inside row 9's own
ratified bound can consume **44 % of row 1's remaining margin**. A grid that
never varies the rail cannot see that.

**Why the full cross is not warranted**, quantified from the two issues' own
declared figures:

| | #50 (rows 1/2/3/6/8) | #53 (row 4) |
|---|---|---|
| Declared stage 1 | 135 corners × 10-point `Vctrl` axis = 1350 transients, plus a 33-corner × 9-rung margin pass = 297 rungs → **1647 runs ≈ 180 CPU-h** (≈ 0.109 CPU-h/run) | 135 corners at band centre → **≈ 108 CPU-h** (≈ 0.80 CPU-h/corner) |
| Stage 2 addition | 18 × 10 = 180 transients + margin pass at `{2 rails} × {SLOW,FAST} × {−40,+125}` = 8 corners × 9 = 72 rungs → 252 runs ≈ **27 CPU-h, +15 %** | 18 corners ≈ **14 CPU-h, +13 %** |
| Full 3-way cross instead | +2 × 1647 = 3294 runs ≈ **+360 CPU-h, +200 %** | +270 corners ≈ **+216 CPU-h, +200 %** |

The per-run costs above are derived from each issue's own declared totals, not
re-measured here, and the full-cross column reproduces the totals those issues
themselves quote for it (#50: ≈ 540 CPU-h at 405 points; #53: ≈ 324 CPU-h) —
which is the cross-check that the per-run figures are read right. Tripling two
grids that are already blocked on a compute gap
(2AMLogic/klayout-tools#2511), to test an interaction no evidence in this repo
suggests exists, is a cost this record declines to impose — while refusing to
leave the rail untested, which is what stage 2 buys for ≈ 13–15 %.

**One boundary, stated so the two are not conflated**: stage 2 is **not** a
substitute for row 9's pushing measurement, and row 9 is not a substitute for
stage 2. Row 9 is a small-signal derivative at the nominal rail; stage 2 is a
two-point large-signal secant across ±10 %. They should be reported alongside
each other, and a disagreement between them beyond their stated bars is a
finding either way — not a reason to drop one.

## Alternatives considered

- **Leave row 7 OPEN with a named follow-on buffer record** (the issue's
  explicitly permitted option (b)). Rejected, because the buffer question is
  not actually undecided: the committed schematic has no buffer, states that
  it has none, and states why. Re-gating the row on a record nobody has a
  reason to write would leave `spec/target-spec.md` open on a question
  `design/` already answered — and DR-003's own standard is that an OPEN row
  must name a gate that something is actually waiting for. Ratifying "no
  buffer in v1" with the load and the BVCEO condition stated is the stronger
  reading of "explicitly, not silently": if a buffer is ever added, the
  superseding record is triggered by the design change, which is the right
  ordering.
- **Ratify a single Kvco number in MHz/V over 0.0–3.3 V.** Rejected on the
  evidence. The pilot's measured curve spans +0.975 to −640.41 MHz/V; its mean
  over the full domain (−192.7 MHz/V) describes no part of the curve, and a
  bound on it would be passed or failed by where the dead zone happens to
  end rather than by anything about the design. This is the failure mode
  issue #57 named and it is the reason row 3's disposition is a window plus a
  measure.
- **Keep the bench's existing `kvco_linearity_pct` as the ratified linearity
  measure**, so no new post-processing is needed. Rejected: it is
  grid-dependent (116.8 % → 137.5 % over `W` for the same curve as the grid
  refines), it is `nan` in two of the pilot's own three temperature rows, and
  grading it would require pinning a uniform `Vctrl` grid the committed
  10-point axis does not supply — new simulation, to grade a weaker measure.
  The chord measure grades on the existing axis and converges as the grid
  refines.
- **A tighter linearity target (≤ 25 %) to match the modelled 22.3 %
  closely.** Rejected: the closed form sweeps only the varactor's own
  corners, holding `F`, `L_diff(f)` and the MIM fixed — it does not carry the
  MIM corner set, the EM model's ±10 % Q / ≈ 0.5 % rms ΔL bars, or the
  HBT loading `design/README.md` explicitly leaves out of its own Q sum. A
  target 1.6 pp above the worst modelled corner would be a target set by an
  incomplete model's precision rather than by what the design owes. ≤ 30 %
  target with ≤ 20 % as the revisit-likely stretch is DR-003's own pattern.
- **Ratify the full 3-way supply cross (405 model-grid points).** Rejected on
  DR-003's own wording ("sub-corners", and a corner set bound to shipped PDK
  *model* libraries, which have no rail axis) and on the cost arithmetic
  above: +200 % on two grids already blocked on compute, to test an
  interaction nothing in this repo's evidence suggests. Stage 3 is what keeps
  that rejection honest — the full cross is required the moment stage 2
  produces a reason for it.
- **Leave the supply sub-corners unstated and let whoever runs #50/#53
  decide.** Rejected. Row 10's ratified cell activates the sub-corners the
  moment row 0 lands, so silence here would not mean "no sub-corners"; it
  would mean two grids running with an unstated corner set, which is the
  opposite of `spec/review-bar.md`'s reproducibility bar. The consequence is
  not hypothetical: #50 and #53 each already state that their 135-point grid
  excludes a supply dimension *pending row 0*.
- **Re-open or relax any of DR-003's nine ratified rows** in light of the
  pilots (row 4's measured miss is the obvious temptation, and row 2's
  stretch is not met by the committed sizing either). Refused, per
  `CLAUDE.md`: agents do not relax the ratified spec to make results pass,
  and a supersede is its own record with its own review. This record states
  the row-4 margin finding in "Consequences" — where it belongs, as a named
  risk for the graded pass — and edits nothing.

## Spec lines affected

`spec/target-spec.md`, and nothing else in `spec/`:

- **Header Status bullet**: "PARTIALLY RATIFIED — 9 target rows, 3 explicitly
  open" becomes a full-ratification statement — **12 target rows, none
  open** — citing DR-003 for the nine and DR-004 for rows 0/3/7, and noting
  that row 10's ±10 % supply sub-corners are now active with their crossing
  stated in DR-004 (row 10's own ratified set unchanged).
- **Date / "How to read this file" / summary-table preamble**: the
  pass-2 date added; the status vocabulary extended with
  `RATIFIED (target) per DR-004`; the "Nine rows … Three rows are OPEN"
  sentence updated to match the table. The cardinal rule is unchanged, and
  the historical "Why every cell is blank in this pass" section is left
  verbatim as DR-003 left it, with one dated sentence appended in the same
  append-not-rewrite style DR-003 used.
- **Row 0**: min/typ/max filled (2.97 / 3.30 / 3.63 V); condition cell
  restated to the ratified rail + device flavor + the `Vctrl`-is-not-a-supply
  separation; status cell **OPEN per DR-003 → RATIFIED (target) per DR-004**.
- **Row 3**: condition cell restated to the window `W`, the four graded
  requirements and the chord-nonlinearity definition, with the
  `kvco_linearity_pct` disposition named; max cell carries the linearity
  bound, min cell the derived mean-slope floor; status cell **OPEN per
  DR-003 → RATIFIED (target) per DR-004**.
- **Row 7**: min cell 0.40 V (0.65 V stretch); condition cell restated to
  the no-buffer decision, the stated load, the current-limited regime and
  the BVCEO compliance inequality; status cell **OPEN per DR-003 →
  RATIFIED (target) per DR-004**.
- **Rows 1, 2, 4, 5, 6, 8, 9, 10, 11: not edited.** No bound, condition or
  status cell of any row DR-003 ratified is changed by this PR — verifiable
  from its diff.

No `design/` or `sim/` file is edited by this PR. `signoff/manifest.json`
and `signoff/t1-report.json` are unchanged and re-render byte-identically in
their graded payload (see Consequences item 5); `signoff/README.md`'s
one-sentence description of the spec's ratification state is updated to match
this pass, since this PR is what makes the old wording false.

## Consequences

1. **`spec/target-spec.md` is fully ratified, and T1 item 5's precondition is
   cleared for every row.** Verdicts against a draft or partially-open spec
   were provisional for rows 0/3/7; once the graded grids run, all twelve
   rows grade against binding targets. Nothing is met: no row's status
   changes from "not met" in this PR, because no evidence is minted by it.
2. **Row 3 is now gradeable on the bench that already exists.** The window's
   five committed axis points and the chord measure need no extra
   simulation — only a post-processing column. That is the concrete win of
   choosing a measure that converges under grid refinement instead of one
   that diverges.
3. **Row 7's ratification turns DR-002's loose verification note into a
   gradeable inequality**, and makes the "no buffer" assumption in
   `design/README.md` a spec fact rather than a schematic convention — with
   the price of adding a buffer stated (re-grade rows 1 and 2; supersede
   row 7).
4. **A named risk for row 4, which this record does not act on.** Row 7's
   arithmetic makes the carrier power explicit, and it is lower than the
   illustration DR-003's row-4 Leeson pass assumed. At the phase-noise
   pilot's own operating point (27 °C, `Vctrl` = 1.65 V,
   `Vpp(VDIFF)` = 1.086791 V, `f_osc` = 5.384250 GHz, `R_p` ≈ 3.895 kΩ
   interpolated between `design/README.md`'s band-centre and high-edge
   values, `Q_loaded` ≈ 9.44), the carrier power in the tank is
   `(Vpp/2)²/(2R_p)` = **37.9 µW**, not the 0.2 mW DR-003's illustration
   used. Re-running the *same* Leeson form on the committed sizing's own
   numbers (F ≈ 2, kT = 4.14 × 10⁻²¹ J) gives
   `10·log₁₀[(2·4.14e-21/3.79e-5)·(5.384e9/(2·9.44·1e6))²]` ≈ **−107.5
   dBc/Hz** at 1 MHz — ≈ 2.5 dB under row 4's ratified −105 target, where
   DR-003's illustration implied ≈ 8 dB. The ISF pilot measured
   **−102.2763 ± 0.2953 dBc/Hz** at that corner (row 4: NOT MET, one corner,
   grading nothing), i.e. 5 dB worse again than the corrected first pass —
   which is a finding about the estimator's optimism, not about the row.
   **Row 4 is untouched by this record.** The disposition of that gap is
   #53's graded grid and, if it confirms the miss, a design change or a
   superseding record — never an edit to the row, per `CLAUDE.md` and per
   #53's own out-of-scope statement.
5. **No evidence is minted, so the verdict of record does not move.**
   `signoff/t1-report.json` is manifest-driven (`evidence: {}`) and is
   independent of the spec's ratification state; re-rendering it from the
   committed manifest and the vendored tiers doc reproduces the committed
   record's graded payload byte-for-byte — all 11 items `unmet` /
   `no_evidence`, `t1_met_count: 0`, same `source_doc_content_hash`.
   (Verified in this PR; the only lines that differ are the `build.*`
   identity fields, because the render available on the authoring host is a
   git build — the exact gotcha `signoff/README.md` documents. CI renders
   from the pinned `0.6.0` release, which is what the committed record was
   rendered with.) So the report stays 0/11 and is **not** re-rendered here.
6. **Two graded grids gain 18 points each, and their owners are told.** #50
   and #53 each declared a 135-point grid with no supply dimension,
   explicitly pending row 0. Stage 2 above adds ≈ 27 CPU-h (+15 %) to #50 and
   ≈ 14 CPU-h (+13 %) to #53. Both issues are updated with this disposition
   when this PR opens; neither is unblocked by it (the compute gap,
   2AMLogic/klayout-tools#2511, is untouched).
7. **What gets harder.** Row 3's window is now a spec fact, so a later
   `design/` change that shifts the varactor's C–V knee — a different
   geometry, a different bias polarity, a band-switching bank — moves the
   usable window and therefore needs row 3 re-read against the new curve, not
   merely re-measured. And row 7's stated load means the first real
   measurement path (a buffer, a pad, an instrument) cannot be added without
   a superseding record. Both are deliberate: they are the cost of the row
   being gradeable at all.
8. **Nothing here claims a measurement.** Every bound above is a target.
   The pilots are orientation and cross-check; the graded verdicts belong to
   #50 and #53 and to whatever records dispose of what they find.

## Open items

- **Row 7's BVCEO compliance over corners** — the inequality is ratified;
  `V(TAIL)` over the row-10 set is not recorded anywhere, so the check is
  owed to the graded pass (and to stage 2's +10 % rail points in
  particular). DR-002 named this burden; this record makes it gradeable, not
  discharged.
- **Row 3's closed form does not sweep everything.** It varies the
  varactor's own corners only, holding `F`, the MIM and `L_diff(f)` fixed,
  and excludes the HBT's `r_b`-through-`C_bc` loading that
  `design/README.md` also leaves out of its Q sum. The ≤ 30 % target's 6.6 pp
  of headroom is where those unswept terms are supposed to fit; if the graded
  grid says otherwise, that is a finding, and the disposition is a record,
  not an edit.
- **Stage 3 of the row-10 disposition** — whether the full 405-point cross is
  required is decided by stage 2's own output, on the criterion stated above.
  Nobody should pre-emptively run it, and nobody should quietly skip stage 2.
- **Row 4's margin (Consequences item 4)** — the corrected Leeson pass and
  the ISF pilot both point the same way. The honest next step is #53's graded
  grid; the step after it, if the miss holds, is a `design/` change (more
  swing means more `I_tail` or more `R_p`, both with row-5/row-8 costs) or a
  superseding spec record. Not this record's call.
- **Row 2's stretch (≥ 20 %)** stays unmet by the committed sizing (17.22 %
  measured, 17.43 % closed-form), for the reason `design/README.md`
  diagnoses (`L_diff(f)` rises 12.7 % across the band and spends the margin).
  Recorded here as still-open work, not re-ratified or relaxed.
- **The `Status:`-staleness wart and the absent two-key tree** remain
  fleet-scoped questions (2AMLogic/product#135); this record follows DR-003's
  handling verbatim and installs nothing.

## Sources

- `spec/target-spec.md` — the table this record disposes (rows 0, 3, 7 and
  the Status header), and its cardinal rule.
- `spec/decision-records/DR-003-target-spec-ratification.md` — pass 1; §Row 0
  / §Row 3 / §Row 7 (the three gates), §Decision 10 (the sub-corner clause
  read in full before the crossing above was decided), and the
  partial-ratification model this record continues. Not edited.
- `spec/decision-records/DR-002-negative-gm-pair-device-class.md` — row 0's
  device class, flavor and rail; `npn13G2v`'s BVCEO; the VCE-compliance
  burden row 7 now carries.
- `spec/decision-records/DR-001-tuning-mechanism.md` — the `Vctrl` domain and
  the no-band-switching decision both rows 0 and 3 inherit.
- `spec/decision-records/TEMPLATE.md` — numbering/collision rule, status
  lifecycle, append-only rule.
- `design/vco.sch` / `design/vco.spice` / `design/README.md` (#44) — the
  committed sizing, the operating point (`I_tail`, `V(TAIL)`), the `L_diff(f)`
  and `G_tank` tables, the measured fixed-C `F`, the varactor-polarity axis
  relation, and the no-buffer statement at lines 99–100.
- `sim/oscillator-core/` (#47) — `run_pvt_sweep.sh`'s declared 10-point
  `Vctrl` axis and 135-point grid; `README.md`'s own Kvco-shape section; and
  pilot record `20260926-010627-e391693` with its `-pilot.csv`,
  `-pilot-tuning.csv` and `-pilot-kvco.csv` (orientation only — that record
  states it grades no row).
- `sim/phase-noise/` (#49) — pilot record `20260926-071903-7a02483`
  (`L(1 MHz)` = −102.2763 ± 0.2953 dBc/Hz at one corner), cited only in
  Consequences item 4.
- `sim/varactor-characterization/records/20260909-231619-de50891.csv` —
  `c_5ghz_f` / `q_5ghz` per cell over the `vctrl_v` grid at five MOS corners
  × three temperatures; the C(V) kernel row 3's closed form uses.
- `sim/inductor-model/em-extraction/records/20260910-052657-3896421-em-vs-analytic.csv`
  — `p11`'s `l_fitted_h(f)`, the EM-fitted model the netlist instantiates.
- `signoff/README.md` + `signoff/manifest.json` + `signoff/t1-report.json` —
  the verdict of record, its drift gate, and the git-build gotcha quoted in
  Consequences item 5.
- Issues #3 (tracker; operator sequence step 4), #35 (DR-003), #33 (DR-002),
  #44 (schematic), #47 / #49 (the two benches), **#50** / **#53** (the graded
  grids this record's row-10 disposition binds), #57 (this record's issue).
- 2AMLogic/2am#357 (ratification-via-PR ruling) and 2AMLogic/product#135
  (two-key tree absent fleet-wide; the `Status:` staleness wart) — the
  mechanism this record exercises, unchanged from DR-003.
- 2AMLogic/klayout-tools#2511 — the `klt sim` gap blocking both graded grids;
  named here because it is why every row this record ratifies is a target
  rather than a verdict.
- Leeson, D. B., "A Simple Model of Feedback Oscillator Noise Spectrum,"
  *Proceedings of the IEEE*, 1966 — the first-pass form re-evaluated in
  Consequences item 4, same form DR-003 §Decision 4 used.
- Hajimiri, A. and Lee, T. H., "A General Theory of Phase Noise in Electrical
  Oscillators," *IEEE JSSC*, 1998 — this repo's canonical phase-noise frame
  (`CLAUDE.md`), of which the Leeson form is the frequency-domain
  simplification; the frame `sim/phase-noise`'s ISF estimator implements.
- This repo's own `CLAUDE.md` — "State the tuning plan honestly" (row 3's
  window and its dead zone are stated, not smoothed over), "no claim without
  a testbench", "numbers without methods are not results", and "agents do not
  relax the ratified spec to make results pass".
