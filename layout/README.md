# layout/

Layout (klayout-tools driven) and DRC/LVS signoff artifacts.

## Contents

| Path | What it is |
|---|---|
| `vco.gds` | The LC-VCO layout: floorplan, device placement and full routing |
| `vco_manifest.json` | Machine-readable provenance + measured acceptance evidence |
| `PROVENANCE.md` | **The provenance record** — tool, method, device mapping, every design decision and how each claim was measured |
| `generate.sh` | Regenerates both artifacts from the PDK, end to end, headless |
| `drc.sh` | Re-runs the design-rule and guard-ring evidence; fails on any verdict drift |
| `drc/` | The committed `klt drc` / `klt ring-check` reports (`PROVENANCE.md` §12) |
| `scripts/` | The generation stages `generate.sh` drives, plus `drc.sh`'s two controls |
| `build/` | Scratch (gitignored, like `sim/build/` and `design/build/`) |

## The layout

`vco.gds` is the physical layout of the circuit in `design/vco.sch` /
`design/vco.spice`. Top cell `vco`, **0.241835 mm²** (610.256 × 396.285 µm),
dominated by the two `p11` spirals.

42 devices, all PDK PCell instances — no hand-drawn device geometry:

| Device | Count | PCell |
|---|---|---|
| Spiral inductor | 2 | `SG13_dev/inductor2` |
| MIM cap | 1 | `SG13_dev/cmim` |
| MOS varactor | 32 | `SG13_dev/SVaricap` (16 per side) |
| SiGe HBT | 4 | `SG13_dev/npn13G2V` |
| Resistor | 3 | `SG13_dev/rppd` — see `PROVENANCE.md` §5 for why |
| Guard-ring tap | 4 | `SG13_dev/ptap1` |
| Via ladder | 52 | `SG13_dev/via_stack` |

All 9 nets of `design/vco.spice` are routed and labelled: `VDD`, `OUTP`,
`OUTN`, `VCTRL`, `TAIL`, `TE`, `NBIAS`, `RE`, `0`.

The tank is **two independent 3-terminal spirals sharing `VDD`**
(`XL1 VDD OUTP 0`, `XL2 VDD OUTN 0`), not one centre-tapped differential coil.

## How it was generated

Fully scripted and headless — no GUI step, no hand-edited geometry:

```sh
layout/generate.sh
```

`klt gen --pdk-pcell` instantiates each PDK PCell, `klt gen-compose` places the
blocks and routes the nets it owns, `klt draw` emits the explicitly drawn metal,
and `klt extract` reads the result back to check every net. Individual stages
are runnable via `LAYOUT_STAGES`; see `PROVENANCE.md` §2.

`klt gen --pdk-pcell` needs a PDK submodule overlay to reach `SG13_dev` in a
stock tarball install; `scripts/pdk_env.sh` reuses the committed workaround at
`sim/inductor-model/em-extraction/scripts/setup_pdk_overlay.sh` and never
mutates the shared PDK install (`PROVENANCE.md` §3).

## Status: drawn and design-rule iterated, not signed off

- **DRC (issue #61) — run, and the report of record is NOT `status: clean`.**
  It is `violations`, 8, all of one rule, all inside the PDK's own `npn13G2V`
  PCell. `PROVENANCE.md` §12 shows — with the same deck, re-run against a
  control stream — that every one of them is an artefact of klt's curated
  deck approximating IHP's `Cnt.c` by dropping its `activ_mask` term, and not
  a defect in this layout (filed upstream as `klayout-tools#2688`). One real
  violation *was* found and fixed in place: two `metal1.space.1` hits from
  the VCTRL tap ladders. **`signoff/design-evidence-tiers.md` item 3 is not
  met and must not be cited.** The deck also covers only 16 DRM chapters and
  has no rule for 37 of the layers this stream draws — §12 discloses both.
- **Guard-ring continuity is verified on Activ and pSD** against a negative
  control, and explicitly **not** verified on Metal1 (§12).
- **LVS closure is issue #62** — not run here. Three deliberate
  schematic/layout differences are already recorded for it in `PROVENANCE.md`
  (the `rppd` vs ideal `R` substitution, the varactor `bn` substrate tie, and
  the `VSUP`/`VCT` testbench sources with no layout counterpart).

No electrical, EM or phase-noise claim is made or implied by this layout.
Read `PROVENANCE.md` §11 before citing any of it as evidence.
