# sg13g2-vco layout — provenance record

Provenance for `layout/vco.gds`, the physical layout of the LC-VCO described by
`design/vco.sch` / `design/vco.spice`. This is the prose half of the record;
`layout/vco_manifest.json` is the machine-readable half, and every number in
this file is reproduced there with the measurement that produced it.

**This layout is not signed off.** It is the floorplan / placement / routing
deliverable (issue #60) plus the design-rule iteration on top of it (issue
#61); LVS closure is issue #62. **Since 2026-10-07 (§13) the IHP-native
DRC report of record is `status: clean`** under IHP's primary runset, with
an independently reviewed coverage assertion. That result has the scope
§13 states: it excludes density/fill, the "maximal" runset and antenna, and
it is block-level. The curated-engine report is kept as a diagnostic
carrying eight violations, all shown to come from the checking deck rather
than this layout. §12 is the record of the state before §13, including the
earlier `coverage_unknown` label. Read §12–§13 before citing any DRC claim,
and "What this record does *not* claim" before citing any claim at all.
**Since 2026-10-08 (§14) a device-aware LVS has been run, and its verdict
is `mismatch`.** IHP's own runset recognizes all 42 devices. It finds
exactly one difference, an extractor artefact on the mirrored spiral L1
(#80); the varactor `bn` difference it first found was a schematic error,
corrected in #79 (DR-005). `klt lvs` cannot run this compare
at the pinned release. Read §14 before citing any LVS claim.

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
- [13. DRC closure record (2026-10-07, issue #61)](#13-drc-closure-record-2026-10-07-issue-61)
- [14. LVS record (2026-10-08, issue #62)](#14-lvs-record-2026-10-08-issue-62)
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

> **Update (issue #79).** The schematic question is answered: it was not
> physically meaningful, and `design/vco.sch` now ties every varactor's `bn` to
> `0` (DR-005). The sentence above describes the state this section was
> written against; `design/vco.spice` now reads `XCVP1 VCTRL OUTP VCTRL 0
> sg13_hv_svaricap`, which is what the layout draws, and the LVS difference
> is gone (§14). The layout is unchanged.

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

- *(Superseded 2026-10-07 by §13: the IHP-native report is now `status:
  clean` inside §13's stated scope. The text of this bullet is kept as
  the earlier state.)* **Not DRC-clean *by label*.** Neither report of record says `status:
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
- *(Updated 2026-10-08 by §14: a device-level comparison has now been run,
  and it reports `mismatch`. The layout is still not LVS-clean. The text of
  this bullet is kept as the earlier state.)*
  **Not LVS-clean.** No device-level netlist comparison was run. Three known
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

## 13. DRC closure record (2026-10-07, issue #61)

*Appended. §12 is kept unchanged as the record of the earlier passes. Where
the two differ, this section describes the current state, and §12 records
how things stood before it.*

The IHP-native report of record now reads **`status: clean`**. The layout
did not change for this: `layout/vco.gds` is byte-identical,
`sha256:937e5b16c3b2bd5555138287a71f5d5673f91db4317a00016c986a568ca1b3c6`
on both sides of this change, and no geometry was touched. What changed is
that the run now **vouches for** its rule coverage through klt's opt-in
coverage assertion, and the vouched number was derived and checked
independently. §12's limit 2 (klt caps every zero-finding external-deck
run at `coverage_unknown`, klayout-tools#2697) is what this resolves. The
upstream fix is
[PR #2803](https://github.com/2AMLogic/klayout-tools/pull/2803), merged at
`70dee3b679a6451c5f4d830fb995c5eeb16084ee`.

### The report of record

| | |
|---|---|
| Report | `layout/drc/vco-drc-ihp.json` (unedited `klt drc` output; `klt drc --check` cheap mode: `match`) |
| Assertion record | `layout/drc/vco-drc-ihp-assertion.json` (written by `drc.sh`: rationale, tools, invocation, controls, limits) |
| Command | `klt drc layout/vco.gds --engine klayout --deck-file "$IHP_PDK_ROOT/libs.tech/klayout/tech/drc/ihp-sg13g2.drc" --deck-var threads=2 --expect-rule-categories 590 --format json` |
| klt | klayout-tools **source revision `70dee3b679a6451c5f4d830fb995c5eeb16084ee`** (reports `0.6.0+g70dee3b679a6`), installed into a throwaway venv under `layout/build/` by `layout/scripts/native_drc_env.sh`. No release carries `--expect-rule-categories` yet. |
| KLayout engine | **0.30.12** (`klayout_version_mismatch: false`), KLayout's own `klayout_0.30.12-1_amd64.deb` (sha256 `23480767fec91bc9…`, MD5 matches klayout.de's published value) **extracted, not installed** into the same scratch dir. The host's distro KLayout 0.28.16 cannot run this deck: §12's `absolute` NameError at `Gat.g` reproduced. |
| Deck | `ihp-sg13g2.drc` @ `sha256:0620b737538af7c86dfb7c6ca0ba3a38f8410b0d51412978ca977ea3df3fb693` (the same deck as §12) |
| Input | `layout/vco.gds` @ `sha256:937e5b16c3b2bd5555138287a71f5d5673f91db4317a00016c986a568ca1b3c6` |
| **Verdict** | **`status: clean`, exit 0, 0 violations, `coverage.known: true`, `coverage.unknown: []`, no `engine_deck_errors`** |
| **Assertion** | **`{"kind": "expected_rule_categories", "expected": 590, "observed": 590, "satisfied": true}`** |

`threads=2` is the only deck variable passed. In `ihp-sg13g2.drc` it sets
KLayout's worker count and gates no rule. It keeps the run modest on a
shared host, and klt records it in `provenance.deck.options`. Every
rule-group switch stays at the deck's default.

### Where 590 comes from (not from the run it vouches for)

The issue's 590 was the category count of the earlier `coverage_unknown`
run, so it was only a starting measurement. Copying it into the assertion
would make the assertion vouch for itself. The count was instead re-derived
from the **deck source** by `layout/scripts/ihp_deck_categories.py`. That
script is committed so the review can be re-run, and `drc.sh` re-runs it on
every invocation:

1. **Which files run.** `ihp-sg13g2.drc` declares no outputs itself. It
   `# %include`s 38 files: `layers_def.drc` plus 37 rule files (14 FEOL, 19
   BEOL, pin, offgrid, angle, forbidden).
2. **Which switches hold under this invocation.** No switch deck-vars are
   passed, so `tables = main`; FEOL, BEOL, OFFGRID, ANGLE, PIN, FORBIDDEN
   and RECOMMENDED are on; `PRECHECK_DRC` is off; the run mode is deep. Under
   those switches every included file's top-level guard is true. Inside the
   files, `unless PRECHECK_DRC` / `next if PRECHECK_DRC` and
   `if RECOMMENDED` are taken, and `if en_tiles` wraps no `output`. The
   script refuses any guard it has not been reviewed against.
3. **Which names are declared.** Every literal `output('NAME', …)` counts.
   Every interpolated name (`"#{base_name}_Offgrid"`, `"M#{met_no}.a"`,
   `"Pin.#{pin_rule}"`, …) is expanded over the loop domain its own file
   defines: a hash's keys, a `%w[]` list, or an array length plus a start
   index. The script holds 20 reviewed templates. An unreviewed template, or
   a reviewed one that has disappeared, is a hard error.
4. **Two categories depend on the stream, not the switches.** IHP declares
   them only when a data condition holds, so the script takes them as stream
   facts from `layout/scripts/ihp_deck_facts.py`. Those facts are read from
   the GDS and the deck's rule table, never from a DRC report.
   - `Seal.l` (`6_10_sealring.drc`): declared only if an EdgeSeal boundary
     (39/4) exists. This stream has **0** such shapes, so it is not declared.
   - `MIM.gR` (`6_11_mim.drc`): declared only if the total MIM (36/0) area
     exceeds `Mim_gR` = 174 800 µm². This stream has **13.3225 µm²**, so it
     is not declared. The category only exists when it is also a finding.

Result: FEOL 50, BEOL 117, pin 9, offgrid 193 (one `_Offgrid` per
non-excluded polygon layer), angle 210 (193 `_Acute`, 8 `_Angle90` for the
cut layers, 9 `_Angle45` for the routing layers), forbidden 11. That gives
**590 unique categories**, with no name shared between files. As a cross-check
beyond the count, the run's declared category **set** equals the statically
enumerated set name for name, and `drc.sh` gates on that set equality. A run
that dropped one category and gained another would therefore fail, even
though the count alone would pass.

The constant 590 is **pinned to the deck hash** in `drc.sh`. Any other deck
fails before the run, with an instruction to re-review the count, rather
than being re-vouched automatically.

### Negative controls

All controls ran in scratch (`layout/build/drc/`) and are re-run by `drc.sh`
every time. Their outcomes are recorded in the assertion record:

| Control | Result | What it shows |
|---|---|---|
| `--expect-rule-categories 591` (reviewed count + 1) | exit 1, **no report written**, "expected 591 … declared 590" | a wrong count fails and cannot produce a clean report |
| `--deck-var no_angle=true` with the reviewed 590 | exit 1, **no report written** | a gated-off rule group (the 210 angle categories) is caught |
| same invocation **without** the assertion | exit 4, `status: coverage_unknown`, 0 violations, `coverage.known: false` | the conservative default is intact; only the vouched run is `clean` |

`drc.sh` was also mutation-tested, using throwaway copies of the script.
Each mutated run failed and left the committed native report untouched:

| Mutation | `drc.sh` |
|---|---|
| Reviewed count set to 591 | fails: the static review disagrees, and the run's assertion fails |
| Reviewed deck hash altered | fails before running |
| Deck error injected (`--deck-var drc_json=<missing>`) | fails: klt refuses the partial report |
| PIN group gated off (`no_pin=true`) | fails: 581 declared, 590 vouched |
| New finding: a 1 nm off-grid Metal1 box added to a copy of the stream | fails: `NEW NATIVE FINDING(S) {'metal1_drw_Offgrid': 4}` |

### The curated diagnostic gates are unchanged and still discriminate

The curated `klt drc --deck sg13g2` report, the `Cnt.c` single-variable
control and the guard-ring intact/broken pairs (§12) are re-run unchanged.
All three reports are **byte-identical** to the committed ones: 8 ×
`activ.enclosing.cont.1` → `clean` with the `activ_mask` term supplied, and
all three ring layers `continuous` with a `broken` control. They still run
on the **tagged `klayout-tools==0.6.0` wheel** that CI pins. `drc.sh` now
refuses any other `klt` on `PATH` for them. A post-tag git build also
reports "0.6.0+g…" but ships a different curated deck (a different hash,
`released: false`). On this host such a build silently rewrote those
diagnostics on the first attempt, before this gate existed. The native run
alone uses the PR #2803 revision.

### Scope and limits: what `clean` here does and does not mean

- **The assertion is a documented claim, not a proof.** KLayout creates a
  rule category when that rule's `output(...)` is reached. Declaring all 590
  therefore shows that every rule's code in this runset ran on this
  invocation. It does not show that each rule faithfully transcribes IHP's
  design-rule manual.
- **Deck scope is IHP's *primary* runset only.** IHP's own runner
  (`run_drc.py`) runs two more decks by default and a third on request.
  None is covered by this report. All three were re-run for this record with
  the same klt revision and KLayout 0.30.12, each in scratch and without an
  assertion:

  | Deck | IHP default | This stream (2026-10-07 re-run) |
  |---|---|---|
  | `rule_decks/density.drc` | on | `violations`, 9: `AFil.g`, `GFil.g`, `M1.j`–`M5.j`, `TM1.c`, `TM2.c`. All are minimum *global* density rules. The block ships un-filled, and fill is deferred to chip assembly (§12 lists eight of these by name; this run confirms the ninth is `TM2.c`). |
  | `rule_decks/sg13g2_maximal.drc` | on | `violations`, 4 × `NW.e`, all in the PDK's own `SVaricap` / `SVaricap$1` PCell cells. This matches §12. The deck is self-declared untested, and the findings have **not** been re-diagnosed as artefacts in this pass. |
  | `rule_decks/antenna.drc` | opt-in | 0 findings, `coverage_unknown` |

  So "clean" here means clean under `ihp-sg13g2.drc`, not under IHP's full
  default runner flow.
- **Block-level, not chip-level.** The sealring, pad, solder-bump and
  copper-pillar rules are declared and pass vacuously, because this block
  carries none of those structures.
- **The `deck` field** of the report records this host's absolute PDK path.
  The deck `content_hash` is the identity to compare across hosts (as in
  §12).
- **No LVS claim.** LVS closure and the signoff-manifest refresh are #62.
  `.github/workflows/signoff.yml` still pins `klayout-tools==0.6.0`, and
  that pin is not changed here. The signoff manifest cites no `layout/drc/`
  artifact, so its drift check is unaffected.

### Tool friction filed (per the friction protocol)

- [2AMLogic/klayout-tools#2806](https://github.com/2AMLogic/klayout-tools/issues/2806):
  klt offers no way to derive or check the `--expect-rule-categories` value
  independently of the run being vouched for. The assertion compares a count
  rather than a set, and categories declared conditionally on the input data
  make the count input-dependent. `ihp_deck_categories.py` exists because of
  this gap.
- [2AMLogic/klayout-tools#2689](https://github.com/2AMLogic/klayout-tools/issues/2689)
  (open): hit again. The engine runs the standalone `klayout` on `PATH` and
  cannot use the KLayout 0.30.12 that klt's own venv ships, so a second
  KLayout had to be provisioned. A recurrence note was added to the issue.

## 14. LVS record (2026-10-08, issue #62)

*Appended. §§1–13 are unchanged. The layout did not change for this
section: `layout/vco.gds` is still
`sha256:937e5b16c3b2bd5555138287a71f5d5673f91db4317a00016c986a568ca1b3c6`, so
§13's DRC record still applies to it.*

**The verdict of record is `mismatch`.** This section is the record of an
honest device-aware compare. It does not report LVS closure.

> **Update (issue #79, 2026-10-09).** This section was first written with two
> differences. The first, the 32 varactors' `bn` pin, was a schematic error:
> `design/vco.sch` tied it to the tank node, the layout (correctly) to the
> p-substrate. The schematic is corrected (DR-005), `design/vco.spice` is
> regenerated, and `layout/lvs.sh` was re-run: **the `bn` difference is
> gone**. One difference remains (spiral L1's terminal order, #80). The text
> below is edited in place to the new state; the pre-#79 state is recoverable
> from git history and is summarised once here: the record compare then
> paired 5 of 13 nets and 6 of 43 device pairs, and control C1 (`bn` moved in
> a scratch reference) removed all 32 varactor differences. It now pairs
> **7 of 10 nets and 42 of 43 device pairs**, and the single unpaired device
> pair is L1. The layout and the runset are unchanged (`layout/vco.gds` and
> the runset hash are byte-for-byte what they were); only the reference moved.

| | |
|---|---|
| Runner | `layout/lvs.sh` (fails on any verdict drift; two consecutive runs write byte-identical files) |
| Engine | KLayout **0.30.12** LVS (`NetlistComparer`), running **IHP-Open-PDK's own runset** `libs.tech/klayout/tech/lvs/sg13g2.lvs` through its `run_lvs.py` driver (flat mode, simplify on, strict top-port mode) |
| Runset identity | `sha256:fd11fced5b0bd5ee0bb66b700acbe359f23c30c5900b16e5f647ed9a430dcc09`, a hash over `sg13g2.lvs`, `run_lvs.py` and all 43 `rule_decks/*.lvs`, pinned in `lvs.sh` |
| Layout | `layout/vco.gds` @ `sha256:937e5b16…` |
| Reference | `layout/lvs/vco-reference.cir`, **derived** from `design/vco.spice` @ `sha256:090983d6…` (below; after #79) |
| Compare of record | `layout/lvs/vco-lvs-ihp.json`, read back from KLayout's own `.lvsdb` cross-reference by `scripts/lvsdb_summary.py` |
| Run record | `layout/lvs/vco-lvs-record.json`: tools, invocation, controls, the klt attempt and the limits |
| Extracted netlist | `layout/lvs/vco-extracted.cir` (the runset's own writer; only its date-stamp line is removed) |
| **Device census** | **42 of 42 devices recognized**, plus one `ptap1` guard-ring tie. The per-class census is identical on both sides: `cap_cmim` 1, `inductor` 2, `npn13G2v` 4, `ptap1` 1, `rppd` 3, `sg13_hv_svaricap` 32 |
| **Status** | **`mismatch`**: exactly one class of difference (spiral L1's terminal order), isolated below |

`run_lvs.py` exits 0 when the netlists do **not** match, and its log says
only "Netlists don't match". The verdict is therefore never taken from its
exit status. It is read from the comparison database KLayout writes.

### Why IHP's runset and not `klt lvs`

§9 recorded at klt 0.6.0 that the curated `sg13g2` extraction recognizes
1 of this block's 42 devices. This was **re-verified, not inherited**,
against the tagged `klayout-tools==0.6.0` wheel CI pins and against current
`main` (`3a75c3ae705b`):

| klt | `klt extract --deck sg13g2` | `klt lvs` (inline extraction, `reference.form: "subckt-call"`, `reference.deck: "sg13g2"`) |
|---|---|---|
| 0.6.0 (tagged) | `{"cap_cmim": 1}`, 7 nets | exit 1: `subcircuit 'inductor' is not a known device for the requested deck` |
| `main` @ `3a75c3ae` | `{"cap_cmim": 1}`, 7 nets | the same refusal |

`reference.device_map` has no kind for a 3-terminal inductor or a
4-terminal varactor, and the HBT class was declined upstream (#1232). A
netlist extracted by the PDK runset cannot be fed to `klt lvs` as
`layout.netlist` either. The plain SPICE reader drops its HBT cards with
only a `Line ignored` warning, and it errors on its 3-node `rppd` cards.
**So at the pinned release no `klt lvs` report of this block can exist, and
neither can the `power_connectivity` block that lives in one.** Filed as a
generic tool gap:
[2AMLogic/klayout-tools#2849](https://github.com/2AMLogic/klayout-tools/issues/2849)
(a native-runset LVS engine, symmetric with `klt drc --engine klayout`).
`lvs.sh` re-runs the klt attempt every time and fails if klt stops refusing,
so the day the gap closes is visible.

IHP's runset, by contrast, recognizes every device family in this block. It
uses its own HBT extractor (`CustomBJTExtractor`), a 4-terminal varactor
class (`G1 W G2 SUB`), an inductor class with a substrate terminal, and a
3-terminal `rppd`. The same KLayout 0.30.12 that §13 provisioned (KLayout's
own `.deb`, extracted into gitignored scratch by
`scripts/native_drc_env.sh`) runs it.

### The reference: derived, traced, never edited

`design/vco.spice` is a simulation deck. `scripts/lvs_reference.py` rewrites
it into the CDL form the runset reads. It applies only the six
transformations below. Each output line is traced to its source line in
`layout/lvs/vco-reference.json`, which also records the source file's
sha256. `design/vco.spice` itself is only read.

| | Transformation | Why it is justified |
|---|---|---|
| T1 | drop `VSUP`/`VCT`, `.save`/`.lib`/`.include`/`.ic`, the `.control` block | testbench-only content with no layout counterpart (§4) |
| T2 | wrap in `.SUBCKT vco` with the nine named nets as ports | the layout labels all nine on pin layers (§9), so each one is a name-anchored compare point |
| T3 | `X` device cards → `Q`/`L`/`C` cards; `El`→`le`, `we=120.0n`, `m=Nx` | **the PDK's own mapping**: each `sg13g2_pr/*.sym` symbol's `lvs_format`. Cross-checked against xschem's own LVS-mode netlist of `design/vco.sch`: **agrees on all 39 cards** (nodes, model, parameters) |
| T4 | ideal `R` → `rppd`, w = 1 µm, l from `floorplan.rppd_length_um()` on the 5 nm grid | the physical device class §5 chose. The R-to-length law is the generator's own, measured from the PCell; 5 nm is the grid `snap_grid.py` places every drawn vertex on (rule 3.1) |
| T5 | substrate pins the schematic ties to `0` (HBT 4th, inductor 3rd, varactor 4th `bn` since #79, `rppd` body) → net `sub`; add the guard-ring tie `ptap1 0 sub` with A = 1084 µm², P = 1084 µm | the runset extracts the p-substrate as its own net, joined to `0` only through the `ptap1` tie. ngspice models ignore the tie, so the schematic writes the substrate as `0`. The tie's A/P come from the generator's ring spec (`floorplan.py` `RING`, `RING_W`: four abutting bars = one annulus), **not** from the extraction |
| T6 | substrate pins the schematic ties to anything **other** than `0` are left exactly as written | before #79 this was the varactor `bn`, kept visible rather than reconciled. Since #79 no pin falls under T6; the rule stays so a future disagreement is still shown, not hidden |

T4 and T5 restate the layout phase's own physical choices. Their parameters
are therefore checked against the generator's intent, not against the
schematic, which has no physical resistor or substrate to compare against.
They match the extraction exactly (`l` = 7.47 / 15.205 / 79.05 µm, tie
A = 1084 µm², P = 1084 µm). The runset also measures the spirals as
w = 8.215, s = 3.734, d = 142.106 µm against the card's 8.22 / 3.74 /
141.975, inside the runset's own 5 % inductor tolerance.

### Exactly one difference, isolated by a single-variable control

KLayout's pairing degrades under ambiguity, so the record compare's raw
counts (7 of 10 nets, 42 of 43 device pairs) can overstate the damage. A
scratch-only diagnostic reference, changing one thing, shows what actually
differs. It comes from `lvs_reference.py`'s `--swap-inductor=` switch and is
never committed.

| Control | Reference change (scratch) | Verdict | What remains |
|---|---|---|---|
| record | none | `mismatch` | **one** device: spiral L1, terminals (`OUTP`, `VDD`) in the layout vs (`VDD`, `OUTP`) in the reference |
| C1 | L1's two winding terminals swapped | **`match`** | nothing: 43/43 device pairs, 10/10 nets, 9/9 pins |

So the layout differs from the derived reference in this way and **no
others**. (Before #79 a second control, "C1: `bn` moved to the substrate",
isolated the varactor difference; it is retired, because the reference of
record now carries that change itself. `lvs.sh` additionally gates that the
record's only unpaired device pair is L1, so a re-introduced `bn` difference
fails the run.)

**Resolved by #79: varactor `bn` (32 devices).** The runset's `SUB` terminal
of every varactor is the p-substrate. `design/vco.spice` used to tie it to
`OUTP`/`OUTN`, which the layout cannot do (§6) and which was never physically
meaningful: the `sg13_hv_svaricap` subcircuit's 4th pin is annotated
*Substrate* in the PDK's own header. It now ties it to `0`. This was more
than an LVS formality: with `bn` on the tank node the PDK's `dsubw`
well-to-substrate junction was shorted out, and the drawn layout *does* hang
that junction on the tank, so every simulation run on the old netlist omitted
a junction on both tank nodes. Its size is now measured:
`sim/bn-substrate-tank/` (a tank-level A/B) puts it at **-22 to -23 % on
f0 and -27 % on tank Q** at band centre, a result with consequences for the
spec bands; see DR-005 and `design/README.md`. The reference sha above is the
only artefact of the change in this directory.

**Remaining: spiral L1 terminal order, an extractor artefact, tracked as #80.** The
stream's own labels put `LA` on `VDD` for **both** spirals, and `LB` on
`OUTP`/`OUTN`, exactly as the schematic says. The two spiral cells are
mirror images (`LA` at x = +25.315 µm in one, −25.315 µm in the other), and
L1 is placed `m90`. The runset finds the two ports by those labels
(`ind_derivations.lvs`), but then orders them **by x position**
(`custom_extractor.lvs`, `define_and_sort_terminals` → `sort_polygons`). Its
inductor class clears terminal equivalence (`custom_devices.lvs`,
`DeviceCustomInd`), so a mirrored spiral always extracts with its windings
reversed. The fix belongs to the runset (or to a reviewed accommodation in
this flow), not to the layout. The runset is IHP's, not klt's, so it is not
filed at klayout-tools. #80 holds the options.

### Supply pairing

Checked explicitly, not inferred from the top-level status:

| | `VDD` | `0` | substrate |
|---|---|---|---|
| record compare | **not paired** (`LA,VDD` vs `VDD`, perturbed by L1's terminal order) | paired | **not paired** (`$1` vs `SUB`; still perturbed, by the same L1 difference) |
| control C1 | paired 1:1 | paired 1:1 | paired 1:1 |

`LA,VDD` is one net carrying two labels, the spiral PCell's `LA` text and the
`VDD` pin label. It is not two nets.

### Negative controls: the compare rejects a broken layout

Each control is a scratch copy of the stream with **one** top-level instance
removed (`scripts/lvs_break.py`). Each is compared against the C1 reference,
which matches the intact stream, so a `match` would mean the compare cannot
see the break.

| Control | Change | Verdict |
|---|---|---|
| N1 (supply) | `VS_VDD_REF` via ladder removed: RREF's `VDD` end detached from the `VDD` strap | **`mismatch`** (rejected) |
| N2 (signal) | `VS_Q1B` via ladder removed: Q1's base detached from `OUTN` | **`mismatch`** (rejected) |
| N3 (device) | `C1` MIM instance removed | **`mismatch`** (rejected) |

`lvs.sh` was also mutation-tested with throwaway copies of the script. A
wrong runset hash fails before running. Pointing C1 at the reference of
record fails the C1 gate. Both left the committed record untouched.

### Item 1/2 sources, re-verified for this record (2026-10-08)

- **Layout reproducibility (item 2).** A cold regeneration on this Linux host
  (`layout/generate.sh`, every stage except `verify`, into an empty build
  directory) with the tagged `klt 0.6.0` and KLayout 0.30.12 produced a
  stream **byte-identical** to the committed one: `sha256:937e5b16…` on both
  sides. §2's record was made on a different host (macOS), so this is a
  cross-host reproduction, not a re-statement.
- **Netlist freshness (item 1).** `design/netlist.sh --check` (xschem 3.4.7,
  the PDK symbol library): `design/vco.spice is current with design/vco.sch`.
  Re-checked for #79 with xschem 3.4.4 (the only xschem on the host that
  re-ran it): current.
- **T3 cross-check against xschem's LVS netlist (limit, #79).** The 39-card
  agreement recorded above needs xschem >= 3.4.7 (`set lvs_netlist 1` and the
  symbols' `lvs_format`). The #79 re-run was on xschem 3.4.4, which ignores
  both and writes the simulation X-cards, so the cross-check was **not
  re-run**: `lvs.sh` detects that, records `skipped`, and carries the earlier
  agreement forward labelled as not re-run (`reference_crosscheck_xschem.
  last_rerun_agreement` in `vco-lvs-record.json`). #79's only change to T3's
  inputs is the 4th node of the 32 varactor cards; re-run on xschem >= 3.4.7
  to refresh.

### What this means for the signoff manifest

- **Item 2 is cited** (`signoff/manifest.json`). It cites the IHP-native DRC
  envelope `layout/drc/vco-drc-ihp.json`, pinned to the stream's content
  hash. `klt signoff` grades item 2 on any passing native envelope and cannot
  check relevance. The envelope is the freshness anchor (it goes stale the
  moment the stream changes). **The claim it stands for is §2 plus the
  cross-host reproduction above**, not anything about DRC.
- **Item 1 is not cited.** No passing klt-native envelope is pinned to
  `design/vco.spice`. Its freshness check needs xschem and a PDK, which the
  PDK-free signoff CI does not have. Citing an unrelated envelope would make
  the row green without evidence.
- **Item 4 is not cited.** No `klt lvs` report can exist (above), and the
  device-aware verdict is `mismatch`.

### Limits

- One engine. No second, independent extractor recognizes this block's HBT,
  varactor and inductor devices, so the result is not cross-checked by a
  second toolchain.
- The reference is derived. T4/T5 are the layout phase's own choices
  restated (see the table).
- A topological and parameter compare only. No parasitic, matching or
  geometric check.
- The runset is IHP's, at the hash above. A PDK update changes it and fails
  `lvs.sh` until the transformations and expectations are re-reviewed.

### Tool friction filed (per the friction protocol)

- [2AMLogic/klayout-tools#2849](https://github.com/2AMLogic/klayout-tools/issues/2849):
  no device-aware `klt lvs` path when a PDK's own KLayout LVS runset
  recognizes devices the curated deck lacks. There is no native-runset
  engine, and runset netlists cannot be read as `layout.netlist`.
- [2AMLogic/klayout-tools#2850](https://github.com/2AMLogic/klayout-tools/issues/2850):
  `klt extract` without `-o` writes its netlist next to the input stream, so
  a read-only census run leaves an untracked `<block>.spice` in `layout/`. It
  happened here once, was removed, and `lvs.sh` now passes `-o` into scratch.

### 14.5 Re-run after #79, with the newest klt release (2026-10-09, issue #62)

*Appended. The text above stands; this records a fresh run and a status
check of the blockers to `match`. Nothing in the layout, the schematic, the
runset or the derived reference changed.*

**Fresh run.** `layout/lvs.sh` was re-run from a clean worktree of `main`
@ `bec98b4` on a Linux (Ubuntu 24.04) host, twice. Both runs exited 0, and
the second wrote byte-identical files.

- Inputs: `layout/vco.gds` @ `sha256:937e5b16…` and `design/vco.spice` @
  `sha256:090983d6…`, the same as above. The runset hash is the same
  (`fd11fced…`).
- Re-derived reference `layout/lvs/vco-reference.cir` (`sha256:f047a24b…`),
  compare of record `vco-lvs-ihp.json` and extraction `vco-extracted.cir`:
  **byte-identical** to the committed files.
- Verdict: **`mismatch`**, unchanged. 42/42 devices recognized, with the
  same census on both sides. The only unpaired device pair is L1's terminal
  order (#80). Control C1 gives `match`. N1, N2 and N3 are all rejected.
- `design/netlist.sh --check` (xschem **3.4.7**): `design/vco.spice is
  current with design/vco.sch`.

**T3 cross-check re-run against the post-#79 netlist.** This host has
xschem 3.4.7, so the cross-check that the #79 run had to skip (above, "Item
1/2 sources") is now **re-run**, not carried forward. xschem's own LVS-mode
netlist of `design/vco.sch` **agrees with the derived reference on all 39
Q/L/C cards** (nodes, model, parameters), and that includes the re-pointed
varactor `bn`. `vco-lvs-record.json` → `reference_crosscheck_xschem` now
holds the live result in place of the `skipped` + `last_rerun_agreement`
block.

**The klt gap at the newest release.** `klayout-tools` 0.7.0 shipped after
§14 was written. `lvs.sh` now runs a second klt leg against the tagged 0.7.0
wheel, in a throwaway venv (`layout/build/klt-0.7.0`). It does not use the
host's klt, and it does not move the CI pin. That leg fails the run if 0.7.0
stops refusing. Measured:

| klt 0.7.0 route | Result |
|---|---|
| `klt lvs`, inline curated extraction, `reference.form: "subckt-call"` (the §14 request) | exit 1: `subcircuit 'inductor' is not a known device for the requested deck` |
| `klt lvs`, `layout.netlist` = the runset's own device-aware extraction of this stream, reference = `vco-reference.cir` | exit 1: `could not parse layout netlist …: Can't find a value for a R, C or L device` (the first 3-node `rppd` card) |
| `klt extract --deck sg13g2` | `{"cap_cmim": 1}`, 7 nets (1 of 42 devices) |

So 2AMLogic/klayout-tools#2849 is still open in 0.7.0. No `klt lvs` report,
and therefore no `power_connectivity` block, can exist for this block on any
released klt. The upstream operator ruling of 2026-10-08 on #2849 chose a
native-runset engine as the path for this case. The checklist and grader
change that would make such a report count for T1 is
2AMLogic/klayout-tools#2870, which depends on #2849.

**State of the two blockers to the #62 match criterion (2026-10-09):**

1. **Spiral L1 terminal order (#80): open, and it needs a decision.** The
   runset on IHP-Open-PDK's `dev` branch still orders inductor ports by x
   (`custom_extractor.lvs`, `define_and_sort_terminals` → `sort_polygons`,
   checked through the GitHub API on 2026-10-09). An upstream fix is not
   available to pin. The in-repo options are listed in #80. This increment
   does not choose one, and the reference of record stays unreconciled. The
   other option is a post-extraction re-ordering by the `LA`/`LB` labels. It
   is a change to the comparison flow that #80 asks to have reviewed first,
   so this increment does not ship it as the record.
2. **No `klt lvs` envelope (klayout-tools#2849): open** at both 0.6.0 and
   0.7.0 (above).

**Not done here, and why.** The derived reference was not edited to swap
L1. That would fit the reference to the layout. It is only a scratch control
(C1), never the record. The signoff manifest gains no citation from this
run. Item 4 has neither a passing compare nor a `klt`-format envelope.
Item 1 still has no `klt`-native envelope pinned to `design/vco.spice`
(klayout-tools#2887 tracks the missing evidence form). Item 2's citation is
unchanged, because the stream did not change. DRC was not re-run, because
the stream did not change (§13 still applies to `sha256:937e5b16…`).
