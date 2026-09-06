# sim/ — ngspice testbenches and append-only evidence records

Per this repo's `CLAUDE.md`: **verification is the product, no claim without a
testbench, PVT corners on every recorded result**, and everything here is
**append-only evidence** — a re-run mints a new, timestamped record; nothing
under `records/`, `netlist-snapshots/` or `corners/` is ever edited or deleted
after it lands. The convention follows `spec/porting-plan.md` §3, which names
it as the one category that transfers to this block from the catalog's more
mature siblings unchanged.

## Experiments

| Directory | Claim under test | Status |
|---|---|---|
| [`tank-characterization/`](tank-characterization/) | L / Q / SRF of the passives an LC tank on this PDK would be built from, over a wide candidate band | MIM cap characterized over the full PVT grid from the PDK's own models; **the spiral inductor cannot be characterized from the PDK — v0.3.0 ships no ngspice inductor model** (see that README's "The inductor gap"). The inductor half is covered by the model below, whose error bars travel with every number it produces. |
| [`inductor-model/`](inductor-model/) | that the analytic spiral-inductor model this repo ships implements the closed form it claims to, over a process × temperature grid | 27/27 known-answer points pass to 0.003 %. **This validates the implementation, not the physics** — the model is an *analytic screening* model with stated error bars (±5 % on L, Q an upper bound, 0.5–20 GHz), **not** a PDK model and **not** an EM extraction. EM extraction is tracked as #9. |

## PDK pin

Every record in this tree is generated against the PDK revision pinned in
[`pdk.json`](pdk.json) (IHP-Open-PDK tag `v0.3.0`, with its tarball sha256).
Each record additionally states the exact `PDK_ROOT`, the ngspice version, and
the **content sha256 of every model library the run loaded**, so a reader can
confirm their own install matches without re-deriving it from the pin file
alone.

`pdk.json` also carries a `known_model_gaps` block. A device the PDK does not
ship a simulatable model for is a first-class constraint on what this repo can
evidence, not a footnote.

## Environment

`source env.sh` resolves `PDK_ROOT`/`PDK` — an explicit export wins, otherwise
the usual open_pdks install prefixes are probed. Every `run_*.sh` sources it,
and an interactive `ngspice` session can too, so nothing here can silently
drift onto a different install than a script used.

## Directory / naming convention

```
sim/
  README.md                  this file — the authoritative convention
  pdk.json                   pinned PDK revision + known model gaps
  env.sh                     PDK_ROOT/PDK resolution, sourced by every run script
  <experiment-slug>/         one directory per distinct claim under test
    README.md                what was measured, over what band and corners,
                             how to reproduce it, and what it does NOT show
    run_*.sh                 THE cold-start entry point: one command, no args
                             (e.g. run_pvt_sweep.sh, run_model_check.sh)
    .spiceinit               ngspice init copied into the run's scratch dir, so
                             a run never depends on $HOME/.spiceinit existing
    testbench/
      tb_<name>.spice.tmpl   the testbench template (@@PLACEHOLDER@@ form)
    netlist-snapshots/
      <record-id>/
        <corner-id>.spice    the exact generated netlist for that PVT point
    corners/
      <record-id>/
        <corner-id>.log      raw ngspice batch output for that PVT point
    records/
      <record-id>.md         narrative record: claim, method, corners, PDK
      <record-id>.csv        parsed scalar summary, one row per corner × device
      <record-id>-curves/    per-corner curve data vs. frequency, where the
                             curve rather than a scalar is the product
```

`<record-id>` is `<UTC yyyymmdd-HHMMSS>-<git short sha of the tree that ran>`.
`<corner-id>` names the PVT point (e.g. `mimcap_wcs_125c_1.5v`).

## Rules a record must satisfy

1. **One command, cold start.** `spec/review-bar.md` item 1: a single
   documented invocation regenerates the evidence from the committed netlist
   and the pinned PDK, with no hidden manual steps. If a run needs a build
   step, that step belongs *inside* the run script.
2. **Stated corners.** Every recorded result names the process/voltage/
   temperature points it was taken at, and states an explicit reason for any
   axis deliberately not swept.
3. **Frozen netlist.** A record freezes the exact netlist it simulated, so it
   stays readable after the template moves on.
4. **A failure is a result.** A model that does not exist, a point that does
   not converge, or a measurement that misses is recorded with its raw log —
   never dropped so the summary looks clean.
5. **Method before number.** A derived quantity states how it was derived. Where
   the derivation can be checked against closed-form algebra, it is (see
   `tank-characterization/`'s reference network); where it cannot — phase
   noise, per `CLAUDE.md` — the method, its variance and its limits are stated
   with the number or the number is not a result.
6. **A non-PDK model is labelled as one, everywhere it is used.** Where a
   device model does not come from the pinned PDK (e.g.
   `inductor-model/sg13g2_inductor_analytic.spice`, an analytic model standing
   in for a device v0.3.0 ships no model for), the record names that file by
   **repo-relative path and content sha256**, and the model's own stated
   accuracy limits propagate to every number derived from it. A reader must
   never have to guess whether a number came from the PDK or from a
   substitute.
