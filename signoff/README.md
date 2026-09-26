# klt signoff: this block's graded T1 state

- **Status**: standing convention, established by issue #34. The verdict
  of record for this block's T1 (sim-validated) standing is the committed
  report rendered by `klt signoff --manifest` — never a hand-maintained
  checkbox list in an issue body.
- **Date**: 2026-09-21, issue #34.
- **Consumes**: `klt signoff` (klayout-tools, pinned release `0.6.0` from
  PyPI) and the vendored checklist below.
- **Does not**: grade anything itself. Every row's verdict comes from the
  tool's own mechanical parse-and-grade; this directory only declares what
  the block is (`block`, `kind`) and where each item's evidence lives.

## What lives here

| Path | What it is |
|---|---|
| `manifest.json` | The block manifest: `block`, `kind`, and the per-item `evidence` map `klt signoff --manifest` grades. The fleet roll-up (2AMLogic/2am#956) consumes exactly this file; `sg13g2-vco` is the row identity. |
| `t1-report.json` | The **verdict of record**: the committed `klt signoff --format json` output. CI re-renders the report on every push and PR and fails on any byte-drift (`.github/scripts/check-signoff.sh`), so a manifest citation whose artifact has since changed fails rather than rotting. |
| `design-evidence-tiers.md` | Vendored copy of the T1-T4 evidence-tier checklist `klt signoff` parses (see provenance below). Vendored so the render is reproducible from this repo alone, at a checklist revision this repo names and hashes, rather than at whatever revision the installed wheel happens to bundle (see "Why the checklist doc is vendored"). |

Today every item renders `unmet` with `reason: "no_evidence"`, and that
is the correct result: no evidence envelope exists yet for any item to
grade — no layout, no schematic-derived netlist, no `klt`-native run
artifact, and no PVT corner pass — and that absence, not the spec's
ratification state, is why the render is all-`unmet`.
`spec/target-spec.md` is now fully ratified (DR-003: nine rows RATIFIED
as targets; DR-004: rows 0/3/7, the three DR-003 left open) — and a
ratified target is explicitly *not met by any measurement*, so the
ratification state moves no row of this report. Per issue #34: an
all-`unmet` manifest is the honest
machine-readable statement of the gap — never hold the manifest back
until the block is further along, and never cite an envelope that does
not actually support an item just to make a row go green.

## The manifest contract

- **`kind: "analog"`** — confirmed against the block, not taken from the
  issue: `spec/target-spec.md` declares a *single free-running LC
  voltage-controlled oscillator* and `spec/porting-plan.md` §2 confirms
  there is no digital partition (no divider chain, no RTL). A
  mixed-signal declaration would be wrong here.
- **`evidence`** — the map from item id to evidence entry, currently
  empty. When evidence starts landing, cite it honestly:
  - **File-backed** — `{"file": "<repo-root-relative path>", "content_hash": "sha256:<hash>"}`.
    Every citation MUST pin `content_hash` to the committed artifact it
    was produced against (`provenance.input.content_hash` of the cited
    `klt` envelope — see `docs/cli/signoff.md` → "Tier-verdict report"):
    an unpinned citation cannot have its freshness verified, and a
    passing report against last week's netlist is evidence of nothing.
    A mismatched pin renders the item `unmet`/`stale_evidence`.
  - **Command-backed** — `{"command": [<argv>], "cwd": ..., "content_hash": ...}`:
    `klt signoff` runs the command and grades that run's own exit status
    and stdout.
  - **Item key discipline** — bare `"<id>"` for every item on this
    analog block (per-kind `<id>.<analog|digital>` keys exist only for
    mixed-signal blocks).
  - **Items 1, 2, 9 and 10 accept any passing native envelope** — the
    tool cannot check topical relevance for them, so citing them is this
    repo's responsibility, not the grader's. The honest default is to
    leave them uncited until an artifact genuinely backing each claim
    exists (`docs/cli/signoff.md` → "Items 1, 2, 9, and 10").
  - **Item 11 stays uncited — but the reason changed.** Under the old
    `0.5.0` pin the blocker was the *build*: the item-11 grading rules
    (klayout-tools#2057, plus the per-item build-grading guard of #2201)
    were on klayout-tools `main` but in no release, so a citation would
    have fallen through to rules the running build did not have and could
    have rendered `met` from nothing. **That gate is closed**: the pin is
    now `0.6.0`, which contains #2057 and #2201, and the refreshed report
    proves it mechanically — `build_t1_item_count: 11` equals
    `t1_item_count: 11` and item 11 carries `graded_by_build: true`, so
    the running build has rules for every row the vendored checklist
    renders. The row still renders `unmet`/`no_evidence`, and now for the
    only remaining reason: **there is no evidence to cite.** No layout,
    no supply routing and no `klt erc` supply-spec run exist in this repo
    yet, so item 11 has nothing to point at — the same "has a row, even
    if unmet" state issue #34 requires. Cite it when a real `klt erc`
    envelope exists, not before. Item 11's blocking work is tracked in
    the companion issue; its known upstream friction for full-custom
    analog is also on file (klayout-tools#2234, #2192) — #2234's
    `ties[].tap_boxes` form and #2255's `well_layer: null` +
    `well_boxes` form are both present in the refreshed checklist, so
    they are declarable rather than structurally unreachable now.

## Why the checklist doc is vendored

The tiers checklist is `klt`'s runtime tool data: `klt signoff --manifest`
renders the item skeleton mechanically from the doc, so the checklist and
the grader can never drift.

**The original reason for vendoring is retired.** Released `klt 0.5.0`
(2026-09-15) bundled a **ten-item** checklist, so rendering against the
bundled doc would have silently reported ten items and no item-11 row at
all. The pinned `0.6.0` release bundles the **eleven-item** doc — in fact
byte-identical to the vendored copy below — so that specific failure
mode no longer exists.

**The vendoring stays anyway, for the reason that outlives any one
release**: the checklist a verdict was graded against is part of the
verdict. A render that takes its checklist from whatever the installed
wheel happens to bundle is reproducible only by someone holding that
exact wheel; a render against a committed, hashed copy is reproducible
from a clone of this repo alone. Since klayout-tools#2175 that is
machine-checked rather than asserted: the report carries
`source_doc_content_hash`, so the committed record now names the exact
checklist bytes it was graded against and CI's byte-drift gate fails the
moment the vendored doc and the record disagree. `signoff/README.md`'s
commands and `.github/scripts/check-signoff.sh` therefore both keep
passing `--tiers-doc signoff/design-evidence-tiers.md` — the documented
vendoring pattern (`docs/cli/signoff.md` → "Where the tier doc comes
from", `KLT_TIERS_DOC`). Retiring the vendoring in favour of the wheel's
bundled doc would be a separate, deliberate decision; it is not implied
by the pin bump.

**Provenance** (keep updated on every refresh):

| Field | Value |
|---|---|
| Source | `2AMLogic/klayout-tools` `docs/design-evidence-tiers.md` |
| Pinned at | commit `0882541638acaec9ceb43c4df77b47d5a1a179db` (2026-09-22), i.e. the doc as of upstream tag `v0.6.0` |
| File SHA-256 | `63eeec72e3d849761cf32dcf091af5728b069b1515e32bb3138e9454303671e5` |
| Last doc-touching upstream commit | `0882541638acaec9ceb43c4df77b47d5a1a179db` (feat(signoff): carry a mixed-signal manifest's declared partition boundary, #2303) |
| License | Apache-2.0 (klayout-tools is Apache-2.0; this copy is verbatim, unmodified) |

This copy is byte-identical to the checklist bundled inside the pinned
`klayout-tools==0.6.0` wheel (`klayout_tools/data/design-evidence-tiers.md`,
same SHA-256), so the vendored doc and the pinned build agree by
construction — verified against a clean `pip install klayout-tools==0.6.0`,
not inferred from the tag.

**Upgrade procedure**: copy the newer doc from klayout-tools verbatim,
update the provenance table, then refresh and commit `t1-report.json`
(the byte-drift gate forces exactly this — the report pins the checklist
it was graded against, and a checker that is not also checking "which
checklist said so" is checking half the question). A newer doc may also
outrun the pinned build (`graded_by_build`, klayout-tools#2201): an item
the pinned `klt` has no rules for renders `unmet` whichever way it is
cited, so guard new-item citations behind a matching klt pin bump. Since
#2201 that condition is readable straight off the record rather than
reasoned about — compare `build_t1_item_count` against `t1_item_count`
(equal, `11` and `11`, on the current record) and check each row's
`graded_by_build`.

## The verdict of record and its drift gate

`t1-report.json` is the **current** verdict — a rolling record, not an
append-only `sim/`-style measurement (git history is its own archive).
It is refreshed deliberately, in the same commit as whatever change
re-grades the block:

```bash
python3 -m pip install klayout-tools==0.6.0   # the pinned release
klt signoff --manifest signoff/manifest.json \
  --tiers-doc signoff/design-evidence-tiers.md --format json \
  > signoff/t1-report.json
```

`.github/scripts/check-signoff.sh` (self-tested by
`test-check-signoff.sh`, both run in CI — a checker that cannot fail is
indistinguishable from no checker at all) re-renders and byte-compares on
every push and PR. "Runs clean" follows `docs/cli/signoff.md`'s
exit-code contract: exit 0 (all items met) and exit 3 (ran successfully,
at least one item unmet) are both successful renders — an all-unmet
report is a correct verdict, not a CI failure. The payload gates on its
own fields (`block`, `kind`, `schema_version`, 11 rendered items, no
error envelope), not the exit code alone.

**The build identity is now in the record, not in prose.** The former
"known field gap" section here described what `klt 0.5.0` could not
report; the `0.6.0` pin closes it. The committed record now carries the
fields klayout-tools#2175/#2176/#2201 added, and they say this:

| Field | Value on the current record | What it settles |
|---|---|---|
| `build.version` / `build.package_version` | `0.6.0` / `0.6.0` | which `klt` graded this verdict — no longer inferred from the CI install step |
| `build.git_tag` / `build.is_release` | `v0.6.0` / `true` | the grading build is the tagged PyPI release, not a working copy |
| `build.dirty` | `false` | no uncommitted tool changes in the grading build |
| `build.grading_ruleset_id` | `sha256:0d8cc27c…a17156` | the grading rules themselves are hashed, so a rules change is drift even at an unchanged version string |
| `source_doc_content_hash` | `sha256:63eeec72…3671e5` | the exact checklist bytes graded — matches the vendored doc's SHA-256 above |
| `build_t1_item_count` vs `t1_item_count` | `11` vs `11` | the build has rules for every row the checklist renders; nothing is graded by a build that lacks rules for it |
| `items[].graded_by_build` | `true` on all 11 T1 rows | per-row confirmation of the same, including item 11 |

So the three things previously held together by prose plus a CI install
step — which build graded the record, which checklist it graded against,
and whether the build actually had rules for every row — are each
machine-readable off the committed JSON, and the CI byte-drift gate fails
the moment any of them moves.

**One gotcha when re-rendering locally.** `build.package_version` alone
does not identify the release: a git build of klayout-tools can report
`package_version: "0.6.0"` while carrying different grading rules and a
different bundled checklist (it self-reports the difference as
`version: "0.6.0+g<sha>"`, `git_tag: null`, `is_release: false`, and a
different `grading_ruleset_id`). Such a build satisfies a
`klayout-tools==0.6.0` requirement in an already-provisioned environment
but renders a record that byte-drifts against CI. Render from a clean
`python3 -m pip install klayout-tools==0.6.0` (a throwaway venv is
enough) and, before committing, check that the record says
`"git_tag": "v0.6.0"` and `"is_release": true`.

## Sources

- `klayout-tools` grader contract: `docs/cli/signoff.md` → "Tier-verdict
  report" (2AMLogic/klayout-tools).
- T1-T4 ladder and the 11-item checklist: `docs/design-evidence-tiers.md`
  (2AMLogic/klayout-tools) — the vendored copy above.
- This block's gap-to-T1 tracker: issue #3 (this report is its verdict
  of record; the hand-maintained checkbox list is retired).
- Fleet roll-up consuming this manifest: 2AMLogic/2am#956.
