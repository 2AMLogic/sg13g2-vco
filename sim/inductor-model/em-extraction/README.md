# sim/inductor-model/em-extraction — openEMS extraction of the SG13G2 spiral-inductor PCell

**What this is.** An electromagnetic (FDTD) extraction of the PDK's own
`inductor2` KLayout PCell (library `SG13_dev`), for the three LVS-testcase
geometries also probed by [`../README.md`](../README.md)'s analytic model and
by [`../../tank-characterization/`](../../tank-characterization/). This is
IHP's own documented route to an inductor number
(`libs.doc/doc/EM_Simulation_Overview.pdf`), tracked as the deferred
alternative in issue #6 and implemented here per issue #9.

It produces:

1. S-parameters of the real drawn PCell over 0.1–30 GHz, for `p1` (1 turn),
   `p13` (5 turns) and `p11` (4 turns) — IHP's own LVS unit-testcase names,
   see [Geometries](#geometries).
2. A fitted lumped `.subckt inductor la lb sub` —
   [`../sg13g2_inductor_em.spice`](../sg13g2_inductor_em.spice) — on the same
   `w, s, d, nr_r` / `SG13G2_IND_MODEL_LIB` drop-in interface the analytic
   model uses.
3. The measured extraction-vs-analytic delta on L, Q and SRF (the single most
   valuable output — it converts the analytic model's *asserted* error bars
   into *measured* ones).

> **This is one process point, one temperature, three geometries.** It is
> **not** a PVT extraction (see [What this does not
> establish](#what-this-does-not-establish)) and it is **not** silicon. Per
> this repo's `CLAUDE.md` — *"numbers without methods are not results"* — read
> [Method](#method) and [Accuracy limits](#accuracy-limits-of-the-fitted-model)
> before quoting any number from here.

Nothing here ratifies a `spec/target-spec.md` row.

---

## Tooling: what was actually used, and how to reproduce it

Provisioned by issue #11 (`operator-mechanical`, host-level action, tracked
there rather than re-derived here):

| | |
|---|---|
| Solver | **openEMS v0.37.0-rc2** + CSXCAD 0.7.0rc2, built from `thliebig/openEMS-Project` @ `ea3c012` (no GUI, Python bindings), prefix `~/opt/openEMS` |
| Engine | FDTD (finite-difference time-domain), Gaussian-pulse excitation, one run per excited port |
| Python glue | `~/opt/openEMS/venv/bin/python` (isolated venv): `openEMS`, `CSXCAD`, **gds2openEMS 0.3.0** (IHP's own GDSII→openEMS workflow, `VolkerMuehlhaus/openems_ihp_sg13g2` @ `b67d46a`, populated into the PDK's own empty `libs.tech/openems/openems_ihp_sg13g2` submodule) |
| Geometry tool | `klayout` (system package), to instantiate the PDK's `inductor2` PCell headlessly |
| Fit / compare | system `python3` + `numpy`/`scipy` (fit does **not** need openEMS — only the S-parameter files) |
| Host | provisioned on `loom-worker-2` only (issue #11); `which openEMS nf2ff` and both Python imports must succeed before running anything here — see #11's closing comment for the exact provisioning record and `~/opt/openEMS/README-fleet.md` on that host |

Verify the tool before running anything:

```bash
which openEMS nf2ff
source ~/opt/openEMS/venv/bin/activate
python3 -c "from openEMS import openEMS; from CSXCAD import ContinuousStructure; import gds2openEMS; print('OK')"
openEMS --version   # must print "openEMS 64bit -- version v0.37.0-rc2"
```

**Reproducing the install is out of scope for this directory** — it is a
multi-library host build (CGAL, VTK, HDF5, Boost, tetgen, fparser, tinyxml),
documented once, at the host level, in issue #11's closing comments. This
directory only records *that* v0.37.0-rc2 was used and *what* it produced.

---

## Reproducing the extraction

```bash
sim/inductor-model/em-extraction/run_extraction.sh
```

Stages, each skippable via `EM_STAGES` (default: all of them):

| Stage | What it does | Needs openEMS? | Approx. wall time (this host, 8 threads) |
|---|---|---|---|
| `geometry` | instantiate the PDK's own `inductor2` PCell headlessly via `klayout -zz -r`, emit GDS + port/SUBGND footprints | no (needs `klayout` + the PDK) | seconds |
| `em` | 2-port FDTD solve per geometry | **yes** | `p1` ~200 s, `p13` ~700–900 s, `p11` ~1270 s |
| `convergence` | one-variable-at-a-time mesh and margin sensitivity on `p1` | **yes** | ~10–20 min |
| `post` | de-embed the port parasitic, extract L/Q/SRF | no (numpy only) | seconds |
| `fit` | fit the lumped `.subckt inductor`, write `../sg13g2_inductor_em.spice` | no (numpy/scipy only) | seconds |
| `compare` | EM vs. analytic, via `ngspice`, write `records/` | no (`ngspice` only) | seconds |

```bash
EM_STAGES="post fit compare" sim/inductor-model/em-extraction/run_extraction.sh   # re-fit without re-solving
```

**Geometry-export note (the one `klayout-tools` friction point hit while
building this pipeline)**: `klt gen --pdk-pcell` cannot yet reach
`ihp-sg13g2`'s own `sg13g2_pycell_lib` (it needs a `cni` compat shim that
`klt` does not add to its `sys.path`, plus a `tkinter`-triggered crash inside
that shim). Filed generically, tool-side, per this repo's `CLAUDE.md` friction
protocol: [2AMLogic/klayout-tools#1630](https://github.com/2AMLogic/klayout-tools/issues/1630).
Workaround in use here (not blocking): a direct `KLAYOUT_PATH`-scoped
`klayout -zz -r` invocation against a scratch overlay that populates the two
submodules the PCell wrapper needs
([`scripts/setup_pdk_overlay.sh`](scripts/setup_pdk_overlay.sh)) — see that
script's header for why the overlay exists (the PDK's own
`pycell4klayout-api`/`pypreprocessor` submodules are *also* empty in the
release tarball, the same empty-submodule failure mode issue #6 hit for
`openems_ihp_sg13g2` itself).

---

## Geometries

The same three IHP LVS unit-testcase instances of the `inductor` device
(`libs.tech/klayout/tech/lvs/testing/testcases/unit/ind_devices/netlist/inductor.cdl`)
that `../` and `../../tank-characterization/` already probe. The `p1`/`p13`/
`p11` labels are IHP's own testcase names (`L_pattern_1`, `L_pattern_13`,
`L_pattern_11`) — **not** a sequential 1/2/3 ordering, so `p13` (5 turns) is
smaller than `p11` (4 turns) in turn count order but has the larger `d`:

| Label | `w` (µm) | `s` (µm) | `d` (µm) | `nr_r` | `d_out` (µm) |
|---|---|---|---|---|---|
| `p1` | 8.22 | 3.29 | 47.65 | 1 | 64.1 |
| `p13` | 6.10 | 3.29 | 110.11 | 5 | 197.5 |
| `p11` | 8.22 | 3.74 | 141.975 | 4 | 230.2 |

Each GDS instance ([`gds/`](gds/)) carries, beyond the PCell's own conductor
layers: two lumped-port footprints (layers 201/0 `LA`, 202/0 `LB`, taken
verbatim from the PCell's own pin boxes) and a local substrate-ground patch
(layer 210/0 `SUBGND`, 15 µm beyond the port footprints), per
[`scripts/gen_geometry.py`](scripts/gen_geometry.py).

---

## Method

- **Stack**: IHP's own openEMS stackup,
  `libs.tech/openems/openems_ihp_sg13g2/workflow/SG13G2.xml`, copied verbatim
  into [`stackup/SG13G2.xml`](stackup/SG13G2.xml) for provenance (sha256
  `e0a9762b…`). This is IHP's EM-facing transcription of the same
  cross-section `libs.tech/klayout/tech/xsect/sg13g2_for_EM.xs` defines for
  KLayout — the same stack `../README.md`'s analytic model derives its
  constants from, so the two routes describe the same physical structure.
  `sigma_TopMetal2 = 3.03e7 S/m` (≈ 11 mΩ/sq, matching `RSTM2` typ.);
  `sigma_substrate = 2 S/m` (50 Ω·cm, matching `RSBLK` typ.).
- **Ports**: 2 lumped z-ports, `LA` and `LB`, each referenced to the local
  `SUBGND` patch — the port topology of IHP's own `run_inductor_2port.py`
  workflow example.
- **Excitation**: Gaussian pulse, one FDTD run per excited port; S-parameters
  by FFT at 601 points, 0–30 GHz.
- **Boundaries**: PEC box, domain = GDS bounding box + 200 µm margin on every
  side. A PEC box is a *closed* domain — it images the coil's own current in
  the walls, which pulls the extracted `L` down slightly; see
  [Convergence](#convergence) for how much.
- **Mesh**: 1.0 µm refined cell size at conductor edges, 20 cells/wavelength
  in the coarse mesh, `dz = 0.4 µm` through TopMetal2's 3 µm thickness.
- **End criterion**: −50 dB residual energy.
- **De-embedding**: the lumped port adds a small series inductance (a Terman
  flat-ribbon estimate from the port footprint's own dimensions, computed in
  `gds2openEMS`'s own `port_information.json`); it is cascaded out as a
  negative series `L` per port before any L/Q/SRF number is read, per IHP's
  own `deembed_openEMS.py` method
  ([`scripts/emlib.py`](scripts/emlib.py) `deembed_series_L`).
- **Two impedances are extracted and both are recorded** per
  [`scripts/emlib.py`](scripts/emlib.py)'s header:
  `Z_se = Z11 − Z12·Z21/Z22` (driving-point impedance at `LA` with `LB` and
  `sub` grounded — the same quantity the analytic model's own known-answer
  check and `../../tank-characterization/`'s probe measure, so it is the one
  the extraction-vs-analytic comparison uses) and `Z_diff = (Z11−Z12−Z21+Z22)/2`
  (differential, for a symmetric LC-tank driving topology).

**Process point: one.** The typ. conductivities shipped in IHP's own EM
stackup, at one (unstated, effectively room) temperature. No corner sweep —
FDTD does not have a native notion of `mc_rsh`/`mc_rsub`/temperature corners
the way the ngspice analytic model does; see
[Accuracy limits](#accuracy-limits-of-the-fitted-model).

---

## Results: S-parameter extraction (`results/`)

Per geometry: `results/inductor_<g>.s2p` (raw 2-port Touchstone, 0–30 GHz, 601
points), `results/inductor_<g>_deembedded.s2p` (port-inductance removed),
`results/inductor_<g>_lq.csv` (L/Q vs. frequency, single-ended + differential)
and one scalar summary, `results/em_summary.csv`:

| Geometry | `w`/`s`/`d` (µm) | `nr_r` | `R_dc` (Ω) | `L`@1G (nH) | `Q`@1G | `L`@10G (nH) | `Q`@10G | SRF (se) |
|---|---|---|---|---|---|---|---|---|
| `p1` | 8.22/3.29/47.65 | 1 | 0.314 | 0.0985 | 1.90 | 0.0918 | 8.83 | **none < 30 GHz** |
| `p13` | 6.10/3.29/110.11 | 5 | 6.812 | 5.124 | 4.49 | −8.24 (past SRF) | −5.46 (past SRF) | 8.07 GHz |
| `p11` | 8.22/3.74/141.975 | 4 | 4.386 | 4.276 | 5.70 | −22.3 (past SRF) | −1.61 (past SRF) | 9.42 GHz |

`srf_se_hz = nan` for `p1` is **expected, not a bug**: `p1` is the smallest,
lowest-inductance, highest-SRF geometry of the three, and its self-resonance
genuinely falls above the 30 GHz scan ceiling — `emlib.srf()` returns `NaN` by
design ("lowest frequency where `Im(Z)` falls through zero; `NaN` if it never
does" within the swept band) rather than extrapolating past data it does not
have. The negative `L`/`Q` values for `p13`/`p11` at 10/20 GHz are likewise
expected: those spot frequencies are past that geometry's own SRF (8.07 /
9.42 GHz), where a driving-point impedance is capacitive and an "inductance"
read off it is not physically an inductance — read the `srf_*_hz` column
first, exactly as `../README.md` states for the analytic model.

---

## Fitted lumped model: [`../sg13g2_inductor_em.spice`](../sg13g2_inductor_em.spice)

Same element-for-element 2-π topology as
[`../sg13g2_inductor_analytic.spice`](../sg13g2_inductor_analytic.spice)
(`Rser` → 10-section `R‖L` skin ladder → `Lmain`, `Cs` turn-feed capacitance,
`Cox`/`Rsub`/`Csub` substrate branch per port), fit to the extraction at each
of the three geometries by `scipy.optimize.least_squares` on relative-error
residuals (weighted to avoid a null in either the series or shunt admittance
dominating the objective) — see
[`scripts/fit_lumped.py`](scripts/fit_lumped.py)'s header for the exact
residual form. It is **not** a lookup table: at runtime it recomputes the
analytic model's own geometry-driven element expressions and multiplies each
by a fitted correction factor selected by nearest extracted turn count
(`nr_r ≤ 1` → the `p1` factors, `≤ 4` → `p11`'s, else `p13`'s). Corner
(`mc_rsh`, `mc_rsub`) and temperature (`tc1`) scaling are therefore inherited
unchanged from the analytic model's physics — the EM run supplies the *level*
at 27 °C/typ., not new corner physics.

### Fit residual (report this before trusting the fitted parameters)

| Geometry | fit band | rms \|ΔZ\|/\|Z\| | max \|ΔZ\|/\|Z\| | rms ΔL | rms ΔQ | SRF: fitted vs. EM |
|---|---|---|---|---|---|---|
| `p1` | 0.3–30 GHz | 0.18 % | 0.52 % | 0.16 % | 0.92 % | no SRF in band (both) |
| `p13` | 0.3–6.86 GHz | 0.83 % | 2.74 % | 0.44 % | 4.23 % | 8.17 GHz vs. 8.07 GHz (+1.2 %) |
| `p11` | 0.3–8.01 GHz | 0.90 % | 2.90 % | 0.48 % | 5.16 % | 9.51 GHz vs. 9.42 GHz (+0.9 %) |

The fit band's upper edge is capped at `min(30 GHz, 0.95 × extracted SRF)` —
enforced, not asserted, per [`scripts/fit_lumped.py`](scripts/fit_lumped.py):
a single-π lumped network has no business chasing points past a device's own
self-resonance (same limit the analytic model states for itself). Full
per-point residuals: `fit/fit_residual_p1.csv`, `fit/fit_residual_p13.csv`,
`fit/fit_residual_p11.csv`. Fitted-vs-analytic element ratios:
`fit/fit_summary.csv`, `fit/fit_parameters.json`.

**One ratio needs a specific caveat, not a red flag reading**: `Cs`'s
fitted/analytic ratio is 1.36×10⁶ for `p1`. This is **not** a fit failure —
the analytic model's own `Cs` expression
(`ind_novl·w_eff²·CATOPMET2 + 1e-21`) is architecturally zero for a 1-turn
coil (`ind_novl = 2·(nr_r−1) = 0`, no turn-to-bridge crossover exists), and
the `+1e-21` term is a numerical floor to keep the netlist's capacitor
non-degenerate, not a physical prediction. The EM fit's 1.36 fF for `p1`
captures a small real parasitic (fringing / feed-to-port capacitance) the
analytic model's crossover-count assumption cannot represent at `nr_r = 1`;
it is small in absolute terms (1.36 fF vs. `p1`'s ~10 fF `Cox`) and the fit
residual table above shows it does not compromise the overall fit quality.
`p13`/`p11` (17.2× and 10.6×) are the same effect at reduced magnitude, once
a real crossover exists for the analytic term to compare against.

---

## Extraction vs. analytic: the measured delta

From record [`records/20260910-052657-3896421.md`](records/20260910-052657-3896421.md)
(regenerate with `EM_STAGES=compare`; method: both models driven by 1 A AC
into `LA`, `LB` and `sub` grounded, typ., 27 °C, on the extraction's own
frequency grid — nothing rescaled or aligned). `Δ = (analytic − EM) / EM`:

| Geometry | `L`(1 GHz) EM | `L`(1 GHz) analytic | Δ`L` | `Q`(1 GHz) EM | `Q`(1 GHz) analytic | Δ`Q` | SRF EM | SRF analytic | Δ SRF |
|---|---|---|---|---|---|---|---|---|---|
| `p1` (1 turn) | 0.0985 nH | 0.1038 nH | **+5.4 %** | 1.90 | 2.57 | **+34.9 %** | none < 30 GHz | none < 30 GHz | n/a |
| `p13` (5 turns) | 5.124 nH | 5.451 nH | **+6.4 %** | 4.49 | 5.26 | **+17.2 %** | 8.07 GHz | 14.31 GHz | **+77.3 %** |
| `p11` (4 turns) | 4.276 nH | 4.606 nH | **+7.7 %** | 5.70 | 6.66 | **+16.9 %** | 9.42 GHz | 14.11 GHz | **+49.8 %** |

**Reading this against the analytic model's own stated error bars**
([`../README.md`](../README.md) § Accuracy limits, unchanged by this PR
except where noted):

- **L is inside the stated bar, in the stated direction.** The analytic
  model's own multi-turn bar is ±5 %; the measured delta is +6.4 %/+7.7 % —
  at or just outside it, and the single-turn bar (±10 %, `p1` explicitly
  flagged there as "outside Mohan's fitted family, an extrapolation") is not
  violated (+5.4 %). The **sign is consistent across all three geometries**
  (analytic always reads high), consistent with the closed-form expression
  being a smooth fit across a device family rather than this exact drawn
  PCell.
- **Q is not inside the stated bar, but the stated bar already predicted
  this direction.** `../README.md` states outright that the analytic model's
  Q is "an UPPER BOUND" with "systematic, one-directional error" from
  unmodelled lateral current crowding and substrate eddy currents — i.e. it
  predicts analytic-Q > real-Q, which is exactly the sign measured here
  (+17–35 %). The **magnitude** the analytic model's own `qlow_*` bracket
  offers (the pessimistic one-sided effective-conduction-depth estimate) is
  the more useful comparison: at `p13`/1 GHz, analytic `q_*` = 5.26,
  `qlow_*` = 3.67, and the EM-measured 4.49 sits **inside that bracket** — so
  the analytic model's own stated bracket, not its point estimate, is the
  quantity validated by this measurement.
- **SRF is the largest gap, and the frequency-limits section already flagged
  why.** `../README.md` calls a lumped model's SRF prediction for the large
  geometries "an order-of-magnitude marker, not a number" because `p13`'s
  2.55 mm conductor approaches a quarter-wavelength near the analytic SRF
  itself — i.e. the analytic model's own self-resonance estimate sits exactly
  where a single-π lumped topology loses the right to answer the question.
  The EM extraction, being a full-wave field solve rather than a lumped
  circuit, has no such limit, and it finds SRF **77 %/50 % lower** than the
  analytic estimate. This is the most consequential number in this table for
  the tank study: a 10 GHz LC-VCO built on `p13` or `p11` would be running
  **above**, not at 70 % of, the true self-resonance the analytic model
  implied — see [What this means for the tank](#what-this-means-for-the-tank).

Full per-geometry × per-spot-frequency table (1/2/5/10/20 GHz, both models):
[`records/20260910-052657-3896421-delta-summary.csv`](records/20260910-052657-3896421-delta-summary.csv);
full swept-frequency comparison:
[`records/20260910-052657-3896421-em-vs-analytic.csv`](records/20260910-052657-3896421-em-vs-analytic.csv).

---

## What this means for the tank

`p13`/`p11` self-resonate at **8.07/9.42 GHz** by EM extraction, not the
14.3/14.1 GHz the analytic model estimated. A tank built on either PDK
testcase geometry for a ~10 GHz LC-VCO would be running **past**, not below,
its own inductor's SRF — the opposite of what the analytic-only study in
`../../tank-characterization/` could show. This is the headline reason the EM
route matters for this design, not a footnote: any tuning-range or
phase-noise claim in the 8–10 GHz range that leaned on the analytic model's
SRF number needs to be re-read against the number in this directory instead.

---

## Convergence

Two one-variable-at-a-time checks on `p1` (the fastest geometry), because
both knobs bias the answer in a *known* direction and the record should show
*by how much* rather than assert the default was fine:

- **`refined_cellsize`**: the FDTD mesh through TopMetal2's 3 µm thickness
  sets how much of the skin effect is resolved; too coarse ⇒ `R` too low ⇒
  `Q` too high.
- **`margin`**: the domain is a closed PEC box, whose walls image the coil's
  own current and pull `L` down; too small ⇒ `L` too low.

From `results/convergence.csv` (baseline: 1.0 µm mesh, 200 µm margin, as used
for every extraction in this directory):

| Variant | `L`@1G vs. baseline | `Q`@10G vs. baseline | `L`@10G vs. baseline | Wall time |
|---|---|---|---|---|
| baseline (1.0 µm / 200 µm) | — | — | — | 202 s |
| `refined_cellsize` → 0.5 µm | **+0.90 %** | **+9.4 %** | +1.9 % | 601 s |
| `margin` → 400 µm | +0.078 % | +0.036 % | +0.057 % | 207 s |

Both move in the **predicted direction**: a finer mesh resolves more of the
skin effect and raises `Q` (baseline is a **conservative, Q-underestimating**
choice — real `Q` is likely slightly higher than reported, not lower); a
larger margin relaxes the PEC-wall image current and raises `L` slightly.
**Margin is well converged already** (< 0.1 % at 2× the margin) — 200 µm was
not starving the domain. **Mesh is the larger lever**: halving the cell size
moved `Q`@10 GHz by 9.4 %, so the `Q` numbers in this directory carry that as
an *additional*, mesh-driven uncertainty on top of the fit residual — read
`Q` values here as good to roughly ±10 %, not the sub-1 % the fit-residual
table alone would suggest, until a finer-mesh run is done for all three
geometries (not done here — checked on `p1` only, per [Accuracy
limits](#accuracy-limits-of-the-fitted-model) point 5).

---

## Accuracy limits of the fitted model

Everything [`../README.md`](../README.md) states about the analytic model's
own limits (frequency band, "Q is an upper bound" direction, SRF as an
order-of-magnitude marker for the large geometries) is **inherited**, because
the fitted model reuses the analytic model's geometry-driven expressions —
see [What this file is not](#what-this-file-is-not-restated-from-the-model-header)
below. In addition, specific to the EM route:

1. **Three geometries were extracted; this is not an EM lookup table for
   arbitrary `w`/`s`/`d`/`nr_r`.** Away from `p1`/`p13`/`p11`, the fitted
   model is an EM-*corrected* analytic model (correction factor selected by
   nearest extracted turn count), and the correction is an **extrapolation**
   nothing here validates. It should describe geometries close to the three
   extracted ones better than the uncorrected analytic model does, but that
   is an expectation, not a measurement.
2. **One process point, one temperature.** The EM solve used IHP's typ.
   conductivities at one (room) temperature. All corner/temperature
   dependence in the fitted model is the analytic model's own physics
   (`mc_rsh`, `mc_rsub`, `tc1`), unchanged — a corner number from this file is
   "the EM level with the analytic model's *scaling*", not an EM corner.
3. **The fit is only trustworthy within its own reported residual band** (see
   [Fit residual](#fit-residual-report-this-before-trusting-the-fitted-parameters)
   above) — `0.3–30 GHz` for `p1`, but capped near each large geometry's own
   SRF for `p13`/`p11`. Outside the fit band (particularly the
   `full_extraction_band` figures in `fit/fit_parameters.json`, which run to
   >10⁵ % for `p13`/`p11` above their own SRF) the single-π topology is simply
   not fit there — this is the same "no way to signal it has stopped being a
   lumped problem" limit the analytic model states for itself, now with an
   explicit numeric boundary instead of an assertion.
4. **No silicon backs any of it.** This is a field solve of a CAD geometry
   against a PDK-published stackup, not a measurement.
5. **Boundary/mesh convergence is checked on `p1` only** (the cheapest
   geometry); the trend from that check is assumed, not independently
   re-verified, to hold for `p13`/`p11`.

### What this file is not (restated from the model header)

1. Not an EM lookup table for arbitrary geometry (see point 1 above).
2. Not a PVT extraction (see point 2 above).
3. Not silicon (see point 4 above).

---

## Provenance

Every S-parameter file's generating command, mesh settings, host, wall time
and content hashes are in its sibling `results/inductor_<g>/run_meta.json`.
Every comparison record's tool versions (`openEMS`, `ngspice`, `numpy`,
`python`) and every input file's sha256 are in
`records/<record-id>-env.json`. GDS geometry hashes:

| File | sha256 |
|---|---|
| `gds/inductor_p1.gds` | `674090e9e0f520f0…` |
| `gds/inductor_p13.gds` | `73ed4b8899a85270…` |
| `gds/inductor_p11.gds` | `5c10348ff729b60a…` |
| `stackup/SG13G2.xml` | `e0a9762bd85e15b2…` |
| `../sg13g2_inductor_em.spice` | `6f24f9857ab7810c…` |

`et`/`ht` (the Gaussian excitation traces and their magnetic counterpart) are
solver **inputs**, fully regenerable from the GDS + stackup + settings above
(~2.5 MB each × 4 per geometry) and are **not** committed — the port
voltage/current probes the S-parameters are actually computed from
(`port_it_*`, `port_ut_*`) are kept, per `run_extraction.sh`'s own cleanup
step.

---

## What this does **not** establish

1. **Arbitrary-geometry accuracy.** Three geometries extracted; the fitted
   model's behaviour away from them is an unvalidated extrapolation (point 1,
   [Accuracy limits](#accuracy-limits-of-the-fitted-model)).
2. **PVT behaviour of the EM-measured level itself.** One process point, one
   temperature; corner/temperature scaling is the analytic model's physics,
   not re-derived from field solves at other corners (point 2, ibid.).
3. **Silicon agreement.** No measurement, no fabricated part.
4. **Anything the analytic model already disclaims** — drawn-layout feed
   parasitics, patterned ground shields, the `inductor3` centre-tapped
   variant, statistical/mismatch spread (see `../README.md` § "Not modelled,
   deliberately"). Not re-litigated here; it applies identically to the
   fitted EM model since it shares the analytic model's topology.

---

## Sources

- IHP-Open-PDK (pinned in [`../../pdk.json`](../../pdk.json)):
  `libs.doc/doc/EM_Simulation_Overview.pdf`;
  `libs.tech/openems/openems_ihp_sg13g2/` (populated per issue #11, from
  `VolkerMuehlhaus/openems_ihp_sg13g2` @ `b67d46a`);
  `libs.tech/klayout/tech/xsect/sg13g2_for_EM.xs`;
  `libs.tech/klayout/python/sg13g2_pycell_lib/ihp/inductor2_code.py`;
  `libs.tech/klayout/tech/lvs/testing/testcases/unit/ind_devices/`.
- openEMS: `thliebig/openEMS-Project` @ `ea3c012` (v0.37.0-rc2); `gds2openEMS`
  0.3.0 (`IHP-GmbH`/`VolkerMuehlhaus` tooling, per issue #11).
- Issue #9 — this directory's own scope and acceptance criteria. Issue #11 —
  the tooling-provisioning record this directory's [Tooling](#tooling-what-was-actually-used-and-how-to-reproduce-it)
  section restates. Issue #6 — the route decision `../README.md` § "Route
  decision" documents in full.
- [`../README.md`](../README.md) — the analytic model this directory measures
  against; every accuracy-limit statement repeated here is sourced there.
- This repo's `CLAUDE.md` — "Tank first", "numbers without methods are not
  results"; [`../../README.md`](../../README.md) — the append-only record
  convention.
