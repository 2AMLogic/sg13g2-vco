#!/usr/bin/env python3
"""Read the three things the 135-corner reduction needs out of a klt-sim run's returned
metadata (issue #329). It reports what the fleet said; it estimates nothing.

  fleet_report.py units  REPORT.json
      One "<status><TAB><corner_id>" line per simulated unit, in report order. The grid
      driver uses it to refuse a corner whose units did not all pass before it reduces
      their traces.

  fleet_report.py inoise REPORT.json --process <mos_cap_hbt> --temp <C>
                         [--npts N --fstart Hz --fstop Hz]
      THIS corner's own inoise_0..inoise_{N-1} points, as "<freq_hz> <inoise>" lines.
      WHY THIS EXISTS: gen_isf_request.py --noise <port> --all-corners deliberately puts
      the whole 45 x 3 grid in ONE request per port (a `noise` analysis has no carrier
      dependence), and a klt-sim submit.stdout summarises each measurement as
      "worst=<v> @ <corner>" -- an extremum ACROSS the job's corners. Scraping that per
      corner would hand all 135 rows the worst corner's noise, silently. The per-corner
      values are in report.json's own corners[].measurements, so they are read from
      there. Frequencies are the declared linear sweep (pn_bench.sh PN_NOISE_*), which is
      what the deck swept.

  fleet_report.py job-id RECEIPT.json
      The batch job id, for the grader's job_id column.

Exit 1 with a one-line reason on stderr when the thing asked for is absent, ambiguous or
non-finite: a corner whose port noise cannot be resolved is a corner the grid driver must
emit with a cause, never one it may give a number to.
"""
import json
import math
import sys
from pathlib import Path


def die(msg):
    sys.stderr.write("error: " + msg + "\n")
    raise SystemExit(1)


def argval(flag, default=None):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


def load(path):
    p = Path(path)
    if not p.is_file():
        die(f"{path} does not exist")
    try:
        return json.loads(p.read_text())
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        die(f"{path} is not readable JSON ({e})")


def corners_of(report, path):
    c = report.get("corners")
    if not isinstance(c, list) or not c:
        die(f"{path} has no corners[] array (schema_version={report.get('schema_version')})")
    return c


def cmd_units(path):
    for c in corners_of(load(path), path):
        print(f"{c.get('status', 'unknown')}\t{c.get('corner_id', '?')}")


def freqs(npts, fstart, fstop):
    if npts < 1:
        die(f"--npts {npts} is not a point count")
    if npts == 1:
        return [fstart]
    return [fstart + (fstop - fstart) * k / (npts - 1) for k in range(npts)]


def cmd_inoise(path, process, temp, npts, fstart, fstop):
    report = load(path)
    hits = []
    for c in corners_of(report, path):
        try:
            t = int(round(float(c.get("temperature_c"))))
        except (TypeError, ValueError):
            continue
        if c.get("process") == process and t == temp:
            hits.append(c)
    if not hits:
        die(f"{path} has no corner with process={process} at {temp} C")
    if len(hits) > 1:
        die(f"{path} has {len(hits)} corners with process={process} at {temp} C "
            f"(ambiguous: {[h.get('corner_id') for h in hits][:3]})")
    c = hits[0]
    if c.get("status") != "pass":
        die(f"{c.get('corner_id')}: unit status is {c.get('status')}, not pass")
    vals = {}
    for m in c.get("measurements") or []:
        vals[m.get("name")] = m.get("value")
    out = []
    for k, f in enumerate(freqs(npts, fstart, fstop)):
        name = f"inoise_{k}"
        if name not in vals:
            die(f"{c.get('corner_id')}: {name} is not in the returned measurements")
        v = vals[name]
        if not isinstance(v, (int, float)) or isinstance(v, bool) or not math.isfinite(v) or v <= 0:
            die(f"{c.get('corner_id')}: {name} = {v!r} is not a finite positive noise density")
        out.append(f"{f:.6e} {v:.8e}")
    print("\n".join(out))


def cmd_job_id(path):
    r = load(path)
    j = r.get("job_id")
    if not j:
        die(f"{path} has no job_id")
    print(j)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, path = sys.argv[1], sys.argv[2]
    if cmd == "units":
        cmd_units(path)
    elif cmd == "inoise":
        process = argval("--process") or die("inoise needs --process <mos_cap_hbt>")
        temp = argval("--temp")
        if temp is None:
            die("inoise needs --temp <C>")
        cmd_inoise(path, process, int(temp), int(argval("--npts", 7)),
                   float(argval("--fstart", 3e9)), float(argval("--fstop", 9e9)))
    elif cmd == "job-id":
        cmd_job_id(path)
    else:
        die(f"unknown subcommand '{cmd}' (units | inoise | job-id)")


main()
