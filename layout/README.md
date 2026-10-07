# layout/

Layout (klayout-tools driven) and DRC/LVS signoff artifacts.

## Contents

| Path | What it is |
|---|---|
| `vco.gds` | The LC-VCO layout: floorplan, device placement and full routing |
| `vco_manifest.json` | Machine-readable provenance + measured acceptance evidence |
| `PROVENANCE.md` | **The provenance record** — tool, method, device mapping, every design decision and how each claim was measured |
| `generate.sh` | Regenerates both artifacts from the PDK, end to end, headless |
| `drc.sh` | Re-runs the design-rule evidence on **two engines** (IHP's own runset, which produces the report of record, and klt's curated deck as a diagnostic) plus the guard-ring checks. Fails on any verdict drift |
| `drc/` | The committed `klt drc` / `klt ring-check` reports and the native run's assertion record (`PROVENANCE.md` §12–§13) |
| `scripts/` | The generation stages `generate.sh` drives (incl. the `snap_grid.py` mask-grid step), plus `drc.sh`'s controls, the static rule-category review (`ihp_deck_categories.py`, `ihp_deck_facts.py`) and the pinned native-DRC environment (`native_drc_env.sh`) |
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
| Via ladder | 54 | `SG13_dev/via_stack` |

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

- **DRC (issue #61): IHP's primary runset reports `status: clean`, inside a
  stated scope** (`PROVENANCE.md` §13).
  - *Report of record*: `drc/vco-drc-ihp.json`, from IHP's own primary runset
    (`ihp-sg13g2.drc` via `klt drc --engine klayout`). It has **zero
    findings, known coverage, and a satisfied coverage assertion**
    (`--expect-rule-categories 590`). The 590 comes from a static review of
    the deck source (`scripts/ihp_deck_categories.py`), not from the run it
    vouches for. `drc/vco-drc-ihp-assertion.json` records how it was derived,
    the exact tool revisions and invocation, and three negative controls: a
    wrong count, a gated-off rule group, and a run without the assertion.
    Getting to zero from the first run's **370 real violations** took three
    generator fixes, all applied in place to the committed stream (§12).
  - *What "clean" covers*: the assertion is a documented claim that every
    rule category in that runset was declared on this invocation. It does
    not prove that each rule faithfully transcribes the DRM. Outside the
    report: IHP's `density.drc` (9 min-density findings, because the block
    ships un-filled; fill is deferred to chip assembly), `sg13g2_maximal.drc`
    (4 `NW.e` findings inside the PDK's own SVaricap PCell, a deck the PDK
    labels untested), and `antenna.drc` (0 findings). All three were re-run
    for this record and are listed in §13. This is a block-level result, not
    a chip-level one.
  - *klt's curated deck* (`drc/vco-drc.json`, a diagnostic): `violations`, 8,
    all inside the PDK's own `npn13G2V` PCell. A same-deck control shows
    they come from the deck's `Cnt.c` approximation (upstream
    `klayout-tools#2688`), not from the layout.
- **Guard-ring continuity is verified on all three of its layers** (Activ,
  pSD, Metal1), each against a negative control that breaks it (§12).
- **LVS closure is issue #62** — not run here. Three deliberate
  schematic/layout differences are already recorded for it in `PROVENANCE.md`
  (the `rppd` vs ideal `R` substitution, the varactor `bn` substrate tie, and
  the `VSUP`/`VCT` testbench sources with no layout counterpart).

No electrical, EM or phase-noise claim is made or implied by this layout.
Read `PROVENANCE.md` §11 before citing any of it as evidence.

## Reproducing the DRC evidence

```sh
# curated deck + helpers: the tagged klt release CI pins, KLayout 0.30.12
uv venv layout/build/klt-0.6.0
VIRTUAL_ENV=layout/build/klt-0.6.0 uv pip install klayout-tools==0.6.0
layout/scripts/native_drc_env.sh layout/build/native-drc-env   # Ubuntu 24.04: KLayout 0.30.12 wrapper
export PATH="$PWD/layout/build/klt-0.6.0/bin:$PWD/layout/build/native-drc-env/bin:$PATH"
export IHP_PDK_ROOT=~/share/pdk/ihp-sg13g2            # deck sha256:0620b737…
layout/drc.sh
```

`drc.sh` provisions the IHP-native run's environment itself, into the
gitignored `layout/build/native-drc-env/` (`scripts/native_drc_env.sh`). That
environment is klayout-tools at `70dee3b679a6451c5f4d830fb995c5eeb16084ee`
(the PR #2803 merge, the first revision with `--expect-rule-categories`) and
KLayout 0.30.12, extracted from KLayout's own Ubuntu 24.04 package; elsewhere,
set `NATIVE_KLAYOUT` to a 0.30.12 binary. Nothing is installed host-wide. The
script fails if the deck hash, either tool revision, the expected category
count, any negative control, or any verdict moves.
