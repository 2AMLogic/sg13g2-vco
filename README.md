# sg13g2-vco

An LC voltage-controlled oscillator on IHP SG13G2 on
[IHP SG13G2](https://github.com/IHP-GmbH/IHP-Open-PDK), IHP's open-source 130 nm SiGe BiCMOS PDK — designed by AI agents driving
[klayout-tools](https://github.com/2AMLogic/klayout-tools) and the
open-source xschem + ngspice flow.

**Status: just opened.** Nothing is designed yet. The first work is
the tank inventory — what the PDK's shipped inductor and MIM-cap models actually support, at which frequencies, with which Q.

**Built agent-native.** Every specification, decision record, testbench, and
line of documentation here is produced by AI agents working from a ratified
spec and an append-only evidence trail — not human-authored work that agents
merely assisted with. Verification is the product: every claim traces to a
recorded result under PVT corners. Where the agents hit friction with the
open-source tooling — most often
[klayout-tools](https://github.com/2AMLogic/klayout-tools) — that friction is
filed as a public issue against the tool itself, so the fix benefits everyone
using this PDK, not just this repo.

## Why this block, on this PDK

An LC VCO is the first block in this catalog that exists *because* of what
SG13G2 is: a SiGe BiCMOS process whose HBTs and PDK-shipped passives (MIM
caps, spiral inductors) are meant for RF work. The sibling PLL canaries
(gf180-pll, sky130-pll, sg13g2-pll) use ring or CMOS oscillators; nothing in
the catalog yet demonstrates an LC tank, a cross-coupled negative-gm pair,
or a phase-noise budget. This is a new block, not a port — start from the
published LC-VCO literature and the PDK's own passive/HBT models, not from a
sibling repo's schematics.

The honest centerpiece is **phase noise, and how it is measured with open
tools**. ngspice has no PSS/pnoise analysis; a phase-noise number here must
come from a documented open-tool method (long transient plus spectral
estimation, or an ISF/impulse method), with the method's limits stated next
to every number. A phase-noise claim without its measurement method is not a
result. Expect and file tool friction — that is this canary's job.

## Target specification (DRAFT — engineering to ratify)

Deliberately thin until the tank study lands: target band (to be chosen
against the PDK passives, likely low-GHz), tuning range, phase noise at a
stated offset, supply/power, output swing into a stated load. Every row gets
min/typ/max only when a committed testbench can produce it.

## License

Apache-2.0.
