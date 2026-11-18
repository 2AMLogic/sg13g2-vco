# Monte Carlo yield campaign for the oscillator core (T1 item 6) — anchor 1 and AC 4c stages run

- **Status (2026-11-18, AC 4c complete + the seed-245 extension)**: **the AC
  4c stages have RUN** — S2 mid-window points (both instruments, N = 400,
  1600/1600 units each), the row-6 decision-rung pick (deterministic probes +
  the rung decision: **RREF 71k**), the per-sample startup-ladder campaign
  and its known-bad control at that rung, stage S4 (the deterministic
  inductor sensitivity, gap G1's only bound), and the **seed-245 extension**
  (N = 4200) that re-sizes the first mismatch ladder draw's
  `sample_size.verdict = insufficient` to `sufficient` — the plan's rule:
  extend with a NEW seed, never argue around. Result, method, versions:
  `../records/20261118-050000-0fa456b-yield-ac4c-stages.md`.
  Row 3 is now covered by eight envelopes (its Kvco-mean floor fails on the
  merits — the DR-006 shortfall, sampled, not created, by this campaign; the
  other three DR-004 requirements pass). Row 6 is covered: process passes
  400/400 with its control detected; mismatch grades a conservative
  lower-bound yield of 0.9186 — a miss on its merits (the DR-006 lane
  again). **Rows 5 and 9 are NOT measured here**: #362 (row 5, graded tank-Q
  bench) and #363 (row 9, supply-pushing bench) own those measurements; this
  campaign consumes whatever they define (issue #244 AC 4d), and
  `spec_rows."6"` declares them gaps naming the owners.
  Earlier: anchor 1 (S0 + S1 + controls) ran 2026-11-15 —
  `../records/20261115-190000-0b056b1-yield-anchor1-run.md`: rows 1/2 grade as
  misses (yield 0.0, the DR-006 shortfall), row 7 400/400 with its control
  detected, `sample_size.verdict = sufficient` everywhere.
  The corner-grid pairing (plan §"Pairing with the row-10 corners") still
  waits on #50.
- **Classification this plan reads**: `spec/decision-records/DR-007-statistical-row-classification.md`.
  Statistical rows are **1, 2, 3, 4, 5, 6, 7, 9**; corner-bounded rows are 0,
  8, 10, 11. This plan covers rows 1, 2, 3, 5, 6, 7, 9. **Row 4 is a declared
  gap** (no per-sample phase-noise estimator exists).
- **No bound is edited.** A Monte Carlo result that contradicts a ratified bound
  is a superseding decision record, never an edit (DR-003's rule).

## Preconditions the run must check first

| # | Precondition | State on 2026-10-17 | State at the run (2026-11-15) |
|---|---|---|---|
| P1 | Full-oscillator route that loads the OSDI varactor under `klt sim` | **Missing** (#94). The only blocking dependency of the run step. | **Cleared** (#290/#291 route). |
| P2 | A `klt` release whose `monte_carlo` seed contract keys a sample on `sample_index` alone, not on the point's position (klayout-tools#2899), and holds RNG-drawn mismatch fixed under `vary: "process"` (klayout-tools#2937) | **Not in the `0.6.0` pin.** Both issues are closed upstream, after `0.6.0` (2026-09-22). The `0.6.0` source derives the per-sample seed from `corner_index`, so the same `sample_index` is a different draw at each `Vctrl` point. That makes the paired-endpoint measurements below meaningless on `0.6.0`. Which release first carries the fix is **not verified here**; the run step must confirm it, not assume it. | **Cleared at 0.8.0, with a requirement.** The 0.8.0 source derives two independent seed components and varies only the requested axis (read from the installed package). But #2899's fix is behind `monte_carlo.seed_scope`, whose **default `per_corner` is bit-identical to the pre-fix behaviour** — the run-step requests must set `"seed_scope": "shared"`, and do. The S0 seed control proves the contract (sigma = 0 with no RNG consumer). |
| P3 | A `klt` that can run `klt yield` | **Cleared at the registry (correction, 2026-11-15).** The 2026-10-17 state was "not reachable from a single-package install" (klayout-tools#2900, then open). #2900 closed `completed` 2026-10-29 and `klt-yield-native` 0.1.0 reached PyPI on 2026-11-05 with a `manylinux_2_28_x86_64` wheel; `uvx --from 'klayout-tools[yield]==0.8.0' klt yield --help` resolves and runs on a dispatch host (measured 2026-11-14, ROADMAP.md). The run step still verifies `klt yield` at execution time before relying on it — closed upstream is not the same as usable at the pin (see #4309 in the friction ledger). | **Cleared at execution time.** All six envelopes were produced with `klayout-tools[yield]==0.8.0` via `uvx`. |
| P4 | A signoff-grading release for the `spec_rows` field | Not in `0.6.0` (klayout-tools#2908, closed on `main`). See `signoff/README.md`. | **Cleared** (pin 0.8.0 grades the field). Item 6 now cites the six run envelopes. |
| P5 | Row 1/2 shortfall disposed (DR-006, proposed) | **Open.** The current netlist's band centre is below row 1's floor; sampling rows 1 and 2 around a design that misses them grades the miss, not the spread. The campaign runs on whatever netlist DR-006 leaves committed, and its records name that netlist's hash. | **Still open, and visible in the result** (as P5 predicted): rows 1/2 yield 0.0 around a 4.00 GHz centre. The spread around the miss is now measured (σ_f0 ≈ 8.5 MHz process / 3.6 MHz mismatch) for DR-006's margin arithmetic. |

Each is checked at run time and printed in the record. A run that cannot
satisfy P1 or P2 is not started on a workaround.

## Engine deviation the run had to document (ngspice-47)

The runner image moved to **ngspice-47** (~2026-11-13) after the elaborate
route was validated on ngspice-46. ngspice-47 and 47p1 abort this deck at the
first transient timepoint — VBIC's self-heating path hands the temperature
limiter a NaN; ngspice-46 passes the byte-identical deck. Not the #50 dsubw
card (finite at TNOM on both engines, measured). The run uses a body with
`selft=0` on XQ1–XQ4, with the root cause, the reproducing logs and the
measured bound (frequency unchanged below print precision; swing −0.42 % at
the 27 C anchor) in the run record and
`evidence-s0-ngspice47-regression/`. **No hot-corner number may come from
that body.** The runner-side pinning gap is filed as klayout-tools#5853
(ledger: `.github/klt-friction-ledger.json`); the campaign requests carry
`engine_version: "47"` as the fail-closed post-run pin.

## What is in this directory

| File | What it is |
|---|---|
| `vco_core_body.spice` | The campaign circuit body, byte-identical to `../klt-sim/elaborate-post79/vco_core_body.spice` (sha256 `9ce081a6…f6155`, the post-#79 validated body). Kept unmodified as the derivation base. |
| `vco_core_body_selft0.spice` | The body the anchor-1 run used: the above plus `selft=0` on XQ1–XQ4 (the documented ngspice-47 self-heating deviation; see the header and the run record). |
| `vco_core_body_known_bad.spice` | The known-bad control body: `selft0` body plus RTE 2k → 4.4k (tail starved; sized by the deterministic probe). |
| `vco_core_body_selft0_rref{2,3,4,6,8,12,69,71,73}.spice` | The row-6 ladder bodies: `selft0` body with RREF scaled by the named factor (`rref69/71/73` in kΩ are the refinement rungs; each derived by exactly one edit, header states it). `rref71` is the **decision rung** the ladder campaign ran at. |
| `vco_core_body_known_bad_rref71k.spice` | The known-bad control body at the decision rung: `known_bad` plus RREF 20.5k → 71k. Deterministic-probe-verified to fail the rung. |
| `sg13g2_inductor_em.spice` | The EM-fitted inductor model copy the body includes (same as the klt-sim attempt dirs carry). |
| `sg13g2_inductor_em_l{0936,1054,1064,1077}.spice` | Stage S4 copies: the EM-fitted model with its total series L scaled by 0.936 / 1.054 / 1.064 / 1.077 (the analytic model's measured error class, issue #9). Generated, one-edit derivations; headers state the edit. |
| `request-nominal-process.json` | Anchor 1, **global process** spread: `hbt_typ_stat`, `mos_tt_stat`, `cap_typ_stat`; N = 400, seed 244, `vary: "process"`, `seed_scope: "shared"`; `Vctrl` in {0.0, 3.3} V, 27 C, 3.3 V. As submitted. |
| `request-nominal-mismatch.json` | Anchor 1, **per-instance mismatch**: `*_mismatch` sections; N = 400, seed 244, `vary: "mismatch"`, `seed_scope: "shared"`; same axes. As submitted. |
| `request-negative-control-seed.json` | The seed negative control (below): plain typical sections, N = 8, expected sigma = 0. As submitted. |
| `request-negative-control-known-bad-process.json` / `-mismatch.json` | The known-bad control at campaign N, seed and axes, per instrument. As submitted. |
| `request-knownbad-probe.json`, `request-regression-probe.json`, `request-selft0-probe.json` | The one-shot deterministic probes (RTE sizing; plain-body fleet abort capture; self-heating-off local pass control). Not campaign requests. |
| `request-pair-probe-{process,mismatch}.json` | The seed-contract probes run before the S2 submission: 8 units at Vctrl 0.0 against the S1 reports, proving sample k is the same die across requests (P2). |
| `request-s2-midwindow-{process,mismatch}.json` | **AC 4c, stage S2** (row 3): N = 400, seed 244, `seed_scope: "shared"`, the four mid-window points 1.65/1.8/2.4/3.0 V (the S1 endpoints complete the five in-window chord points + f(0.0)). As submitted. |
| `request-ladder-probe-rref{1,2,3,4,6,8,12}.json` | The deterministic RREF ladder map (one unit each, plain typical): thresholds the rung bracket. |
| `request-rung-pick-rref{69,71,73}.json`, `request-rung-pick-knownbad71k.json` | The rung refinement probes and the known-bad viability probe at the picked rung. **Decision: 71k** — the strongest starvation whose measured nominal margin-equivalent (3.062) still clears the 3.0 floor; 69k (2.980) would grade the campaign yield ≈ 0 by estimator construction. |
| `request-r6-ladder-rref71-{process,mismatch}.json` | **AC 4c, row 6**: the per-sample startup-ladder campaign at the decision rung, N = 400 per instrument, seed 244, Vctrl 1.65 V (the pilot ladder's convention). As submitted. |
| `request-r6-ladder-control-rref71-{process,mismatch}.json` | The row-6 known-bad control at the SAME rung, N = 100 per instrument. Expected: fails the rung → margin floor 1.0 → yield 0.0 → detected. As submitted. |
| `request-s4-inductor-l{0936,1054,1064,1077}.json` | **AC 4c, stage S4** (deterministic, gap G1's only bound): plain typical sections, both tuning endpoints, no sampling. As submitted. |
| `assemble_yield_samples.py` | The committed assembler: pairs samples by `mc<index>` across the endpoints, derives f0 / ratio / swing, writes the six sample-set documents. `ac4c` mode derives the row-3 quantities (pairing S1 endpoints with the S2 mid-window points by the seed contract) and the row-6 per-sample ladder margin (I_tail measured from `vte_avg`/RTE, never inferred), and writes the ten AC 4c sample-set documents. `ac4c-ext` mode writes the seed-245 extension sample set (the extension's I_nom comes from its nominal-body companion request). |
| `yield-limits.json` | Run defaults (confidence 0.95, half-width 0.01, target yield 0.99) and the quoted per-row limits. |
| `yield-samples-*.json` (6 + 10 + 1) | The `klt yield` sample-set documents (measurement × instrument): six anchor-1 (rows 1/2/7), ten AC 4c (row 3's four requirements × 2 instruments, row 6's ladder margin × 2), and the seed-245 extension `yield-samples-mismatch-startup_margin_lower-ext245.json`. The seed-244 mismatch ladder sample set stays committed as the extension's provenance (its own envelope is deliberately not committed — see the run record). |
| `yield-envelope-*.json` (16) | The `klt yield` grading envelopes (produced at the 0.8.0 pin) — what `signoff/manifest.json` item 6 cites. Every committed envelope grades `sample_size.verdict` != `insufficient`; the first mismatch ladder draw's envelope (seed 244, `insufficient`) is intentionally not committed — it regenerates exactly from its committed sample set, and the seed-245 extension envelope is the row-6 mismatch citation. |
| `request-r6-ladder-ext245-mismatch.json` / `-nommis-mismatch.json` | **AC 4e extension** (row 6, mismatch): the decision-rung request and its nominal-body companion at seed 245, N = 4200 — sized from the first draw's committed CI alone so the verdict stays `sufficient` across it. As submitted. |
| `evidence-s0/` | Seed-control report + retained per-unit decks/logs (16/16 pass, sigma = 0). |
| `evidence-s1-process/`, `evidence-s1-mismatch/` | The two instruments' full reports (per-sample measurements, seeds, digests) and batch receipts. |
| `evidence-s2-process/`, `evidence-s2-mismatch/` | **AC 4c, stage S2**: the mid-window reports (1600/1600 units each; every die oscillates at every point). |
| `evidence-r6-ladder-process/`, `evidence-r6-ladder-mismatch/`, `evidence-r6-ladder-control-process/`, `evidence-r6-ladder-control-mismatch/` | **AC 4c, row 6**: the decision-rung campaign and its known-bad control, per instrument. |
| `evidence-r6-ladder-ext245/` (`set-manifest.json`), `evidence-r6-ladder-ext245-mismatch/`, `evidence-r6-ladder-ext245-nommis-mismatch/` | **AC 4e, row 6 extension**: the seed-245 ladder and nominal-companion reports (4200 + 4200 units) and their receipts; the set manifest records both job ids (the companion's first collector was lost to a builder-step timeout; re-collected with `--attach`, never re-run). |
| `evidence-ac4c-probes/` | The deterministic probes that sized and verified the AC 4c stages before any sampling: the RREF ladder map, the seed-contract pair probes, and the four S4 inductor scalings (13/13 pass). |
| `evidence-ac4c-rung-pick/` | The rung refinement probes (69/71/73k), the known-bad viability probe at 71k, and the rung decision (71k) with its reasoning. |
| `evidence-knownbad-probe/`, `evidence-knownbad-process/`, `evidence-knownbad-mismatch/` | The control probe and control runs' reports and receipts. |
| `evidence-s0-ngspice47-regression/` | The ngspice-47 regression evidence: a one-unit fleet probe on the plain body (aborts), local 46/47/47p1 reproductions, the self-heating-off pass control, and the TNOM diode probe showing dsubw is not the cause. |

The requests go to the batch fleet; none is a hand-rolled `ngspice -b` loop.
They are validated with `klt sim --dry-run` (which exists at the versions
after 0.6.0) and were dry-run before every submission.

## Model availability: what the pinned PDK offers, and the gaps

Checked 2026-10-17 against the PDK install; the install's
`sg13g2_svaricaphv_mod_mismatch.lib` has sha256 `16da7669…cf51`, which equals
the `v0.3.0` value in `sim/pdk.json`, and `capacitors_mod.lib` /
`cornerCAP.lib` match the digests that file records. The other libraries below
were **not** hashed against the tarball, only found in the install, so treat
"matches v0.3.0" as established for those three files and assumed for the rest.
The run record must hash every library it loads (the existing model-bundle
capture does this).

Devices instantiated by `design/vco.spice` and what statistical model each has:

| Device in the netlist | Global-process (`*_stat`) | Per-instance mismatch | Verdict |
|---|---|---|---|
| `npn13G2v` x4 (`XQ1`..`XQ4`) | `sg13g2_hbt_stat.lib` (`hbt_typ_stat`): one-sigma spreads on `cje`, `cjc`, `cjcp`, `is`, `ibei`, `re`, `rcx`, `rbx` (VBIC); `tf` is commented out upstream | `sg13g2_hbt_mod_mismatch.lib`: `qarea = agauss(1, 0.1, mm_ok)` per instance | Both found. |
| `sg13_hv_svaricap` x32 | `mos_tt_stat` includes `svaricap` `vfbo` (0.04), `toxo` (0.0133), `dlq` (0.10), `dwq` (0.10) | `sg13g2_svaricaphv_mod_mismatch.lib`: `w`, `l` `agauss` (`dw_mm`, `dl_mm` = 3 nm) | Both found. **Needs the `dsubw` `vj` overlay** (`sim/README.md`, 'Model overlay policy') in the private copy of *both* libraries, or the sample is NaN above ~52.5 C. |
| `cap_cmim` x1 | `capacitors_stat.lib`: `cap_carea` (0.033), `cap_cpara` (0.067) | `capacitors_mod_mismatch.lib`: `cap_carea_mm = agauss(1, 0.01)` | Both found. |
| `inductor` (`XL1`) | **none** | **none** | **Gap G1.** Not a PDK model at all (`pdk.json` `known_model_gaps`): the analytic or EM-fitted stand-in has a stated accuracy, not a distribution. |
| `RREF`, `RRE`, `RTE` (bias network) | **none as written** | **none as written** | **Gap G2.** The netlist uses ideal `R` cards, which carry no spread. The PDK has `resistors_stat.lib` (`rsh_rsil` 0.0467, `rsh_rppd` 0.033, `rsh_rhigh` 0.0833, `res_area` 0.033) and per-instance mismatch for `rsil`/`rppd`/`rhigh`, but using them means changing `design/vco.spice`, which is a design decision outside this plan. |
| MOS (`sg13_hv_nmos/pmos`) | `mos_tt_stat` | `sg13g2_moshv_mod_mismatch.lib` | Not used by this netlist. Listed so the absence is deliberate. |

Further gaps in the *combination* of sources:

- **G3, no joint process + mismatch section.** The PDK ships `hbt_typ_stat`
  and `hbt_typ_mismatch` as separate `.lib` sections that each pull a
  different copy of the same subcircuit, so they cannot be loaded together.
  A combined run needs a hand-built overlay under the model-overlay policy,
  with its own provenance. Until it exists, the two requests above are two
  instruments, and **their variances are not added here**: summing them
  assumes independence that no record tests.
- **G4, no statistical corner sections.** `hbt_bcs`, `hbt_wcs`, `mos_ss`, ... have no
  `_stat` counterpart. The `_stat` sections are centred on typical, and the
  corner values correspond to about 3 sigma of the same distributions
  (for example `hbt_bcs` `cje` 0.83 against a 0.058 sigma). So a Monte Carlo
  sample cannot be run *around* a process corner. The campaign pairs with row
  10 only on the temperature and supply axes (below), and **no claim is made
  about corner-plus-spread worst case**.
- **G5, resistor and inductor spread are unsampled**, so the row-6 and row-7
  results from this campaign understate the true spread by those terms. Row 7
  in particular names the tail mirror: its transistor ratio is sampled
  (`XQ3`, `XQ4`), its resistors are not (G2). The run record must say so next
  to every row-6/7 number. A deterministic sensitivity (not statistical) at
  the inductor model's own measured error, +5.4 / +6.4 / +7.7 % on L
  (`pdk.json`), is the cheap way to bound G1; it is listed as stage S4.

## Seed

Fixed at **244** before any run, never changed after seeing a sample. Both
sampling requests share it, so a re-run reproduces the draws exactly (P2 makes
that true across `Vctrl` points). Any later re-draw uses a new seed and is a
new record, not a replacement.

## Sample size

Target: show **yield >= 0.99** for each covered row, at 95 % two-sided
confidence, with a CI half-width no wider than `klt yield`'s default of
0.01 (the argument stated here, for a reviewer to attack).

- With zero failures in N samples, the exact (Clopper-Pearson) two-sided 95 %
  lower bound on yield is `(0.025)^(1/N)`. At **N = 400** this is
  `exp(ln(0.025)/400) = 0.9908`, above 0.99. N = 299 would do for a one-sided
  bound; 400 keeps the two-sided one.
- If the observed yield is 0.99, the Wald half-width is
  `1.96 * sqrt(0.99 * 0.01 / 400) = 0.0097`, within 0.01.
- N = 400 cannot certify yields above 0.9908, and a **single failure** in 400
  drops the exact lower bound to 0.9862, below 0.99. So the 0.99 claim holds
  only for a zero-failure row; a row with any failure is reported with its
  actual interval, and showing 0.99 for it needs a larger N and a new seed.
- `klt yield` grades its own `sample_size.verdict`; if it reports
  `insufficient` the campaign is extended with a new seed, not argued
  around.

## Stages and cost

Cost basis: the pilot measured about 6.5 CPU-minutes per 5 ns transient on
this netlist (`sim/oscillator-core/klt-sim/README.md`), so one sampling
request at 400 samples and 2 endpoints is 800 transients, about **87 CPU-hours**.

| Stage | Rows | Per sample | Transients (N=400) | About |
|---|---|---|---|---|
| S0 negative control (seed) | none (harness check) | 2 | 16 (N = 8) | 1.7 CPU-h |
| S1 anchor 1, process, endpoints | 1, 2, 6, 7 | `Vctrl` 0.0, 3.3 | 800 | 87 CPU-h |
| S1 anchor 1, mismatch, endpoints | 1, 2, 6, 7 | 0.0, 3.3 | 800 | 87 CPU-h |
| S2 mid-window points | 3 | + 1.65, 1.8, 2.4, 3.0 (row 3 needs >= 5 points in the window, endpoint 3.3 shared) | 1600 per instrument | 173 CPU-h each — **RUN 2026-11-17** |
| S3 supply pairs | 9 | ~~+ 2 points at band-centre `Vctrl`, VDD at 2.97 / 3.63 V~~ | ~~800 per instrument~~ | **NOT run here**: row 9's measurement is **#363's** (the supply-pushing bench, open/`loom:blocked`). This issue consumes whatever that bench defines (issue #244 AC 4d); no second row-9 bench is defined in this directory. |
| Row-6 decision-rung ladder | 6 | 1 point at Vctrl 1.65 at RREF 71k | 400 per instrument (+ 100-unit control) | ~44 CPU-h each — **RUN 2026-11-17** |
| Row-6 mismatch extension | 6 | same, seed 245 (new seed, never a re-tune of the first draw) | 4200 mismatch + 4200 companion nominal-body units | ~450 CPU-h — **RUN 2026-11-17/18**, collected 2026-11-18 |
| S4 inductor sensitivity (deterministic) | 1, 2, 5 | 4 scalings of L (0.936 / 1.054 / 1.064 / 1.077 — the analytic model's measured error class, issue #9), no sampling | few | negligible — **RUN 2026-11-17** (evidence-ac4c-probes) |
| Row 5 (tank Q) | 5 | ~~one small-signal `ac` run of the loaded tank~~ | ~~400~~ | **NOT run here**: row 5's graded measurement is **#362's** (the tank-Q bench, open/`loom:blocked`). This issue consumes whatever that bench defines (issue #244 AC 4d); the 2026-10-17 plan predates #361/#362/#363 and its in-directory row-5 bench request is deliberately not written. |

Total if every stage runs for both instruments is about 700 CPU-hours at
anchor 1 alone (2 x 87 + 2 x 173 + 2 x 87), a fleet job. This is why the plan stages: S0 and S1 first, and
S2/S3 only if S1 shows a row near its bound. The 8-core shared dispatch host
runs none of it.

## Pairing with the row-10 corners

Row 10's set is non-statistical and unchanged. The pairing is:

1. **Anchor 1** (this directory): typical process centre, 27 C, 3.3 V.
2. **Temperature and supply anchors**: once #50's graded grid exists, the
   (temperature, supply) combination that leaves each covered row the least
   margin gets its own sampling request, at typical process (G4 forbids a
   process-corner centre). These requests are **not written now**: naming a
   worst corner before the grid exists would be invention. Row 0's +/-10 %
   rail gives candidates at 2.97 / 3.63 V and row 11 gives -40 / +125 C.
3. The corner grid remains the grading instrument for the bound corners.
   The Monte Carlo result says how much spread sits around the typical centre;
   it does not replace a corner's pass/fail.

## Negative controls

`klt yield` defines a negative control as a **seeded, known-bad variant**
whose own yield must visibly degrade, and records the verdict beside the
campaign. Two controls are planned, because they test different things:

1. **Seed control (S0, deterministic; harness check).**
   `request-negative-control-seed.json`: the same seed and axes but the plain
   typical sections, so no `gauss()` or `agauss()` is active. N = 8. Expected
   result: every sample's measurements are identical. A nonzero spread means
   the sampler or the harness injects variation nobody asked for, and the
   campaign does not proceed.
2. **Known-bad variant (for `klt yield`'s `negative_control`).** One edit to a
   private copy of the netlist, chosen so that its zero-spread measurement
   degrades against the real campaign. **Resolved**: the tail-starved body
   (`RTE` 2k → 4.4k) was probe-sized and run at anchor 1 (row 7); the row-6
   stage adds the SAME body at the decision rung
   (`vco_core_body_known_bad_rref71k.spice`), deterministic-probe-verified to
   fail the rung (`request-rung-pick-knownbad71k`: late-window pk-pk
   6.3e-4 V << 0.1 V) before the ladder campaign was submitted. If a control
   run is not detected, the campaign cannot distinguish a failing design from
   a passing one, and the real result is not usable.

## Analysis

1. Per sample, assemble the derived quantities from the paired `Vctrl` points
   that share a draw: `f = 10 / t_10_periods` at each point; row 1 band centre
   (geometric mean of the endpoint frequencies, matching the pilot's
   convention); row 2 ratio `f_max / f_min`; row 7 `vdiff_max - vdiff_min`; row
   6 from the pilot bench's startup-margin measurement (its 9-rung ladder;
   how it becomes a per-sample ratio is settled in the run step); `isup_avg`
   as the row-8 cross-check, graded against nothing.
2. Write a `klt yield` sample-set document (`{"measurements": [{name,
   samples, limits, negative_control}]}`) with each limit copied from
   `spec/target-spec.md` (row 1 4.5 to 5.5 GHz, row 2 ratio >= 1.15, row 7 >=
   0.40 V, row 6 >= 3.0, row 3 as stated there). Limits are quoted, never
   adjusted.
3. Run `klt yield` and commit its JSON with the raw reports. The signoff
   citation uses that JSON.
4. The estimator for any per-sample frequency is the pilot bench's, whose
   known-answer check is in `sim/oscillator-core/run_method_check.sh`. The
   request's `.meas` period count is coarser, as `klt-sim/README.md` already
   says; use the one that was validated.

The pairing evidence is two distinct claims. The P2 pair probes prove only the
**same-body** claim: sample k is the same die across requests sharing a seed,
every body being the campaign body. The row-6 ladder estimator additionally
pairs **across netlists** — its `I_nom` is measured on the nominal body while
its `I_rung` comes from the decision-rung body
(`vco_core_body_selft0_rref71.spice`) — which no request-level probe covers.
The committed reports support that second claim directly: per-die `vte_avg` at
the 1.65 V point correlates across the two bodies at the same `mc<index>` at
0.9946 (process), 0.9983 (mismatch) and 0.9980 (seed-245 nominal companion vs
extension ladder), while the same series shifted one index (index+1) — the
null — gives 0.065 / -0.103 / -0.006. Re-derived on 2026-11-18 by joining each
pair on `mc<index>` and computing Pearson over per-die `vte_avg` from
`evidence-s2-{process,mismatch}/report.json` (1.65 V point),
`evidence-r6-ladder-{process,mismatch}/report.json` and
`evidence-r6-ladder-ext245-{,nommis-}mismatch/report.json`; the AC 4c run
record describes the same pairing design.

## What this plan (still) does not do

- ~~Run anything, or cite a `klt yield` report~~ — **done for anchor 1 on
  2026-11-15** (`../records/20261115-190000-0b056b1-yield-anchor1-run.md`;
  the six envelopes are cited by `signoff/manifest.json` item 6) and for the
  **AC 4c stages on 2026-11-17/18** (S2, the row-6 decision-rung ladder and
  control, S4, and the seed-245 mismatch extension; run record
  `../records/20261118-050000-0fa456b-yield-ac4c-stages.md`; all 16 committed
  envelopes are cited by `signoff/manifest.json` item 6, which now declares
  rows 5/9 as gaps naming #362/#363).
- Cover row 4: a per-sample phase-noise estimator does not exist, so row 4
  stays a declared gap in the signoff coverage statement.
- ~~Cover rows 5 and 9 here~~ — **reassigned 2026-11-17 (issue #244 AC 4d,
  absorbing #361's finding)**: #362 owns the row-5 graded tank-Q bench and
  #363 the row-9 supply-pushing bench (both filed 2026-11-15 out of PR #357's
  coverage note; both open, `loom:blocked`). This directory defines no
  competing row-5/row-9 bench and runs no S3 supply pairs; it consumes
  whatever those benches define. Until they land, rows 5 and 9 stay uncovered
  or are declared gaps naming them — either is honest; a second measurement
  here would not be.
- Bump the klt pin (P2 to P4 are checked against whichever release the run
  step pins).
- The corner-pairing anchors wait on #50 (open, `loom:operator`); no worst
  corner is named before that grid exists.
