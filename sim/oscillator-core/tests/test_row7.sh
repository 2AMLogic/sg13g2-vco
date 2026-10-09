#!/usr/bin/env bash
# PDK-free known-answer check of the ratified row-7 grade (DR-004 (d)/(e),
# issue #112): the sampled tail-minimum extractor, the per-point VCE_max and
# its sampling bound, the per-corner swing/compliance grader and the global
# bound-corner aggregation. Synthetic traces and CSV rows only; no simulator,
# no PDK. Prints one "PASS <name>" / "FAIL <name> (...)" line per assertion.
# Usage: tests/test_row7.sh [path/to/osc_bench.sh]  (default: ../osc_bench.sh)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH="${1:-${HERE}/../osc_bench.sh}"
# shellcheck source=../../lib.sh
source "${HERE}/../../lib.sh"
# shellcheck disable=SC1090
source "${BENCH}"
W="$(mktemp -d)"; trap 'rm -rf "${W}"' EXIT
FAIL=0
FULL="0.0 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0 3.3"
CSV_OUT="${W}/o.csv"; ROW7_CSV="${W}/r7.csv"

check() { if [[ "$2" == ok ]]; then echo "PASS $1"; else echo "FAIL $1 ($2)"; FAIL=1; fi; }
near() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(a != "nan" && a != "" && d <= t) }'; }
TWO_PI=6.283185307179586

# ======================================================================
# 1. Extractor: osc_trace_extrema reports the instantaneous minimum, which
#    for an asymmetric tail ripple is NOT mean - amplitude and NOT the mean.
#    v(t) = 2.66 + 0.1 cos(wt) + 0.03 cos(2wt), f = 10 GHz:
#    min at cos(wt) = -0.1/0.12 -> 2.66 - 0.0716667 = 2.5883333;
#    max at cos(wt) = 1 -> 2.79; trapezoidal mean 2.66.
# ======================================================================
awk -v tp="${TWO_PI}" 'BEGIN { for (i = 0; i <= 20000; i++) { t = i * 0.25e-12
  printf "%.9e %.9e\n", t, 2.66 + 0.1*cos(tp*1e10*t) + 0.03*cos(2*tp*1e10*t) } }' > "${W}/asym"
read -r vmin tmin vmax _tmax dtx n <<<"$(osc_trace_extrema "${W}/asym" 2.5e-9)"
near "${vmin}" 2.5883333 1e-5 && check extrema-asym-min ok || check extrema-asym-min "${vmin}"
near "${vmax}" 2.79 1e-6 && check extrema-asym-max ok || check extrema-asym-max "${vmax}"
read -r _f _vpp _c vmean _a _b _d _n <<<"$(osc_metrics "${W}/asym" 2.5e-9)"
near "${vmean}" 2.66 1e-5 && check extrema-asym-mean-is-not-min ok || check extrema-asym-mean-is-not-min "${vmean}"
awk -v a="${vmin}" -v m="${vmean}" 'BEGIN { exit !(m - a > 0.07) }' \
  && check extrema-min-distinct-from-mean ok || check extrema-min-distinct-from-mean "min ${vmin} mean ${vmean}"
near "${dtx}" 0.25e-12 1e-16 && check extrema-dtmax ok || check extrema-dtmax "${dtx}"
[[ "${n}" == 10001 ]] && check extrema-window-count ok || check extrema-window-count "${n}"
awk -v t="${tmin}" 'BEGIN { exit !(t >= 2.5e-9) }' && check extrema-window-respected ok || check extrema-window-respected "${tmin}"
# empty window -> nan, never 0
read -r vmin _r <<<"$(osc_trace_extrema "${W}/asym" 9e-9)"
[[ "${vmin}" == nan ]] && check extrema-empty-window-nan ok || check extrema-empty-window-nan "${vmin}"

# Sampling bound: coarse 7 ps steps with a phase offset step over the true
# minimum of 2.6 + 0.1 sin(wt + 0.3), f = 10 GHz (true min 2.5). The sampled
# minimum must sit ABOVE the true one by no more than
# A(1 - cos(pi f dt)) = 0.1 (1 - cos(0.2199)) = 2.4085e-3.
awk -v tp="${TWO_PI}" 'BEGIN { for (i = 0; i <= 714; i++) { t = i * 7e-12
  printf "%.9e %.9e\n", t, 2.6 + 0.1*sin(tp*1e10*t + 0.3) } }' > "${W}/coarse"
read -r vmin _t _vx _tx dtx _n <<<"$(osc_trace_extrema "${W}/coarse" 2.5e-9)"
bound="$(awk -v dt="${dtx}" 'BEGIN { print 0.1 * (1 - cos(3.141592653589793 * 1e10 * dt)) }')"
awk -v s="${vmin}" -v b="${bound}" 'BEGIN { e = s - 2.5; exit !(e >= 0 && e <= b && e > 0) }' \
  && check sampled-min-within-bound ok || check sampled-min-within-bound "sampled ${vmin} bound ${bound}"

# ======================================================================
# 2. osc_row7_point: VCE_max and its sampling-bound upper value.
#    vpp 1.0 V @ 5 GHz, dt 2 ps; tail ripple 0.2 V pk-pk @ 10 GHz, dt 2 ps;
#    V(TAIL)_min 2.4 V; VDD 3.3 V.
#    VCE = 3.3 + 0.25 - 2.4 = 1.15 V
#    vpp_err  = 1.0 (1 - cos(pi 5e9 2e-12))  = 4.9345e-4
#    tail_err = 0.1 (1 - cos(pi 1e10 2e-12)) = 1.9733e-4
#    upper    = 1.15 + vpp_err/4 + tail_err  = 1.1503207
# ======================================================================
read -r ev et vce vup <<<"$(osc_row7_point 1.0 5e9 2e-12 0.2 1e10 2e-12 2.4 3.3)"
near "${vce}" 1.15 1e-9 && check point-vce ok || check point-vce "${vce}"
near "${ev}" 4.9345e-4 1e-7 && check point-vpp-err ok || check point-vpp-err "${ev}"
near "${et}" 1.9733e-4 1e-7 && check point-tail-err ok || check point-tail-err "${et}"
near "${vup}" 1.1503207 1e-6 && check point-vce-upper ok || check point-vce-upper "${vup}"
# the bound uses max(f_tail, 2 f_osc): a tail measured at f_osc must not shrink it
read -r _ev et2 _v _u <<<"$(osc_row7_point 1.0 5e9 2e-12 0.2 5e9 2e-12 2.4 3.3)"
near "${et2}" "${et}" 1e-12 && check point-tail-freq-floor ok || check point-tail-freq-floor "${et2}"
# actual rail: the same swing/tail at a 3.63 V rail is 0.33 V worse
read -r _ev _et vce363 _u <<<"$(osc_row7_point 1.0 5e9 2e-12 0.2 1e10 2e-12 2.4 3.63)"
near "${vce363}" 1.48 1e-9 && check point-uses-actual-rail ok || check point-uses-actual-rail "${vce363}"
# missing measurements stay nan
read -r _ev _et vce _u <<<"$(osc_row7_point 1.0 5e9 2e-12 nan nan nan nan 3.3)"
[[ "${vce}" == nan ]] && check point-missing-tail-nan ok || check point-missing-tail-nan "${vce}"
read -r _ev _et vce _u <<<"$(osc_row7_point 1.0 5e9 2e-12 0.2 1e10 2e-12 2.4 nan)"
[[ "${vce}" == nan ]] && check point-missing-vdd-nan ok || check point-missing-vdd-nan "${vce}"
read -r ev _et _v vup <<<"$(osc_row7_point 0.3 0 2e-12 0.2 nan 2e-12 2.4 3.3)"
[[ "${ev}" == nan && "${vup}" == nan ]] && check point-no-osc-no-bound ok || check point-no-osc-no-bound "${ev} ${vup}"

# ======================================================================
# 3. Per-corner grader on synthetic 37-column rows.
# row <v> <status> <vpp> <vtmin> <vdd> [vtail_err] [vpp_err] [meas] [tmean]
# ======================================================================
row() {
  local te="${6:-0}" pe="${7:-0}" ms="${8:-VALID}" tm="${9:-2.7}"
  echo "c,m,c1,h,27,$1,${OSC_TMAX},$2,5e9,20,2e-12,0.1,0.1,$3,1e-9,0,0,0,0,1e10,2,2.5,${tm},0,0,0,0,${ms},-,$4,3e-9,0.1,${te},${pe},$5,0,0"
}
grid() { # grid <vpp> <vtmin> <vdd> [te] [pe] : every FULL point identical
  for v in ${FULL}; do row "${v}" PASS "$1" "$2" "$3" "${4:-0}" "${5:-0}"; done
}
run() { # run [vlist] ; rows on stdin
  { echo hdr; cat; } > "${CSV_OUT}"; : > "${ROW7_CSV}"
  osc_emit_row7 m c1 h 27 "${OSC_TMAX}" "${1:-${FULL}}"
}
col() { awk -F, -v c="$1" '{ print $c }' "${ROW7_CSV}"; }
verd() { awk -F, '{ print $19","$20","$21","$22","$23 }' "${ROW7_CSV}"; }
expect() { [[ "$(verd)" == "$2" ]] && check "$1" ok || check "$1" "got: $(verd) reason: $(col 24)"; }
ALLMET="MET,MET,MET,MET,MET"
INC="INCOMPLETE,INCOMPLETE,INCOMPLETE,INCOMPLETE,INCOMPLETE"

grid 0.8 2.5 3.3 | run
expect all-pass "${ALLMET}"
[[ "$(col 7),$(col 8)" == "10,5" ]] && check counts-domain-window ok || check counts-domain-window "$(col 7),$(col 8)"
near "$(col 11)" 1.0 1e-9 && check vce-recorded ok || check vce-recorded "$(col 11)"
near "$(col 14)" 3.3 1e-9 && check vdd-recorded ok || check vdd-recorded "$(col 14)"

# ---- tail ripple: the cycle minimum, not the mean, decides compliance.
# mean 2.70 V -> (3.3 + 0.25) - 2.70 = 0.85 V would pass; the minimum 1.30 V
# gives 2.25 V > 2.2 V: NOT MET, and the record carries both values.
{ for v in ${FULL}; do row "${v}" PASS 1.0 1.30 3.3 0 0 VALID 2.70; done; } | run
expect ripple-min-not-mean "MET,MET,NOT MET,NOT MET,NOT MET"
[[ "$(col 16)" == 1.3 && "$(col 17)" == 2.7 ]] && check ripple-min-and-mean-recorded ok \
  || check ripple-min-and-mean-recorded "min $(col 16) mean $(col 17)"

# ---- compliance boundary: (3.3 + 0.8/4) - 1.3 == 2.2 exactly in IEEE double.
grid 0.8 1.3 3.3 | run
expect boundary-exact-no-sampling-error "${ALLMET}"
# the same measured value with a nonzero sampling bound is NOT a pass
grid 0.8 1.3 3.3 1e-4 4e-4 | run
expect boundary-within-sampling-bound "MET,MET,WITHIN SAMPLING BOUND,WITHIN SAMPLING BOUND,WITHIN SAMPLING BOUND"
# clearly under the limit even at the upper value: MET
grid 0.8 1.31 3.3 1e-4 4e-4 | run
expect boundary-under-by-more-than-bound "${ALLMET}"
# 0.1 mV over: NOT MET
grid 0.8 1.2999 3.3 | run
expect boundary-just-over "MET,MET,NOT MET,NOT MET,NOT MET"
# actual rail: passes at 3.3 V, fails at a 3.63 V rail (VCE 1.9 -> 2.23 V)
grid 0.8 1.6 3.3 | run
expect rail-3v3 "${ALLMET}"
grid 0.8 1.6 3.63 | run
expect rail-3v63 "MET,MET,NOT MET,NOT MET,NOT MET"
# compliance is graded over the FULL domain: an over-limit point at 0.0 V,
# outside W, still fails the corner
{ row 0.0 PASS 0.8 1.2 3.3; for v in 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0 3.3; do row "${v}" PASS 0.8 2.5 3.3; done; } | run
expect compliance-outside-window "MET,MET,NOT MET,NOT MET,NOT MET"
[[ "$(col 13)" == 0.0 ]] && check worst-vctrl-recorded ok || check worst-vctrl-recorded "$(col 13)"

# ---- insufficient swing (graded over W only)
{ for v in ${FULL}; do if [[ "${v}" == 2.4 ]]; then row "${v}" PASS 0.39 2.5 3.3; else row "${v}" PASS 0.8 2.5 3.3; fi; done; } | run
expect swing-under-target "NOT MET,NOT MET,MET,NOT MET,NOT MET"
[[ "$(col 9),$(col 10)" == "0.39,2.4" ]] && check swing-min-located ok || check swing-min-located "$(col 9),$(col 10)"
{ for v in ${FULL}; do if [[ "${v}" == 3.3 ]]; then row "${v}" PASS 0.5 2.5 3.3; else row "${v}" PASS 0.8 2.5 3.3; fi; done; } | run
expect swing-target-not-stretch "MET,NOT MET,MET,MET,NOT MET"
grid 0.40 2.5 3.3 | run
expect swing-at-target-bound "MET,NOT MET,MET,MET,NOT MET"
grid 0.65 2.5 3.3 | run
expect swing-at-stretch-bound "${ALLMET}"
# small swing OUTSIDE W does not grade row-7 swing
{ row 0.0 PASS 0.30 2.5 3.3; for v in 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0 3.3; do row "${v}" PASS 0.8 2.5 3.3; done; } | run
expect swing-outside-window-ignored "${ALLMET}"
# a non-oscillating window point is a measured swing failure, never a pass
grid 0.8 2.5 3.3 | sed 's/,1.8,\([^,]*\),PASS,/,1.8,\1,NOSC,/' | run
[[ "$(col 19)" == "NOT MET" && "$(col 22)" == "NOT MET" ]] && check nosc-in-window ok || check nosc-in-window "$(verd)"

# ---- missing / invalid / incomplete data never passes
grid 0.8 2.5 3.3 | grep -v ',2.4,' | run;  expect missing-window-point "${INC}"
grid 0.8 2.5 3.3 | grep -v ',0.0,' | run;  expect missing-domain-point "${INC}"
grid 0.8 2.5 3.3 | grep -v '^c,m,c1,h,27,3.3,' | run; expect missing-hi-endpoint "${INC}"
{ grid 0.8 2.5 3.3; row 2.4 PASS 0.8 2.5 3.3; } | run; expect duplicate "${INC}"
{ grid 0.8 2.5 3.3; row 2.0 PASS 0.8 2.5 3.3; } | run; expect unexpected-voltage "${INC}"
grid 0.8 2.5 3.3 | sed '3s/,VALID,-,/,INVALID,vtail:truncated,/' | run; expect invalid-truncated-trace "${INC}"
grid 0.8 2.5 3.3 | sed '4s/,PASS,/,FAIL,/' | run; expect simulator-fail "${INC}"
grid 0.8 2.5 3.3 | sed '5s/,PASS,/,NODATA,/' | run; expect nodata "${INC}"
grid 0.8 2.5 3.3 | sed '6s/,-,2.5,/,-,nan,/' | run; expect tail-min-nan "${INC}"
grid 0.8 2.5 3.3 | sed '6s/,3.3,0,0$/,nan,0,0/' | run; expect vdd-nan "${INC}"
grid 0.8 2.5 3.3 | cut -d, -f1-29 | run; expect legacy-29-column-record "${INC}"
grid 0.8 2.5 3.3 | grep -v ',1.8,' | run "0.0 0.3 0.6 0.9 1.2 1.65 2.4 3.0 3.3"
expect four-window-samples "${INC}"
grid 0.8 2.5 3.3 | run "0.0 0.3 0.6 0.9 1.2 1.8 2.4 3.0 3.3"
expect list-without-lo-endpoint "${INC}"
# a coarser-tmax repeat is ignored, not a duplicate
{ grid 0.8 2.5 3.3; row 2.4 PASS 0.1 2.5 3.3 | sed "s/,${OSC_TMAX},/,5p,/"; } | run
expect coarse-tmax-ignored "${ALLMET}"
osc_emit_row7 m c1 h 27 "${OSC_TMAX}" 2>/dev/null && check list-required bad || check list-required ok
( unset ROW7_CSV; osc_emit_row7 m c1 h 27 "${OSC_TMAX}" "${FULL}" ) && check no-csv-noop ok || check no-csv-noop bad

# ======================================================================
# 4. End to end through the real osc_simulate_point with stubbed simulator:
#    a tail ripple whose minimum differs from its mean, a constant 3.63 V
#    rail, and a truncated trace.
# ======================================================================
# shellcheck disable=SC2034  # EXPERIMENT_DIR is read by the sourced osc_simulate_point
WORKDIR="${W}/work"; NETLIST_DIR="${W}/net"; LOG_DIR="${W}/log"; EXPERIMENT_DIR="${W}"
mkdir -p "${WORKDIR}" "${NETLIST_DIR}" "${LOG_DIR}"
# shellcheck disable=SC2034  # read by osc_render's sed (stubbed here)
RECORD_ID="fixture"
osc_render() { : > "$2"; }
osc_run_ngspice() { : > "$2"; echo "rc=0 model_error=0"; }
TAIL_KIND=ok
gen_point() { # gen_point <prefix>: vdiff 1.0 V pk-pk @ 5 GHz; tail mean 2.0 + asym ripple; vdd 3.63
  local p="${WORKDIR}/$1"
  awk -v tp="${TWO_PI}" -v k="${TAIL_KIND}" -v P="${p}" 'BEGIN {
    last = (k == "truncated") ? 3000 : 5000
    for (i = 0; i <= 5000; i++) { t = i * 1e-12
      printf "%.9e %.9e\n", t, 0.5*sin(tp*5e9*t) > (P "_vdiff")
      printf "%.9e %.9e\n", t, 0.005*sin(tp*1e10*t) > (P "_vcm")
      if (i <= last) printf "%.9e %.9e\n", t, 2.0 + 0.1*cos(tp*1e10*t) + 0.03*cos(2*tp*1e10*t) > (P "_vtail")
      printf "%.9e %.9e\n", t, 1.0e-3 > (P "_isup")
      printf "%.9e %.9e\n", t, 3.63 > (P "_vdd")
    } }'
}
: > "${CSV_OUT}"; osc_write_csv_headers
for v in ${FULL}; do
  gen_point "tr_e2e_${v}"
  osc_simulate_point "e2e_${v}" m c1 h 27 "${v}" "${OSC_TMAX}" >/dev/null || true
done
: > "${ROW7_CSV}"; osc_emit_row7 m c1 h 27 "${OSC_TMAX}" "${FULL}"
# tail min = 2.0 - 0.0716667 = 1.9283333; VCE = 3.63 + 0.25 - 1.9283333 = 1.9516667
near "$(col 16)" 1.9283333 2e-4 && check e2e-tail-cycle-min ok || check e2e-tail-cycle-min "$(col 16)"
near "$(col 17)" 2.0 1e-4 && check e2e-tail-mean-separate ok || check e2e-tail-mean-separate "$(col 17)"
near "$(col 14)" 3.63 1e-9 && check e2e-actual-rail ok || check e2e-actual-rail "$(col 14)"
near "$(col 11)" 1.9516667 3e-4 && check e2e-vce ok || check e2e-vce "$(col 11)"
awk -v a="$(col 12)" -v b="$(col 11)" 'BEGIN { exit !(a > b) }' && check e2e-upper-above-measured ok || check e2e-upper-above-measured "$(col 12) vs $(col 11)"
expect e2e-grade "${ALLMET}"
# the same point set with one truncated tail trace
osc_write_csv_headers
for v in ${FULL}; do
  TAIL_KIND=ok; [[ "${v}" == 1.8 ]] && TAIL_KIND=truncated
  gen_point "tr_e2e_${v}"
  osc_simulate_point "e2e_${v}" m c1 h 27 "${v}" "${OSC_TMAX}" >/dev/null || true
done
: > "${ROW7_CSV}"; osc_emit_row7 m c1 h 27 "${OSC_TMAX}" "${FULL}"
expect e2e-truncated-trace "${INC}"
[[ "$(col 24)" == *"vtail:truncated"* ]] && check e2e-truncated-reason ok || check e2e-truncated-reason "$(col 24)"

# ======================================================================
# 5. Global aggregation over the declared required (bound) corners.
# ======================================================================
H="$(osc_row7_header)"
line() { # line <mos> <cap> <target> <stretch> <compliance>
  echo "$1,$2,hbt_wcs,125,1.65,3.3,10,5,0.8,1.65,1.0,1.0002,0.0,3.3,0.8,2.5,2.7,2.5,MET,$4,$5,$3,$4,-"
}
REQ="ss:cap_bcs:hbt_wcs:125 ss:cap_wcs:hbt_wcs:125 ff:cap_bcs:hbt_wcs:125"
S="${W}/s.csv"
{ echo "${H}"; line ss cap_bcs MET MET MET; line ss cap_wcs MET MET MET; line ff cap_bcs MET MET MET; } > "${S}"
out="$(osc_row7_summary "${S}" "${REQ}")"
[[ "${out}" == "STAGE-1 MET (target and stretch)"* && "${out}" == *"stage-2"* ]] && check summary-complete ok || check summary-complete "${out}"
[[ "${out}" != MET* ]] && check summary-never-bare-met ok || check summary-never-bare-met "${out}"
{ echo "${H}"; line ss cap_bcs MET MET MET; line ss cap_wcs MET "NOT MET" MET; line ff cap_bcs MET MET MET; } > "${S}"
out="$(osc_row7_summary "${S}" "${REQ}")"
[[ "${out}" == "STAGE-1 MET (target); stretch NOT MET"* ]] && check summary-stretch-miss ok || check summary-stretch-miss "${out}"
{ echo "${H}"; line ss cap_bcs MET MET MET; line ss cap_wcs "NOT MET" "NOT MET" "NOT MET"; line ff cap_bcs MET MET MET; } > "${S}"
out="$(osc_row7_summary "${S}" "${REQ}")"
[[ "${out}" == "NOT MET:"* ]] && check summary-one-corner-fails ok || check summary-one-corner-fails "${out}"
{ echo "${H}"; line ss cap_bcs MET MET MET; line ff cap_bcs MET MET MET; line tt cap_typ MET MET MET; } > "${S}"
out="$(osc_row7_summary "${S}" "${REQ}")"
[[ "${out}" == "NOT GRADED (partial)"*"1 missing"* ]] && check summary-missing-corner ok || check summary-missing-corner "${out}"
{ echo "${H}"; line ss cap_bcs MET MET MET; line ss cap_wcs INCOMPLETE INCOMPLETE INCOMPLETE; line ff cap_bcs MET MET MET; } > "${S}"
out="$(osc_row7_summary "${S}" "${REQ}")"
[[ "${out}" == "NOT GRADED (partial)"*"1 INCOMPLETE"* ]] && check summary-incomplete-corner ok || check summary-incomplete-corner "${out}"
WSB="WITHIN SAMPLING BOUND"
{ echo "${H}"; line ss cap_bcs MET MET MET; line ss cap_wcs "${WSB}" "${WSB}" "${WSB}"; line ff cap_bcs MET MET MET; } > "${S}"
out="$(osc_row7_summary "${S}" "${REQ}")"
[[ "${out}" == "NOT MET:"*"1 within sampling bound, not a pass"* ]] && check summary-sampling-bound-corner ok || check summary-sampling-bound-corner "${out}"
{ echo "${H}"; line ss cap_bcs MET MET MET; line ss cap_bcs MET MET MET; line ss cap_wcs MET MET MET; line ff cap_bcs MET MET MET; } > "${S}"
out="$(osc_row7_summary "${S}" "${REQ}")"
[[ "${out}" == "NOT GRADED (partial)"*"1 duplicated"* ]] && check summary-duplicate ok || check summary-duplicate "${out}"
out="$(osc_row7_summary "${S}" "")"
[[ "${out}" == "NOT GRADED"* ]] && check summary-no-required ok || check summary-no-required "${out}"
out="$(osc_row7_summary "${W}/absent.csv" "${REQ}")"
[[ "${out}" == "NOT GRADED"* ]] && check summary-no-csv ok || check summary-no-csv "${out}"

exit "${FAIL}"
