# Record 20261010-060510-edf5eb5-surrogate-corrected

**SCREENING ONLY — grades no specification row**

- **Experiment**: oscillator-core, OSDI-free varactor surrogate (issue #179), point `corrected`
- **Topology**: corrected (`bn` on 0, as design/vco.spice)
- **Corner**: MOS fit series `tt/27 C`, cap_typ, hbt_typ, VCTRL = 1.65 V, VDD 3.3 V
- **Surrogate source**: `sim/varactor-characterization/records/20260927-081226-f88eb89.csv` (sha256 `afb1ad4a4b87d2f6f2b299b7b11ba975bbbe17e4c3e1aed11dc6cc861cdccfe5`, last commit touching it `83b44be302c07aaef8924e002e087cc04d379f84`), mos/small rows, `c_5ghz_f` and `q_5ghz` columns
- **Code commit**: `edf5eb52e1f2a0bdba591b576945ab291981412b`
- **Command**: `sim/oscillator-core/surrogate_bench.py --point corrected --vctrl 1.65 --corner tt --temp 27`; inner simulator command `ngspice -b deck.spice` (single unit, local)
- **Simulator**: `ngspice-42`; transient `tran 1p 5n 0 2p`, window 2.5e-09..5e-09 s, start `.ic` 10 mV differential
- **Rendered deck**: `netlist-snapshots/20261010-060510-edf5eb5-surrogate-corrected/surrogate_corrected.spice` (sha256 `516e82863529886ca8329ce5768e4f29059ee2980d4908cac09ffda8eb078f98`)
- **Model**: charge-based behavioral MOS core (piecewise-linear C, exact piecewise-quadratic q), pointwise series R = 1/(2 pi 5e9 C Q), exactly one native `dsubw`+`rsubw` branch per cell with the sanctioned `vj = 0.3357` overlay (`sim/tools/svaricap_overlay.py`); contract in `sim/tools/svaricap_surrogate.py`.
- The behavioral surrogate omits OSDI device noise; no phase-noise result from it is complete device-noise evidence.
- Issue #94 remains the only route to graded, OSDI-backed full-oscillator evidence.
- Fleet grids, full tuning sweeps and ISF/phase-noise screening are NOT implemented here; they are follow-on work conditional on this smoke result.
- **Limits**: 5 GHz effective C/Q only; fitted bias/corner/temperature/geometry only; one probe cell per side pair (cells 1 and 16 on each side) stands for the 16 identical cells of that side; this smoke does not establish broadband or large-grid accuracy.
- **Estimator**: sim/lib.sh `osc_metrics` on V(OUTP)-V(OUTN), rising crossings through the window mean, interpolated; quantization floor reported per point.
- **Instantaneous v_rec at the core** (whole run, 4 probe cells): min 1.501955 V, max 1.796885 V; domain [0.0, 3.3] V +/- 1 mV -> **OK**

## Result

- starts and oscillates: **YES**
- f_osc = 4.193201e+09 Hz (10 cycles, interpolated quantization floor 0.08386 %, no-interpolation floor 10 %)
- differential Vpp = 5.898386e-01 V; startup settling (0.9 of final envelope) t_settle = 1.785600e-10 s

This is the corrected-topology (`bn` on 0) smoke point. It proves startup and model integration only and is not compared with the pre-#79 frequency.
