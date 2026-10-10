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
| `lvs.sh` | Re-runs the LVS evidence: derives the reference from `design/vco.spice`, runs IHP's own LVS runset as shipped (with control C1 and three negative controls) and with the reviewed label-order inductor terminal step (#80; with the fidelity control R0 and seven negative controls), and records why `klt lvs` (0.6.0, the CI pin, and 0.7.0, the newest release) cannot run this compare. Fails on any verdict drift |
| `lvs/` | The derived LVS reference and its per-line trace, the runset's device-aware extraction, the compare of record and the run record (`PROVENANCE.md` §14) |
| `scripts/` | The generation stages `generate.sh` drives (incl. the `snap_grid.py` mask-grid step), plus `drc.sh`'s controls, the static rule-category review (`ihp_deck_categories.py`, `ihp_deck_facts.py`), the pinned native-DRC environment (`native_drc_env.sh`), and `lvs.sh`'s reference derivation (`lvs_reference.py`), `.lvsdb` reader (`lvsdb_summary.py`), label-order step (`lvs_label_order.rb`, #80) and negative-control helpers (`lvs_break.py`, `lvs_inductor_ctl.py`) |
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
- **LVS (issues #62, #80): run, device-aware. The compare of record is
  `match` on the cross-reference, with three strict-port NAME findings
  recorded; IHP's runset as shipped gives `mismatch`** (`PROVENANCE.md` §14,
  §14.6). Read §14 and §14.6 before citing anything about LVS.
  - *Compare of record (#80, §14.6)*: the same hash-pinned runset plus one
    reviewed, removable step (`scripts/lvs_label_order.rb`) that orders each
    spiral's two winding terminals by the `LA`/`LB` labels the runset itself
    uses to find them, instead of by x. It reorders L1 (mirrored) and leaves
    L2 alone, keyed on labels, not instance names. The reference is not
    edited. Result: 43/43 device pairs, 10/10 nets, 9/9 pins. The runset's
    strict top-port check still logs three port-name findings (`'LA,VDD'` vs
    `'VDD'`, ...: the spiral PCell's label text names the pin net), and
    `run_lvs.py`'s summary therefore says FAIL; they are recorded, not
    suppressed. A fidelity control (R0) shows the wrapper alone reproduces
    the runset-as-shipped compare exactly. Seven negative controls through
    the step are all rejected: L1 genuinely wired the other way round, `LA`
    on the wrong net (three variants), and the three breaks below. An
    upstream report to IHP is drafted in §14.6, **not yet filed**.
  - *Engine*: IHP's own KLayout LVS runset (`sg13g2.lvs`, KLayout 0.30.12).
    It recognizes **all 42 devices** (plus the guard-ring `ptap1` tie), with
    the same per-class census on both sides. `klt lvs` at the pinned 0.6.0
    (and at current `main`) cannot run this compare: it refuses the reference
    (no inductor, varactor or HBT class for `sg13g2`), and its curated
    extraction recognizes 1 of 42 devices
    ([klayout-tools#2849](https://github.com/2AMLogic/klayout-tools/issues/2849)).
    So **no `klt lvs` report and no `power_connectivity` block exist** for
    this block.
  - *Reference*: `lvs/vco-reference.cir`, derived from `design/vco.spice` by
    `scripts/lvs_reference.py`. Its six transformations are listed and traced
    per line. The PDK symbols' own `lvs_format` mapping is cross-checked
    against xschem's LVS netlist and agrees on all 39 cards it covers.
  - *Exactly one difference*, isolated by a single-variable control: spiral
    L1's terminal order, an artefact of the runset's x-sorted inductor ports
    on a mirrored instance (the labels show L1 wired as the schematic says),
    tracked in **#80**. (The 32 varactors' `bn` pin was a second difference
    until **#79** corrected the schematic to tie it to the substrate, as the
    layout always did; DR-005.) With L1's order swapped in a scratch
    reference, the compare reports `match`, with `VDD`, `0` and the substrate
    each pairing 1:1. Three negative controls (a supply break, a signal
    break, a missing device) are all rejected. The L1 difference is not
    reconciled in the reference of record.
  - *Re-run 2026-10-09* (`PROVENANCE.md` §14.5): byte-identical record,
    verdict still `mismatch`. The xschem 3.4.7 cross-check was re-run against
    the post-#79 netlist and agrees on all 39 cards. The tagged klt **0.7.0**
    behaves as 0.6.0 does: it refuses the reference, recognizes 1 of 42
    devices, and cannot read the runset's extraction as `layout.netlist`. So
    #2849 is still open at the newest release. #80 (L1 order) is resolved
    by the label-order step above.

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

## Reproducing the LVS evidence

```sh
export IHP_PDK_ROOT=~/share/pdk/ihp-sg13g2   # LVS runset hash fd11fced… (see lvs.sh)
layout/lvs.sh
```

`lvs.sh` reuses the pinned KLayout 0.30.12 environment that
`scripts/native_drc_env.sh` provisions, and provisions the tagged
`klayout-tools==0.6.0` venv for its klt leg, plus a tagged
`klayout-tools==0.7.0` venv for the newest-release leg (§14.5), if they are
missing. Both live under
the gitignored `layout/build/`. If `xschem` is on `PATH`, the script also
cross-checks the derived reference against xschem's own LVS-mode netlist. It
writes `lvs/` only after every expectation holds: the runset-as-shipped
`mismatch` (L1 only) and control C1, the label-order compare of record
`match` with exactly the three known port-name findings, the fidelity control
R0, every negative control (as shipped and through the step), the supply
pairing, and klt's refusal (at both 0.6.0 and 0.7.0). Any drift fails the run and leaves the record untouched. Two
consecutive runs produce byte-identical files.
