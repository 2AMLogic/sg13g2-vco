#!/usr/bin/env bash
# Simulator-free known-answer fixture for the 135-corner ISF reduction driver (issue #329):
# run_pn_sweep.sh --reduce over a SYNTHETIC returned-grid directory. No ngspice, no PDK, no
# fleet. Prints PASS/FAIL lines and "all cases passed".
#
# The complete corner is a KNOWN ANSWER, not a round trip. Its six traces are built from a
# first-order ISF model -- Gamma(theta) = G0*cos(theta), so impulse k shifts the carrier's
# phase permanently by G0*cos(theta_k)*dq -- written out as a plain phase-modulated sine.
# Nothing in the fixture computes L(df); the reducer has to recover G0 from crossing-time
# shifts against the reference trace and arrive at
#     L(df) = (G0/sqrt2)^2 * Si / (2*(2*pi*df)^2),
# which is evaluated independently below. A fixture that built both halves from one payload
# could only prove the two halves agree.
#
# Covered, per the issue's AC 4 (a corner is never dropped and never given a number it did
# not earn): one complete corner, one whose ensemble came back short, one with an invalid
# (non-finite) trace, one whose port-noise value cannot be resolved, and one with no
# returned evidence at all.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PN="$(cd "${HERE}/.." && pwd)"
SWEEP="${PN}/run_pn_sweep.sh"
REDUCER="${PN}/klt-sim/reduce_isf_fleet.sh"
GRADER="${PN}/grade_pn_grid.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
has() { if grep -q -- "$3" <<<"$2"; then pass "$1"; else fail "$1: no '$3' in: $(head -c 400 <<<"$2")"; fi; }
hasnt() { if grep -q -- "$3" <<<"$2"; then fail "$1: unexpected '$3'"; else pass "$1"; fi; }
eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1: got '$2', want '$3'"; fi; }
ne() { if [[ "$2" != "$3" ]]; then pass "$1"; else fail "$1: '$2' should differ from '$3'"; fi; }
near() { if awk -v a="$2" -v b="$3" -v tol="$4" 'BEGIN { d = a - b; if (d < 0) d = -d; exit (d <= tol) ? 0 : 1 }'; then
           pass "$1"; else fail "$1: got '$2', want '$3' +-'$4'"; fi; }

# ---- the fixture's declared method constants (also used for the analytic answer) -------
F0=4.2e9; NPER=9; G0_TANK=1.4e13; G0_TAIL=5e12; SI_TANK=5.6e-12; SI_TAIL=9.4e-12

# ---- build a synthetic returned grid ---------------------------------------------------
cat > "${T}/build.py" <<'PY'
"""Write a synthetic run_pn_sweep.sh --generate OUTDIR with returned fleet evidence."""
import json, math, sys
from pathlib import Path

OUT = Path(sys.argv[1])
F0, NPER, G0_TANK, G0_TAIL = float(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
SI_TANK, SI_TAIL = float(sys.argv[6]), float(sys.argv[7])
N_IMP, T1, AMP, STEP, VCT = 10, 3.5e-9, 0.3, 2e-12, 1.65
NPTS, FSTART, FSTOP = 7, 3e9, 9e9
DT = (NPER + 1.0 / N_IMP) / F0
TSTOP = T1 + N_IMP * DT
IMP_T = [T1 + k * DT for k in range(N_IMP)]
# (dqd, dqt) exactly as gen_isf_request.py rows them, and as the reducer's PN_*_DQ_LIST
# spells them -- the .dat filenames are built from these strings.
UNITS = [("0", "0"), ("4e-15", "0"), ("-4e-15", "0"), ("8e-15", "0"), ("-8e-15", "0"), ("0", "4e-15")]
# process, temp_c, f0_source, fault
CORNERS = [
    ("tt_typ_typ", 27, "oscillator-core-fleet-grid", None),
    ("ss_bcs_wcs", -40, "oscillator-core-fleet-grid", "short_ensemble"),
    ("ff_wcs_typ", 125, "fallback-27C", "nan_trace"),
    ("sf_typ_bcs", 27, "oscillator-core-fleet-grid", "no_noise"),
    ("fs_bcs_typ", -40, "oscillator-core-fleet-grid", "no_evidence"),
]


def trace(dqd, dqt, poison=False):
    """A phase-modulated sine: each impulse adds G0*cos(theta_k)*dq of permanent phase."""
    g = G0_TANK * float(dqd) + G0_TAIL * float(dqt)
    steps = [(t, g * math.cos(2 * math.pi * F0 * t)) for t in IMP_T]
    w, pts = 2 * math.pi * F0, []
    for i in range(int(TSTOP / STEP) + 1):
        t = i * STEP
        phi = sum(s for (tk, s) in steps if t >= tk)
        pts.append([t, AMP * math.sin(w * t + phi)])
    if poison:
        pts[len(pts) // 2][1] = float("nan")
    return pts


def unit_dir(ev, proc, temp, dqd, dqt, poison):
    slug = f"{proc}_{VCT:.3f}V_{temp}C_params_dqd{dqd}_dqt{dqt}".replace(".", "p").replace("-", "n")
    d = ev / slug
    d.mkdir(parents=True, exist_ok=True)
    (d / "corner.cir").write_text(f"* synthetic unit\nalterparam dqd={dqd}\nalterparam dqt={dqt}\n")
    (d / "corner.json").write_text(json.dumps(
        {"corner_id": f"{proc}/{VCT:.3f}V/{temp}C/params:dqd={dqd},dqt={dqt}"}) + "\n")
    (d / "waveform.raw.json").write_text(json.dumps(
        {"variables": [{"name": "time"}, {"name": "V(vdiff)"}], "points": trace(dqd, dqt, poison)}))
    return f"{proc}/{VCT:.3f}V/{temp}C/params:dqd={dqd},dqt={dqt}"


def isf_report(proc, temp, cids):
    return {"schema_version": 3, "status": "pass", "corner_count": len(cids),
            "corners": [{"corner_id": c, "process": proc, "supply_v": {"vct": VCT},
                         "temperature_c": temp, "status": "pass",
                         "measurements": [{"name": "vdiff_max", "value": AMP, "unit": "V"}]}
                        for c in cids]}


def noise_report(port):
    si = SI_TANK if port == "tank" else SI_TAIL
    freqs = [FSTART + (FSTOP - FSTART) * k / (NPTS - 1) for k in range(NPTS)]
    corners = []
    for proc, temp, _src, fault in CORNERS:
        if fault == "no_noise":          # this corner is simply absent from the noise job
            continue
        corners.append({"corner_id": f"{proc}/{VCT:.3f}V/{temp}C", "process": proc,
                        "supply_v": {"vct": VCT}, "temperature_c": temp, "status": "pass",
                        "measurements": [{"name": f"inoise_{k}", "value": si, "unit": "A/sqrt(Hz)"}
                                         for k, _f in enumerate(freqs)]})
    return {"schema_version": 3, "status": "pass", "corner_count": len(corners), "corners": corners}


OUT.mkdir(parents=True, exist_ok=True)
plan = ["process,temp_c,f0_hz,f0_source,tstop_s,n_units,n_plateau_expected,cost_cpu_h,nper"]
for proc, temp, src, fault in CORNERS:
    cdir = OUT / f"{proc}_{temp}C"
    cdir.mkdir(parents=True, exist_ok=True)
    (cdir / "request-isf-post79.json").write_text("{}\n")
    plan.append(f"{proc},{temp},{F0:.6e},{src},{TSTOP:.6e},{len(UNITS)},3,0.001,{NPER}")
    if fault == "no_evidence":
        continue
    ev = cdir / "evidence"
    units = UNITS[:4] if fault == "short_ensemble" else UNITS
    cids = [unit_dir(ev, proc, temp, d, t, fault == "nan_trace" and (d, t) == ("4e-15", "0"))
            for d, t in units]
    (ev / "report.json").write_text(json.dumps(isf_report(proc, temp, cids), indent=1) + "\n")
    (ev / "batch-receipt.json").write_text(json.dumps({"job_id": f"klt-sim-fixture-{proc}-{temp}"}) + "\n")
(OUT / "grid-plan.csv").write_text("\n".join(plan) + "\n")
for port in ("tank", "tail"):
    d = OUT / f"noise-{port}"
    d.mkdir(parents=True, exist_ok=True)
    (d / "report.json").write_text(json.dumps(noise_report(port), indent=1) + "\n")
print(f"built {len(CORNERS)} corners under {OUT}")
PY
OUT="${T}/grid"
python3 "${T}/build.py" "${OUT}" "${F0}" "${NPER}" "${G0_TANK}" "${G0_TAIL}" "${SI_TANK}" "${SI_TAIL}" >/dev/null \
  || { echo "FAIL fixture could not be built"; exit 1; }

# ---- records/ must be untouched by anything below --------------------------------------
records_state() { find "${PN}/records" -type f 2>/dev/null | sort | xargs cksum 2>/dev/null | sha256sum; }
RECORDS_BEFORE="$(records_state)"

# ---- drive the real entry point --------------------------------------------------------
RED_OUT="$("${SWEEP}" --reduce "${OUT}" 2>&1)"; RED_RC=$?
CORNERS="${OUT}/corners.csv"
if [[ "${RED_RC}" -eq 0 && -f "${CORNERS}" ]]; then pass "--reduce ran and wrote corners.csv"
else
  fail "--reduce rc=${RED_RC}"; echo "${RED_OUT}" | tail -20
  echo "1 failure(s)"; exit 1   # every check below reads corners.csv; do not pretend to run them
fi
has "--reduce reports a pass/non-pass count" "${RED_OUT}" "1 pass, 4 non-pass of 5 corner(s)"

cell() { # <process> <temp_c> <column-name>
  awk -F, -v p="$1" -v t="$2" -v c="$3" \
    'NR == 1 { for (i = 1; i <= NF; i++) if ($i == c) k = i; next }
     $1 == p && $2 == t { print $k; exit }' "${CORNERS}"
}

# ---- AC: every corner the plan declares is present exactly once -------------------------
eq "every plan corner has a row" "$(tail -n +2 "${CORNERS}" | wc -l | tr -d ' ')" "5"
eq "no duplicate corner rows" \
   "$(tail -n +2 "${CORNERS}" | cut -d, -f1,2 | sort | uniq -d | wc -l | tr -d ' ')" "0"
eq "grader's 12 columns come first, in its order" \
   "$(head -1 "${CORNERS}" | cut -d, -f1-12)" \
   "process,temp_c,status,l_1mhz_dbc,l_10mhz_dbc,l_1mhz_sd_db,inductor_bar_db,n_plateau_min,plateau_ripple_max_s,f0_hz,job_id,raw_log"

# ---- AC: the complete corner, against the independently evaluated kernel -----------------
eq "complete corner is pass" "$(cell tt_typ_typ 27 status)" "pass"
L1_WANT="$(awk -v g="${G0_TANK}" -v si="${SI_TANK}" 'BEGIN {
  PI = 4*atan2(1,1); gr = g/sqrt(2); s = si*si; dw = 2*PI*1e6
  printf "%.4f", 10*log(gr*gr*s/(2*dw*dw))/log(10) }')"
near "L(1MHz) recovers the model's G0 (analytic ${L1_WANT} dBc/Hz)" "$(cell tt_typ_typ 27 l_1mhz_dbc)" "${L1_WANT}" 0.6
near "L(10MHz) is exactly 20 dB below (1/f^2 kernel)" \
  "$(awk -v a="$(cell tt_typ_typ 27 l_1mhz_dbc)" -v b="$(cell tt_typ_typ 27 l_10mhz_dbc)" 'BEGIN{print a-b}')" "20" 0.01
near "carrier reported is the measured one" "$(cell tt_typ_typ 27 f0_hz)" "${F0}" 2e6
near "inductor-model bar travels with the number" "$(cell tt_typ_typ 27 inductor_bar_db)" "0.421" 0.001
if awk -v s="$(cell tt_typ_typ 27 l_1mhz_sd_db)" 'BEGIN { exit (s+0 >= 0 && s+0 < 1) ? 0 : 1 }'; then
  pass "ensemble sd is reported and small"; else fail "sd = $(cell tt_typ_typ 27 l_1mhz_sd_db)"; fi
eq "job_id carried from the batch receipt" "$(cell tt_typ_typ 27 job_id)" "klt-sim-fixture-tt_typ_typ-27"

# ---- AC: n_plateau_min is the MIN and plateau_ripple_max_s the MAX ----------------------
ISF="${OUT}/reduce/tt_typ_typ_27C/tt_typ_typ_27C-pilot-isf.csv"
agg() { awk -F, -v w="$1" 'NR > 1 {
    if (nmin == "" || $10+0 < nmin) nmin = $10+0; if ($10+0 > nmax) nmax = $10+0
    ns += $10; n++; nlast = $10+0
    if (rmin == "" || $9+0 < rmin) rmin = $9+0; if ($9+0 > rmax) rmax = $9+0
    rs += $9; rlast = $9+0 }
  END { if (w=="nmin") print nmin; else if (w=="nmax") print nmax
        else if (w=="nmean") printf "%.4g", ns/n; else if (w=="nlast") print nlast
        else if (w=="rmax") printf "%.6e", rmax; else if (w=="rmin") printf "%.6e", rmin
        else if (w=="rmean") printf "%.6e", rs/n; else if (w=="rlast") printf "%.6e", rlast }' "${ISF}"; }
eq "n_plateau_min is the MIN of the per-impulse column" "$(cell tt_typ_typ 27 n_plateau_min)" "$(agg nmin)"
ne "  ...and the fixture's MAX differs, so MAX is ruled out" "$(agg nmin)" "$(agg nmax)"
ne "  ...and its mean differs, so the mean is ruled out" "$(agg nmin)" "$(agg nmean)"
eq "plateau_ripple_max_s is the MAX of the per-impulse column" "$(cell tt_typ_typ 27 plateau_ripple_max_s)" "$(agg rmax)"
ne "  ...and the MIN differs, so MIN is ruled out" "$(agg rmax)" "$(agg rmin)"
ne "  ...and the LAST row's value differs, so last-row is ruled out" "$(agg rmax)" "$(agg rlast)"
ne "  ...and the mean differs" "$(agg rmax)" "$(agg rmean)"

# ---- AC: three failure modes, each listed with a cause and no number --------------------
VOCAB="pass sim_error no_oscillation invalid"
check_bad() { # <process> <temp> <label> <cause-substring> [<expected status>]
  local p="$1" t="$2" label="$3" want="$4" st cause
  st="$(cell "${p}" "${t}" status)"; cause="$(cell "${p}" "${t}" cause)"
  case " ${VOCAB} " in *" ${st} "*) ;; *) fail "${label}: status '${st}' is outside the grader's vocabulary"; return ;; esac
  [[ "${st}" != "pass" ]] || { fail "${label}: status is pass, should not be"; return; }
  [[ -n "${5:-}" && "${st}" != "${5}" ]] && { fail "${label}: status '${st}', want '${5}'"; return; }
  [[ -n "${cause}" ]] || { fail "${label}: no cause recorded"; return; }
  grep -q -- "${want}" <<<"${cause}" || { fail "${label}: cause '${cause}' does not mention '${want}'"; return; }
  [[ -z "$(cell "${p}" "${t}" l_1mhz_dbc)" && -z "$(cell "${p}" "${t}" l_10mhz_dbc)" ]] \
    || { fail "${label}: a non-pass corner was given an L number"; return; }
  [[ -f "${OUT}/$(cell "${p}" "${t}" raw_log)" ]] \
    || { fail "${label}: raw_log '$(cell "${p}" "${t}" raw_log)' is not a file"; return; }
  pass "${label}: ${st}, cause recorded, no number, raw_log kept"
}
check_bad ss_bcs_wcs -40 "short ensemble" "incomplete ensemble" sim_error
check_bad ff_wcs_typ 125 "invalid trace" "trace" invalid
check_bad sf_typ_bcs 27 "unresolvable port noise" "port noise" sim_error
check_bad fs_bcs_typ -40 "nothing returned" "no returned ISF evidence" sim_error
has "invalid-trace cause names the non-finite reason" \
  "$(cat "${OUT}/reduce/ff_wcs_typ_125C.log")" "nonfinite"
eq "f0_source provenance is carried through" "$(cell ff_wcs_typ 125 f0_source)" "fallback-27C"

# ---- AC: the grader accepts this table unchanged ----------------------------------------
GR="$(python3 "${GRADER}" "${CORNERS}" 2>&1)"; GR_RC=$?
eq "grader parses corners.csv" "${GR_RC}" "0"
hasnt "grader does not reject the schema" "${GR}" "lacks column"
has "3-corner-plus grid is INCOMPLETE, as expected" "${GR}" "INCOMPLETE"
has "grader lists the short-ensemble corner" "${GR}" "INVALID  ss_bcs_wcs -40C: status=sim_error"
has "grader lists the invalid-trace corner" "${GR}" "INVALID  ff_wcs_typ 125C: status=invalid"
has "grader carries raw_log into its listing" "${GR}" "raw_log=reduce/ff_wcs_typ_125C.log"
has "grader still misses the 130 ungenerated corners" "${GR}" "MISSING"
hasnt "the complete corner is not listed as invalid" "${GR}" "INVALID  tt_typ_typ 27C"

# ---- re-running --reduce over the same OUTDIR is not an append-only abort ---------------
L1_FIRST="$(cell tt_typ_typ 27 l_1mhz_dbc)"
RE="$("${SWEEP}" --reduce "${OUT}" 2>&1)"; RE_RC=$?
eq "re-reduce exits 0" "${RE_RC}" "0"
hasnt "re-reduce does not hit the append-only guard" "${RE}" "append-only"
eq "re-reduce yields the same row count" "$(tail -n +2 "${CORNERS}" | wc -l | tr -d ' ')" "5"
eq "re-reduce reproduces the first run's L" "$(cell tt_typ_typ 27 l_1mhz_dbc)" "${L1_FIRST}"

# ---- the plan MUST carry nper: reducing at the wrong spacing is silently wrong ----------
# Reducing nper=9 traces at nper=3 does NOT fail -- it publishes a different number. That
# is exactly why grid-plan.csv records the spacing and --reduce reads it per corner.
WRONG="$(env -u PDK_ROOT -u PDK "${REDUCER}" --process tt_typ_typ --temp 27 --nper 3 \
  --f0 "${F0}" --outdir "${T}/wrongnper" "${OUT}/reduce/tt_typ_typ_27C/traces" \
  "${OUT}/reduce/tt_typ_typ_27C/inoise-tank.txt" "${OUT}/reduce/tt_typ_typ_27C/inoise-tail.txt" \
  wrongnper 2>&1)"
W_L1="$(awk -F, '$1 == "l_1mhz_mean" { print $2 }' "${T}/wrongnper/wrongnper-pilot-summary.csv" 2>/dev/null)"
if [[ -n "${W_L1}" ]] && awk -v a="${W_L1}" -v b="$(cell tt_typ_typ 27 l_1mhz_dbc)" \
     'BEGIN { d = a - b; if (d < 0) d = -d; exit (d > 1.0) ? 0 : 1 }'; then
  pass "a desynced nper changes L by >1 dB with no error (so nper must come from the plan)"
else
  fail "desynced nper gave L='${W_L1}' vs '$(cell tt_typ_typ 27 l_1mhz_dbc)'"
  echo "${WRONG}" | tail -5
fi
sed 's/,nper$//; s/,9$//' "${OUT}/grid-plan.csv" > "${T}/noplan.csv"
mkdir -p "${T}/nonper" && cp "${T}/noplan.csv" "${T}/nonper/grid-plan.csv"
NO="$("${SWEEP}" --reduce "${T}/nonper" 2>&1)"
has "a plan without nper is refused, not guessed" "${NO}" "has no 'nper' column"

# ---- regression: the pre-#329 single-corner invocation still runs -----------------------
PILOT_TR="${PN}/klt-sim/isf-post79/traces"
PILOT_SUM="${PN}/records/20261105-200000-6834172-pilot-summary.csv"
if [[ -f "${PILOT_TR}/index.tsv" && -f "${PILOT_SUM}" ]]; then
  LEG="$(env -u PDK_ROOT -u PDK "${REDUCER}" --outdir "${T}/legacy" "${PILOT_TR}" \
    "${PN}/klt-sim/noise-post79/evidence-tank/submit.stdout" \
    "${PN}/klt-sim/noise-post79/evidence-tail/submit.stdout" \
    20261105-200000-6834172 4.197e9 2>&1)"; LEG_RC=$?
  eq "4 positionals + f0 still run" "${LEG_RC}" "0"
  [[ "${LEG_RC}" -eq 0 ]] || echo "${LEG}" | tail -5
  for k in l_1mhz_mean l_10mhz_mean l_1mhz_sd gq_rms_tank_mean si_tank f0_measured; do
    eq "  ...and reproduce the committed record's ${k}" \
      "$(awk -F, -v k="${k}" '$1 == k { print $2; exit }' "${T}/legacy/20261105-200000-6834172-pilot-summary.csv")" \
      "$(awk -F, -v k="${k}" '$1 == k { print $2; exit }' "${PILOT_SUM}")"
  done
  eq "  ...and the summary still says tt / 27 C by default" \
    "$(awk -F, '$1 == "mos" || $1 == "cap" || $1 == "hbt" || $1 == "temp_c" { printf "%s=%s ", $1, $2 }' \
       "${T}/legacy/20261105-200000-6834172-pilot-summary.csv")" \
    "mos=tt cap=cap_typ hbt=hbt_typ temp_c=27 "
  # The records dir stays append-only: no --outdir, an id that already exists -> refusal,
  # and the refusal happens before any file is created.
  APP="$(env -u PDK_ROOT -u PDK "${REDUCER}" "${PILOT_TR}" \
    "${PN}/klt-sim/noise-post79/evidence-tank/submit.stdout" \
    "${PN}/klt-sim/noise-post79/evidence-tail/submit.stdout" \
    20261105-200000-6834172 4.197e9 2>&1)"
  has "records/ is still append-only without --outdir" "${APP}" "append-only"
else
  fail "committed pilot traces/summary absent: cannot check the single-corner regression"
fi

eq "nothing was written under sim/phase-noise/records" "$(records_state)" "${RECORDS_BEFORE}"

echo "${fails} failure(s)"
[[ ${fails} -eq 0 ]] || exit 1
echo "all cases passed"
