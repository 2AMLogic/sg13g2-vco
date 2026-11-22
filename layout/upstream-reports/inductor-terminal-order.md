# Upstream report A — inductor terminal order (DRAFT, NOT FILED)

**Status: DRAFT, NOT FILED** (operator review header — omit everything outside
the delimited **Filing body** section below when filing).
Prepared on 2026-11-20 in
[2AMLogic/sg13g2-vco#417](https://github.com/2AMLogic/sg13g2-vco/issues/417),
per the 2026-10-19 ruling on
[2AMLogic/sg13g2-vco#162](https://github.com/2AMLogic/sg13g2-vco/issues/162).
Filing at `IHP-GmbH/IHP-Open-PDK` is outward-facing and stays with a human; the
ranked choices asked of the operator are at the end. Nothing has been posted
outside `2AMLogic/sg13g2-vco`.

---

<!-- begin filing body -->

## Filing body (copy verbatim for `IHP-GmbH/IHP-Open-PDK`)

**Title:** KLayout LVS reverses the two-terminal `inductor` windings when the
LB port sorts ahead of LA by position

This report describes the runset, not any one block, and is independent of a
companion report on inductor port-text net naming
([`layout/upstream-reports/inductor-port-names.md`][report-b]). The block-scale
measured outcome quoted below is attributed to the existing recorded run in
[`2AMLogic/sg13g2-vco`][vco-repo]
([`layout/PROVENANCE.md` §14.6][prov-14-6],
[`layout/lvs/vco-lvs-record.json`][lvs-record]); no new EDA run was made for
this report.

### Where the behaviour lives, per revision

All paths are under `ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/`.
Revisions checked through the GitHub REST API on 2026-11-20:

- `dev` head `cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8` (2026-11-10).
- Last `dev` commit touching `…/tech/lvs`:
  `27071f58a5196012f0702fa2366ec7de8fea381e` (2026-10-07, "[KLayout LVS]:
  Changelog and testing README for class-based RF matching"), so the LVS tree
  at `dev` head is identical to it in these files.
- Release tag `v0.3.0` → commit `5cccb161f7492697cfa52eb14dc03beb00bdca9e`
  (the revision the `klayout-tools` allowlist pins).

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

### What happens (runset-level, generic)

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
4. The PDK's own convention is LA = terminal 1: in its LVS unit testcase
   ([`testing/testcases/unit/ind_devices/netlist/inductor.cdl`][d-ind-cdl]),
   all sixteen extra `L_pattern_1`–`L_pattern_16` cards name their nodes
   `la_N lb_N`, in that order (above them, the base 1-turn `w = 2.0 µm`,
   `s = 2.1 µm`, `d = 25.35 µm` cards `L1`, `L4` and `L5` use `net1 net2`,
   `net5 net6` and `net6 net5`, respectively, alongside 2-turn `L2` on
   `net3 net4`), and in every one of the twenty `IND` markers of the matching
   [`inductor.gds`][d-ind-gds] LA lies to the left of LB. The testcase
   therefore never exercises a spiral where LB sorts ahead of LA, and none of
   its spirals has externally anchored net names.

When placement makes LB sort before LA, the extractor assigns LB to
`inductor_1` even though the CDL lists LA first. In the measured `m90`
example below, reflection across the vertical axis exchanges the ports'
left-to-right order. For the same as-drawn pair, `m0` reflects across the
horizontal axis and preserves both x coordinates, so LA still sorts first.
([KLayout transformation definitions](https://www.klayout.de/doc/about/transformations.html))

### Minimal reproduction (measured 2026-10-10)

Measured with KLayout 0.30.12 on a runset snapshot whose terminal-ordering
code is identical to the revisions above (scratch files only; nothing
committed; recorded in [`2AMLogic/sg13g2-vco` `layout/PROVENANCE.md` §14.6][prov-14-6]).
The unit testcase layout
([`testing/testcases/unit/ind_devices/layout/inductor.gds`][d-ind-gds]) has
three 1-turn, `w = 2.0 µm`, `s = 2.1 µm`, `d = 25.35 µm` `inductor2` markers
(`L1`, `L4` and `L5`, with lower-left corners at `(−44.68, 0)`,
`(−44.68, 150)` and `(105.32, 150)` µm). Take only the shapes inside the first
`IND` marker box, **`(−44.68, 0)` to `(44.68, 89.36)` µm**, as top cell
`indtest`. The PCell's own `LA`/`LB` texts (at `(−2.05, 1.0)` and
`(2.05, 1.0)` µm) name its two port nets `LA` and `LB`. Use this CDL:

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

### How it was observed in a block layout (attributed to the recorded run)

In [`2AMLogic/sg13g2-vco`][vco-repo]
([`layout/PROVENANCE.md` §14.6][prov-14-6],
[`layout/lvs/vco-lvs-record.json`][lvs-record]), both differential tank spiral
sub-cells have `LA` at local x = −25.315 µm and `LB` at +25.315 µm. L2 is
placed `r0`, so its `LA` (on `VDD`) is left and sorts first. L1 is placed
`m90`, so its `LA` (on `VDD`) lands at x = −134.685 µm, right of its `LB` (on
`OUTP`, at −185.315 µm), and sorts second. With the runset as shipped the
compare of record pairs 42/43 devices, 7/10 nets, 9/9 pins, with only L1
unpaired. Restoring the label order locally
([`layout/scripts/lvs_label_order.rb`][label-order-rb],
[2AMLogic/sg13g2-vco#80][vco-80]) pairs 43/43 devices, 10/10 nets, 9/9 pins;
that local step is an accommodation to be retired once a fixed runset is
available.

### Duplicate check (2026-11-20, read-only REST)

Searched `IHP-GmbH/IHP-Open-PDK` issues and pull requests (search API covers
both; no posting, no reactions), plus the first 100 recently updated
issues/PRs:

- Queries: "LVS inductor" (28 hits), "inductor mirrored" (0), "inductor
  terminal" (10), "LVS terminal order" (13), "LA LB LVS" (9).
- Read in full, none covers this behaviour:
  - [IHP-GmbH/IHP-Open-PDK#1067](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1067)
    (closed 2026-08-25, fixed by
    [IHP-GmbH/IHP-Open-PDK#1068](https://github.com/IHP-GmbH/IHP-Open-PDK/pull/1068)):
    inductor decks hardcoding the TopMetal2/TopMetal1 metal stack, plus three
    other extractor defects (`ind3_core` testing `ind_lb_tm1` twice; nil
    defaults applied after use; zero turn count not clamped). None is the
    terminal sort.
  - [IHP-GmbH/IHP-Open-PDK#1287](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1287)
    (open): SG13CMOS5L deck — `s` read at a crossover, and no pin arrangement
    for a centre-tapped coil. Parameter measurement and layer arrangement, not
    terminal order.
  - [IHP-GmbH/IHP-Open-PDK#1343](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1343)
    (open): `inductor3` with `nr_r=1` PCell geometry (ring closed where LA/LB
    attach). PCell drawing, not LVS ordering.
  - [IHP-GmbH/IHP-Open-PDK#1270](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1270)
    (closed): extracted `w`/`s`/`d` parameter discrepancies. Measurement, not
    order.
  - [IHP-GmbH/IHP-Open-PDK#456](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/456)
    (closed),
    [IHP-GmbH/IHP-Open-PDK#786](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/786),
    [IHP-GmbH/IHP-Open-PDK#872](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/872):
    PCell pin layers and flow usage, not ordering.

**Disposition: no existing report of this behaviour. This report is not a
duplicate.**

### Proposed fix

**Retain the LA/LB identity through extraction, so the LA winding remains
terminal 1 in either orientation.** Concretely, the smallest proper fix in
the runset:

1. Scope label ordering to the two-terminal `inductor` extractor. Pass
   `ind_port_la` and `ind_port_lb` separately so it can assign LA to
   `inductor_1` and LB to `inductor_2`. The join in `ind_derivations.lvs`
   (line 52 at `dev`, 50 at `v0.3.0`) loses that identity. The coordinate
   fallback in `custom_extractor.lvs` (line 294 / 291) then decides the order.
2. Declaring the two windings equivalent
   (`equivalent_terminal_id`) would also make the compare pass, but it is
   **not** proposed as the fix: winding equivalence masks a genuine wiring
   swap — a layout whose LA really is wired to the LB net would compare clean
   (measured: control (a) in [`layout/PROVENANCE.md` §14.6][prov-14-6] gives
   `match` against an L1-swapped reference under the runset as shipped). If IHP
   prefers that route, it needs an explicit decision that such a swap is no
   longer a difference worth catching.

#### Regression test it needs

Add a **mirrored pattern to the unit testcase**
(`testing/testcases/unit/ind_devices`): an existing `L_pattern_*` spiral (or
the `(−44.68, 0)` to `(44.68, 89.36)` µm `L1` crop) mirrored in place (`M90`),
with its two nets anchored by name, against a CDL entry listing its nodes in
LA, LB order (`la_N lb_N`). It must match after the fix and fail before it.
The existing patterns cannot catch the bug: LA is left of LB in every one of
the twenty `IND` boxes, and their inductor nets are not anchored by name, so
mirroring in place still matches there.

#### Negative controls that must still be rejected

All already exist as measured scratch controls in
[`2AMLogic/sg13g2-vco` `layout/PROVENANCE.md` §14.6][prov-14-6]; a fixed
runset must keep rejecting every one:

| Control | Change | Must be |
|---|---|---|
| (a) genuine swap | L1 re-placed mirrored about its own axis (`m90` → `r0`), wires unchanged, so `LA` lands on the `OUTP` wire | `mismatch` — an equivalence-style fix would accept this, which is why fix 1 is preferred |
| (b1) labels swapped, L2 | L2's `LA`/`LB` texts swapped (`LA` on `OUTN`) | `mismatch` |
| (b2) labels swapped, L1 | L1's `LA`/`LB` texts swapped (`LA` on `OUTP`) | `mismatch` |
| (b3) `LA` moved | L1's `LA` text moved onto its `LB` port (runset drops the device) | `mismatch` |
| N1–N3 | the [`layout/PROVENANCE.md` §14][prov-14] connectivity breaks (supply via, signal via, missing MIM) | `mismatch` ×3 |

Verification must retain the **schematic-derived reference** (never the
extraction re-read as reference), the **explicit port mapping**, and
**device/net/pin coverage** (in [`2AMLogic/sg13g2-vco`][vco-repo]: 43/43
devices, 10/10 nets, 9/9 pins; [`layout/lvs/vco-lvs-record.json`][lvs-record]).

[vco-repo]: https://github.com/2AMLogic/sg13g2-vco
[report-b]: https://github.com/2AMLogic/sg13g2-vco/blob/main/layout/upstream-reports/inductor-port-names.md
[prov-14]: https://github.com/2AMLogic/sg13g2-vco/blob/main/layout/PROVENANCE.md#14-lvs-record-2026-10-08-issue-62
[prov-14-6]: https://github.com/2AMLogic/sg13g2-vco/blob/main/layout/PROVENANCE.md#146-the-label-order-step-l1s-terminal-order-accommodated-2026-10-10-issue-80
[lvs-record]: https://github.com/2AMLogic/sg13g2-vco/blob/main/layout/lvs/vco-lvs-record.json
[label-order-rb]: https://github.com/2AMLogic/sg13g2-vco/blob/main/layout/scripts/lvs_label_order.rb
[vco-80]: https://github.com/2AMLogic/sg13g2-vco/issues/80
[d-ind-cdl]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/testing/testcases/unit/ind_devices/netlist/inductor.cdl#L18-L40
[d-ind-gds]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/testing/testcases/unit/ind_devices/layout/inductor.gds
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

<!-- end filing body -->

---

## Repository transition and operator decision (`2AMLogic/sg13g2-vco` only — omit when filing)

### What `2AMLogic/sg13g2-vco` removes once a fixed runset is pinned

[`layout/PROVENANCE.md` §14.6 "Removal"](https://github.com/2AMLogic/sg13g2-vco/blob/main/layout/PROVENANCE.md#removal):
delete
[`layout/scripts/lvs_label_order.rb`](https://github.com/2AMLogic/sg13g2-vco/blob/main/layout/scripts/lvs_label_order.rb),
the wrapper and shim block in
[`layout/lvs.sh`](https://github.com/2AMLogic/sg13g2-vco/blob/main/layout/lvs.sh)
and the `lo-*` runs; bump `IHP_LVS_DECK_SHA`; require the runset as shipped to
reach the `match` of record on its own (C1, the L1-swapped reference, becomes a
control that must be rejected); keep (a) and (b1)–(b3) as plain-runset negative
controls. An x-order fix that declared the windings equivalent would
additionally require the (a) decision above.

### Decision asked of the operator (ranked, answer separately from [report B](https://github.com/2AMLogic/sg13g2-vco/blob/main/layout/upstream-reports/inductor-port-names.md))

1. **File this report at `IHP-GmbH/IHP-Open-PDK`** — copy the delimited
   **Filing body** section above verbatim; a human files it.
2. **Defer filing while klt investigates the pinned runset.** The proposed
   work would reproduce the as-drawn and `m90` cases, report strict-port
   findings verbatim and identify the terminal-order limitation if the
   evidence distinguishes it from a real wiring swap. The report would
   retain the as-shipped verdict.
   ([2AMLogic/klayout-tools#6903](https://github.com/2AMLogic/klayout-tools/issues/6903))

   A separate proposal would measure label-based ordering against negative
   controls. Using a normalised result for signoff requires an operator
   ruling.
   ([2AMLogic/klayout-tools#6914](https://github.com/2AMLogic/klayout-tools/issues/6914))
3. **Do not file**: keep the finding recorded as FAIL and the local
   label-order accommodation in place. This leaves
   [2AMLogic/sg13g2-vco#162](https://github.com/2AMLogic/sg13g2-vco/issues/162)'s
   strict top-port chain blocked as today.

Prepared in
[2AMLogic/sg13g2-vco#417](https://github.com/2AMLogic/sg13g2-vco/issues/417);
blockers and evidence chain:
[2AMLogic/sg13g2-vco#162](https://github.com/2AMLogic/sg13g2-vco/issues/162),
[2AMLogic/sg13g2-vco#62](https://github.com/2AMLogic/sg13g2-vco/issues/62).
