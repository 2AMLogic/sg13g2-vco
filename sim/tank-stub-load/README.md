# `tank-stub-load/` -- what #420's OUTP/OUTN edge-pin straps load onto the tank

`layout/vco.gds` exposes the tank outputs as TopMetal1 chip-level pins at the
bbox bottom edge (issue #420, `layout/PROVENANCE.md` §17): a 2.0 um
TopMetal1 strap per tank node, from the existing tank strap down to the guard
ring's outer edge. Each strap hangs on the tank node itself, so it is a
capacitive load the block (and any parent) pays for. This directory is the
measurement of that load: resonance frequency, tank Q and tuning ratio, with
and without the stubs, over a declared corner set.

Records are append-only: `records/<UTC stamp>-<short sha>/`.

## What is, and is not, measured

**Measured:** small-signal AC (`ac lin 5501 1g 12g`) of the same surrogate
passive differential tank as [`../bn-substrate-tank/`](../bn-substrate-tank/)
(post-#79 form, post-#95 overlay): `XL1`/`XL2` (the EM-fitted `inductor`
subckt, inlined), `XC1` (`cap_cmim`, same card) and 16 varactor cells per side
(lumped series R-C core inside the PDK subckt's own `dsubw`/`rsubw` text),
driven by a 1 A differential current so `v(zd)` is the differential
impedance. The only difference between the two variants is two ideal
node-to-substrate capacitors:

- `nostub` -- the tank as drawn before #420;
- `stub` -- plus `Cstp OUTP 0 6.888f` / `Cstn OUTN 0 6.1992f`.

**The stub capacitance is geometric, not extracted.** The requesting parent
(`sg13g2-lc-pll`, #345) recorded 0.0861 fF/um for its own 2.0 um TopMetal1
routes over substrate; #420's straps are drawn at the same 2.0 um width
(`layout/scripts/floorplan.py` `TANK_PIN_W`), so the added capacitance per
side is that coefficient times the NEW strap length (the metal that was not
there before; the in-bbox overlap was already part of the tank):

- OUTP: y -26.0 .. -106.0 -> 80.0 um -> C_p = 0.0861 x 80.0 = **6.888 fF**
- OUTN: y -34.0 .. -106.0 -> 72.0 um -> C_n = 0.0861 x 72.0 = **6.1992 fF**

Limits of that estimate, stated: the coefficient is the parent's geometric
figure transferred into this block's substrate environment, not an extraction
of this layout (no neighbouring metal within 13 um of either strap; the guard
ring's Activ box is 39 um from OUTP's strap and 14 um from OUTN's, by the
floorplan `RING` constants); fringing and strap-to-ring coupling are not
separated out. Series resistance of the strap is not modelled: at a
conservative 1 ohm the capacitor branch's own Q is 1/(2 pi f C R) > 5000 at
4 GHz, three orders above the loaded tank Q, so it cannot move f0 or Q at
the precision claimed.

**Surrogate -- read this before citing any number.** Same caveats as
`../bn-substrate-tank/README.md`: the MOS-capacitor core of each varactor
cell is a lumped series R-C (27 C, 5 GHz values from the committed varactor
record at every temperature), the HBT pair / tail / bias network are omitted,
and the absolute f0 is ~2 % high against the full oscillator. The A/B
**delta** here is native ngspice elements only (an ideal C per side), so the
measured shift does not inherit the surrogate's absolute error -- it inherits
only the surrogate's tank-to-full-oscillator offset, which cancels to first
order in a small-charge perturbation. That cancellation is a stated limit,
not a proof.

**Estimators.** Identical to `../bn-substrate-tank/` (issue #166 validation):
each unit is one deterministic AC solve, so there is no sampling variance;
numerical resolution is the 2 MHz sweep step (about +-0.05 % on f0, +-0.5 %
on Q). `f0` is the zero-phase crossing of Z; Q is the phase-bandwidth Q,
`f0/(f_m45 - f_p45)`. `analyze.py` reduces a corner to numbers only if f0,
f_p45, f_m45 and zpk are finite, positive and ordered; every expected
(variant, point, process, temperature) appears exactly once in
`stub-ab-coverage.csv`.

## Corner set (declared; it is a subset)

| axis | values run |
|---|---|
| MIM corner (`cap_*`, `cornerCAP.lib`) | typ, bcs, wcs |
| temperature | -40, 27, 125 C |
| Vctrl | 0.0, 1.5, 3.3 V (tt MOS); 1.5 V only for ss, ff |
| MOS corner (varactor core C, R) | tt (all three Vctrl), ss, ff (band centre only) |
| stub capacitance | the two geometric values above; no sensitivity sweep |
| not run | `sf`, `fs` MOS; HBT corners (no HBT in this bench); supply sub-corners |

Every unit went to the Spot batch fleet as a `klt sim` request with
`--wait-for-capacity 600` (`run_stub_ab.sh`), none locally: 10 units x 9
corners = 90 rows, **90/90 valid** (the #95 `dsubw` overlay keeps even the
+125 C rows finite -- unlike the older `bn-substrate-tank` records, whose
pre-overlay +125 C rows are errors). The fleet's ngspice is 47.

## Results (record `records/20261121-074401-e6b0670-226451eb/`)

`stub-ab-delta.csv` pairs the variants per (mos, vctrl, process, temp) -- 45
pairs. Anchor row (tt MOS, typ MIM, 27 C, band-centre Vctrl 1.5 V):

| | `nostub` | `stub` | change |
|---|---|---|---|
| f0 | 4.2683 GHz | 4.2266 GHz | **-0.98 %** |
| phase-bandwidth Q | 10.00 | 10.06 | +0.59 % |
| impedance peak | 2.269 kohm | 2.261 kohm | -0.36 % |

Ranges over all 45 pairs: **f0 -0.79 .. -1.02 %**, **Q +0.21 .. +0.76 %**,
impedance peak -0.24 .. -0.60 %. The shift is weakest at Vctrl 3.3 V
(-0.79 .. -0.82 %, where the varactor C dominates the tank) and strongest at
band centre and above (-0.97 .. -1.02 %); it is insensitive to MOS corner and
MIM corner at the 0.1 % level, and to temperature at the 0.03 % level --
the stub is a fixed C against a corner-varying tank, exactly as drawn.

Tuning ratio `f(0.0)/f(3.3)` (tt MOS, `stub-ab-tuning.csv`):
1.1113 .. 1.1168 -> 1.1093 .. 1.1146, i.e. **-0.18 .. -0.20 %** over MIM
corner x temperature.

## What these numbers do and do not decide

No `spec/target-spec.md` row is graded here (passive tank, surrogate). Spec
context, stated so the number is not misread: rows 1/2 are **already unmet
pre-#420** (graded band centre 4.000 GHz against the 4.5-5.5 GHz window,
ratio 1.1096 against >= 1.15; the re-tune decision DR-006 is pending), so
nothing moves met -> unmet -- but the stub deepens both shortfalls by ~1 %
of f0 and ~0.2 % of ratio, and that cost is intrinsic to exposing the pins
at the edge at all. The trade belongs to whoever lands DR-006: per side, the
pin replaces a ~103-111 um parent route (~8.9-9.5 fF by the parent's own
geometric estimate) with a ~29 um one (~2.5 fF), against the 6.2-6.9 fF the
stub itself adds inside this block.

## Reproducing

```sh
sim/tank-stub-load/run_stub_ab.sh      # submits 10 units to the batch fleet
python3 -I sim/tank-stub-load/analyze.py <record-dir> [--strict]
```

`make_requests.py --cp/--cn` override the stub capacitances (in farads).
Raw per-unit outputs live in the fleet artifact store; only the run's
manifest is committed (`manifests/artifacts/tank-stub-load-<run-id>.manifest.json`,
issue #253). The record's `decks/` carries each unit's netlist, request and
`cell.json` (which records the stub values and the `dsubw` overlay lineage).
