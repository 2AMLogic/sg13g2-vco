# `bn-substrate-tank/` -- what tying the varactor `bn` to the substrate does to the tank (issue #79)

`design/vco.sch` tied each `sg13_hv_svaricap`'s 4th pin `bn` to the tank node.
The pin is the p-substrate, the layout draws it on the substrate (`0`), and
#79 corrected the schematic. This directory is the measurement of what that
correction does to the **passive tank**: resonance frequency, tank Q and the
tuning ratio, before and after, over a declared corner set.

Records are append-only: `records/<UTC stamp>-<short sha>/`.

## What is, and is not, measured

**Measured:** small-signal AC (`ac lin 5501 1g 12g`) of the differential tank
of `design/vco.spice` -- `XL1`/`XL2` (the EM-fitted `inductor` subckt, same
instance cards), `XC1` (`cap_cmim`, same card) and 16 varactor cells per side
-- driven by a 1 A differential current, so `v(zd)` is the differential
impedance. The only difference between the two variants is the connection of
each cell's `bn`: to its own well `W` (`bn-tank`, the pre-#79 schematic) or to
`0` (`bn-sub`, the corrected one).

**Surrogate -- read this before citing any number.** The MOS-capacitor core of
a varactor cell (`nmvcap1/2`) is an OSDI (Verilog-A) device. It cannot be
loaded here (see "Why not the whole oscillator"), so each cell's core is a
lumped series R-C, with C and R taken from the committed varactor record
(`../varactor-characterization/records/20260927-081226-f88eb89.csv`,
`mos_small` = the netlist's w 3.74 u / l 0.3 u / Nx 1; C = `c_5ghz_f`,
R = 1/(2 pi 5e9 C Q5); V_rec = 3.3 - Vctrl, because that record put the sweep
on the well with the gate at 0 V). Everything *else* in the cell is the PDK
subcircuit's own text, copied verbatim: the `dsubw` diode (area/perimeter
expressions, `.model dsubw d ...`), the series `rsubw`, and `bn`. Because that
record tied `W` and `bn` together, its C and Q are the cell *without* the
junction, so the junction is added once, by the native diode, not double
counted. The A/B **delta** is therefore dominated by native ngspice elements;
the **absolute** f0 is a surrogate. Limits of the surrogate:

- MOS-core C and R are the 27 C, 5 GHz values at every temperature (the record
  shows C(T) varying by 2-4 % and Q5 by about 4 %, over -40 .. 125 C);
- the HBT pair, tail and bias network are omitted. Cross-check against the
  full oscillator (`../oscillator-core/records/20260926-010627-e391693-pilot.csv`,
  old netlist, tt/typ, 27 C): the full circuit oscillates at 5.419 GHz
  (Vctrl 0 V) and 4.622 GHz (3.3 V), ratio 1.172; this tank-only surrogate
  resonates at 5.546 / 4.691 GHz, ratio 1.182. The surrogate is 2.3 % /
  1.5 % high in f0 (the pair's capacitance) and 0.8 % high in ratio;
- the AC solve is small-signal at the DC operating point (OUTP = OUTN = 3.3 V
  through the inductors), so the junction sees 3.3 V reverse bias. At full
  swing the junction capacitance modulates; this is not captured.

**Estimators.** Each unit is one deterministic AC solve, so there is no
sampling variance; numerical resolution is the 2 MHz sweep step (about
+-0.05 % on f0, +-0.5 % on Q). `f0` is the zero-phase crossing of `Z`. Q is the
**phase-bandwidth Q**, `f0/(f_m45 - f_p45)`, with `f_p45`/`f_m45` the
frequencies where the phase of `Z` is +/-45 degrees (the half-power points of
an ideal parallel RLC, not exactly so here). It is a *loaded tank* Q, with
the inductor model's loss, the MIM, the varactor cores and now the junction
in it. ngspice 42 `.meas` has no `PARAM` in AC, hence the phase thresholds.

## Corner set (declared; it is a subset)

| axis | values run |
|---|---|
| MIM corner (`cap_*`, `cornerCAP.lib`) | typ, bcs, wcs |
| temperature | -40, 27, 125 C |
| Vctrl | 0.0, 1.5, 3.3 V (tt MOS); 1.5 V only for ss, ff |
| MOS corner (varactor core C, R) | tt (all three Vctrl), ss, ff (band centre only) |
| not run | `sf`, `fs` MOS; HBT corners (no HBT in this bench); supply sub-corners; the 45-corner x 10-point graded grid |

Every unit went to the Spot batch fleet as `klt sim` requests
(`run_tank_ab.sh`), none locally. 15 of the 108 rows are error rows (see next
section). 

## The +125 C problem -- a finding about the PDK model

With `bn` on the substrate the stock `dsubw` card goes **NaN above roughly
52 C**, in ngspice-42 locally and in the fleet's ngspice-46 alike. The card has
`vj = 0.1 V`; ngspice scales the junction potential with temperature, it
crosses zero, and the capacitance expression `(1 + V/vj)^-m` goes NaN once the
junction is reverse biased. (A single diode, 3.3 V reverse, AC: finite at 50 C,
NaN at 55 C.) With `bn` on the well the junction sees 0 V and the problem is
masked, which is why it was never visible. Consequence: **the corrected
netlist cannot be simulated at 125 C (row 11's upper bound) with the PDK's card
as shipped.** The 125 C rows of `bn-sub` are error rows, recorded as such.

A flagged supplement, `bn-sub-tnom125` and `bn-sub-tnom85`, adds `tnom = T` to
the `dsubw` model line (stopping the vj scaling at that temperature). It is
**not** the PDK's card and is shown only as a sensitivity: at 125 C it gives
the same f0 shift (-22.6 .. -23.3 % at Vctrl 0 / 1.5, -18 % at 3.3) and Q
(-26 %) as the as-shipped 27 C rows, i.e. the temperature dependence of the
junction capacitance that the model *would* have is small compared with the
effect itself. What the correct temperature scaling of this junction is, is a
PDK-model question, not answered here (filed as a follow-up).

## Results (record `records/20261009-002323-383f22e/`)

`tank-ab-delta.csv` pairs each `bn-sub` row with its `bn-tank` row;
`tank-ab-tuning.csv` has the tuning ratios. Headlines (27 C, tt MOS, typ MIM,
band centre Vctrl 1.5 V; the ranges are over the whole table):

| | `bn` = tank (old) | `bn` = 0 (new) | change |
|---|---|---|---|
| f0 | 5.532 GHz | 4.268 GHz | -22.9 % (range -17.3 .. -23.3 %) |
| phase-bandwidth Q | 13.78 | 10.00 | -27.5 % (range -17.4 .. -27.8 %) |
| impedance peak | 4.0 kohm | 2.3 kohm | x0.56 |
| tuning ratio f(0 V)/f(3.3 V) | 1.182 | 1.113 | -0.069 |

Tuning ratio, new netlist, over MIM corner and -40/27 C: 1.111 .. 1.116 (old:
1.179 .. 1.186). The MIM corner moves f0 by about +-1 %; temperature moves Q
(-40 C: 15.7 -> 11.4, i.e. the same -27 %) but not the ratio.

### Phase noise: not measured; a bracket, labelled as inference

No phase-noise number was produced. The ISF bench (`../phase-noise/`) needs
the OSDI varactor and could not be run for #79. What the tank result *implies*,
by two textbook scalings (these are inferences from the tank Q and impedance, not
simulation, with no variance because there is no estimator):

- Leeson, equal offset and equal sustaining-device noise factor,
  `L ~ (f0 / 2 Q df)^2`: `20 log10[(4.268/5.532) / (10.00/13.78)] = +0.5 dB`
  (lower f0 helps, lower Q hurts, nearly cancelling);
- if the pair is current-limited (swing ~ I * Rp) the 0.56x impedance peak
  costs a further `20 log10(1/0.56) = +5.0 dB`, giving `+5.5 dB`.

So the effect on phase noise is **between roughly +0.5 and +5.5 dB, sign
certain, size not known**, at a different carrier (4.3 GHz, not 5.0). Not a
spec-row verdict; row 4 stays as ungraded as it was.

## Why not the whole oscillator (`design/run_elaborate.sh`, `oscillator-core`, `phase-noise`)

All three need the OSDI `mosvar` library, and none could be regenerated:

1. **Locally**: this host's ngspice is 42 (OSDI v0.3 only). The pinned
   compiler (OpenVAF-Reloaded v24.0.1mob, `sim/tools/build-osdi.sh`) emits OSDI
   v0.4, which ngspice 42 refuses ("targets v0.4"). `build-osdi.sh` also writes
   its result into the shared PDK tree.
2. **On the fleet**: the batch runner image runs klt 0.5.0. A 0.7.0 client is
   refused (`batch_runner_version_mismatch`); a 0.6.0 client is accepted but
   cannot send `options.osdi_preload` / `stage_model_inputs` (0.7.0 only), nor
   stage `.include` files. Upstream:
   2AMLogic/klayout-tools#2851, #2877, #2901.

These records are therefore **not** superseded by this change; they remain the
evidence for the *pre-#79* netlist and say so in `design/README.md`.

## Reproducing

```bash
sim/bn-substrate-tank/run_tank_ab.sh      # needs network + the fleet; uvx klayout-tools==0.6.0
python3 -I sim/bn-substrate-tank/analyze.py sim/bn-substrate-tank/records/<stamp>
```

`make_requests.py` documents the circuit in its docstring; the frozen decks and
requests of each unit are under `records/<stamp>/decks/`, the klt reports
(job ids, ngspice 46 runner) under `reports/`.

## Candidate re-tune (#93)

`make_requests.py --cells N --mim-um S --candidate NAME` emits one bn=0 variant
at an explicit sizing (defaults reproduce the #79 decks; decks identical, only
`cell.json` gains the sizing keys). `run_tank_ab.sh` takes `TANK_AB_ARGS` and
`TANK_AB_LABEL`. New records (append-only, the #79 record is untouched):

- `records/20261009-2100-2eb3659-candidate-screen/` -- tank_screen output
  (374 candidates), `envelope.py` output to 600 cells, the known-answer
  self-check, `bench-comparison.csv`, and `COMMANDS.txt`.
- `records/20261009-205236-2eb3659-cand-n14-m1p14/`,
  `records/20261009-205834-2eb3659-cand-n12-m1p14/` -- frozen decks, reports
  (job ids) and `tank-ab*.csv`. Same surrogate and limits as above: lumped
  MOS-core R-C per cell (cell scaling assumed), no HBT loading, small-signal,
  tt MOS corner at the Vctrl endpoints only, fleet ngspice. 15 of 45 rows in
  each are +125 C error rows (the `dsubw` NaN problem, #95); they are errors,
  not passes, and the ratios below use only -40/27 C.

| | cells | MIM | ratio (27 C, typ) | f0 centre | Q (tt, 1.5 V) | row 2 |
|---|---|---|---|---|---|---|
| baseline | 16 | 3.65 um | 1.113 | 4.05 GHz (endpoints 4.275/3.842) | 10.00 | fail |
| cand-n14-m1p14 | 14 | 1.14 um | 1.122 | 4.50 GHz | 9.63 | fail |
| cand-n12-m1p14 | 12 | 1.14 um | 1.117 | 4.77 GHz | 9.69 | fail |

Conclusion: the explored envelope yields no candidate meeting row 2; see
`design/README.md` ("Re-tune against the corrected netlist (#93)") for the
structural argument and the decision needed. Q is the loaded-tank value without
the HBT pair; startup, power and large-signal junction modulation are
unassessed. #94 owns full oscillator/PVT/phase-noise regeneration.
