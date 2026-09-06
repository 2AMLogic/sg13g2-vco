# sim/tank-characterization — L / Q / SRF of the SG13G2 tank passives

**What this is.** The "Tank first" study this repo's `CLAUDE.md` requires
before anything is sized: *characterize the PDK's spiral-inductor and MIM-cap
models (L, Q, SRF across the band) before sizing the pair.*

**The headline result is half a study, and that is the result.**
IHP-Open-PDK v0.3.0 ships a fully simulatable MIM-capacitor model and **no
ngspice-simulatable spiral-inductor model at all**. The C half of the tank is
characterized here over the full PVT grid. The L half cannot be characterized
in this flow, by anyone, with this PDK release — see
[The inductor gap](#the-inductor-gap). That is recorded as evidence rather
than papered over with a hand-rolled inductance formula, because a number
this block's phase-noise and tuning-range claims would later lean on must not
be one an agent invented.

Nothing here ratifies a `spec/target-spec.md` row. Ratification is a separate
decision-record step; this directory only produces the evidence it would cite.

---

## Reproducing it

```bash
sim/tank-characterization/run_pvt_sweep.sh
```

That is the entire cold-start invocation — no arguments, no preceding build
step, no manual ngspice session. It takes about 15 s.

**Requirements**: `ngspice` on `PATH`, `bash`, and an IHP-Open-PDK **v0.3.0**
install (pinned with its tarball sha256 in [`../pdk.json`](../pdk.json);
fetchable with `klayout-tools`' `scripts/fetch-ihp-sg13g2.sh`). It does *not*
need xschem, klayout, `klt`, Python, or any compiled OSDI/Verilog-A model —
every device it touches is built from ngspice's native R/L/C primitives and a
`.model … C` card, which is why this experiment has no build step.

`../env.sh` resolves the install: `$PDK_ROOT`/`$PDK` if you export them,
otherwise the usual open_pdks prefixes (`/usr/share/pdk`,
`/usr/local/share/pdk`, `~/share/pdk`, `~/.ciel`, `~/.volare`). If it cannot
find one it says so and the sweep exits non-zero rather than running against
nothing.

```bash
export PDK_ROOT=/path/to/ihp-open-pdk   # only if it is somewhere unusual
export PDK=ihp-sg13g2
```

The run mints a fresh record ID (`<UTC timestamp>-<git short sha>`) and writes
**append-only** evidence under it — a re-run never rewrites an earlier record:

| Path | Contents |
|---|---|
| `netlist-snapshots/<record-id>/<corner-id>.spice` | the exact netlist simulated, placeholders already substituted |
| `corners/<record-id>/<corner-id>.log` | raw ngspice batch output for that point |
| `records/<record-id>-curves/<corner-id>.csv` | C(f), Q(f) and the reference L(f)/Q(f), 50 points/decade |
| `records/<record-id>.csv` | scalar summary, one row per corner × device instance |
| `records/<record-id>-method-check.csv` | known-answer check of the extraction arithmetic |
| `records/<record-id>-inductor.csv` | the inductor probe's outcome |
| `records/<record-id>.md` | the narrative record, including the PDK digests the run actually loaded |

`run_pvt_sweep.sh` exits non-zero if any simulation point fails or if the
known-answer check drifts past 0.1 %, so "it ran" and "it produced trustworthy
numbers" are not the same claim and the script distinguishes them.

---

## What was measured, and how

Each device under test hangs between a hot node and AC ground and is driven by
an **ideal 1 A AC current source injecting into the hot node**, so the node
voltage *is* the driving-point impedance: `V(node) = Z(f)`, ohms per amp. From
`Z(f)`:

| Quantity | Definition used |
|---|---|
| `Ceff(f)` | `Im(Y) / (2πf)`, with `Y = 1/Z` — the parallel-equivalent capacitance |
| `Q(f)` | `\|Im(Y)\| / Re(Y)` — identical to `\|Im Z\| / Re Z`, but better conditioned near SRF where `Re(Z)` blows up |
| `SRF` | the frequency at which `Im(Z)` crosses zero, i.e. where the device stops being net capacitive and turns inductive |
| `Leff(f)` | `Im(Z) / (2πf)` — used for the reference network and, when a model exists, for the inductor |

Scalars come from a **500 point/decade** pass (so the SRF zero-crossing is
interpolated on a fine grid); the committed curve files are a **50
point/decade** pass over the same range, purely to keep the repository small.

### The band swept, and why it is wide

**100 MHz … 300 GHz.** The target band for this block is *not chosen yet* —
`spec/target-spec.md` row 1 is blank, and choosing it is downstream of this
study. Narrowing the sweep to an assumed centre frequency would have made the
study circular. 300 GHz is roughly the fT neighbourhood of this process's
fastest HBT, so the sweep brackets every LC-VCO centre frequency this PDK could
plausibly support, from well below to well above.

### The PVT grid

| Axis | Points | Rationale |
|---|---|---|
| **P** (process) | `cap_typ`, `cap_bcs`, `cap_wcs` | the three non-statistical MIM sections in `cornerCAP.lib`; `bcs`/`wcs` scale `cap_carea` and `cap_cpara` by 0.9 / 1.1, i.e. ±10 % on MIM area capacitance |
| **V** (bias) | 0.0 V, 1.5 V | see [Bias dependence](#bias-dependence-measured-not-assumed) — swept to *measure* the claim that these models are bias-independent, not to assume it |
| **T** | −40, 27, 125 °C | the same span the sibling blocks in this catalog corner over |

= **18 simulation points**, each carrying **6 device instances** (2 models ×
3 geometries) = 108 device rows per record, plus the reference network
re-checked at all 18 points.

**Deliberately not run**: the `*_mismatch` and `*_stat` sections of
`cornerCAP.lib`. Those model device-to-device spread *within* one die and need
a Monte Carlo harness this study does not have. Named here rather than
silently skipped; it is the obvious follow-on once a tank topology exists to
apply it to.

### Devices and geometries

| Model | Geometries | Notes |
|---|---|---|
| `cap_cmim` | 20×20, 35×35, 50×50 µm | the **lumped** MIM model: one 55 mΩ series resistor plus an area+perimeter capacitance. No plate/feed inductance, no substrate network. |
| `cap_rfcmim` | 20×20 (wfeed 5 µm), 35×35 (wfeed 10 µm), 50×50 µm (wfeed 15 µm) | the **RF** MIM model: skin-effect R/L, plate + feed inductance, series plate resistance, and an oxide/substrate network (Cox, Csub, Rsub). |

All six are inside the validity window `capacitors_mod.lib` states for
`cap_rfcmim` itself: `w`, `l` ∈ [7 µm, 75 µm]; `wfeed` ∈ [1 µm, 30 µm] and
`wfeed ≤ w − 1.2 µm`.

### The method is validated, not just asserted

Every corner also carries an **ideal R-L-C reference network** (`R = 2 Ω`,
`L = 1 nH`, `C = 100 fF`) that is not a PDK device. Its `Leff`, `Q` and `SRF`
are known in closed form:

```
Zref(ω) = (R + jωL) / ((1 − ω²LC) + jωRC)
Leff(ω) = Im(Zref)/ω        Q(ω) = Im(Zref)/Re(Zref)
SRF     = sqrt((L − R²C) / (L²C)) / 2π
```

`run_pvt_sweep.sh` evaluates those independently (in `awk`) and **fails the
run** if the simulated values disagree by more than 0.1 %. On the committed
record the worst disagreement across all 18 corners is **0.0026 %** (on SRF,
which is the interpolated quantity; `Leff` and `Q` land within 0.0002 %).

This is what lets the *inductive*-branch extraction be trusted even though
this PDK ships no inductor to exercise it on: what is missing there is the
device model, not the method.

---

## Results

All figures below are from record `20260906-135025-d3410d1`, at `cap_typ`,
27 °C, `Vbias = 0 V`, and are reproducible by re-running the script. The full
grid is in that record's CSVs.

### 1. `cap_cmim` has no self-resonance and overstates Q by 5–12×

`cap_cmim` contains no inductance whatsoever, so `Im(Z)` never crosses zero:
its SRF is recorded as `none`, at every corner, by construction rather than by
a measurement miss. Its `Ceff` is flat with frequency and its `Q = 1/(ωRₛC)`
rises without bound as `f → 0`.

| Geometry | Q @ 1 GHz | Q @ 5 GHz | Q @ 10 GHz |
|---|---|---|---|
| 20 µm, `cap_cmim` | 4797 | 959 | 480 |
| 20 µm, `cap_rfcmim` | 857 | 160 | **67.6** |
| 35 µm, `cap_cmim` | 1570 | 314 | 157 |
| 35 µm, `cap_rfcmim` | 330 | 57.2 | **20.4** |
| 50 µm, `cap_cmim` | 770 | 154 | 77.0 |
| 50 µm, `cap_rfcmim` | 151 | 24.0 | **6.27** |

The optimism ratio runs 4.8× at 1 GHz to **12.3×** at 10 GHz for the largest
device.

> **Consequence for this block**: any tank, tuning-range or phase-noise claim
> built on `cap_cmim` is wrong by roughly an order of magnitude in tank Q, and
> silently has no self-resonance at all. `cap_rfcmim` is the only one of the
> two that can support an RF claim. This is a trap worth stating loudly because
> `cap_cmim` is the two-pin, simpler-looking, more obviously named device.

### 2. `cap_rfcmim`: bigger caps cost you Q *and* SRF

| Geometry | C @ 1 GHz | SRF | Q @ 1 GHz | Q @ 5 GHz | Q @ 10 GHz |
|---|---|---|---|---|---|
| 20×20 µm, wfeed 5 µm | 0.603 pF | **53.7 GHz** | 857 | 160 | 67.6 |
| 35×35 µm, wfeed 10 µm | 1.846 pF | **26.6 GHz** | 330 | 57.2 | 20.4 |
| 50×50 µm, wfeed 15 µm | 3.774 pF | **16.1 GHz** | 151 | 24.0 | 6.27 |

Both the Q roll-off and the SRF scale roughly as expected for a
distributed-plate MIM: SRF falls with area (more C against a plate inductance
that grows with `l`), and Q falls with both frequency and size.

> **Consequence for this block**: `Q_tank ≤ Q_C` always, so this table is a
> hard upper bound on tank Q from the capacitor alone, before the inductor is
> even considered. Two concrete bounds it puts on the design space: a 10 GHz
> tank using ≈3.8 pF of MIM cannot exceed `Q_tank = 6.3`; the same tank using
> ≈0.6 pF cannot exceed `Q_tank = 68`. **Small C / large L is strongly
> favoured** — which is precisely the trade the missing inductor model is
> needed to close.
>
> Note also that a 50×50 µm MIM's SRF (16.1 GHz) sits inside the plausible
> LC-VCO band for this process. Tank capacitance cannot be scaled up freely.

### 3. Temperature dependence is negligible

Over −40 … 125 °C at `cap_typ`, for the 35 µm `cap_rfcmim`:

| T | C @ 1 GHz | Q @ 1 GHz | Q @ 10 GHz | SRF |
|---|---|---|---|---|
| −40 °C | 1.8456 pF | 330.0 | 20.44 | 26.566 GHz |
| 27 °C | 1.8460 pF | 329.9 | 20.43 | 26.563 GHz |
| 125 °C | 1.8467 pF | 329.8 | 20.43 | 26.558 GHz |

That is **+0.06 % on C and −0.06 % on Q over a 165 °C span**, consistent with
`cmim_core`'s stated `TC1 = 3.6e-6`, `TC2 = 2e-9`. For a VCO, the MIM cap is
effectively *not* a temperature-drift contributor; whatever frequency drift
this block ends up with will come from somewhere else.

### 4. Process spread tracks the ±10 % `cap_carea` scaling

35 µm `cap_rfcmim`, 27 °C:

| Section | C @ 1 GHz | Q @ 1 GHz | Q @ 10 GHz | SRF |
|---|---|---|---|---|
| `cap_bcs` | 1.662 pF (−10.0 %) | 366.5 | 23.11 | 28.05 GHz (+5.6 %) |
| `cap_typ` | 1.846 pF | 329.9 | 20.43 | 26.56 GHz |
| `cap_wcs` | 2.030 pF (+10.0 %) | 300.0 | 18.25 | 25.28 GHz (−4.8 %) |

C moves with `cap_carea` exactly as the corner file defines it; Q moves ∓11 %
and SRF ±5 % (≈ `1/sqrt(C)`, as expected for a fixed parasitic inductance).

> **Consequence for this block**: MIM process spread alone contributes about
> **∓5 % on tank centre frequency** for a purely MIM-tuned tank. The tuning
> range eventually spec'd has to absorb that before any varactor range is
> allocated.

### Bias dependence, measured not assumed

`cmim_core` is declared as `.model cmim_core C (TC1=… TC2=… TNOM=27 CJ=… CJSW=…)`
— temperature coefficients but **no voltage coefficient** — so the model is
bias-independent by construction. Rather than assert that, the sweep carries a
`Vbias` axis. Across all 54 (corner × device) pairs the `C @ 1 GHz` values at
`Vbias = 0 V` and `Vbias = 1.5 V` are **identical to every digit ngspice
prints** (exactly 0 % difference).

> **Consequence for this block**: the MIM cap contributes **no** tuning
> mechanism and **no** AM-to-PM conversion path of its own. All tuning must
> come from the varactor or a switched bank — which makes the varactor
> selection (out of scope here, `spec/target-spec.md` row 2) the only tuning
> lever. It also means MIM-cap bias does not need to appear as an axis in any
> later tank testbench, which is a real saving in corner count.

### Band edges and model validity

`capacitors_mod.lib` states a **geometry** validity range for `cap_rfcmim`
(honoured above) and states **no frequency validity range at all**. The
model's `lplate/lfeed/lskin/cox/csub/rsub/rmim/rskin` coefficients are
polynomial fits, and the PDK does not document the band they were fitted over.
So:

- **Below SRF** the model behaves as a physical lossy MIM and the numbers in
  §1–§4 are the study's actual product.
- **Above SRF** `Ceff` goes *negative* — the device is net inductive. That is
  correct behaviour, and the curve files show it plainly (e.g. the 50 µm
  `cap_rfcmim` reads `C = −5.74 pF` at 20 GHz, above its 16.1 GHz SRF). The
  `Q` column above SRF is the parasitic inductance's Q, not a capacitor Q, and
  must not be read as one. **Cross-check the `srf_hz` column before using any
  `c_*`/`q_*` value at a higher frequency.**
- **The top decade (≈30–300 GHz) is swept but is not validated.** It is
  included so the record shows where the model stops being credible rather
  than stopping short of it and leaving the reader to guess. No claim in this
  README rests on a number above 20 GHz.

---

## The inductor gap

**IHP-Open-PDK v0.3.0 ships no ngspice-simulatable spiral-inductor model.**
This was established by search, not by assumption; `testbench/tb_inductor_zscan.spice.tmpl`
runs the probe anyway so the negative result lands in the evidence tree with a
raw log behind it (`corners/<record-id>/inductor_probe.log`):

```
Error: unknown subckt: xl_p1 lp1 0 0 inductor w=8.22u s=3.29u d=47.65u nr_r=1
```

What v0.3.0 *does* ship for the inductor, all of it layout- or LVS-side:

| Artifact | Path in the PDK |
|---|---|
| KLayout PCells | `libs.tech/klayout/python/sg13g2_pycell_lib/ihp/inductor{s,2,3}_code.py` |
| LVS rule decks | `libs.tech/klayout/tech/lvs/rule_decks/ind_{extraction,derivations,connections}.lvs` |
| LVS unit testcase | `libs.tech/klayout/tech/lvs/testing/testcases/unit/ind_devices/` (16 geometry patterns) |
| xschem symbols | `libs.tech/xschem/sg13g2_pr/inductor{,3}.sym` |
| Qucs-S symbol | `libs.tech/qucs-s/symbols/inductor_2.xml` |

and what it does **not** ship: any `.subckt inductor` or inductor `.model`
under `libs.tech/ngspice/models/`. The xschem symbol's `format` line emits
`X<name> <la> <lb> <sub> inductor w=… s=… d=… nr_r=…` — an instance card
pointing at a subcircuit that does not exist in this release. The Qucs-S
descriptor is more pointed: its `L` parameter carries the equation
**`w*s`**, a product of two lengths. That is dimensionally an area, not an
inductance; it is a placeholder, not a model.

IHP's own intended route is **EM extraction**, not a compact model:
`libs.doc/doc/EM_Simulation_Overview.pdf`, `libs.tech/openems/`, and
`libs.tech/palace/`. Both of those EM directories are **git submodules that
are empty in the release tarball** (GitHub source tarballs never carry
submodule contents), so a `fetch → simulate` path does not exist out of the
box either.

### What this blocks

Every acceptance criterion in this study that names the inductor: L, Q and SRF
vs. frequency for the spiral cannot be produced with the shipped models by any
means. Downstream, it blocks the parts of `spec/target-spec.md` that need a
tank Q or a tank centre frequency (rows 1, 2, 3, 5, 6) from being ratified on
simulated evidence — the MIM data above bounds `Q_tank` from one side only.

### What it does not block

The measurement *method* is in place and validated (see §"The method is
validated"), and this testbench is wired to accept a model the moment one
exists:

```bash
export SG13G2_IND_MODEL_LIB=/path/to/inductor_model.spice   # .subckt inductor la lb sub
sim/tank-characterization/run_pvt_sweep.sh
```

`run_pvt_sweep.sh` then `.include`s it, the probe runs, and
`records/<record-id>-inductor.csv` fills in with L/Q/SRF at 1, 5 and 10 GHz
for the three geometries — no other change needed. The subcircuit must be
named `inductor` with pins `(la, lb, sub)` and accept `w`, `s`, `d`, `nr_r`,
matching what the PDK's own xschem symbol and LVS netlists emit.

The three probed geometries are lifted verbatim from the PDK's own LVS unit
testcase, so they are geometries IHP itself exercises rather than ones this
repo invented — a single-turn `w=8.22 s=3.29 d=47.65`, a 5-turn
`w=6.10 s=3.29 d=110.11`, and a 4-turn `w=8.22 s=3.74 d=141.975` (µm). No
claim is made that any of them suits this block's tank.

### Tracked as

Deciding *which* route to take to an inductor model — EM-extract the PDK's own
PCell with openEMS/Palace and fit a lumped subcircuit, use published
measured data, or accept an analytic model with its error bars stated — is a
design decision with real cost, out of scope for a characterization study.
It is filed separately as **#6**.

---

## Findings summary

1. The MIM cap is fully characterizable in this flow; the spiral inductor is
   not characterizable in this flow **at all** on PDK v0.3.0.
2. Use `cap_rfcmim`, never `cap_cmim`, for anything at RF: `cap_cmim` reports
   5–12× optimistic Q and has no self-resonance.
3. `Q_C` at 10 GHz falls from 68 (0.6 pF) to 6.3 (3.8 pF); tank Q is bounded
   above by that, so the tank wants small C and large L.
4. A 50×50 µm MIM self-resonates at 16.1 GHz — inside the plausible band.
   Tank capacitance does not scale up freely.
5. MIM temperature drift is negligible (±0.06 % over 165 °C); MIM process
   spread is ±10 % on C, ≈∓5 % on tank centre frequency.
6. The MIM cap is exactly bias-independent, so it offers no tuning and no
   AM-to-PM path; all tuning must come from the varactor or a switched bank.

None of these is a ratified spec row, and this PR does not make any of them
one.

---

## Sources

- This repo's `CLAUDE.md` — "Tank first", "PVT corners on every recorded
  result", "`sim/` results are append-only evidence".
- `spec/porting-plan.md` §2 (names this study) and §3 (the evidence
  conventions this directory follows).
- `spec/review-bar.md` items 1 and 2 — one-command characterization and README
  reproducibility.
- IHP-Open-PDK v0.3.0: `libs.tech/ngspice/models/capacitors_mod.lib`,
  `cornerCAP.lib`; the inductor artifacts tabulated above. Pin and content
  digests in [`../pdk.json`](../pdk.json) and in each record.
