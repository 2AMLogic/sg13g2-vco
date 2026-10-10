# sim/ — ngspice testbenches and append-only evidence records

Per this repo's `CLAUDE.md`: **verification is the product, no claim without a
testbench, PVT corners on every recorded result**, and everything here is
**append-only evidence** — a re-run mints a new, timestamped record; nothing
under `records/`, `netlist-snapshots/` or `corners/` is ever edited or deleted
after it lands. The convention follows `spec/porting-plan.md` §3, which names
it as the one category that transfers to this block from the catalog's more
mature siblings unchanged.

**Enforcement.** The `sim-append-only` job in `.github/workflows/signoff.yml`
runs `.github/scripts/check-sim-append-only.sh` on every pull request and fails
on any change other than a pure addition to a `records/`, `netlist-snapshots/`
or `corners/` directory anywhere below `sim/` (including
`inductor-model/em-extraction/records/`); a rename counts as delete + add and
fails. There is **no exemption** (no label, no PR-body marker): correct an old
record by adding a new record that supersedes it. Working output such as
`em-extraction/results/` is not covered. Its self-test is
`.github/scripts/test-check-sim-append-only.sh`.

## Experiments

> **Pre-#79 numbers:** the `phase-noise/` and `oscillator-core/` rows below describe the
> **pre-#79 netlist** (varactor `bn` tied to the tank node, since corrected to the substrate).
> Their f0, tuning-range, power and Kvco figures are not current: DR-005 puts the band centre
> near 4.3 GHz, outside the ratified row-1 band. See
> [DR-005](../spec/decision-records/DR-005-varactor-bn-substrate.md), the notes in
> [`phase-noise/`](phase-noise/README.md) and [`oscillator-core/`](oscillator-core/README.md),
> and the `bn-substrate-tank/` row. The re-tune closed with no defensible candidate (#93); the decision is pending in [DR-006](../spec/decision-records/DR-006-row2-shortfall-bn-substrate-varactor.md) (#184, status proposed); regeneration (#94) is sequenced after it.

| Directory | Claim under test | Status |
|---|---|---|
| [`tank-characterization/`](tank-characterization/) | L / Q / SRF of the passives an LC tank on this PDK would be built from, over a wide candidate band | MIM cap characterized over the full PVT grid from the PDK's own models; **the spiral inductor cannot be characterized from the PDK — v0.3.0 ships no ngspice inductor model** (see that README's "The inductor gap"). The inductor half is covered by the model below, whose error bars travel with every number it produces. |
| [`inductor-model/`](inductor-model/) | that the analytic spiral-inductor model this repo ships implements the closed form it claims to, over a process × temperature grid; **and** ([`em-extraction/`](inductor-model/em-extraction/), #9) an openEMS extraction of the PDK's own inductor PCell, measured against it | Analytic: 27/27 known-answer points pass to 0.003 %. **This validates the implementation, not the physics** — the model is an *analytic screening* model with stated error bars (±5 % on L, Q an upper bound, 0.5–20 GHz), **not** a PDK model and **not** an EM extraction. EM extraction (openEMS v0.37.0-rc2, FDTD, 0.1–30 GHz): fit residual < 1 % rms within its fit band for all 3 LVS-testcase geometries; now the authoritative model for those 3 geometries — measured L within +5–8 % of the analytic model (confirms its bar), Q +17–35 % (confirms its "upper bound" direction), **SRF 50–77 % lower than analytic predicted** for the two multi-turn geometries. |
| [`varactor-characterization/`](varactor-characterization/) | C(V), dC/dV (Kvco) and Q(V,f) of the MOS varactor (`sg13_hv_svaricap`) and the two junction-diode candidates (`dantenna`, `dpantenna`) — the tuning-mechanism evidence `tank-characterization`'s finding 6 hands off | 216/216 simulation points PASS across 5 MOS × 3 diode process corners × 3 temperatures × 9 control-voltage points; known-answer method check passes to 0.1 % at every point. MOS varactor: `Cmax/Cmin` up to 2.08×, `Q` 224 down to 0.19 depending on geometry and frequency. Junction diodes: `Cmax/Cmin` only 1.03–1.24×, `Q` ~1–1.7 — not competitive tuning devices. Ratifies no `spec/target-spec.md` row. |
| [`phase-noise/`](phase-noise/) | `spec/target-spec.md` **row 4** — single-sideband phase noise `L(Δf)` of `design/vco.sch` at 1 MHz and 10 MHz offsets from a band-centre carrier — measured by an **ISF (Hajimiri–Lee) derivation**, with the estimator justified against the alternatives, its variance across realisations, and its limits | **(pre-#79 netlist)** Estimator shipped and known-answer checked: 42/42 quantities within derived tolerances, including an end-to-end identity against Leeson's independently-derived linear-tank kernel to 0.005 dB. **The estimator choice is forced by a simulator fact, not a preference**: ngspice's `.tran` carries no device noise, so a periodogram or a jitter conversion of this deck measures the solver, not the circuit — at ~640 CPU-hours per corner. The ISF route costs ~1.2 CPU-hours per corner because it never estimates a spectrum. Measured at **one declared corner**, so it **grades no row**; the 135-point row-10/11 grid (~150 CPU-hours) is blocked on the same `klt sim` gap as `oscillator-core` ([klayout-tools#2511](https://github.com/2AMLogic/klayout-tools/issues/2511)). |
| [`oscillator-core/`](oscillator-core/) | the first experiment here that contains an **oscillator**: start-up from the differential initial condition, `f_osc` over the full 0.0–3.3 V `Vctrl` domain (hence the row-2 tuning ratio and the row-3 `Kvco` curve), the large-signal supply current, the differential-mode check, and the row-6 startup margin — all against the committed `design/vco.spice`, over the row-10/11 PVT grid | **(pre-#79 netlist)** Bench and method shipped and exercised against the real netlist; **the graded PVT grid has not run, so no row is graded.** Extractor known-answer check: 56/56 quantities within tolerances *derived* from the estimator's own discretization bounds. Measured **pilot subset** (typical process corner, three row-11 temperatures, 13 transients + a 9-rung margin ladder): the oscillator starts at every point from the 10 mV `.ic` (settling 0.49–1.26 ns), is cleanly differential (`f(TAIL)/f_osc` = 2.000, common-mode amplitude ≤ 1.1 % of differential), tunes 4.61–5.45 GHz with a geometric band centre of 4.96–5.02 GHz, and draws 0.99–1.05 mW large-signal. **`Kvco` is strongly non-linear** — at 27 °C the per-segment slope runs from ~0 to −640 MHz/V, all of the tuning sitting above `Vctrl` ≈ 1.2 V. The remaining 134 PVT points (~180 CPU-hours) are blocked on `klt sim`, which cannot express this deck (no OSDI device loading, no `ngbehavior` selection, no `ihp-sg13g2` off-host image) — reproduced in [`oscillator-core/klt-sim/`](oscillator-core/klt-sim/), filed as [klayout-tools#2511](https://github.com/2AMLogic/klayout-tools/issues/2511), tracked as #50. No phase-noise (row 4) claim is made (#49). Ratifies no `spec/target-spec.md` row. |
| [`bn-substrate-tank/`](bn-substrate-tank/) | what correcting the varactor `bn` pin from the tank node to the p-substrate (#79, DR-005) does to the passive tank's f0, Q and tuning ratio | Small-signal AC A/B, 108 rows on the batch fleet over MIM 3 x T 3 x (MOS tt x Vctrl 3 + ss/ff at band centre): **f0 -17 .. -23 %, tank Q -17 .. -28 %, tuning ratio 1.18 -> 1.11**. A lumped surrogate stands in for the OSDI MOS core, so the delta is native and the absolute f0 is not. With `bn` on the substrate the PDK's `dsubw` card is NaN above ~52 C -- the +125 C rows are errors. Phase noise **not measured** (OSDI blocked). Grades no row. |
| [`tank-screen/`](tank-screen/) | PDK-free analytic screen ranking (cells, MIM, inductor) tuples against rows 1-2 for the closed #93 re-tune (no defensible candidate; decision pending in DR-006, #184); known-answer checked against the `bn-substrate-tank` A/B record | **Screening arithmetic, not evidence** (lumped LC, no HBT loading, endpoints-only calibration). Writes no records; grades no row. |

## Record currency (`sim/record-currency.json`)

Records are append-only, so "is this record still about today's design?" is
computed **outside** them by `.github/scripts/record_currency.py` (Python
stdlib, PDK-free) and published as the derived, deterministic index
`sim/record-currency.json` (sorted, no timestamps, no HEAD-dependent fields
beyond the blob hash of the commit a record's own filename names). It
enumerates every `sim/**/records/` entry, groups flat companions
(`<id>.md`, `<id>-pilot.csv`, `<id>-curves/...`) and directory records by
record ID, and reports per record: path, `state`, `basis`, `reason`.

**States are narrow: currency against the bytes of `design/vco.spice`** -- not
simulation validity, grading completeness, or PDK/model currency.

| State | Meaning |
|---|---|
| `current` | an explicit, valid `design_netlist_sha256` (captured from the source the run actually consumed) equals the current `design/vco.spice` hash |
| `superseded` | the same, but unequal: the run consumed a different source than today's |
| `unknown` | anything else, always with a reason (below) |

`unknown` covers: filename-only provenance (the commit id in the name proves at
most the checkout the writer named -- not a clean tree nor the inputs consumed;
the index reports that commit's `design/vco.spice` blob hash as context only and
never upgrades it); unresolvable, ambiguous, shallow-history-missing or absent
commit ids; malformed or mutually conflicting explicit hashes; an explicit hash
that conflicts with (or whose declared snapshot is missing from) the captured
source snapshot -- filename inference is never used to hide bad explicit
provenance; and component/model characterization or synthetic comparison
records (`tank-characterization`, `inductor-model`, `varactor-characterization`,
`bn-substrate-tank`), which are not derived from `design/vco.spice` and so
are `unknown` ("not-applicable") unless they carry documented explicit source
provenance. A dirty run (explicit hash differs from the filename commit's blob)
is accepted when the consumed source is identified by the explicit hash; the
reason says so.

**Deck integrity is a separate diagnostic.** A klt report's `netlist_sha256`
hashes the *generated deck*, not `design/vco.spice`; it is compared only to the
deck paired by name (`reports/<n>.json` <-> `decks/<n>.spice`) and shown as
`deck_integrity`. A deck/source mismatch alone proves neither supersession nor
invalidity.

**Source currency vs report/deck integrity (issue #143).** These are two
independent verdicts. *Currency* asks whether the consumed `design/vco.spice`
bytes equal today's; it never changes with deck diagnostics. *Report/deck
integrity* asks whether a report's `netlist_sha256` equals the sha256 of its
paired deck. A record can be `current` and still fail integrity. A known
mismatch (a) makes `record_currency.py cite` / `validate_citations` reject
the record when it is cited as evidence, naming the report and its paired deck,
and (b) fails the standalone gate `check-all.sh deck-integrity`
(`record_currency.py integrity`). Regenerating `record-currency.json` does not
clear it: the verdict is recomputed from the record bytes. Reports with no
paired deck (legacy/unpaired) are listed as **unchecked** -- neither verified
nor a failure, and no provenance is invented for them. Frozen historical
evidence is never edited; a known historical mismatch can only be accepted by
an entry with a written justification in `INTEGRITY_ALLOWLIST`
(`.github/scripts/record_currency.py`). Disposition on the tree at introduction:
no mismatches and no unpaired reports, so the allowlist is empty.

**Paired-report contract (issue #173).** The pair is identified by name
*before* the report is parsed. A report whose `decks/<n>.spice` companion
exists must be valid JSON in which every `netlist_sha256` key carries the same
64-character lowercase-hex string. Otherwise it is a **malformed paired
report** (listed under `deck_integrity.malformed` as report path -> reason:
invalid JSON, missing digest, non-string digest such as a number or `null`,
wrong length or non-hex digest, or conflicting digests). A malformed paired
report fails the integrity gate and citation validation exactly like a
mismatch, independently of source currency, and is never silently skipped.
The same justified `INTEGRITY_ALLOWLIST` is the only way to accept a
historical one. Reports with no paired deck keep the legacy policy above:
unchecked, and not parsed for validity. Disposition at introduction: all 26
paired reports on the tree are well-formed, so the allowlist stays empty.

**Provenance schema** (`sg13g2-vco/source-provenance/1`): for new
`osc_derive_body()`-based runs (`run_pilot_grid.sh`, `run_pvt_sweep.sh`,
`run_supply_stage2.sh`, `phase-noise/run_isf_pilot.sh`), the bench copies
`design/vco.spice` once, derives from the copy, fails if the source changed
during derivation, and writes, for the reserved record ID,
`<experiment>/netlist-snapshots/<id>/design-vco.spice` (captured bytes) and
`<experiment>/records/<id>-source-provenance.json`:

```json
{"schema": "sg13g2-vco/source-provenance/1", "record_id": "<id>",
 "design_netlist_path": "design/vco.spice",
 "design_netlist_sha256": "<64 lowercase hex>",
 "source_snapshot": "sim/<experiment>/netlist-snapshots/<id>/design-vco.spice"}
```

The classifier also accepts a `design_netlist_sha256` key anywhere in a
record's JSON files; the helpers are `snapshot_source`,
`assert_source_unchanged` and `write_source_provenance` in `sim/lib.sh`.
Existing records are untouched and so remain `unknown`.

**Captured model inputs** (issue #133; schema `sg13g2-vco/model-inputs/1`).
The same capture idiom covers everything else those runs read by path. After
`osc_preflight` has resolved the PDK and built `mosvar.osdi`, and before the
first simulation, `osc_capture_model_bundle` (`oscillator-core/osc_bench.sh`)
copies into a private, read-only bundle in the run's scratch directory:

- the PDK model libraries the testbenches load (`cornerHBT.lib`,
  `cornerMOShv.lib`, `cornerCAP.lib`, plus `sg13g2_svaricaphv_mod.lib` and
  `sg13g2_hbt_mod.lib`) **and the transitive closure of their
  `.include`/`.lib` references**, every section included, parsed out of the
  captured bytes and laid out as in the PDK so relative references resolve
  to other copies;
- the non-PDK inductor model (`inductor-model/sg13g2_inductor_em.spice`) and
  anything it includes;
- the `mosvar.osdi` binary this run built;
- the experiment's `.spiceinit`, which also replaces the copy ngspice reads
  from the scratch directory.

Every deck is rendered against the bundle (`osc_render`); the PDK, inductor and
OSDI digests in the narrative (`osc_provenance_md`, the runners' inductor
line) come from the bundle's manifest, never from re-hashing live files; and
`osc_publish_summary` re-verifies every copy, the manifest, the served
`.spiceinit` and the retained files before the summary `.md` is written. Editing a
live library, model, OSDI binary or init file mid-run therefore reaches no later
point and no recorded digest. An edit to the bundle fails the run, and no summary
is written. A missing root or nested dependency, a reference that leaves the model
directory or is absolute (it could not be served from a copy without rewriting
bytes), an init file that loads anything (`source`/`osdi`/`codemodel`), or a
template that names an uncaptured library fails before any deck exists. The
generic helpers are `capture_input_closure`, `capture_input_file`,
`input_bundle_sha` and `verify_input_bundle` in `sim/lib.sh`; the PDK-free
fixture test is `sim/tests/test-model-bundle.sh` (run by
`check-all.sh currency-selftest`).

What a reserved record **retains** (all append-only):

| Retained | Where |
|---|---|
| machine-readable manifest: role, bundle path, sha256 of the copy, original location (context only) | `<experiment>/records/<id>-model-inputs.json` |
| repo-owned inputs as captured: inductor model, `.spiceinit` | `<experiment>/netlist-snapshots/<id>/model-inputs/{inductor,init}/` |

What remains **external** to committed evidence, identified by digest only
(`retained_snapshot: null` in the manifest): the PDK model libraries (pinned by
`sim/pdk.json`) and the built `mosvar.osdi` binary. Also outside the capture:
the ngspice executable and its system-wide `spinit` (identified by the
recorded `ngspice` version only), and `design/vco.spice`, which has its own
capture above. The manifest carries no `design_netlist_sha256`, so the
classifier ignores it. **Record currency still concerns `design/vco.spice`
only.** Records written before #133 are unchanged and carry no model manifest;
their model digests were computed from live files when the narrative was
written.

**Committed-tree integrity gate** (issue #139). Run-time verification above
happens only when a run publishes; `check-all.sh model-inputs`
(`.github/scripts/model_inputs_check.py`, stdlib python3, no PDK) independently
audits what is committed. For every `records/<id>-model-inputs.json` it checks
the schema, that `record_id` equals the id in the filename, 64-hex digests,
unique `(role, bundle_path)` identities, and that each non-null
`retained_snapshot` is a safe relative path (no absolute, `.`/`..`, backslash or
symlink) equal to `<experiment>/netlist-snapshots/<id>/model-inputs/<bundle_path>`,
exists, and hashes to the declared `sha256`. It also enforces the writer's role
policy (`osc_model_inputs_json` / `osc_retain_model_inputs` in
`sim/oscillator-core/osc_bench.sh`): the repo-owned roles `inductor-model` and
`simulator-init` must have a non-null `retained_snapshot`, the external roles
`pdk-model` (PDK libraries) and `osdi-binary` (`mosvar.osdi`) must have
`retained_snapshot: null` (digest only, never demanded), any other role is
rejected, and at least one entry of each of the four roles (`inductor-model`,
`simulator-init`, `pdk-model`, `osdi-binary`) must be present, counted only
from structurally valid entries -- so a manifest whose repo-owned inputs were
not committed, or that dropped the PDK/OSDI digest identities, cannot pass as
verified (the external bytes themselves stay unretained). Only the manifest and
the retained snapshot bytes are read -- never live models -- so editing today's
inductor model cannot invalidate a historical capture. Records with no
manifest (everything before #133) are listed as `legacy / not checked`, not
counted as verified. The gate is separate from record currency, which still
concerns `design/vco.spice` only. Fixture self-test:
`check-all.sh model-inputs-selftest`.

**Refresh** after any `design/vco.spice` change or new record:
`python3 .github/scripts/record_currency.py write`, commit the index. CI gates:
`check-all.sh currency` (index equals fresh classification; in a shallow clone
only the history-independent fields are compared) and `check-all.sh
currency-selftest`. `check-signoff.sh` rejects a manifest evidence entry whose
path lies under `sim/**/records/` unless that record is freshly `current` (and
the committed index is not stale), independently of the rendered-report
comparison; unknown, superseded, missing and unmappable citations fail.
`record_currency.py cite PATH...` runs the same check by hand.

## Measurement-method CI (PDK-free)

`.github/workflows/method-check.yml` runs the known-answer checks of the
estimators in `lib.sh` on every push to `main` and every pull request:
`oscillator-core/run_method_check.sh`, `phase-noise/run_method_check.sh`,
`inductor-model/run_model_check.sh` (self-contained, loads no PDK model) and
`oscillator-core/tests/test_emit_tuning.sh`, and (issue #113)
`oscillator-core/tests/test_supply_stage2.sh` -- the DR-004 stage-2 supply
sub-corner enumeration, rails in generated decks, nominal reproducibility,
rail identity and escalation-report fixtures (renders decks, runs no PDK
simulation). The same command runs locally:

    .github/scripts/run-method-checks.sh [artifact-dir]

- **Simulator**: ngspice 42 (CI installs the `ubuntu-24.04` apt package and
  asserts the version; local development host: ngspice-42), plus bash, awk and
  git. No `PDK_ROOT`, OSDI, xschem, KLayout or credentials; the runner scrubs
  those variables from the checks' environment.
- **Disposable copy**: only git-tracked files are copied to a temp directory
  and run there, so the committed append-only evidence is never modified and CI
  never commits anything. Fresh records, snapshots, corner logs and the
  per-script logs are uploaded as the `method-check-evidence` artifact
  (`if: always()`); they are method diagnostics, not device signoff evidence.
- **Pass criteria**: every script exits 0 *and* its newest `*-method-check.csv`
  has no non-PASS row and at least the pinned minimum PASS rows (56 / 42 / 324),
  so a script that measures nothing fails. Tolerances are the scripts' own
  derived ones; the runner adds none.
- **Measured runtime** (8-vCPU shared host, ngspice-42): oscillator-core ~1 s,
  phase-noise ~3-4 s, inductor-model ~5-8 s, tuning fixture <1 s; ~14 s total.
  The job timeout is 10 min, dominated by the apt install.
- **Falsification**: mutating `osc_metrics()`'s period divisor `(nx - 1)` to
  `nx` fails oscillator-core (16/56 rows), and dropping the factor 2 in
  `pn_l_dbc()` fails phase-noise (1/42 rows); both make the runner exit 1.

## PDK pin

Every record in this tree is generated against the PDK revision pinned in
[`pdk.json`](pdk.json) (IHP-Open-PDK tag `v0.3.0`, with its tarball sha256).
Each record additionally states the exact `PDK_ROOT`, the ngspice version, and
the **content sha256 of every model library the run loaded**, so a reader can
confirm their own install matches without re-deriving it from the pin file
alone.

`pdk.json` also carries a `known_model_gaps` block. A device the PDK does not
ship a simulatable model for is a first-class constraint on what this repo can
evidence, not a footnote.

## Model overlay policy (svaricap `dsubw`, issue #95)

Three things are kept distinct:

1. **The v0.3.0 defect.** The pinned PDK's `sg13g2_svaricaphv_mod.lib` and
   `sg13g2_svaricaphv_mod_mismatch.lib` give the `dsubw` card `vj = 0.1`, which
   is NaN in ngspice above ~52.5 C with `bn` on the substrate (IHP-Open-PDK
   issue #1098). Existing records describe those bytes and are never rewritten.
2. **The sanctioned overlay.** IHP-Open-PDK PR #1102 (merge commit
   `0243d867c6b7493526b141d2e4d74afa027e5b8e`) changed `vj = 0.1` to
   `vj = 0.3357` in both files. Until the pin moves, runs apply that exact
   substitution to their **private copy** of the model closure:
   `sim/tools/svaricap_overlay.py` (logic) via `apply_svaricap_vj_overlay` in
   `sim/lib.sh` (called by `osc_capture_model_bundle`, so oscillator and
   phase-noise benches get it; passive-tank decks inline the same card from the
   same module). It never writes `$PDK_ROOT`, refuses (fail-closed, before any
   simulation) unless each file has the v0.3.0 sha256 and the card text occurs
   exactly once, and **refuses a file that already carries the fix** instead of
   double-patching. Provenance: the bundle's `overlay/svaricap-vj.json`
   (original and overlaid digests, upstream issue/PR/merge commit) is in the
   manifest and `-model-inputs.json`, and the record summary prints the
   pre-overlay digests. `tnom = T` is not a production workaround.
3. **A future PDK-pin upgrade.** A pin that includes PR #1102 makes the overlay
   unnecessary: it will refuse ("already carries the upstream fix"), which is
   the signal to delete the overlay and its calls, not to bypass it. Do not
   repin just for this; a pin bump changes far more input surface.

No spec bound is relaxed by the overlay; row 11 stays -40 C to +125 C.

## Environment

`source env.sh` resolves `PDK_ROOT`/`PDK` — an explicit export wins, otherwise
the usual open_pdks install prefixes are probed. `run_pvt_sweep.sh` sources it
because it needs the PDK's model libraries; `run_model_check.sh` deliberately
does not, so it keeps its no-PDK-install cold start (see its own header and
`sim/lib.sh`'s header for why). An interactive `ngspice` session can source it
too, so nothing here can silently drift onto a different install than a
PDK-dependent script used.

## Directory / naming convention

```
sim/
  README.md                  this file — the authoritative convention
  pdk.json                   pinned PDK revision + known model gaps
  env.sh                     PDK_ROOT/PDK resolution, sourced by run scripts
                             that need the PDK (not all of them — see
                             "Environment" above)
  <experiment-slug>/         one directory per distinct claim under test
    README.md                what was measured, over what band and corners,
                             how to reproduce it, and what it does NOT show
    run_*.sh                 THE cold-start entry point: one command, no args
                             (e.g. run_pvt_sweep.sh, run_model_check.sh)
    .spiceinit               ngspice init copied into the run's scratch dir, so
                             a run never depends on $HOME/.spiceinit existing
    testbench/
      tb_<name>.spice.tmpl   the testbench template (@@PLACEHOLDER@@ form)
    netlist-snapshots/
      <record-id>/
        <corner-id>.spice    the exact generated netlist for that PVT point
        model-inputs/        captured repo-owned model inputs (osc_bench.sh
                             runs, issue #133; see "Captured model inputs")
    corners/
      <record-id>/
        <corner-id>.log      raw ngspice batch output for that PVT point
    records/
      <record-id>.md         narrative record: claim, method, corners, PDK
      <record-id>.csv        parsed scalar summary, one row per corner × device
      <record-id>-curves/    per-corner curve data vs. frequency, where the
                             curve rather than a scalar is the product
      <record-id>-model-inputs.json  captured model-input manifest
                             (osc_bench.sh runs, issue #133)
```

`<record-id>` is `<UTC yyyymmdd-HHMMSS>-<git short sha of the tree that ran>`.
`<corner-id>` names the PVT point (e.g. `mimcap_wcs_125c_1.5v`).

## Rules a record must satisfy

1. **One command, cold start.** `spec/review-bar.md` item 1: a single
   documented invocation regenerates the evidence from the committed netlist
   and the pinned PDK, with no hidden manual steps. If a run needs a build
   step, that step belongs *inside* the run script.
2. **Stated corners.** Every recorded result names the process/voltage/
   temperature points it was taken at, and states an explicit reason for any
   axis deliberately not swept.
3. **Frozen netlist.** A record freezes the exact netlist it simulated, so it
   stays readable after the template moves on.
4. **A failure is a result.** A model that does not exist, a point that does
   not converge, or a measurement that misses is recorded with its raw log —
   never dropped so the summary looks clean.
5. **Method before number.** A derived quantity states how it was derived. Where
   the derivation can be checked against closed-form algebra, it is (see
   `tank-characterization/`'s reference network); where it cannot — phase
   noise, per `CLAUDE.md` — the method, its variance and its limits are stated
   with the number or the number is not a result.
6. **A non-PDK model is labelled as one, everywhere it is used.** Where a
   device model does not come from the pinned PDK (e.g.
   `inductor-model/sg13g2_inductor_analytic.spice`, an analytic model standing
   in for a device v0.3.0 ships no model for), the record names that file by
   **repo-relative path and content sha256**, and the model's own stated
   accuracy limits propagate to every number derived from it. A reader must
   never have to guess whether a number came from the PDK or from a
   substitute.
