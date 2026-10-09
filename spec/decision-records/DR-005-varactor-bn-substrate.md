# DR-005: Varactor `bn` is the p-substrate -- tie it to `0`, not to the tank node

- **Status**: **proposed** -- a design correction made in the PR that carries this
  record (issue #79), taking effect when that PR merges. It changes **no row of
  `spec/target-spec.md` and relaxes no bound**; it does change what DR-001's
  device evidence is evidence *of* (see "Consequences"). Same two-key path as
  DR-003/DR-004; a stale `Status:` field is not evidence the decision did not
  take effect.
- **Date**: 2026-10-09
- **Decided by**: Builder agent, issue #79
- **Supersedes**: none. It corrects an assumption in `design/README.md` and
  qualifies how DR-001's varactor evidence may be used; DR-001's decision (MOS
  accumulation varactor, full 0.0-3.3 V domain) stands.

## Context

`design/vco.sch` tied each `sg13_hv_svaricap`'s 4th pin `bn` to the tank node
(`XCVP1 VCTRL OUTP VCTRL OUTP ...`). The PDK's subcircuit annotates that pin
*Substrate*; IHP's LVS runset extracts it as `SUB` on the p-substrate net; the
layout draws it on the substrate, tied to `0` by the guard ring (`layout/PROVENANCE.md`
§6), and cannot do otherwise without an isolated p-well that neither the
schematic nor the layout has. The device-aware LVS (#62) measured the
disagreement and its control isolated it (`layout/PROVENANCE.md` §14).

`design/README.md` justified the tie: "tying `W` and `bn` together shorts out the
internal `dsubw` well-to-substrate junction rather than hanging it on the tank
node, so the two-terminal impedance, and hence its Q, is the same either way."
That was true of the varactor characterization testbench (which also tied them,
so its C and Q exclude the junction) and false of the drawn layout, where each
bank's n-well sits on the substrate.

## Decision

`bn` is tied to `0` (the substrate) on all 32 varactors in `design/vco.sch`;
`design/vco.spice` is regenerated from it (`design/netlist.sh`); the LVS
reference is derived from the new netlist (`layout/lvs.sh`). No spec bound,
band, ratio or Q target is changed.

## Alternatives considered

- **Keep `bn` on the tank and call the layout wrong.** Not physically
  realizable without a deep-n-well/isolated-p-well structure the block lacks;
  it would make every sign-off simulation describe a device that cannot be
  built. Rejected.
- **Add the isolation structure to the layout** (so `bn` could float on the
  tank). Not asked for, large layout change, and it would add its own
  deep-n-well-to-substrate junction on the tank. Out of scope; may be revisited
  as a deliberate tank-Q recovery option.
- **Tie `bn` to a quiet bias instead of `0`.** `bn` is the shared substrate;
  the layout has one substrate net. Not available.

## Consequences

**Measured** (`sim/bn-substrate-tank/`, passive tank, small-signal AC, a lumped
surrogate for the OSDI MOS core with the PDK's own `dsubw`/`rsubw` verbatim; the
method and its limits are in that README): the junction is 16 x ~8.4 fF in
series with ~17.6 ohm on each tank node. Across MIM typ/bcs/wcs x T -40/27 C x
(MOS tt at Vctrl 0/1.5/3.3, ss/ff at 1.5) f0 falls **17.3-23.3 %** (band centre
5.53 -> 4.27 GHz), phase-bandwidth tank Q falls **17.4-27.8 %** (13.8 -> 10.0 at
27 C), the impedance peak is 0.56x, and the tuning ratio goes 1.18 -> 1.11.

1. **Row 1 / row 2 / row 5 / row 4 are now at risk, not relaxed.** The tank
   alone lands near 4.3 GHz at band centre (row 1 band 4.5-5.5 GHz) with a
   ratio under the row-2 floor of 1.15. Nothing in this record changes those
   rows; re-sizing the tank (fewer/smaller varactor cells, smaller MIM,
   inductor) against the corrected netlist is the follow-up, and is a design
   task, not a spec change. If it cannot recover the band, *that* would be a
   spec question and would need its own record.
2. **Phase noise (row 4) was not measured.** The ISF bench needs the OSDI MOS
   varactor. Inference only, from the tank Q and impedance, no estimator and
   so no variance: between about +0.5 dB (Leeson, equal offset) and +5.5 dB
   (current-limited swing), sign certain, size unknown, at a 4.3 GHz carrier.
3. **DR-001's varactor evidence** (`Cmax/Cmin` 1.88-2.08x, Q) is for the device
   with `W`/`bn` tied. It remains the right evidence for the MOS core; it is
   not the impedance of the cell as built, which now includes the junction.
4. **A PDK-model hazard surfaced.** With `bn` on the substrate the PDK's
   `dsubw` card (`vj = 0.1 V`) goes NaN above ~52 C in ngspice (42 and 46), so
   **the corrected netlist cannot be simulated at row 11's +125 C with the
   card as shipped**. The +125 C rows of the A/B are error rows; a flagged
   `tnom` workaround gives a sensitivity only.
5. **Not regenerated, and why.** `design/run_elaborate.sh`, `sim/oscillator-core`
   and `sim/phase-noise` need the OSDI `mosvar` library. Locally ngspice-42
   refuses the OSDI v0.4 the pinned compiler emits; on the fleet the runner
   (klt 0.5.0) cannot accept `osdi_preload`
   (2AMLogic/klayout-tools#2851/#2877/#2901). Those records are append-only
   and describe the **pre-#79** netlist; each README now says so. They must be
   re-run, as new records, when either path opens.
6. **LVS:** the 32-device `bn` difference is gone; the record compare pairs 42
   of 43 device pairs and the one remaining pair is spiral L1's terminal order
   (#80, an extractor artefact). The verdict is still `mismatch`, honestly.
