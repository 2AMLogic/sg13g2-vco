"""Solver-free fixtures for the EM-extraction post/fit stages (issue #167).

Needs numpy and scipy (declared in .github/numeric-requirements.txt); no PDK,
ngspice or openEMS.  The synthetic "extraction" is generated from the
project's own lumped topology (emlib.model_Y) with the analytic element values
of the three real geometries, plus the Terman port inductance that post
de-embeds, so the known answer is the model that generated it.
"""
import importlib.util
import json
import os
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EM = os.path.join(ROOT, "sim", "inductor-model", "em-extraction")
SCRIPTS = os.path.join(EM, "scripts")

if SCRIPTS not in sys.path:
    sys.path.insert(0, SCRIPTS)
import emlib  # noqa: E402


def load(name):
    spec = importlib.util.spec_from_file_location("em_" + name, os.path.join(SCRIPTS, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


postprocess = load("postprocess")
fit_lumped = load("fit_lumped")
compare_analytic = load("compare_analytic")

# w, s, d (um), nr_r of the three PDK LVS-testcase geometries (gds/inductor_*.json)
GEOM = {
    "p1": (8.22, 3.29, 47.65, 1),
    "p13": (2.0, 2.1, 15.48, 5),
    "p11": (4.0, 2.1, 30.0, 4),
}
PORTS = {"ports": [
    {"portnumber": 1, "length": 11.2303, "width": 8.22},
    {"portnumber": 2, "length": 11.2303, "width": 8.22},
], "unit": 1e-6}
FREQ = np.linspace(0.05e9, 30e9, 160)


def true_params(g):
    w, s, d, n = GEOM[g]
    a = fit_lumped.analytic_elements(w * 1e-6, s * 1e-6, d * 1e-6, n)
    return {"Rdc": a["Rser"], "Rlad": a["Rlad"], "L1": a["L1"], "Ltot": a["Ltot"],
            "Cs": a["Cs"], "Cox": a["Cox"], "Rsub": a["Rsub"], "Csub": a["Csub"]}


def true_Z(g):
    return np.linalg.inv(emlib.model_Y(FREQ, true_params(g)))


def write_geometry(root, g):
    w, s, d, n = GEOM[g]
    os.makedirs(os.path.join(root, "gds"), exist_ok=True)
    os.makedirs(os.path.join(root, "results", "inductor_%s" % g), exist_ok=True)
    with open(os.path.join(root, "gds", "inductor_%s.json" % g), "w") as fh:
        json.dump({"geometry": g, "w_um": w, "s_um": s, "d_um": d, "nr_r": n}, fh)
    with open(os.path.join(root, "results", "inductor_%s" % g, "port_information.json"), "w") as fh:
        json.dump(PORTS, fh)
    Zraw = emlib.deembed_series_L(FREQ, true_Z(g), -emlib.port_inductances(PORTS))
    emlib.write_snp(os.path.join(root, "results", "inductor_%s.s2p" % g),
                    FREQ, emlib.z2s(Zraw, 50.0), 50.0)


def make_tree(root, omit=()):
    """Complete three-geometry input set; omit = relative paths to leave out."""
    for g in emlib.GEOMS:
        write_geometry(root, g)
    for rel in omit:
        os.unlink(os.path.join(root, rel))


def write_run_meta(root, gs=None):
    """run_meta.json (consumed by the compare stage's provenance) per geometry."""
    for g in gs or emlib.GEOMS:
        meta = {"solver": {"version_banner": "stub-solver"},
                "settings": {"fstop": 30e9, "numfreq": len(FREQ)},
                "gds_sha256": "g" * 64, "stackup_xml_sha256": "s" * 64,
                "wall_seconds": 1.0, "host": "test"}
        with open(os.path.join(root, "results", "inductor_%s" % g, "run_meta.json"), "w") as fh:
            json.dump(meta, fh)


# derived outputs of each stage, relative to the extraction root
POST_OUT = (["results/em_summary.csv"]
            + ["results/inductor_%s_%s" % (g, x) for g in emlib.GEOMS for x in ("deembedded.s2p", "lq.csv")])
FIT_OUT = (["fit/fit_parameters.json", "fit/fit_summary.csv", "model/sg13g2_inductor_em.spice"]
           + ["fit/fit_residual_%s.csv" % g for g in emlib.GEOMS])


def seed_outputs(root, rels, tag=b"PREVIOUS-RUN "):
    """Pre-populate derived outputs with sentinel bytes; return {rel: bytes}."""
    out = {}
    for rel in rels:
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        data = tag + rel.encode() + b"\n"
        with open(p, "wb") as fh:
            fh.write(data)
        out[rel] = data
    return out


def read_all(root, rels):
    out = {}
    for rel in rels:
        p = os.path.join(root, rel)
        if os.path.exists(p):
            with open(p, "rb") as fh:
                out[rel] = fh.read()
        else:
            out[rel] = None
    return out


def stray(root):
    """Staging dirs or temp files left under the root."""
    found = []
    for dp, dn, fn in os.walk(root):
        for n in dn + fn:
            if n.startswith(".stage-") or ".tmp-" in n:
                found.append(os.path.join(dp, n))
    return sorted(found)
