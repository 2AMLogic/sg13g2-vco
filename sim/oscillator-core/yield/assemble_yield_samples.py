#!/usr/bin/env python3
"""Assemble the anchor-1 yield sample-set documents from the campaign reports.

Run step of issue #244 (anchor 1: tt statistical centre, 27 C, nominal rail).
Reads the four committed `klt sim` reports (campaign and known-bad control,
process and mismatch instruments), pairs samples by `mc<k>` suffix across the
two Vctrl endpoints (monte_carlo.seed_scope = "shared" makes sample k the same
die at both), derives the three graded quantities, and writes the two
`klt yield` sample-set documents.

Derived quantities and their spec rows (limits are quoted from
`spec/target-spec.md`, never adjusted):

- `f0_bandcentre_hz`   row 1: geometric mean of the endpoint frequencies,
                       the pilot's band-centre convention.   [4.5e9, 5.5e9]
- `tuning_ratio`       row 2: f(Vctrl=0) / f(Vctrl=3.3).      [>= 1.15]
- `swing_worst_v`      row 7: vdiff_max - vdiff_min, the WORSE
                       (smaller) of the two sampled endpoints. [>= 0.40]

Per-sample frequency is f = 10 / (t_cross_11 - t_cross_1), the two-WHEN
TD=10n estimator the elaborate-post79 record validated. The known-bad
control's samples are the same derived quantities from the tail-starved body
(RTE 2k -> 4.4k), carried as each measurement's negative_control.

Usage: python3 assemble_yield_samples.py   (from this directory)
"""

import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

REPORTS = {
    "process": {
        "campaign": HERE / "evidence-s1-process" / "report.json",
        "known_bad": HERE / "evidence-knownbad-process" / "report.json",
    },
    "mismatch": {
        "campaign": HERE / "evidence-s1-mismatch" / "report.json",
        "known_bad": HERE / "evidence-knownbad-mismatch" / "report.json",
    },
}

LIMITS = {
    "f0_bandcentre_hz": {"min": 4.5e9, "max": 5.5e9},
    "tuning_ratio": {"min": 1.15},
    "swing_worst_v": {"min": 0.40},
}
UNITS = {"f0_bandcentre_hz": "Hz", "tuning_ratio": "dimensionless", "swing_worst_v": "V"}

MC_MARKERS = ("/mc0", "/mc1", "/mc2", "/mc3", "/mc4", "/mc5", "/mc6", "/mc7", "/mc8", "/mc9")


def mc_index(corner_id: str) -> int:
    """`.../mc<k>` -> k. The `mc` suffix is appended after the supply field,
    so the last `/mc`-prefixed segment is the sample index."""
    tail = corner_id.rsplit("/mc", 1)
    if len(tail) != 2 or not tail[1].isdigit():
        raise ValueError(f"corner_id {corner_id!r} carries no mc<index> suffix")
    return int(tail[1])




def frequency_hz(unit: dict) -> float:
    t1 = unit["t_cross_1"]
    t11 = unit["t_cross_11"]
    if t1 is None or t11 is None or t11 <= t1:
        raise SystemExit(f"crossing times absent or inverted: {t1} .. {t11}")
    return 10.0 / (t11 - t1)


def derive_instrument(path: Path) -> dict[str, list[float]]:
    report = json.loads(path.read_text())
    endpoints: dict[tuple[int, float], dict] = {}
    for corner in report.get("corners", []):
        if corner.get("status") != "pass":
            raise SystemExit(f"{path.name}: unit {corner['corner_id']} is {corner.get('status')!r}")
        vct = float(corner["supply_v"]["vct"])
        endpoints[(mc_index(corner["corner_id"]), vct)] = {
            m["name"]: m["value"] for m in corner.get("measurements", [])
        }
    idxs = sorted({k[0] for k in endpoints})
    n = len(idxs)
    if n != 400:
        raise SystemExit(f"{path.name}: expected 400 sample indices, found {n}")
    f0s, ratios, swings = [], [], []
    for idx in idxs:
        lo = endpoints.get((idx, 0.0))
        hi = endpoints.get((idx, 3.3))
        if lo is None or hi is None:
            raise SystemExit(f"{path.name}: sample {idx} is missing an endpoint")
        f_lo, f_hi = frequency_hz(lo), frequency_hz(hi)
        f0s.append(math.sqrt(f_lo * f_hi))
        ratios.append(f_lo / f_hi)
        swings.append(
            min(
                lo["vdiff_max"] - lo["vdiff_min"],
                hi["vdiff_max"] - hi["vdiff_min"],
            )
        )
    return {"f0_bandcentre_hz": f0s, "tuning_ratio": ratios, "swing_worst_v": swings}


def main() -> int:
    # One sample-set document per (instrument, measurement): rows 1 and 2
    # genuinely miss (DR-006 shortfall, yield 0.0) and their envelopes grade
    # `fail`; row 7 passes (yield 1.0, CI low 0.9908, control detected) and
    # its envelope grades `pass`. Splitting the envelopes keeps the item-6
    # render truthful at row granularity -- one combined document would mark
    # row 7 failed inside a failing envelope even though every sample passes.
    rows = {"f0_bandcentre_hz": ["1"], "tuning_ratio": ["2"], "swing_worst_v": ["7"]}
    for instrument, paths in REPORTS.items():
        campaign = derive_instrument(paths["campaign"])
        known_bad = derive_instrument(paths["known_bad"])
        for name in ("f0_bandcentre_hz", "tuning_ratio", "swing_worst_v"):
            if len(campaign[name]) != 400 or len(known_bad[name]) != 400:
                raise SystemExit(f"{instrument}/{name}: expected 400 samples per side")
            doc = {
                "_comment": [
                    f"Anchor-1 sample set for klt yield, measurement {name} "
                    f"(issue #244 run step). Assembled from the committed "
                    f"evidence-s1-{instrument}/report.json (campaign) and "
                    f"evidence-knownbad-{instrument}/report.json (negative control) by "
                    "assemble_yield_samples.py.",
                    "Samples paired by mc<index> across the Vctrl 0.0/3.3 endpoints "
                    "(seed_scope shared: same die at both).",
                    "Limits are quoted from spec/target-spec.md and are never adjusted here.",
                ],
                "measurements": [
                    {
                        "name": name,
                        "unit": UNITS[name],
                        "samples": [round(v, 6) for v in campaign[name]],
                        "limits": LIMITS[name],
                    }
                ],
            }
            if name == "swing_worst_v":
                # The known-bad control is tail starvation: it degrades the swing row and
                # nothing else (sizing probe evidence-knownbad-probe/: f0 moves 0.2 %, ratio
                # unchanged). Declaring it on rows 1/2 would report `not_detected` for a
                # control that never targeted them -- and rows 1/2 campaign yield is already
                # 0.0 (the DR-006 shortfall), so no variant could degrade them further until
                # a passing re-tune exists. Undeclared control = disclosure, per
                # docs/cli/yield.md; the sampler-injection harness check is the separate
                # deterministic seed control (evidence-s0/, sigma = 0 exactly).
                doc["measurements"][0]["negative_control"] = {
                    "samples": [round(v, 6) for v in known_bad[name]],
                    "description": (
                        "Known-bad variant: campaign body with RTE 2k -> 4.4k (tail starved; sizing probe "
                        "evidence-knownbad-probe/, zero-spread swing 0.260 V at Vctrl=0). Same N, seed 244, "
                        "seed_scope shared and axes as the campaign; its swing yield must visibly degrade."
                    ),
                }
            out = HERE / f"yield-samples-{instrument}-{name}.json"
            out.write_text(json.dumps(doc, indent=1) + "\n")
            print(f"wrote {out.name} (row {rows[name][0]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
