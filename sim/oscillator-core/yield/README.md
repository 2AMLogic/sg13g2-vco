# Monte Carlo yield campaign plan for the oscillator core (T1 item 6) — planned, not run

- **Status**: **plan only. No sample has been simulated and nothing here is a
  result.** Issue #244. The run is a follow-up that depends on #94 (the OSDI
  varactor model cannot run locally or on the batch backend yet) and follows
  the corner grid in #50.
- **Classification this plan reads**: `spec/decision-records/DR-007-statistical-row-classification.md`.
  Statistical rows are **1, 2, 3, 4, 5, 6, 7, 9**; corner-bounded rows are 0,
  8, 10, 11. This plan covers rows 1, 2, 3, 5, 6, 7, 9. **Row 4 is a declared
  gap** (no per-sample phase-noise estimator exists).
- **No bound is edited.** A Monte Carlo result that contradicts a ratified bound
  is a superseding decision record, never an edit (DR-003's rule).

## Preconditions the run must check first

| # | Precondition | State on 2026-10-17 |
|---|---|---|
| P1 | Full-oscillator route that loads the OSDI varactor under `klt sim` | **Missing** (#94). The only blocking dependency of the run step. |
| P2 | A `klt` release whose `monte_carlo` seed contract keys a sample on `sample_index` alone, not on the point's position (klayout-tools#2899), and holds RNG-drawn mismatch fixed under `vary: "process"` (klayout-tools#2937) | **Not in the `0.6.0` pin.** Both issues are closed upstream, after `0.6.0` (2026-09-22). The `0.6.0` source derives the per-sample seed from `corner_index`, so the same `sample_index` is a different draw at each `Vctrl` point. That makes the paired-endpoint measurements below meaningless on `0.6.0`. Which release first carries the fix is **not verified here**; the run step must confirm it, not assume it. |
| P3 | A `klt` that can run `klt yield` | **Not reachable from a single-package install** (klayout-tools#2900, open). `klt yield --help` on `0.6.0` says the native extension needs a repo checkout and a Rust toolchain. |
| P4 | A signoff-grading release for the `spec_rows` field | Not in `0.6.0` (klayout-tools#2908, closed on `main`). See `signoff/README.md`. |
| P5 | Row 1/2 shortfall disposed (DR-006, proposed) | **Open.** The current netlist's band centre is below row 1's floor; sampling rows 1 and 2 around a design that misses them grades the miss, not the spread. The campaign runs on whatever netlist DR-006 leaves committed, and its records name that netlist's hash. |

Each is checked at run time and printed in the record. A run that cannot
satisfy P1 or P2 is not started on a workaround.

## What is in this directory

| File | What it is |
|---|---|
| `request-nominal-process.json` | Anchor 1, **global process** spread: `hbt_typ_stat`, `mos_tt_stat`, `cap_typ_stat`; N = 400, seed 244, `vary: "process"`; `Vctrl` in {0.0, 3.3} V, 27 C, 3.3 V. |
| `request-nominal-mismatch.json` | Anchor 1, **per-instance mismatch**: `*_mismatch` sections; N = 400, seed 244, `vary: "mismatch"`; same axes. |
| `request-negative-control-seed.json` | The seed negative control (below): plain typical sections, N = 8, expected sigma = 0. |

All three are `klt sim` requests and go to the batch fleet; none is a
hand-rolled `ngspice -b` loop. Each is validated for JSON only: `klt sim` has no
validate-only mode at `0.6.0` that does not simulate (checked with
`klt sim --help`), so they have **not** been dry-run.

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
| S2 mid-window points | 3 | + 1.65, 1.8, 2.4, 3.0 (row 3 needs >= 5 points in the window, endpoint 3.3 shared) | 1600 per instrument | 173 CPU-h each |
| S3 supply pairs | 9 | + 2 points at band-centre `Vctrl`, VDD at 2.97 / 3.63 V | 800 per instrument | 87 CPU-h each |
| S4 inductor sensitivity (deterministic) | 1, 2, 5 | 3 scalings of L, no sampling | few | negligible |
| Row 5 (tank Q) | 5 | one small-signal `ac` run of the loaded tank, not a transient | 400 | small; request not written yet |

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
   private copy of the netlist, chosen so that its **zero-spread** row-7 swing
   is at most 0.8 x the 0.40 V floor (<= 0.32 V). A starting candidate is the
   tail resistor `RTE` raised, which lowers `I_tail`; the value is **not
   chosen here**. The run step sets it by one deterministic nominal transient
   and records that transient *before* sampling. The same N, seed and axes
   are then run; `klt yield` must report this variant's yield as degraded
   against the real campaign. If it is not detected, the campaign cannot
   distinguish a failing design from a passing one, and the real result is
   not usable.

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

## What this plan does not do

- Run anything, or cite a `klt yield` report (follow-up after #94).
- Cover row 4: a per-sample phase-noise estimator does not exist, so row 4
  stays an uncovered statistical row in the signoff coverage statement.
- Bump the klt pin (P2 to P4 are checked against whichever release the run
  step pins).
