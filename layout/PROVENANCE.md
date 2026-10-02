# sg13g2-vco layout — provenance record

Provenance for `layout/vco.gds`, the physical layout of the LC-VCO described by
`design/vco.sch` / `design/vco.spice`. This is the prose half of the record;
`layout/vco_manifest.json` is the machine-readable half, and every number in
this file is reproduced there with the measurement that produced it.

**This layout is not signed off.** It is the floorplan / placement / routing
deliverable (issue #60) plus the design-rule iteration on top of it (issue
#61); LVS closure is issue #62. **The DRC report of record is not `status:
clean`** — it carries eight violations of one rule, all of them demonstrated
to be an artefact of the checking deck rather than of this layout. Read
§12 before citing any DRC claim, and "What this record does *not* claim" at
the end before citing any claim at all.

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
| Source tool | `klt` (klayout-tools) `0.6.0+gaf8d6c54312e` |
| Read-back helper | `klayout` 0.28.16 on `PATH` (klt bundles its own KLayout 0.30.12 for `extract` and for the curated DRC engine) |
| PDK | IHP-Open-PDK `ihp-sg13g2`, install at `$IHP_PDK_ROOT` (this run: `~/share/pdk/ihp-sg13g2`) |
| Schematic of record | `design/vco.sch` |
| Netlist of record | `design/vco.spice` |
| Generation method | **fully scripted, headless** — no GUI step, no hand-edited geometry |

Two KLayout versions appear deliberately. The repo's `klayout` on `PATH` runs
the two read-back helpers (`measure_ports.py`, `verify.py`); `klt extract`
uses the KLayout that ships inside the pinned `klayout-tools` wheel. Both are
recorded in the manifest so a version drift shows up as evidence rather than
silently.

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
| `devices` | `klt gen --pdk-pcell` once per distinct PDK PCell call |
| `ports` | measures each generated stream's own terminal geometry (`klayout -zz -r`) |
| `requests` | emits the `klt gen-compose` / `klt draw` request documents |
| `compose` | runs them: 2 varactor banks, the bias core, the drawn wiring, the top cell |
| `connectivity` | `klt extract`s the result and checks every net |
| `verify` | reads the composed stream back and writes the manifest |

```sh
LAYOUT_STAGES="requests compose verify" layout/generate.sh
```

The design-rule evidence is a **second, separate script**, because none of it
instantiates a PCell and so none of it needs the PDK overlay §3 describes — it
only reads the committed stream:

```sh
layout/drc.sh
```

It rewrites `layout/drc/*.json` and **exits non-zero if any verdict drifts
from the one §12 records**, so a PDK, PCell or deck change that moves a result
fails the run instead of quietly rewriting the evidence.

### The flow is deterministic — verified, not asserted

A **cold run from an empty build directory** was re-run against the committed
artifact and produces a **byte-identical** stream:

```
$ LAYOUT_BUILD_DIR=/tmp/layout-cold layout/generate.sh      # from scratch
$ sha256sum /tmp/layout-cold/vco.gds layout/vco.gds
c8c3485079d4634edd96cc5b459422c96706c18e48a5a896db2a009ba132333a  /tmp/layout-cold/vco.gds
c8c3485079d4634edd96cc5b459422c96706c18e48a5a896db2a009ba132333a  layout/vco.gds
```

`layout/vco.gds` @ `sha256:c8c3485079d4634edd96cc5b459422c96706c18e48a5a896db2a009ba132333a`.
So the committed GDS is exactly what the committed script produces from the
committed PDK — this is a *reproducibly generated* artifact in the sense
`signoff/design-evidence-tiers.md` item 2 grades above "documented provenance",
not merely a hand-made artifact with a description attached. A PCell, PDK or
`klt` change that alters the geometry will change that hash.

**No geometry in this flow is hand-drawn as a literal.** Every device is a PDK
PCell instance; every via ladder is a `SG13_dev/via_stack` PCell call (52 of
them), so no via or via-enclosure rectangle is authored here; the guard ring is
four `SG13_dev/ptap1` bars. The explicitly drawn metal (§8) is expressed as
rectangles whose coordinates are *derived from measured device terminal
positions*, not written out as constants — so it follows the devices if a PCell
changes rather than silently detaching from them.

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

Three nets are left to klt's router; six are drawn explicitly. The split is a
tool-capability boundary, and both sides are stated so a reviewer need not
infer which metal came from where.

**Routed by `klt gen-compose` (`connectivity[]`, in the `core` composition):**
`TE`, `RE`, `NBIAS` — the three nets that live entirely inside that
composition's own clear region.

**Drawn explicitly via `klt draw` (the `wiring` cell, 76 shapes, 9 labels):**
`VDD`, `OUTP`, `OUTN`, `VCTRL`, `TAIL`, `0`. Each for one of two reasons:

- **(a) it terminates on a device pad the sg13g2 layer-role table cannot
  name** — the spirals' TopMetal1 pins, the MIM cap's Metal5/TopMetal1 plates;
  the router cannot target a pad it has no role for.
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
| `SG13_dev/via_stack` | — | 52 (every via ladder in the block) |

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

- **Not DRC-clean.** The report of record is `status: violations`, not
  `status: clean`, so `signoff/design-evidence-tiers.md` item 3 is **not**
  satisfied and this layout must not be cited for it. Every remaining
  violation is demonstrated in §12 to be an artefact of the checking deck
  rather than of this layout — but a demonstration is not a clean report, and
  the two must not be conflated. The deck also covers only part of the DRM
  (§12 quotes its `deck_scope` and its 37 rule-free drawn layers), so even a
  clean verdict from it would not have been a full design-rule result.
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
| Deck | `sg13g2` @ `sha256:89ba7c9ee605174b50c4efffe8c601aa4449007038b17a3d9df63ffd8547da13` |
| Input | `layout/vco.gds` @ `sha256:c8c3485079d4634edd96cc5b459422c96706c18e48a5a896db2a009ba132333a` |
| Tooling | `klt 0.6.0+gaf8d6c54312e`, bundled KLayout 0.30.12 |
| **Status** | **`violations`, 8 — NOT `clean`** |
| Rule counts | `{"activ.enclosing.cont.1": 8}` |

**A reproducibility caveat, stated rather than glossed.** The build used is a
*post-tag* build: `klt version` reports `git_tag: null`, `is_release: false`,
and the report's own `provenance.deck.released` is correspondingly `false`.
The run was repeated through `uvx --from "klayout-tools==0.6.0" klt drc …` to
pin it to the released wheel and returned the identical verdict and the
identical deck content hash — **but that invocation resolved to the same
`0.6.0+gaf8d6c54312e` build**, so it is a repeat, not an independent
cross-check against the tagged `v0.6.0` wheel that `.github/workflows/
signoff.yml` installs. The deck hash above is the thing to pin against; if a
later run on a genuinely tagged `v0.6.0` reports a different deck hash, this
report must be re-rendered rather than reinterpreted.

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

One real defect, found by the first run against the layout #60 committed and
fixed in place in the same generator (`layout/scripts/floorplan.py`) rather
than in a parallel copy:

| Rule | Count | Where | Cause | Fix |
|---|---|---|---|---|
| `metal1.space.1` | 2 (one per bank) | `VS_VCTRL_P1` / `VS_VCTRL_N1` | the inboard VCTRL tap's `vs_m1_m3` ladder sat at a round `BANK_X0 + 2.0 µm`, leaving its 0.70 µm Metal1 pad **0.09 µm** from the adjacent `SVaricap` cell's own gate metal — half the 0.18 µm `M1.b` minimum | the tap's x is now **derived from the measured `G1` port box and the measured via-stack pad width**, centred in the gap between two adjacent cells' gate metal, giving **0.32 µm** each side; the clearance is `assert`ed against `M1_SP`, so a PCell or pitch change fails generation instead of silently reopening the violation |

Nothing else about the layout changed: same devices, same nets, same
floorplan, same 610.256 × 396.285 µm bounding box, and `generate.sh`'s
connectivity stage still reports the same nine distinct nets with
`dead_metal = 0` (§9). The stream hash changed because the stream changed.

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

### Why the PDK's own deck was not used instead

`klt drc --engine klayout` would run IHP's deck of record, which implements
`Cnt.c` correctly. It does not run here: that engine shells out to the
standalone `klayout` on `PATH`, which is **0.28.16**, and IHP's deck aborts
part-way through at rule `Gat.g` with

```
ERROR: undefined local variable or method `absolute' for DRCEngine
  rule_decks/feol/5_8_gatpoly.drc:70
```

— a DRC-DSL metric newer than that KLayout. klt's handling is correct and not
the gap: it refused the partial report rather than reporting its zero
violations as a clean verdict. The gap is that klt *bundles* KLayout 0.30.12
(it is what the curated engine and `klt extract` run) but `--engine klayout`
cannot use it, and nothing preflights the PATH binary's feature level against
the deck's. Filed as
[2AMLogic/klayout-tools#2689](https://github.com/2AMLogic/klayout-tools/issues/2689).
Installing a newer standalone KLayout on the build host was not an option
available to this phase.

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
| Metal1 `8/0` | `continuous` | `continuous` | **not evidence** |

The tap ring itself — the p+ diffusion that actually ties the substrate to `0`
— is verified on both of its layers. **The Metal1 row is reported and
explicitly not claimed**: its negative control also passes, which means a
`continuous` verdict on `8/0` inside that window can be produced by core
routing that merely shares the layer, with the ring's own Metal1 open. `klt
ring-check` has no way to scope its layer set to a cell or instance subset, so
there is no way to ask the question about the ring's Metal1 alone; filed as
[2AMLogic/klayout-tools#2690](https://github.com/2AMLogic/klayout-tools/issues/2690).
Treat Metal1 ring continuity as **unverified**, not as passing.

### What this leaves for #62 and beyond

- **Item 3 of `signoff/design-evidence-tiers.md` is not met** and no citation
  of this layout should claim it. The blocker is upstream (klayout-tools
  #2688), not in this repo: once the curated deck carries `Cnt.c`'s
  `activ_mask` join, re-running `layout/drc.sh` against an unchanged
  `layout/vco.gds` is expected to report `status: clean` — the control above
  is exactly that experiment, run early.
- **The scope caveat survives a future clean verdict.** Even then, the 16
  deck-scope chapters and 37 rule-free drawn layers above remain the honest
  bound on what "clean" would mean, and must be restated with the claim.
- **Metal1 guard-ring continuity remains unverified** (klayout-tools #2690).
