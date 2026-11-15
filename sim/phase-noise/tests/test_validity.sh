#!/usr/bin/env bash
# Simulator-free fixture for phase-noise measurement validity (issue #137):
# pn_verdict, pn_is_finite, pn_gamma_stats, pn_inoise_from_log and
# pn_reduce_ensemble on synthetic inputs. Prints PASS/FAIL lines. No ngspice.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${HERE}/../.." && pwd)"
# shellcheck source=../../lib.sh
source "${SIM_DIR}/lib.sh"
# shellcheck source=../pn_bench.sh
source "${SIM_DIR}/phase-noise/pn_bench.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
expect() { # name got want
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1: got '$2' want '$3'"; fi
}

# ---- pn_verdict -------------------------------------------------------------
# The reproduced defect: NaN and -inf were reported as meeting target+stretch.
expect "regression pn_verdict NaN -105 -115" "$(pn_verdict NaN -105 -115)" UNDETERMINED
for v in NaN nan NAN +nan -nan inf -inf Inf -Inf INF +inf infinity -Infinity 1e999 -1e999 \
         "" " " abc 1x 1,5 -- 0x10 1e 1e+ . - + "1 2"; do
  expect "pn_verdict value '${v}'" "$(pn_verdict "${v}" -105 -115)" UNDETERMINED
done
expect "pn_verdict NaN target" "$(pn_verdict -120 NaN -115)" UNDETERMINED
expect "pn_verdict inf stretch" "$(pn_verdict -120 -105 -inf)" UNDETERMINED
expect "pn_verdict no args" "$(pn_verdict)" UNDETERMINED
# valid pass / miss boundaries stay successful measurements
expect "verdict well below stretch" "$(pn_verdict -120 -105 -115)" "TARGET AND STRETCH BOTH MET"
expect "verdict exactly at stretch" "$(pn_verdict -115 -105 -115)" "TARGET AND STRETCH BOTH MET"
expect "verdict just above stretch" "$(pn_verdict -114.999 -105 -115)" "TARGET MET / STRETCH NOT MET"
expect "verdict exactly at target" "$(pn_verdict -105 -105 -115)" "TARGET MET / STRETCH NOT MET"
expect "verdict just above target" "$(pn_verdict -104.999 -105 -115)" "TARGET NOT MET"
expect "verdict exponent form" "$(pn_verdict -1.2e2 -1.05e2 -1.15e2)" "TARGET AND STRETCH BOTH MET"
expect "verdict far miss" "$(pn_verdict 50 -105 -115)" "TARGET NOT MET"

# ---- pn_is_finite -----------------------------------------------------------
for v in 0 -1 +2.5 .5 5. 1e-9 -3.2E+12 4e-15; do
  if pn_is_finite "${v}"; then pass "finite '${v}'"; else fail "finite '${v}' rejected"; fi
done
for v in nan NaN inf -Inf "" x 1e999 1..2 0x1; do
  if pn_is_finite "${v}"; then fail "non-finite '${v}' accepted"; else pass "non-finite '${v}' rejected"; fi
done

# ---- pn_gamma_stats ---------------------------------------------------------
# cos ISF sampled at 8 uniform phases, Gq_peak = 2: rms = sqrt(2).
good="${T}/good.gamma"
awk 'BEGIN{ PI=4*atan2(1,1); for (i=0;i<8;i++){ p=2*PI*i/8; printf "%.10f %.10e\n", p, 2*cos(p) } }' > "${good}"
read -r rt _ _ _ _ _ _ ng <<<"$(pn_gamma_stats "${good}")"
if awk -v r="${rt}" 'BEGIN{ d=r-sqrt(2); exit (d<1e-6 && d>-1e-6) ? 0 : 1 }' && [[ "${ng}" == 8 ]]; then
  pass "gamma_stats known answer rms=sqrt2, n=8"; else fail "gamma_stats known answer: ${rt} ${ng}"; fi
for bad in "NaN 1.0" "0.5 NAN" "0.5 inf" "0.5 -Inf" "0.5 abc" "0.5 1e999" "0.5" "0.5 1.0 9"; do
  { cat "${good}"; echo "${bad}"; } > "${T}/bad.gamma"
  out="$(pn_gamma_stats "${T}/bad.gamma")"
  expect "gamma_stats rejects line '${bad}'" "${out%% *}" nan
done
head -3 "${good}" > "${T}/short.gamma"
expect "gamma_stats too few phases" "$(pn_gamma_stats "${T}/short.gamma" | cut -d' ' -f1)" nan
: > "${T}/empty.gamma"
expect "gamma_stats empty file" "$(pn_gamma_stats "${T}/empty.gamma" | cut -d' ' -f1)" nan

# ---- pn_inoise_from_log (noise-spectrum reducer) ----------------------------
mklog() { # file row...
  local f="$1"; shift
  { echo "Index   frequency       inoise_spectrum"; echo "-----------------------------"
    local i=0 r; for r in "$@"; do echo "${i}	${r}"; i=$((i+1)); done; echo; } > "${f}"
}
mklog "${T}/n_ok.log" "3e9 2e-11" "6e9 4e-11" "9e9 3e-11"
expect "inoise median of valid spectrum" "$(pn_inoise_from_log "${T}/n_ok.log")" "3.00000000e-11"
for bad in "nan" "NaN" "-nan" "inf" "-inf" "1e999" "0" "-1e-11" "1.2.3" "abc"; do
  mklog "${T}/n_bad.log" "3e9 2e-11" "6e9 ${bad}" "9e9 3e-11"
  expect "inoise rejects value '${bad}'" "$(pn_inoise_from_log "${T}/n_bad.log")" nan
done
mklog "${T}/n_badf.log" "NaN 2e-11" "6e9 4e-11"
expect "inoise rejects non-finite frequency" "$(pn_inoise_from_log "${T}/n_badf.log")" nan
echo "no table here" > "${T}/n_none.log"
expect "inoise missing spectrum" "$(pn_inoise_from_log "${T}/n_none.log")" nan

# ---- pn_reduce_ensemble -----------------------------------------------------
HDR="port,realization,dq_c,f0_hz,vpp_diff_v,gq_rms_trapz,gq_rms_sample,c0,c1,c2,c3,max_phase_gap_rad,n_phases,null_floor_s,n_crossings_unmatched,l_1mhz_dbc,l_10mhz_dbc"
# row <port> <idx> [gq] [nph] [l1] [l10]
row() { echo "$1,$2,4e-15,6e9,0.9,${3-1.3e13},1.3e13,1e11,1.9e13,1e11,1e11,0.6,${4:-10},1e-15,0,${5:--102.0},${6:--122.0}"; }
ens() { { echo "${HDR}"; cat; } > "${T}/real.csv"; }
reduce() { pn_reduce_ensemble "${T}/real.csv" 4 1 10 2>"${T}/err"; }

{ row tank 1 1.0e13 10 -100 -120; row tank 2 2.0e13 10 -104 -124; row tank 3 3.0e13 10 -102 -122
  row tank 4 4.0e13 10 -98 -118; row tail 1; } | ens
out="$(reduce)"; rc=$?
expect "reduce valid ensemble exits 0" "${rc}" 0
expect "reduce known-answer stats" "${out}" "2.500000e+13 1.290994e+13 4 -101.0000 2.5820 -104.0000 -98.0000 -121.0000 2.5820"

# a valid finite target MISS is still a successful measurement
{ for i in 1 2 3 4; do row tank "${i}" 1.3e13 10 -60 -80; done; row tail 1; } | ens
out="$(reduce)"; rc=$?
expect "reduce valid target-miss ensemble exits 0" "${rc}" 0
expect "valid miss verdict" "$(pn_verdict "$(echo "${out}" | cut -d' ' -f4)" -105 -115)" "TARGET NOT MET"

# mixed valid/invalid realizations: no statistics, offender named
for bad in nan NaN NAN inf -Inf 1e999 abc "" 0 -1e13; do
  { row tank 1; row tank 2 "${bad}"; row tank 3; row tank 4; row tail 1; } | ens
  out="$(reduce)"; rc=$?
  if [[ "${rc}" -ne 0 && -z "${out}" ]] && grep -q "tank r2" "${T}/err"; then
    pass "reduce rejects gq '${bad}' and names tank r2"; else fail "reduce gq '${bad}': rc=${rc} out='${out}'"; fi
done
{ row tank 1; row tank 2 1.3e13 10 NaN; row tank 3; row tank 4; row tail 1; } | ens
out="$(reduce)"; rc=$?
if [[ "${rc}" -ne 0 && -z "${out}" ]] && grep -q "tank r2.*l_1mhz_dbc" "${T}/err"; then
  pass "reduce rejects NaN L(1 MHz)"; else fail "reduce NaN L: rc=${rc}"; fi
{ row tank 1; row tank 2 1.3e13 10 -102 -inf; row tank 3; row tank 4; row tail 1; } | ens
if ! reduce >/dev/null && grep -q "l_10mhz_dbc" "${T}/err"; then
  pass "reduce rejects -inf L(10 MHz)"; else fail "reduce -inf L10"; fi
# port failure named as tail
{ row tank 1; row tank 2; row tank 3; row tank 4; row tail 1 nan; } | ens
if ! reduce >/dev/null && grep -q "tail r1" "${T}/err"; then
  pass "reduce names failing tail port"; else fail "reduce tail failure"; fi
# incomplete ISF coverage (a dropped impulse)
{ row tank 1; row tank 2 1.3e13 9; row tank 3; row tank 4; row tail 1; } | ens
if ! reduce >/dev/null && grep -q "tank r2.*9 phases" "${T}/err"; then
  pass "reduce rejects incomplete ISF phase coverage"; else fail "reduce phase coverage"; fi
# incomplete ensembles
{ row tank 1; row tank 2; row tank 3; row tail 1; } | ens
if ! reduce >/dev/null && grep -q "tank r4: missing" "${T}/err"; then
  pass "reduce rejects missing tank realization"; else fail "reduce missing tank"; fi
{ row tank 1; row tank 2; row tank 3; row tank 4; } | ens
if ! reduce >/dev/null && grep -q "tail r1: missing" "${T}/err"; then
  pass "reduce rejects missing tail realization"; else fail "reduce missing tail"; fi
{ row tank 1; row tank 1; row tank 2; row tank 3; row tank 4; row tail 1; } | ens
if ! reduce >/dev/null && grep -q "duplicate" "${T}/err"; then
  pass "reduce rejects duplicate realization"; else fail "reduce duplicate"; fi
echo "tank,1,4e-15,6e9" > "${T}/short_row"; { cat "${T}/short_row"; row tank 2; row tank 3; row tank 4; row tail 1; } | ens
if ! reduce >/dev/null && grep -q "tank r1: incomplete row" "${T}/err"; then
  pass "reduce rejects truncated row"; else fail "reduce truncated row"; fi
echo "" | ens
if ! reduce >/dev/null; then pass "reduce rejects header-only CSV"; else fail "reduce header-only"; fi
if ! pn_reduce_ensemble "${T}/nonexistent.csv" 4 1 10 2>/dev/null >&2; then
  pass "reduce rejects missing CSV"; else fail "reduce missing CSV"; fi

# known answer on the committed historical pilot record (read-only)
rec="$(ls "${SIM_DIR}"/phase-noise/records/*-pilot-realizations.csv 2>/dev/null | head -1)"
if [[ -n "${rec}" ]]; then
  expect "reduce historical pilot record unchanged" "$(pn_reduce_ensemble "${rec}" 4 1 10)" \
    "1.329958e+13 4.596977e+11 4 -102.2763 0.2953 -102.4447 -101.8343 -122.2763 0.2953"
fi

# ---- pn_summary_rows_common: the 27-row column contract (issue #346) --------
# pn_bench.sh leaves the mid/tail arm variables to a measurement run; bind
# sentinels so set -u does not trip on them during the section dispatch.
# shellcheck disable=SC2034  # read by pn_summary_rows_common (pn_bench.sh)
F0_MEAS=6.0e9 VPP_MEAS=0.9 SI_TANK=1e-24 SI_TAIL=1e-26 \
NOISE_FLAT_TANK=1.0 NOISE_FLAT_TAIL=1.0 GQ_MEAN=1.3e13 GQ_SD=4.6e11 GQ_N=4 \
GQ_TAIL=1.3e12 LINEARITY_PCT=2.0 L1_MEAN=-102.3 L1_SD=0.30 L1_MIN=-102.4 \
L1_MAX=-101.8 L10_MEAN=-122.3 L10_SD=0.30 L1_TAIL=-118.1 PORT_RATIO_DB=16 \
IND_BAR_Q_DB=0.50 IND_BAR_FIT_DB=0.10 IND_BAR_DB=0.51

# An unrecognized section name must fail loudly: the summary rows are
# append-only published evidence, so a silently-empty section that exits 0
# would publish a truncated record while the driver reports success.
out="$(pn_summary_rows_common taill mos cap hbt 25 3.3 rail 2>"${T}/summary-unknown.err")"; rc=$?
expect "summary unknown section rc" "${rc}" 1
expect "summary unknown section stdout empty" "${out}" ""
# The valid-set grep reads PN_SUMMARY_SECTIONS, so pin its presence first:
# set -u does not flag "${arr[*]}" on an unset array, and the empty
# expansion would turn that grep into a vacuous match on any stderr.
if [[ -z "${PN_SUMMARY_SECTIONS[*]+x}" ]]; then
  fail "summary section list: PN_SUMMARY_SECTIONS is not set by pn_bench.sh"
elif grep -q "unknown section 'taill'" "${T}/summary-unknown.err" \
   && grep -qF "${PN_SUMMARY_SECTIONS[*]}" "${T}/summary-unknown.err"; then
  pass "summary unknown section names the bad section and the valid set"
else
  fail "summary unknown section stderr: $(cat "${T}/summary-unknown.err")"
fi

out="$(pn_summary_rows_common "" 2>"${T}/summary-empty.err")"; rc=$?
expect "summary empty section rc" "${rc}" 1
expect "summary empty section stdout empty" "${out}" ""

# No argument at all: "${1}" trips set -u before the case dispatches. That
# abort is the landed behaviour -- assert it stays loud, not silent.
out="$(pn_summary_rows_common 2>"${T}/summary-noarg.err")"; rc=$?
expect "summary no-argument rc" "${rc}" 1
expect "summary no-argument stdout empty" "${out}" ""
if grep -q "unbound variable" "${T}/summary-noarg.err"; then
  pass "summary no-argument trips set -u on \${1}"
else
  fail "summary no-argument stderr: $(cat "${T}/summary-noarg.err")"
fi

# Row counts are the published column contract: 6 / 2 / 19 rows, 27 total.
# The name list comes from pn_bench.sh's PN_SUMMARY_SECTIONS (the one place
# the valid names are stated); counts is parallel to it. Guard the list's
# presence with the + alternate form before any other dereference: set -u
# does flag "${#arr[@]}" on an unset array, and without set -e (this
# fixture's mode) that error abandons the whole if compound without taking
# either branch -- no fail, no assertions, exit 0. It does not flag the
# + form, so the first arm runs and fails loudly instead.
counts=(6 2 19)
if [[ -z "${PN_SUMMARY_SECTIONS[*]+x}" ]]; then
  fail "summary section list: PN_SUMMARY_SECTIONS is not set by pn_bench.sh"
elif [[ "${#PN_SUMMARY_SECTIONS[@]}" -ne "${#counts[@]}" ]]; then
  fail "summary section list: got ${#PN_SUMMARY_SECTIONS[@]} name(s), want ${#counts[@]}"
else
  for i in "${!PN_SUMMARY_SECTIONS[@]}"; do
    s="${PN_SUMMARY_SECTIONS[i]}"
    if [[ "${s}" == head ]]; then
      n="$(pn_summary_rows_common "${s}" mos cap hbt 25 3.3 "supply rail simulated" | wc -l)"
    else
      n="$(pn_summary_rows_common "${s}" | wc -l)"
    fi
    expect "summary rows ${s}" "${n}" "${counts[i]}"
  done
fi

if [[ "${fails}" -ne 0 ]]; then echo "${fails} check(s) failed"; exit 1; fi
echo "all cases passed"
