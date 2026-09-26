# `klt sim/` — the graded grid expressed for the corner runner, and why it does not run yet

This directory is a **finding**, not a working path. It exists because this
repo's canary job (`CLAUDE.md`, "friction protocol") is to record exactly where
`klayout-tools` is missing a capability the design work needs, with the
reproduction attached — and because the moment those gaps close, running this
experiment's grid off-host should be a submit, not a rewrite.

Upstream issue: **[2AMLogic/klayout-tools#2511](https://github.com/2AMLogic/klayout-tools/issues/2511)**.

## Why the grid wants to leave the host at all

`../run_pvt_sweep.sh` declares 1350 transient points plus 119 margin
transients. Measured on the machine that wrote it (ngspice-46, one core, the
2 ps timestep ceiling `design/vco.spice`'s own comments justify), this netlist
simulates at roughly **13 ps of circuit time per wall-clock second** — 32 OSDI
varactor instances and four HBTs, all stiff. One 20 ns point is therefore
~25 CPU-minutes and the declared grid is several hundred CPU-hours. That is a
fleet job by any reading, and `klt sim` is the verb that exists to route a
corner matrix to a fleet.

## What is here

| File | What it is |
|---|---|
| `request-pvt-grid.json` | The full row-10/11 grid as a `klt sim` request: 45 composite process corners (MOS 5 × MIM 3 × HBT 3, each a `sections` bundle), the 10-point `Vctrl` axis as `corners.supply_v.vct`, the three row-11 temperatures, the 20 ns `tran`, and the `.meas` cards that would stand in for the extractors. Committed so it stays current with the sweep it mirrors; **not runnable against `klt 0.6.0`.** |
| `attempt-20260926/request-single-corner.json` | The cut-down, single-corner request actually submitted, so the failure below reproduces in one point instead of 1350. |
| `attempt-20260926/corners_sg13g2.lib` | The nested-`.lib` aggregator the attempt had to generate (see gap 3). |
| `attempt-20260926/corner.cir` | The corner deck `klt sim` generated. This is the primary evidence: read its `.control` block. |
| `attempt-20260926/ngspice.log` | The raw failure, carrying both blocking gaps in eleven lines. |
| `attempt-20260926/klt-sim-report.json` | The response, showing how the failure surfaces (as a *measurement* diagnostic, not a model-load one). |

Machine-specific absolute paths in the captured artifacts are replaced by the
same `@@MODELS_DIR@@` / `@@IND_MODEL@@` / `@@ATTEMPT_DIR@@` tokens the ngspice
templates in `../testbench/` use, so the evidence is readable on any checkout.

## The gaps, as reproduced

Read `attempt-20260926/ngspice.log`. Two of the four are visible in it directly.

**1. No way to load the OSDI (Verilog-A) varactor model — blocking.**
`sg13_hv_svaricap` is a Verilog-A compact model; ngspice only instantiates it
from a compiled `.osdi` loaded with `pre_osdi <path>` *inside `.control` and
before the first analysis command*. The generated `.control` block is exactly:

```
.control
alter vct=1.65
tran 1p 20n 0 2p
quit
.endc
```

There is no request field for a control-block preamble and no OSDI field in the
schema — the string `osdi` does not occur anywhere in the installed package. So
all 32 varactor instances go unresolved:

```
Unable to find definition of model xcvp1:sg13_hv_svaricap
```

and the response reports it as `measurement 't_100_periods' produced no value`,
which points at the measurement rather than at the model.

**2. No way to set `ngbehavior=hsa` — blocking.**
The log opens with `Note: No compatibility mode selected!`. The PDK's model
cards are HSPICE-style and `../.spiceinit` exists precisely to set this mode.
`klt sim` runs `ngspice -b` with no `cwd=`, so ngspice reads a `.spiceinit`
from wherever `klt` happened to be invoked, not from the per-corner artifact
directory it just created — the same request is not reproducible between two
shells on one machine.

**3. `corners.process` is bound to one `models.lib` file — worked around.**
SG13G2 ships one corner library per device family
(`cornerMOShv.lib`/`cornerCAP.lib`/`cornerHBT.lib`) and this circuit contains
all three, so a corner needs three `.lib` cards against three *different*
paths. The bundle form emits N sections against the *same* file. The attempt
generated `corners_sg13g2.lib`, whose sections are nested `.lib` calls, and
pointed `models.lib` at that. **This works** — the deck got as far as expanding
the varactor subcircuit, which means the MOS, MIM and HBT sections all
resolved — but every caller with a per-family PDK has to invent it.

**4. No off-host image for this PDK — the harder one.**
`remote_launcher.SUPPORTED_PDKS` is `("sky130A", "gf180mcu")`, and the batch
fleet image bakes `PDK_VARIANTS="sky130A gf180mcuD"`. So even with gaps 1–3
closed, `--backend batch` and `--backend remote` have no `ihp-sg13g2` to run
against. This one is not `klt sim`'s to fix alone — it is a fleet-image
decision — but it is the reason the gap is currently a wall rather than an
inconvenience.

**Also noted upstream, not blocking:** a quantity that is a *function of the
corner axis* — this bench's `f_max/f_min` ratio over the swept `Vctrl`, or its
`Kvco` slope against it — cannot be declared as a measurement, because each
corner is reported independently. The caller has to recompute it from the
report. `../osc_bench.sh`'s `osc_emit_tuning` is that recomputation.

## Reproducing the failure

```bash
# 1. generate the two inputs the request references
cd "$(git rev-parse --show-toplevel)"
source sim/env.sh
M="${SG13G2_NGSPICE_MODELS}"
D=sim/oscillator-core/klt-sim/attempt-20260926
mkdir -p /tmp/klt-sim-repro && cd /tmp/klt-sim-repro

# the circuit body: design/vco.spice's device section (the same split
# osc_bench.sh's osc_derive_body does), plus the non-PDK inductor model,
# the differential observation node the .meas cards read, and the .ic
REPO="$(git -C "$OLDPWD" rev-parse --show-toplevel)"
{
  echo ".include ${REPO}/sim/inductor-model/sg13g2_inductor_em.spice"
  awk '/^\*\*\*\* begin user architecture code/ { exit }
       /^\*\*/ { next } /^[[:space:]]*\.save[[:space:]]/ { next } { print }' \
      "${REPO}/design/vco.spice"
  echo "Bvdiff VDIFF 0 V = V(OUTP) - V(OUTN)"
  echo ".ic v(OUTP)=3.305 v(OUTN)=3.295"
} > vco_core_body.spice

sed "s|@@MODELS_DIR@@|${M}|g" "${REPO}/${D}/corners_sg13g2.lib" > corners_sg13g2.lib
cp "${REPO}/${D}/request-single-corner.json" request.json

# 2. submit one corner locally -- a single unit, so it stays local by policy
klt sim request.json --backend local --format text
```

Expected: `status: error`, one corner, `measurement 't_100_periods' produced no
value`; `.klt/sim/*/ngspice.log` byte-comparable to
`attempt-20260926/ngspice.log` modulo the tokenised paths.

## What happens when the gaps close

Substitute `@@MODELS_DIR@@` / `@@IND_MODEL@@` in `request-pvt-grid.json`,
generate the same two inputs, and submit it. Two things still have to be done by
hand afterwards and are not gaps so much as division of labour: the derived
quantities (`f_max/f_min`, `Kvco`, the row-6 bracket) are recomputed from the
report by `../osc_bench.sh`, and the `.meas`-based period count is a coarser
estimator than `sim/lib.sh`'s `osc_metrics` — `.meas tran ... TRIG/TARG
RISE=n` counts a *fixed number of crossings* and cannot be told "count the
crossings inside this time window", so its discarded-startup window moves with
the frequency instead of being fixed at 10 ns. `../run_method_check.sh` does
not validate that estimator, only the one in `sim/lib.sh`.
