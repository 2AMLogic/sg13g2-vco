#!/usr/bin/env python3
"""Generate the klt-sim request + deck body for the post-#79 ISF pilot (issue #94).

Mirrors sim/phase-noise/run_isf_pilot.sh: same impulse schedule constants
(pn_bench.sh), same device section (the #290/#291 vco_core_body.spice, copied
unchanged), but the six transients (1 reference + 4 tank-port + 1 tail-port
realisations) are rows of a `corners.params` axis instead of six rendered
decks. Usage: gen_isf_request.py OUTDIR [--probe]  (--probe: 1 unit, for a smoke).

Graded-grid additions (issue #53; same device section, same estimator):
  --nper N            integer part of the impulse spacing in carrier periods (default 3, the
                      pilot's; the graded grid uses 9, see GRID_NPER)
  --process NAME --temp T
                      one named PVT corner (NAME = mos_cap_hbt, e.g. ss_bcs_wcs) instead of the
                      pilot's tt_typ_typ / 27 C
  --grid UNITS_CSV OUTDIR
                      write one request per (process, temp) of the 135-point row-10/11 grid under
                      OUTDIR/<process>_<T>C/, plus OUTDIR/grid-plan.csv (which records each
                      corner's carrier AND the nper its impulse instants were baked at, so the
                      reduction driver cannot read it back against a different schedule); the
                      per-corner carrier
                      (--f0) comes from the sim/oscillator-core fleet grid's units CSV (Vctrl 1.65 V)
                      or, where that corner did not oscillate there, from the same process at 27 C
                      (recorded as f0_source=fallback-27C). Impulse times are baked into the PWL
                      sources, so the carrier calibration forces one request per corner.
"""
import csv, json, shutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORE = HERE.parent.parent / "oscillator-core/klt-sim/elaborate-post79"

F0_NOM, N_IMP, NPER, T1, HW = 5.384e9, 10, 3, 3.5e-9, 2e-12   # pn_bench.sh
PLATEAU_FRAC = 0.35                                              # pn_bench.sh PN_PLATEAU_FRAC
GRID_NPER = 9
RATE_PS_PER_S = 11.19   # circuit ps per wall-s, one core, measured by the pre-#79 pilot (pn_bench.sh)
MOS = ["tt", "ss", "ff", "sf", "fs"]; CAP = ["typ", "bcs", "wcs"]; HBT = ["typ", "bcs", "wcs"]
TEMPS = [-40, 27, 125]
TANK_DQ = [4e-15, -4e-15, 8e-15, -8e-15]
TAIL_DQ = [4e-15]
LIBS = "libs.tech/ngspice/models/"


def argval(flag, default=None):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


def schedule(f0, nper):
    """Impulse schedule for a carrier f0: (dt, tstop, times). Mirrors pn_bench.sh / the reducer."""
    dt = (nper + 1.0 / N_IMP) / f0
    return dt, T1 + N_IMP * dt, [T1 + k * dt for k in range(N_IMP)]


def expected_n_plateau(f0_actual, f0_design, nper):
    """Worst-case crossings (one per period) in the last PLATEAU_FRAC of an interval when the
    true carrier is f0_actual but the spacing was designed at f0_design: floor of the plateau
    length in periods (a window of length w holds at least floor(w) rising edges)."""
    import math
    return math.floor(PLATEAU_FRAC * (nper + 1.0 / N_IMP) * f0_actual / f0_design + 1e-9)


def process_bundle(name):
    mos, cap, hbt = name.split("_")
    return {"name": name, "sections": [
        {"section": f"hbt_{hbt}", "lib": LIBS + "cornerHBT.lib"},
        {"section": f"mos_{mos}", "lib": LIBS + "cornerMOShv.lib"},
        {"section": f"cap_{cap}", "lib": LIBS + "cornerCAP.lib"}]}


def pwl(times, pname):
    s = "0 0"
    for t in times:
        s += f" {t-HW:.12e} 0 {t:.12e} {{{pname}/{HW:.6e}}} {t+HW:.12e} 0"
    return s


def all_process_names():
    return [f"{m}_{c}_{h}" for m in MOS for c in CAP for h in HBT]


def noise(out, port, all_corners=False):
    """Port-noise request (tb_vco_port_noise.spice.tmpl equivalent): small-signal `noise`
    analysis, probe + output as a matched pair, 7 points over 3..9 GHz; the 7 inoise_spectrum
    points come back as expr measurements. The `.ic` line is dropped (the pilot's noise deck
    has none; `noise` runs from the DC operating point). `noise` has no impulse schedule, so
    --all-corners puts the whole 45 x 3 grid in ONE request (no carrier dependence)."""
    probe, outv = {"tank": ("IPROBE OUTN OUTP dc 0 ac 1", "v(OUTP,OUTN)"),
                   "tail": ("IPROBE 0 TAIL dc 0 ac 1", "v(TAIL)")}[port]
    body = "".join(l for l in (CORE / "vco_core_body.spice").read_text().splitlines(True)
                   if not l.startswith(".ic")) + probe + "\n"
    (out / f"vco_noise_{port}_body.spice").write_text(body)
    shutil.copy(CORE / "sg13g2_inductor_em.spice", out)
    req = json.loads((CORE / "request-elaborate-post79.json").read_text())
    req["netlist"] = f"vco_noise_{port}_body.spice"
    req["corners"]["supply_v"] = {"vct": [1.65]}
    if all_corners:
        req["corners"]["process"] = [process_bundle(n) for n in all_process_names()]
        req["corners"]["temperature_c"] = TEMPS
    req["analysis"] = {"kind": "noise", "args": f"{outv} IPROBE lin 7 3e9 9e9"}
    req["measurements"] = [{"name": f"inoise_{k}", "unit": "A/sqrt(Hz)",
                            "expr": f"inoise_spectrum[{k}]"} for k in range(7)]
    name = f"request-noise-{port}-{'grid' if all_corners else 'post79'}.json"
    (out / name).write_text(json.dumps(req, indent=1) + "\n")
    print(f"noise {port}: 7 points" + (f" x {len(all_process_names()) * len(TEMPS)} corners" if all_corners else ""))


def isf(out, f0, nper, process=None, temp=None, probe=False):
    """Write the ISF transient request + deck for one carrier. Returns (n_units, tstop)."""
    out.mkdir(parents=True, exist_ok=True)
    dt, tstop, times = schedule(f0, nper)
    body = (CORE / "vco_core_body.spice").read_text()
    body += "\n* ISF impulse trains (sim/phase-noise/pn_bench.sh schedule); amplitude = dq/hw from .param rows\n"
    body += ".param dqd=0 dqt=0\n"
    body += f"IISFD OUTN OUTP PWL({pwl(times, 'dqd')})\nIISFT 0 TAIL PWL({pwl(times, 'dqt')})\n"
    (out / "vco_isf_body.spice").write_text(body)
    shutil.copy(CORE / "sg13g2_inductor_em.spice", out)
    req = json.loads((CORE / "request-elaborate-post79.json").read_text())
    req["netlist"] = "vco_isf_body.spice"
    rows = [(0.0, 0.0)] + [(q, 0.0) for q in TANK_DQ] + [(0.0, q) for q in TAIL_DQ]
    if probe:
        rows = rows[:2]
    if process is not None:
        req["corners"]["process"] = [process_bundle(process)]
        req["corners"]["temperature_c"] = [int(temp)]
    req["corners"]["params"] = {"dqd": [r[0] for r in rows], "dqt": [r[1] for r in rows]}
    req["corners"]["supply_v"] = {"vct": [1.65]}
    req["analysis"] = {"kind": "tran", "args": f"1p {tstop:.12e} 0 2p"}
    req["measurements"] = [{"name": "vdiff_max", "unit": "V",
        "spice": f".meas tran vdiff_max MAX v(vdiff) FROM=2.5n TO={tstop:.6e}"}]
    req["options"]["waveforms"] = True
    (out / "request-isf-post79.json").write_text(json.dumps(req, indent=1) + "\n")
    return len(rows), tstop


def read_f0(units_csv):
    """{(process, temp): f_osc_Hz} for the passing Vctrl = 1.65 V units of the #50 fleet grid."""
    f = {}
    for r in csv.DictReader(open(units_csv)):
        if r["vct_V"] == "1.65" and r["status"] == "pass" and r["f_osc_GHz_from_10_periods"]:
            f[(r["process"], int(r["temp_C"]))] = float(r["f_osc_GHz_from_10_periods"]) * 1e9
    return f


def grid(units_csv, out, nper):
    """One request per (process, temp) + grid-plan.csv (the cost the entry point prints)."""
    out.mkdir(parents=True, exist_ok=True)
    f0s = read_f0(units_csv)
    # `nper` is last on purpose: estimate_cpu_h (run_pn_sweep.sh) sums column 8, and the
    # reduction driver needs the spacing each corner was GENERATED at -- the impulse
    # instants are baked into that corner's PWL sources, so reducing it against any other
    # nper reads the steps at the wrong instants and reports nothing wrong (issue #329).
    plan = [["process", "temp_c", "f0_hz", "f0_source", "tstop_s", "n_units", "n_plateau_expected",
             "cost_cpu_h", "nper"]]
    for proc in all_process_names():
        for t in TEMPS:
            if (proc, t) in f0s:
                f0, src = f0s[(proc, t)], "oscillator-core-fleet-grid"
            elif (proc, 27) in f0s:
                f0, src = f0s[(proc, 27)], "fallback-27C"
            else:
                raise SystemExit(f"error: no carrier for {proc} at {t} C or 27 C in {units_csv}")
            n, tstop = isf(out / f"{proc}_{t}C", f0, nper, proc, t)
            cost = n * tstop * 1e12 / RATE_PS_PER_S / 3600.0
            plan.append([proc, t, f"{f0:.6e}", src, f"{tstop:.6e}", n,
                         expected_n_plateau(f0, f0, nper), f"{cost:.3f}", nper])
    with open(out / "grid-plan.csv", "w", newline="") as fh:
        csv.writer(fh, lineterminator="\n").writerows(plan)
    tot = sum(float(r[7]) for r in plan[1:])
    print(f"grid: {len(plan) - 1} corners, {sum(int(r[5]) for r in plan[1:])} units, "
          f"{tot:.1f} CPU-h at {RATE_PS_PER_S} ps/wall-s; "
          f"{sum(1 for r in plan[1:] if r[3] != 'oscillator-core-fleet-grid')} corners on fallback carrier")


def main():
    nper = int(argval("--nper", NPER))
    if "--grid" in sys.argv:
        i = sys.argv.index("--grid")
        return grid(sys.argv[i + 1], Path(sys.argv[i + 2]), nper)
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    if "--noise" in sys.argv:
        return noise(out, argval("--noise"), "--all-corners" in sys.argv)
    f0 = float(argval("--f0", F0_NOM))  # grid-design carrier; pass the MEASURED reference carrier
    n, tstop = isf(out, f0, nper, argval("--process"), argval("--temp"), "--probe" in sys.argv)
    print(f"tstop={tstop:.6e} dt={schedule(f0, nper)[0]:.6e} units={n}")


main()
