#!/usr/bin/env python3
"""Extract v(vdiff) from klt-sim waveform.raw.json files into wrdata-style `time value` .dat files.
Usage: extract_vdiff.py EVIDENCE_DIR OUT_DIR   -> OUT_DIR/dqd_<..>_dqt_<..>.dat + index.tsv (dqd dqt file)"""
import json, re, sys
from pathlib import Path
ev, out = Path(sys.argv[1]), Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
rows = []
for d in sorted(p for p in ev.iterdir() if p.is_dir()):
    cir = (d / "corner.cir").read_text()
    dqd = re.search(r"^alterparam dqd=(\S+)", cir, re.M).group(1)
    dqt = re.search(r"^alterparam dqt=(\S+)", cir, re.M).group(1)
    w = json.loads((d / "waveform.raw.json").read_text())
    names = [v["name"].lower() for v in w["variables"]]
    iv = names.index("v(vdiff)")
    name = f"dqd_{dqd}_dqt_{dqt}.dat"
    with open(out / name, "w") as fh:
        for p in w["points"]:
            fh.write(f"{p[0]:.12e} {p[iv]:.12e}\n")
    rows.append((dqd, dqt, name, len(w["points"])))
(out / "index.tsv").write_text("".join("\t".join(map(str, r)) + "\n" for r in rows))
print(*rows, sep="\n")
