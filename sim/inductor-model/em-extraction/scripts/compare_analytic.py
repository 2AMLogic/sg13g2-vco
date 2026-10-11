#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Record the extraction-vs-analytic delta on L, Q and SRF, per geometry.

This is the single most valuable output of issue #9: it converts the analytic
screening model's *asserted* error bars into *measured* ones.

Method.  Both SPICE models are driven by the same testbench the analytic model's
own known-answer check uses -- a 1 A AC current injected at LA with LB and `sub`
grounded, so V(la) = Z(f) -- at typ (mc_rsh = mc_rsub = 1) and 27 C, on the same
frequency grid the EM extraction produced.  The EM curve is the de-embedded
2-port collapsed to the same single-ended driving-point impedance
(Z11 - Z12*Z21/Z22).  Nothing is rescaled or aligned; the three curves are
compared point for point.

The record id is reserved first (sim/lib.sh reserve_record_id, issue #225);
record files are refused if they already exist and latest_record_id.txt moves last.

Writes:
  records/<record-id>-em-vs-analytic.csv    per geometry x frequency
  records/<record-id>-delta-summary.csv     the scalar delta table
  records/<record-id>.md                    the narrative record
  records/<record-id>-env.json              tool versions / provenance
  records/<record-id>-ngspice.txt           both ngspice logs
  results/latest_record_id.txt              pointer to the newest complete record

FAILURE CONTRACT (#224).  The comparison is all-or-nothing.  Before ngspice is
started it preflights the model files and, for each of the three geometries
(p1, p13, p11), the Touchstone, port information, geometry metadata and
run_meta.json.  Each ngspice run must exit 0 and its curve must have the
expected columns and sample count, finite impedance and a strictly increasing
frequency grid; the analytic and fitted grids must match and the EM data must
cover the whole comparison band (no extrapolation).  Everything is computed
into a staging directory and the record bundle is published, with the
latest-record pointer last, only after every geometry succeeded.  A failure
exits nonzero, leaves earlier records and the pointer untouched and writes the
ngspice output (if any) to run_log/compare-failure-<record-id>.txt.  Publication
is per-file atomic renames, not a crash-atomic multi-file transaction (see
emlib.Stage and the README).

Undefined derived quantities are NOT errors: an SRF with no Im(Z) zero crossing
below FMAX is NaN ("none < 30 GHz") and its delta is NaN.  Invalid raw data are
errors.
"""

import argparse
import csv
import datetime
import json
import os
import platform
import re
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import emlib  # noqa: E402

GEOMS = [
    ("p1", 8.22, 3.29, 47.65, 1),
    ("p13", 6.10, 3.29, 110.11, 5),
    ("p11", 8.22, 3.74, 141.975, 4),
]
SPOT_F = [1e9, 2e9, 5e9, 10e9, 20e9]
FMIN, FMAX, DF = 1e8, 3e10, 5e7
RUN_META_KEYS = ("solver", "settings", "gds_sha256", "stackup_xml_sha256")


class CompareError(Exception):
    """Invalid raw data or a failed simulator run in the compare stage.

    `diagnostic` optionally carries raw simulator output to retain.
    """

    def __init__(self, msg, diagnostic=None):
        super().__init__(msg)
        self.diagnostic = diagnostic


def run_ngspice(model_lib, workdir):
    """Return f, {geom: Z(f)} for a `.subckt inductor` SPICE library."""
    npts = int(round((FMAX - FMIN) / DF)) + 1
    curve = os.path.join(workdir, "curve.csv")
    lines = [
        "* tb_em_vs_analytic -- driving-point Z of .subckt inductor, LB and sub grounded",
        '.include "%s"' % model_lib,
        ".temp 27",
    ]
    for name, w, s, d, n in GEOMS:
        lines += [
            "I%s 0 l%s dc 0 ac 1" % (name, name),
            "Ld%s l%s 0 1" % (name, name),
            "XL_%s l%s 0 0 inductor w=%gu s=%gu d=%gu nr_r=%d mc_rsh=1.0 mc_rsub=1.0"
            % (name, name, w, s, d, n),
        ]
    lines += [
        ".control",
        "set wr_singlescale",
        "set wr_vecnames",
        "ac lin %d %g %g" % (npts, FMIN, FMAX),
    ]
    vecs = []
    for name, *_ in GEOMS:
        lines += [
            "let zr_%s = real(v(l%s))" % (name, name),
            "let zi_%s = imag(v(l%s))" % (name, name),
        ]
        vecs += ["zr_%s" % name, "zi_%s" % name]
    lines += ["wrdata %s %s" % (curve, " ".join(vecs)), ".endc", ".end"]

    deck = os.path.join(workdir, "tb.spice")
    with open(deck, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    with open(os.path.join(workdir, ".spiceinit"), "w") as fh:
        fh.write("set ngbehavior=hsa\nset skywaterpdk\n")
    try:
        r = subprocess.run(
            ["ngspice", "-b", deck], cwd=workdir, capture_output=True, text=True
        )
    except OSError as e:
        raise CompareError("cannot run ngspice for %s: %s" % (model_lib, e))
    log = "$ ngspice -b (exit %s) model %s\n%s%s" % (r.returncode, model_lib, r.stdout, r.stderr)
    if r.returncode != 0:
        raise CompareError(
            "ngspice exited with status %s for %s (a curve file, if any, is ignored)"
            % (r.returncode, model_lib), log)
    if not os.path.isfile(curve):
        raise CompareError("ngspice produced no curve file for %s" % model_lib, log)
    f, out = parse_curve(curve, npts, model_lib)
    return f, out, deck, log


def parse_curve(curve, npts, label):
    """Validate and split an ngspice wrdata file into (f, {geom: Z(f)})."""
    def bad(why):
        return CompareError("invalid ngspice curve for %s: %s" % (label, why))

    try:
        a = np.genfromtxt(curve, names=True)
    except Exception as e:  # noqa: BLE001 - any parse failure is an invalid curve
        raise bad("unparseable (%s: %s)" % (type(e).__name__, e))
    names = a.dtype.names or ()
    need = ["zr_%s" % g[0] for g in GEOMS] + ["zi_%s" % g[0] for g in GEOMS]
    missing = [n for n in need if n not in names]
    if len(names) < 1 or missing:
        raise bad("missing column(s) %s" % ", ".join(missing or ["frequency"]))
    a = np.atleast_1d(a)
    if len(a) != npts:
        raise bad("expected %d samples, got %d" % (npts, len(a)))
    f = np.asarray(a[names[0]], dtype=float)
    if not np.all(np.isfinite(f)) or not np.all(np.diff(f) > 0):
        raise bad("frequency grid is non-finite or not strictly increasing")
    if not (np.isclose(f[0], FMIN, rtol=1e-6) and np.isclose(f[-1], FMAX, rtol=1e-6)):
        raise bad("frequency grid %g..%g Hz is not the requested %g..%g Hz"
                  % (f[0], f[-1], FMIN, FMAX))
    out = {}
    for name, *_ in GEOMS:
        zr, zi = (np.asarray(a["%s_%s" % (k, name)], dtype=float) for k in ("zr", "zi"))
        if not (np.all(np.isfinite(zr)) and np.all(np.isfinite(zi))):
            raise bad("non-finite impedance for geometry %s" % name)
        out[name] = zr + 1j * zi
    return f, out


# --- evidence ownership (issue #225) ----------------------------------------
# Record ids come from the shared sim/lib.sh reserve_record_id (exclusive mkdir
# of <em dir>/corners/<id>, which also rejects ids already used by historical
# flat records/<id>*), so concurrent or same-second runs at one commit never
# share a namespace.  A reservation is never released: a failed run keeps its
# id.  Staging refuses any record file that already exists (_stage_new), so even
# a broken reservation cannot replace existing evidence.
LIB_SH = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "lib.sh"))
RECORD_ID_RE = re.compile(r"^[0-9]{8}-[0-9]{6}-[0-9A-Za-z]+-[0-9a-f]+$")


class ReservationError(RuntimeError):
    pass


def reserve_record_id(root):
    """Reserve and return a record id under the experiment dir `root`.
    Creates only <root>/corners/<id>; no record output is opened."""
    r = subprocess.run(
        ["bash", "-c", 'source "$1" && reserve_record_id "$2" "$3"', "_",
         LIB_SH, root, root],
        capture_output=True, text=True,
    )
    rid = r.stdout.strip()
    if r.returncode != 0 or not RECORD_ID_RE.match(rid):
        raise ReservationError(
            "record id reservation failed under %s (rc=%d): %s"
            % (root, r.returncode, r.stderr.strip() or rid or "no id printed"))
    return rid


def spot(f, y, f0):
    return emlib.at(f, y, f0)


def _read_json(path, what):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError) as e:
        raise emlib.InputError("%s: %s: %s: %s" % (what, path, type(e).__name__, e))


def preflight(root, res, analytic, fitted):
    """Check every input the comparison consumes; return the loaded inputs.

    Raises emlib.InputError listing every problem found (one per line).
    """
    problems = []
    for label, path in (("analytic model", analytic), ("fitted model", fitted)):
        if not os.path.isfile(path) or os.path.getsize(path) == 0:
            problems.append("%s: %s: missing or empty" % (label, path))
        else:
            with open(path, errors="replace") as fh:
                if ".subckt inductor" not in fh.read().lower():
                    problems.append("%s: %s: no `.subckt inductor`" % (label, path))
    geoms = {}
    for name, *_ in GEOMS:
        try:
            inp = emlib.load_geometry_inputs(root, name)
            rm = os.path.join(res, "inductor_%s" % name, "run_meta.json")
            if not os.path.isfile(rm):
                raise emlib.InputError("geometry %s: %s: missing" % (name, rm))
            meta = _read_json(rm, "geometry %s run metadata" % name)
            absent = [k for k in RUN_META_KEYS if not isinstance(meta, dict) or k not in meta]
            if absent:
                raise emlib.InputError(
                    "geometry %s: %s: missing key(s) %s" % (name, rm, ", ".join(absent)))
            inp["meta"] = meta
            fe = inp["f"]
            if fe[0] > FMIN * (1 + 1e-9) or fe[-1] < FMAX * (1 - 1e-9):
                raise emlib.InputError(
                    "geometry %s: EM data span %.4g..%.4g Hz but the comparison band is "
                    "%.4g..%.4g Hz; refusing to extrapolate" % (name, fe[0], fe[-1], FMIN, FMAX))
            geoms[name] = inp
        except emlib.InputError as e:
            problems.append(str(e))
    fitj = os.path.join(root, "fit", "fit_parameters.json")
    fits = {}
    if os.path.isfile(fitj):
        try:
            fits = _read_json(fitj, "fit parameters")
            if not isinstance(fits, dict):
                raise emlib.InputError("fit parameters: %s: not a JSON object" % fitj)
        except emlib.InputError as e:
            problems.append(str(e))
    conv = os.path.join(res, "convergence.csv")
    convrows = []
    if os.path.isfile(conv):
        try:
            with open(conv) as fh:
                convrows = list(csv.DictReader(fh))
        except (OSError, csv.Error, UnicodeDecodeError) as e:
            problems.append("convergence: %s: %s: %s" % (conv, type(e).__name__, e))
    if problems:
        raise emlib.InputError(
            "compare needs all %d geometries (%s) and both models; nothing was published:\n  %s"
            % (len(GEOMS), " ".join(g[0] for g in GEOMS), "\n  ".join(problems)))
    return geoms, fits, convrows


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--analytic", required=True)
    ap.add_argument("--fitted", required=True)
    args = ap.parse_args(argv)
    root = args.dir
    try:
        return run(root, args.analytic, args.fitted)
    except (emlib.InputError, emlib.PublishError, CompareError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 1


def run(root, analytic, fitted):
    res = os.path.join(root, "results")
    recdir = os.path.join(root, "records")
    # Inputs first (#224): a bad input tree is rejected before anything is reserved.
    geoms, fits, convrows = preflight(root, res, analytic, fitted)

    # Ownership next (#225): nothing under records/ is created or opened before this.
    try:
        record_id = reserve_record_id(root)
    except ReservationError as e:
        print("compare_analytic: %s; nothing written" % e, file=sys.stderr)
        return 1
    os.makedirs(recdir, exist_ok=True)

    stage = emlib.Stage(root, "compare")
    try:
        _compute(root, res, recdir, record_id, analytic, fitted, geoms, fits, convrows, stage)
    except BaseException:
        stage.discard()
        raise
    stage.publish()
    print("record", record_id)
    return 0


def _stage_new(stage, dest):
    """Stage a new record file; refuse to replace existing evidence (#225).

    Publication replaces destinations, so exclusivity is checked here.  The
    mutable latest-record pointer is staged with `stage.add` directly.
    """
    if os.path.lexists(dest):
        raise CompareError("record file already exists, refusing to replace it: %s" % dest)
    return stage.add(dest)


def _retain_diagnostic(root, record_id, text):
    """Keep failure output outside records/ (which holds only complete records)."""
    d = os.path.join(root, "run_log")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "compare-failure-%s.txt" % record_id)
    with open(path, "x") as fh:
        fh.write(text)
    print("failure diagnostics kept in %s" % path, file=sys.stderr)


def _ngspice_pair(root, record_id, analytic, fitted):
    logs = []
    try:
        with tempfile.TemporaryDirectory() as wd:
            res = []
            for tag, lib in (("a", analytic), ("f", fitted)):
                sub = os.path.join(wd, tag)
                os.makedirs(sub)
                try:
                    res.append(run_ngspice(lib, sub))
                except CompareError as e:
                    if e.diagnostic:
                        logs.append(e.diagnostic)
                    raise
                logs.append(res[-1][3])
            (f_ana, Z_ana, _, log_a), (f_fit, Z_fit, _, log_f) = res
    except CompareError as e:
        _retain_diagnostic(root, record_id, "%s\n\n%s\n" % (e, "\n".join(logs)))
        raise
    if f_ana.shape != f_fit.shape or not np.allclose(f_ana, f_fit, rtol=1e-9, atol=0):
        _retain_diagnostic(root, record_id, "analytic/fitted grids differ\n\n" + "\n".join(logs))
        raise CompareError("analytic and fitted frequency grids differ; refusing to compare by position")
    return f_ana, Z_ana, Z_fit, log_a, log_f


def _finite(label, *vals):
    for v in vals:
        if not np.all(np.isfinite(v)):
            raise CompareError("%s: derived quantity is non-finite (invalid data, not an SRF-style undefined)" % label)


def _compute(root, res, recdir, record_id, analytic, fitted, geoms, fits, convrows, stage):
    f, Z_ana, Z_fit, log_a, log_f = _ngspice_pair(root, record_id, analytic, fitted)
    with open(_stage_new(stage, os.path.join(recdir, "%s-ngspice.txt" % record_id)), "w") as fh:
        fh.write("=== analytic model ===\n" + log_a + "\n=== EM-fitted model ===\n" + log_f)

    rows = []
    summary = []
    for name, w, s, d, n in GEOMS:
        inp = geoms[name]
        fe, z0 = inp["f"], inp["z0"]
        Zd = emlib.deembed_series_L(fe, emlib.s2z(inp["S"], z0), emlib.port_inductances(inp["pinfo"]))
        zse = emlib.z_single_ended(Zd)
        _finite("geometry %s EM single-ended impedance" % name, zse)
        # put everything on the ngspice grid (coverage was verified in preflight)
        zem = np.interp(f, fe, zse.real) + 1j * np.interp(f, fe, zse.imag)
        za, zf = Z_ana[name], Z_fit[name]

        Lem, Qem = emlib.lq(f, zem)
        La, Qa = emlib.lq(f, za)
        Lf, Qf = emlib.lq(f, zf)
        _finite("geometry %s L/Q" % name, Lem, La, Lf)
        for i in range(len(f)):
            rows.append(
                [name, "%.10g" % f[i]]
                + ["%.6g" % v for v in (Lem[i], La[i], Lf[i], Qem[i], Qa[i], Qf[i],
                                        zem[i].real, za[i].real, zf[i].real,
                                        zem[i].imag, za[i].imag, zf[i].imag)]
            )

        # SRF may legitimately be undefined (no crossing): NaN, kept as such.
        srf_em, srf_a, srf_f = (emlib.srf(f, z) for z in (zem, za, zf))
        row = {
            "geometry": name, "w_um": w, "s_um": s, "d_um": d, "nr_r": n,
            "srf_em_hz": srf_em, "srf_analytic_hz": srf_a, "srf_fitted_hz": srf_f,
            "d_srf_analytic_vs_em_pct": 100 * (srf_a - srf_em) / srf_em if np.isfinite(srf_em) else float("nan"),
        }
        for f0 in SPOT_F:
            g = "%dg" % int(round(f0 / 1e9))
            le, la_, lf = (spot(f, x, f0) for x in (Lem, La, Lf))
            qe, qa, qf = (spot(f, x, f0) for x in (Qem, Qa, Qf))
            with np.errstate(divide="ignore", invalid="ignore"):
                dl_a, dl_f = 100 * (la_ - le) / le, 100 * (lf - le) / le
                dq_a, dq_f = 100 * (qa - qe) / qe, 100 * (qf - qe) / qe
            _finite("geometry %s spot %s" % (name, g), le, la_, lf, qe, qa, qf,
                    dl_a, dl_f, dq_a, dq_f)
            row["l_em_%s_h" % g] = le
            row["l_analytic_%s_h" % g] = la_
            row["l_fitted_%s_h" % g] = lf
            row["d_l_analytic_vs_em_%s_pct" % g] = dl_a
            row["d_l_fitted_vs_em_%s_pct" % g] = dl_f
            row["q_em_%s" % g] = qe
            row["q_analytic_%s" % g] = qa
            row["q_fitted_%s" % g] = qf
            row["d_q_analytic_vs_em_%s_pct" % g] = dq_a
            row["d_q_fitted_vs_em_%s_pct" % g] = dq_f
        summary.append(row)
        print(
            "%-4s  L(1G) EM %8.4g nH vs analytic %8.4g nH (%+6.1f %%) | "
            "Q(10G) EM %6.2f vs analytic %6.2f (%+6.1f %%) | SRF EM %s"
            % (
                name, row["l_em_1g_h"] * 1e9, row["l_analytic_1g_h"] * 1e9,
                row["d_l_analytic_vs_em_1g_pct"],
                row["q_em_10g"], row["q_analytic_10g"], row["d_q_analytic_vs_em_10g_pct"],
                ("%.2f GHz" % (srf_em / 1e9)) if np.isfinite(srf_em) else "none <30 GHz",
            )
        )

    with open(_stage_new(stage, os.path.join(recdir, "%s-em-vs-analytic.csv" % record_id)), "w", newline="") as fh:
        wcsv = csv.writer(fh)
        wcsv.writerow(
            ["geometry", "f_hz", "l_em_h", "l_analytic_h", "l_fitted_h",
             "q_em", "q_analytic", "q_fitted",
             "re_z_em", "re_z_analytic", "re_z_fitted",
             "im_z_em", "im_z_analytic", "im_z_fitted"]
        )
        wcsv.writerows(rows)

    keys = list(summary[0].keys())
    with open(_stage_new(stage, os.path.join(recdir, "%s-delta-summary.csv" % record_id)), "w", newline="") as fh:
        wcsv = csv.DictWriter(fh, fieldnames=keys)
        wcsv.writeheader()
        for r in summary:
            wcsv.writerow({k: ("%.6g" % v if isinstance(v, float) else v) for k, v in r.items()})

    try:
        ngv = subprocess.run(["ngspice", "--version"], capture_output=True, text=True).stdout.splitlines()[1:2]
    except OSError:
        ngv = []
    env = {
        "record_id": record_id,
        "generated_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "host": {"hostname": platform.node(), "platform": platform.platform()},
        "ngspice_version": ngv,
        "python": sys.version.split()[0],
        "numpy": np.__version__,
        "models": {
            "analytic": {"path": os.path.relpath(analytic, root), "sha256": emlib.sha256(analytic)},
            "em_fitted": {"path": os.path.relpath(fitted, root), "sha256": emlib.sha256(fitted)},
        },
        "em_runs": {},
    }
    for name, *_ in GEOMS:
        m = geoms[name]["meta"]
        env["em_runs"][name] = {
            "solver": m["solver"], "settings": m["settings"],
            "gds_sha256": m["gds_sha256"],
            "stackup_xml_sha256": m["stackup_xml_sha256"],
            "wall_seconds": m.get("wall_seconds"),
            "host": m.get("host"),
        }
    with open(_stage_new(stage, os.path.join(recdir, "%s-env.json" % record_id)), "w") as fh:
        json.dump(env, fh, indent=2, sort_keys=True)
        fh.write("\n")

    write_markdown(
        _stage_new(stage, os.path.join(recdir, "%s.md" % record_id)), record_id, summary, fits, convrows, env
    )

    # The pointer is staged last, so it is also published last (Stage.publish
    # replaces it by atomic rename; it is the one mutable file in the bundle).
    with open(stage.add(os.path.join(res, "latest_record_id.txt")), "w") as fh:
        fh.write(record_id + "\n")


def _pct(x):
    return "n/a" if not np.isfinite(x) else "%+.1f %%" % x


def _ghz(x):
    return "none < 30 GHz" if not np.isfinite(x) else "%.2f GHz" % (x / 1e9)


def write_markdown(path, record_id, summary, fits, convrows, env):
    L = []
    A = L.append
    A("# Record `%s` — openEMS extraction of the SG13G2 spiral-inductor PCell" % record_id)
    A("")
    A("Generated by `sim/inductor-model/em-extraction/run_extraction.sh`. "
      "Append-only, per [`../../../README.md`](../../../README.md).")
    A("")
    A("## Method")
    A("")
    A("| | |")
    A("|---|---|")
    A("| Solver | `%s` |" % env["em_runs"].get("p1", {}).get("solver", {}).get("version_banner", "?"))
    A("| Engine | FDTD, time domain, Gaussian pulse, one run per excited port |")
    A("| Geometry | the PDK's own KLayout PCell `inductor2` (library `SG13_dev`), instantiated headlessly |")
    A("| Stack | IHP's own `libs.tech/openems/openems_ihp_sg13g2/workflow/SG13G2.xml`, sha256 `%s` |"
      % env["em_runs"].get("p1", {}).get("stackup_xml_sha256", "?")[:16])
    A("| Ports | 2 lumped z-ports (LA, LB) to a local SUBGND patch = the subcircuit's `sub` node |")
    A("| De-embedding | negative series L per port, Terman flat-ribbon, per IHP's own `scripts/deembed_openEMS.py` method |")
    s = env["em_runs"].get("p1", {}).get("settings", {})
    A("| Band | 0 .. %g GHz, %s points |" % (s.get("fstop", 0) / 1e9, s.get("numfreq", "?")))
    A("| Mesh | `refined_cellsize` %s um, `cells_per_wavelength` %s |"
      % (s.get("refined_cellsize"), s.get("cells_per_wavelength")))
    A("| Domain | GDS bbox + %s um margin, %s boundaries |"
      % (s.get("margin"), "/".join(sorted(set(s.get("Boundaries", []))))))
    A("| End criterion | residual energy %s dB |" % s.get("energy_limit"))
    A("| Host | `%s`, %s threads |"
      % (env["host"]["hostname"], s.get("numThreads", "auto")))
    A("")
    A("Process point: **one** — the typ. conductivities shipped in IHP's EM stackup "
      "(sigma_TopMetal2 = 3.03e7 S/m = 11 mOhm/sq; sigma_substrate = 2 S/m = 50 Ohm*cm), "
      "at one temperature. This is not a PVT extraction and nothing here should be read as one.")
    A("")
    A("## Extraction vs. the analytic screening model")
    A("")
    A("Both curves are the same driving-point impedance: 1 A AC into LA with LB "
      "and `sub` grounded, typ, 27 C. `d` = (analytic - EM) / EM.")
    A("")
    A("| Geometry | L(1 GHz) EM | L(1 GHz) analytic | dL | Q(1 GHz) EM | Q(1 GHz) analytic | dQ | Q(10 GHz) EM | Q(10 GHz) analytic | dQ | SRF EM | SRF analytic | dSRF |")
    A("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in summary:
        A("| `%s` (%d turn%s) | %.4g nH | %.4g nH | %s | %.3g | %.3g | %s | %.3g | %.3g | %s | %s | %s | %s |"
          % (r["geometry"], r["nr_r"], "" if r["nr_r"] == 1 else "s",
             r["l_em_1g_h"] * 1e9, r["l_analytic_1g_h"] * 1e9, _pct(r["d_l_analytic_vs_em_1g_pct"]),
             r["q_em_1g"], r["q_analytic_1g"], _pct(r["d_q_analytic_vs_em_1g_pct"]),
             r["q_em_10g"], r["q_analytic_10g"], _pct(r["d_q_analytic_vs_em_10g_pct"]),
             _ghz(r["srf_em_hz"]), _ghz(r["srf_analytic_hz"]),
             _pct(r["d_srf_analytic_vs_em_pct"])))
    A("")
    A("## Fitted lumped model")
    A("")
    A("`../../sg13g2_inductor_em.spice`, same 2-pi topology as the analytic model "
      "so every element is directly comparable. Ratios below are fitted / analytic.")
    A("")
    if fits:
        el = ("Rser", "Rlad", "L1", "Ltot", "Cs", "Cox", "Rsub", "Csub")
        A("| Geometry | " + " | ".join(el) + " |")
        A("|---" * (len(el) + 1) + "|")
        for g in ("p1", "p13", "p11"):
            if g not in fits:
                continue
            rr = fits[g]["ratio_fitted_over_analytic"]
            A("| `%s` | " % g + " | ".join("%.3g" % rr[k] for k in el) + " |")
        A("")
        A("### Fit residual")
        A("")
        A("| Geometry | fit band | rms \\|dZ\\|/\\|Z\\| | max \\|dZ\\|/\\|Z\\| | rms dL | rms dQ | SRF fitted vs EM |")
        A("|---|---|---|---|---|---|---|")
        for g in ("p1", "p13", "p11"):
            if g not in fits:
                continue
            e = fits[g]
            r = e["residual"]["fit_band"]
            sf, se = e["srf_fitted_hz"], e["srf_em_hz"]
            A("| `%s` | %s GHz | %.2f %% | %.2f %% | %.2f %% | %.2f %% | %s |"
              % (g, r["band_ghz"], r["rms_rel_err_zse_pct"], r["max_rel_err_zse_pct"],
                 r["rms_rel_err_L_pct"], r["rms_rel_err_Q_pct"],
                 ("%s vs %s (%s)" % (_ghz(sf), _ghz(se), _pct(100 * (sf - se) / se)))
                 if np.isfinite(se) else "no SRF in band"))
        A("")
    if convrows:
        A("## Mesh and boundary convergence")
        A("")
        A("One-variable-at-a-time on `p1`, against the baseline settings above.")
        A("")
        A("| Variant | cellsize | margin | dL(1 GHz) | dQ(1 GHz) | dQ(10 GHz) | wall s |")
        A("|---|---|---|---|---|---|---|")
        for r in convrows:
            A("| `%s` | %s um | %s um | %s %% | %s %% | %s %% | %s |"
              % (r["variant"], r["refined_cellsize_um"], r["margin_um"],
                 r.get("d_l_se_1g_pct", "0"), r.get("d_q_se_1g_pct", "0"),
                 r.get("d_q_se_10g_pct", "0"), r.get("wall_seconds", "")))
        A("")
    A("## Provenance")
    A("")
    A("```json")
    A(json.dumps(env, indent=2, sort_keys=True))
    A("```")
    with open(path, "x") as fh:
        fh.write("\n".join(L) + "\n")


if __name__ == "__main__":
    sys.exit(main())
