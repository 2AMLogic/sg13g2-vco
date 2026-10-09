#!/usr/bin/env python3
"""Check that the grader shell constants agree with the ratified spec.

The simulation graders copy ratified numeric requirements into shell
constants (sim/oscillator-core/osc_bench.sh OSC_ROW*, sim/phase-noise/
pn_bench.sh PN_ROW4_*, sim/oscillator-core/supply_stage2.sh S2_*). This gate
parses spec/target-spec.md (and the DR-004 stage-2 condition it references)
directly and compares every mapped constant after unit normalisation.

It checks AGREEMENT only. It never authorises a changed requirement (that is
a superseding decision record) and never regenerates historical evidence.
The expected values come from the spec text, never from the graders.

Fails (exit 1) on: a disagreeing constant, a spec field that cannot be
located or parsed, a mapped constant that is missing or not a plain literal,
or a new ROW-numbered grader constant with no mapping. Exit 2 on usage error.

Usage: check-grader-spec-agreement.py [--root DIR]

Stdlib only; no PDK, no simulator.
"""

import argparse
import glob
import os
import re
import sys
from decimal import Decimal, InvalidOperation
from fractions import Fraction

SPEC = "spec/target-spec.md"
DR_GLOB = "spec/decision-records/DR-004-*.md"
OSC = "sim/oscillator-core/osc_bench.sh"
PN = "sim/phase-noise/pn_bench.sh"
S2 = "sim/oscillator-core/supply_stage2.sh"
GRADERS = (OSC, PN, S2)

# Unit -> multiplier to the base unit (Hz, V, W, ratio, dBc/Hz, degC).
UNITS = {
    "GHz": 10**9, "MHz": 10**6, "kHz": 10**3, "Hz": 1,
    "V": 1, "mV": Fraction(1, 1000),
    "W": 1, "mW": Fraction(1, 1000),
    "%": Fraction(1, 100),
    "MHz/V": 10**6, "kHz/V": 10**3, "Hz/V": 1,
    "dBc/Hz": 1, "dBc": 1, "": 1, "C": 1,
}

NUM = r"[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?"


class SpecError(Exception):
    """A spec field could not be located or parsed."""


class Fail(Exception):
    pass


def qty(num, unit=""):
    if unit not in UNITS:
        raise SpecError("unsupported unit '%s'" % unit)
    try:
        return Fraction(Decimal(num.lstrip("+"))) * Fraction(UNITS[unit])
    except InvalidOperation:
        raise SpecError("not a number: '%s'" % num)


# --------------------------------------------------------------- spec parsing
def normalise(text):
    text = text.replace("−", "-").replace("\\|", "|")
    text = re.sub(r"[*`]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def split_cells(line):
    body = line.strip()
    if not (body.startswith("|") and body.endswith("|")):
        return None
    body = body[1:-1]
    return [normalise(c) for c in re.split(r"(?<!\\)\|", body)]


class Spec:
    COLS = {"param": 1, "min": 2, "typ": 3, "max": 4, "cond": 5, "status": 6}

    def __init__(self, root):
        self.root = root
        path = os.path.join(root, SPEC)
        try:
            with open(path, encoding="utf-8") as fh:
                lines = fh.read().splitlines()
        except OSError as exc:
            raise Fail("cannot read %s: %s" % (SPEC, exc))
        self.rows = {}
        self.bad_rows = {}
        for line in lines:
            m = re.match(r"\|\s*(\d+)\s*\|", line)
            if not m:
                continue
            rid = int(m.group(1))
            cells = split_cells(line)
            if rid in self.rows or rid in self.bad_rows:
                self.bad_rows[rid] = "row %d appears more than once" % rid
            elif cells is None or len(cells) != 7:
                self.bad_rows[rid] = (
                    "row %d is not a 7-cell table row (id|parameter|min|typ|"
                    "max|condition|status)" % rid)
            else:
                self.rows[rid] = cells
        self.dr_text = None
        self.dr_err = None
        hits = sorted(glob.glob(os.path.join(root, DR_GLOB)))
        if len(hits) != 1:
            self.dr_err = "expected exactly one %s, found %d" % (DR_GLOB, len(hits))
        else:
            with open(hits[0], encoding="utf-8") as fh:
                self.dr_text = normalise(fh.read())
            self.dr_name = os.path.basename(hits[0])

    def cell(self, row, col):
        if row in self.bad_rows:
            raise SpecError(self.bad_rows[row])
        if row not in self.rows:
            raise SpecError("row %d not found in %s" % (row, SPEC))
        return self.rows[row][self.COLS[col]]

    def match(self, row, col, pattern, what):
        text = self.cell(row, col)
        m = re.search(pattern, text)
        if not m:
            raise SpecError(
                "row %d %s cell: cannot parse %s; cell text is: '%s'"
                % (row, col, what, text[:160]))
        return m

    def title(self, row, keyword):
        if keyword.lower() not in self.cell(row, "param").lower():
            raise SpecError(
                "row %d parameter is '%s', expected it to mention '%s' "
                "(rows renumbered or retitled?)"
                % (row, self.cell(row, "param")[:60], keyword))

    def dr(self, pattern, what):
        if self.dr_text is None:
            raise SpecError(self.dr_err)
        m = re.search(pattern, self.dr_text)
        if not m:
            raise SpecError("%s: cannot parse %s" % (self.dr_name, what))
        return m


# ------------------------------------------------------------ spec field table
FIELDS = {}


def field(fid, row, desc):
    def deco(fn):
        FIELDS[fid] = (row, desc, fn)
        return fn
    return deco


def _row0(s, col):
    s.title(0, "Supply")
    m = s.match(0, col, r"^(%s) (V)\b" % NUM, "a voltage")
    return qty(m.group(1), m.group(2))


@field("row0.min", 0, "supply minimum (V)")
def _(s):
    return _row0(s, "min")


@field("row0.typ", 0, "supply nominal (V)")
def _(s):
    return _row0(s, "typ")


@field("row0.max", 0, "supply maximum (V)")
def _(s):
    return _row0(s, "max")


@field("row0.rails", 0, "supply min/max rails (V), +/-10 % condition")
def _(s):
    lo, typ, hi = _row0(s, "min"), _row0(s, "typ"), _row0(s, "max")
    m = s.match(0, "cond", r"±\s*(%s)\s*%%" % NUM, "the +/- N % excursion")
    pct = qty(m.group(1), "%")
    if lo != typ * (1 - pct) or hi != typ * (1 + pct):
        raise SpecError(
            "row 0 min/typ/max (%s/%s/%s V) are not typ*(1-/+%s) of the "
            "stated excursion" % (float(lo), float(typ), float(hi), m.group(1)))
    return [lo, hi]


@field("row1.min", 1, "band minimum (Hz)")
def _(s):
    s.title(1, "band")
    m = s.match(1, "min", r"^(%s) ([kMG]?Hz)$" % NUM, "a frequency")
    return qty(m.group(1), m.group(2))


@field("row1.max", 1, "band maximum (Hz)")
def _(s):
    s.title(1, "band")
    m = s.match(1, "max", r"^(%s) ([kMG]?Hz)$" % NUM, "a frequency")
    return qty(m.group(1), m.group(2))


@field("row2.target", 2, "tuning range target as f_max/f_min ratio")
def _(s):
    s.title(2, "Tuning range")
    m = s.match(2, "min", r"^≥ (%s) %%$" % NUM, "'≥ N %'")
    return 1 + qty(m.group(1), "%")


@field("row2.stretch", 2, "tuning range stretch as f_max/f_min ratio")
def _(s):
    s.title(2, "Tuning range")
    m = s.match(2, "max", r"^\(≥ (%s) %% stretch\)$" % NUM, "'(≥ N % stretch)'")
    return 1 + qty(m.group(1), "%")


@field("row3.v_lo", 3, "Vctrl window low (V)")
def _(s):
    s.title(3, "Kvco")
    m = s.match(3, "cond", r"window W = \[(%s), (%s)\] V" % (NUM, NUM),
                "the window 'W = [lo, hi] V'")
    return qty(m.group(1), "V")


@field("row3.v_hi", 3, "Vctrl window high (V)")
def _(s):
    s.title(3, "Kvco")
    m = s.match(3, "cond", r"window W = \[(%s), (%s)\] V" % (NUM, NUM),
                "the window 'W = [lo, hi] V'")
    return qty(m.group(2), "V")


@field("row3.v_full_lo", 3, "full-domain low (V), f(lo) in the coverage span")
def _(s):
    s.title(3, "Kvco")
    m = s.match(3, "cond", r"full-domain span f\((%s)\) - f\((%s)\)" % (NUM, NUM),
                "the 'full-domain span f(lo) - f(hi)'")
    w = s.match(3, "cond", r"window W = \[(%s), (%s)\] V" % (NUM, NUM), "window")
    if qty(m.group(2), "V") != qty(w.group(2), "V"):
        raise SpecError("row 3 full-domain span high end f(%s) differs from the "
                        "window high end %s" % (m.group(2), w.group(2)))
    return qty(m.group(1), "V")


@field("row3.coverage", 3, "window coverage minimum (ratio)")
def _(s):
    s.title(3, "Kvco")
    m = s.match(3, "cond", r"≥ (%s) %% of the same corner's own" % NUM,
                "'≥ N % of the same corner's own' coverage")
    return qty(m.group(1), "%")


@field("row3.kvco_mean", 3, "|Kvco|_mean floor (Hz/V)")
def _(s):
    s.title(3, "Kvco")
    m = s.match(3, "min", r"\|Kvco\|_mean ≥ (%s) ([kM]?Hz/V|MHz/V)" % NUM,
                "'|Kvco|_mean ≥ N MHz/V'")
    return qty(m.group(1), m.group(2))


@field("row3.inl_target", 3, "chord nonlinearity target (percent)")
def _(s):
    s.title(3, "Kvco")
    m = s.match(3, "max", r"chord nonlinearity ≤ (%s) %% of span" % NUM,
                "'chord nonlinearity ≤ N % of span'")
    return qty(m.group(1), "%") * 100


@field("row3.inl_stretch", 3, "chord nonlinearity stretch (percent)")
def _(s):
    s.title(3, "Kvco")
    m = s.match(3, "max", r"\(≤ (%s) %% stretch\)" % NUM, "'(≤ N % stretch)'")
    return qty(m.group(1), "%") * 100


@field("row3.min_points", 3, "minimum Vctrl points for the chord measure")
def _(s):
    s.title(3, "Kvco")
    m = s.match(3, "cond", r"graded on ≥ (\d+) Vctrl points", "'graded on ≥ N Vctrl points'")
    return Fraction(int(m.group(1)))


def _pn(s, col, idx):
    s.title(4, "Phase noise")
    if col == "max":
        m = s.match(
            4, "max",
            r"^≤ (%s) dBc/Hz @ (%s) (MHz) \(target\); ≤ (%s) \(stretch\)"
            % (NUM, NUM, NUM), "'≤ X dBc/Hz @ 1 MHz (target); ≤ Y (stretch)'")
        if qty(m.group(2), m.group(3)) != 10**6:
            raise SpecError("row 4 primary offset is not 1 MHz")
        return qty(m.group(1 if idx == 0 else 4), "dBc/Hz")
    m = s.match(
        4, "cond",
        r"at (%s) (MHz) offset the companion bounds are ≤ (%s) target / ≤ (%s) stretch"
        % (NUM, NUM, NUM), "'at 10 MHz offset the companion bounds are ≤ X target / ≤ Y stretch'")
    if qty(m.group(1), m.group(2)) != 10 * 10**6:
        raise SpecError("row 4 companion offset is not 10 MHz")
    return qty(m.group(3 if idx == 0 else 4), "dBc/Hz")


@field("row4.1m_target", 4, "L(1 MHz) target (dBc/Hz)")
def _(s):
    return _pn(s, "max", 0)


@field("row4.1m_stretch", 4, "L(1 MHz) stretch (dBc/Hz)")
def _(s):
    return _pn(s, "max", 1)


@field("row4.10m_target", 4, "L(10 MHz) target (dBc/Hz)")
def _(s):
    return _pn(s, "cond", 0)


@field("row4.10m_stretch", 4, "L(10 MHz) stretch (dBc/Hz)")
def _(s):
    return _pn(s, "cond", 1)


@field("row6.margin", 6, "startup margin minimum (ratio)")
def _(s):
    s.title(6, "Startup")
    m = s.match(6, "min", r"^≥ (%s)$" % NUM, "'≥ N'")
    return qty(m.group(1))


def _row7(s, idx):
    s.title(7, "Output swing")
    m = s.match(
        7, "min", r"^(%s) (m?V) Vpp \((%s) (m?V) stretch\)$" % (NUM, NUM),
        "'N V Vpp (M V stretch)'")
    return qty(m.group(1 + 2 * idx), m.group(2 + 2 * idx))


@field("row7.vpp_min", 7, "differential swing minimum (V)")
def _(s):
    return _row7(s, 0)


@field("row7.vpp_stretch", 7, "differential swing stretch (V)")
def _(s):
    return _row7(s, 1)


@field("row7.bvceo", 7, "BVCEO(min) compliance limit (V)")
def _(s):
    s.title(7, "Output swing")
    m = s.match(7, "cond", r"BVCEO\(min\) = (%s) V" % NUM, "'BVCEO(min) = N V'")
    return qty(m.group(1), "V")


def _row8(s, idx):
    s.title(8, "Supply current")
    m = s.match(
        8, "max", r"^≤ (%s) (m?W) core \(target\); ≤ (%s) (m?W) \(stretch\)"
        % (NUM, NUM), "'≤ N mW core (target); ≤ M mW (stretch)'")
    return qty(m.group(1 + 2 * idx), m.group(2 + 2 * idx))


@field("row8.p_max", 8, "core power ceiling (W)")
def _(s):
    return _row8(s, 0)


@field("row8.p_stretch", 8, "core power stretch (W) -- not consumed by any grader")
def _(s):
    return _row8(s, 1)


def _temps(s):
    s.title(10, "PVT")
    m = s.match(10, "cond", r"temperatures \{([^}]*)\} ?°C",
                "'temperatures {a, b, c} °C'")
    parts = [p.strip() for p in m.group(1).split(",") if p.strip()]
    if not parts:
        raise SpecError("row 10 temperature set is empty")
    return [qty(p, "C") for p in parts]


@field("row10.temps", 10, "corner temperatures (C), agreeing with row 11 envelope")
def _(s):
    temps = _temps(s)
    s.title(11, "temperature")
    lo = qty(s.match(11, "min", r"^(%s) ?°C$" % NUM, "'N °C'").group(1), "C")
    hi = qty(s.match(11, "max", r"^(%s) ?°C$" % NUM, "'N °C'").group(1), "C")
    if min(temps) != lo or max(temps) != hi:
        raise SpecError("row 10 temperatures and row 11 envelope disagree "
                        "inside the spec itself")
    return temps


def _dr_stage2(s):
    m = s.dr(r"Stage 2 [-—–] the supply sub-corner set: (\d+) points\. "
             r"\{([^}]*)\} V × \{([^}]*)\} × \{([^}]*)\} ?°C",
             "the stage-2 '{rails} V × {processes} × {temps} °C' condition")
    rails = [qty(x.strip(), "V") for x in m.group(2).split(",") if x.strip()]
    procs = [x.strip() for x in m.group(3).split(",") if x.strip()]
    temps = [qty(x.strip(), "C") for x in m.group(4).split(",") if x.strip()]
    n = int(m.group(1))
    if len(rails) * len(procs) * len(temps) != n:
        raise SpecError("DR-004 stage 2 states %d points but its own sets give %d"
                        % (n, len(rails) * len(procs) * len(temps)))
    return rails, procs, temps, n


@field("dr4.rails", 0, "DR-004 stage-2 rails (V), agreeing with row 0")
def _(s):
    rails = _dr_stage2(s)[0]
    if rails != FIELDS["row0.rails"][2](s):
        raise SpecError("DR-004 stage-2 rails disagree with spec row 0 min/max")
    return rails


@field("dr4.processes", 10, "DR-004 stage-2 process vertices")
def _(s):
    return _dr_stage2(s)[1]


@field("dr4.temps", 10, "DR-004 stage-2 temperatures (C), agreeing with row 10")
def _(s):
    temps = _dr_stage2(s)[2]
    if temps != FIELDS["row10.temps"][2](s):
        raise SpecError("DR-004 stage-2 temperatures disagree with spec row 10")
    return temps


@field("dr4.n_points", 10, "DR-004 stage-2 point count")
def _(s):
    return Fraction(_dr_stage2(s)[3])


# ---------------------------------------------------------------- the mapping
# (grader file, shell variable, spec field id, kind, grader-value scale).
# kind "num": one literal; "list": whitespace-separated literals; "words":
# whitespace-separated names. scale converts the grader's native unit to the
# spec field's base unit (e.g. 1/100 for a constant stored in percent).
# NOTE the stage-2 constants also exercise the DR-004 condition; the nominal
# rail constants map to the row 0 typical value.
MAPPING = [
    (S2, "S2_RAILS", "dr4.rails", "list", 1),
    (S2, "S2_RAILS", "row0.rails", "list", 1),
    (S2, "S2_NOMINAL_RAIL", "row0.typ", "num", 1),
    (OSC, "OSC_VDD_NOM", "row0.typ", "num", 1),
    (S2, "S2_TEMPS", "dr4.temps", "list", 1),
    (S2, "S2_TEMPS", "row10.temps", "list", 1),
    (S2, "S2_PROCESSES", "dr4.processes", "words", 1),
    (S2, "S2_N_POINTS", "dr4.n_points", "num", 1),
    (OSC, "OSC_ROW1_F_MIN_HZ", "row1.min", "num", 1),
    (OSC, "OSC_ROW1_F_MAX_HZ", "row1.max", "num", 1),
    (OSC, "OSC_ROW2_RATIO", "row2.target", "num", 1),
    (OSC, "OSC_ROW2_RATIO_STRETCH", "row2.stretch", "num", 1),
    (OSC, "OSC_ROW3_V_LO", "row3.v_lo", "num", 1),
    (OSC, "OSC_ROW3_V_HI", "row3.v_hi", "num", 1),
    (OSC, "OSC_ROW3_V_FULL_LO", "row3.v_full_lo", "num", 1),
    (OSC, "OSC_ROW3_COVERAGE_MIN", "row3.coverage", "num", 1),
    (OSC, "OSC_ROW3_KVCO_MEAN_MIN_HZ_PER_V", "row3.kvco_mean", "num", 1),
    (OSC, "OSC_ROW3_CHORD_INL_PCT", "row3.inl_target", "num", 1),
    (OSC, "OSC_ROW3_CHORD_INL_PCT_STRETCH", "row3.inl_stretch", "num", 1),
    (OSC, "OSC_ROW3_MIN_SAMPLES", "row3.min_points", "num", 1),
    (PN, "PN_ROW4_1M_TARGET", "row4.1m_target", "num", 1),
    (PN, "PN_ROW4_1M_STRETCH", "row4.1m_stretch", "num", 1),
    (PN, "PN_ROW4_10M_TARGET", "row4.10m_target", "num", 1),
    (PN, "PN_ROW4_10M_STRETCH", "row4.10m_stretch", "num", 1),
    (OSC, "OSC_ROW6_MARGIN", "row6.margin", "num", 1),
    (OSC, "OSC_ROW7_VPP_MIN_V", "row7.vpp_min", "num", 1),
    (OSC, "OSC_ROW7_VPP_MIN_STRETCH_V", "row7.vpp_stretch", "num", 1),
    (OSC, "OSC_ROW7_BVCEO_MIN_V", "row7.bvceo", "num", 1),
    (OSC, "OSC_ROW8_P_MAX_W", "row8.p_max", "num", 1),
]
# The percent-valued grader constants hold N, not N/100: the spec extractors
# for those fields already return N (see row3.inl_*), so scale stays 1.

# Spec rows/fields deliberately NOT consumed by any grader constant. They must
# still be locatable in the spec; a ROW-numbered grader constant appearing for
# one of them is flagged so it gets mapped rather than silently drifting.
UNCONSUMED_ROWS = {
    5: "tank Q (no grader constant)",
    8: "stretch <= 5 mW (OSC_ROW8_P_MAX_W maps only the 10 mW target)",
    9: "supply sensitivity / pushing (no grader constant)",
    11: "temperature envelope (checked only through row 10 and S2_TEMPS)",
}
UNCONSUMED_SPEC_FIELDS = (
    ("row5.q", 5, "Tank quality", "min", r"^≥ (%s)$" % NUM),
    ("row9.pushing", 9, "Supply sensitivity", "max", r"^≤ (%s) MHz/V \(target\)" % NUM),
)

# Grader policy knobs, not ratified bounds (intentionally out of scope).
OUT_OF_SCOPE = {
    "OSC_ROW7_MIN_WINDOW_SAMPLES": "grader policy (sample-count knob)",
    "OSC_ROW7_AWK_LIB": "awk library body, not a bound",
}

ROW_VAR = re.compile(r"^((?:OSC|PN|S2)_ROW(\d+)\w*)=", re.M)
LITERAL = re.compile(r"^%s$" % NUM)


# ------------------------------------------------------------ grader parsing
def read_text(root, rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        raise Fail("cannot read %s: %s" % (rel, exc))


def grader_value(text, rel, var):
    """Top-level (column 0) literal assignment of var; returns the string."""
    found = []
    for m in re.finditer(r"^%s=(.*)$" % re.escape(var), text, re.M):
        rest = m.group(1)
        if rest[:1] in ('"', "'"):
            q = rest[0]
            end = rest.find(q, 1)
            if end < 0:
                raise Fail("%s: %s has an unterminated quote" % (rel, var))
            value, tail = rest[1:end], rest[end + 1:]
        else:
            vm = re.match(r"[^\s#]*", rest)
            value, tail = vm.group(0), rest[vm.end():]
        if tail.strip() and not tail.strip().startswith("#"):
            raise Fail("%s: %s has trailing text after the value; use a plain "
                       "literal assignment" % (rel, var))
        if re.search(r"[$`]", value):
            raise Fail("%s: %s='%s' is not a plain literal (expansion); the "
                       "checker cannot verify it -- use a literal" % (rel, var, value))
        found.append(value)
    if not found:
        raise Fail("%s: no top-level assignment of %s found (renamed or removed? "
                   "update MAPPING in check-grader-spec-agreement.py)" % (rel, var))
    if len(set(found)) > 1:
        raise Fail("%s: %s is assigned more than once at top level with "
                   "different values %s" % (rel, var, found))
    return found[0]


def to_values(raw, kind, rel, var):
    if kind == "words":
        return raw.split()
    items = raw.split()
    if not items:
        raise Fail("%s: %s is empty" % (rel, var))
    out = []
    for it in items:
        if not LITERAL.match(it):
            raise Fail("%s: %s='%s' contains a non-numeric token '%s'"
                       % (rel, var, raw, it))
        out.append(Fraction(Decimal(it.lstrip("+"))))
    if kind == "num":
        if len(out) != 1:
            raise Fail("%s: %s='%s' should be a single number" % (rel, var, raw))
        return out[0]
    return out


def fmt(v):
    if isinstance(v, list):
        return "[" + " ".join(fmt(x) for x in v) + "]"
    if isinstance(v, str):
        return v
    return "%g" % float(v)


# ----------------------------------------------------------------------- main
def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    args = ap.parse_args(argv)
    root = os.path.abspath(args.root)

    failures = []
    ok = 0
    try:
        spec = Spec(root)
    except Fail as exc:
        print("FAIL: %s" % exc, file=sys.stderr)
        return 1

    cache = {}

    def spec_value(fid):
        if fid not in cache:
            row, desc, fn = FIELDS[fid]
            try:
                cache[fid] = (fn(spec), None)
            except SpecError as exc:
                cache[fid] = (None, str(exc))
        return cache[fid]

    texts = {}
    for rel in GRADERS:
        try:
            texts[rel] = read_text(root, rel)
        except Fail as exc:
            failures.append(str(exc))

    for rel, var, fid, kind, scale in MAPPING:
        row, desc, _ = FIELDS[fid]
        want, err = spec_value(fid)
        label = "%s (%s) vs spec row %d, %s" % (var, rel, row, desc)
        if err:
            failures.append("%s: spec field %s unreadable: %s" % (label, fid, err))
            continue
        if rel not in texts:
            continue
        try:
            got = to_values(grader_value(texts[rel], rel, var), kind, rel, var)
        except Fail as exc:
            failures.append("%s: %s" % (label, exc))
            continue
        if kind != "words":
            got = [g * scale for g in got] if isinstance(got, list) else got * scale
        if got != want:
            failures.append("%s: grader has %s, spec says %s"
                            % (label, fmt(got), fmt(want)))
        else:
            ok += 1
            print("ok: %s = %s" % (label, fmt(got)))

    # Rows deliberately unconsumed must still be locatable in the spec.
    for fid, row, kw, col, pat in UNCONSUMED_SPEC_FIELDS:
        try:
            spec.title(row, kw)
            spec.match(row, col, pat, "the ratified bound")
            print("ok: spec row %d located; %s" % (row, UNCONSUMED_ROWS[row]))
        except SpecError as exc:
            failures.append("spec row %d (not consumed by a grader) unreadable: %s"
                            % (row, exc))
    for fid in ("row8.p_stretch",):
        _, err = spec_value(fid)
        if err:
            failures.append("spec row 8 stretch (not consumed) unreadable: %s" % err)
        else:
            print("ok: spec row 8 stretch located; %s" % UNCONSUMED_ROWS[8])
    try:
        spec.title(11, "temperature")
        print("ok: spec row 11 located; %s" % UNCONSUMED_ROWS[11])
    except SpecError as exc:
        failures.append("spec row 11 unreadable: %s" % exc)

    # New ROW-numbered grader constants must be mapped or declared out of scope.
    mapped = {(rel, var) for rel, var, *_ in MAPPING}
    for rel, text in texts.items():
        for m in ROW_VAR.finditer(text):
            var, row = m.group(1), int(m.group(2))
            if (rel, var) in mapped or var in OUT_OF_SCOPE:
                continue
            why = UNCONSUMED_ROWS.get(row)
            failures.append(
                "%s: new grader constant %s (spec row %d%s) has no mapping; add "
                "it to MAPPING (or OUT_OF_SCOPE if it is policy, not a ratified "
                "bound) in check-grader-spec-agreement.py"
                % (rel, var, row, "; row declared unconsumed: " + why if why else ""))

    if failures:
        for f in failures:
            print("FAIL: %s" % f, file=sys.stderr)
        print("check-grader-spec-agreement: %d disagreement(s), %d ok. This gate "
              "checks agreement only; a changed requirement needs a superseding "
              "decision record (spec/README.md)." % (len(failures), ok),
              file=sys.stderr)
        return 1
    print("check-grader-spec-agreement: %d mapped constants agree with the spec" % ok)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
