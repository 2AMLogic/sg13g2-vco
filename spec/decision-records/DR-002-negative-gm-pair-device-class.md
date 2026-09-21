# DR-002: Negative-gm pair — SiGe HBT cross-coupled pair (npn13G2v) over CMOS pair or Colpitts

- **Status**: proposed
- **Date**: 2026-09-21
- **Decided by**: Builder agent, issue #33
- **Related**: #3 (gap-to-T1 tracker — this record supplies the decision
  the tracker's "design/vco.sch + derived netlist" step, named in the
  operator's 2026-09-15T00:00:29Z sequencing comment, consumes),
  #33 (this issue), #5/#6/#8/#9/#11/#23 (the tank-characterization and
  inductor-model/em-extraction evidence this record consumes, per
  `sim/`'s own index), DR-001 (the sibling decision — tuning device and
  `Vctrl` domain — whose own "Consequences" names this record's question
  as still open)
- **Consumes**:
  - `sim/tank-characterization/README.md` — finding 7 and its
    "Consequence for this block" blockquote: at 10 GHz the tank-Q
    limiter is the **inductor** (`Q_L ≈ 5`, an upper bound) and not the
    capacitor (`Q_C` up to 68 for the 20×20 µm `cap_rfcmim`); records
    `20260906-160246-a73c3c7` (analytic-model run) and
    `20260910-052245-3896421` (the run whose inductor rows are
    EM-fitted-model-backed).
  - `sim/inductor-model/em-extraction/README.md` — "What this means for
    the tank": the two multi-turn PDK-testcase geometries self-resonate
    at **8.07 / 9.42 GHz** by EM extraction, **50–77 % lower** than the
    analytic screening model's 14.3/14.1 GHz estimate; a ~10 GHz tank on
    either geometry would run *past*, not below, its own inductor's SRF.
  - The PDK's own shipped HBT models and device documentation
    (IHP-Open-PDK v0.3.0, pinned per `sim/pdk.json`):
    `libs.tech/ngspice/models/sg13g2_hbt_mod.lib` (VBIC Rev. 1.15
    parameter models: `npn13G2`/`npn13G2l`/`npn13G2v`) + `cornerHBT.lib`
    (the `hbt_typ`/mismatch/statistical corner sections), the
    `libs.tech/xschem/sg13g2_pr/npn13G2{,l,v}*.sym` HBT symbols, and
    `libs.doc/doc/SG13G2_os_process_spec.pdf` (Rev. 1.2, §3) — the
    BVCEO/fT/fmax/beta tables cited below.
  - `spec/target-spec.md` rows 0 (supply/device flavor), 6 (startup /
    negative-gm margin), and 4 (phase-noise method, still open) — this
    record is the citation those rows' pending decisions point at, not a
    filler of their numeric cells.
  - `2AMLogic/klayout-tools#1242` (MERGED 2026-08-20, docs-only —
    see "Consequences") and `2AMLogic/sg13g2-bandgap#4` (this PDK
    family's resident evidence of that upstream limitation's downstream
    effect).

## Ratification note (per this repo's own two-key mechanism, unverified
beyond its one-line description)

`spec/target-spec.md`'s Status section describes ratification as flowing
"through the two-key mechanism (EE key + market key)"; DR-001's own
ratification note records the search that found no document anywhere in
this org describing what those keys concretely are or how a PR would
demonstrate them, and this record does not re-run that search or
contradict its finding. **This record therefore follows DR-001's
precedent exactly: it stays `proposed`, not `ratified`, and its PR does
not assert that a single PR merge is sufficient to ratify it.** A future
edit flipping Status to `ratified` should wait until whatever mechanism
DR-001 describes is confirmed to have run against this specific record.
This record's job is to supply the grounded recommendation that
mechanism has something to act on.

## Context

`spec/porting-plan.md` §2 names the negative-gm cross-coupled pair's
device class (CMOS pair vs. SiGe HBT pair vs. Colpitts) as design work
with no sibling schematic to start from, and states what gates it:

> "A future architecture decision record, informed by the tank study's Q
> and SRF data (a low-Q tank needs more gm margin, which favors a device
> class with more gm per unit bias current)."

That gating evidence has since landed on `main` and is materially worse
for the tank than the analytic stand-in that predated it
(`sim/tank-characterization/README.md` finding 7 and
`sim/inductor-model/em-extraction/README.md`):

- The 5-turn spiral's **`Q_L ≈ 5` at 10 GHz is an upper bound** (lateral
  current crowding and substrate eddy-current loss are unmodelled), and
  it — not the capacitor (`Q_C` up to 68) — is what sets tank Q. The
  tank study's own one-line reading: "the real gap is wider, not
  narrower."
- The EM-fitted model moved the two multi-turn PDK-testcase geometries'
  **SRF down to 8.07 / 9.42 GHz** — 50–77 % below the analytic estimate —
  so any tank built on those geometries in the single-digit-GHz-to-10 GHz
  region the tank study contemplates operates near or past its
  inductor's self-resonance, where the inductor's Q is falling.

Exactly the deciding factor porting-plan §2 names — gm margin, per unit
bias current, against a lossy tank — is therefore the one this record
must reason from. The tuning half of the tank is already decided
(DR-001: `sg13_hv_svaricap`, 0.0–3.3 V HV `Vctrl`, its `dC/dV` kernel
measured), and the tracker's next Builder step (`design/vco.sch`, issue #3
and the operator's 2026-09-15 sequencing comment) needs the pair's device
class, topology, and supply flavor before any schematic can be drawn.
This record is that decision.

## Decision

**Adopt a SiGe HBT cross-coupled differential negative-gm pair, built on
the PDK's high-BVCEO HBT flavor `npn13G2v`, biased from the 3.3 V supply
rail.** Topology: the standard differential cross-coupled pair (two
identical HBTs, each collector cross-coupled to the opposite base across
the differential tank, tail-current biased — the tail structure is
schematic-time work). This record does not size the pair, draw it, or
design its bias network.

### Device class: SiGe HBT, because gm per unit bias current is the
deciding axis and the measured tank makes it the expensive axis

The measured `Q_L ≈ 5` (upper bound) at 10 GHz converts directly into
the gm the pair must deliver: the cross-coupled pair presents a
differential negative resistance of magnitude `2/gm` across the tank, so
startup (`target-spec.md` row 6) requires `gm > 2/Rp` with the tank's
parallel loss `Rp` scaling as `ωL·Q_L` — **the lower the inductor's Q,
the more gm per unit inductance the pair must supply, at every
frequency, corner, and temperature the eventual row-6 testbench
sweeps.** This is the porting-plan §2 framing made concrete with the
tank study's own recorded number; it is not a textbook gm-margin
argument disconnected from this PDK's measured evidence.

Between the two device classes SG13G2 offers, the HBT is the one that
answers:

- **Bipolar `gm = IC/VT`** — the physical ceiling on transconductance per
  unit bias current at a given collector current (`1/VT` ≈ 38.6 S/A at
  27 °C); a strong-inversion 130 nm CMOS pair is bounded by
  `gm/ID ≤ 2/(VGS−VTH)`, an order below `1/VT` at the overdrives a
  ~10 GHz-class tank demands. These are device-physics relations used
  structurally here, not measured results; the measured quantity this
  record leans on is the `Q_L` above. The quantitative pair-vs-tank
  margins are row 6's testbench to produce, per this repo's
  numbers-with-methods rule.
- **Corner predictability**: an HBT's `gm` is set by its bias current,
  not by a threshold-voltage corner. `target-spec.md` row 6 requires
  startup margin "stated across process/temperature corners since tank
  loss and active-device `g_m` both move with corner"; on the HBT side
  the PDK ships the corner machinery (`cornerHBT.lib`:
  `hbt_typ`/mismatch/statistical sections over the VBIC models) so the
  row-6 sweep can consume the PDK's own spread directly.
- **Flight through this flow, from the PDK, with no new model
  infrastructure**: the HBT models are SPICE-parameter VBIC Rev. 1.15
  cards (`sg13g2_hbt_mod.lib`) that ngspice runs natively, with matching
  xschem symbols — unlike `sg13_hv_svaricap`, which required the OSDI
  Verilog-A toolchain `sim/pdk.json` documents. Simulating the pair
  adds no new model dependency to this repo.
- **Why the cross-coupled topology and not Colpitts**: the cross-coupled
  pair presents its full `2/gm` directly across the differential tank;
  a Colpitts feedback divider delivers only a fraction (the capacitive
  division ratio) of the device's gm to the tank — on a `Q_L ≈ 5` tank,
  that fraction is paid in startup margin or in the extra tail current
  needed to buy it back, which is the exact opposite of what the
  measured tank budget allows.
- **Where phase noise fits**: this record does **not** justify the HBT
  pair on a phase-noise number. The Hajimiri & Lee ISF framework
  (this repo's canonical frame, `CLAUDE.md`/`spec/target-spec.md` row 4)
  is what later makes swing and margin phase-noise-relevant, but a
  topology chosen on a phase-noise advantage this flow cannot yet
  measure would repeat exactly the evidentiary failure
  `spec/porting-plan.md` §1 documents (ngspice has no PSS/pnoise; a
  number without its method is not a result). The deciding axis here is
  startup margin, which this flow *can* evidence (operating-point and
  negative-resistance testbenches against the HBT models).

### Device flavor: `npn13G2v` (high-BVCEO), on the PDK's own numbers

From `SG13G2_os_process_spec.pdf` (Rev. 1.2 §3, the PDK's own device
tables), `npn13G2v` specifies **BVCEO 2.5 V** (2.2 V min), fT 90–120 GHz,
fmax 280–330 GHz, beta 300–1200 (650 target) — against the standard
`npn13G2`'s **BVCEO 1.6 V** (1.4 V min) at fT 300–350 GHz. The
high-BVCEO flavor is chosen because its breakdown rating is the one that
fits a full-swing oscillator on the 3.3 V rail (below) while its fT —
roughly a third of the standard flavor's — still clears any band the
EM-verified tank geometries plausibly support: the multi-turn
PDK-testcase inductors self-resonate at 8.07/9.42 GHz, and an fT of
90 GHz is ≥ 9× the top of that region. Choosing fT headroom over
breakdown headroom would spend the margin this block cannot yet verify it
has (swing is row 7, unmeasured) and risk the one failure mode
(breakdown) that is permanent rather than tunable.

### Supply flavor: a single 3.3 V rail for the oscillator core,
independent of the varactor's `Vctrl` domain

The pair and its tail run from the PDK's **3.3 V supply domain** — the
same rail class as DR-001's HV varactor rating, but a distinct decision
and a distinct node: `Vctrl` (0.0–3.3 V, DR-001) is a DC control node
sweeping the varactor (gate or well side, per DR-001's still-open
bias-polarity point), not a supply. Choosing the 3.3 V rail does not
constrain the `Vctrl` window, and the `Vctrl` window does not set the
rail. What the rail choice buys: with the tail current source dropping
the difference, the worst-case collector-emitter excursion of a
full-swing pair stays within `npn13G2v`'s 2.5 V BVCEO while keeping the
current-limited swing headroom the ISF frame makes phase-noise-relevant.
The interface check this decoupling leaves open — the tank's DC
common-mode verses the varactor's terminal placement — belongs to the
schematic-time decision DR-001 already scopes, not to this record.
`spec/target-spec.md` row 0's "supply / device flavor" question for the
pair is answered by this section (with DR-001 answering the varactor
half); its numeric min/typ/max cells stay blank per that file's own
rule, pending the testbenches rows 6–9 define.

## Alternatives considered

- **A 130 nm CMOS cross-coupled pair (1.2 V core or 3.3 V HV MOS).**
  Rejected on the deciding axis: strong-inversion CMOS `gm/ID` is bounded
  by `2/(VGS−VTH)` — an order below the bipolar `1/VT` ceiling — so on
  the measured `Q_L ≈ 5` tank, the same startup requirement converts
  directly into either a higher tail current (power, row 8) or thinner
  margin at the VTH corners row 6 must sweep. A CMOS pair is not
  disqualified on speed at these bands — at ~10 GHz, 130 nm MOS fT is
  adequate — which is exactly why this record keeps the rejection on the
  measured gm-margin axis rather than reaching for an fT argument the
  block does not need. The block's stated purpose (`README.md`: nothing
  in the catalog demonstrates an LC tank, cross-coupled negative-gm pair,
  or HBT-based RF design on this PDK) also asks for the HBT path, but
  purpose alone without the measured evidence would not carry this
  decision — the gm-per-current relation carries it.
- **A Colpitts (HBT) oscillator, single-ended or differential.**
  Rejected for v1, for three concrete reasons. (1) The capacitive
  feedback divider presents only a fraction of the device gm to the
  tank, so the same `2/Rp` startup requirement costs more device gm —
  and therefore more tail current — exactly the margin the measured
  `Q_L ≈ 5` budget least affords. (2) Its principled advantage is an
  ISF/cyclostationarity argument (Hajimiri & Lee), which is real in
  shape but is precisely the phase-noise-advantage class of claim this
  flow cannot yet evidence (no PSS/pnoise; row 4's method still open) —
  choosing on it would repeat the failure porting-plan §1 documents.
  (3) A single-ended Colpitts mismatches the differential tank and
  output structure the spec rows assume (row 7: differential swing), and
  a differential Colpitts adds tank-divider complexity before any
  evidence asks for it. Not permanently closed: if the row-4
  phase-noise method study later enables topology-vs-ISF measurements on
  this flow, a future record may revisit this with evidence.
- **The standard `npn13G2` (high-fT, low-BVCEO) HBT flavor.** Deferred,
  with a named trigger, not rejected: its fT (300–350 GHz) is 3× the
  `npn13G2v`'s, but this record's bands do not need it (see "Device
  flavor"), and its 1.6 V BVCEO (vs 2.5 V) buys only 0.9 V of swing
  headroom on a 3.3 V rail — less than the current-limited swing an LC
  tank wants to maximize per the ISF frame. Trigger to revisit: if
  tank-sizing evidence lands the center band (target-spec row 1) far
  enough from the inductor SRFs that swing stays provably inside 1.6 V
  VCE excursions, or the band lands materially above ~10 GHz where fT
  margin starts to matter, swap flavors in a follow-up record. Until
  either triggers, the breakdown-rating-first choice stands.
- **A lower core rail (1.2 V / 2.5 V) for the pair alone.** Rejected: it
  narrows the current-limited swing this topology exists to maximize
  while paying the HBT's costs (including the LVS consequence below)
  for none of its high-BVCEO benefit — and if the swing budget were
  really 1.2 V-class, the CMOS pair's rail options would dominate on
  every other axis, collapsing the decision rather than refining it. The
  3.3 V rail is the one supply domain this PDK's own HV varactor rating
  (DR-001) already establishes as the block's working class.

## Consequences

**What this fixes / unblocks:**

- Closes `spec/porting-plan.md` §2's "Negative-gm cross-coupled pair"
  open question with a device class, topology, and supply flavor grounded
  in the measured tank evidence (finding 7, the EM-extracted SRFs) and
  the PDK's own HBT tables — not in a generic textbook argument.
- Unblocks the schematic-capture Builder step (`design/vco.sch` +
  derived netlist) named in issue #3 and the operator's 2026-09-15
  sequencing comment: with DR-001's tuning device and domain plus this
  record's pair, every device the v1 schematic instantiates now has a
  decided class.
- Gives `spec/target-spec.md` row 0 (pair supply flavor) and row 6
  (startup margin) their decision citation: the row-6 testbench —
  operating-point and negative-resistance sweeps against the VBIC HBT
  models over `cornerHBT` corners, alongside tank loss from the
  inductor model — can now be authored against named devices with no new
  model infrastructure (the HBT cards run natively in ngspice, unlike
  the varactor's OSDI dependency).

**What this costs, and hands to later design work:**

- **A permanent, already-documented LVS consequence.** `klayout-tools#1242`
  (MERGED 2026-08-20 — verified re-read for this record; it is a
  docs-only investigation, not a fix) formally investigated and
  **permanently declined** bipolar (SiGe HBT) device recognition in
  klayout-tools: the stock `BipolarDevice` model cannot express SG13G2's
  NPN topology. `2AMLogic/sg13g2-bandgap#4` already carries the
  downstream shape of that limitation on this PDK family: LVS completes
  with permanent, attributable mismatch causes (`NPN13G2` unmatched,
  class-level topology entries, disclosure-only warnings). **This block's
  LVS evidence will carry the same permanent mismatch for the pair's
  HBTs**, over and above whatever a clean LVS of the rest of the block
  achieves. This record weighs that cost against the measured gm-margin
  evidence and accepts it: a disclosure-only mismatch with an attributed
  upstream cause is a documented evidence-shaped cost, not a dead end
  (the bandgap repo demonstrates the LVS evidence stays readable with
  it), and per this repo's CLAUDE.md friction protocol, pair-layout
  tooling gaps that surface in `klt` get filed generically upstream as
  they are hit — with the design-specific detail kept out of the tool
  tracker.
- **Swing/VCE compliance is now the verification burden the rail choice
  creates.** The 3.3 V rail + `npn13G2v` (BVCEO 2.5 V) combination is
  only safe if the row-6/row-7 testbenches confirm the tail drop keeps
  worst-case VCE excursions inside 2.5 V; that check is part of the
  schematic-time work this record unblocks, not something it performs.
- **The `npn13G2v` fT margin is band-contingent.** At ~90 GHz fT the
  choice is comfortable for the EM-plausible sub-10 GHz bands but must
  be re-read if a later target-band decision (row 1) lands materially
  higher — the named revisit trigger under "Alternatives considered".
- **Startup-margin, swing, power, and pushing numbers all remain open**,
  per this repo's no-number-without-a-testbench rule — this record names
  devices, a topology, and a rail; it does not fill a single numeric
  cell in `spec/target-spec.md`.
- **No schematic, negative-gm pair sizing, or bias-network
  implementation is authorized by this record** — per this issue's own
  explicit scope boundary, mirroring DR-001's: this record recommends a
  device class, topology, and supply flavor; a separate issue implements
  the schematic using this decision plus DR-001's decision plus the
  fitted inductor models.

## Sources

- `sim/tank-characterization/README.md` — finding 7 ("Against the
  analytic inductor model, at 10 GHz the tank-Q limiter is the inductor
  (`Q_L ≈ 5`, an upper bound) and not the capacitor (`Q_C` up to 68)")
  and the "Consequence for this block" blockquote it derives; records
  `20260906-160246-a73c3c7` / `20260910-052245-3896421`.
- `sim/inductor-model/em-extraction/README.md` — "What this means for
  the tank": `p13`/`p11` self-resonate at **8.07/9.42 GHz** by EM
  extraction, not 14.3/14.1 GHz; a ~10 GHz tank on either PDK-testcase
  geometry runs past its inductor's SRF. Plus
  `sim/inductor-model/README.md` §"Accuracy limits" for the error bars
  these numbers travel with.
- `spec/decision-records/DR-001-tuning-mechanism.md` — the sibling
  decision (tuning device, `Vctrl` domain, bias-polarity question left
  open) and the ratification-note precedent this record follows
  verbatim in structure.
- `spec/target-spec.md` — rows 0, 6 (this record is their pending
  decision's citation), row 4 (phase-noise method, still open), and the
  Status section's two-key description DR-001 quotes.
- `spec/porting-plan.md` §1 (the phase-noise evidentiary objection this
  record's Decision section deliberately respects) and §2 (the
  negative-gm row this record answers; the gm-per-unit-bias-current
  framing it hands this record).
- IHP-Open-PDK v0.3.0 (pinned per `sim/pdk.json`):
  `libs.tech/ngspice/models/sg13g2_hbt_mod.lib` (VBIC Rev. 1.15 HBT
  parameter cards), `libs.tech/ngspice/models/cornerHBT.lib`,
  `libs.tech/xschem/sg13g2_pr/npn13G2{,l,v}*.sym`, and
  `libs.doc/doc/SG13G2_os_process_spec.pdf` (Rev. 1.2 §3) — the
  BVCEO/fT/fmax/beta tables the "Device flavor" section reads.
- `2AMLogic/klayout-tools#1242` (MERGED 2026-08-20; state re-verified
  against the live issue for this record — docs-only investigation that
  permanently declined bipolar recognition, closing klayout-tools#1232)
  and `2AMLogic/sg13g2-bandgap#4` (the downstream LVS-mismatch evidence
  this PDK family already carries for `NPN13G2`).
- Hajimiri, A. and Lee, T. H., "A General Theory of Phase Noise in
  Electrical Oscillators," *IEEE Journal of Solid-State Circuits*, 1998 —
  this repo's canonical phase-noise frame (`CLAUDE.md`), cited here for
  why swing and margin — not an unmeasured topology advantage — carry
  the phase-noise relevance of this decision.
- This repo's own `CLAUDE.md` — "State the tuning plan honestly", "no
  claim without a testbench", "numbers without methods are not results",
  and the friction-protocol canary framing that shapes the LVS
  consequence above.
