# Upstream report A — inductor terminal order (DRAFT, NOT FILED)

**Status: DRAFT, NOT FILED.** Prepared for operator review on 2026-11-20
(issue #417, per the 2026-10-19 ruling on #162). Filing at
`IHP-GmbH/IHP-Open-PDK` is outward-facing and stays with a human; the ranked
choices asked of the operator are at the end. Nothing has been posted outside
this repository.

**Title to file:** KLayout LVS: 2-terminal `inductor` terminals are ordered by
x position, not by their LA/LB labels, so a mirrored inductor always compares
with reversed windings.

This report describes the runset, not any one block. The block-scale measured
outcome quoted below is attributed to the existing recorded run
(`layout/PROVENANCE.md` §14.6); no new EDA run was made for this report.

## Where the behaviour lives, per revision

All paths are under `ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/`.
Revisions checked through the GitHub REST API on 2026-11-20:

- `dev` head `cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8` (2026-11-10).
- Last `dev` commit touching `…/tech/lvs`:
  `27071f58a5196012f0702fa2366ec7de8fea381e` (2026-10-07, "[KLayout LVS]:
  Changelog and testing README for class-based RF matching"), so the LVS tree
  at `dev` head is identical to it in these files.
- Release tag `v0.3.0` → commit `5cccb161f7492697cfa52eb14dc03beb00bdca9e`
  (the revision the klt allowlist pins).

**The behaviour is present at every revision above.** Each line number was
re-read in the file blob at the commit cited (not carried over from any
earlier note):

| Mechanism | `dev` head `cc9afba5` = `27071f58` | `v0.3.0` `5cccb161` |
|---|---|---|
| `ind_derivations.lvs` finds the two ports by their texts | [`:44`][d-ind-44] (`ind_port_la`), [`:46`][d-ind-46] (`ind_port_lb`) | [`:42`][v-ind-42], [`:44`][v-ind-44] |
| `ind_derivations.lvs` joins them, losing label identity | [`:52`][d-ind-52] `ind2_ports = ind_port_la.join(ind_port_lb)` | [`:50`][v-ind-50] |
| `custom_extractor.lvs` coordinate-sort fallback | [`:294`][d-ce-294] `sorted_ports ||= sort_polygons(ports)` (varicap excepted, `:280–293`) | [`:291`][v-ce-291] |
| `custom_extractor.lvs` `sort_polygons` sort key | [`:351`][d-ce-351] def, [`:374`][d-ce-374] `sort_by(&:first)` (first vertex, i.e. x) | [`:348`][v-ce-348], [`:371`][v-ce-371] |
| `custom_devices.lvs` windings compared as distinct | [`:81`][d-cd-81] `class DeviceCustomInd`, [`:88`][d-cd-88] `clear_equivalent_terminal_ids` | [`:72`][v-cd-72], [`:79`][v-cd-79] |
| `ind_extraction.lvs` 2-terminal extractor entry | [`:28`][d-ie-28] `GeneralNTerminalExtractor.new('inductor', 2)` | [`:28`][v-ie-28] |
| `layers_definitions.lvs` label source | [`:425`][d-ld-425] `ind_text = labels(27, 25)` | [`:425`][v-ld-425] |

[d-ind-44]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L44
[d-ind-46]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L46
[d-ind-52]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L52
[d-ce-294]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_extractor.lvs#L294
[d-ce-351]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_extractor.lvs#L351
[d-ce-374]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_extractor.lvs#L374
[d-cd-81]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_devices.lvs#L81
[d-cd-88]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_devices.lvs#L88
[d-ie-28]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_extraction.lvs#L28
[d-ld-425]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/layers_definitions.lvs#L425
[v-ind-42]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L42
[v-ind-44]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L44
[v-ind-50]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L50
[v-ce-291]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_extractor.lvs#L291
[v-ce-348]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_extractor.lvs#L348
[v-ce-371]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_extractor.lvs#L371
[v-cd-72]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_devices.lvs#L72
[v-cd-79]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/custom_devices.lvs#L79
[v-ie-28]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_extraction.lvs#L28
[v-ld-425]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/layers_definitions.lvs#L425

## What happens (runset-level, generic)

1. `ind_derivations.lvs` identifies the two ports of an `inductor2` by their
   `LA`/`LB` texts on `IND:text` (27/25, matched case-insensitively:
   `ind_port_la = ind_ports_.interacting(ind_text.texts(la_patt))`, and the
   same for `LB`), then **joins** them into one region
   (`ind2_ports = ind_port_la.join(ind_port_lb)`), so the labels' identity is
   lost before extraction.
2. `custom_extractor.lvs`, `GeneralNTerminalExtractor#define_and_sort_terminals`,
   sets `sorted_ports ||= sort_polygons(ports)` for every class except the
   varicap. `sort_polygons` collects each merged port polygon's vertices and
   orders the ports by `sort_by(&:first)`, the polygon's first vertex `[x, y]`,
   in effect by x. `inductor_1` and `inductor_2` are then assigned in that
   order (`define_terminal(device, @reg_dev.terminal_id("#{name}_#{i}"), …,
   sorted_ports[i - 1])`).
3. `custom_devices.lvs`, `DeviceCustomInd#initialize`, calls
   `clear_equivalent_terminal_ids`, so the comparer treats the two windings as
   distinct and the order is compared.
4. The PDK's own convention is LA = terminal 1: its LVS unit testcase
   (`testing/testcases/unit/ind_devices/netlist/inductor.cdl`) names every
   pattern's nodes `la_N lb_N`, in that order, and in every pattern of the
   matching `inductor.gds` LA lies to the left of LB. The testcase therefore
   never exercises a mirrored spiral, and that is why it passes.

Consequence: for any inductor instance placed with a mirror (`m90`, `r180`,
`m0` — anything that puts `LA` right of `LB`), the extracted `inductor_1` is
the **LB** port. A correctly wired mirrored inductor fails LVS against a CDL
that lists its nodes in LA, LB order. Any layout that mirrors an inductor, for
example for a symmetric differential tank, hits this.

## Minimal reproduction (measured 2026-10-10, §14.6)

Measured with KLayout 0.30.12 on a runset snapshot whose terminal-ordering
code is identical to the revisions above (scratch files only; nothing
committed). Take only the 1-turn, d = 25.35 µm `inductor2` pattern from the
unit testcase layout (`testing/testcases/unit/ind_devices/layout/inductor.gds`)
as top cell `indtest`. The PCell's own `LA`/`LB` texts name its two port nets
`LA` and `LB`. Use this CDL:

```
.SUBCKT indtest LA LB
L1 LA LB sub inductor w=2u s=2.1u d=25.35u nr_r=1
.ENDS
```

As drawn, `run_lvs.py --topcell=indtest` reports "Congratulations! Netlists
match." Mirror the same shapes about the marker's vertical centre line
(`M90`). The labels move with their ports, so the device is still wired
LA→`LA` and LB→`LB`; nothing electrical changed. The run now fails: the
comparer can pair the device only by pairing layout net `LA` with reference
`LB`, and the strict top-port check logs `Port mismatch 'LA' vs. 'LB'` and
`Port mismatch 'LB' vs. 'LA'`. In a larger circuit, where the nets are
anchored by other devices, the same thing shows up as an unpaired inductor
with its terminals reversed.

## How it was observed in this block (attributed to the §14.6 record run)

Both spiral sub-cells have `LA` at local x = −25.315 µm and `LB` at
+25.315 µm. L2 is placed `r0`, so its `LA` (on `VDD`) is left and sorts
first. L1 is placed `m90`, so its `LA` (on `VDD`) lands at
x = −134.685 µm, right of its `LB` (on `OUTP`, at −185.315 µm), and sorts
second. With the runset as shipped the compare of record pairs 42/43 devices,
7/10 nets, 9/9 pins, with only L1 unpaired. The recorded compare of record
(`layout/lvs/vco-lvs-record.json`) restores the label order locally
(`layout/scripts/lvs_label_order.rb`, #80) and pairs 43/43, 10/10, 9/9; that
step is an accommodation, removed per §14.6 "Removal" once a fixed runset is
pinned (below).

## Duplicate check (2026-11-20, read-only REST)

Searched `IHP-GmbH/IHP-Open-PDK` issues and pull requests (search API covers
both; no posting, no reactions), plus the first 100 recently updated
issues/PRs:

- Queries: "LVS inductor" (28 hits), "inductor mirrored" (0), "inductor
  terminal" (10), "LVS terminal order" (13), "LA LB LVS" (9).
- Read in full, none covers this behaviour:
  - [#1067](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1067) (closed
    2026-08-25, fixed by
    [#1068](https://github.com/IHP-GmbH/IHP-Open-PDK/pull/1068)): inductor
    decks hardcoding the TopMetal2/TopMetal1 metal stack, plus three other
    extractor defects (`ind3_core` testing `ind_lb_tm1` twice; nil defaults
    applied after use; zero turn count not clamped). None is the terminal
    sort.
  - [#1287](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1287) (open):
    SG13CMOS5L deck — `s` read at a crossover, and no pin arrangement for a
    centre-tapped coil. Parameter measurement and layer arrangement, not
    terminal order.
  - [#1343](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1343) (open):
    `inductor3` with `nr_r=1` PCell geometry (ring closed where LA/LB
    attach). PCell drawing, not LVS ordering.
  - [#1270](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1270) (closed):
    extracted `w`/`s`/`d` parameter discrepancies. Measurement, not order.
  - [#456](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/456) (closed),
    [#786](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/786),
    [#872](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/872): PCell pin
    layers and flow usage, not ordering.

**Disposition: no existing report of this behaviour. This report is not a
duplicate.**

## Proposed fix

**Retain the LA/LB identity through extraction, so the LA winding remains
terminal 1 in either orientation.** Concretely, the smallest proper fix in
the runset:

1. Order by label. Keep `ind_port_la` and `ind_port_lb` as separate inputs to
   the extractor (or pass the label-to-polygon mapping through), define
   `inductor_1` on the LA port and `inductor_2` on the LB port, and apply the
   same rule to `inductor3` (LA, LB, LC). The join at `ind_derivations.lvs`
   (line 52 at `dev`, 50 at `v0.3.0`) is where the identity is lost; the
   coordinate fallback at `custom_extractor.lvs` (line 294 / 291) is where the
   order is decided.
2. Declaring the two windings equivalent
   (`equivalent_terminal_id`) would also make the compare pass, but it is
   **not** proposed as the fix: winding equivalence masks a genuine wiring
 swap — a layout whose LA really is wired to the LB net would compare clean
 (measured: control (a) in §14.6 gives `match` against an L1-swapped
 reference under the runset as shipped). If IHP prefers that route, it needs
 an explicit decision that such a swap is no longer a difference worth
 catching.

### Regression test it needs

Add a **mirrored pattern to the unit testcase**
(`testing/testcases/unit/ind_devices`): the existing pattern mirrored in place
(`M90`), nets anchored by name, against the same `la_N lb_N`-order CDL entry.
It must match after the fix and fail before it. The existing patterns cannot
catch the bug: LA is left of LB in every one, and their inductor nets are not
anchored by name, so mirroring in place still matches there.

### Negative controls that must still be rejected

All already exist as measured scratch controls in §14.6; a fixed runset must
keep rejecting every one:

| Control | Change | Must be |
|---|---|---|
| (a) genuine swap | L1 re-placed mirrored about its own axis (`m90` → `r0`), wires unchanged, so `LA` lands on the `OUTP` wire | `mismatch` — an equivalence-style fix would accept this, which is why fix 1 is preferred |
| (b1) labels swapped, L2 | L2's `LA`/`LB` texts swapped (`LA` on `OUTN`) | `mismatch` |
| (b2) labels swapped, L1 | L1's `LA`/`LB` texts swapped (`LA` on `OUTP`) | `mismatch` |
| (b3) `LA` moved | L1's `LA` text moved onto its `LB` port (runset drops the device) | `mismatch` |
| N1–N3 | the §14 connectivity breaks (supply via, signal via, missing MIM) | `mismatch` ×3 |

Verification must retain the **schematic-derived reference** (never the
extraction re-read as reference), the **explicit port mapping**, and
**device/net/pin coverage** (in this block: 43/43 devices, 10/10 nets, 9/9
pins; the record run's numbers, `layout/lvs/vco-lvs-record.json`).

## What this repo removes once a fixed runset is pinned

§14.6 "Removal": delete `layout/scripts/lvs_label_order.rb`, the wrapper and
shim block in `lvs.sh` and the `lo-*` runs; bump `IHP_LVS_DECK_SHA`; require
the runset as shipped to reach the `match` of record on its own (C1, the
L1-swapped reference, becomes a control that must be rejected); keep (a) and
(b1)–(b3) as plain-runset negative controls. An x-order fix that declared the
windings equivalent would additionally require the (a) decision above.

## Decision asked of the operator (ranked, answer separately from report B)

1. **File this report at `IHP-GmbH/IHP-Open-PDK`** — the text above is ready
   to file verbatim; a human files it.
2. **Route the fix through the klt-side engine first**
   ([2AMLogic/klayout-tools#6903](https://github.com/2AMLogic/klayout-tools/issues/6903),
   open): the `klayout-runset` route carries the mirrored-inductor compare
   and the strict-port envelope without depending on IHP's schedule; file at
   IHP only if that route stalls or IHP uptake matters.
3. **Do not file**: keep the finding recorded as FAIL and the local
   label-order accommodation in place. This leaves #162's strict top-port
   chain blocked as today.

Prepared in #417; blockers and evidence chain: #162, #62.
