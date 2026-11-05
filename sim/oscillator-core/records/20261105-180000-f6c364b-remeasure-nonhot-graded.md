# Post-#79 re-measure of the 199 estimator-errored units on the fleet, then graded (issue #94, partial deliverable)

Append-only; the 20261105-152054 and 20261105-170000 records are untouched. Request and inputs:
`klt-sim/remeasure-nonhot-post79/` (`request-remeasure-nonhot-post79.json`, `vco_core_body.spice`,
`sg13g2_inductor_em.spice`; evidence under `evidence/`: the full `report.json`, five `batch-receipt-*.json`,
`submit.stderr`, and one retained `corner.cir` + `ngspice.log` for tt_typ_typ/3.3 V/27 C).
Per-unit table: `20261105-180000-f6c364b-remeasure-nonhot-units.csv` (1350 rows); graded:
`20261105-180000-f6c364b-remeasure-nonhot-graded.csv` (135 rows, by `grade_fleet_grid.py`, unchanged).

## What was run
- Same netlist as the grid record: `design/vco.spice` sha256 `090983d6...`; submitted file hash
  `9ce081a6af3d5f3a884e0157e8e25a562d2afa3826b8de7c8d380ee812a6f155` (= report `netlist_sha256`, identical to the grid run).
- Request: the 45 process corners x Vctrl {2.4, 3.0, 3.3} V x {-40, 27} C = **270 units** (a superset of the 199 errored
  units: it also re-runs 71 units that passed before, as a repeat check). The only changes from the grid request are
  `tran 1p 10n 0 2p` (was 5 ns) and the amplitude/average windows `FROM=5n TO=10n` (was 2.5-5 ns). The `t_10_periods`
  card is unchanged (rising crossings 11 -> 21 of v(vdiff)). 125 C was **not** resubmitted.
- Submitted with `klt sim --backend batch --max-units-per-job 55` (client klt 0.9.1.dev102, runner klt 0.9.0,
  `runner_compatibility: match`, ngspice-46, spot c7i.8xlarge / m6i.4xlarge). Nothing ran locally. No quota failure this time.
  Fleet jobs: `klt-sim-07e3b978c478`, `klt-sim-0a58bf87dfde`, `klt-sim-67ca552c1a6d`, `klt-sim-9ca4010d7a9d`,
  `klt-sim-a675b64af1fd` (also in `environment.remote.fleet` of the retained report). Wall clock ~90 s.
- OSDI: `options.osdi_preload` = `mosvar.osdi` (`pre_osdi /opt/pdk/...` is in the retained `corner.cir`); all 270 units
  loaded it and simulated. **The OSDI ABI version actually loaded is still not reported by the runner and was not measured.**
- The units CSV is built by `merge_remeasure.py` (new): the 270 re-measured rows replace the same keys in the grid CSV
  (f = 10 / t_10_periods; vdiff_pp = vdiff_max - vdiff_min); every other row, including all 450 125 C errors, is carried unchanged.

## Result
- **270/270 units pass; all 199 previously errored units now return a `t_10_periods`.** That supports the attribution
  in the grid record: the errors were the estimator (21 crossings did not fit in 5 ns at Vctrl >= 2.4 V), not a failure to oscillate.
  Waveforms were not retained, so this is inferred from the measurement returning, not from a viewed waveform.
- **Repeat check:** the 71 units that passed in the 5 ns grid reproduce `f_osc` exactly (max relative change 0), so the
  frequency estimator is independent of the window length where both succeed. Not a variance estimate: the run is
  deterministic (one `.ic`, no seeds), so this shows reproducibility only.
- Caveat on the merged curves: Vctrl <= 1.8 V points come from the 5 ns run (amplitude window 2.5-5 ns) and
  2.4/3.0/3.3 V from the 10 ns run (amplitude window 5-10 ns). Frequencies are directly comparable (above); `vdiff_pp`
  at the high-Vctrl end is from the later window.

## Grade (rows 1/2/3/7 from the 10-period estimator; the grader and bounds are unchanged)
| Temp | corners | f_min across corners | f_max across corners | f_max/f_min | row 3 coverage | row 3 mean Kvco (MHz/V) | row 3 chord INL % | W-window vdiff_pp min (V) |
|---|---|---|---|---|---|---|---|---|
| -40 C | 45 | 3.779-3.871 GHz | 4.236-4.310 GHz | 1.110-1.124 | 0.945-0.955 | 240.8-274.6 | 23.0-24.1 | 0.595-0.608 |
| 27 C | 45 | 3.751-3.842 GHz | 4.176-4.251 GHz | 1.103-1.117 | 0.955-0.965 | 227.0-258.9 | 22.2-23.3 | 0.519-0.536 |
| 125 C | 45 | not graded | | | | | | INCOMPLETE (all 10 units per corner are the recorded HBT first-timepoint abort, `timestep_too_small`) |

- **Row 1** (4.5-5.5 GHz): at all 90 graded curves an endpoint is outside; in fact the whole tuning curve sits below 4.5 GHz.
- **Row 2** (>= 1.15 full-domain ratio; stretch 1.20): NOT MET on all 90 (best 1.124).
- **Row 3** (single-signed, coverage >= 0.90, mean Kvco >= 381 MHz/V, chord INL <= 30 %): NOT MET on all 90. The curves are
  single-signed with coverage and INL inside bounds; **the failing term is mean Kvco** (227-275 MHz/V vs 381).
- **Row 7 swing** (vdiff_pp >= 0.40 V over W): MET on all 90. **Row 7 BVCEO compliance is NOT graded** (the fleet report
  has no cycle minimum of V(TAIL)).
- 125 C: 45 curves stay INCOMPLETE; recorded as errors with cause, not dropped. No spec row was relaxed.

## Limits
- The frequency is a coarse 10-period estimator from a 5-10 ns transient started from one `.ic`; no seed or variance estimate;
  it carries a ~0.1 % quantization floor. The row 1/2/3 shortfalls (4-17 %, 17-40 % for Kvco) are far larger than that floor,
  but a startup-transient bias in the 11th-21st crossings was not bounded here (a longer run or the ISF pilot would test it).
- Spec target rows are graded at -40 C and 27 C only; 125 C remains blocked by the HBT first-timepoint abort (#280/#281).
- This is a measured, unfavorable result for rows 1-3 against the ratified spec; it is reported as-is. Row 6/8 are not in the request.
- `design/run_elaborate.sh`, the `sim/phase-noise` ISF pilot and the pre-#79 banners are **not** addressed here (issue #94 stays open);
  every banner stays because no banner-covered number is replaced by a record that also covers 125 C and rows 6/8.
