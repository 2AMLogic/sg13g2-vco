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

Three tiers. Only tier 1 is inventory-pinned; tiers 2 and 3 are pinned by
other mechanisms and listed so an edit cannot miss them.

**Tier 1 — inventory-pinned members (40 files).** Changing any byte of these
without regenerating fails CI (`check-all.sh signoff-inventories`), naming the
file:

- Item 1 (`inventory-1-design-sources.json`, 3 members): `design/vco.sch`,
  `design/vco.spice`, `design/netlist.sh`.
- Item 9 (`inventory-9-testbenches.json`, 25 bindings): `sim/pdk.json` (the
  PDK pin: source, release tag `v0.3.0`, upstream tarball sha256), all 13
  `sim/*/testbench/*` templates, and the 11 runner scripts matched by
  `sim/**/*.sh` minus the `(/tests/|/records/|/netlist-snapshots/|/corners/)`
  exclusions.
- Item 10 (`inventory-10-repo-hygiene.json`, 12 members): `README.md`,
  `LICENSE`, `spec/target-spec.md`, the DR-003 and DR-004 decision records,
  all six `.github/workflows/*.yml`, `.github/scripts/check-all.sh`.

**Tier 2 — generator-owned artifacts (never hand-edited):**
`signoff/evidence/t1-item-{1,9,10}-*.json` (envelopes),
`signoff/characterization.md`, `signoff/t1-report.json` (the verdict of
record, written only by `.github/scripts/regen-signoff.sh` on a clean, gated
render).

**Tier 3 — manifest-cited artifacts (pinned by `content_hash` in
`signoff/manifest.json`, graded by `klt signoff`, not audited by
`inventories.py`):** `layout/drc/vco-drc-ihp.json` (items 2 and 3, pinned to
`layout/vco.gds`'s digest), `layout/erc/vco-erc.json` and
`layout/lvs/vco-lvs-record.json` (item 11), the six
`sim/oscillator-core/yield/yield-envelope-*.json` citations (item 6), the
vendored `signoff/design-evidence-tiers.md` (pinned via the report's
`source_doc_content_hash`), and the ratified spec table (item 8 reads its
digest as a characterization input).

Verified item-6 rule (spot-check at `9e27225`): each item-6 `content_hash`
equals the sha256 of the **samples document** its envelope names (e.g.
`yield-envelope-process-f0_bandcentre_hz.json` → sha256 of
`yield-samples-process-f0_bandcentre_hz.json`), not the envelope file's own
digest — that is what `klt yield` grading verifies. A pin computed from the
envelope's own bytes grades `stale_evidence` while CI stays green, because
the stale verdict itself renders reproducibly.

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
- No inventory pins anything under `layout/` or `sim/*/records/`: those are
  tier-3 manifest citations. A layout or record edit is not invisible — it is
  gated by `check-signoff.sh`'s byte-drift assert instead of
  `inventories.py --check`.
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
the exact check"; it matched all 40 members at the audit stamp):

```bash
git diff --name-only origin/main...HEAD \
  | grep -E '^(design/|sim/|README\.|LICENSE$|spec/|\.github/(workflows|scripts)/)'
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

`spec/target-spec.md` additionally carries the item-8 characterization input
digest, so it needs one more regeneration before the wrapper:

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
- `check-signoff.sh` (signoff CI): the committed `t1-report.json` must be
  byte-identical to a fresh render at the pin — a manifest citation whose
  artifact changed fails here.
- Exit-3 nuance: `klt signoff` treats "ran clean, ≥1 item unmet" (exit 3) as
  a successful render, so a *stale* verdict can render reproducibly green.
  The payload gates inside `regen-signoff.sh` plus the byte-drift assert are
  what keep the record honest; neither a clean exit nor a green CI run alone
  proves the evidence is fresh.
