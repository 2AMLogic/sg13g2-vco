# Upstream report B — inductor port names (DRAFT, NOT FILED)

**Status: DRAFT, NOT FILED.** Prepared for operator review on 2026-11-20
(issue #417, per the 2026-10-19 ruling on #162). Filing at
`IHP-GmbH/IHP-Open-PDK` is outward-facing and stays with a human; the ranked
choices asked of the operator are at the end. Nothing has been posted outside
this repository.

**Title to file:** KLayout LVS: the inductor `LA`/`LB` PCell texts are
connected as net names, so an inductor port on a named top-level pin net
reports a strict top-port mismatch (`'LA,VDD' vs. 'VDD'`) on a net the
cross-reference itself pairs.

This report describes the runset, not any one block, and is independent of
report A ([`inductor-terminal-order.md`](inductor-terminal-order.md)): A is
about *which physical winding becomes which device terminal*; B is about
*what the nets get called*. The block-scale measured outcome quoted below is
attributed to the existing recorded run (`layout/PROVENANCE.md` §14.6); no
new EDA run was made for this report.

## Where the behaviour lives, per revision

Paths are under `ihp-sg13g2/libs.tech/klayout/tech/lvs/` (`rule_decks/`
for the decks). Revisions checked through the GitHub REST API and
raw file fetches on 2026-11-20:

- `dev` head `cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8` (2026-11-10).
- Last `dev` commit touching `…/tech/lvs`:
  `27071f58a5196012f0702fa2366ec7de8fea381e` (2026-10-07, "[KLayout LVS]:
  Changelog and testing README for class-based RF matching"); the six
  inductor rule-deck files and `sg13g2.lvs` are byte-identical between the
  two commits (compared locally, blob for blob), so both carry the same
  behaviour.
- Release tag `v0.3.0` → commit `5cccb161f7492697cfa52eb14dc03beb00bdca9e`
  (the revision the klt digest allowlist pins).

**The behaviour is present at every revision above.** Each line number was
re-read in the file blob at the commit cited (not carried over from any
earlier note):

| Mechanism | `dev` head `cc9afba5` = `27071f58` | `v0.3.0` `5cccb161` |
|---|---|---|
| `rule_decks/layers_definitions.lvs` inductor pin layer | [`:420`][d-ld-420] `ind_pin  = get_polygons(27, 2)` | [`:420`][v-ld-420] |
| `rule_decks/layers_definitions.lvs` inductor text layer | [`:425`][d-ld-425] `ind_text = labels(27, 25)` | [`:425`][v-ld-425] |
| `rule_decks/ind_connections.lvs` **text→pin connect (the behaviour)** | [`:28`][d-ic-28] `connect(ind_pin, ind_text)` | [`:28`][v-ic-28] |
| `rule_decks/ind_derivations.lvs` same texts already used as *terminal markers only* | [`:44`][d-id-44], [`:46`][d-id-46] (`interacting`, no connect) | [`:42`][v-id-42], [`:44`][v-id-44] |
| `sg13g2.lvs` strict top-port gate that surfaces it | [`:505`][d-sg-505] `success = compare && flag_missing_ports` | [`:493`][v-sg-493] |

[d-ld-420]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/layers_definitions.lvs#L420
[d-ld-425]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/layers_definitions.lvs#L425
[d-ic-28]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_connections.lvs#L28
[d-id-44]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L44
[d-id-46]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L46
[d-sg-505]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/cc9afba57e0ec1b5ba77e6bbb638ba9dbe5866b8/ihp-sg13g2/libs.tech/klayout/tech/lvs/sg13g2.lvs#L505
[v-ld-420]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/layers_definitions.lvs#L420
[v-ld-425]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/layers_definitions.lvs#L425
[v-ic-28]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_connections.lvs#L28
[v-id-42]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L42
[v-id-44]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/rule_decks/ind_derivations.lvs#L44
[v-sg-493]: https://github.com/IHP-GmbH/IHP-Open-PDK/blob/5cccb161f7492697cfa52eb14dc03beb00bdca9e/ihp-sg13g2/libs.tech/klayout/tech/lvs/sg13g2.lvs#L493

## What happens (runset-level, generic)

1. The PDK's inductor PCells write `LA`/`LB` (and `LC`) texts on layer
   27/25, one per winding port, as terminal identification.
2. `ind_connections.lvs` line 28 connects that text layer into the net:
   `connect(ind_pin, ind_text)`. From then on every `LA`/`LB` text is a
   net-name contributor on the pin net it sits on. (The electrical joins
   are the neighbouring `connect(ind2_ports, ind_pin)` and
   `connect(ind_pin, ind_wind_layer)` lines; texts carry no geometry, so
   line 28 contributes naming only.)
3. In any normal flow instance the spiral sits on nets that already have
   names of their own, from explicit pin texts (a `VDD` pin text, an `OUTN`
   pin text, …). The extracted net then carries two labels and its name
   becomes the comma-joined `LA,VDD`.
4. Strict top-port mode (`sg13g2.lvs`: `success = compare &&
   flag_missing_ports`, logged as "missing/mislabeled top-level ports are
   treated as errors") then reports `Port mismatch 'LA,VDD' vs. 'VDD'` — a
   **name** finding on a net the cross-reference itself pairs. The compare
   matches; the overall verdict is still FAIL because of the name.

The PDK's own inductor unit testcases do not catch this: standalone
patterns have no other net names, the PCell texts are the intended names,
and nothing joins.

## How it was observed in this block (attributed to the §14.6 record run)

The record compare of 2026-10-10 (`layout/PROVENANCE.md` §14.6,
`layout/lvs/vco-lvs-record.json` → `verdict_of_record.strict_port_check`)
pairs **43/43 devices, 10/10 nets and 9/9 pins**, and the runset's strict
top-port check still logs exactly three errors, one per pin net that
carries a spiral PCell text:

- `Port mismatch 'LA,VDD' vs. 'VDD'` (L1's `LA` on the `VDD` strap),
- `Port mismatch 'LB,OUTN' vs. 'OUTN'` (L2's `LB`),
- `Port mismatch 'LB,OUTP' vs. 'OUTP'` (L1's `LB`).

`run_lvs.py`'s summary says FAIL for that run and the record says so; the
findings are recorded, not suppressed — there is no
`--ignore_top_ports_mismatch`, and none is wanted (#162 requires a clean
strict top-port result with no name exception).

## Duplicate check (2026-11-20, read-only REST)

Searched `IHP-GmbH/IHP-Open-PDK` issues and pull requests (the search API
covers both; no posting, no reactions):

- Queries: "LVS port mismatch" (18 hits), "flag_missing_ports" (4),
  "ind_connections" (0), "net name label LVS" (12), "LA,VDD" (2),
  "strict top port" (6), "inductor label" (6), "PCell text net name" (4),
  "port name comma" (1), "multiple labels net" (3).
- Read in full or skimmed to disposition, none covers this behaviour:
  - [#1130](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1130) (open):
    SG13G2 IO **diode** leaves do not strict-deep LVS-match the official
    schematics; its "label-promotion" symptom is about hierarchical names
    on IO pads at a preview commit. Different device class, different
    mechanism.
  - [#484](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/484) (open): a
    user-placed label on the wrong net that the comparer does not flag —
    label-placement semantics, not device texts naming nets.
  - [#667](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/667) (open,
    umbrella "LVS Bugs"): device-extraction issues (ptap counts, resistor
    sizing); no port-naming item.
  - [#872](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/872) (closed):
    xschem symbol/netlist generation for LVS. Flow, not naming.
  - [#828](https://github.com/IHP-GmbH/IHP-Open-PDK/pull/828) (closed,
    matched "port name comma"): comma-separated **implicit net connections
    in the reader CLI/GUI** — reference-netlist syntax, not extracted net
    names.
  - [#1287](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1287),
    [#1343](https://github.com/IHP-GmbH/IHP-Open-PDK/issues/1343): as
    dispositioned in report A (parameter measurement at a crossover /
    centre-tap arrangement; `nr_r=1` PCell geometry) — neither is about
    net naming.

**Disposition: no existing report of this behaviour. This report is not a
duplicate.**

## Proposed fix

**Use the device markers to identify the terminals, and let explicit pin
text name the net.** The terminal identification in `ind_derivations.lvs`
(`ind_ports_.interacting(ind_text.texts(la_patt))`) needs no net name — it
already works purely geometrically. Only `ind_connections.lvs:28` turns
the same texts into net names. Two options, in increasing size:

1. **Marker-only (preferred, smallest):** drop the
   `connect(ind_pin, ind_text)` line so 27/25 texts name nothing; nets are
   then named only by explicit pin texts. The standalone unit testcases
   need their net names moved to explicit pin texts (their CDLs already
   list `la_N lb_N`; the layout side then carries matching pin texts).
   Note for report A's minimal reproduction: after this fix its `LA`/`LB`
   net names likewise come from explicit pin texts, not from the PCell.
2. **Precedence (compatible):** keep the connect, but where a net carries
   an explicit pin text, let the pin text name the net alone and demote
   the 27/25 text to a marker (attach 27/25 labels for naming only when
   the net has no pin text). More code in the deck, no testcase change.

Either way `LA,VDD` disappears as a net name, strict top-port mode sees
`'VDD' vs. 'VDD'` and passes, and a genuinely misnamed pin must still
fail. The proposal describes the fix; nothing is implemented here, no
suppression is added, and the layout is not altered to hide the finding.

### Regression test it needs

An **as-drawn (unmirrored) `inductor2`** whose two top pins carry
independently chosen explicit pin texts — names that are not `LA`/`LB`
(e.g. `NETA`/`NETB`) — run with strict top-port mode on. This isolates the
port-name behaviour from report A's mirroring. Before the fix it must
report `Port mismatch 'LA,NETA' vs. 'NETA'` (and the `LB` twin); after the
fix it must match with no port finding.

### Negative controls that must still be rejected

| Control | Change | Must be |
|---|---|---|
| misnamed top pin | one explicit pin text renamed (`VDD` → `VDDX`), reference unchanged | `mismatch` — strict checking must still catch a genuine wrong name after the fix |
| (a) genuine swap, (b1)–(b3) label abuse | report A's §14.6 controls | `mismatch` — terminal identity and label sanity live in the device compare, not in net naming, and must survive the naming change |
| N1–N3 | the §14 connectivity breaks (supply via, signal via, missing MIM) | `mismatch` ×3 |

Verification must retain the **schematic-derived reference** (never the
extraction re-read as reference), the **explicit port mapping**, and
**device/net/pin coverage** (in this block: 43/43 devices, 10/10 nets,
9/9 pins; the record run's numbers, `layout/lvs/vco-lvs-record.json`).

## When a runset with the port-name fix is pinned

The current pin records three strict-port errors and an overall FAIL.
On the first pin with the naming fix, update `IHP_LVS_DECK_SHA` and the
expectations together in [`layout/lvs.sh`](../lvs.sh).

- If the label-order step is still needed, update `WANT_FLAGS` to use the
  explicit net names (`VDD / OUTP` for L1 and `VDD / OUTN` for L2).
  Retiring that step depends on the terminal-order fix in report A.
- Replace the exact three-error expectation with a requirement for zero
  strict-port findings.
  Require VDD, OUTN and OUTP each to pair with its own reference name and
  require the runset log to report success. The misnamed-pin control must
  fail under the same strict settings.
- Regenerate the LVS record from the new run, including the findings and
  measured runset outcome in `verdict_of_record.strict_port_check`. Check
  the full device, net and pin coverage and update §14.6 with the new result.

## Decision asked of the operator (ranked, answer separately from report A)

1. **File this report at `IHP-GmbH/IHP-Open-PDK`** — the text above is
   ready to file verbatim; a human files it.
2. **Defer filing while klt investigates the pinned runset.** The proposed
   reproduction would establish whether strict top-port checking runs and
   where the findings appear. klt would report observable findings verbatim,
   keep the as-shipped failure visible, and identify the terminal-order
   limitation where distinguishable. This work uses the existing runset
   pin. [KLT #6903](https://github.com/2AMLogic/klayout-tools/issues/6903)

   A separate proposal would measure whether treating LA/LB as markers
   preserves genuine errors. Using a normalised result for signoff
   requires an operator ruling. [KLT #6914](https://github.com/2AMLogic/klayout-tools/issues/6914)
3. **Do not file**: the finding stays recorded as FAIL. Unlike report A
   there is no local accommodation to keep, but #162's strict top-port
   requirement stays unreachable on this runset.

Prepared in #417; blockers and evidence chain: #162, #62.
