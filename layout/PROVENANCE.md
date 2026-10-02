# sg13g2-vco layout — provenance record

Provenance for `layout/vco.gds`, the physical layout of the LC-VCO described by
`design/vco.sch` / `design/vco.spice`. This is the prose half of the record;
`layout/vco_manifest.json` is the machine-readable half, and every number in
this file is reproduced there with the measurement that produced it.

**This layout is not signed off.** It is the floorplan / placement / routing
deliverable (issue #60) plus the design-rule iteration on top of it (issue
#61); LVS closure is issue #62. **No DRC report of record carries a
`status: clean` label yet**: the curated-engine report carries eight
violations, all demonstrated to be an artefact of the checking deck rather
than of this layout, and the IHP-native report carries zero findings but a
`coverage_unknown` label that klt 0.6.0 cannot upgrade to `clean` for an
externally-run deck. Read §12 before citing any DRC claim, and "What this
record does *not* claim" at the end before citing any claim at all.

<!-- toc -->
- [1. Tooling and inputs](#1-tooling-and-inputs)
- [2. How to regenerate](#2-how-to-regenerate)
- [3. The PDK submodule overlay (why it is needed)](#3-the-pdk-submodule-overlay-why-it-is-needed)
- [4. Device-to-schematic mapping](#4-device-to-schematic-mapping)
- [5. Resistor device class: why `rppd`](#5-resistor-device-class-why-rppd)
- [6. Varactor well and substrate](#6-varactor-well-and-substrate)
- [7. Floorplan](#7-floorplan)
- [8. What klt routed and what it did not](#8-what-klt-routed-and-what-it-did-not)
- [9. Evidence: how each acceptance criterion was measured](#9-evidence-how-each-acceptance-criterion-was-measured)
- [10. EM-only layers are absent](#10-em-only-layers-are-absent)
- [11. What this record does *not* claim](#11-what-this-record-does-not-claim)
- [12. DRC state (issue #61)](#12-drc-state-issue-61)
<!-- /toc -->

## 1. Tooling and inputs

| Input | Value |
|---|---|
| Source tool | `klt` (klayout-tools) `0.6.0` — the tagged wheel, the same install `.github/workflows/signoff.yml` pins |
| Read-back helper | `klayout` 0.30.12 standalone on `PATH` (klt also bundles KLayout 0.30.12 for `extract` and the curated DRC engine) |
| PDK | IHP-Open-PDK `ihp-sg13g2`, install at `$IHP_PDK_ROOT` (this run: `~/share/pdk/ihp-sg13g2`) |
| Schematic of record | `design/vco.sch` |
| Netlist of record | `design/vco.spice` |
| Generation method | **fully scripted, headless** — no GUI step, no hand-edited geometry |

Two KLayout versions appear deliberately. The repo's `klayout` on `PATH` runs
the read-back helpers (`measure_ports.py`, `verify.py`, `snap_grid.py`) and,
since the DRC-closure pass, the IHP-native DRC deck through
`klt drc --engine klayout` (IHP's deck needs KLayout 0.30.3+ — the 0.28.16
of the first pass aborted at `Gat.g`); `klt extract` uses the KLayout that
ships inside the pinned `klayout-tools` wheel. Both are recorded in the
manifest so a version drift shows up as evidence rather than silently.

## 2. How to regenerate

```sh
layout/generate.sh
```

Cold-start, end to end, no arguments. It writes `layout/vco.gds` and
`layout/vco_manifest.json` and nothing else outside `layout/build/`
(gitignored scratch, same convention as `sim/build/` and `design/build/`).

Stages, each independently runnable via `LAYOUT_STAGES`:

| Stage | What it does |
|---|---|
| `devices` | `klt gen --pdk-pcell` once per distinct PDK PCell call, then `scripts/snap_grid.py` puts each stream on the 5 nm manufacturing grid (§12) — **before** ports are measured, so every derived coordinate is grid-clean by construction |
| `ports` | measures each generated stream's own terminal geometry (`klayout -zz -r`) |
| `requests` | emits the `klt gen-compose` / `klt draw` request documents |
| `compose` | runs them: 2 varactor banks, the bias core, the drawn wiring, the top cell, then `snap_grid.py` over the composed stream (a no-op by construction, kept as a belt-and-braces check) |
| `connectivity` | `klt extract`s the result and checks every net |
| `verify` | reads the composed stream back and writes the manifest |

```sh
LAYOUT_STAGES="requests compose verify" layout/generate.sh
```

The design-rule evidence is a **second, separate script**:

```sh
layout/drc.sh
```

It rewrites `layout/drc/*.json` and **exits non-zero if any verdict drifts
from the one §12 records**, so a PDK, PCell or deck change that moves a result
fails the run instead of quietly rewriting the evidence. Since the
DRC-closure pass it runs **two** engines: the curated deck (which needs only
`klt` and reads the committed stream, no PDK overlay) and IHP's own primary
runset via `--engine klayout` (which additionally needs a standalone
KLayout ≥ 0.30.3 on `PATH` and a PDK install, resolved through the same
`$IHP_PDK_ROOT` / `$PDK_ROOT/ihp-sg13g2` / `~/share/pdk/ihp-sg13g2` search
order as `generate.sh`).

### The flow is deterministic — verified, not asserted

A **cold run from an empty build directory** was re-run against the committed
artifact and produces a **byte-identical** stream:

```
$ LAYOUT_BUILD_DIR=/tmp/layout-cold layout/generate.sh      # from scratch
$ sha256sum /tmp/layout-cold/vco.gds layout/vco.gds
937e5b16c3b2bd55…  /tmp/layout-cold/vco.gds
937e5b16c3b2bd55…  layout/vco.gds
```

`layout/vco.gds` @ `sha256:937e5b16c3b2bd55…` (full hash in
`layout/vco_manifest.json`). Re-verified with the mask-grid step in the flow:
**two** cold runs from two empty build directories produce byte-identical
streams — `snap_grid.py` writes GDS with timestamps disabled for exactly this
reason. So the committed GDS is exactly what the committed script produces
from the committed PDK — this is a *reproducibly generated* artifact in the
sense `signoff/design-evidence-tiers.md` item 2 grades above "documented
provenance", not merely a hand-made artifact with a description attached. A
PCell, PDK or `klt` change that alters the geometry will change that hash.

**No geometry in this flow is hand-drawn as a literal.** Every device is a PDK
PCell instance; every via ladder is a `SG13_dev/via_stack` PCell call (54 of
them, since TE/RE moved off the router), so no via or via-enclosure rectangle
is authored here; the guard ring is four `SG13_dev/ptap1` bars. The explicitly
drawn metal (§8) is expressed as rectangles whose coordinates are *derived
from measured device terminal positions*, not written out as constants — so it
follows the devices if a PCell changes rather than silently detaching from
them. The mask-grid step likewise derives everything from the stream it reads:
it moves vertices by at most half a grid step and never changes topology
(§12).

## 3. The PDK submodule overlay (why it is needed)

`klt gen --pdk-pcell` cannot reach `SG13_dev` in a **stock** `ihp-sg13g2`
tarball install. IHP-Open-PDK vendors `pycell4klayout-api` and `pypreprocessor`
as *git submodules* under `libs.tech/klayout/python/`, and a GitHub source
tarball never carries submodule contents — so `import sg13g2_pycell_lib` dies
at `from cni.dlo import PCellWrapper` and no SG13G2 PCell is reachable.

This is a PDK packaging gap, already filed upstream as
[2AMLogic/klayout-tools#1630](https://github.com/2AMLogic/klayout-tools/issues/1630).
**Do not re-file it.**

`layout/scripts/pdk_env.sh` reuses the committed, revision-pinned workaround
already in this repo —
`sim/inductor-model/em-extraction/scripts/setup_pdk_overlay.sh` — rather than
re-deriving it. It builds a symlink tree of `libs.tech/klayout` with those two
submodule directories replaced by real checkouts, then wraps that in a second
symlink tree shaped like a PDK *root* so `klt --pdk-root` can be pointed at it.

The shared PDK install is **never mutated**; both overlay trees live under
`layout/build/`. The pinned submodule revisions are recorded in the manifest:

| Submodule | Revision |
|---|---|
| `pycell4klayout-api` | `2ffdf79fe51a7c35b361cc854369b5d434c8d478` |
| `pypreprocessor` | `cf1ff9bad0fb5338cf1c5b990b2b816b1ea01a64` |

## 4. Device-to-schematic mapping

Every instance in `layout/vco.gds` traced back to its `design/vco.spice` card.
Net names are spelled exactly as the netlist spells them — ground is literally
`0`.

| Schematic | Netlist card | PCell | Terminal → net |
|---|---|---|---|
| `XL1` | `inductor w=8.22e-6 s=3.74e-6 d=141.975e-6 nr_r=4` | `SG13_dev/inductor2` | `la`→`VDD`, `lb`→`OUTP`, `sub`→`0` |
| `XL2` | `inductor w=8.22e-6 s=3.74e-6 d=141.975e-6 nr_r=4` | `SG13_dev/inductor2` | `la`→`VDD`, `lb`→`OUTN`, `sub`→`0` |
| `XC1` | `cap_cmim w=3.65e-6 l=3.65e-6` | `SG13_dev/cmim` | `PLUS`→`OUTP`, `MINUS`→`OUTN` |
| `XCVP1..16` | `sg13_hv_svaricap w=3.74e-6 l=0.3e-6 Nx=1` | `SG13_dev/SVaricap` | `G1`,`G2`→`VCTRL`, `W`→`OUTP`, `bn`→`0` (§6) |
| `XCVN1..16` | `sg13_hv_svaricap w=3.74e-6 l=0.3e-6 Nx=1` | `SG13_dev/SVaricap` | `G1`,`G2`→`VCTRL`, `W`→`OUTN`, `bn`→`0` (§6) |
| `XQ1` | `npn13G2v Nx=1 El=1.0` | `SG13_dev/npn13G2V` | `C`→`OUTP`, `B`→`OUTN`, `E`→`TAIL`, `sub`→`0` |
| `XQ2` | `npn13G2v Nx=1 El=1.0` | `SG13_dev/npn13G2V` | `C`→`OUTN`, `B`→`OUTP`, `E`→`TAIL`, `sub`→`0` |
| `XQ3` | `npn13G2v Nx=1 El=2.0` | `SG13_dev/npn13G2V` | `C`→`TAIL`, `B`→`NBIAS`, `E`→`TE`, `sub`→`0` |
| `XQ4` | `npn13G2v Nx=1 El=1.0` | `SG13_dev/npn13G2V` | `C`→`NBIAS`, `B`→`NBIAS`, `E`→`RE`, `sub`→`0` |
| `RTE` | `2k` | `SG13_dev/rppd` | `P_HI`→`TE`, `P_LO`→`0` |
| `RREF` | `20.5k` | `SG13_dev/rppd` | `P_HI`→`VDD`, `P_LO`→`NBIAS` |
| `RRE` | `4k` | `SG13_dev/rppd` | `P_HI`→`RE`, `P_LO`→`0` |
| `VSUP` | `dc 3.3` | — **no layout counterpart** | testbench source |
| `VCT` | `dc 1.65` | — **no layout counterpart** | testbench source |

Three naming traps, all measured rather than assumed:

- **The HBT PCell capitalises the V** — `SG13_dev/npn13G2V`, while the model
  and netlist spell it `npn13G2v`. A script asking for `npn13G2v` finds nothing.
- **Emitter length is `le`, not the netlist's `El`** — `XQ3` needs `le='2.0u'`;
  the other three are the `1.0u` default.
- **`cmim` must be overridden** — it defaults to `w`=`l`=`6.99u`, so `3.65u` is
  passed explicitly, with `Calculate='w&l'` so `C` is derived rather than driving.

`VSUP` and `VCT` are elaboration-only testbench sources with no physical
counterpart. #62's LVS reference netlist must exclude them. Note also that
`design/vco.spice` is **flat, not a subcircuit** — its `.subckt vco` / `.ends`
lines are commented out.

### The tank is two independent spirals, not one centre-tapped coil

`XL1 VDD OUTP 0` and `XL2 VDD OUTN 0` are two separate 3-terminal `inductor`
instances that happen to share `VDD`. The layout draws them that way: two
distinct `SG13_dev/inductor2` instances (`L1__vco_ind`, `L2__vco_ind`), each
with its own `la`/`lb`/`sub` terminals, joined only by the `VDD` TopMetal2
strap. Drawing a single centre-tapped differential spiral would be an LVS
mismatch in #62.

## 5. Resistor device class: why `rppd`

`design/vco.spice` instantiates `RREF`/`RTE`/`RRE` as **ideal** ngspice `R`
elements (`RTE TE 0 2k m=1`). No PDK resistor model is named anywhere in the
design, and no decision record (DR-001..DR-004) picks one — so choosing the
physical device class was this phase's call. **The choice is
`SG13_dev/rppd` (`res_rppd`, p+ poly), at w = 1.0 µm.**

The three candidates, from the PDK's own model libraries
(`libs.tech/ngspice/models/resistors_mod.lib`, `cornerRES.lib`):

| Device | Sheet R (Ω/sq) | Mismatch σ(Rsh) | TC1 (ppm/K) | Length for 20.5 kΩ at w = 1 µm |
|---|---|---|---|---|
| `rsil` | 7.0 | 1.2 % | **+3100** | **≈ 2.93 mm** — unusable |
| `rppd` | **260.0** | **1.5 %** | **+170** | **79.0 µm** |
| `rhigh` | 1360 | **5.0 %** | −2300 | 15.1 µm |

Reasoning, in the order the constraints actually bind:

1. **`rsil` is ruled out on area alone.** At 7 Ω/sq, `RREF` needs ~2900 squares
   — 2.9 mm of length at minimum width. That is an order of magnitude larger
   than the entire block.
2. **`rhigh` is ruled out on mismatch and temperature coefficient, not area.**
   It is the most compact option, but σ(Rsh) = 5 % and TC1 = −2300 ppm/K.
   `RREF` sets the tail current through the `XQ4`/`XQ3` mirror
   (`I_tail` = 204.1 µA, `design/README.md:371`), so a 5 % `RREF` spread is a
   5 % tail-current spread — which modulates oscillation amplitude and
   therefore phase noise directly. And over a −40…125 °C span, −2300 ppm/K is
   ≈ 38 % drift in `I_tail`. Every recorded result in this repo carries PVT
   corners; a device whose nominal value moves 38 % across them makes those
   corners dominated by the resistor rather than by the circuit.
3. **`rppd` is the compromise that holds.** 1.5 % mismatch (3.3× better than
   `rhigh`) and +170 ppm/K (≈ 2.8 % drift over the same span, ~14× flatter than
   `rhigh`, ~18× flatter than `rsil`). Its area cost is real but small: the
   three resistors together are ~102 µm of 1 µm-wide poly, trivial beside the
   two 230 µm spirals that already dominate the floorplan (§7).
4. **Current density does not constrain the choice.** `I_tail` is 204.1 µA and
   `RREF`/`RRE` carry ~0.1 mA; at w = 1 µm all three candidates are comfortably
   inside their limits. Matching and temperature stability are the only live
   criteria, which is what points at `rppd`.

### How the lengths were derived (and cross-checked)

The `rppd` PCell's `Calculate: 'l'` R-to-length solve needs a Tcl callback
layer IHP-Open-PDK does not ship, so it is **inert headlessly** and `l` must be
supplied directly. The length/resistance law was therefore *measured from the
PCell itself* at w = 1.0 µm, by generating l = 5/10/20 µm and reading each
result's own `rppd r=…` annotation:

```
r(l) = 258.4492 · l_µm + 70.001  Ω      (exact on all three points)
```

Inverting it gives the committed lengths. `generate.sh` then re-reads each
*generated* device's own annotation and records it in the manifest, so a PCell
change surfaces as a value drift in the evidence instead of silently.

| | Target | Length | PCell's own annotation |
|---|---|---|---|
| `RTE` | 2 kΩ | 7.468 µm | `rppd r=2000.099` |
| `RRE` | 4 kΩ | 15.206 µm | `rppd r=3999.980` |
| `RREF` | 20.5 kΩ | 79.048 µm | `rppd r=20499.901` |

**Independent cross-check.** The measured slope, 258.4492 Ω per µm of length at
w = 1.0 µm, is a sheet resistance of ≈ 258.4 Ω/sq. The ngspice model's
`rsh_rppd` is **260.0** Ω/sq (`cornerRES.lib:21`). The PCell geometry and the
simulation model agree to 0.6 % — two independent sources for the same number,
which is why the law above is quoted as measured rather than assumed. (The
70.001 Ω intercept is the device's two head/contact regions, consistent with
the model's own `lhead` = 0.86 µm and `rzspec` terms.)

**#62 must reconcile a drawn `res_rppd` against an ideal `R`** in the reference
netlist. That is a known, deliberate schematic/layout difference, recorded here
so the LVS phase treats it as expected rather than as a mismatch to chase.

## 6. Varactor well and substrate

This is the subtlest part of the layout, and the part most likely to be
misread, so it is stated in full.

The PDK's subckt signature is annotated in
`libs.tech/ngspice/models/sg13g2_svaricaphv_mod.lib`:

```
*                        Gate1
*                        |  Well
*                        |  |  Gate2
*                        |  |  |  Substrate
*                        |  |  |  |
.subckt sg13_hv_svaricap G1 W G2 bn
```

So `W` is the **n-well** and `bn` is the **p-substrate**. `design/vco.spice`
writes `XCVP1 VCTRL OUTP VCTRL OUTP sg13_hv_svaricap` — i.e. it ties *both*
`W` and `bn` to the tank node.

### What the layout does

- **`W` (n-well) → the bank's own tank node.** Each of the 16 cells in a bank
  gets a Metal1 landing pad over its own n-well contact; one Metal2 bus runs
  the length of the bank and is fed by that side's tank trunk. Bank P's bus is
  `OUTP`; bank N's is `OUTN`.
- **The 16 cells of a bank are arrayed at the SVaricap cell's own NWell pitch
  (2.15 µm)**, so all 16 n-wells merge into **one** island per bank — which is
  correct, because all 16 share one tank node.
- **The two islands are physically isolated.** Measured on the committed
  stream: layer 31/0 (NWell) merges to **exactly 2 polygons**, at
  x ∈ [−68.00, −33.60] and x ∈ [+33.60, +68.00] — 67.2 µm apart, equal area
  (164.1 µm² each). There is no other NWell anywhere in the layout, so nothing
  bridges them and nothing ties either one to `sub!` or to `VDD`.
- **`bn` (p-substrate) → `0`.** This is a **deliberate deviation from the
  netlist card**, and the one place the layout cannot follow the schematic.

### Why `bn` cannot follow the netlist

`bn` is the common p-substrate. Tying it to `OUTP` would require the whole bank
to sit in an isolated p-well inside a deep n-well (`SG13_dev/isolbox`), which
this block does not have and which the schematic does not ask for. The drawn
substrate is therefore the shared one, tied to `0` through the four
`SG13_dev/ptap1` guard-ring bars.

**#62's LVS will see `bn` = `0` where `design/vco.spice` says `bn` = tank
node.** That is expected, recorded here, and is a schematic question (is the
netlist's `bn` tie physically meaningful?) rather than a layout defect.

### An honest note on the `bn` PCell parameter

The `SVaricap` PCell's `bn` parameter **is** overridden per bank — `bn='OUTP'`
for bank P, `bn='OUTN'` for bank N, as recorded in the generated request
documents, and visible in the stream as two distinct cells (`SVaricap` and
`SVaricap$1`).

**But that override is annotation-only, and it must not be credited with the
isolation.** Measured: the XOR of all layers between `SVaricap` and
`SVaricap$1` is **empty** — the two cells' geometry is identical, and the PCell
ignores `bn` when drawing. The override is kept because it records the intended
electrical node faithfully against the netlist card, not because it does any
geometric work.

**The isolation is a floorplan property, not a parameter property**: it comes
from placing the two banks 67.2 µm apart so their n-well islands cannot merge,
and from routing each island's contacts only to its own tank node. That is what
the two-polygon NWell measurement above actually verifies.

## 7. Floorplan

| | Value |
|---|---|
| Top cell | `vco` |
| Bounding box | 610.256 × 396.285 µm |
| Area | **0.241835 mm²** |

The two `p11` spirals dominate: at `d_out` = 230.2 µm each
(`sim/inductor-model/em-extraction/README.md`) they alone are ~0.11 mm², so the
floorplan is organised around them rather than around the active devices.

```
                    y > 0:  the two spirals, side by side
        +---------------------------+---------------------------+
        |          L1 (OUTP)        |          L2 (OUTN)        |
        |   SG13_dev/inductor2      |   SG13_dev/inductor2      |
        +---------------------------+---------------------------+
                       VDD strap (TopMetal2) joins the two `la`
   y = 0 ------------------------------------------------------------
                    y < 0:  the active core, inside the guard ring
        +-----------------------------------------------------------+
        |  OUTP / OUTN TopMetal1 trunks, symmetric about x = 0       |
        |                        C1  cmim  (OUTP-OUTN)              |
        |  [ BANK P: 16x SVaricap ]  <-67.2um->  [ BANK N: 16x ]     |
        |          VCTRL Metal3 trunk under both banks              |
        |                   Q1      Q2    (cross-coupled, mirrored)  |
        |                        Q3 (tail, le=2.0u)     Q4   RREF    |
        |             RTE                      RRE                   |
        +-----------------------------------------------------------+
            guard ring = 4x SG13_dev/ptap1 bars, substrate -> `0`
```

Symmetry is deliberate and structural: `Q1`/`Q2` are the same block placed
`mirror_x`, bank N's origin is the arithmetic mirror of bank P's, and the
`OUTP`/`OUTN` trunks are equal-width metal on the same plane. The differential
pair's two halves are intended to be each other's mirror image rather than
merely similar.

**The guard ring's four `ptap1` bars abut at the corners, they do not
overlap.** Measured both ways: an overlap interleaves the two bars' own contact
arrays and `klt drc` reports ~600 `cont.space`/`cont.width` violations that
neither bar has on its own. The abutting arrangement carries none of them —
confirmed by #61's report of record (§12), whose only remaining rule is
unrelated to the ring — and the abutment still closes the annulus, which §12
verifies with `klt ring-check` against a negative control rather than by
inspection.

## 8. What klt routed and what it did not

One net is left to klt's router; eight are drawn explicitly. The split is a
tool-capability boundary, and both sides are stated so a reviewer need not
infer which metal came from where.

**Routed by `klt gen-compose` (`connectivity[]`, in the `core` composition):**
`NBIAS` — the one net that lives entirely inside that composition's own clear
region *and* needs no via drop. `TE` and `RE` were router-routed until the
DRC-closure pass: their via1 drops are drawn at klt's PDK-independent
0.22 µm contact constant, which IHP's min-AND-max 0.19 µm via1 rule (V1.a)
rejects outright (klayout-tools #2698), so both feeds moved to explicit
Metal2 runs + `via_stack` PCell ladders — the same transition pattern as
everywhere else in this block.

**Drawn explicitly via `klt draw` (the `wiring` cell, 86 shapes, 9 labels):**
`VDD`, `OUTP`, `OUTN`, `VCTRL`, `TAIL`, `TE`, `RE`, `0`. Each for one of two
reasons:

- **(a) it terminates on a device pad the sg13g2 layer-role table cannot
  name** — the spirals' TopMetal1 pins, the MIM cap's Metal5/TopMetal1 plates;
  the router cannot target a pad it has no role for — or, for `TE`/`RE`, it
  needs a PDK via the router will not draw.
- **(b) it needs deliberate, symmetric, wide differential metal** that a
  point-to-point Manhattan router does not produce — the `OUTP`/`OUTN` trunks
  and the `VDD` strap are shaped for tank symmetry, not for shortest path.

Not because the router "failed": it was not asked, and the reason is per-net.

**`klt draw` is PDK-unaware by construction.** Its own response is stamped:

> written verbatim by `klt draw`: no PDK awareness and no rule checking were
> applied; this cell is not guaranteed to be design-legal

That stamp is the honest status of the explicitly drawn metal, and it is a
large part of why DRC closure is a separate phase (#61).

## 9. Evidence: how each acceptance criterion was measured

Every row was read back out of the **committed** `layout/vco.gds`, not asserted
by the generator. The machine-readable form is
`vco_manifest.json` → `acceptance_checks[]`.

### Instance counts

Flattened instance count per PCell, walking the hierarchy and multiplying
`CellInstArray` sizes:

| PCell | Expected | Measured |
|---|---|---|
| `SG13_dev/inductor2` | 2 | **2** |
| `SG13_dev/cmim` | 1 | **1** |
| `SG13_dev/SVaricap` | 32 | **32** (16 + 16, as two distinct bank cells) |
| `SG13_dev/npn13G2V` | 4 | **4** (3 × `le=1.0u`, 1 × `le=2.0u`) |
| `SG13_dev/rppd` | 3 | **3** |
| `SG13_dev/ptap1` | 4 | **4** (guard ring) |
| `SG13_dev/via_stack` | — | 54 (every via ladder in the block, incl. the TE/RE feeds since the DRC-closure pass) |

### All 9 nets

Two independent measurements, because one alone would be misleading:

1. **Labels in the stream.** All nine net names are present as text on the
   correct pin layers: `0`/`NBIAS`/`TAIL`/`TE` on 8/25 (Metal1),
   `RE`/`TE` on 10/25 (Metal2), `VCTRL` on 30/25 (Metal3),
   `OUTP`/`OUTN` on 126/25 (TopMetal1), `VDD` on 134/25 (TopMetal2).

2. **Extraction, with the spirals removed.** `klt extract --deck sg13g2` on the
   layout as committed returns **7** nets, with `OUTN|OUTP|VDD` **merged** —
   correct and expected, because an inductor is a DC short and klt's sg13g2
   deck models no inductor device, so the two spirals' metal joins the three
   tank nodes. Re-extracting the same layout with the two `inductor2` instances
   deleted (`scripts/prune_spirals.py`) separates them iff nothing *else*
   shorts them, and it does:

   ```
   vco           nets=7  dead_metal=0  ['0','NBIAS','OUTN|OUTP|VDD','RE','TAIL','TE','VCTRL']
   vco_nospiral  nets=9  dead_metal=0  ['0','NBIAS','OUTN','OUTP','RE','TAIL','TE','VCTRL','VDD']
   ```

   Nine distinct, singly-connected nets, exactly the nine of
   `design/vco.spice`. **`dead_metal = 0` on both** — every piece of routing
   metal in the block joins an extracted net, so there is no stranded or
   decorative wiring.

This is a *connectivity* check, not LVS. It demonstrates that the nets exist
and are distinct; it does not demonstrate device-level correspondence, which is
#62.

### Tool limitations this phase measured, relevant to #62

`device_counts` on the committed layout is `{"cap_cmim": 1}` — **1 of this
block's 42 devices extracts**. This bounds what #62 can do with `klt lvs` on
the current deck. It is **not** a defect in this layout, and it is why §9's net
evidence is framed as a connectivity check rather than as an LVS result.

Three separate causes, each checked against the `klt` 0.6.0 deck source and the
upstream tracker rather than assumed:

| Device | Status | Where it stands |
|---|---|---|
| SiGe HBT (4×) | **declined upstream, with rationale** | `klayout-tools` #1232 investigated populating `EXTRACTION_DECK.bipolars` and concluded the model does not fit: IHP uses a `CustomBJTExtractor`, not the `DeviceExtractorBJT3Transistor` that `BipolarDevice` wires up, and `npn_mk` is a boolean expression (`trans_drw AND pwell AND ptap_holes`) where `BipolarDevice.marker` takes a single layer/datatype pair. The deck documents this decision in its own source. **Do not re-file.** The `npn13G2V` emitters also produce `Gate shape touches no diffusion - ignored` warnings, which is a symptom of the same gap. |
| MOS varactor (32×), spiral inductor (2×) | **known not curated** | The deck's own source lists `sg13_hv_svaricap`, inductors, ESD devices and the RF MOS as uncurated. Already-known upstream; not re-filed. |
| Poly resistor (3×) | **newly filed: `klayout-tools` #2679** | The deck *does* carry `rsil`/`rppd`/`rhigh` `ResistorDevice` classes, so this one was expected to work and does not. Diagnosed below. |

#### The poly-resistor finding (klayout-tools#2679)

Worth recording because it is a measurement, not a guess, and because #62 would
otherwise chase it as a layout defect. The deck declares
`ResistorDevice(name="rppd", body=(5,0) GatPoly, marker=(128,0) polyres)` — the
usual "marker overlaps body" convention. The PDK's `SG13_dev/rppd` PCell draws
the **opposite**: `polyres` is the resistive body, `GatPoly` is only the two
head/contact pads. Measured on `rppd_rref` (w = 1.0 µm, l = 79.048 µm):

```
GatPoly 5/0   -> 2 polygons   (0.000,-0.430)-(1.000, 0.000)    <- head
                              (0.000,79.048)-(1.000,79.478)    <- head
polyres 128/0 -> 1 polygon    (0.000, 0.000)-(1.000,79.048)    <- the BODY
body AND marker area = 0.000 um2
```

The marker's extent is *exactly* the requested length and the two GatPoly pads
sit outside it, so the polarity is unambiguous. `body AND marker` is empty, so
the device region is empty and no drawn resistor is ever recognized — silently,
with `status: "extracted"` and exit 0. Every layer the class `requires`
(111/0, 14/0, 28/0) **is** present, so this is a polarity mismatch and not a
missing-layer problem. It is the same shape of bug as the already-fixed #2591
(`tap_nplus` inverting the upstream convention).

This is also why the three `rppd` instances' Metal1 terminal pads would show up
as `dead_metal` if the resistors were extracted in isolation — with no device
body, the poly never joins the metal. In the **composed** block they are not
dead, because the `TE`/`RE`/`NBIAS`/`0` routing lands on them; hence
`dead_metal = 0` in §9.

## 10. EM-only layers are absent

`sim/inductor-model/em-extraction/gds/inductor_p11.gds` is a committed GDS of
exactly this `p11` spiral, and it is a useful reference — but it carries
**EM-only artifacts that must not enter a signoff layout**: two lumped-port
footprints on 201/0 (`LA`) and 202/0 (`LB`), plus a substrate-ground patch on
210/0 (`SUBGND`) extending 15 µm beyond the ports. Carried through, they
surface in #61 as `coverage.layers_in_stream_without_rules`.

**This layout does not copy that geometry.** Both spirals are fresh
`SG13_dev/inductor2` PCell instantiations. Measured on the committed stream —
53 layers present, and of those:

```
EM-only layers (201/0, 202/0, 210/0) present: none
```

One deliberate non-finding, because it looks like a hit and is not: the strings
`LA` and `LB` **do** appear in the stream, as *text* on layer **27/25**. That
is the `inductor2` PCell's own terminal annotation on a pin/text layer — not
the EM-only *drawing* layers 201/0 and 202/0, which are absent. The distinction
is between a layer and a label that happens to share its name.

## 11. What this record does *not* claim

- **Not DRC-clean *by label*.** Neither report of record says `status:
  clean`, so `signoff/design-evidence-tiers.md` item 3 is **not** satisfied
  and this layout must not be cited for it. The curated report's eight
  remaining violations are demonstrated in §12 to be artefacts of the
  checking deck rather than of this layout, and the IHP-native report has
  zero findings — but a demonstration is not a clean report, and the three
  must not be conflated. The curated deck also covers only part of the DRM
  (§12 quotes its `deck_scope` and its 37 rule-free drawn layers), so even a
  clean verdict from it would not have been a full design-rule result; the
  native deck's zero findings carry the native deck's own scope, and the
  §12 optional-deck survey (density fill deferred to chip assembly,
  maximal's PCell-internal `NW.e`) bounds the rest.
- **Not LVS-clean.** No device-level netlist comparison was run. Three known
  deliberate differences are already recorded for #62: the drawn `res_rppd`
  against the netlist's ideal `R` (§5), the varactor `bn` tie (§6), and the
  `VSUP`/`VCT` testbench sources with no layout counterpart (§4). The deck's
  device-class coverage (§9) bounds what is checkable at all. **LVS closure is
  #62.**
- **`klt gen-compose`'s `nets[].routed` is not a DRC guarantee.** It means the
  router produced a connection, not that the connection is legal.
- **No output buffer.** Deliberately excluded per `design/README.md:99-100`.
- **No electrical or EM claim.** Nothing here supersedes the tank study in
  `sim/inductor-model/`; no inductance, Q, frequency or phase-noise number is
  asserted or implied by this layout.

## 12. DRC state (issue #61)

This section is the DRC record. Its machine-readable half is
`layout/drc/*.json`, rewritten by `layout/drc.sh` (§2); every number below is
quoted from those files rather than typed from memory, and `drc.sh` fails if
any of them drifts.

### The verdict of record

| | |
|---|---|
| Report | `layout/drc/vco-drc.json` |
| Command | `klt drc layout/vco.gds --deck sg13g2 --top vco --format json` |
| Engine | `curated` (klt's own pip-only Region-primitive deck; default) |
| Deck | `sg13g2` @ `sha256:894326a4e37fb24fef2f7ffc6ae1da55a0e262b0f0bc1c09adc4862909278fda` (`released: true`) |
| Input | `layout/vco.gds` @ `sha256:937e5b16c3b2bd55…` |
| Tooling | `klt 0.6.0` (tagged wheel, the same install CI pins), standalone KLayout 0.30.12 on `PATH`, bundled KLayout 0.30.12 |
| **Status** | **`violations`, 8 — NOT `clean`** |
| Rule counts | `{"activ.enclosing.cont.1": 8}` |

The reproducibility caveat of the first DRC pass is resolved by this one:
that pass could only run a post-tag `0.6.0+gaf8d6c54312e` build and said so.
This pass runs the **tagged `0.6.0` wheel** (the same `klayout-tools==0.6.0`
`.github/workflows/signoff.yml` installs), so `provenance.deck.released` is
`true` and the deck hash above is the tagged wheel's. A smaller caveat
replaces it, recorded by the tool itself: the resolved KLayout engine is
0.30.12 where this klt build was tested against 0.30.10, so
`provenance.klayout_version_mismatch` is `true` — klt states the verdict is
unaffected and only count-level fields could differ; `drc.sh` re-asserts the
counts on every run, so any such difference fails loudly rather than
silently.

### The second report of record: IHP's own runset, zero findings

`layout/drc/vco-drc-ihp.json` is the same committed stream checked by the
PDK's own primary DRC runset — `libs.tech/klayout/tech/drc/ihp-sg13g2.drc`,
the deck that implements the process rules (including `Cnt.c` as IHP wrote
it, NBL, latch-up, the 5 nm grid of rule 3.1 and the 0/45/90 edge angles of
rule 3.2) rather than approximating them:

| | |
|---|---|
| Report | `layout/drc/vco-drc-ihp.json` |
| Command | `klt drc layout/vco.gds --engine klayout --deck-file "$IHP_PDK_ROOT/libs.tech/klayout/tech/drc/ihp-sg13g2.drc" --format json` |
| Deck | `ihp-sg13g2.drc` @ `sha256:0620b737538af7c8…` (590 rule categories) |
| **Findings** | **0 violations** |
| **Status label** | **`coverage_unknown`** — see below |

**Why zero findings is not labelled `clean`.** This is klt 0.6.0's documented
behaviour, not a hedge: there is no instrumentation interface by which an
externally-run deck can prove every rule executed, and a deck that gates its
rules behind an unset `-rd` global produces the same zero-item report as one
that genuinely ran everything, so klt refuses the `clean` label for any
zero-finding `--engine klayout` run and reports `coverage_unknown` (exit 4)
instead. A *found* violation always overrides to `violations` — which is how
the 370 findings this pass started from were reported by the same engine.
`drc.sh` therefore gates on the **findings** (zero) and records the status
label verbatim. Filed as a feature request per this repo's friction protocol:
[2AMLogic/klayout-tools#2697](https://github.com/2AMLogic/klayout-tools/issues/2697).

The `provenance.deck` field of this report records the host's absolute PDK
install path; the `content_hash` beside it is the path-independent identity
to compare across hosts.

### Coverage disclosure

`signoff/design-evidence-tiers.md` item 3 requires these three fields to be
stated with any DRC claim, and makes the disclosure the claimant's job, not
the tool's. Quoted verbatim from the cited envelope's `coverage` block:

- **`coverage.rules_skipped`** — `[]`. Empty: every rule the deck carries was
  evaluated on this run.
- **`coverage.deck_scope`** — `Act`, `Cnt`, `Gat`, `M1`, `M2`, `M3`, `M4`,
  `M5`, `TM1`, `TM2`, `TV1`, `TV2`, `V1`, `V2`, `V3`, `V4`. Sixteen DRM
  chapters: the Activ/Cont/GatPoly front end and the Metal1–TopMetal2 /
  Via1–TopVia2 back end. **Everything else in the DRM is outside this deck
  entirely** — no NWell, nBuLay, pSD/nSD implant, SRAM/DigiBnd, recommended,
  density/fill, antenna, latch-up, edge-seal or device-specific (HBT,
  SVaricap, MIM, inductor) chapter is checked at all. A clean verdict from
  this deck would still not be a full sg13g2 DRC result.
- **`coverage.layers_in_stream_without_rules`** — 37 layers are drawn in this
  stream that the deck has no rule for: `1/20` `1/23` `5/23` `8/2` `8/23`
  `8/25` `10/2` `10/23` `10/25` `14/0` `26/0` `27/0` `27/2` `27/25` `28/0`
  `30/23` `30/25` `31/0` `32/0` `36/0` `40/0` `46/21` `50/23` `51/0` `52/0`
  `63/0` `67/23` `111/0` `126/2` `126/23` `126/25` `128/0` `129/0` `134/23`
  `134/25` `148/0` `156/0`. Most are pin (`*/2`), label (`*/23`, `*/25`) and
  device-recognition layers that carry no width/space rule anywhere, but the
  list also contains real mask layers this deck simply does not model — NWell
  `31/0`, nSD `32/0`, pSD `14/0`, Activ:mask `1/20`, polyres `128/0`, HBT and
  SVaricap markers. **Nothing on any of those 37 layers was checked.** The
  `1/20` entry is also the direct cause of the eight remaining violations,
  below.

### What was fixed to get here

Two iteration passes over the layout #60 committed, both fixing in place in
the same generator (`layout/scripts/floorplan.py`) rather than in a parallel
copy. **Pass 1** (PR #74) fixed the curated deck's findings. **Pass 2** (the
DRC-closure pass, this change) ran IHP's own primary runset for the first
time — it reported **370 real findings** — and fixed all of them:

| Pass | Rule | Count | Where | Cause | Fix |
|---|---|---|---|---|---|
| 1 | `metal1.space.1` | 2 (one per bank) | `VS_VCTRL_P1` / `VS_VCTRL_N1` | the inboard VCTRL tap's `vs_m1_m3` ladder sat at a round `BANK_X0 + 2.0 µm`, leaving its 0.70 µm Metal1 pad **0.09 µm** from the adjacent `SVaricap` cell's own gate metal — half the 0.18 µm `M1.b` minimum | the tap's x is now **derived from the measured `G1` port box and the measured via-stack pad width**, centred in the gap between two adjacent cells' gate metal, giving **0.32 µm** each side; the clearance is `assert`ed against `M1_SP`, so a PCell or pitch change fails generation instead of silently reopening the violation |
| 2 | `*_Offgrid` (23 layer keys) | 306 | everywhere: spiral PCell internals, `rppd` internals, hand-drawn wiring, via-ladder origins | IHP rule 3.1 requires every vertex on a **5 nm** grid; PCell arithmetic (`d = 141.975 µm`…) and port-measurement-derived wiring coordinates land on arbitrary nanometres | **`layout/scripts/snap_grid.py`**, a new mask-grid step in `generate.sh`: per cell and layer it merges the shapes (snapping overlapping PCell pieces independently would open seam slivers inside solid metal), rounds every vertex to 5 nm, and restores raw edge *directions* — axis-aligned edges stay axis-aligned, near-45° edges (dx = 41588, dy = 41587 → 44.9993°) become exact. Device streams are snapped **before** port measurement, so ports, requests, wiring and placements are grid-clean by construction; the composed stream is snapped again as a no-op-check. Vertices move ≤ 2.5 nm; two cold builds are byte-identical (§2) |
| 2 | `topmetal2_drw_Angle45` | 36 | both spiral instances | rule 3.2 has **no angle tolerance**: a 45° edge one nanometre off exact is a violation, not a rounding footnote | same snap step's exact-45 restoration (see above) |
| 2 | `NBL.b` | 60 | both varactor banks | IHP requires **1.5 µm** between NBL regions (or a notch-free union) even on the same net; the 16-cell banks' abutted `SVaricap` NBL shapes leave 0–130 nm gaps | **one same-net NBL plate per bank** (`wiring_request`), spanning the measured `nbl_box_um` of cells 1..16 at each bank's tank node; the banks stay 67.2 µm apart (≫ `NBL.c`'s 3.2 µm different-net minimum), and `measure_ports.py` now measures the cell's own NBL box so the plate is derived, never transcribed |
| 2 | `V1.a` (introduced and fixed within the pass) | 4 | TE/RE router via-drops | klt's router draws its via1 drops at its PDK-independent **0.22 µm** contact constant; IHP's rule V1.a fixes via1 at **0.19 µm min *and* max**, so the drop violates in both directions on this PDK | TE and RE moved from the router to explicit Metal2 runs + `SG13_dev/via_stack` PCell ladders at each resistor feed (same pattern as every other transition in this block); filed generically as [2AMLogic/klayout-tools#2698](https://github.com/2AMLogic/klayout-tools/issues/2698) |

Two intermediate findings the pass introduced on its own path and then
cleared are recorded for honesty: the first snap implementation rounded
vertices per-piece instead of per-merged-layer, which opened 3 seam notches
per spiral that rule TM2.a (Euclidian width) correctly flagged, and the
router's 220 nm via1s appeared only once the snapped inputs made the router
switch via variant. Both are gone in the committed stream; the deck's zero
finding count covers them.

### The eight that remain are the deck's, not the layout's

All eight are `activ.enclosing.cont.1` inside the PDK's **own** `npn13G2V`
PCell — two per HBT, on all four of `Q1`/`Q2`/`Q3`/`Q4` — so no placement,
routing or spacing decision in this repo can move them. They are a known,
*self-declared* approximation in klt's curated deck, and the approximation is
over-strict rather than merely narrow.

klt's rule description says so itself: it "approximates the official rule's
SRAM/DigiBnd-scoped compound-layer derivation as a plain, unconditional
Activ-encloses-Cont floor". IHP's deck of record
(`libs.tech/klayout/tech/drc/rule_decks/feol/5_14_cont.drc`, rule `Cnt.c`)
writes the enclosing region as

```ruby
cnt_c_act = act_nsram.join(activ_mask).not(digibnd_drw)
cnt_c_l   = cont_nsvaricap.enclosed(cnt_c_act, 0.07.um, euclidian)
```

while klt's curated form is `enclosing(Activ.drawing 1/0, Cont.drawing 6/0)
>= 0.07 µm`. The dropped `.join(activ_mask)` term is the problem: `activ_mask`
is layer **`1/20`**, it *enlarges* the enclosing region, and **IHP's HBT PCell
draws its emitter/base windows on `1/20` rather than on `1/0`**. Dropping it
therefore makes the enclosing region smaller than the rule's, so contacts that
the real rule passes are reported as under-enclosed. (A second dropped term,
`contbar = cont_nseal.non_squares`, likewise puts non-square contact *bars*
into a check `Cnt.c` never applied to them.)

**This is measured with klt's own check, not re-implemented.** A first attempt
to re-derive the enclosure in `pya` by hand produced a different number than
klt's `enclosing` primitive and was discarded — a hand-rolled check is a
second thing that can be wrong. Instead, `layout/drc.sh` runs a
single-variable control: the **same deck, same engine, same layout**, re-run
against a diagnostic copy of the stream that supplies exactly the one dropped
term (`layout/scripts/activ_mask_overlay.py` copies the 8 `1/20` shapes onto
`1/0` and changes nothing else).

| Stream | `klt drc --deck sg13g2` |
|---|---|
| `layout/vco.gds` as committed | `status: violations`, 8 × `activ.enclosing.cont.1` |
| + the `.join(activ_mask)` term `Cnt.c` has and klt's deck drops | **`status: clean`, 0** |

Supplying that one term accounts for every remaining violation and introduces
none of its own. Recorded in `layout/drc/vco-cnt-c-control.json`; `drc.sh`
fails if the control stream ever stops coming back clean, because that would
mean the remaining violations are real and the explanation here is stale.

**The control stream is an experiment, not a layout.** It lives in
`layout/build/drc/` (gitignored) and is never committed, never shipped, and
never cited as evidence about the block. Copying Activ:mask geometry onto
Activ:drawing in the real stream would be falsifying mask data to make a
report go green; the point of the control is only to identify *which rule
term* the difference comes from.

Filed upstream as a tool gap per this repo's friction protocol:
[2AMLogic/klayout-tools#2688](https://github.com/2AMLogic/klayout-tools/issues/2688).

### The PDK's own deck: how it became runnable here

`klt drc --engine klayout` runs IHP's deck of record, which implements
`Cnt.c` correctly. It could not run on the first pass's host: that engine
shells out to the standalone `klayout` on `PATH`, which was **0.28.16**, and
IHP's deck aborted part-way through at rule `Gat.g` with

```
ERROR: undefined local variable or method `absolute' for DRCEngine
  rule_decks/feol/5_8_gatpoly.drc:70
```

— a DRC-DSL metric newer than that KLayout (IHP's own DRC requirements say
KLayout 0.30.3+). klt's handling is correct and not the gap: it refused the
partial report rather than reporting its zero violations as a clean verdict.
The gap — klt *bundles* KLayout 0.30.12 but `--engine klayout` cannot use
it, and nothing preflights the PATH binary's feature level — was filed as
[2AMLogic/klayout-tools#2689](https://github.com/2AMLogic/klayout-tools/issues/2689).

This pass ran on a host with a standalone **KLayout 0.30.12** on `PATH`, so
the same engine + deck now runs to completion — that is where the 370 real
findings (and, after the fixes above, the zero-finding report of record)
come from. `drc.sh` resolves the PDK install through the same search order
as `generate.sh` (`$IHP_PDK_ROOT`, `$PDK_ROOT/ihp-sg13g2`,
`~/share/pdk/ihp-sg13g2`), so the native-deck leg of the drift gate now
needs a PDK install too — recorded in §2.

### IHP's optional decks, surveyed once and not gated

IHP's own runner (`tech/drc/run_drc.py`) additionally offers three optional
decks. All three were run once against this stream, for state, and are
deliberately **not** part of `drc.sh`'s gate:

| Deck | IHP default | This stream | Scope decision |
|---|---|---|---|
| `antenna.drc` | opt-in (`--antenna`) | **0 findings** (`coverage_unknown` label, same §12 instrumentation cap) | none needed |
| `density.drc` | on (`--no_density` to disable) | 9 findings: `AFil.g`, `GFil.g`, `M1.j`…`M5.j`, `TM1.c` — min-*fill* rules | fill insertion is a chip-assembly step (the rules are the *Fil* filler layers); this block ships un-filled by design and #59's signoff phase owns the fill decision |
| `rule_decks/sg13g2_maximal.drc` | on (`--disable_extra_rules` to disable) | 4 × `NW.e`, all inside the PDK's **own** `SVaricap` PCell | the PDK's README self-declares this deck "not verified or tested"; the 4 findings are PCell-internal (well-tie enclosure), unreachable from this repo's floorplan — same class as the curated deck's `Cnt.c` artefact |

### Guard-ring / tap continuity

`layout/drc/vco-ring-check.json`. The ring is the four `SG13_dev/ptap1` bars
of §7, clipped to its own Activ outer box `[-80.0, -106.0, 105.0, -16.0]`;
`--ignore-enclosed` is required because the ring encloses core geometry on the
same layers.

**Each layer is run twice.** A `continuous` verdict means nothing on its own —
a check that cannot fail is indistinguishable from one that passes — so the
same invocation is also run against a copy of the stream with one of the four
`ptap1` bars deleted (`layout/scripts/break_ring.py`), which opens the annulus
on one side and changes nothing else.

| Ring layer | Committed layout | Negative control | Verdict |
|---|---|---|---|
| Activ `1/0` | `continuous` | `broken` (37) | **continuity verified** |
| pSD `14/0` | `continuous` | `broken` (72) | **continuity verified** |
| Metal1 `8/0` | `continuous` | `broken` (56) | **continuity verified** |

All three of the ring's layers are now verified with discriminating negative
controls. (On the first pass the Metal1 row was reported as *not evidence*:
its negative control also passed, because unrelated Metal1 core routing
shared the clip window and could satisfy `klt ring-check`'s continuity test
with the ring's own Metal1 open —
[2AMLogic/klayout-tools#2690](https://github.com/2AMLogic/klayout-tools/issues/2690).
The DRC-closure pass's wiring changes — TE/RE moved to explicit Metal2 runs,
the grid snap merging each cell's Metal1 — changed what the window contains,
and on the committed stream the control now breaks it: 56 Metal1 ring
violations appear when one `ptap1` bar is deleted, so the `continuous`
verdict on the committed layout is attributable to the ring. The upstream
scoping gap stays open for other layouts; this one no longer leans on it.)

### What this leaves for #62 and beyond

- **Item 3 of `signoff/design-evidence-tiers.md` is not met** and no citation
  of this layout should claim it. Every *real* design-rule violation IHP's
  own primary runset can find is fixed (zero findings,
  `layout/drc/vco-drc-ihp.json`), but the literal `status: clean` label is
  produced by neither engine, for two **upstream** reasons, and this repo
  does not relax a ratified criterion to make a result pass:
  1. the curated deck's `Cnt.c` artefact — 8 findings inside the PDK's own
     `npn13G2V` PCell (klayout-tools #2688); once fixed upstream,
     re-running `layout/drc.sh` against an unchanged `layout/vco.gds` is
     expected to report `status: clean` — the §12 control is exactly that
     experiment, run early;
  2. klt 0.6.0's `--engine klayout` caps every zero-finding run at
     `coverage_unknown` because external-deck execution cannot be
     instrumented (klayout-tools #2697).
  Either landing turns one of the two reports of record into `clean` with no
  geometry change expected.
- **The scope caveat survives a future clean verdict.** The curated deck's 16
  deck-scope chapters and 37 rule-free drawn layers above remain the honest
  bound on what its "clean" would mean, and must be restated with the claim.
  The IHP-native report has no per-layer coverage at all (only its 590 rule
  categories), so its zero-findings claim carries the deck's own scope, and
  the optional-deck survey above (density fill deferred to chip assembly;
  maximal's PCell-internal `NW.e`) is the rest of the story.
- **Density fill is deferred by design**, not forgotten: the 9 fill-rule
  findings are recorded above and belong to the fill/chip-assembly phase.
