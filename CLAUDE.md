# sg13g2-vco — agent instructions

Open-source canary block: an lc voltage-controlled oscillator on ihp sg13g2,
on IHP SG13G2, IHP's open-source 130 nm SiGe BiCMOS PDK, designed and verified by AI agents.

- **PDK**: IHP SG13G2 (https://github.com/IHP-GmbH/IHP-Open-PDK). Open-source flow: xschem + ngspice for
  design/sim, klayout-tools (`klt`) for layout work.
- **This is a new block, not a port.** The catalog's other oscillators are
  ring/CMOS types inside PLLs. Start from the LC-VCO literature (Hajimiri/Lee
  ISF work is the canonical phase-noise frame) and the PDK's shipped HBT and
  passive models. There is no sibling schematic to copy.
- **Phase noise carries its measurement method.** ngspice has no PSS/pnoise.
  Every phase-noise number states how it was produced (transient length,
  window, estimator — or ISF derivation), its variance, and the method's
  known limits. Numbers without methods are not results.
- **Tank first.** Characterize the PDK's spiral-inductor and MIM-cap models
  (L, Q, SRF across the band) before sizing the pair; commit that study to
  `sim/` — every later tuning-range and phase-noise claim leans on it.
- **State the tuning plan honestly**: varactor choice (MOS accumulation vs
  junction), band-switching if any, and KVCO linearity across the range.
- **Friction protocol (the canary's job)**: every time klayout-tools is
  awkward, missing a capability, or wrong for what you need, file an issue at
  `2AMLogic/klayout-tools` describing the tool gap generically — that tracker
  is scoped to the tool, so keep design-specific detail out of it and
  describe the gap, not the design.
- **Verification is the product**: no claim without a testbench; PVT corners
  on every recorded result; `sim/` results are append-only evidence.
- Spec changes go through `spec/` with a decision record; agents do not
  relax the ratified spec to make results pass.

<!-- BEGIN LOOM ORCHESTRATION -->
This repository uses [Loom](https://github.com/rjwalters/loom) for AI-powered development orchestration — see the Loom repository for the full guide (roles, labels, worktrees, configuration). When installed, Loom also writes a locally-substituted copy of that guide to `.loom/CLAUDE.md`.
<!-- END LOOM ORCHESTRATION -->
