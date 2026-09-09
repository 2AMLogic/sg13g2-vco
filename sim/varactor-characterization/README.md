# sim/varactor-characterization — C(V), dC/dV and Q(V,f) of the tuning candidates

**What this is.** `tank-characterization/`'s finding 6 says the MIM cap is
exactly bias-independent — "all tuning must come from the varactor or a
switched bank" — and names varactor selection as the next open question
(`spec/target-spec.md` row 2, out of scope there). This directory is the
device-level evidence that question needs: C(V), dC/dV (the Kvco kernel) and
Q(V, f) of `sg13_hv_svaricap` (the MOS accumulation-mode varactor IHP ships)
and of the two junction-diode alternatives issue #18 names, `dantenna` and
`dpantenna`, over control voltage, process corner and temperature.

**This study does NOT**: choose the varactor, choose a band-switching
scheme, build a tank, build an oscillator, or say anything about phase
noise. It ratifies **no** `spec/target-spec.md` row. It feeds the
tuning-mechanism decision record that rows **0** (the `Vctrl` domain),
**2** (tuning range) and **3** (Kvco and its linearity) are waiting on, and
supplies one input `spec/porting-plan.md` §2's "Varactor / tuning mechanism"
open question needs; row **9** (whatever that row tracks once the decision
record exists) is also fed for the same reason. Nothing here is blocked by,
or blocks, #9 (EM inductor extraction) — no inductor and no EM tool appear
anywhere in this directory.

**Headline result**: the MOS varactor and the junction-diode candidates are
not close. `sg13_hv_svaricap` gives `Cmax/Cmin` up to **2.08** with `Q` from
**224** (smallest geometry, 1 GHz) down to **0.19** (largest, 10 GHz);
`dantenna`/`dpantenna` give `Cmax/Cmin` of only **1.03–1.24** with `Q`
**~1–1.7** at 1 GHz regardless of area — these two "antenna" diodes are
ESD/antenna-protection devices IHP never designed for RF tuning, and the
numbers say so plainly. See [Results](#results) for the full table.

---

## Reproducing it

```bash
sim/varactor-characterization/run_varactor_sweep.sh
```

That is the entire cold-start invocation — no arguments, no manual ngspice
session, and (unlike `tank-characterization/`) **no manual build step
either**: this script calls [`../tools/build-osdi.sh`](../tools/build-osdi.sh)
itself before generating any netlist. The first run fetches a
checksum-pinned OpenVAF-Reloaded release (~60 MB, cached under
`${SG13G2_TOOLS_CACHE:-~/.cache/sg13g2-vco}`) and compiles `mosvar.osdi`
from the PDK's own Verilog-A source; later runs just verify the result still
loads. On the machine this record was produced on, the full sweep (216
simulation points) takes **under 4 minutes**.

**Requirements**: `ngspice` and `curl` on `PATH`, `bash`, and an
IHP-Open-PDK **v0.3.0** install (pinned in [`../pdk.json`](../pdk.json)).

```bash
export PDK_ROOT=/path/to/ihp-open-pdk   # only if it is somewhere unusual
export PDK=ihp-sg13g2
```

The run mints a fresh record ID and writes **append-only** evidence under
it, following [`../README.md`](../README.md)'s convention:

| Path | Contents |
|---|---|
| `netlist-snapshots/<record-id>/<corner-id>.spice` | the exact netlist simulated |
| `corners/<record-id>/<corner-id>.log` | raw ngspice batch output for that point |
| `records/<record-id>-curves/<corner-id>.csv` | C(f) and Q(f), 50 points/decade |
| `records/<record-id>.csv` | scalar summary, one row per corner × device |
| `records/<record-id>-kvco.csv` | Cmax/Cmin, ratio, dC/dV per device × corner × temp × domain |
| `records/<record-id>-method-check.csv` | known-answer check of the extraction arithmetic |
| `records/<record-id>.md` | the narrative record, including every loaded model's content sha256 |

`run_varactor_sweep.sh` exits non-zero if any simulation point fails or the
known-answer check drifts past 0.1 %.

---

## Why OSDI, and why this study builds it instead of using the PDK's copy

`sg13_hv_svaricap` (`sg13g2_svaricaphv_mod.lib`) instantiates a Verilog-A
compact model (`.model sg13_hv_svaricap mosvar`, source
`libs.tech/verilog-a/mosvar/mosvar.va`). ngspice can only run it through an
OSDI-compiled shared library, loaded with the `pre_osdi` command inside
`.control`, **before** the first analysis command — ngspice defers
Verilog-A/OSDI device instantiation to analysis setup, not to netlist parse,
so `pre_osdi` must precede `ac`, not merely follow the device lines. (This
was verified directly: putting the load in a `.control` block that ran
*after* an already-failed parse did not help; putting it before the first
`ac` did.)

The pinned IHP-Open-PDK v0.3.0 release happens to ship a **prebuilt**
`libs.tech/ngspice/osdi/mosvar.osdi` alongside the Verilog-A source, but its
provenance — which compiler, which version, built when — is undocumented in
the release. [`../tools/build-osdi.sh`](../tools/build-osdi.sh) (ported from
`2AMLogic/sg13g2-opamp`'s `sim/tools/build-osdi.sh`, scoped down to
`mosvar` only) compiles the PDK's **own** Verilog-A source with a
checksum-pinned OpenVAF-Reloaded release instead, so every number in this
study traces to a compiler and source this repo can name by sha256 — see
each record's `.md` for both digests. `sim/pdk.json`'s `osdi_toolchain`
block restates the pin as a fact sheet.

---

## Bias convention

### `sg13_hv_svaricap`: which node gets the control voltage

`sg13_hv_svaricap`'s pins are `(G1, W, G2, bn)`: `G1`/`G2` are the two split
poly gates (coupled internally by `Rk`/`Ck_g12`), `W` is the isolated n-well
under the gates, and `bn` is the buried n-layer / substrate contact that
isolates that well. Capacitance depends on `Vgb = V(gate) - V(well)`.

This testbench ties `G1` and `G2` together as the **hot** node (the tank-side
RF connection in a real VCO — fixed at 0 V DC by an ideal 1 H choke, since the
negative-gm pair would hold it at a fixed bias, not let it move with tuning)
and ties `W` and `bn` together as the **ctrl** node, driven by the sweep
voltage directly (an ideal DC source is already a perfect AC short, so `ctrl`
needs no choke). This is the standard accumulation-varactor tuning scheme —
tune the isolated well, not the tank node — and matches
`libs.tech/xschem/sg13g2_tests/ac_svaricap_test.sch`'s own topology (DC bias
into the well/substrate side through a choke, gates held at a fixed
potential), though that PDK regression test biases `W` and `bn` from
*separate* nets (`W` grounded, `bn` driven) where this study ties them
together — a simplification stated here rather than left implicit, and safe
over this study's 0–3.3 V range (see below).

### Sign convention: what `Vctrl = 0` means

Hot is fixed at 0 V DC, so `Vgb = 0 − Vctrl = −Vctrl`. `Vctrl = 0` is this
testbench's closest approach to full accumulation (`Vgb ≥ 0`); increasing
`Vctrl` drives `Vgb` more negative, toward and through depletion. **C is
therefore monotonically non-increasing in `Vctrl`** in every corner this
study ran (verified — see [Results](#results)). This does *not* mean a real
tank must be wired the same way: a design could equally tie the gates to
`Vtune` and hold the well fixed, recovering the opposite-sign C(V). What this
study measures is the magnitude of the swing and its shape, both of which are
sign-convention-independent; the tuning-mechanism decision record is where a
specific bias polarity gets chosen.

`W` and `bn` being tied to the same node (rather than biased separately, or
`bn` held at a fixed rail as some real layouts would for isolation) does not
forward-bias anything: the internal `dsubw` well-to-substrate junction sees
zero bias by construction under this tie, at every `Vctrl` this study sweeps.

### `dantenna`/`dpantenna`: reverse bias, and a testbench bug this caught

Both diodes are instantiated `D<n> anode cathode model` (confirmed from their
own internal `D1 1 2 darea` / `D1 1 2 dparea` lines), so pin 1 is the anode,
pin 2 the cathode. This testbench grounds the anode (the hot/AC-probe node,
through a choke) and drives the cathode with `+Vctrl` through an ideal DC
source — cathode more positive than anode, i.e. reverse bias for every
`Vctrl ≥ 0` swept.

**The choke on the hot node is required even though a diode is not a DC-open
device**, and a first draft without one produced a silently wrong result:
with only the diode between "hot" and "ctrl" and an ideal current source (DC
value exactly 0) at "hot", ngspice's DC operating point solves for
`V(hot) = V(ctrl)` — zero net diode current forces zero diode voltage, so
**no reverse bias was actually being applied** at any `Vctrl`. The symptom
was a `C(V)` curve completely flat in `V`, at every corner. Adding the choke
(grounding "hot" independently of "ctrl") fixed it. This is exactly the kind
of bug `sim/README.md` rule 5 ("method before number") exists to catch before
a flat, wrong C(V) gets read as a real result — recorded here rather than
silently fixed and forgotten.

---

## Devices and geometries

### `sg13_hv_svaricap`: four geometries spanning the model's OWN range

Issue #18 informally described the sweep as spanning "the model's `l` floor
(300 nm) to a few µm". **That is not what the model supports**, and this
study honours the model's actual documented range rather than the informal
one: `cornerMOShv.lib`'s own `.param` block states `sg13g2_hv_svaricap_*`
corner scalings, and `sg13g2_svaricaphv_mod.lib`'s `.model … mosvar` card
states `lmin=2.99e-7`, `lmax=8.1e-7` (300–810 nm), `wmin=3.7e-6`,
`wmax=9.8e-6` (3.7–9.8 µm); the subckt's own commented `paramtest` lines
state the same bounds plus `Nx ∈ [1,10]`, `Ny ≤ 1`. There is no "few µm" `l`
option — the model tops out under 1 µm of channel length by design.

| Key | l | w | Nx | Ny | Notes |
|---|---|---|---|---|---|
| `mos_small` | 300 nm (floor) | 3.74 µm (floor) | 1 | 1 | smallest legal instance |
| `mos_mid` | 550 nm | 6.00 µm | 4 | 1 | mid-range |
| `mos_large` | 800 nm (ceiling) | 9.74 µm (ceiling) | 10 (ceiling) | 1 | largest legal single instance |
| `mos_xlarge` | 800 nm | 9.74 µm | 10 | 1 | **four** `mos_large` unit cells in parallel |

`mos_xlarge` exists because `tank-characterization` finding 3 wants tank
capacitance in the sub-pF..~2 pF range, and a single `mos_large` instance
tops out at 489 fF at `Vctrl = 0` (27 °C, `tt`) — under 0.5 pF. `Nx = 10` is
the model's own documented ceiling; reaching ~2 pF means paralleling
multiple max-rated cells, exactly how a real layout would do it (parallel
unit fingers), not pushing one instance past its stated validity. This
study's measured range at `Vctrl = 0`, `tt`, 27 °C: `mos_small` 10.5 fF up
to `mos_xlarge` 1.96 pF — brackets the tank study's target range on both
ends.

### `dantenna` / `dpantenna`: two areas each

| Key | Model | l × w | Area |
|---|---|---|---|
| `dasm` | `dantenna` | 2 µm × 2 µm | 4 µm² |
| `dalg` | `dantenna` | 20 µm × 20 µm | 400 µm² |
| `dpsm` | `dpantenna` | 2 µm × 2 µm | 4 µm² |
| `dplg` | `dpantenna` | 20 µm × 20 µm | 400 µm² |

**Why these areas are much smaller than the MOS geometries' C range, on
purpose**: `darea`'s `cj0 = 9.371e-16 F` (per unit area) and its series
resistance is calibrated on the same per-area basis (SPICE `area=` scales
`is`/`cj0` up and `rs` down together), so — measured directly in this study,
see [Results](#results) — this diode's `RC` time constant, and therefore its
`Q` at any given frequency, is **independent of area**. Picking a bigger
area buys more capacitance at the same (poor) `Q`; it does not buy a device
that competes with the MOS varactor on quality, so this study used areas
large enough to separate the two devices' C by ~2 orders of magnitude
(demonstrating the area-independent-`Q` claim) rather than areas chosen to
match the MIM/MOS target C range.

---

## The control-voltage grid: one list, not two

Issue #18 asks the sweep to cover "both the 1.2 V core and 3.3 V HV control
ranges" — `sg13_hv_svaricap` is an HV device and row 0 (which supply domain
`Vctrl` lives in) is not decided. This study uses **one monotonic list**,
`0.0, 0.3, 0.6, 0.9, 1.2, 1.8, 2.4, 3.0, 3.3` V, rather than two independent
sweeps, because every point from 0.0–1.2 V is *also* exactly the baseline a
report on "what the 1.2 V-only range buys" needs — the two domains share
every point below 1.2 V by construction, so re-slicing one run into a
`core` (first 5 points, 0.0–1.2 V) and a `full` (all 9 points, 0.0–3.3 V)
domain costs nothing extra to simulate and cannot disagree with itself at
the shared points. `records/<record-id>-kvco.csv`'s `domain` column carries
both slices for every device × corner × temperature combination.

---

## The PVT grid

| Axis | Points | Rationale |
|---|---|---|
| **P** (MOS) | `mos_tt`, `mos_ss`, `mos_ff`, `mos_sf`, `mos_fs` | all **five** non-statistical sections in `cornerMOShv.lib`. Verified by reading the file: `sf` and `fs` carry `sg13g2_hv_svaricap_{vfbo,toxo,dlq,dwq}` values distinct from BOTH `tt` and `ss`/`ff` (e.g. `sf`: `vfbo=0.8, toxo=1.02, dlq=1.1, dwq=1.1` vs `ss`: `vfbo=0.8, toxo=1.04, dlq=1.05, dwq=1.05`) — so `sf`/`fs` are NOT redundant with `ss`/`ff` for this device, and issue #18's provisional "add sf/fs if their svaricap parameters differ, check the file" resolves to **yes, add them**. |
| **P** (diode) | `dio_tt`, `dio_ss`, `dio_ff` | all three non-statistical sections in `cornerDIO.lib`. Measured (not assumed) to be corner-invariant for `dantenna`/`dpantenna` — see [Results](#results) — because all three sections `.include "diodes.lib"` unconditionally and identically; only `schottky_nbl1_is`/`schottky_nbl1_kf` differ between them, and `schottky_nbl1` is an unrelated device. |
| **V** (control) | 9 points, 0.0–3.3 V | see above |
| **T** | −40, 27, 125 °C | the same span `tank-characterization` and the sibling blocks in this catalog use |

`*_mismatch`/`*_stat` sections are omitted for the same reason
`tank-characterization` omits `cornerCAP.lib`'s: they model device-to-device
spread within one die and need a Monte Carlo harness this study does not
have.

= **5 MOS sections × 3 temps × 9 V = 135** MOS simulation points × 4
geometries, **+ 3 diode sections × 3 temps × 9 V = 81** diode simulation
points × 4 device/area combinations = **216 simulation points**, 864 device
rows, all PASS.

---

## Method

Identical Z-scan to `tank-characterization`'s: an ideal **1 A AC current
source** injects into each device's hot node, so `V(node) = Z(f)`. From
`Z(f)`: `Ceff(f) = Im(Y)/(2πf)` and `Q(f) = |Im(Y)|/Re(Y)` with `Y = 1/Z`.
Scalars (`C`/`Q` at 1, 5, 10, 20 GHz) come from a 500 point/decade dense
pass over 1e8–3e11 Hz; the committed curve files are a 50 point/decade
coarse pass over the same range.

**Kvco extraction**: `dC/dV` is computed as the finite difference between
consecutive swept `Vctrl` points on the **1 GHz** capacitance — the lowest
of the four scalar frequencies, and the one least affected by each device's
own RC roll-off (see below). `records/<record-id>-kvco.csv` reports the
peak and minimum `|dC/dV|` (signed) plus `Cmax`, `Cmin` and `Cmax/Cmin`, per
device × corner × temperature × domain.

**Method validation**: the identical ideal R-L-C reference network
`tank-characterization/testbench/tb_mimcap_zscan.spice.tmpl` uses
(`R = 2 Ω`, `L = 1 nH`, `C = 100 fF`, closed-form `Leff`/`Q`/`SRF`), re-run
at every one of the 216 points and checked to 0.1 %. All 216 points passed;
worst disagreement across the whole grid was on `SRF` (the interpolated
quantity), consistent with `tank-characterization`'s own worst case.

**SRF**: every device in this study is expected to show **no** self-resonance
— `sg13_hv_svaricap` is a gate capacitance behind a well/substrate resistor
network, and the diodes are plain reverse-biased junctions; neither has a
plate/feed inductance of the kind `cap_rfcmim` has. The SRF `.meas` was run
anyway at every point (same posture as `tank-characterization`'s `cap_cmim`
row) and missed at all 216, recorded as `srf_hz = none` — the expected,
physically meaningful answer, not a measurement failure.

---

## Results

All figures below are from record `20260909-231619-de50891`
(ngspice-46, IHP-Open-PDK v0.3.0), reproducible by re-running the script;
the full grid is in that record's CSVs.

### 1. `sg13_hv_svaricap`: `Cmax/Cmin` up to 2.08, and Q collapses as C grows

At `mos_tt`, 27 °C, full domain (0.0–3.3 V), 1 GHz:

| Geometry | Cmax (at V=0) | Cmin (near V≈2.4–3.3)* | Cmax/Cmin | Q @ 1 GHz (V=0) | Q @ 10 GHz (V=0) |
|---|---|---|---|---|---|
| `mos_small` | 10.46 fF | 5.567 fF | **1.88** | 224 | 22.4 |
| `mos_mid` | 110.98 fF | 53.37 fF | **2.08** | 13.7 | 1.37 |
| `mos_large` | 489.3 fF | 260.6 fF | **1.88** | 1.94 | 0.194 |
| `mos_xlarge` | 1.957 pF | 1.042 pF | **1.88** | 1.94 | 0.194 |

\* `C(V)` is monotonically decreasing from `V=0` to roughly `V=2.4`, then
ticks up by well under 0.1 % out to `V=3.3` — an extremely shallow tail, not
the ~3 % non-monotonicity `dantenna` shows (finding 2), but present
consistently across all four geometries (confirmed at exactly the same
relative depth in `mos_xlarge`, a 4x-parallel copy of `mos_large`, so it is
a real feature of the model's `C(V)` shape, not simulation noise). `Cmin`
above is the true minimum over the sampled grid; `records/<record-id>-kvco.csv`'s
`c_at_vmax` column separately reports the `V=3.3` endpoint value, which is
consistently ~0.05–0.06 % above `Cmin`.

`mos_large` and `mos_xlarge` report identical `Q` (as expected — four
identical cells in parallel do not change `Q`) and near-identical
`Cmax/Cmin` to `mos_small`/`mos_large` (small deviations trace to `Nx`
scaling inside the model, not to a different physical mechanism). Over the
**core-only** domain (0.0–1.2 V) the same devices give a smaller but still
real swing: `mos_small` 1.69×, `mos_mid` 1.82×, `mos_large`/`mos_xlarge`
1.64× — i.e. **the 1.2 V-only range buys roughly 85–90 % of the full 3.3 V
range's tuning ratio** for this device, at the cost of the top ~30 % of
`Vctrl` headroom.

> **Consequence for this block**: bigger geometries buy more absolute
> tuning capacitance at a steep `Q` cost — `mos_large`'s `Q @ 10 GHz` (0.19)
> is two orders of magnitude below `mos_small`'s (22.4). Any tank built
> around this varactor has to trade tuning range against tank `Q` at the
> geometry-selection stage, the same shape of trade `tank-characterization`
> finding 3 found for MIM cap size vs `Q_C`.

### 2. `dantenna`/`dpantenna`: weak tuning, and `Q` that never clears ~1.7

At `dio_tt`, 27 °C, full domain, 1 GHz:

| Device | Area | Cmax | Cmin | Cmax/Cmin | Q @ 1 GHz (V=1.2) |
|---|---|---|---|---|---|
| `dantenna` (`dasm`) | 4 µm² | 1.590 fF (at V≈0.9)* | 1.546 fF (at V=0)* | 1.03 | 1.11 |
| `dantenna` (`dalg`) | 400 µm² | 146.5 fF (at V≈0.9)* | 141.2 fF (at V=3.3)* | 1.04 | 1.06 |
| `dpantenna` (`dpsm`) | 4 µm² | 2.090 fF (at V=0) | 1.690 fF (at V=3.3) | 1.24 | 1.65 |
| `dpantenna` (`dplg`) | 400 µm² | 185.7 fF (at V=0) | 150.8 fF (at V=3.3) | 1.23 | 1.56 |

\* `dantenna`'s `C(V)` is **non-monotonic** over this range: it rises from
`V=0` to a peak around `V≈0.9`, then falls back — for `dasm` the fall
undershoots back below the peak but stays above the `V=0` starting value
out to `V=3.0`, then ticks up again by `V=3.3`; for `dalg` the fall
continues past the `V=0` value, so its minimum lands at the `V=3.3` end
instead. Plausible for a device built from three regions
(`darea`+`dperim`+`dcorner`) with different `vj`/`m` whose individually
monotonic depletion curves sum to a non-monotonic total. Reported as
measured — `records/<record-id>-kvco.csv`'s `cmax`/`cmin` columns are the
true extrema over the sampled grid, not just the two endpoints, and its
`c_at_vmin`/`c_at_vmax` columns report the endpoint values separately.
`dpantenna` is cleanly monotonic decreasing throughout.

`Q` is **independent of area** for both devices (verified directly: `dasm`
vs `dalg`, and `dpsm` vs `dplg`, differ by <10 % in `Q` despite a 100×
area difference) — see [Devices and geometries](#devices-and-geometries)
for why.

> **Consequence for this block**: neither antenna diode gets close to
> `sg13_hv_svaricap`'s tuning ratio (1.03–1.24× vs up to 2.08×) or its `Q`
> at the small-geometry end (~1–1.7 vs up to 224). These are ESD/antenna
> protection devices, not devices IHP designed for RF tuning, and this
> study's numbers say plainly that the MOS varactor is the only credible
> candidate of the two device classes issue #18 named — a finding for the
> tuning-mechanism decision record to weigh, not a decision this study
> makes.

### 3. Process spread: ~6 % on `Cmin`, temperature spread larger than MIM's

`mos_small`, full domain, 27 °C, across `{tt, ss, ff, sf, fs}`:

| Section | Cmax (V=0) | Cmin (V=3.3) | Cmax/Cmin |
|---|---|---|---|
| `ss` | 10.19 fF (−2.6 %) | 5.531 fF (−0.7 %) | 1.842 |
| `tt` | 10.46 fF | 5.567 fF | 1.878 |
| `sf` | 10.29 fF (−1.6 %) | 5.543 fF (−0.4 %) | 1.856 |
| `fs` | 10.64 fF (+1.7 %) | 5.595 fF (+0.5 %) | 1.902 |
| `ff` | 10.76 fF (+2.9 %) | 5.613 fF (+0.8 %) | 1.918 |

Process spread on `Cmin` is **±0.8 %** here — much tighter than
`tank-characterization`'s MIM `Cmax/Cmin`-driving ±10 % `cap_carea` spread
(finding 4), because this device's corner scalings act on `vfbo`/`toxo`
(threshold-like parameters), not directly on an area-scaled capacitance.

`mos_small`, `tt`, full domain, across temperature:

| T | Cmax (V=0) | Cmin (V=3.3) | Cmax/Cmin |
|---|---|---|---|
| −40 °C | 10.64 fF (+1.8 %) | 5.510 fF (−1.2 %) | 1.936 |
| 27 °C | 10.46 fF | 5.567 fF | 1.878 |
| 125 °C | 10.23 fF (−2.1 %) | 5.681 fF (+2.0 %) | 1.801 |

Roughly **±2 % on both `Cmax` and `Cmin`** over the full −40…125 °C span,
and — unlike `tank-characterization` finding 3's MIM cap (±0.06 % over the
same span) — `Cmax` and `Cmin` move in *opposite* directions with
temperature, so `Cmax/Cmin` itself drifts by about 7 % relative
(1.94 → 1.80) end to end. Any frequency-drift or Kvco-drift budget for this
block cannot treat this varactor as temperature-inert the way the MIM cap
is.

### 4. `dantenna`/`dpantenna` corner-invariance, measured not assumed

`dasm`, 27 °C, `Vctrl = 1.2 V`, across `{dio_tt, dio_ss, dio_ff}`: `C`, `Q`
and every other reported scalar are **byte-identical to every digit ngspice
prints** across all three sections — confirming, by measurement, the file
read that `cornerDIO.lib`'s three sections load `diodes.lib` unconditionally
and identically (only `schottky_nbl1_is`/`kf` differ, and that device is
unrelated). The same three sections show a real, if modest, temperature
dependence for `dasm` at `tt`, 1.2 V: `C @ 1 GHz` moves from 1.585 fF
(−40 °C) to 1.589 fF (27 °C) to 1.585 fF (125 °C) — non-monotonic and under
0.3 % end to end, while `Q` falls from 1.16 (−40 °C) to 0.996 (125 °C), a
real ~15 % drop.

> **Consequence for this block**: like the MIM cap's bias-independence
> (`tank-characterization` finding 6), the junction diodes' process-corner
> independence means neither `dantenna`/`dpantenna` process spread nor MOS
> process spread needs to appear as a *combined* axis in a later tank
> testbench beyond what each device's own corner sweep already covers — but
> unlike the MIM cap, temperature is NOT free to drop for the MOS varactor
> (finding 3 above).

---

## Findings summary

1. `sg13_hv_svaricap` gives `Cmax/Cmin` up to 2.08× (full 0–3.3 V domain) or
   up to 1.82× (1.2 V-only core domain — roughly 85–90 % of the full range's
   ratio); `Q` ranges from 224 (smallest geometry, 1 GHz) down to 0.19
   (largest geometry, 10 GHz) — bigger geometries buy tuning capacitance at
   a steep `Q` cost.
2. `dantenna`/`dpantenna` give `Cmax/Cmin` of only 1.03–1.24× with `Q`
   ~1–1.7 at 1 GHz, independent of area — these ESD/antenna diodes are not
   competitive tuning devices next to the MOS varactor.
3. The model's own documented range is `l ∈ [300, 810]` nm, `w ∈ [3.7, 9.8]`
   µm, `Nx ∈ [1, 10]` — narrower in `l` than issue #18 informally assumed
   ("a few µm"). Reaching `tank-characterization`'s ~2 pF target needs
   paralleling multiple max-rated cells, not a single out-of-range instance.
4. `sg13_hv_svaricap`'s process spread on `Cmin` is tight (±0.8 % across
   `tt/ss/ff/sf/fs`) but its temperature spread is not: `Cmax` and `Cmin`
   move in opposite directions over −40…125 °C, drifting `Cmax/Cmin` by
   ~7 % relative end to end — unlike the MIM cap, this device cannot be
   treated as temperature-inert.
5. `cornerMOShv.lib`'s `sf`/`fs` sections carry `sg13_hv_svaricap` corner
   parameters distinct from both `tt` and `ss`/`ff` — confirmed by reading
   the file — so all five non-statistical sections belong in any corner
   sweep of this device, not just `tt`/`ss`/`ff`.
6. `cornerDIO.lib`'s `dio_tt`/`dio_ss`/`dio_ff` sections are, by
   construction and confirmed by measurement, **identical** for
   `dantenna`/`dpantenna` (only an unrelated device's parameters differ
   between them) — the same bias-independence posture
   `tank-characterization` found for the MIM cap, but for process corner
   instead of bias.
7. `Vctrl = 0` in this testbench's chosen bias convention is the closest
   approach to full accumulation reachable by tying the gates to a fixed
   0 V DC and sweeping the well; a real design could equally tune from the
   gate side with the well fixed, recovering the opposite sign of `dC/dV`.
   This study reports magnitude and shape, which are convention-independent;
   the sign a real tank uses is a tuning-mechanism decision, not this
   study's to make.

None of these is a ratified `spec/target-spec.md` row, and this study does
not make any of them one.

---

## Sources

- This repo's `CLAUDE.md` — "State the tuning plan honestly: varactor choice
  (MOS accumulation vs junction), band-switching if any, and KVCO linearity
  across the range."
- `sim/tank-characterization/README.md` — finding 6 and its consequence
  paragraph, the study this one answers.
- `spec/target-spec.md` rows 0, 2, 3, 9 (all `DRAFT`, none moved by this
  study) and `spec/porting-plan.md` §2.
- IHP-Open-PDK v0.3.0: `libs.tech/ngspice/models/sg13g2_svaricaphv_mod.lib`,
  `cornerMOShv.lib`, `diodes.lib`, `cornerDIO.lib`;
  `libs.tech/verilog-a/mosvar/mosvar.va`;
  `libs.tech/xschem/sg13g2_tests/ac_svaricap_test.sch`. Pin and content
  digests in [`../pdk.json`](../pdk.json) and in each record.
- `2AMLogic/sg13g2-opamp`'s `sim/tools/build-osdi.sh` — ported (scoped to
  `mosvar`) as [`../tools/build-osdi.sh`](../tools/build-osdi.sh).
