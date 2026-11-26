"""Shared request/report inventory for the tank A/B record analyzers
(issues #166, #462 and #470).

A record directory (as written by run_tank_ab.sh / run_stub_ab.sh) holds
two inventories:

  reports/<name>.json        one returned klt sim report per submitted unit
  decks/<name>.request.json  that unit's requested process x temperature matrix

Discovery is the UNION of the two (#462): a unit whose report never came
back still exists as a request, and each of its requested corners must get
an explicit NO-REPORT coverage outcome -- a requested corner may never
silently disappear from the coverage CSV.

A unit whose report DID come back carries the same request-status decision
(#470): an absent or unreadable request gets exactly one request-level
coverage entry per returned report, decided here (request_coverage) and
applied by each consumer once per report, never inside its corner loop --
an empty report must not be able to skip it.

The two consumers (../bn-substrate-tank/analyze.py and
../tank-stub-load/analyze.py) share this inventory, the missing-report
coverage and the request-level coverage through this module; CSV
formatting, units, validation and the delta/tuning reductions stay local
to each experiment.

Both consumers run under `python3 -I` (isolated mode), so they load this
module by path with importlib.util -- the same way make_requests.py loads
svaricap_overlay.py.
"""
import glob, json, math, os


def isnum(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def fmt_t(t):
    return int(t) if float(t).is_integer() else t


def split_name(name):
    parts = name.split("__")
    return (parts[0], parts[1]) if len(parts) == 2 else (name, "")


def expected_corners(rec, name):
    """(set of (process, float temp), None) from decks/<name>.request.json.

    Returns (None, None) when the request file is absent (legacy record) and
    (None, why) when it is present but unreadable or malformed."""
    p = os.path.join(rec, "decks", name + ".request.json")
    if not os.path.exists(p):
        return None, None
    try:
        with open(p) as fh:
            cs = json.load(fh)["corners"]
        procs = [x["name"] for x in cs["process"]]
        temps = list(cs["temperature_c"])
        if not procs or not temps:
            raise ValueError("empty corner list")
        if not all(isinstance(pr, str) for pr in procs):
            raise ValueError("non-string process name")
        if not all(isnum(t) for t in temps):
            raise ValueError("non-numeric or non-finite temperature")
        return {(pr, float(t)) for pr in procs for t in temps}, None
    except Exception as e:
        return None, "request unreadable: %s" % type(e).__name__


def discover(rec):
    """Sorted union of unit names from reports/*.json and
    decks/*.request.json: every unit that was requested or returned.
    Empty when the record holds neither (the caller's EMPTY-INVENTORY)."""
    names = set()
    for p in glob.glob(os.path.join(rec, "reports", "*.json")):
        names.add(os.path.basename(p)[:-5])
    for p in glob.glob(os.path.join(rec, "decks", "*.request.json")):
        names.add(os.path.basename(p)[:-len(".request.json")])
    return sorted(names)


def no_report_coverage(rec, name, why):
    """Coverage entries for a unit with no usable report: a REQUEST-UNREADABLE
    entry when its request file is present but unreadable, then one NO-REPORT
    entry per requested corner (a single blank NO-REPORT entry for a legacy
    unit with no request file).

    Returns (variant, point, [(process, temp, outcome, detail), ...]); the
    caller maps the entries into its own coverage CSV format."""
    variant, point = split_name(name)
    exp, req_err = expected_corners(rec, name)
    entries = []
    if req_err:
        entries.append(("", "", "REQUEST-UNREADABLE", req_err))
    if exp is None:
        entries.append(("", "", "NO-REPORT", why))
    else:
        for pr, t in sorted(exp):
            entries.append((pr, fmt_t(t), "NO-REPORT", why))
    return variant, point, entries


def request_coverage(name, exp, req_err):
    """Request-level coverage entries for a unit whose report came back,
    from its request state as returned by expected_corners (issue #470).

    The consumer applies them once per returned report, whatever its corner
    list: one REQUEST-UNREADABLE entry when the request file is present but
    unreadable, one COVERAGE-UNCHECKED entry when it is absent (legacy
    record) and none when it is readable -- a readable request is covered by
    the consumer's per-corner entries and MISSING-CORNER rows.

    Returns [(process, temp, outcome, detail), ...] with blank process and
    temp; the caller maps the entries into its own coverage CSV format."""
    if req_err:
        return [("", "", "REQUEST-UNREADABLE", req_err)]
    if exp is None:
        return [("", "", "COVERAGE-UNCHECKED", "no decks/%s.request.json" % name)]
    return []
