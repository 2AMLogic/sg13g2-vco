#!/usr/bin/env python3
"""Generate the klt-sim request + deck body for the post-#79 ISF pilot (issue #94).

Mirrors sim/phase-noise/run_isf_pilot.sh: same impulse schedule constants
(pn_bench.sh), same device section (the #290/#291 vco_core_body.spice, copied
unchanged), but the six transients (1 reference + 4 tank-port + 1 tail-port
realisations) are rows of a `corners.params` axis instead of six rendered
decks. Usage: gen_isf_request.py OUTDIR [--probe]  (--probe: 1 unit, for a smoke).
"""
import json, shutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORE = HERE.parent.parent / "oscillator-core/klt-sim/elaborate-post79"

F0_NOM, N_IMP, NPER, T1, HW = 5.384e9, 10, 3, 3.5e-9, 2e-12   # pn_bench.sh
if "--f0" in sys.argv:  # grid-design carrier; pass the MEASURED reference carrier (see record)
    F0_NOM = float(sys.argv[sys.argv.index("--f0") + 1])
DT = (NPER + 1.0 / N_IMP) / F0_NOM
TSTOP = T1 + N_IMP * DT
TIMES = [T1 + k * DT for k in range(N_IMP)]
TANK_DQ = [4e-15, -4e-15, 8e-15, -8e-15]
TAIL_DQ = [4e-15]


def pwl(pname):
    s = "0 0"
    for t in TIMES:
        s += f" {t-HW:.12e} 0 {t:.12e} {{{pname}/{HW:.6e}}} {t+HW:.12e} 0"
    return s


def noise(out, port):
    """Port-noise request (tb_vco_port_noise.spice.tmpl equivalent): small-signal `noise`
    analysis, probe + output as a matched pair, 7 points over 3..9 GHz; the 7 inoise_spectrum
    points come back as expr measurements. The `.ic` line is dropped (the pilot's noise deck
    has none; `noise` runs from the DC operating point)."""
    probe, outv = {"tank": ("IPROBE OUTN OUTP dc 0 ac 1", "v(OUTP,OUTN)"),
                   "tail": ("IPROBE 0 TAIL dc 0 ac 1", "v(TAIL)")}[port]
    body = "".join(l for l in (CORE / "vco_core_body.spice").read_text().splitlines(True)
                   if not l.startswith(".ic")) + probe + "\n"
    (out / f"vco_noise_{port}_body.spice").write_text(body)
    shutil.copy(CORE / "sg13g2_inductor_em.spice", out)
    req = json.loads((CORE / "request-elaborate-post79.json").read_text())
    req["netlist"] = f"vco_noise_{port}_body.spice"
    req["corners"]["supply_v"] = {"vct": [1.65]}
    req["analysis"] = {"kind": "noise", "args": f"{outv} IPROBE lin 7 3e9 9e9"}
    req["measurements"] = [{"name": f"inoise_{k}", "unit": "A/sqrt(Hz)",
                            "expr": f"inoise_spectrum[{k}]"} for k in range(7)]
    (out / f"request-noise-{port}-post79.json").write_text(json.dumps(req, indent=1) + "\n")
    print(f"noise {port}: 7 points")


def main():
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    if "--noise" in sys.argv:
        return noise(out, sys.argv[sys.argv.index("--noise") + 1])
    body = (CORE / "vco_core_body.spice").read_text()
    body += "\n* ISF impulse trains (sim/phase-noise/pn_bench.sh schedule); amplitude = dq/hw from .param rows\n"
    body += ".param dqd=0 dqt=0\n"
    body += f"IISFD OUTN OUTP PWL({pwl('dqd')})\nIISFT 0 TAIL PWL({pwl('dqt')})\n"
    (out / "vco_isf_body.spice").write_text(body)
    shutil.copy(CORE / "sg13s2_inductor_em.spice" if False else CORE / "sg13g2_inductor_em.spice", out)
    req = json.loads((CORE / "request-elaborate-post79.json").read_text())
    req["netlist"] = "vco_isf_body.spice"
    rows = [(0.0, 0.0)] + [(q, 0.0) for q in TANK_DQ] + [(0.0, q) for q in TAIL_DQ]
    if "--probe" in sys.argv:
        rows = rows[:2]
    req["corners"]["params"] = {"dqd": [r[0] for r in rows], "dqt": [r[1] for r in rows]}
    req["corners"]["supply_v"] = {"vct": [1.65]}
    req["analysis"] = {"kind": "tran", "args": f"1p {TSTOP:.12e} 0 2p"}
    req["measurements"] = [{"name": "vdiff_max", "unit": "V",
        "spice": f".meas tran vdiff_max MAX v(vdiff) FROM=2.5n TO={TSTOP:.6e}"}]
    req["options"]["waveforms"] = True
    (out / "request-isf-post79.json").write_text(json.dumps(req, indent=1) + "\n")
    print(f"tstop={TSTOP:.6e} dt={DT:.6e} units={len(rows)}")


main()
