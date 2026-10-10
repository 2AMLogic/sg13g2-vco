# svaricap `vj` overlay smoke test (issue #95)

New evidence; the older records are untouched and still describe the unpatched
v0.3.0 `dsubw` card (`vj = 0.1`), whose 125 C rows are error rows.

- Circuit: the issue #79 passive tank, `bn` on the substrate (`bn-sub`), tt MOS
  cell values, Vctrl 1.5 V, MIM cap_typ, small-signal AC 1-12 GHz.
- Model: the `dsubw` card with exactly one change, `vj = 0.1 -> vj = 0.3357`
  (IHP-Open-PDK issue #1098, PR #1102, merge commit
  `0243d867c6b7493526b141d2e4d74afa027e5b8e`), from `sim/tools/svaricap_overlay.py`
  at the commit this record is named for. See the header of `decks/*.spice`.
- Method: one `klt sim` request (klayout-tools 0.6.0 via uvx), 3 temperature
  points (50, 55, 125 C), submitted to the batch fleet (`KLT_SIM_BACKEND=batch`),
  job `klt-sim-86dc7fefa58f` (aws-batch-fleet, spot c7i.4xlarge, ngspice per
  `report.json` `environment`). Nothing was run locally.

| T (C) | status | f0 (GHz) | zpk (ohm) |
|---|---|---|---|
| 50 | pass | 4.26205 | 2191.58 |
| 55 | pass | 4.26155 | 2176.83 |
| 125 | pass | 4.30870 | 2064.62 |

All finite, including 55 and 125 C where v0.3.0 gave NaN. Limits: one tank
point (not the full A/B grid); the OSDI MOS core is the lumped R-C stand-in
documented in `make_requests.py`; the full-oscillator and phase-noise runs
(#94) are not regenerated here.
