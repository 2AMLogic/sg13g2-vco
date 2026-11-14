#!/usr/bin/env python3
"""Extract v(vdiff) from klt-sim waveform.raw.json files into wrdata-style `time value` .dat files.

  extract_vdiff.py EVIDENCE_DIR OUT_DIR [--corner CORNER_ID_PREFIX]
      -> OUT_DIR/dqd_<..>_dqt_<..>.dat + index.tsv (dqd dqt file rows)

--corner RESTRICTS the walk to units whose corner.json corner_id starts with the given
prefix (e.g. "ss_bcs_wcs/1.650V/-40C/"). Output names come from the deck's `alterparam
dqd=`/`dqt=` lines ALONE, so they carry no process or temperature: if several corners'
returned units ever share one evidence directory, their six filenames collide and one
corner's traces silently overwrite another's. One request per corner (the graded grid's
layout) cannot collide, and --corner makes that structural rather than incidental
(issue #329).

A subdirectory that is not a returned unit, or whose waveform has no v(vdiff), is SKIPPED
with a note on stderr rather than aborting the walk -- a partially returned corner must
still reduce as far as it can, and the missing .dat is then caught by the reducer's
trace-validity gate, which names it. Extracting nothing at all is an error: that is an
empty traces dir, which no gate downstream would distinguish from a clean run."""
import json
import re
import sys
from pathlib import Path


def argval(flag, default=None):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


def note(msg):
    sys.stderr.write("extract_vdiff: skipped " + msg + "\n")


ev, out = Path(sys.argv[1]), Path(sys.argv[2])
want = argval("--corner")
out.mkdir(parents=True, exist_ok=True)
rows = []
for d in sorted(p for p in ev.iterdir() if p.is_dir()):
    cir, wav, cjs = d / "corner.cir", d / "waveform.raw.json", d / "corner.json"
    if not cir.is_file():
        note(f"{d.name}: no corner.cir (not a returned unit)")
        continue
    if want is not None:
        if not cjs.is_file():
            note(f"{d.name}: no corner.json, so its corner identity cannot be checked "
                 f"against --corner {want}")
            continue
        cid = json.loads(cjs.read_text()).get("corner_id", "")
        if not cid.startswith(want):
            continue
    if not wav.is_file():
        note(f"{d.name}: no waveform.raw.json (unit returned no waveform)")
        continue
    text = cir.read_text()
    mdqd = re.search(r"^alterparam dqd=(\S+)", text, re.M)
    mdqt = re.search(r"^alterparam dqt=(\S+)", text, re.M)
    if mdqd is None or mdqt is None:
        note(f"{d.name}: corner.cir has no alterparam dqd=/dqt= pair")
        continue
    dqd, dqt = mdqd.group(1), mdqt.group(1)
    w = json.loads(wav.read_text())
    names = [v["name"].lower() for v in w["variables"]]
    if "v(vdiff)" not in names:
        note(f"{d.name}: waveform has no v(vdiff) (variables: {names[:6]})")
        continue
    iv = names.index("v(vdiff)")
    name = f"dqd_{dqd}_dqt_{dqt}.dat"
    if (out / name).exists():
        sys.exit(f"error: {out / name} already written in this walk -- two units in "
                 f"{ev} share dqd={dqd} dqt={dqt}; group units by corner (--corner) first")
    with open(out / name, "w") as fh:
        for p in w["points"]:
            fh.write(f"{p[0]:.12e} {p[iv]:.12e}\n")
    rows.append((dqd, dqt, name, len(w["points"])))
if not rows:
    sys.exit(f"error: no v(vdiff) trace extracted from {ev}"
             + (f" for --corner {want}" if want else ""))
(out / "index.tsv").write_text("".join("\t".join(map(str, r)) + "\n" for r in rows))
print(*rows, sep="\n")
