#!/usr/bin/env python3
"""svaricap_surrogate.py -- OSDI-free charge-based sg13_hv_svaricap surrogate (issue #179).

SCREENING ONLY -- grades no specification row.

Why: design/vco.spice instantiates 32 OSDI-backed `sg13_hv_svaricap` cells and
neither the local ngspice nor the batch fleet can load mosvar.osdi (issue #94).
sim/bn-substrate-tank/ has a one-frequency, one-bias small-signal series R-C,
which cannot represent large-signal startup.  This module emits a four-terminal
`.subckt` with the same pins as the PDK cell (G1 W G2 bn) whose MOS core is a
behavioral, charge-conserving nonlinear capacitor with a bias-dependent series
resistance, plus EXACTLY ONE native well-to-substrate branch (dsubw + rsubw).

Contract (issue #179)
---------------------
* Terminal voltage of the behavioral core:  v_gw = V(G) - V(W),
  v_rec = -v_gw = V(W) - V(G).  The committed characterization record drove the
  WELL with the gates at 0 V, so its `vctrl_v` column IS v_rec; it is used
  as-is (the axis is never reversed here).  In the oscillator G = VCTRL and the
  tank/well DC level is 3.3 V, hence v_rec = 3.3 - VCTRL at the DC point.
* C(v_rec) is the `c_5ghz_f` column of the `mos`/`small` rows of one
  (corner, temperature) series, interpolated PIECEWISE-LINEARLY in v_rec.
  Charge, not a voltage-dependent ideal capacitor:
      q(v_gw)  = integral_0^{v_gw} C(-u) du = -Qint(v_rec)
      i_core   = d q(v_gw) / dt
  Qint is the exact integral of the piecewise-linear C, i.e. piecewise
  QUADRATIC; q and C are both continuous at every knot, q(0) = 0 and
  dq/dv_gw = C(v_rec) everywhere (C > 0 so q is strictly monotonic).
* Series loss, derived pointwise from the same record row:
      Rcore(v_rec) = 1 / (2 pi 5e9 C_5GHz Q_5GHz)
  interpolated piecewise-linearly and independently of q/C, in series with the
  core on the well side.
* The record's C/Q were measured with W and bn tied, so they EXCLUDE the native
  well-to-substrate branch.  `dsubw` (overlaid card, vj = 0.3357, from
  svaricap_overlay.py) and `rsubw` are copied from the PDK subcircuit text,
  appear once in the subckt, and are NOT folded into the fitted core.
* Domain: the model is valid only for instantaneous v_rec in [0.0, 3.3] V.
  The lookup argument is clamped (and q continues linearly with the endpoint C,
  so q and C stay continuous), but that is numerical continuity only, not
  extrapolation: classify_domain() turns any excursion beyond DOMAIN_TOL_V
  (1 mV) into INVALID-OUT-OF-DOMAIN and the benches exit nonzero.
* G1 and G2 are tied inside the cell by a 1 uOhm resistor; the PDK's G1-G2
  coupling capacitor and rk are NOT modeled (the design ties G1 = G2).

Honest limits: no OSDI device noise (no complete phase-noise evidence), 5 GHz
effective C/Q only, fitted bias/temperature/corner/geometry only
(mos/small = w 3.74u / l 0.3u / Nx 1).  Pure stdlib; no simulator needed to
import or test it.
"""
import argparse
import csv
import hashlib
import math
import os
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
import svaricap_overlay as overlay  # noqa: E402

REPO = os.path.abspath(os.path.join(_HERE, "..", ".."))
DEFAULT_CSV = "sim/varactor-characterization/records/20260927-081226-f88eb89.csv"
F_EXTRACT_HZ = 5e9
V_REC_MIN = 0.0
V_REC_MAX = 3.3
DOMAIN_TOL_V = 1e-3
STATUS_OK = "OK"
STATUS_INVALID = "INVALID-OUT-OF-DOMAIN"
LABEL = "SCREENING ONLY — grades no specification row"
NOISE_NOTE = ("The behavioral surrogate omits OSDI device noise; no phase-noise "
              "result from it is complete device-noise evidence.")
PATH_NOTE = ("Issue #94 remains the only route to graded, OSDI-backed "
             "full-oscillator evidence.")
FOLLOW_ON_NOTE = ("Fleet grids, full tuning sweeps and ISF/phase-noise screening "
                  "are NOT implemented here; they are follow-on work conditional "
                  "on this smoke result.")


class SurrogateError(Exception):
    pass


# ----------------------------------------------------------------- parsing
def load_series(csv_path, device_class="mos", device_key="small"):
    """Return {(corner, temp_c): Series} for the mos/small rows of the record.

    Rejects missing columns, non-PASS rows, non-finite or non-positive C/Q,
    non-finite bias, duplicate bias points, unsorted bias points (file order
    must already be ascending within a series), fewer than 3 points per series
    and a series that does not span exactly [V_REC_MIN, V_REC_MAX].
    """
    raw = {}
    with open(csv_path, newline="") as fh:
        rd = csv.DictReader(fh)
        need = {"device_class", "device_key", "corner_label", "temp_c", "vctrl_v",
                "status", "c_5ghz_f", "q_5ghz"}
        missing = need - set(rd.fieldnames or [])
        if missing:
            raise SurrogateError("%s: missing columns %s" % (csv_path, sorted(missing)))
        for n, row in enumerate(rd, start=2):
            if row["device_class"] != device_class or row["device_key"] != device_key:
                continue
            key = (row["corner_label"], float(row["temp_c"]))
            try:
                v = float(row["vctrl_v"])
                c = float(row["c_5ghz_f"])
                q = float(row["q_5ghz"])
            except ValueError:
                raise SurrogateError("line %d %s: unparsable number" % (n, key))
            if row["status"] != "PASS":
                raise SurrogateError("line %d %s: status %r is not PASS" % (n, key, row["status"]))
            for name, x in (("vctrl_v", v), ("c_5ghz_f", c), ("q_5ghz", q)):
                if not math.isfinite(x):
                    raise SurrogateError("line %d %s: non-finite %s" % (n, key, name))
            if c <= 0 or q <= 0:
                raise SurrogateError("line %d %s: non-positive C or Q" % (n, key))
            raw.setdefault(key, []).append((v, c, q))
    if not raw:
        raise SurrogateError("%s: no %s/%s rows" % (csv_path, device_class, device_key))
    out = {}
    for key, pts in raw.items():
        out[key] = Series(key[0], key[1], pts)
    return out


class Series:
    """One (corner, temperature) fit: knots, C, R, charge integral, LOO residuals."""

    def __init__(self, corner, temp_c, pts):
        key = "%s/%gC" % (corner, temp_c)
        if len(pts) < 3:
            raise SurrogateError("%s: need >= 3 points, got %d" % (key, len(pts)))
        vs = [p[0] for p in pts]
        for a, b in zip(vs, vs[1:]):
            if b == a:
                raise SurrogateError("%s: duplicate bias point %g" % (key, a))
            if b < a:
                raise SurrogateError("%s: unsorted bias points (%g after %g)" % (key, b, a))
        if abs(vs[0] - V_REC_MIN) > 1e-9 or abs(vs[-1] - V_REC_MAX) > 1e-9:
            raise SurrogateError("%s: series spans %g..%g, not %g..%g"
                                 % (key, vs[0], vs[-1], V_REC_MIN, V_REC_MAX))
        self.corner, self.temp_c, self.key = corner, temp_c, key
        self.vs = vs
        self.cs = [p[1] for p in pts]
        self.qs = [p[2] for p in pts]
        self.rs = [1.0 / (2 * math.pi * F_EXTRACT_HZ * c * q) for c, q in zip(self.cs, self.qs)]
        # Qint at knots (exact integral of the piecewise-linear C)
        self.qk = [0.0]
        for i in range(len(vs) - 1):
            h = vs[i + 1] - vs[i]
            self.qk.append(self.qk[-1] + 0.5 * (self.cs[i] + self.cs[i + 1]) * h)

    # --- interpolation ------------------------------------------------
    def _seg(self, x):
        vs = self.vs
        if x <= vs[0]:
            return 0
        if x >= vs[-1]:
            return len(vs) - 2
        lo, hi = 0, len(vs) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if vs[mid] <= x:
                lo = mid
            else:
                hi = mid
        return lo

    @staticmethod
    def _clamp(x):
        return min(max(x, V_REC_MIN), V_REC_MAX)

    def _lin(self, ys, x):
        x = self._clamp(x)
        i = self._seg(x)
        x0, x1 = self.vs[i], self.vs[i + 1]
        return ys[i] + (ys[i + 1] - ys[i]) * (x - x0) / (x1 - x0)

    def c_at(self, v_rec):
        return self._lin(self.cs, v_rec)

    def r_at(self, v_rec):
        return self._lin(self.rs, v_rec)

    def qint(self, v_rec):
        """Integral_0^{v_rec} C(s) ds; linear continuation with the endpoint C outside."""
        if v_rec < V_REC_MIN:
            return self.cs[0] * (v_rec - V_REC_MIN)
        if v_rec > V_REC_MAX:
            return self.qk[-1] + self.cs[-1] * (v_rec - V_REC_MAX)
        i = self._seg(v_rec)
        h = self.vs[i + 1] - self.vs[i]
        d = v_rec - self.vs[i]
        slope = (self.cs[i + 1] - self.cs[i]) / h
        return self.qk[i] + self.cs[i] * d + 0.5 * slope * d * d

    def q_gw(self, v_gw):
        """Charge on the gate side, q(v_gw) = integral_0^{v_gw} C(-u) du = -Qint(-v_gw)."""
        return -self.qint(-v_gw)

    # --- leave-one-out residuals --------------------------------------
    def loo(self):
        """Predict every INTERIOR point from its two neighbours (piecewise-linear)
        and return (eps_C, eps_R): the maximum relative residuals.  Endpoints are
        never extrapolated; they are checked for exact reproduction instead."""
        eC = eR = 0.0
        for i in range(1, len(self.vs) - 1):
            t = (self.vs[i] - self.vs[i - 1]) / (self.vs[i + 1] - self.vs[i - 1])
            for ys, tag in ((self.cs, "C"), (self.rs, "R")):
                pred = ys[i - 1] + t * (ys[i + 1] - ys[i - 1])
                rel = abs(pred - ys[i]) / ys[i]
                if tag == "C":
                    eC = max(eC, rel)
                else:
                    eR = max(eR, rel)
        return eC, eR

    def tolerances(self):
        eC, eR = self.loo()
        return {"epsilon_C": eC, "epsilon_R": eR,
                "tol_dqdv": max(1e-3, 1.25 * eC),
                "tol_R": max(1e-3, 1.25 * eR)}


def known_answer_tolerances(eps_c, eps_r, quant_floor_interp_pct):
    """Fixed by issue #179 item 4; must not be widened after seeing a result."""
    return {"tol_freq": max(0.01, eps_c / 2 + quant_floor_interp_pct / 100.0),
            "tol_amp": max(0.05, eps_c + eps_r)}


# ------------------------------------------------------------------ domain
def classify_domain(vmin, vmax, tol=DOMAIN_TOL_V):
    """STATUS_OK iff both extrema are finite and inside [0, 3.3] V +/- tol."""
    if tol > 1e-3 + 1e-15:
        raise SurrogateError("domain tolerance %g exceeds the 1 mV the contract allows" % tol)
    if not (math.isfinite(vmin) and math.isfinite(vmax)):
        return STATUS_INVALID
    if vmin < V_REC_MIN - tol or vmax > V_REC_MAX + tol:
        return STATUS_INVALID
    return STATUS_OK


def vrec_from_vctrl_dc(vctrl, vdd=3.3):
    """DC operating-point map used by the oscillator: well at VDD, gate at VCTRL."""
    return vdd - vctrl


# --------------------------------------------------------- ngspice emission
def _g(x):
    return "%.12g" % x


def _clamp_expr(x):
    return "((%s<%s)?%s:((%s>%s)?%s:%s))" % (x, _g(V_REC_MIN), _g(V_REC_MIN),
                                              x, _g(V_REC_MAX), _g(V_REC_MAX), x)


def qint_expr(s, x):
    """ngspice expression for Qint(x) (nested ternary, piecewise quadratic)."""
    n = len(s.vs)
    parts = []
    for i in range(n - 1):
        h = s.vs[i + 1] - s.vs[i]
        slope = (s.cs[i + 1] - s.cs[i]) / h
        d = "(%s-%s)" % (x, _g(s.vs[i]))
        parts.append("%s+%s*%s+%s*%s*%s" % (_g(s.qk[i]), _g(s.cs[i]), d, _g(0.5 * slope), d, d))
    expr = "(%s)" % parts[-1]
    for i in range(n - 2, 0, -1):
        expr = "((%s<%s)?(%s):%s)" % (x, _g(s.vs[i]), parts[i - 1], expr)
    return ("((%s<%s)?(%s*%s):((%s>%s)?(%s+%s*(%s-%s)):%s))"
            % (x, _g(V_REC_MIN), _g(s.cs[0]), x,
               x, _g(V_REC_MAX), _g(s.qk[-1]), _g(s.cs[-1]), x, _g(V_REC_MAX), expr))


def r_expr(s, x):
    """ngspice expression for Rcore(x): clamped piecewise-linear."""
    xc = _clamp_expr(x)
    n = len(s.vs)
    parts = []
    for i in range(n - 1):
        slope = (s.rs[i + 1] - s.rs[i]) / (s.vs[i + 1] - s.vs[i])
        parts.append("%s+%s*(%s-%s)" % (_g(s.rs[i]), _g(slope), xc, _g(s.vs[i])))
    expr = "(%s)" % parts[-1]
    for i in range(n - 2, 0, -1):
        expr = "((%s<%s)?(%s):%s)" % (xc, _g(s.vs[i]), parts[i - 1], expr)
    return expr


def render_subckt(s, name="sg13_hv_svaricap_sur"):
    """The four-terminal surrogate cell, ngspice text.  Core node `nc`: the
    behavioral core sits between `nc` and G1; Rcore sits between W and `nc`."""
    x = "v(nc,G1)"     # = V(W side) - V(G) = v_rec at the core
    return "\n".join([
        "* SCREENING ONLY — grades no specification row",
        "* %s: OSDI-free charge-based replacement for the PDK sg13_hv_svaricap" % name,
        "* fit series %s (mos/small, c_5ghz_f and q_5ghz columns); generated by" % s.key,
        "* sim/tools/svaricap_surrogate.py -- see its docstring for the contract.",
        "* v_gw = V(G)-V(W); v_rec = -v_gw = V(W)-V(G); core current = d q(v_gw)/dt;",
        "* q(v_gw) = -Qint(v_rec), Qint = exact integral of piecewise-linear C(v_rec).",
        ".subckt %s G1 W G2 bn" % name,
        ".param l=0.3e-6 w=3.74e-6 Nx=1 Ny=1",
        ".param rsubw0=0.2596 rsubwf=0.0009212 rsubwexp=0.6952",
        "Rg12 G2 G1 1u",
        "Rcore W nc r='%s'" % r_expr(s, x),
        "Ccore G1 nc q='-(%s)'" % qint_expr(s, x),
        # native junction branch: verbatim from the PDK subcircuit text
        "dsubw W1 W dsubw off area = '(((Nx*0.38u)+(Nx*l))+1.11u)*(Ny*(w+0.97u))' "
        "pj = '2*((((Nx*0.38u)+(Nx*l))+1.11u)+(Ny*(w+0.97u)))'",
        "rsubw W1 bn r = '(rsubw0/(sqrt(pow(Nx, rsubwexp))))/(w+rsubwf)'",
        ".ends %s" % name,
        ""])


def render_model_card():
    return overlay.overlaid_card()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest()


def source_provenance(csv_rel=DEFAULT_CSV):
    path = os.path.join(REPO, csv_rel)
    try:
        commit = subprocess.run(["git", "-C", REPO, "log", "-1", "--format=%H", "--", csv_rel],
                                capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        commit = "unavailable"
    return {"csv": csv_rel, "csv_sha256": sha256_file(path),
            "csv_commit": commit or "unavailable"}


# ------------------------------------------------------ oscillator rewriting
def surrogate_vco_body(vco_text, sub_name, topology):
    """Rewrite the device section of design/vco.spice for the surrogate.

    topology 'corrected' keeps bn on 0 (as in design/vco.spice); 'pre79' ties
    each cell's bn to its own well W (the pre-#79 schematic).  Returns the
    device section only (everything before '**** begin user architecture
    code'), with the 32 sg13_hv_svaricap instances renamed to the surrogate.
    """
    if topology not in ("corrected", "pre79"):
        raise SurrogateError("unknown topology %r" % topology)
    out, n = [], 0
    for line in vco_text.splitlines():
        if line.startswith("**** begin user architecture code"):
            break
        if line.startswith(".save"):
            continue
        tok = line.split()
        if len(tok) >= 6 and tok[0].startswith("XCV") and tok[5] == "sg13_hv_svaricap":
            g1, w, g2, bn = tok[1:5]
            if g1 != g2:
                raise SurrogateError("%s: G1 != G2 (%s, %s); the design ties them" % (tok[0], g1, g2))
            if bn != "0":
                raise SurrogateError("%s: design/vco.spice expected bn on 0, found %s" % (tok[0], bn))
            if topology == "pre79":
                bn = w
            tok = [tok[0], g1, w, g2, bn, sub_name] + tok[6:]
            line = " ".join(tok)
            n += 1
        out.append(line)
    if n != 32:
        raise SurrogateError("expected 32 sg13_hv_svaricap cells in design/vco.spice, found %d" % n)
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------- CLI
def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("subckt", help="print the surrogate .subckt and the dsubw model card")
    p.add_argument("--csv", default=DEFAULT_CSV)
    p.add_argument("--corner", default="tt")
    p.add_argument("--temp", type=float, default=27.0)
    p = sub.add_parser("tolerances", help="print the predeclared leave-one-out tolerances")
    p.add_argument("--csv", default=DEFAULT_CSV)
    p = sub.add_parser("check-domain", help="classify measured v_rec extrema; nonzero exit if invalid")
    p.add_argument("vmin", type=float)
    p.add_argument("vmax", type=float)
    a = ap.parse_args(argv)
    if a.cmd == "check-domain":
        st = classify_domain(a.vmin, a.vmax)
        print(st)
        return 0 if st == STATUS_OK else 3
    series = load_series(os.path.join(REPO, a.csv))
    if a.cmd == "tolerances":
        for k in sorted(series):
            t = series[k].tolerances()
            print("%s/%g\t%s" % (k[0], k[1], "\t".join("%s=%.6g" % kv for kv in t.items())))
        return 0
    s = series[(a.corner, a.temp)]
    print(render_model_card())
    print(render_subckt(s))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SurrogateError as e:
        print("svaricap_surrogate: refused: %s" % e, file=sys.stderr)
        sys.exit(1)
