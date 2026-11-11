# Record 20261111-233500-54ea69e -- graded row-10/11 phase-noise grid: machinery and fleet smoke (issue #53, increment)

- **This record grades NO `spec/target-spec.md` row.** The 135-point grid was **not run** in this increment; no row bound was edited.
- **What was run**: one two-unit smoke on the batch fleet, `tt_typ_typ` / 27 C / Vctrl 1.65 V, widened spacing (`--nper 9`, carrier
  4.196708 GHz from the oscillator-core fleet grid): units `dqd=0` (reference) and `dqd=4e-15`. First submit `klt-sim-c332ab2ccd78`
  (`--submit-only`; could not be re-attached because `--attach` rejects the request hash), then `--resume` launched
  `klt-sim-1dfa416c0f4a`: 2/2 pass, 25.18 ns each in 5.73 s wall, `vdiff_max` 0.2959 V (matches the pilot's settled per-cycle peak).
  Evidence (corner decks/logs; waveforms not committed): `klt-sim/grid-smoke-nper9/`.
- **Method**: unchanged from the pilot record `20261105-200000-6834172` (ISF from impulse-train transients, reference-run crossing
  differences, `L = Gq_rms^2 S_i / (2 (2 pi df)^2)`), except impulse spacing `(9 + 1/10)` periods. The smoke produced no L(df).
  Variance, limits and the non-PDK inductor bars are those of the pilot record and apply to any later graded numbers.
- **Findings**: (1) `n_plateau >= 3` needs `nper >= 9` (0.35 plateau fraction), not 5-6; (2) fleet speed is ~400x the 11.19 ps/s
  local constant, so the 505 CPU-h the entry point prints at that constant overstates compute (~1.3 CPU-h) while waveform volume
  (~240 GB for 810 units) dominates; (3) all 125 C units failed in the oscillator-core fleet grid (`timestep_too_small`), so 45
  corners may never yield a valid L and row 4 would remain INCOMPLETE.
- **Not done**: per-corner reduction glue, the 135-corner submission, the 135-corner port-noise run, stage-2 supply points
  (`run_supply_stage2.sh` untouched), the graded row-4 record.
