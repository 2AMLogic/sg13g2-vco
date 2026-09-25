# design/ — LC-VCO core schematic and its derived netlist

The oscillator core: an xschem schematic, the netlist **derived** from it, and
a cold-start script that elaborates that netlist under ngspice against the
pinned PDK and runs a startup transient.

| File | What it is |
|---|---|
| [`vco.sch`](vco.sch) | **The source of truth.** xschem schematic of the LC-VCO core (issue #44). |
| [`vco.spice`](vco.spice) | **Derived file — never hand-edited.** xschem's netlist of `vco.sch`, normalised (see below). |
| [`netlist.sh`](netlist.sh) | Re-derives `vco.spice` from `vco.sch`; `--check` fails if the committed netlist has drifted. |
| [`run_elaborate.sh`](run_elaborate.sh) | Cold-start elaboration check: netlist freshness → OSDI build → ngspice operating point + startup transient at three `Vctrl` points. |
| [`.spiceinit`](.spiceinit) | `set ngbehavior=hsa`, copied into the run directory so a cold checkout does not depend on the PDK's `install.py` having symlinked one into `$HOME`. |

**What is here and what is not.** This directory is the schematic and its
elaboration check. It is **not** a testbench tree: no graded frequency/Kvco
bench, no phase-noise bench, no startup-margin bench, no PVT sweep, and no
evidence record. Those belong under `sim/` with its append-only record
convention (`sim/README.md`), and no number in this README or in
`run_elaborate.sh`'s output grades a `spec/target-spec.md` row. Everything
below is **nominal-corner, single-run design arithmetic**, stated with its
method so a later graded bench can be compared against it.

## How the netlist is derived

```bash
design/netlist.sh            # regenerate design/vco.spice from design/vco.sch
design/netlist.sh --check    # fail if the committed netlist is stale
design/run_elaborate.sh      # --check, then build OSDI, then elaborate + run
```

`netlist.sh` runs `xschem -n -q -r --rcfile $PDK_ROOT/$PDK/libs.tech/xschem/xschemrc`
and applies exactly two normalisations to the raw output, so the committed file
is machine-independent: the `** sch_path:` header (which carries an absolute
path) is rewritten to `design/vco.sch`, and trailing whitespace is stripped.
Device lines are xschem's verbatim. `run_elaborate.sh` calls
`netlist.sh --check` **first**, so a run can never silently simulate a netlist
that has drifted from the schematic.

The committed netlist carries three `@@TOKEN@@` placeholders in place of
machine-specific absolute paths — the same substitution mechanism the
`sim/*/run_*.sh` testbench templates use. `run_elaborate.sh` substitutes them
and refuses to run if any survives:

| Token | Resolves to |
|---|---|
| `@@MODELS_DIR@@` | `$PDK_ROOT/$PDK/libs.tech/ngspice/models` (`cornerHBT.lib hbt_typ`, `cornerMOShv.lib mos_tt`, `cornerCAP.lib cap_typ`) |
| `@@IND_MODEL@@` | `sim/inductor-model/sg13g2_inductor_em.spice` — this repo's own EM-fitted `inductor` subckt; **the PDK ships none** (`sim/pdk.json` → `known_model_gaps.spiral_inductor`) |
| `@@OSDI_MOSVAR@@` | `mosvar.osdi`, built by `sim/tools/build-osdi.sh`; loaded with `pre_osdi` *inside* `.control` and **before** the first analysis command, because ngspice defers OSDI device instantiation to analysis setup rather than to netlist parse |

## Which records fix the topology

Nothing about the topology is chosen in this directory. It is fixed by three
landed decision records, and this schematic only performs the sizing they
deliberately left to schematic time:

- **`spec/decision-records/DR-001-tuning-mechanism.md`** — tuning device is
  `sg13_hv_svaricap` (MOS accumulation-mode varactor), driven over the full
  0.0–3.3 V HV `Vctrl` domain; no band-switching capacitor bank in v1.
- **`spec/decision-records/DR-002-negative-gm-pair-device-class.md`** — SiGe HBT
  cross-coupled differential pair, high-BVCEO flavor `npn13G2v`, biased from the
  3.3 V rail, tail-current biased. DR-002 explicitly does **not** size the pair
  or design its bias network.
- **`spec/decision-records/DR-003-target-spec-ratification.md`** — the nine
  ratified `spec/target-spec.md` rows this sizing is answerable to (rows 0, 3
  and 7 remain OPEN and are **not** touched here).

## The circuit, as drawn

```
        VDD                                   VDD
         |                                     |
    [ L1 p11 ]                            [ L2 p11 ]      two p11 spirals,
         |                                     |          EM-fitted subckt
  OUTP --+---------------[ C1 ]----------------+-- OUTN   cap_cmim 3.65x3.65
         |                                     |
  16x sg13_hv_svaricap                  16x sg13_hv_svaricap
    W,bn -> tank node                     W,bn -> tank node
    G1,G2 -> VCTRL                        G1,G2 -> VCTRL
         |                                     |
       Q1 c                                  c Q2         npn13G2v, El=1.0
        b >--------- cross-coupled ----------< b          (base of one to the
        e                                     e            other's collector)
         +------------------+------------------+
                          TAIL
                            |
                          Q3 c   (npn13G2v, El=2.0)     Q4 diode-connected
                           b <--- NBIAS ---+--- RREF 20.5k --- VDD
                           e               |
                           |            (Q4 b=c)
                        RTE 2k              e
                           |                |
                           0             RRE 4k
                                            |
                                            0
```

A single `Vctrl` net spans the full 0.0–3.3 V domain and drives all 32 varactor
cells. `VSUP` is an ideal 3.3 V source; there is no output buffer (row 7 is
OPEN, and adding a buffer would bind it).

## Tank sizing, with its arithmetic

All device numbers below are read out of this repo's own committed evidence
records at the **nominal** point (`tt` / `hbt_typ` / `cap_typ`, 27 °C, 5.0 GHz),
not estimated:

| Element | Source | Value |
|---|---|---|
| Inductor `p11` (w = 8.22 µm, s = 3.74 µm, d = 141.975 µm, nr_r = 4) | `sim/inductor-model/em-extraction/records/20260910-052657-3896421-em-vs-analytic.csv`, `p11` row at 5.0 GHz, `l_fitted`/`q_fitted` | L = 5.72389 nH, Q = 10.7019 (raw EM: 5.69836 nH / 10.2804); SRF = 9.42 GHz |
| Varactor cell `mos_small` (l = 0.3 µm, w = 3.74 µm, Nx = 1) | `sim/varactor-characterization/records/20260909-231619-de50891.csv` (`device_key=small`, `tt`, 27 °C; its swept column is `vctrl_v`) | C = 10.4522 fF @ `vctrl_v` = 0.0 V, C = 5.56899 fF @ `vctrl_v` = 3.3 V; Q = 44.79 / 84.92 |
| `cap_cmim` 3.65 × 3.65 µm | PDK `capacitors_mod.lib` `cmim_core` (CJ = 1.5 fF/µm², CJSW = 40 aF/µm, series R = 55 mΩ) | C = 20.57 fF |

**Which inductor model, and why it matters.** The netlist instantiates
`sim/inductor-model/sg13g2_inductor_em.spice` — the **EM-fitted** subckt (see
`@@IND_MODEL@@` above) — so every number in this section is read from the
EM-extraction record, *not* from
`sim/inductor-model/records/20260910-052743-3896421.csv`. That latter record's
model-under-test is `sg13g2_inductor_analytic.spice`, the analytic screening
model, and its own companion `.md` says it "does NOT claim the model is a
faithful description of a real SG13G2 spiral"; `sim/pdk.json` and
`sim/inductor-model/README.md` both make the EM-fitted model the authoritative
one for `p1`/`p13`/`p11` and treat the analytic model's Q as an upper bound.
`spec/target-spec.md` rows 1 and 5 were ratified against the EM-fitted model.
The two disagree materially at 5 GHz — analytic 5.24033 nH / Q 12.3419 vs.
EM-fitted 5.72389 nH / Q 10.7019, and SRF 14.11 GHz vs. 9.42 GHz — so the
sourcing is stated explicitly rather than left to the reader.

The `l_fitted`/`q_fitted` columns are used in preference to `l_em`/`q_em`
because they *are* the driving-point behaviour of the subckt the netlist
actually elaborates; `l_em`/`q_em` are the raw openEMS solve the subckt was
fitted to, and are quoted alongside as a cross-check. The two differ by < 0.5 %
in L and ≈ 4 % in Q at 5 GHz, consistent with the record's stated `p11` fit
residual (rms ΔL 0.48 %, rms ΔQ 5.16 %).

**The inductor geometry is one of the three EM-extracted ones** (`p11`), so no
extrapolation error bar applies: `sg13g2_inductor_em.spice` is authoritative
only at `p1`/`p13`/`p11`. `p1` (0.0985 nH at 1 GHz) is far too small to resonate
in the row-1 band with any realisable capacitance, and `p13` (7.938 nH at 5 GHz,
and with an 8.07 GHz SRF — lower still) is *larger* than `p11`, which pushes the
required tank capacitance further below the fixed-C floor discussed under row 2.
`p11` is the smallest usable validated geometry.

**L is frequency-dependent, and the arithmetic below respects that.** The
EM-fitted `p11` subckt is not a constant inductor: its effective L rises
monotonically with frequency, because the tank is working up the skirt of a
9.42 GHz self-resonance (`l_fitted` for `p11` goes 4.27 nH at 1 GHz → 5.72 nH at
5 GHz → 8.91 nH at 7 GHz → 13.57 nH at 8 GHz). Two inductors, one per side
(VDD → OUTP, VDD → OUTN), give:

| f | L per side (`l_fitted`) | **L_diff** |
|---|---|---|
| 4.62260 GHz (`Vctrl` = 3.3, low end) | 5.43182 nH | **10.8636 nH** |
| 5.0 GHz (band centre) | 5.72389 nH | **11.4478 nH** |
| 5.41854 GHz (`Vctrl` = 0, high end) | 6.12094 nH | **12.2419 nH** |

i.e. **L_diff = 11.4478 nH at band centre, moving +12.7 % from the bottom of the
band to the top.** That is real physics, not an artifact, and it works *against*
the tuning range — see row 2 below.

The two inductors also supply the pair's DC collector feed, so the tank carries
no bias resistors and therefore no resistive Q loading. The alternative — one
spiral across OUTP–OUTN (L_diff = 5.72 nH at band centre) — has no centre tap in
the EM-fitted model and would need two supply-feed resistors across the tank;
the model's three validated geometries include no centre-tapped device, so that
option is not available at a validated geometry at all.

**Carrier-to-SRF margin, and the fit-band ceiling (row 1's real bound).** The
EM-extracted `p11` self-resonance is **9.42 GHz** (the fitted subckt's own SRF is
9.51 GHz, +0.9 %), so the highest carrier this schematic produces, 5.41854 GHz,
sits **≈ 1.74× below SRF** — not the ≈ 2.6× the analytic model's 14.11 GHz would
have suggested. The *binding* bound is tighter still and is not the SRF at all:
the `p11` lumped fit is only validated over **0.3–8.008 GHz** (record §"Fit
residual"), so 8.008 GHz — not 9.42 GHz — is the ceiling under which every number
here has to sit. Row 1's 4.5–5.5 GHz window is comfortably inside it (5.5 GHz is
0.69× the fit-band ceiling and 0.58× SRF), which is what makes row 1's sizing
defensible; but the margin is modest enough that it must be stated, because it is
also *why* L(f) rises 12.7 % across the band above, and why an L treated as
constant gets the tuning arithmetic wrong.

### Varactor polarity — the choice DR-001 left open

DR-001 (§"`Vctrl` domain") explicitly does **not** fix which physical node
carries `Vctrl`: *"Which node is the tank's own AC node is a schematic-level
decision for the … oscillator design, not a fact this device-level sweep
determines on its own."* This schematic makes that decision:

> **Gates `G1`/`G2` → `VCTRL`; well + buried-n `W`/`bn` → the tank node.**

This is the **opposite** of `sim/varactor-characterization`'s own testbench
convention, and it is forced by the tank's DC bias. The inductors are a DC
short to VDD, so each tank node sits at exactly 3.3 V.

**Axis conversion, stated once and used everywhere below.** The characterization
record's swept column is `vctrl_v`, which in *its* testbench is the voltage on
the **well/bn** node with the gates DC-referenced to 0 V through a choke (record
§Method). So that record's axis is `V_GB = −vctrl_v`: its `vctrl_v` = 0.0 V row
is `V_GB` = 0 (C = 10.4522 fF, Q = 44.79) and its `vctrl_v` = 3.3 V row is
`V_GB` = −3.3 V (C = 5.56899 fF, Q = 84.92). This schematic's `Vctrl` net is a
third, distinct axis: gates are driven, the well sits at 3.3 V, so
`V_GB = V(VCTRL) − 3.3` and therefore `vctrl_v = 3.3 − V(VCTRL)`. Wherever a
`V_GB` value appears below it is that quantity, converted from the record's
`vctrl_v` column by this relation — never the record's raw column value.
Therefore:

- as drawn: `V_GB = V(VCTRL) − 3.3` sweeps **0 → −3.3 V** as `Vctrl` sweeps
  3.3 → 0 V. That is precisely the `V_GB` branch the characterization measured,
  and the branch that carries the whole 1.88× `Cmax/Cmin`;
- the other orientation (gates on the tank node) would make
  `V_GB = 3.3 − V(VCTRL)` sweep **0 → +3.3 V**, i.e. entirely on the
  accumulation side, where the measured C is already at its maximum
  (10.4522 fF at `V_GB = 0`) and saturating. It would deliver nearly **no**
  tuning.

`W` and `bn` are tied together, as in the characterization testbench — which
shorts out the internal `dsubw` well-to-substrate junction rather than hanging
it on the tank node — so the two-terminal impedance, and hence its Q, is the
same either way; only the sign of `dC/dV` and the reachable `V_GB` branch
differ. **Consequence, stated rather than buried:** frequency is now *maximum*
at `Vctrl = 0` and *minimum* at `Vctrl = 3.3`, inverted with respect to the
record's `vctrl_v` axis, and Kvco is strongly non-linear — see "Reportable
findings" below.

### Row 2 — tuning range ≥ 15 % (F ≤ 0.92·V)

Sixteen cells per side, i.e. 32 cells, all in parallel between a tank node and
`VCTRL`. Two equal single-ended banks present **half** their capacitance to the
differential port, so the differential varactor contribution is 8 cells' worth:

```
V_max = 8 × 10.4522 fF = 83.62 fF   (Vctrl = 3.3 V, V_GB = 0,    record vctrl_v = 0.0)
V_min = 8 ×  5.56899fF = 44.55 fF   (Vctrl = 0.0 V, V_GB = -3.3, record vctrl_v = 3.3)
dV    = 39.07 fF,  V_max/V_min = 1.877
```

DR-003 §Decision 2's bound for ≥ 15 % is `F ≤ 0.92 · V`, with `V` the varactor
contribution at its maximum:

```
row-2 bound:  F <= 0.92 × 83.62 fF = 76.9 fF
```

`F` as drawn is the `cap_cmim` (20.57 fF) plus everything else that loads the
tank and does not tune — HBT C_bc/C_cs, the tank-side substrate network of each
spiral, the varactors' own internal `Ck`/`Cic`, wiring. None of those is
separately characterized by any record here, so `F` is **measured out of the
elaboration run** rather than guessed, using the two endpoint frequencies and
`L_diff` **evaluated at each of those frequencies** (per the L(f) table above —
using a single constant `L_diff` here is what made an earlier revision of this
section wrong):

```
C_tot = 1/(w^2 L_diff(f))
  at f = 5.41854 GHz (Vctrl = 0.0):  L_diff = 12.2419 nH
                                     C_tot =  70.47 fF  ->  F =  70.47 - 44.55 = 25.92 fF
  at f = 4.62260 GHz (Vctrl = 3.3):  L_diff = 10.8636 nH
                                     C_tot = 109.12 fF  ->  F = 109.12 - 83.62 = 25.50 fF
```

**F = 25.5–25.9 fF = 0.30–0.31 · V_max — comfortably inside the 76.9 fF bound,
with about 3× headroom.** Of that, 20.6 fF is the drawn MIM and ≈ 5 fF is
parasitic.

**The two endpoint estimates agree to 0.4 fF**, which is the real result of this
sub-section: `F` is a genuinely *fixed* capacitance, as its name asserts, and the
two independent measurements of it are consistent. Equivalently, the varactor's
*effective* large-signal dC across the band is 38.64 fF against the small-signal
39.07 fF — **98.9 %**, i.e. essentially no large-signal compression of dC at all,
despite a ±0.275 V per-node swing (1.10 V peak-to-peak differential) over a
non-linear C(V). (The residual 0.4 fF
is within the L(f) interpolation and the record's own ≈ 0.5 % rms ΔL fit
residual, so it does not support a compression claim in either direction.)

With `F` fixed, the closed form is no longer `sqrt((F+V_max)/(F+V_min))` — that
expression assumes a constant L. Solving `f = 1/(2π√(L_diff(f)·C))`
**self-consistently** in f, with `C = F + C_var(V)` and `F` = 25.71 fF (the mean
of the two endpoint estimates), reproduces both simulated endpoints:

```
                                      predicted    simulated     error
  Vctrl = 0.0   (C_var = V_min):      5.42408 GHz  5.41854 GHz   +0.102 %
  Vctrl = 3.3   (C_var = V_max):      4.61916 GHz  4.62260 GHz   -0.074 %
  fractional range:                   17.43 %      17.22 %
```

**Both endpoints to better than 0.2 %** — the closed form and the transient now
agree, which they did not when L was treated as constant. So the mechanism of the
tuning range is, stated correctly:

- `C_var(V)` supplies a 1.877× small-signal capacitance ratio, traversed
  essentially without large-signal compression (98.9 % above);
- but `L_diff` is **not** constant across that traverse — it rises 12.7 % from the
  bottom of the band to the top, toward the 9.42 GHz self-resonance (table above).
  Because the larger L sits at the *high*-frequency end, it pulls that endpoint
  back down and so **compresses** the achievable range. This is the whole
  discrepancy: a constant-L closed form,
  `sqrt((F+V_max)/(F+V_min))` at F = 25.71 fF, gives 1.2474 → **24.74 %**, while
  solving `L_diff(f)` self-consistently gives 17.43 %, which the transient
  confirms at 17.22 %.

The last point is the correction that matters. A constant-L reading has to
attribute the whole 24.7 % → 17.2 % gap to something in the *capacitor*, and the
only available candidate is large-signal dC compression — which is exactly the
fictitious term an earlier revision of this README invoked (see finding 2). The
gap is the inductor's L(f), and the varactor's dC is essentially uncompressed.

Both the predicted 17.43 % and the simulated 17.22 % clear row 2's ≥ 15 % target.
**Neither clears the ≥ 20 % stretch** — reported, not papered over. The honest
diagnosis: 32 `mos_small` cells against a 25.7 fF fixed floor would buy 24.7 % if
`L_diff` were flat, and L(f)'s 12.7 % rise across the band spends most of that
margin. Closing the gap therefore needs either more varactor or less `F` (both
row-5 Q trades), or an inductor whose L(f) is flatter across the band — i.e. one
further from its SRF, which at a validated geometry means `p11` is already the
best of the three. None of that is a different reading of these numbers.

### Row 5 — loaded tank Q ≥ 6 at 5.0 GHz, counting every element as drawn

Summed parallel loss conductances at 5.0 GHz band centre, with
L_diff = 11.4478 nH and Q_L = 10.7019 (the EM-fitted `p11` subckt at 5.0 GHz).
C_tot = 1/(w²L_diff) = 88.51 fF, so the varactor sits at
C_var = 88.51 − 25.71 = 62.80 fF, i.e. 7.850 fF/cell, i.e. `vctrl_v` ≈ 0.506 V
in the record's axis = **V_GB ≈ −0.506 V**, where the record gives Q_var ≈ 60.3:

```
w·L_diff = 359.64 ohm
G_L   = 1/(Q_L · w·L_diff) = 1/(10.7019 × 359.64) = 0.2598  mS
G_var = w · C_var / Q_var                         = 0.0327  mS
G_mim = w · C_mim / Q_mim                         = 0.000023 mS  (model Q = 28 138: a 55 mohm series R)
G_tank                                            = 0.2926  mS
Q_loaded = 1/(G_tank · w·L_diff)                  = 9.50
```

**Q_loaded ≈ 9.5 ≥ 6 (target) and ≥ 8 (stretch)**, at the nominal corner. Redone
with the raw EM columns (`l_em` = 5.69836 nH, `q_em` = 10.2804) instead of the
fitted subckt's own, the same sum gives **Q_loaded ≈ 9.2** — the spread between
the two is the record's own ΔQ fit residual, and the verdict is the same under
either. The 9.2 figure is the one directly comparable to `spec/target-spec.md`
row 1, whose ratification text quotes `p11`'s `q_em` (10.28 @ 5 GHz); 9.5 is the
one consistent with the frequencies simulated above, since both come from the
fitted subckt the netlist instantiates. Both land close to DR-003's own
illustrative ≈ 8.8 basis, which is a useful cross-check that this sizing is the
one the row was ratified around.

Recomputed self-consistently at each band edge — L_diff, Q_L, C_var and Q_var all
taken at that edge's own frequency rather than at band centre — the range is
Q_loaded ≈ 9.31 at the low end (4.62260 GHz, C_var = V_max, Q_var = 44.79) and
≈ 9.45 at the high end (5.41854 GHz, C_var = V_min, Q_var = 84.92), so the whole
tuning range clears the stretch bound nominally.

This is row 5's **named constraint** honoured: the tuning capacitance is
realized as 32 parallel *small-geometry* (`mos_small`) cells, whose Q is 44.8 at
5 GHz at V_GB = 0 — not a `mos_mid`-class bank, whose Q of 2.73 would load the
tank to ≈ 2.8 and miss the row outright. (The "preserved under parallelism"
evidence DR-003 cites is `mos_large` vs `mos_xlarge` — the latter is 4×
`mos_large` in parallel and has *identical* Q. The 44.8 figure itself is
`mos_small`'s.)

**Three stated limits on that number.** (a) Nominal corner only; row 5 demands
it over the row-10 corner set, which is a `sim/` testbench's job, not this
directory's. (b) `cap_cmim`'s model carries *no* plate-to-substrate parasitic
and no feed loss — the PDK's own comment in `capacitors_mod.lib` says extraction
adds them — so the MIM's real contribution to both C and G is larger than
modelled. The verdict is insensitive to it, though: forcing the MIM's Q down to
20 still leaves Q_loaded = 8.6 — clear of the ≥ 6 target, and still (narrowly)
clear of the ≥ 8 stretch. (c) The HBT pair's own r_b-through-C_bc loading
is **not** in the sum; no recorded Q exists for it, and it is not bounded here.

### Row 6 — startup margin ≥ 3.0, and row 8 — ≤ 10 mW core

From the elaboration run's operating point: V(TE) = 0.40811 V across
RTE = 2 kohm, so I_tail = 204.1 µA and I_C = 102.0 µA per HBT. At 27 °C
(V_T = 25.87 mV) that is **g_m = 3.945 mS** per device, and a cross-coupled pair
presents G_neg = g_m/2 = **1.972 mS** differentially:

```
margin = G_neg / G_tank = 1.972 / 0.2926 =  6.7
      (= g_m   / G_tank = 3.945 / 0.2926 = 13.5 under DR-003's own illustrative
         convention, "G_loss ~ 1.0 mS -> the pair owes ~ 3 mS")
```

`G_tank` = 0.2926 mS is row 5's band-centre sum above, so this margin inherits
the EM-fitted L/Q sourcing and every limit stated there. At the band edges, where
`G_tank` is 0.3406 mS (low end) and 0.2540 mS (high end), the same G_neg gives
margin 5.8 and 7.8 respectively — the worst case over the range is the low end,
and it still clears ≥ 3.0 by ≈ 1.9×.

Either reading clears row 6's ≥ 3.0 at the nominal corner — which is *not* what
row 6 asks for (it asks at every row-10 bound corner); that is a later
testbench's verdict. The transient corroborates it directly: the oscillation
grows out of a 10 mV differential initial condition and sustains 1.10 V
peak-to-peak differential for the 53 counted cycles of the measurement window.

Row 8: the large-signal mean supply current over the 10–20 ns window is
306.6 µA, i.e. **P_core = 1.012 mW** — of which 0.673 mW is the oscillator pair
and 0.339 mW the `RREF`/Q4/`RRE` bias branch. That clears the ≤ 10 mW target and
the ≤ 5 mW stretch by a wide margin at nominal rail and 27 °C. It is a
single-corner number from a startup transient, not a graded row-8 result.

## What `run_elaborate.sh` checks, and how to read it

```bash
source sim/env.sh        # optional; the script sources it itself
design/run_elaborate.sh
```

Exit status is 0 only if **all** of: the committed netlist matches the
schematic; ngspice reports zero unknown-subckt / unknown-model / "could not find
a valid modelname" errors; and every one of the three `Vctrl` points produced a
countable oscillation.

**Frequency method, stated because a number without its method is not a
result.** Transient, 20 ns, maximum timestep 2 ps (≥ 100 points per period at
5 GHz), from a 10 mV differential `.ic`. Frequency is a **period count**: rising
crossings of the in-window mean of v(OUTP) − v(OUTN) over the **10–20 ns window
only** (so the startup ramp is excluded), elapsed span divided by the count.
This is not a spectral estimate; it states no phase noise and no line width, and
it is not a substitute for row 4's method. Its resolution is bounded by the 2 ps
step and linear interpolation between samples, ≈ ±0.05 % over the 45–53 cycles
counted. Single nominal corner, single run — no variance is estimated.

**Differential-mode check.** The script also reports Vpp_cm/Vpp_diff,
f_cm/f_diff and f_tail/f_diff. A genuinely differential tank puts the entire
fundamental into the differential mode and leaves the common mode and the tail
node with only the second harmonic the two half-circuits pump in phase; two
independently-resonating branches would instead show a *fundamental* in the
common mode. Measured: Vpp_cm/Vpp_diff = 0.003–0.008 and f_cm/f_diff =
f_tail/f_diff = **2.000** at all three `Vctrl` points — one differential
resonator, with TAIL behaving as a virtual ground at the fundamental.

### Result as of this schematic (ngspice-46, IHP-Open-PDK v0.3.0, nominal corner)

| Vctrl (V) | f_osc (GHz) | Vpp_diff (V) | P_core (mW) |
|---|---|---|---|
| 0.0 | 5.41854 | 1.1000 | 1.0119 |
| 1.65 | 5.38416 | 1.0870 | 1.0119 |
| 3.3 | 4.62260 | 0.8093 | 1.0117 |

Fractional tuning range 17.22 %; geometric band centre 5.0048 GHz; both
endpoints inside the row-1 4.5–5.5 GHz window.

## Reportable findings (not fixed by relaxing anything)

1. **Kvco is strongly non-linear over the `Vctrl` domain.** 5.4185 → 5.3842 GHz
   over the *lower* half of the range (0 → 1.65 V), and 5.3842 → 4.6226 GHz over
   the upper half: roughly 96 % of the tuning lives in the top half. This is a
   direct consequence of the varactor-polarity constraint above — the tank node
   is pinned at 3.3 V by the inductor, so the C(V) transition, which sits near
   V_GB ≈ 0, lands at the very top of the `Vctrl` range instead of at its centre.
   `spec/target-spec.md` row 3 (Kvco and its linearity) is **OPEN** per DR-003,
   so nothing here is out of spec; it is recorded so the eventual row-3 record
   starts from measured behaviour. Re-centring it would need the tank's DC bias
   moved off the rail (supply-feed resistors, or a centre-tapped inductor the
   EM-fitted model has no validated geometry for) — a topology change, not a
   sizing tweak.
2. **The ≥ 20 % stretch on row 2 is not met** (17.22 % simulated, 17.43 %
   predicted), and the cause is **the inductor's L(f), not large-signal dC
   compression.** The EM-fitted `p11` subckt's effective L rises 12.7 % from the
   bottom of the band to the top as it climbs toward its 9.42 GHz self-resonance,
   and because the larger L sits at the high-frequency endpoint it pulls that
   endpoint down and compresses the range: a flat-L closed form would predict
   24.74 %, and solving `L_diff(f)` self-consistently gives 17.43 %, which the
   transient confirms at 17.22 % (both endpoints to better than 0.2 %). The
   varactor's *effective* large-signal dC is 98.9 % of its small-signal value —
   essentially uncompressed — so there is no hidden capacitive loss to recover.
   Closing the gap needs more varactor or a smaller `F` (both row-5 Q trades), or
   an inductor further from its SRF; among the three validated geometries `p11` is
   already the best on that axis.

   *Method note, because this finding was previously stated wrongly.* An earlier
   revision of this README sourced L/Q from the **analytic** screening model
   (`sim/inductor-model/records/20260910-052743-3896421.csv`) while the netlist
   instantiates the **EM-fitted** one, and in doing so treated `L_diff` as a
   constant 10.4807 nH. That produced two endpoint estimates of `F` disagreeing
   by 8.3 fF, which was then attributed to 78.8 % large-signal dC compression.
   Both the disagreement and the compression were artifacts of the wrong (and
   constant) inductance, not physical effects: with the correct `L_diff(f)` the two
   `F` estimates agree to 0.4 fF. There is no 78.8 % compression, and no 22.5 %
   small-signal prediction — the number that needed explaining was always L(f).
3. **The fixed capacitor is `cap_cmim`, not `cap_rfcmim`.** `cap_rfcmim`'s model
   states its own valid range as *"7um to 75um"* for w and l, and the PCell
   floors at the same value (`rfcmim_minLW = 7u` in
   `libs.tech/klayout/python/sg13g2_pycell_lib/sg13g2_tech.json`). At 7 × 7 µm
   that is ≈ 74 fF — essentially this tank's entire row-2 fixed-C budget of
   76.9 fF on its own, and over it once the ≈ 5 fF of measured parasitics are
   counted, and 3.6× the 20.6 fF the band centring actually needs. No drawable
   `cap_rfcmim` fits here at all.
   `cap_cmim` floors at `cmim_minLW = 1.14u`, so 3.65 × 3.65 µm is a legal,
   drawable geometry. The cost is model fidelity, stated under row 5's limit
   (b). Both devices are characterized in `sim/tank-characterization/`, at
   20/35/50 µm — well above this geometry, which is itself an extrapolation of
   the areal model.
4. **No PVT.** Every number here is `tt`/`hbt_typ`/`cap_typ` at 27 °C on a
   nominal rail. Rows 5, 6 and 10 all demand corner coverage; supplying it is a
   `sim/` testbench issue, deliberately out of this schematic's scope.
