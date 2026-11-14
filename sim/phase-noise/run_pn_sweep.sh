#!/usr/bin/env bash
# GRADED row-10/11 phase-noise grid entry point (issue #53): the ISF estimator of
# run_isf_pilot.sh at every point of the 135-point corner set, on the batch fleet.
#
#   run_pn_sweep.sh                      # declare the grid, print the cost; runs nothing
#   run_pn_sweep.sh --list               # the 135 corners, one per line (PDK-free)
#   run_pn_sweep.sh --generate OUTDIR    # write the 135 per-corner requests + grid-plan.csv
#   run_pn_sweep.sh --submit OUTDIR      # submit them (needs PN_SWEEP_ACK_CPU_H >= the estimate)
#   run_pn_sweep.sh --reduce OUTDIR      # reduce the returned units -> OUTDIR/corners.csv
#   run_pn_sweep.sh --grade CORNERS.csv  # grade row 4 from a per-corner status table
#
# WHY ONE REQUEST PER CORNER. The impulse train's timing is baked into the PWL
# sources (a function of the carrier), and the carrier moves 4.1-4.3 GHz across the
# corner set, so each (process, temperature) needs its own deck: the per-corner
# carrier calibration the issue asks for, taken from the oscillator-core fleet grid's
# measured f_osc (Vctrl 1.65 V) rather than from a second pre-run. Where that grid had
# no oscillating unit (every 125 C point), the same process's 27 C carrier is used and
# the corner is marked f0_source=fallback-27C; the reducer measures the true carrier
# and records f0_grid_error_pct, and the grader refuses a corner whose n_plateau < 3.
#
# SPICE NEVER RUNS HERE. --submit goes to the Spot batch fleet (klt sim --batch-set,
# --backend batch, --wait-for-capacity 600). There is deliberately no local path.
#
# --reduce CLOSES THE LOOP (issue #329). It drives klt-sim/reduce_pn_grid.sh, which reduces
# each returned corner with the SAME estimator functions run_isf_pilot.sh uses -- each with
# its own carrier and impulse spacing out of grid-plan.csv, and its own port-noise points
# out of the grid noise job's per-corner results -- and writes the per-corner table
# --grade reads. A corner that cannot be reduced is listed with a non-pass status and its
# cause; none is dropped and none is given a number. No SPICE runs in --reduce either.
#
# GRADING RULE. Row 4 is graded only when all 135 corners are present, simulated and
# valid; anything else prints INCOMPLETE and grades nothing (grade_pn_grid.py).
#
# COST is derived, not asserted: units x tstop at the pilot's measured 11.19 ps of
# circuit time per wall-clock second (pn_bench.sh), printed before anything starts.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${HERE}/.." && pwd)"
GEN="${HERE}/klt-sim/gen_isf_request.py"
UNITS_CSV="${PN_SWEEP_F0_UNITS:-${SIM_DIR}/oscillator-core/records/20261105-152054-a6be03f-pvt-grid-units.csv}"
NPER="${PN_SWEEP_NPER:-9}"   # 9 => plateau 0.35*9.1 = 3.2 periods => n_plateau >= 3 (README)

plan() {  # print the declared grid + derived cost; $1 = dir to generate into
  python3 "${GEN}" --grid "${UNITS_CSV}" "$1" --nper "${NPER}"
}
estimate_cpu_h() { awk -F, 'NR>1 { s += $8 } END { printf "%.0f", s }' "$1/grid-plan.csv"; }

case "${1:-}" in
  --list)
    for m in tt ss ff sf fs; do for c in typ bcs wcs; do for h in typ bcs wcs; do
      for t in -40 27 125; do echo "${m}_${c}_${h} ${t}"; done; done; done; done ;;
  --generate)
    [[ -n "${2:-}" ]] || { echo "usage: $0 --generate OUTDIR" >&2; exit 2; }
    plan "$2"; echo "estimated cost: $(estimate_cpu_h "$2") CPU-h (grid-plan.csv)" ;;
  --submit)
    [[ -n "${2:-}" ]] || { echo "usage: $0 --submit OUTDIR  (OUTDIR from --generate)" >&2; exit 2; }
    [[ -f "$2/grid-plan.csv" ]] || { echo "error: $2/grid-plan.csv missing; run --generate first" >&2; exit 2; }
    EST="$(estimate_cpu_h "$2")"
    echo "about to submit $(( $(wc -l < "$2/grid-plan.csv") - 1 )) requests, ~${EST} CPU-h on the shared Spot fleet"
    [[ "${PN_SWEEP_ACK_CPU_H:-0}" -ge "${EST}" ]] || {
      echo "error: set PN_SWEEP_ACK_CPU_H=${EST} (or more) to acknowledge the cost; nothing submitted" >&2; exit 1; }
    mapfile -t REQS < <(find "$2" -name request-isf-post79.json | sort)
    klt sim --batch-set "${REQS[@]}" --max-in-flight 4 --capacity-retries 5 \
      --wait-for-capacity 600 --submit-only --format json | tee "$2/batch-receipt.json" ;;
  --reduce)
    [[ -n "${2:-}" ]] || { echo "usage: $0 --reduce OUTDIR  (OUTDIR from --generate, with returned evidence)" >&2; exit 2; }
    "${HERE}/klt-sim/reduce_pn_grid.sh" "$2" ;;
  --grade)
    [[ -n "${2:-}" ]] || { echo "usage: $0 --grade CORNERS.csv" >&2; exit 2; }
    python3 "${HERE}/grade_pn_grid.py" "$2" ;;
  "")
    T="$(mktemp -d /tmp/pn-sweep-plan.XXXXXX)"; trap 'rm -rf "${T}"' EXIT
    plan "${T}"
    echo "grid: 5 MOS x 3 MIM x 3 HBT x 3 T = 135 corners; impulse spacing ${NPER}.1 periods; 6 units/corner"
    echo "estimated cost: $(estimate_cpu_h "${T}") CPU-h of circuit time (pilot rate 11.19 ps/wall-s, one core)"
    echo "(the issue's ~108 CPU-h was the pre-#79, 3.1-period figure; see README 'graded grid')"
    echo "MEASURED ON THE FLEET (smoke, job klt-sim-1dfa416c0f4a): one 25.18 ns unit ran in 5.73 s wall,"
    echo "  i.e. ~4400 ps/s, ~400x the 11.19 ps/s local-contended constant above -> ~$(awk -v n=810 'BEGIN{printf "%.1f", n*5.73/3600}') CPU-h;"
    echo "  the binding cost is waveform volume (~300 MB/unit, ~240 GB for 810 units), not compute."
    echo "nothing was run. --generate OUTDIR, --submit OUTDIR, --reduce OUTDIR, --grade OUTDIR/corners.csv." ;;
  *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
esac
