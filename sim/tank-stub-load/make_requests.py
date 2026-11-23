#!/usr/bin/env python3
"""make_requests.py -- build the `klt sim` AC requests for the issue #420
tank-stub A/B.

    make_requests.py <outdir> [--cp F] [--cn F]

Writes, per (variant, mos corner, Vctrl):
<outdir>/<variant>/<mos>_v<V>/{tank.spice, request.json, cell.json}.
Variants:

  nostub   the passive tank as drawn before #420 (no edge pin straps)
  stub     the same tank plus the two #420 TopMetal1 pin straps, modeled as
           node-to-substrate capacitance C_p on OUTP and C_n on OUTN

WHAT THE CIRCUIT IS.  The same surrogate passive tank as
../bn-substrate-tank/make_requests.py (post-#79 form: varactor `bn` on the
substrate): XL1/XL2 (EM-fitted inductor, inlined), XC1 (cap_cmim 3.65x3.65 um,
as in the netlist) and 16 varactor cells per side, each cell's OSDI MOS core
replaced by a lumped series R-C from the committed varactor record with the
PDK subckt's own dsubw/rsubw text (overlaid card, issue #95) around it.  Read
that directory's README before citing absolute numbers: the surrogate's f0
is ~2 % high against the full oscillator.  The A/B DELTA between the two
variants is native ngspice elements only (an ideal C per side), so the shift
this experiment measures does not inherit the surrogate's absolute error --
it inherits only the surrogate's TANK-to-FULL offset, which cancels to first
order in a small-charge perturbation and is stated as a limit in the record.

WHAT THE STUB CAPACITANCE IS.  Geometric, not extracted: issue #420's parent
(sg13g2-lc-pll, #345) recorded 0.0861 fF/um for its own 2.0 um TopMetal1
routes over substrate, and #420's straps are drawn at the same 2.0 um width
(layout/scripts/floorplan.py TANK_PIN_W), so the added capacitance per side
is that coefficient times the NEW strap length (the metal that was not there
before; the in-bbox overlap was already part of the tank):

  OUTP  y -26.0 .. -106.0  -> 80.0 um  -> C_p = 0.0861 * 80.0 = 6.888 fF
  OUTN  y -34.0 .. -106.0  -> 72.0 um  -> C_n = 0.0861 * 72.0 = 6.1992 fF

Series resistance of the strap is NOT modeled: at a conservative 1 ohm the
capacitor branch's own Q is 1/(2*pi*f*C*R) > 5000 at 4 GHz, three orders
above the loaded tank Q, so it cannot move f0 or Q at the precision claimed.
Limits stated in the record: the coefficient is the parent's geometric
estimate transferred into this block's substrate environment (no neighboring
metal within 13 um of either strap; the guard ring's Activ box is 39 um from
OUTP's strap and 14 um from OUTN's, by the floorplan RING constants), not an
extraction of THIS layout; fringing and
strap-to-ring coupling are not separated out.
"""
import argparse, importlib.util, json, math, os, sys

_ap = argparse.ArgumentParser()
_ap.add_argument("outdir")
_ap.add_argument("--cp", type=float, default=0.0861e-15 * 80.0,
                 help="OUTP stub capacitance in F (default: geometric 6.888 fF)")
_ap.add_argument("--cn", type=float, default=0.0861e-15 * 72.0,
                 help="OUTN stub capacitance in F (default: geometric 6.1992 fF)")
_args = _ap.parse_args()
for name, v in (("--cp", _args.cp), ("--cn", _args.cn)):
    if not math.isfinite(v) or v <= 0:
        sys.exit("illegal %s: need a finite positive capacitance" % name)
out = _args.outdir

_spec = importlib.util.spec_from_file_location(
    "svaricap_overlay", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "svaricap_overlay.py"))
overlay = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(overlay)
DSUBW_CARD = overlay.overlaid_card()   # raises if the inline v0.3.0 text is not the expected card
NCELLS = 16
MIM_STR = "3.65e-6"
repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# (c_5ghz_f, q_5ghz) at 27 C from the varactor record, key (mos corner, V_rec)
# -- identical table to ../bn-substrate-tank/make_requests.py (same source csv,
# same V_rec = 3.3 - Vctrl convention).  The varactor half of the tank must be
# the same surrogate as the #79 A/B so the two records can be read together.
REC = {("tt", 3.3): (1.045e-14, 44.79), ("tt", 1.8): (5.63e-15, 83.98),
       ("tt", 0.0): (5.569e-15, 84.92)}
CSV = os.path.join(repo, "sim/varactor-characterization/records/20260927-081226-f88eb89.csv")
rows = {}
for ln in open(CSV).read().splitlines()[1:]:
    f = ln.split(",")
    if f[0] == "mos" and f[1] == "small" and f[3] == "27":
        rows[(f[2], round(float(f[4]), 2))] = (float(f[8]), float(f[12]))
W5 = 2 * math.pi * 5e9
VCTRL_TO_VREC = {0.0: 3.3, 1.5: 1.8, 3.3: 0.0}
# (mos corner, Vctrl) set: tt at three Vctrl (the tuning axis); ss/ff at
# band-centre Vctrl 1.5 -- exactly ../bn-substrate-tank's set.
POINTS = [("tt", 0.0), ("tt", 1.5), ("tt", 3.3), ("ss", 1.5), ("ff", 1.5)]

IND = open(os.path.join(repo, "sim/inductor-model/sg13g2_inductor_em.spice")).read()

def deck(variant, c, r, vc):
    cells = []
    for side, node in (("P", "OUTP"), ("N", "OUTN")):
        for i in range(1, NCELLS + 1):
            # subckt pins: G W bn -- post-#79: bn on the substrate (issue #79)
            cells.append(f"XCV{side}{i} VCTRL {node} 0 svar")
    stub = ""
    if variant == "stub":
        stub = (f"* #420 pin straps: geometric node-to-substrate capacitance\n"
                f"Cstp OUTP 0 {_args.cp:.6g}\n"
                f"Cstn OUTN 0 {_args.cn:.6g}\n")
    return f"""* tank stub A/B for issue #420 -- variant {variant}: edge pin straps {'present' if variant == 'stub' else 'absent'}
* generated by sim/tank-stub-load/make_requests.py; see its docstring
* sim/inductor-model/sg13g2_inductor_em.spice, INLINED below (the batch
* backend does not stage .include targets)
{IND}
* PDK svaricap well parasitics, verbatim from sg13g2_svaricaphv_mod.lib,
* around a lumped R-C standing in for the OSDI MOS core (see make_requests.py)
* OVERLAID card (issue #95): v0.3.0 text with only vj 0.1 -> 0.3357 (IHP-Open-PDK
* PR #1102, merge 0243d867c6b7493526b141d2e4d74afa027e5b8e); v0.3.0 is NaN above ~52 C
{DSUBW_CARD}
.subckt svar G W bn
.param l=0.3e-6 w=3.74e-6 Nx=1 Ny=1
.param rsubw0=0.2596 rsubwf=0.0009212 rsubwexp=0.6952
Rcore W n1 {r:.6g}
Ccore n1 G {c:.6g}
dsubw W1 W dsubw off area = '(((Nx*0.38u)+(Nx*l))+1.11u)*(Ny*(w+0.97u))' pj = '2*((((Nx*0.38u)+(Nx*l))+1.11u)+(Ny*(w+0.97u)))'
rsubw W1 bn r = '(rsubw0/(sqrt(pow(Nx, rsubwexp))))/(w+rsubwf)'
.ends svar
VDD VDD 0 dc 3.3
VCT VCTRL 0 dc {vc}
XL1 VDD OUTP 0 inductor w=8.22e-6 s=3.74e-6 d=141.975e-6 nr_r=4 m=1
XL2 VDD OUTN 0 inductor w=8.22e-6 s=3.74e-6 d=141.975e-6 nr_r=4 m=1
XC1 OUTP OUTN cap_cmim w={MIM_STR} l={MIM_STR} m=1
{chr(10).join(cells)}
{stub}* AC probe: 1 A differential current, so v(zd) IS the differential impedance
Iac OUTN OUTP dc 0 ac 1
Ezd ZD 0 OUTP OUTN 1
Rzd ZD 0 1G
"""

def request(vc, temps=(-40, 27, 125)):
    meas = [
     ("zpk", "ohm", ".meas ac zpk MAX vm(zd) FROM=1g TO=12g"),
     ("f0", "Hz", ".meas ac f0 WHEN vp(zd)=0 FALL=1"),
     ("f_p45", "Hz", ".meas ac f_p45 WHEN vp(zd)=0.78539816 FALL=1"),
     ("f_m45", "Hz", ".meas ac f_m45 WHEN vp(zd)=-0.78539816 FALL=1"),
    ]
    return {"netlist": "tank.spice", "engine": "ngspice",
            "models": {"pdk": "ihp-sg13g2", "lib": "libs.tech/ngspice/models/cornerCAP.lib"},
            "corners": {"process": [{"name": s, "sections": [s]} for s in ("cap_typ", "cap_bcs", "cap_wcs")],
                        "temperature_c": list(temps)},
            "analysis": {"kind": "ac", "args": "lin 5501 1g 12g"},
            "measurements": [{"name": a, "unit": u, "spice": s} for a, u, s in meas],
            "options": {"timeout_s": 900, "keep_artifacts": True,
                        "ngspice_init": ["set ngbehavior=hsa"]}}

def emit(variant, mos, vc, temps):
    c, q = rows[(mos, VCTRL_TO_VREC[vc])]
    r = 1.0 / (W5 * c * q)
    d = os.path.join(out, variant, f"{mos}_v{vc}")
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "tank.spice"), "w").write(deck(variant, c, r, vc))
    json.dump(request(vc, temps), open(os.path.join(d, "request.json"), "w"), indent=2)
    json.dump({"variant": variant, "mos": mos, "vctrl": vc, "c_cell_f": c, "q5": q,
               "r_cell_ohm": r, "dsubw_overlay": {"change": "vj 0.1 -> 0.3357", "tool": "sim/tools/svaricap_overlay.py",
                                 "upstream_issue": "IHP-GmbH/IHP-Open-PDK#1098",
                                 "upstream_pull_request": "IHP-GmbH/IHP-Open-PDK#1102",
                                 "upstream_merge_commit": overlay.UPSTREAM["merge_commit"],
                                 "v030_card": overlay.V030_DSUBW_CARD, "card": DSUBW_CARD},
               "cells_per_side": NCELLS, "mim_side_um": 3.65,
               "stub": {"cp_f": _args.cp, "cn_f": _args.cn} if variant == "stub" else None,
               "source": "sim/varactor-characterization/records/20260927-081226-f88eb89.csv mos small 27C"},
              open(os.path.join(d, "cell.json"), "w"), indent=2)

for variant in ("nostub", "stub"):
    for mos, vc in POINTS:
        emit(variant, mos, vc, (-40, 27, 125))
print("ok", out)
