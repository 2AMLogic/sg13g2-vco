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
| `lvs.sh` | Re-runs the LVS evidence: derives the reference from `design/vco.spice`, runs IHP's own LVS runset as shipped (with control C1 and three negative controls) and with the reviewed label-order inductor terminal step (#80; with the fidelity control R0 and seven negative controls), and records why `klt lvs` (0.8.0, the version the committed records reproduce under; the claims pin moved to 0.9.2 in #416) cannot run this compare. Fails on any verdict drift |
| `lvs/` | The derived LVS reference and its per-line trace, the runset's device-aware extraction, the compare of record and the run record (`PROVENANCE.md` §14) |
| `erc.sh` | Re-runs the ERC supply-spec evidence (`klt erc` at klt 0.8.0, the version the committed record reproduces under): both supplies one electrical island, the guard-ring substrate tie checked, and the AC3 negative control (one `ptap1` bar deleted) rejected. Fails on any verdict drift (#330, `PROVENANCE.md` §16) |
| `erc/` | The committed supply spec, the `klt erc` envelope of record and the negative-control record (`PROVENANCE.md` §16) |
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
| Via ladder | 56 | `SG13_dev/via_stack` |

All 9 nets of `design/vco.spice` are routed and labelled (`VCTRL` and `0`
each carry a second label, on their TopMetal2 chip-level pins, below):
`VDD`, `OUTP`, `OUTN`, `VCTRL`, `TAIL`, `TE`, `NBIAS`, `RE`, `0`.

## Chip-level pins on TopMetal2 (issues #314, #427)

A parent that keeps Metal1-5 out of a region around the block can reach every
signal the chip needs from outside the bbox only on TopMetal1/TopMetal2.
`OUTP`/`OUTN` are TopMetal1 and `VDD` is TopMetal2; `VCTRL` and `0` are
TopMetal2 pins too (they were a Metal3 label inside the core and a Metal1
label on the guard ring, respectively).

| Pin | Layer (GDS) | Shape (µm, in `vco` coordinates) | Label | Distance to artifact bbox edge |
|---|---|---|---|---|
| `VCTRL` | TopMetal2 `134/0` | x −68.0…−64.0, y −106.0…−54.5 (4.0 µm wide strap) | `VCTRL` on `134/25` at (−66.0, −104.0) | **0.03 µm** to the bottom edge (bbox y0 = −106.03; the strap's outboard end is the guard ring's outer edge, y = −106.0) |
| `0` | TopMetal2 `134/0` | x 64.0…68.0, y −106.0…−101.57 (4.0 µm wide landing strap) | `0` on `134/25` at (66.0, −104.0) | **0.03 µm** to the bottom edge (same as `VCTRL`) |

Land on either strap's bottom end (y −106…−104). `VCTRL` reaches the
existing Metal3 trunk through one Metal3→TopMetal2 `via_stack`
(`VS_VCTRL_PIN`, at (−66.0, −57.0)); `0` reaches the bottom guard-ring bar's
Metal1 through one Metal1→TopMetal2 `via_stack` (`VS_GND_PIN`, at
(66.0, −104.07), the same `vs_m1_tm2` ladder `VS_VDD_REF` uses — its height
is derived from the ladder's measured pads so the TopMetal2 pad never passes
the ring edge while the Metal1 pad still bites the bar by 0.23 µm). No other
shape of the block changed, the artifact bbox is unchanged, and the landings
add no Metal1-5 outside their stacks. The nearest other TopMetal2 is the
`VDD` trunk (y −11.5…−3.5, ~90 µm above the landings) and the RREF spur
(x 93…97); the two straps are 128 µm apart (`topmetal2.space` is 2.0).

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
  - *klt's curated deck* (`drc/vco-drc.json`, a diagnostic): `violations`,
    64, all `nwell.enclosing.pactiv.1` rolled up on the 32 SVaricap +
    32 `SVaricap$1` cells. A same-deck control supplying the deck's dropped
    `Cnt.c` activ_mask term does not clear them: the standing diagnosis is
    a missing carve-out in the curated rule (§12, issue #315, upstream
    `klayout-tools#2688` line), not a layout defect.
- **Guard-ring continuity is verified on all three of its layers** (Activ,
  pSD, Metal1), each against a negative control that breaks it (§12).
- **ERC supply evidence (#330): `klt erc` reports `erc_status: clean` — both
  supplies one electrical island, the substrate tie checked** (`PROVENANCE.md`
  §16).
  - *Report of record*: `erc/vco-erc.json` — `klt erc` at klt 0.8.0 (the
    version the record reproduces under)
    against the committed supply spec (`erc/vco-erc-spec.json`): `VDD` and
    `0` each resolve to exactly one island with zero findings, and the
    guard-ring substrate tie (native-substrate form: asserted region +
    Activ ∩ pSD taps, since sg13g2 draws no PWell) is reported as checked
    work resting on `checked_by_well_assertion`. The roles measurement
    carries the severed-rail negative (nothing unlabelled outside the four
    declared PCell-provided p+ carve-outs), and the spec's own layer
    coverage is complete under the `sg13g2` deck.
  - *Negative control*: one `ptap1` bar deleted (`scripts/break_ring.py`)
    flips the verdict to `violations` with `erc.missing_tie` naming `0`
    plus unlabelled-conductor findings. Since the TopMetal2 ground landing
    (#427) the second `0` label sits on the landing and survives the
    deletion, so `erc.unconnected_net` no longer fires — the rejection
    rides on the severed substrate tie
    (`erc/vco-erc-control.json`).
  - *Signoff*: item 11 cites this envelope plus `klt lvs`'s recorded
    refusal of the compare and renders `unmet` / `check_errored` — `met`
    stays gated on item 4's LVS report (#62); see §16.6 for the exact
    states.
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
    the same per-class census on both sides. `klt lvs` at klt 0.8.0
    (and at current `main`; the claims pin is 0.9.2, where the census is
    unchanged — 4 of 42, re-measured 2026-11-20) cannot run this compare: it
    refuses the reference
    (no inductor, varactor or HBT class for `sg13g2`), and its curated
    extraction recognizes 4 of 42 devices
    (`cap_cmim` 1, `rppd` 3; [klayout-tools#2849](https://github.com/2AMLogic/klayout-tools/issues/2849)).
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
    behaved as 0.6.0 did (historical; 0.8.0, which the committed records
    reproduce under, recognizes 4 of 42): it refused the reference, recognized 1 of 42 devices, and could
    not read the runset's extraction as `layout.netlist`. So #2849 was still
    open at the newest release then. #80 (L1 order) is resolved
    by the label-order step above.

No electrical, EM or phase-noise claim is made or implied by this layout.
Read `PROVENANCE.md` §11 before citing any of it as evidence.

## Reproducing the DRC evidence

```sh
# curated deck + helpers: the tagged klt 0.8.0 wheel the committed records
# reproduce under (the claims pin, .github/klt-version, is 0.9.2 since #416;
# the layout records regenerate under it via #266), KLayout 0.30.12
uv venv layout/build/klt-0.8.0
VIRTUAL_ENV=layout/build/klt-0.8.0 uv pip install klayout-tools==0.8.0
layout/scripts/native_drc_env.sh layout/build/native-drc-env   # Ubuntu 24.04: KLayout 0.30.12 wrapper
export PATH="$PWD/layout/build/klt-0.8.0/bin:$PWD/layout/build/native-drc-env/bin:$PATH"
export IHP_PDK_ROOT=~/share/pdk/ihp-sg13g2            # deck sha256:0620b737…
layout/drc.sh
```

`drc.sh` provisions the IHP-native run's environment itself, into the
gitignored `layout/build/native-drc-env/` (`scripts/native_drc_env.sh`). That
environment is klayout-tools at `c572046be644e0407f693f2410f3abb799d68a3a`
(the v0.8.0 tag commit; PR #2803, the first revision with `--expect-rule-categories`, predates it) and
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
`klayout-tools==0.8.0` venv for its klt leg and for the newest-release leg
(§14.5; both legs are the version the committed records reproduce under —
0.8.0, not the 0.9.2 claims pin, until #266 regenerates them), if it is
missing. It lives under
the gitignored `layout/build/`. If `xschem` is on `PATH`, the script also
cross-checks the derived reference against xschem's own LVS-mode netlist. It
writes `lvs/` only after every expectation holds: the runset-as-shipped
`mismatch` (L1 only) and control C1, the label-order compare of record
`match` with exactly the three known port-name findings, the fidelity control
R0, every negative control (as shipped and through the step), the supply
pairing, and klt's refusal (at 0.8.0). Any drift fails the run and leaves the record untouched. Two
consecutive runs produce byte-identical files.

## Reproducing the ERC evidence

```sh
# the tagged klt 0.8.0 wheel the committed ERC record reproduces under, in a
# throwaway venv — never the host's (the claims pin is 0.9.2 since #416; the
# ERC record regenerates under it via #266)
uv venv layout/build/klt-0.8.0
VIRTUAL_ENV=layout/build/klt-0.8.0 uv pip install klayout-tools==0.8.0
layout/erc.sh
```

`erc.sh` provisions the pinned venv itself if it is missing (under the
gitignored `layout/build/`, like `drc.sh`'s and `lvs.sh`'s environments) and
needs `klayout` on PATH only for the negative-control stream. It validates
the committed spec, runs `klt erc` against the committed stream, re-runs the
same invocation on a copy with one `ptap1` guard-ring bar deleted (which
must be rejected), re-hashes the committed envelope (`klt erc --check`), and
re-derives every verdict `PROVENANCE.md` §16 records. Any drift fails the
run. Two consecutive runs produce byte-identical files.
