# Pin safety: the hash-pinned signoff surface, audited

This is the audit of record and the operator runbook for every file whose
**bytes** this repo pins by sha256. It is not a tutorial: the generators
(`signoff/inventories.py`, `signoff/characterization.py`) own the artifact
formats, and every command below is copy-exact — a hash is never transcribed
by hand anywhere in the flow.

- **This file is itself unpinned.** It is not an inventory member and must
  never be added to one without a `signoff/inventories.py` change: membership
  is generator-owned, not doc-owned.
- The authoritative member list is **always** the inventories
  (`signoff/evidence/inventory-*.json`), re-derived live — never the grouped
  lists below, which are a snapshot.

## Audit of record

- **Audited at**: 2026-11-17, `main` @ `9e27225` (merge of PR #390), klt pin
  `0.8.0` (`.github/klt-version`). Re-derive with the commands in the runbook
  before relying on any statement here; a member edit invalidates the stamp.
- **Method** (three independent checks):
  1. `python3 -I signoff/inventories.py --check` — the CI drift check,
     rebuilding every inventory from the live tree and comparing member by
     member.
  2. `sha256sum` recomputed over each of the 40 members the three inventories
     list, compared against the recorded `sha256:<hex>` values.
  3. The chain bindings recomputed: envelope
     `provenance.input.content_hash` == sha256 of its inventory's bytes
     (items 1, 9, 10) and `signoff/manifest.json` `evidence` pin == that same
     value.
- **Result: 40/40 members match; all six bindings hold; zero drift.**

## The pinned surface (snapshot @ `9e27225`)

Four tiers. Only tier 1 is inventory-pinned; tiers 2–4 are pinned by other
mechanisms and listed so an edit cannot miss them.

**Tier 1 — inventory-pinned members (40 files).** Changing any byte of these
without regenerating fails CI (`check-all.sh signoff-inventories`), naming the
file:

- Item 1 (`inventory-1-design-sources.json`, 3 members): `design/vco.sch`,
  `design/vco.spice`, `design/netlist.sh`.
- Item 9 (`inventory-9-testbenches.json`, 25 bindings): `sim/pdk.json` (the
  PDK pin: source, release tag `v0.3.0`, upstream tarball sha256), all 13
  `sim/*/testbench/*` templates, and the 11 runner scripts matched by
  `sim/**/*.sh` minus the `(/tests/|/records/|/netlist-snapshots/|/corners/)`
  exclusions **that also reference a `sim/*/testbench/*` file by basename**.
  That last clause is a content test, not a path filter: the glob selects 27
  candidate scripts, the basename reference narrows them to the 11 members
  (`_runners` in `signoff/inventories.py`). Membership therefore depends on
  a script's *text*: an edit that adds or removes a testbench-basename
  reference adds or removes a tier-1 member without touching any path.
- Item 10 (`inventory-10-repo-hygiene.json`, 12 members): `README.md`,
  `LICENSE`, `spec/target-spec.md`, the DR-003 and DR-004 decision records,
  all six `.github/workflows/*.yml`, `.github/scripts/check-all.sh`.

**Tier 2 — generator-owned artifacts (never hand-edited):**
`signoff/evidence/t1-item-{1,8,9,10}-*.json` (envelopes; the item-8 one,
`t1-item-8-characterization.json`, is additionally manifest-pinned — see
tier 3), `signoff/characterization.md`, `signoff/t1-report.json` (the verdict of
record, written only by `.github/scripts/regen-signoff.sh` on a clean, gated
render).

**Tier 3 — manifest-cited artifacts (`signoff/manifest.json`, graded by
`klt signoff`, not audited by `inventories.py`).** The manifest uses two
citation forms, and they are not equally strong. One rule governs every
`content_hash` on this surface: it pins the artifact's declared **provenance
input** — the artifact it was produced from — not the cited file's own bytes.

- *`content_hash` pins (of the declared provenance input):*
  `layout/drc/vco-drc-ihp.json` (items 2 and 3) and `layout/erc/vco-erc.json`
  (item 11) both pin `layout/vco.gds`'s digest — the GDS bytes are gated,
  the records' own bytes are not; the six
  `sim/oscillator-core/yield/yield-envelope-*.json` citations (item 6) pin
  the **samples document** each envelope names (verified rule below);
  `signoff/evidence/t1-item-8-characterization.json` (item 8 envelope) pins
  `signoff/characterization.md`'s digest — the characterization render is
  gated, the envelope's own bytes are not.
- *The one own-bytes pin:* the vendored `signoff/design-evidence-tiers.md`
  is pinned on its own bytes via the report's `source_doc_content_hash` —
  the only `content_hash` on this surface that covers the cited file itself.
- *JSON-pointer citations (not byte-pinned):* `layout/lvs/vco-lvs-record.json`
  is cited as `"pointer": "/klt_leg/lvs/response"` with **no `content_hash`
  anywhere**. Only the bytes under that pointer reach the render; an edit
  elsewhere in that file is caught by no digest, so treat the record as
  ungated except through item-11 grading.

That ungated-own-bytes caveat is not unique to the LVS record. Under the
rule above, an edit to the DRC or ERC record's own bytes outside the one
digest-bearing field — the `status`, the violation count, the
`coverage_assertion` — or to the item-8 envelope's `summary`/`status` is
caught by no digest anywhere either. Treat each of these files the same way:
vouched for on its provenance input, ungated on its own bytes except
through grading.

Item 8's characterization inputs (their digests are bound into the tier-2
render): `characterization.py`
embeds the digests of **three** inputs — `spec/target-spec.md` (itself a
tier-1 member),
`signoff/characterization-rows.json`, and `sim/record-currency.json` —
rendered into `signoff/characterization.md` (tier 2). An edit to any of the
three needs `characterization.py --regen`; the wrapper does not run it
(runbook step 2).

Verified item-6 rule (spot-check at `9e27225`): each item-6 `content_hash`
equals the sha256 of the **samples document** its envelope names (e.g.
`yield-envelope-process-f0_bandcentre_hz.json` → sha256 of
`yield-samples-process-f0_bandcentre_hz.json`), not the envelope file's own
digest — that is what `klt yield` grading verifies. A pin computed from the
envelope's own bytes grades `stale_evidence` while CI stays green, because
the stale verdict itself renders reproducibly.

**Tier 4 — byte-pinned under their own gates, outside the manifest.** These
pins live in evidence files, not `signoff/manifest.json`, and each has a
dedicated CI gate; an edit to the pinned bytes fails that gate, not
`inventories.py --check`:

- **37 simulation decks, 36 gated.** 36 of the 37 tracked
  `sim/*/records/<stamp>/decks/*.spice` are pinned by
  `environment.netlist_sha256` in their paired
  `records/<stamp>/reports/*.json`, gated by `check-all.sh deck-integrity`
  (`check-record-deck-integrity.sh` → `record_currency.py integrity`;
  at the audit stamp: 36 verified pairs, 0 unchecked unpaired reports).
  A deck edit without regenerating its report fails the gate, named. The
  exception:
  `sim/bn-substrate-tank/records/20261010-overlay-smoke-b233273/` keeps its
  report at the record root (`report.json`) instead of under `reports/`, so
  its deck `bn-sub__tt_v1.5.spice` falls outside the pairing convention and
  no gate reads its `netlist_sha256` — the digest is committed and matches,
  it just sits at a path the gate never reads. The gate's `unchecked
  unpaired reports` counter counts reports without decks, never decks
  without reports, which is why it still prints 0. Gate-side fix tracked in
  #392; this document states the exception rather than claiming coverage.
- **`layout/vco.gds`.** Eight layout records carry its digest —
  `layout/vco_manifest.json`, `layout/drc/vco-drc.json`,
  `layout/drc/vco-drc-ihp.json`, `layout/drc/vco-drc-ihp-assertion.json`,
  `layout/drc/vco-cnt-c-control.json`, `layout/lvs/vco-lvs-ihp.json`,
  `layout/lvs/vco-lvs-record.json`, `layout/erc/vco-erc.json` — gated by
  `check-all.sh layout-evidence` (`check-layout-evidence.sh`), which
  recomputes the GDS digest itself rather than trusting any citation.
  Note the tier-3/4 split here: `layout/drc/vco-drc-ihp.json` and
  `layout/erc/vco-erc.json` are *also* manifest-cited (tier 3) — on
  `layout/vco.gds`'s digest, not their own bytes — and the LVS record is
  pointer-cited only (tier 3). None of the three records' own bytes
  carries a digest anywhere; what all three vouch for is the GDS digest
  (tier 4).

## N/A findings (explicit, so nothing reads as an open question)

- `signoff/README.md` (this directory's own guide) is **not** a pinned
  member; the inventory-pinned `README.md` is the repo-root project README.
  The two are easy to conflate — an edit to `signoff/README.md` needs no
  regeneration, an edit to the root `README.md` goes through the full
  runbook path.
- `signoff/evidence/inventory-t1.json` and
  `signoff/evidence/inventory-meta.json` **do not exist** and have never
  existed. The authoritative inventory names are the three per-item files
  above; a runbook or brief that names the aggregate forms is describing
  files that are not there.
- No inventory pins anything under `layout/` or `sim/*/records/` — true, but
  that does not make those edits ungated, and "tier-3 manifest citations"
  was the wrong disposition. The bytes there are pinned under their own
  gates (tier 4): the 36 paired sim decks by their reports'
  `environment.netlist_sha256` (`check-all.sh deck-integrity`), and
  `layout/vco.gds` by the eight layout records
  (`check-all.sh layout-evidence`). What *is* tier 3 under those trees is
  the set of manifest-cited record/envelope files
  (`layout/drc/vco-drc-ihp.json`, `layout/erc/vco-erc.json`, the item-6
  yield envelopes; the LVS record is pointer-cited only) — but per the
  tier-3 rule, their `content_hash` pins cover their provenance inputs,
  not their own bytes. A deck or GDS edit is caught by the tier-4 gates,
  not by `check-signoff.sh`'s byte-drift assert.
- `sim/pdk.json`'s `tarball_sha256` pins the upstream PDK release tarball,
  not a repo file; the repo-file pin for `sim/pdk.json` itself is the tier-1
  member hash. They are separate bindings and both hold.
- The netlist freshness gate `design/netlist.sh --check` is recorded
  `ran_in_signoff_ci: false`: the item-1 inventory attests that
  `design/vco.sch` and `design/vco.spice` are the inventoried bytes, not that
  the netlist was re-derived from the schematic. That limitation is stated in
  the envelope summary and `signoff/README.md`; run the gate where xschem and
  the IHP-Open-PDK exist.

## Operator runbook

### 1. Is the file I am about to touch pinned?

Triage net (regex, deliberately over-inclusive — a hit means "stop and use
the exact check"; it matched all 40 inventory members at the audit stamp,
and `layout/` is in the net because that tree carries tier-4 pins no
inventory knows about):

```bash
git diff --name-only origin/main...HEAD \
  | grep -E '^(design/|sim/|layout/|README\.|LICENSE$|spec/|\.github/(workflows|scripts)/)'
```

Exact answer — the authoritative list, derived live from the inventories:

```bash
jq -r '[(.members[]?.path // empty), (.testbenches[]?.path // empty), (.runners[]?.path // empty), (.pdk.pin_file.path // empty)] | .[]' \
  signoff/evidence/inventory-*.json | sort -u
```

Did this branch touch a pinned member (empty output / exit 1 = no):

```bash
git diff --name-only origin/main...HEAD \
  | grep -Fxf <(jq -r '[(.members[]?.path // empty), (.testbenches[]?.path // empty), (.runners[]?.path // empty), (.pdk.pin_file.path // empty)] | .[]' signoff/evidence/inventory-*.json)
```

A "no" here is path-derived, and one tier-1 class can change membership
without changing any path: an item-9 runner edit that adds or removes a
`sim/*/testbench/*` basename reference (see tier 1 above). For any
`sim/**/*.sh` edit the intersection is not sufficient on its own — run
`python3 -I signoff/inventories.py --check` (step 3 below), which re-derives
membership from the live tree; that is the authoritative answer.

A hit the inventories do not list is still gated when it is a tier-4 or
tier-3 surface: `layout/vco.gds` → regenerate the affected records
(`layout/generate.sh`, `layout/drc.sh`, `layout/lvs.sh`, `layout/erc.sh`)
and run `check-all.sh layout-evidence`; a `sim/*/records/…/decks/*.spice`
edit → regenerate the paired report so its `environment.netlist_sha256`
matches, then run `check-all.sh deck-integrity`; a manifest-cited record or
envelope → tier 3, regrade with `klt signoff` (the wrapper).

### 2. Make the edit, then regenerate — never hand-write a hash

Recompute a member's digest (the inventories carry the `sha256:<hex>` prefix;
the generator adds it — this command is for eyeballing, not for pasting):

```bash
printf 'sha256:%s\n' "$(sha256sum <file> | cut -d' ' -f1)"
```

The sanctioned regeneration, which covers inventories, envelopes, manifest
pins and the report in one atomic, gated step (a failed render leaves the
committed record untouched):

```bash
.github/scripts/regen-signoff.sh
```

Three files carry item-8 characterization input digests —
`spec/target-spec.md`, `signoff/characterization-rows.json`, and
`sim/record-currency.json` — and the wrapper does **not** cover them (it
runs only `inventories.py --regen`). An edit to any of the three needs this
regeneration first, or `check-all.sh signoff-characterization` goes red:

```bash
python3 -I signoff/characterization.py --regen
```

Hand-editing an inventory, an envelope, or `signoff/t1-report.json` is always
wrong; the two generators and the guarded wrapper are their only writers.

### 3. Verify before committing

```bash
python3 -I signoff/inventories.py --check   # inventory drift; names the file
.github/scripts/check-signoff.sh            # committed report == fresh render at the pin
git status --short                          # expect: your file(s) + the regenerated
                                            # inventory/envelope/manifest/report set, nothing else
```

## What CI enforces

- `check-all.sh signoff-inventories` → `inventories.py --check`: member
  changed, added or removed without regenerating fails, named.
- `check-all.sh signoff-characterization` → `characterization.py --check`:
  a drifted row line fails, named.
- `check-all.sh deck-integrity` → `check-record-deck-integrity.sh`
  (`record_currency.py integrity`): a paired report/deck `netlist_sha256`
  mismatch — or a malformed paired report — fails, named (tier 4; 36
  verified pairs at the audit stamp; 37 decks tracked, the one unpaired
  exception named under tier 4).
- `check-all.sh layout-evidence` → `check-layout-evidence.sh`: a layout
  record carrying a stale `layout/vco.gds` digest fails, named (tier 4;
  the checker recomputes the GDS digest itself, 8 records at the audit
  stamp).
- `check-all.sh model-inputs` → `check-model-inputs.sh`: a committed
  `sim/**/records/<id>-model-inputs.json` must match its retained
  `netlist-snapshots/<id>/model-inputs/` bytes (issue #139). Listed here for
  completeness: it pins nothing today (0 manifests verified at the audit
  stamp), so it has no tier-map entry — a gate that cannot run is not one
  that passed.
- `check-signoff.sh` (signoff CI): the committed `t1-report.json` must be
  byte-identical to a fresh render at the pin — a manifest citation whose
  artifact changed fails here.
- Exit-3 nuance: `klt signoff` treats "ran clean, ≥1 item unmet" (exit 3) as
  a successful render, so a *stale* verdict can render reproducibly green.
  The payload gates inside `regen-signoff.sh` plus the byte-drift assert are
  what keep the record honest; neither a clean exit nor a green CI run alone
  proves the evidence is fresh.
