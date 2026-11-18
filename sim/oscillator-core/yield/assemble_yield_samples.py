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

Usage: python3 assemble_yield_samples.py           (anchor-1 mode, as before)
       python3 assemble_yield_samples.py ac4c      (AC 4c stages: rows 3 and 6)
       python3 assemble_yield_samples.py ac4c-ext  (row-6 mismatch extension, seed 245)
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
    if len(sys.argv) > 1 and sys.argv[1] == "ac4c":
        return ac4c_main()
    if len(sys.argv) > 1 and sys.argv[1] == "ac4c-ext":
        return ac4c_ext_main()
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


# ---------------------------------------------------------------------------
# AC 4c stages (issue #244, 2026-11-17): rows 3 and 6.
#
# Row 3 (Kvco and linearity) pairs the anchor-1 S1 endpoints (Vctrl 0.0/3.3,
# evidence-s1-*/report.json) with the S2 mid-window points (1.65/1.8/2.4/3.0,
# evidence-s2-*/report.json) by sample index -- the seed contract
# (klayout-tools#2899 behind monte_carlo.seed_scope = "shared") makes sample k
# the same die at every point and across requests; proven before submission by
# the request-pair-probe-* units against the S1 reports.
#
# Row 6 (startup margin) derives a per-sample LOWER BOUND on I_nom/I_threshold
# from the decision rung of the pilot's RREF ladder. Oscillation criterion (the
# pilot's declared one, on this bench's 20 ns tran): t_cross_1 and t_cross_11
# both present AND vdiff peak-to-peak over the late window 15-20 ns >= 0.1 V
# (10x the 10 mV .ic perturbation). I_tail is MEASURED per die from
# vte_avg / RTE (RTE = 2k in the campaign body), never inferred from the RREF
# multiplier (the pilot's limit 1). A die that fails the decision rung reports
# the floor 1.0 -- it demonstrably sustains at nominal tail current only, the
# same bound the anchor-1 known-bad control's oscillation at nominal measured.
# ---------------------------------------------------------------------------

RTE_OHMS = 2000.0  # RTE stays 2k in every campaign/rung body (only RREF scales)
LATE_VPP_MIN = 0.1  # the declared oscillation criterion, in V
WINDOW_V = (1.65, 3.3)  # row 3's ratified window W, both endpoints
S2_POINTS = (1.65, 1.8, 2.4, 3.0)  # the new mid-window points
S1_POINTS = (0.0, 3.3)  # the anchor-1 endpoints, reused by the seed contract
CHORD_POINTS = (1.65, 1.8, 2.4, 3.0, 3.3)  # >=5 in-window points incl. both endpoints

ROW3_LIMITS = {
    # Quoted from spec/target-spec.md row 3; never adjusted here.
    "kvco_mean_mhz_v": {"min": 381.0},
    "kvco_chord_nonlinearity_pct": {"max": 30.0},
    "window_coverage": {"min": 0.9},
    "kvco_single_signed": {"min": 1.0},
}
ROW6_LIMITS = {"startup_margin_lower": {"min": 3.0}}  # spec/target-spec.md row 6
ROW3_UNITS = {
    "kvco_mean_mhz_v": "MHz/V",
    "kvco_chord_nonlinearity_pct": "percent",
    "window_coverage": "dimensionless",
    "kvco_single_signed": "dimensionless",
}


def load_units(path: Path, expect_points: tuple[float, ...], expect_n: int) -> dict[tuple[int, float], dict]:
    """Map (mc index, Vctrl) -> {measurement name: value-or-None} for every
    unit the engine ran. An engine-level abort (no measurement value at all)
    raises: a missing die is not a non-oscillation and must not be silently
    averaged away."""
    report = json.loads(path.read_text())
    units: dict[tuple[int, float], dict] = {}
    for corner in report.get("corners", []):
        status = corner.get("status")
        if status not in ("pass", "error"):
            raise SystemExit(f"{path.name}: unit {corner['corner_id']} is {status!r}")
        meas = {m["name"]: m.get("value") for m in corner.get("measurements", [])}
        if not any(v is not None for v in meas.values()):
            raise SystemExit(f"{path.name}: unit {corner['corner_id']} has no measurement value at all")
        units[(mc_index(corner["corner_id"]), float(corner["supply_v"]["vct"]))] = meas
    idxs = {k[0] for k in units}
    if len(idxs) != expect_n:
        raise SystemExit(f"{path.name}: expected {expect_n} sample indices, found {len(idxs)}")
    for idx in idxs:
        for vct in expect_points:
            if (idx, vct) not in units:
                raise SystemExit(f"{path.name}: sample {idx} is missing Vctrl={vct}")
    return units


def freq_hz_or_none(unit: dict) -> float | None:
    t1, t11 = unit.get("t_cross_1"), unit.get("t_cross_11")
    if t1 is None or t11 is None or t11 <= t1:
        return None
    return 10.0 / (t11 - t1)


def oscillating(unit: dict) -> bool:
    if unit.get("t_cross_1") is None or unit.get("t_cross_11") is None:
        return False
    late = unit.get("vdiff_late_max")
    lami = unit.get("vdiff_late_min")
    return late is not None and lami is not None and (late - lami) >= LATE_VPP_MIN


def row3_derive(instrument: str) -> tuple[dict[str, list[float]], int]:
    s1 = load_units(HERE / f"evidence-s1-{instrument}" / "report.json", S1_POINTS, 400)
    s2 = load_units(HERE / f"evidence-s2-{instrument}" / "report.json", S2_POINTS, 400)
    freqs: dict[tuple[int, float], float | None] = {}
    for idx in range(400):
        for vct, units in ((0.0, s1), (3.3, s1), *[(v, s2) for v in S2_POINTS]):
            freqs[(idx, vct)] = freq_hz_or_none(units[(idx, vct)])
    errored = 0
    kvco, chord_nl, cover, single = [], [], [], []
    for idx in range(400):
        vals = [freqs[(idx, v)] for v in (0.0,) + CHORD_POINTS]
        if any(v is None for v in vals):
            errored += 1
            continue
        f_wlo = freqs[(idx, WINDOW_V[0])]
        f_whi = freqs[(idx, WINDOW_V[1])]
        f_lo0 = freqs[(idx, 0.0)]
        span = f_wlo - f_whi
        kvco.append(abs(span) / (WINDOW_V[1] - WINDOW_V[0]) / 1e6)
        cover.append(span / (f_lo0 - f_whi))
        chord = [
            f_wlo + (v - WINDOW_V[0]) / (WINDOW_V[1] - WINDOW_V[0]) * (f_whi - f_wlo)
            for v in CHORD_POINTS
        ]
        chord_nl.append(
            100.0
            * max(abs(freqs[(idx, v)] - c) for v, c in zip(CHORD_POINTS, chord))
            / abs(f_whi - f_wlo)
        )
        segs = [freqs[(idx, b)] - freqs[(idx, a)] for a, b in zip(CHORD_POINTS, CHORD_POINTS[1:])]
        single.append(1.0 if all(s > 0 for s in segs) or all(s < 0 for s in segs) else 0.0)
    out = {
        "kvco_mean_mhz_v": kvco,
        "kvco_chord_nonlinearity_pct": chord_nl,
        "window_coverage": cover,
        "kvco_single_signed": single,
    }
    for name, samples in out.items():
        if len(samples) + errored != 400:
            raise SystemExit(f"{instrument}/{name}: {len(samples)} samples + {errored} errored != 400")
    return out, errored


def row6_derive(instrument: str) -> tuple[dict[str, list[float]], int, list[float]]:
    s2 = load_units(HERE / f"evidence-s2-{instrument}" / "report.json", S2_POINTS, 400)
    ladder = load_units(HERE / f"evidence-r6-ladder-{instrument}" / "report.json", (1.65,), 400)
    control = load_units(HERE / f"evidence-r6-ladder-control-{instrument}" / "report.json", (1.65,), 100)

    def itail(units: dict, idx: int, points: tuple[float, ...]) -> float | None:
        # I_tail is MEASURED from vte_avg/RTE (the pilot's route), never from
        # the RREF multiplier. The nominal rung reads the die's own S2 unit
        # (the bias side barely moves with Vctrl; 1.65 V first, then any other).
        for vct in points:
            v = units[(idx, vct)].get("vte_avg")
            if v is not None:
                return v / RTE_OHMS
        return None

    samples, errored = [], 0
    for idx in range(400):
        if not oscillating(s2[(idx, 1.65)]):
            # The die did not sustain at NOMINAL tail in its own S2 unit: the
            # floor 1.0 is not measured for it. Errored, never asserted.
            errored += 1
            continue
        if oscillating(ladder[(idx, 1.65)]):
            i_nom = itail(s2, idx, (1.65,) + S2_POINTS[1:])
            i_rung = itail(ladder, idx, (1.65,))
            if i_nom is None or i_rung is None or i_rung <= 0:
                errored += 1
                continue
            samples.append(i_nom / i_rung)
        else:
            samples.append(1.0)

    ctrl = []
    for idx in range(100):
        if oscillating(control[(idx, 1.65)]):
            raise SystemExit(
                f"{instrument}: known-bad control unit mc{idx} SUSTAINS the decision rung -- "
                "the rung does not separate the variant from the campaign; pick the rung from "
                "the deterministic probe (and its known-bad probes) before grading."
            )
        ctrl.append(1.0)
    return {"startup_margin_lower": samples}, errored, ctrl


def write_sample_set(instrument: str, name: str, samples: list[float], limits: dict, unit: str,
                     errored: int, rows_tag: str, control: dict | None, comment: list[str],
                     out_name: str | None = None) -> None:
    meas: dict = {
        "name": name,
        "unit": unit,
        "samples": [round(v, 6) for v in samples],
        "limits": limits,
    }
    if errored:
        meas["errored"] = errored
    if control is not None:
        meas["negative_control"] = control
    doc = {"_comment": comment, "measurements": [meas]}
    out = HERE / f"yield-samples-{instrument}-{out_name or name}.json"
    out.write_text(json.dumps(doc, indent=1) + "\n")
    print(f"wrote {out.name} (row {rows_tag}, n={len(samples)}, errored={errored})")


def ac4c_main() -> int:
    for instrument in ("process", "mismatch"):
        r3, err3 = row3_derive(instrument)
        base3 = [
            f"AC 4c sample set for klt yield, measurement {name}, {instrument} instrument "
            "(issue #244). Assembled from evidence-s1-%s/report.json (Vctrl 0.0/3.3, anchor 1) "
            "and evidence-s2-%s/report.json (1.65/1.8/2.4/3.0) by assemble_yield_samples.py "
            "ac4c, paired by mc<index>: seed 244 + seed_scope shared makes sample k the same "
            "die at every point and across requests (verified pre-submission by the "
            "request-pair-probe-%s units against the S1 reports). Limits are quoted from "
            "spec/target-spec.md row 3 and are never adjusted here."
            % (instrument, instrument, instrument)
            for name in ROW3_LIMITS
        ]
        for name, comment in zip(ROW3_LIMITS, base3):
            write_sample_set(instrument, name, r3[name], ROW3_LIMITS[name],
                             ROW3_UNITS[name], err3, "3", None, [comment])
        r6, err6, ctrl6 = row6_derive(instrument)
        write_sample_set(
            instrument, "startup_margin_lower", r6["startup_margin_lower"],
            ROW6_LIMITS["startup_margin_lower"], "dimensionless", err6, "6",
            {
                "samples": [round(v, 6) for v in ctrl6],
                "description": (
                    "Known-bad variant: campaign body with RTE 2k -> 4.4k (tail starved) run at "
                    "the SAME decision rung, N=100 per instrument, seed 244, seed_scope shared. "
                    "It must fail the rung (margin floor 1.0) where the campaign sustains it, so "
                    "its yield degrades visibly; a control unit that sustained the rung aborts "
                    "the assembly instead of grading."
                ),
            },
            [
                f"AC 4c sample set for klt yield, measurement startup_margin_lower, {instrument} "
                "instrument (issue #244). Per-sample LOWER bound on I_nom/I_threshold from the "
                "decision rung of the pilot's RREF ladder (evidence-r6-ladder-%s/report.json, "
                "I_tail measured from vte_avg/RTE): a die sustaining the rung reports its measured "
                "I_nom(die, from its own S2 unit)/I_tail(die at the rung); a die that fails it "
                "reports the floor 1.0 (measured to sustain at nominal tail in its own S2 unit). "
                "The declared criterion cannot resolve 3.0 inside the rung bracket, so samples "
                "between the floor and the rung's margin-equivalent grade conservatively as fail "
                "-- the reported yield is a lower bound on the true yield at 3.0. Oscillation "
                "criterion: t_cross_1 and t_cross_11 present AND vdiff peak-to-peak over 15-20 ns "
                ">= 0.1 V (the pilot's declared one). Vctrl 1.65 V, the pilot ladder's convention."
                % instrument,
            ],
        )
    return 0


def row6_ext_derive(instrument: str, tag: str, n: int) -> tuple[list[float], int, list[float]]:
    """The seed-245 extension draw (issue #244 AC 4e): the first mismatch draw
    (seed 244, N = 400) graded sample_size.verdict `insufficient`, and the plan
    extends with a NEW seed rather than arguing around. Same rung, same
    estimator; I_nom comes from the companion nominal-body request (same seed,
    same index -> the same die), because the original pairing source (the S2
    points) belongs to the seed-244 draw."""
    nom = load_units(HERE / f"evidence-r6-ladder-ext{tag}-nommis-{instrument}" / "report.json", (1.65,), n)
    ladder = load_units(HERE / f"evidence-r6-ladder-ext{tag}-{instrument}" / "report.json", (1.65,), n)
    control = load_units(HERE / f"evidence-r6-ladder-control-{instrument}" / "report.json", (1.65,), 100)

    samples, errored = [], 0
    for idx in range(n):
        if not oscillating(nom[(idx, 1.65)]):
            errored += 1
            continue
        if oscillating(ladder[(idx, 1.65)]):
            i_nom = nom[(idx, 1.65)].get("vte_avg")
            i_rung = ladder[(idx, 1.65)].get("vte_avg")
            if i_nom is None or i_rung is None or i_rung <= 0:
                errored += 1
                continue
            samples.append((i_nom / RTE_OHMS) / (i_rung / RTE_OHMS))
        else:
            samples.append(1.0)

    ctrl = []
    for idx in range(100):
        if oscillating(control[(idx, 1.65)]):
            raise SystemExit(
                f"{instrument}: known-bad control unit mc{idx} SUSTAINS the decision rung -- "
                "the rung does not separate the variant from the campaign."
            )
        ctrl.append(1.0)
    if len(samples) + errored != n:
        raise SystemExit(f"ext{tag}/{instrument}: {len(samples)} samples + {errored} errored != {n}")
    return samples, errored, ctrl


def ac4c_ext_main() -> int:
    tag, n = "245", 4200
    instrument = "mismatch"
    samples, errored, ctrl = row6_ext_derive(instrument, tag, n)
    write_sample_set(
        instrument, "startup_margin_lower", samples,
        ROW6_LIMITS["startup_margin_lower"], "dimensionless", errored, "6",
        {
            "samples": [round(v, 6) for v in ctrl],
            "description": (
                "Known-bad variant: campaign body with RTE 2k -> 4.4k (tail starved) run at "
                "the SAME decision rung, N=100, seed 244, seed_scope shared (the control is a "
                "discriminability self-check, not a sizing claim, so it is not re-drawn with "
                "the extension seed). It must fail the rung (margin floor 1.0) where the "
                "campaign sustains it; a control unit that sustained the rung aborts the "
                "assembly instead of grading."
            ),
        },
        [
            f"AC 4e extension sample set for klt yield, measurement startup_margin_lower, "
            f"{instrument} instrument, seed 245, N={n} (issue #244). The first mismatch draw "
            "(seed 244, N=400, yield-samples-mismatch-startup_margin_lower.json) graded "
            "sample_size.verdict `insufficient`; the plan extends with a new seed, never "
            "argues around. Same decision rung RREF 71k and estimator as the first draw "
            "(evidence-r6-ladder-ext245-%s/report.json; I_nom from the companion "
            "nominal-body request evidence-r6-ladder-ext245-nommis-%s/report.json, seed 245 "
            "+ seed_scope shared makes sample k the same die in both). A die sustaining the "
            "rung reports its measured I_nom/I_tail; a die that fails it reports the floor "
            "1.0 (measured to sustain at nominal tail). The reported yield is a conservative "
            "LOWER bound on the true yield at the 3.0 floor. Oscillation criterion: "
            "t_cross_1 and t_cross_11 present AND vdiff peak-to-peak over 15-20 ns >= 0.1 V. "
            "Vctrl 1.65 V, the pilot ladder's convention."
            % (instrument, instrument)
        ],
        out_name=f"startup_margin_lower-ext{tag}",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
