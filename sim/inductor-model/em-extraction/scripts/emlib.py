# SPDX-License-Identifier: Apache-2.0
"""Shared post-processing for the openEMS spiral-inductor extraction.

Touchstone I/O, S/Z/Y conversion, lumped-port de-embedding, and the L/Q/SRF
extraction convention.  Deliberately depends only on numpy, so the evidence in
../results/ can be re-derived by a reader who has no EM solver installed.

THE EXTRACTION CONVENTION, stated once
--------------------------------------
The EM model is a 2-port: port 1 = terminal LA, port 2 = terminal LB, both
referenced to the local substrate ground patch (the subcircuit's `sub` node).
Two impedances are derived from it and both are recorded:

  Z_se   = Z11 - Z12*Z21/Z22    driving-point impedance at LA with LB and sub
                                grounded.  This is *exactly* the quantity
                                ../testbench/tb_inductor_model_check.spice.tmpl
                                measures on the analytic model
                                (`XL lp 0 0 inductor`), so it is the one the
                                extraction-vs-analytic comparison uses.

  Z_diff = Z11 - Z12 - Z21 + Z22   differential impedance across LA/LB.  This is
                                what an LC-VCO tank actually sees; recorded
                                alongside because the two differ materially
                                once the substrate branch matters.

From either:  L = Im(Z)/omega,  Q = Im(Z)/Re(Z),  SRF = lowest frequency where
Im(Z) crosses zero downwards (linear interpolation between grid points).
Above SRF the reported L is not an inductance; the CSVs carry the SRF column so
a reader can see where that happens.
"""

import hashlib
import json
import math
import os
import shutil
import tempfile

import numpy as np


# --------------------------------------------------------------------- hashing
def sha256(path):
    """Hex-digest sha256 of a file, read in chunks (no whole-file read)."""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ----------------------------------------------------------------- touchstone
def read_snp(path):
    """Read a Touchstone file written by gds2openEMS (Hz / RI / R z0).

    Returns (f, S, z0) with S of shape (nfreq, n, n).
    """
    fmt = None
    z0 = 50.0
    rows = []
    with open(path) as fh:
        for line in fh:
            line = line.split("!")[0].strip()
            if not line:
                continue
            if line.startswith("#"):
                tok = line[1:].split()
                # e.g. "Hz S RI R 50"
                fmt = tok[2].upper()
                if "R" in [t.upper() for t in tok]:
                    idx = [t.upper() for t in tok].index("R")
                    z0 = float(tok[idx + 1])
                unit = tok[0].upper()
                mult = {"HZ": 1.0, "KHZ": 1e3, "MHZ": 1e6, "GHZ": 1e9}[unit]
                continue
            rows.append([float(x) for x in line.split()])
    a = np.array(rows)
    f = a[:, 0] * mult
    body = a[:, 1:]
    n = int(round(np.sqrt(body.shape[1] / 2)))
    if fmt == "RI":
        c = body[:, 0::2] + 1j * body[:, 1::2]
    elif fmt == "MA":
        c = body[:, 0::2] * np.exp(1j * np.deg2rad(body[:, 1::2]))
    elif fmt == "DB":
        c = 10 ** (body[:, 0::2] / 20.0) * np.exp(1j * np.deg2rad(body[:, 1::2]))
    else:
        raise ValueError("unsupported Touchstone format %r" % fmt)
    S = c.reshape(len(f), n, n)
    if n == 2:
        # Touchstone 2-port row order is S11 S21 S12 S22.
        S = S.transpose(0, 2, 1)
    return f, S, z0


def write_snp(path, f, S, z0=50.0, comments=()):
    n = S.shape[1]
    with open(path, "w") as fh:
        for c in comments:
            fh.write("! %s\n" % c)
        fh.write("# Hz S RI R %g\n" % z0)
        Sw = S.transpose(0, 2, 1) if n == 2 else S
        for i, fi in enumerate(f):
            vals = Sw[i].reshape(-1)
            fh.write(
                "%.10g " % fi
                + " ".join("%.10g %.10g" % (v.real, v.imag) for v in vals)
                + "\n"
            )


# ------------------------------------------------------------- S <-> Z <-> Y
def s2z(S, z0=50.0):
    n = S.shape[1]
    I = np.eye(n)[None, :, :]
    return z0 * np.linalg.solve(np.transpose(I - S, (0, 2, 1)), np.transpose(I + S, (0, 2, 1))).transpose(0, 2, 1)


def z2s(Z, z0=50.0):
    n = Z.shape[1]
    I = np.eye(n)[None, :, :] * z0
    return np.linalg.solve(np.transpose(Z + I, (0, 2, 1)), np.transpose(Z - I, (0, 2, 1))).transpose(0, 2, 1)


def z2y(Z):
    return np.linalg.inv(Z)


# ------------------------------------------------------------------ de-embed
def flat_strip_inductance(length_m, width_m, thickness_m=0.0):
    """Terman's flat-ribbon self-inductance (Radio Engineers Handbook, 1945).

    The same expression IHP's own scripts/deembed_openEMS.py uses, reimplemented
    here in numpy so the de-embedding does not need scikit-rf.
    """
    wt = width_m + thickness_m
    return (
        2e-7
        * length_m
        * (np.log(2 * length_m / wt) + 0.5 + 0.2235 * wt / length_m)
    )


def port_inductances(port_info):
    """Parasitic series L built into each lumped port, in port-number order."""
    unit = port_info.get("unit", 1e-6)
    out = []
    for p in sorted(port_info["ports"], key=lambda p: p["portnumber"]):
        out.append(
            flat_strip_inductance(p["length"] * unit, p["width"] * unit, 0.0)
        )
    return np.array(out)


def deembed_series_L(f, Z, Lport):
    """Remove a series inductance at each port: Z' = Z - diag(j*omega*L_n).

    Cascading a *negative* series inductor at every port, which is what IHP's
    own de-embedding script does, is exactly this subtraction on the Z matrix.
    """
    w = 2 * np.pi * f
    Zd = Z.copy()
    for n, L in enumerate(Lport):
        Zd[:, n, n] -= 1j * w * L
    return Zd


# ----------------------------------------------------------------- L / Q / SRF
def z_single_ended(Z):
    """Z looking into port 1 with port 2 shorted to the reference (sub)."""
    return Z[:, 0, 0] - Z[:, 0, 1] * Z[:, 1, 0] / Z[:, 1, 1]


def z_differential(Z):
    return Z[:, 0, 0] - Z[:, 0, 1] - Z[:, 1, 0] + Z[:, 1, 1]


def lq(f, Z):
    w = 2 * np.pi * f
    with np.errstate(divide="ignore", invalid="ignore"):
        L = np.imag(Z) / w
        Q = np.imag(Z) / np.real(Z)
    return L, Q


def srf(f, Z):
    """Lowest frequency where Im(Z) falls through zero.  NaN if it never does."""
    im = np.imag(Z)
    ok = np.isfinite(im) & (f > 0)
    fi, im = f[ok], im[ok]
    for i in range(len(fi) - 1):
        if im[i] > 0 and im[i + 1] <= 0:
            t = im[i] / (im[i] - im[i + 1])
            return fi[i] + t * (fi[i + 1] - fi[i])
    return float("nan")


def at(f, y, f0):
    """Linear interpolation of y at f0 (complex-safe)."""
    if np.iscomplexobj(y):
        return np.interp(f0, f, y.real) + 1j * np.interp(f0, f, y.imag)
    return np.interp(f0, f, y)


# --------------------------------------------------------- the lumped topology
LADDER_M = np.arange(1, 11)  # ten sections, as in sg13g2_inductor_analytic.spice


def series_branch_Z(f, Rdc, Rlad, L1, Ltot):
    """Series branch of the 2-pi topology: Rdc + 10 x (Rlad || j w L1/m^2) + Lmain.

    Identical element-for-element to sg13g2_inductor_analytic.spice's series
    branch, so a fitted parameter can be read directly against that model's
    analytic value for the same element.
    """
    w = 2 * np.pi * np.asarray(f)
    Lm = L1 / LADDER_M**2
    Lint = Lm.sum()
    Lmain = Ltot - Lint
    Z = np.full(w.shape, Rdc + 0j)
    for Lmi in Lm:
        jwl = 1j * w * Lmi
        Z = Z + (Rlad * jwl) / (Rlad + jwl)
    return Z + 1j * w * Lmain


def y_series(f, Rdc, Rlad, L1, Ltot, Cs):
    w = 2 * np.pi * np.asarray(f)
    return 1.0 / series_branch_Z(f, Rdc, Rlad, L1, Ltot) + 1j * w * Cs


def y_shunt(f, Cox, Rsub, Csub):
    w = 2 * np.pi * np.asarray(f)
    Zsi = 1.0 / (1.0 / Rsub + 1j * w * Csub)
    return 1.0 / (1.0 / (1j * w * Cox) + Zsi)


def model_Y(f, p):
    """Full 2x2 Y of the symmetric 2-pi model from a parameter dict."""
    ys = y_series(f, p["Rdc"], p["Rlad"], p["L1"], p["Ltot"], p["Cs"])
    yh = y_shunt(f, p["Cox"], p["Rsub"], p["Csub"])
    Y = np.zeros((len(f), 2, 2), dtype=complex)
    Y[:, 0, 0] = ys + yh
    Y[:, 1, 1] = ys + yh
    Y[:, 0, 1] = -ys
    Y[:, 1, 0] = -ys
    return Y


def measured_series_shunt(Y):
    """Symmetrised series and shunt admittances of a measured 2-port."""
    ys = -(Y[:, 0, 1] + Y[:, 1, 0]) / 2.0
    yh = ((Y[:, 0, 0] + Y[:, 0, 1]) + (Y[:, 1, 1] + Y[:, 1, 0])) / 2.0
    return ys, yh



# ------------------------------------------------- input preflight + publishing
# The post and fit stages must not report success unless every geometry of the
# three-geometry study was processed, and must not leave a mixture of old and
# new derived files behind when they fail.  See README "Failure contract".
GEOMS = ["p1", "p13", "p11"]


class InputError(Exception):
    """A required extraction input is missing, empty or malformed."""


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def load_geometry_inputs(root, g):
    """Preflight and load the three inputs of geometry `g`.

    Required: results/inductor_<g>.s2p (2-port Touchstone),
    results/inductor_<g>/port_information.json (two ports with length/width)
    and gds/inductor_<g>.json (w_um, s_um, d_um, nr_r).  Raises InputError
    naming the geometry and the offending file.  Returns a dict with keys
    f, S, z0, pinfo, gj.
    """
    res = os.path.join(root, "results")
    s2p = os.path.join(res, "inductor_%s.s2p" % g)
    pjson = os.path.join(res, "inductor_%s" % g, "port_information.json")
    gjson = os.path.join(root, "gds", "inductor_%s.json" % g)

    def bad(path, why):
        return InputError("geometry %s: %s: %s" % (g, path, why))

    for path in (s2p, pjson, gjson):
        if not os.path.isfile(path):
            raise bad(path, "missing")
        if os.path.getsize(path) == 0:
            raise bad(path, "empty")
    try:
        f, S, z0 = read_snp(s2p)
    except Exception as e:  # noqa: BLE001 - any parse failure is an input error
        raise bad(s2p, "cannot parse Touchstone (%s: %s)" % (type(e).__name__, e))
    if S.ndim != 3 or S.shape[1:] != (2, 2) or len(f) < 2:
        raise bad(s2p, "expected a 2-port with >= 2 frequency points")
    if not (np.all(np.isfinite(f)) and np.all(np.isfinite(S)) and np.all(np.diff(f) > 0)):
        raise bad(s2p, "non-finite data or non-increasing frequency grid")
    if not (_num(z0) and z0 > 0):
        raise bad(s2p, "invalid reference impedance")
    try:
        with open(pjson) as fh:
            pinfo = json.load(fh)
        ports = pinfo["ports"]
        nums = sorted(p["portnumber"] for p in ports)
        if nums != [1, 2]:
            raise ValueError("ports must be numbered 1 and 2")
        for p in ports:
            if not (_num(p["length"]) and _num(p["width"]) and p["length"] > 0 and p["width"] > 0):
                raise ValueError("port length/width must be positive numbers")
        if not _num(pinfo.get("unit", 1e-6)):
            raise ValueError("unit must be a number")
    except (ValueError, KeyError, TypeError, AttributeError) as e:
        raise bad(pjson, "malformed port information (%s: %s)" % (type(e).__name__, e))
    try:
        with open(gjson) as fh:
            gj = json.load(fh)
        for k in ("w_um", "s_um", "d_um", "nr_r"):
            if not _num(gj[k]) or gj[k] <= 0:
                raise ValueError("%s must be a positive number" % k)
    except (ValueError, KeyError, TypeError) as e:
        raise bad(gjson, "malformed geometry metadata (%s: %s)" % (type(e).__name__, e))
    return {"f": f, "S": S, "z0": z0, "pinfo": pinfo, "gj": gj}


class Stage:
    """Disposable staging directory plus a publish step.

    Outputs are written under `stage.path` (mirroring nothing: `add` names the
    final destination) and copied to their destinations only by `publish()`,
    which is called after every geometry succeeded.  Publication is a
    sequence of per-file atomic renames (copy to a temp name beside the
    destination, then os.replace); it is NOT a crash-atomic multi-file
    transaction.  If publication itself fails part-way, the staging directory
    is kept and the failure message says which files were already replaced;
    re-running the stage regenerates and republishes the whole set.
    """

    def __init__(self, root, name):
        for old in os.listdir(root):  # leftovers from an interrupted publish
            if old.startswith(".stage-%s-" % name):
                shutil.rmtree(os.path.join(root, old), ignore_errors=True)
        self.path = tempfile.mkdtemp(prefix=".stage-%s-" % name, dir=root)
        self._items = []  # (staged path, destination)

    def add(self, dest, basename=None):
        """Return the staged path to write for final destination `dest`."""
        staged = os.path.join(self.path, "%02d-%s" % (len(self._items), basename or os.path.basename(dest)))
        self._items.append((staged, dest))
        return staged

    def discard(self):
        shutil.rmtree(self.path, ignore_errors=True)

    def publish(self):
        for staged, dest in self._items:
            if not os.path.isfile(staged):
                raise RuntimeError("internal error: staged output missing: %s" % staged)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
        done = []
        try:
            for staged, dest in self._items:
                tmp = "%s.tmp-%d" % (dest, os.getpid())
                try:
                    shutil.copyfile(staged, tmp)
                    os.replace(tmp, dest)
                finally:
                    if os.path.exists(tmp):
                        os.unlink(tmp)
                done.append(dest)
        except Exception as e:
            raise PublishError(
                "publication failed after replacing %d of %d file(s): %s: %s\n"
                "  already replaced: %s\n"
                "  staged set kept in %s; re-run this stage to regenerate and "
                "republish the complete set"
                % (len(done), len(self._items), type(e).__name__, e,
                   ", ".join(done) or "(none)", self.path)) from e
        self.discard()


class PublishError(Exception):
    """Publication failed part-way; the staging directory was kept."""
