#!/usr/bin/env bash
# DR-004 stage-2 supply sub-corner REPORT and escalation grader (issue #113).
#
#   sim/oscillator-core/report_supply_stage2.sh \
#       --stage2-osc  <dir>/<record-id>            # run_supply_stage2.sh record
#       [--baseline-osc <dir>/<record-id>]         # stage-1 run_pvt_sweep.sh record
#       [--stage2-pn  <dir>/<record-id>]...        # phase-noise stage-2 records
#       [--baseline-pn <dir>/<record-id>]...       # nominal-rail phase-noise records
#       --out <dir>/<new-record-id>                # writes <id>-supply-stage2.{csv,md}
#
# PDK-FREE: it reads CSVs and the markdown records' digests, and runs no
# simulator, so tests/test_supply_stage2.sh exercises it on synthetic fixtures.
#
# WHAT IT DOES
# For each of the 18 stage-2 sub-corners (and, for row 6, the 8 margin corners)
# it reports rows 1/4/6/7/8, compares each row's stage-2 MARGIN with the margin
# the MATCHING stage-1 (nominal-rail) point left, and prints one status:
#
#   ESCALATION_REQUIRED  stage 2 moved the margin by more than stage 1 left
#                        (s2_status in supply_stage2.sh states the exact rule)
#   NO_ESCALATION        it did not
#   INSUFFICIENT         a margin is unavailable: no baseline supplied, the
#                        baseline point is missing/invalid/incomplete, the
#                        stage-2 point was not run or is invalid, or the two
#                        records' design/model provenance differ
#
# and an OVERALL status: ESCALATION_REQUIRED if any (row, point) says so;
# otherwise INSUFFICIENT_EVIDENCE if any is INSUFFICIENT; otherwise
# NO_ESCALATION. "No escalation" is therefore only ever printed when every
# required (row, point) was actually compared.
#
# ESCALATION ROUTES TO A SUPERSEDING DECISION RECORD (DR-004 stage 3). This
# script edits no spec, launches no simulation and certainly not the 405-point
# grid; it reports.
#
# MARGINS (positive = inside the bound; unit is the row's own)
#   row 1  min(f_min - 4.5 GHz, 5.5 GHz - f_max) over the COMPLETE Vctrl curve
#          (osc_emit_tuning's tuning CSV; an incomplete curve is unavailable)
#   row 4  min(-105 - L(1 MHz), -125 - L(10 MHz)) dB, from the ISF estimator's
#          mean over its realisations. THE METHOD'S LIMITS TRAVEL WITH IT: the
#          realisation spread (sample sd, NOT a Monte-Carlo variance), the one
#          carrier operating point and the non-PDK inductor model's bars are
#          the phase-noise record's, and the combined spread of the two
#          compared numbers is printed beside the movement. A movement inside
#          that spread is flagged; the status is still the rule's.
#   row 6  (lower bound of the tail-current-scaling margin proxy) - 3.0. The
#          proxy is a BRACKET; the conservative lower end is used on BOTH sides
#          of the comparison, and a bracket straddling the bound reads as a
#          negative margin.
#   row 7  TWO separate comparisons per point (issue #119), both read from
#          the <record>-row7.csv that osc_bench.sh's osc_emit_row7 (the
#          issue-#112 grader, used unchanged by stage 1 and stage 2) wrote;
#          nothing here re-derives a swing or a VCE:
#            swing       min complete-window Vpp_diff - 0.40 V (V). A window
#                        point that did not oscillate (NOSC) is a measured
#                        swing failure; its sustained swing is counted as 0 V.
#            compliance  2.2 V - the CONSERVATIVE (sampling-bound upper)
#                        VCE_max over the full Vctrl domain (V).
#          INCOMPLETE grades (missing/duplicate/unexpected Vctrl, INVALID
#          waveform, legacy 29-column point rows) and WITHIN SAMPLING BOUND
#          compliance (the measured value is under 2.2 V, its bound is not)
#          are INSUFFICIENT with the grader's reason, never a margin. A
#          row-7 CSV whose header is not osc_row7_header's (legacy/foreign
#          layout), a missing one, or a grade line whose verdict contradicts
#          its value is unavailable as well. Target and stretch verdicts
#          travel in the value column; the escalation rule uses the margins.
#   row 8  10 mW - large-signal core power at the band-centre Vctrl, VALID
#          measurements only (the rail multiplies the same average current).
#
# PROVENANCE. A comparison is only made when the stage-2 and the baseline
# records agree on the device-section sha256, the non-PDK inductor model sha256,
# every loaded PDK library digest and the OSDI binary digest (read from the
# records' markdown). A missing or different digest makes the baseline
# UNAVAILABLE for that family (rows 1/6/8 together; row 4 per phase-noise
# record), never silently accepted.
#
# MIXED-RAIL PREVENTION. Every input CSV must carry the rail (vsup_v) for
# stage 2; every lookup matches the rail numerically. A baseline file without a
# rail column is accepted only as the nominal 3.3 V rail.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$(cd "${HERE}/.." && pwd)"

# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"
# shellcheck source=osc_bench.sh
source "${HERE}/osc_bench.sh"
# shellcheck source=../phase-noise/pn_bench.sh
source "${SIM_DIR}/phase-noise/pn_bench.sh"
# shellcheck source=supply_stage2.sh
source "${HERE}/supply_stage2.sh"

S2_OSC="" BASE_OSC="" OUT="" S2_PN=() BASE_PN=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage2-osc)   S2_OSC="$2"; shift 2 ;;
    --baseline-osc) BASE_OSC="$2"; shift 2 ;;
    --stage2-pn)    S2_PN+=("$2"); shift 2 ;;
    --baseline-pn)  BASE_PN+=("$2"); shift 2 ;;
    --out)          OUT="$2"; shift 2 ;;
    -h|--help)      sed -n '2,60p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -n "${S2_OSC}" && -n "${OUT}" ]] || { echo "error: --stage2-osc and --out are required" >&2; exit 2; }
s2_check_enumeration || exit 2
for f in "${S2_OSC}.csv" "${S2_OSC}-tuning.csv"; do
  [[ -f "${f}" ]] || { echo "error: missing stage-2 input ${f}" >&2; exit 2; }
done
if [[ -e "${OUT}-supply-stage2.csv" || -e "${OUT}-supply-stage2.md" ]]; then
  echo "error: ${OUT}-supply-stage2.* already exists; sim/ evidence is append-only -- use a fresh record id" >&2
  exit 2
fi

TAB="$(printf '\t')"

# ----------------------------------------------------------------- getters
# Every getter prints ONE line: margin<TAB>value<TAB>reason (margin "nan" when
# unavailable; reason says why, or is "-").
res() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

# Finite-number validation (issue #175). A temperature, rail or measured
# value that is not a finite number is INSUFFICIENT with the field named, never
# coerced by awk to 0 (which would match a corner or feed arithmetic).
# arg_check <temp> <rail> -- rc 1 after printing an unavailable result line.
arg_check() {
  s2_finite "$1" || { res nan - "invalid temp_c '$1' (not a finite number)"; return 1; }
  s2_finite "$2" || { res nan - "invalid vsup_v '$2' (not a finite number)"; return 1; }
  return 0
}

get_row1() { # prefix mos cap hbt temp rail
  local f="$1-tuning.csv"
  [[ -f "${f}" ]] || { res nan - "no tuning CSV ${f##*/}"; return; }
  arg_check "$5" "$6" || return
  awk -F, -v mos="$2" -v cap="$3" -v hbt="$4" -v temp="$5" -v rail="$6" -v nom="${S2_NOMINAL_RAIL}" \
      -v lo="${OSC_ROW1_F_MIN_HZ}" -v hi="${OSC_ROW1_F_MAX_HZ}" "${S2_AWK_FINITE}"'
    function near(a, b,  d) { d = a - b; if (d < 0) d = -d; return d < 1e-9 }
    NR == 1 { hasrail = ($21 == "vsup_v"); next }
    $1 == mos && $2 == cap && $3 == hbt {
      if (!s2_fin($4)) { bad = "temp_c"; badv = $4; next }
      if (hasrail && !s2_fin($21)) { bad = "vsup_v"; badv = $21; next }
      if (($4 + 0) != (temp + 0)) next
      if (hasrail) { if (!near($21, rail)) next }
      else if (!near(rail, nom)) next
      n++; fmin = $6; fmax = $7; v = $18
    }
    END {
      if (n == 0 && bad != "") { printf "nan\t-\tinvalid %s \047%s\047 in a tuning row of this process (not a finite number)\n", bad, badv; exit }
      if (n == 0) { printf "nan\t-\tno matching tuning row\n"; exit }
      if (n > 1)  { printf "nan\t-\t%d matching tuning rows (ambiguous)\n", n; exit }
      if (v == "INCOMPLETE" || v == "INSUFFICIENT" || fmin == "nan" || fmax == "nan") {
        printf "nan\t-\tVctrl curve %s\n", v; exit }
      if (!s2_fin(fmin)) { printf "nan\t-\tinvalid f_min_hz \047%s\047 (not a finite number)\n", fmin; exit }
      if (!s2_fin(fmax)) { printf "nan\t-\tinvalid f_max_hz \047%s\047 (not a finite number)\n", fmax; exit }
      m1 = fmin - lo; m2 = hi - fmax; m = (m1 < m2) ? m1 : m2
      printf "%.6e\tf_min=%s;f_max=%s\t-\n", m, fmin, fmax
    }' "${f}"
}

get_row8() { # prefix mos cap hbt temp rail
  local f="$1.csv"
  [[ -f "${f}" ]] || { res nan - "no points CSV ${f##*/}"; return; }
  arg_check "$5" "$6" || return
  awk -F, -v mos="$2" -v cap="$3" -v hbt="$4" -v temp="$5" -v rail="$6" -v nom="${S2_NOMINAL_RAIL}" \
      -v vc="${S2_BAND_CENTRE_VCTRL}" -v tmax="${OSC_TMAX}" -v pmax="${OSC_ROW8_P_MAX_W}" "${S2_AWK_FINITE}"'
    function near(a, b,  d) { d = a - b; if (d < 0) d = -d; return d < 1e-9 }
    NR == 1 { rc = 0; for (i = 1; i <= NF; i++) if ($i == "vsup_v") rc = i; hasrail = (rc > 0); next }
    $2 == mos && $3 == cap && $4 == hbt && $7 == tmax {
      if (!s2_fin($5)) { bad = "temp_c"; badv = $5; next }
      if (!s2_fin($6)) { bad = "vctrl_v"; badv = $6; next }
      if (hasrail && !s2_fin($rc)) { bad = "vsup_v"; badv = $rc; next }
      if (($5 + 0) != (temp + 0) || !near($6, vc)) next
      if (hasrail) { if (!near($rc, rail)) next }
      else if (!near(rail, nom)) next
      n++; st = $8; p = $27; ms = $28; mr = $29
    }
    END {
      if (n == 0 && bad != "") { printf "nan\t-\tinvalid %s \047%s\047 in a point row of this process (not a finite number)\n", bad, badv; exit }
      if (n == 0) { printf "nan\t-\tno matching band-centre point\n"; exit }
      if (n > 1)  { printf "nan\t-\t%d matching points (ambiguous)\n", n; exit }
      if (st != "PASS") { printf "nan\t-\tpoint status %s\n", st; exit }
      if (ms != "VALID" || p == "nan" || p == "") { printf "nan\t-\tINVALID measurement (%s)\n", mr; exit }
      if (!s2_fin(p)) { printf "nan\t-\tinvalid p_core_ls_w \047%s\047 (not a finite number)\n", p; exit }
      printf "%.6e\tp_core_ls_w=%s\t-\n", pmax - p, p
    }' "${f}"
}

get_row6() { # prefix mos cap hbt temp rail
  local f="$1-margin-summary.csv"
  [[ -f "${f}" ]] || { res nan - "no margin-summary CSV ${f##*/}"; return; }
  arg_check "$5" "$6" || return
  awk -F, -v mos="$2" -v cap="$3" -v hbt="$4" -v temp="$5" -v rail="$6" -v nom="${S2_NOMINAL_RAIL}" \
      -v bound="${OSC_ROW6_MARGIN}" "${S2_AWK_FINITE}"'
    function near(a, b,  d) { d = a - b; if (d < 0) d = -d; return d < 1e-9 }
    NR == 1 { hasrail = ($15 == "vsup_v"); next }
    $2 == mos && $3 == cap && $4 == hbt {
      if (!s2_fin($5)) { bad = "temp_c"; badv = $5; next }
      if (hasrail && !s2_fin($15)) { bad = "vsup_v"; badv = $15; next }
      if (($5 + 0) != (temp + 0)) next
      if (hasrail) { if (!near($15, rail)) next }
      else if (!near(rail, nom)) next
      n++; lo = $9; hi = $10; v = $11; rc = $13; me = $14
    }
    END {
      if (n == 0 && bad != "") { printf "nan\t-\tinvalid %s \047%s\047 in a margin row of this process (not a finite number)\n", bad, badv; exit }
      if (n == 0) { printf "nan\t-\tno matching margin corner\n"; exit }
      if (n > 1)  { printf "nan\t-\t%d matching margin corners (ambiguous)\n", n; exit }
      if (rc != "rc=0" || me != "model_error=0") { printf "nan\t-\tmargin run failed (%s %s)\n", rc, me; exit }
      if (lo == "nan" || lo == "") { printf "nan\t-\tmargin %s (no oscillating rung)\n", v; exit }
      if (!s2_fin(lo)) { printf "nan\t-\tinvalid margin_lower_bound \047%s\047 (not a finite number)\n", lo; exit }
      if (hi != "nan" && hi != "" && !s2_fin(hi)) { printf "nan\t-\tinvalid margin_upper_bound \047%s\047 (not a finite number)\n", hi; exit }
      note = (v ~ /STRADDLES/) ? "bracket straddles the bound; lower end used" : "-"
      printf "%.6e\tmargin_lo=%s;margin_hi=%s\t%s\n", lo - bound, lo, hi, note
    }' "${f}"
}

# Phase-noise records: identify a record by the identity rows its summary CSV
# carries (mos/cap/hbt/temp_c/vsup_v). A record without them (older pilots)
# cannot be matched to a point and is reported as unidentifiable, not guessed.
pn_summary_value() { awk -F, -v q="$2" 'NR > 1 && $1 == q { print $2; exit }' "$1-pilot-summary.csv" 2>/dev/null; }
pn_find() { # rail mos cap hbt temp prefix...
  local rail="$1" mos="$2" cap="$3" hbt="$4" temp="$5" p hits="" n=0 vm vc vh vt vr bad=""
  shift 5
  for p in "$@"; do
    [[ -f "${p}-pilot-summary.csv" ]] || continue
    vm="$(pn_summary_value "${p}" mos)"; vc="$(pn_summary_value "${p}" cap)"
    vh="$(pn_summary_value "${p}" hbt)"; vt="$(pn_summary_value "${p}" temp_c)"
    vr="$(pn_summary_value "${p}" vsup_v)"
    [[ -n "${vr}" ]] || continue
    if [[ "${vm}" == "${mos}" && "${vc}" == "${cap}" && "${vh}" == "${hbt}" ]]; then
      # identity numbers must be finite BEFORE they are compared (awk would
      # coerce text to 0 and could match a corner)
      s2_finite "${vt}" || { bad="temp_c '${vt}'"; continue; }
      s2_finite "${vr}" || { bad="vsup_v '${vr}'"; continue; }
    fi
    if [[ "${vm}" == "${mos}" && "${vc}" == "${cap}" && "${vh}" == "${hbt}" ]] \
       && awk -v a="${vt}" -v b="${temp}" -v r1="${vr}" -v r2="${rail}" \
            'BEGIN { d = r1 - r2; if (d < 0) d = -d; e = a - b; if (e < 0) e = -e; exit (d < 1e-9 && e < 1e-9) ? 0 : 1 }'; then
      hits="${p}"; n=$((n + 1))
    fi
  done
  if [[ "${n}" == 0 && -n "${bad}" ]]; then echo "INVALID:${bad}"
  elif [[ "${n}" == 0 ]]; then echo ""; elif [[ "${n}" == 1 ]]; then echo "${hits}"; else echo "AMBIGUOUS"; fi
}
get_row4_from() { # prefix  -> margin<TAB>value<TAB>reason<TAB>sd1<TAB>sd10
  local p="$1" l1 l10 s1 s10 f v
  l1="$(pn_summary_value "${p}" l_1mhz_mean)"; l10="$(pn_summary_value "${p}" l_10mhz_mean)"
  s1="$(pn_summary_value "${p}" l_1mhz_sd)";   s10="$(pn_summary_value "${p}" l_10mhz_sd)"
  # finite-number validation before any arithmetic (issue #175); "nan"/empty
  # means unavailable and is handled below, anything else must be finite
  for f in l_1mhz_mean:"${l1}" l_10mhz_mean:"${l10}" l_1mhz_sd:"${s1}" l_10mhz_sd:"${s10}"; do
    v="${f#*:}"
    [[ "${v}" == "nan" || -z "${v}" ]] && continue
    s2_finite "${v}" || { printf 'nan\t-\tinvalid %s \047%s\047 (not a finite number) in the phase-noise record\tnan\tnan\n' "${f%%:*}" "${v}"; return; }
  done
  awk -v l1="${l1}" -v l10="${l10}" -v s1="${s1}" -v s10="${s10}" \
      -v t1="${PN_ROW4_1M_TARGET}" -v t10="${PN_ROW4_10M_TARGET}" 'BEGIN {
    if (l1 == "" || l1 == "nan" || l10 == "" || l10 == "nan") {
      printf "nan\t-\tL(df) unavailable (nan) in the phase-noise record\tnan\tnan\n"; exit }
    a = t1 - l1; b = t10 - l10; m = (a < b) ? a : b
    printf "%.4f\tL1M=%s;L10M=%s\t-\t%s\t%s\n", m, l1, l10, s1, s10
  }'
}

# Row 7. One lookup, two getters (swing / compliance) over the grade lines the
# shared grader wrote. Columns are those of osc_row7_header (osc_bench.sh); the
# header is checked verbatim so a legacy or foreign layout is never misread.
R7_HEADER="$(OSC_CSV_RAIL=0 osc_row7_header)"
r7_line() { # kind(swing|compliance) prefix mos cap hbt temp rail
  local kind="$1" f="$2-row7.csv" h hasrail=0
  [[ -f "${f}" ]] || { res nan - "no row-7 CSV ${f##*/} (record predates stage-2 row-7 grading)"; return; }
  h="$(head -1 "${f}")"
  if [[ "${h}" == "${R7_HEADER},vsup_v" ]]; then hasrail=1
  elif [[ "${h}" != "${R7_HEADER}" ]]; then res nan - "row-7 CSV ${f##*/} has an unrecognised (legacy or foreign) header"; return
  fi
  arg_check "$6" "$7" || return
  awk -F, -v kind="${kind}" -v mos="$3" -v cap="$4" -v hbt="$5" -v temp="$6" -v rail="$7" \
      -v hasrail="${hasrail}" -v nom="${S2_NOMINAL_RAIL}" \
      -v vt="${OSC_ROW7_VPP_MIN_V}" -v bv="${OSC_ROW7_BVCEO_MIN_V}" "${S2_AWK_FINITE}${OSC_ROW7_AWK_LIB}"'
    function near(a, b,  d) { d = a - b; if (d < 0) d = -d; return d < 1e-9 }
    NR == 1 { next }
    $1 == mos && $2 == cap && $3 == hbt {
      if (!s2_fin($4)) { bad = "temp_c"; badv = $4; next }
      if (hasrail && NF == 25 && !s2_fin($25)) { bad = "vsup_v"; badv = $25; next }
      if (($4 + 0) != (temp + 0)) next
      if (hasrail) { if (NF != 25 || !near($25, rail)) next }
      else if (!near(rail, nom)) next
      n++; vmin = $9; vmat = $10; vce = $11; vup = $12; vupat = $13
      sw = $19; ss = $20; cp = $21; why = $24
    }
    END {
      if (n == 0 && bad != "") { printf "nan\t-\tinvalid %s \047%s\047 in a row-7 grade of this process (not a finite number)\n", bad, badv; exit }
      if (n == 0) { printf "nan\t-\tno matching row-7 grade\n"; exit }
      if (n > 1)  { printf "nan\t-\t%d matching row-7 grades (ambiguous)\n", n; exit }
      if (kind == "swing") {
        if (sw == "INCOMPLETE" || ss == "INCOMPLETE") { printf "nan\t-\trow-7 INCOMPLETE (%s)\n", why; exit }
        if (sw != "MET" && sw != "NOT MET") { printf "nan\t-\tunrecognised swing verdict %s\n", sw; exit }
        if (!r7_num(vmin)) { printf "nan\t-\tno numeric window swing\n"; exit }
        m = vmin - vt; note = "-"
        if (why ~ /did not oscillate/) { m = -vt; note = why "; sustained swing counted as 0 V" }
        if ((sw == "MET") != (m >= 0)) { printf "nan\t-\tswing verdict %s contradicts min Vpp %s V (invalid grade line)\n", sw, vmin; exit }
        printf "%.6e\tvpp_min_window=%s@%s;swing_target=%s;swing_stretch=%s\t%s\n", m, vmin, vmat, sw, ss, note
        exit
      }
      if (cp == "INCOMPLETE") { printf "nan\t-\trow-7 INCOMPLETE (%s)\n", why; exit }
      if (cp ~ /SAMPLING/) {
        printf "nan\t-\tcompliance WITHIN SAMPLING BOUND: measured VCE_max %s V <= %s V but its sampling-bound upper value %s V is not; not a pass and not a margin\n", vce, bv, vup; exit }
      if (cp != "MET" && cp != "NOT MET") { printf "nan\t-\tunrecognised compliance verdict %s\n", cp; exit }
      if (!r7_num(vce)) { printf "nan\t-\tcompliance %s without a numeric VCE_max\n", cp; exit }
      if (cp == "MET" && !r7_num(vup)) { printf "nan\t-\tcompliance MET without a sampling-bound upper VCE_max (invalid grade line)\n"; exit }
      # conservative worst value: the larger of the upper bound and the
      # measured maximum (a NOT MET point may carry no sampling bound)
      w = vce + 0; note = "-"
      if (r7_num(vup)) { if (vup + 0 > w) w = vup + 0 }
      else note = "a NOT MET point has no sampling bound; its measured VCE_max is used, so the true margin can be lower still"
      m = bv - w
      if ((cp == "MET") != (m >= 0)) { printf "nan\t-\tcompliance verdict %s contradicts VCE_max %s V / upper %s V (invalid grade line)\n", cp, vce, vup; exit }
      printf "%.6e\tvce_max=%s;vce_max_upper=%s@%s;compliance=%s\t%s\n", m, vce, vup, vupat, cp, note
    }' "${f}"
}
get_row7_swing()      { r7_line swing "$@"; }
get_row7_compliance() { r7_line compliance "$@"; }

# ------------------------------------------------------------- provenance
# prov_digests <record.md> -- "key=hex" lines for the digests that define which
# design and models produced a record's numbers. The record text wraps lines,
# so it is whitespace-normalised first.
prov_digests() {
  [[ -f "$1" ]] || return 1
  tr '\n' ' ' < "$1" | sed 's/  */ /g' | awk '
    function grab(key, pat,   s) {
      if (match($0, pat)) {
        s = substr($0, RSTART, RLENGTH)
        # the digest is the hex run just before the match'"'"'s closing backtick
        if (match(s, /[0-9a-f]+`$/)) print key "=" substr(s, RSTART, RLENGTH - 1) } }
    { grab("body",      "Device section sha256 `[0-9a-f]+`")
      grab("inductor",  "sg13g2_inductor_em\\.spice` sha256 `[0-9a-f]+`")
      grab("cornerHBT", "cornerHBT\\.lib` sha256 `[0-9a-f]+`")
      grab("cornerMOShv","cornerMOShv\\.lib` sha256 `[0-9a-f]+`")
      grab("cornerCAP", "cornerCAP\\.lib` sha256 `[0-9a-f]+`")
      grab("svaricap",  "sg13g2_svaricaphv_mod\\.lib` sha256 `[0-9a-f]+`")
      grab("hbtmod",    "sg13g2_hbt_mod\\.lib` sha256 `[0-9a-f]+`")
      grab("osdi",      "mosvar\\.osdi` \\(this run.s build\\) sha256 `[0-9a-f]+`") }'
}
PROV_KEYS="body inductor cornerHBT cornerMOShv cornerCAP svaricap hbtmod osdi"
# prov_compare <a.md> <b.md> -- prints "OK" or a one-line reason.
prov_compare() {
  local a b k va vb bad=""
  a="$(prov_digests "$1")" || { echo "record $1 not found (provenance unverifiable)"; return; }
  b="$(prov_digests "$2")" || { echo "record $2 not found (provenance unverifiable)"; return; }
  for k in ${PROV_KEYS}; do
    va="$(echo "${a}" | awk -F= -v k="${k}" '$1 == k { print $2 }')"
    vb="$(echo "${b}" | awk -F= -v k="${k}" '$1 == k { print $2 }')"
    if [[ -z "${va}" || -z "${vb}" ]]; then bad="${bad} ${k}(missing)"
    elif [[ "${va}" != "${vb}" ]]; then bad="${bad} ${k}(differs)"; fi
  done
  if [[ -n "${bad}" ]]; then echo "provenance mismatch:${bad}"; else echo OK; fi
}

# ------------------------------------------------------------------- report
WORK="$(mktemp -d "${TMPDIR:-/tmp}/s2-report.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT
CSV="${OUT}-supply-stage2.csv"
MD="${OUT}-supply-stage2.md"
echo "row,process,vsup_v,temp_c,metric,unit,stage2_value,stage1_value,stage2_margin,stage1_margin,movement,stage1_margin_left,status,reason" > "${CSV}"

# osc-family provenance, once
OSC_PROV="no baseline supplied"
if [[ -n "${BASE_OSC}" ]]; then OSC_PROV="$(prov_compare "${S2_OSC}.md" "${BASE_OSC}.md")"; fi

emit() { # row process rail temp metric unit v2 v1 m2 m1 status reason [extra]
  local row="$1" proc="$2" rail="$3" temp="$4" metric="$5" unit="$6" v2="$7" v1="$8" m2="$9" m1="${10}" st="${11}" reason="${12}"
  local mv left
  mv=nan left=nan
  if s2_finite "${m2}" && s2_finite "${m1}"; then
    mv="$(awk -v a="${m2}" -v b="${m1}" 'BEGIN { printf "%.6e", a-b }')"
  fi
  if s2_finite "${m1}"; then
    left="$(awk -v b="${m1}" 'BEGIN { printf "%.6e", (b > 0) ? b : 0 }')"
  fi
  # a margin that is neither a number nor the "unavailable" marker is named
  if [[ "${st}" == INSUFFICIENT ]]; then
    local ir; ir="$(s2_status_reason "${m1}" "${m2}")"
    [[ "${ir}" != "-" ]] && reason="${ir}; ${reason}"
  fi
  # commas would break the CSV
  reason="${reason//,/;}"
  echo "${row},${proc},${rail},${temp},${metric},${unit},${v2},${v1},${m2},${m1},${mv},${left},${st},${reason}" >> "${CSV}"
}

compare_family() { # row proc rail temp metric unit getter stage2prefix baseprefix mos cap hbt  (osc-family rows)
  local row="$1" proc="$2" rail="$3" temp="$4" metric="$5" unit="$6" getter="$7" p2="$8" pb="$9"
  local mos="${10}" cap="${11}" hbt="${12}"
  local l2 l1 m2 v2 r2 m1 v1 r1 st reason
  l2="$("${getter}" "${p2}" "${mos}" "${cap}" "${hbt}" "${temp}" "${rail}")"
  IFS="${TAB}" read -r m2 v2 r2 <<<"${l2}"
  if [[ -z "${pb}" ]]; then m1=nan; v1=-; r1="no baseline supplied"
  elif [[ "${OSC_PROV}" != OK ]]; then m1=nan; v1=-; r1="${OSC_PROV}"
  else
    l1="$("${getter}" "${pb}" "${mos}" "${cap}" "${hbt}" "${temp}" "${S2_NOMINAL_RAIL}")"
    IFS="${TAB}" read -r m1 v1 r1 <<<"${l1}"
  fi
  st="$(s2_status "${m1}" "${m2}")"
  reason="-"
  if [[ "${st}" == INSUFFICIENT ]]; then
    reason="stage2: ${r2}; baseline: ${r1}"
  elif [[ "${r2}" != "-" || "${r1}" != "-" ]]; then
    reason="stage2: ${r2}; baseline: ${r1}"
  fi
  emit "${row}" "${proc}" "${rail}" "${temp}" "${metric}" "${unit}" "${v2}" "${v1}" "${m2}" "${m1}" "${st}" "${reason}"
}

NPN=0
while read -r proc rail temp mos cap hbt; do
  compare_family 1 "${proc}" "${rail}" "${temp}" "f_band_margin" "Hz" get_row1 "${S2_OSC}" "${BASE_OSC}" "${mos}" "${cap}" "${hbt}"
  compare_family 8 "${proc}" "${rail}" "${temp}" "power_margin_at_band_centre" "W" get_row8 "${S2_OSC}" "${BASE_OSC}" "${mos}" "${cap}" "${hbt}"
  compare_family 7 "${proc}" "${rail}" "${temp}" "row7_swing_margin_min_window_vpp" "V" get_row7_swing "${S2_OSC}" "${BASE_OSC}" "${mos}" "${cap}" "${hbt}"
  compare_family 7 "${proc}" "${rail}" "${temp}" "row7_compliance_margin_vce_upper" "V" get_row7_compliance "${S2_OSC}" "${BASE_OSC}" "${mos}" "${cap}" "${hbt}"

  # row 4 -- one phase-noise record per point
  p2="$(pn_find "${rail}" "${mos}" "${cap}" "${hbt}" "${temp}" ${S2_PN[@]+"${S2_PN[@]}"})"
  pb="$(pn_find "${S2_NOMINAL_RAIL}" "${mos}" "${cap}" "${hbt}" "${temp}" ${BASE_PN[@]+"${BASE_PN[@]}"})"
  m2=nan v2=- r2="no phase-noise record for this point"; sd2_1=""; sd2_10=""
  m1=nan v1=- r1="no baseline phase-noise record for the matching nominal point"; sd1_1=""; sd1_10=""
  if [[ "${p2}" == AMBIGUOUS ]]; then r2="several phase-noise records match this point (ambiguous)"
  elif [[ "${p2}" == INVALID:* ]]; then r2="invalid ${p2#INVALID:} in a phase-noise record of this process (not a finite number)"; p2=""
  elif [[ -n "${p2}" ]]; then
    IFS="${TAB}" read -r m2 v2 r2 sd2_1 sd2_10 <<<"$(get_row4_from "${p2}")"
  fi
  if [[ "${pb}" == AMBIGUOUS ]]; then r1="several baseline phase-noise records match (ambiguous)"
  elif [[ "${pb}" == INVALID:* ]]; then r1="invalid ${pb#INVALID:} in a baseline phase-noise record of this process (not a finite number)"; pb=""
  elif [[ -n "${pb}" ]]; then
    pv="$(prov_compare "${p2}.md" "${pb}.md")"
    if [[ -z "${p2}" || "${p2}" == AMBIGUOUS ]]; then :
    elif [[ "${pv}" != OK ]]; then r1="${pv}"
    else IFS="${TAB}" read -r m1 v1 r1 sd1_1 sd1_10 <<<"$(get_row4_from "${pb}")"; fi
  fi
  st="$(s2_status "${m1}" "${m2}")"
  reason="stage2: ${r2}; baseline: ${r1}"
  if [[ "${st}" != INSUFFICIENT ]]; then
    bar="$(awk -v a="${sd2_1}" -v b="${sd1_1}" -v c="${sd2_10}" -v d="${sd1_10}" -v x="${m2}" -v y="${m1}" 'BEGIN {
      s1 = sqrt(a*a + b*b); s10 = sqrt(c*c + d*d); s = (s1 > s10) ? s1 : s10
      mv = x - y; if (mv < 0) mv = -mv
      printf "combined realisation spread %.4f dB; movement %s that spread", s, (mv <= s) ? "is INSIDE" : "exceeds" }')"
    reason="${bar}"
  fi
  emit 4 "${proc}" "${rail}" "${temp}" "pn_margin_min_1M_10M" "dB" "${v2}" "${v1}" "${m2}" "${m1}" "${st}" "${reason}"
  NPN=$((NPN + 1))
done < <(s2_enumerate)

while read -r proc rail temp mos cap hbt; do
  compare_family 6 "${proc}" "${rail}" "${temp}" "startup_margin_proxy_lower_bound" "ratio" get_row6 "${S2_OSC}" "${BASE_OSC}" "${mos}" "${cap}" "${hbt}"
done < <(s2_enumerate_margin)

# --------------------------------------------------------------- aggregate
tally() { awk -F, -v r="$1" -v s="$2" 'NR > 1 && $1 == r && $13 == s { n++ } END { print n + 0 }' "${CSV}"; }
N_ESC="$(awk -F, 'NR > 1 && $13 == "ESCALATION_REQUIRED" { n++ } END { print n + 0 }' "${CSV}")"
N_INS="$(awk -F, 'NR > 1 && $13 == "INSUFFICIENT" { n++ } END { print n + 0 }' "${CSV}")"
# Row-7 target/stretch/compliance verdicts over the 18 stage-2 points
# (descriptive; the escalation status is the margins' comparison, not these).
r7_count() { # metric key value
  awk -F, -v m="$1" -v k="$2" -v v="$3" 'NR > 1 && $1 == 7 && $5 == m { n2 = split($7, kv, ";"); for (i = 1; i <= n2; i++) if (kv[i] == k "=" v) n++ } END { print n + 0 }' "${CSV}"
}
if [[ "${N_ESC}" -gt 0 ]]; then OVERALL=ESCALATION_REQUIRED
elif [[ "${N_INS}" -gt 0 ]]; then OVERALL=INSUFFICIENT_EVIDENCE
else OVERALL=NO_ESCALATION; fi

{
  echo "# DR-004 stage-2 supply sub-corner report ($(basename "${OUT}"))"
  echo
  echo "- **Stage-2 oscillator-core record**: \`$(basename "${S2_OSC}")\`"
  echo "- **Baseline (stage-1, nominal ${S2_NOMINAL_RAIL} V) oscillator-core record**: ${BASE_OSC:+\`$(basename "${BASE_OSC}")\`}${BASE_OSC:-none supplied}"
  echo "- **Phase-noise records**: stage 2 ${#S2_PN[@]}, baseline ${#BASE_PN[@]}"
  echo "- **Design/model provenance (osc family)**: ${OSC_PROV}"
  echo "- **OVERALL: ${OVERALL}** (${N_ESC} escalating (row, metric, point) result(s); ${N_INS} insufficient-evidence)"
  echo
  echo "## Status by row"
  echo
  echo "| Row | Results | ESCALATION_REQUIRED | NO_ESCALATION | INSUFFICIENT |"
  echo "|---|---|---|---|---|"
  for r in 1 4 6 7 8; do
    echo "| ${r} | $(awk -F, -v r="${r}" 'NR > 1 && $1 == r { n++ } END { print n + 0 }' "${CSV}") | $(tally "${r}" ESCALATION_REQUIRED) | $(tally "${r}" NO_ESCALATION) | $(tally "${r}" INSUFFICIENT) |"
  done
  echo
  echo "Row 7 has two results per point (swing, compliance). Stage-2 row-7"
  echo "verdicts as graded (descriptive, not the escalation status): swing"
  echo "target MET at $(r7_count row7_swing_margin_min_window_vpp swing_target MET)/${S2_N_POINTS}, stretch MET at $(r7_count row7_swing_margin_min_window_vpp swing_stretch MET)/${S2_N_POINTS};"
  echo "compliance MET at $(r7_count row7_compliance_margin_vce_upper compliance MET)/${S2_N_POINTS},"
  echo "WITHIN SAMPLING BOUND (not a pass) at $(grep -c 'compliance WITHIN SAMPLING BOUND' "${CSV}")/${S2_N_POINTS}."
  echo
  if [[ "${N_ESC}" -gt 0 ]]; then
    echo "## Escalating results"
    echo
    awk -F, 'NR > 1 && $13 == "ESCALATION_REQUIRED" { printf "- row %s `%s`, %s, %s V, %s C: stage-2 margin %s vs stage-1 margin %s %s\n", $1, $5, $2, $3, $4, $9, $10, $6 }' "${CSV}"
    echo
    echo "Under DR-004 stage 3 this makes the full 3-way cross (405 model-grid"
    echo "points) required, **and routes to a superseding decision record**. This"
    echo "report does not edit \`spec/\`, does not relax any row and does not"
    echo "launch that grid."
    echo
  fi
  echo "## How to read this"
  echo
  echo "- Margins are positive inside the bound, in the row's own unit; the"
  echo "  per-point values are in \`$(basename "${CSV}")\`. The rule is"
  echo "  \`s2_status\` in \`supply_stage2.sh\`: escalate when \`|m2 - m1| > m1\`"
  echo "  (read literally, DR-004's \"more than the margin stage 1 left\"), or,"
  echo "  where stage 1 left no margin, when stage 2 is worse. Equality does not"
  echo "  escalate."
  echo "- **INSUFFICIENT is not a pass.** It means a margin was unavailable"
  echo "  (no baseline, missing/invalid/incomplete point, or design/model"
  echo "  provenance that differs). The OVERALL status can read NO_ESCALATION only"
  echo "  when every required (row, point) was compared."
  echo "- **Row 7 is two comparisons per point** (issue #119), both from the"
  echo "  shared issue-#112 grader \`osc_emit_row7\` run per rail, against the"
  echo "  matching nominal (${S2_NOMINAL_RAIL} V) process/temperature grade:"
  echo "  \`row7_swing_margin_min_window_vpp\` = min Vpp_diff over the complete"
  echo "  window [${OSC_ROW3_V_LO}, ${OSC_ROW3_V_HI}] V - ${OSC_ROW7_VPP_MIN_V} V (a NOSC window point counts"
  echo "  as 0 V), and \`row7_compliance_margin_vce_upper\` = ${OSC_ROW7_BVCEO_MIN_V} V - the"
  echo "  sampling-bound UPPER value of (VDD + Vpp_diff/4) - V(TAIL)_min over the"
  echo "  full Vctrl domain. The target (${OSC_ROW7_VPP_MIN_V} V) and stretch (${OSC_ROW7_VPP_MIN_STRETCH_V} V) swing"
  echo "  verdicts and the compliance verdict are in the value columns."
  echo "- **Row 7 sampling assumptions.** Both extremes are samples of an"
  echo "  adaptive-timestep trace; the bound assumes a locally sinusoidal"
  echo "  waveform (\`A(1 - cos(pi f dt_max))\`), so a sharper cusp can hide more."
  echo "  A compliance value inside its sampling bound of the limit is WITHIN"
  echo "  SAMPLING BOUND and reads INSUFFICIENT, never a margin. Incomplete Vctrl"
  echo "  coverage, INVALID waveforms, duplicate or legacy evidence and a missing"
  echo "  baseline row-7 grade are INSUFFICIENT with the grader's reason."
  echo "- **Row 4 carries its method and limits** (\`sim/phase-noise/README.md\`)."
  echo "  ngspice has no PSS/pnoise; \`L(df)\` is an ISF (Hajimiri-Lee) derivation"
  echo "  at one operating point (\`Vctrl\` = ${PN_VCTRL} V), the spread is the"
  echo "  sample sd over injected-charge realisations (not a Monte-Carlo"
  echo "  variance), and the non-PDK inductor model's bars (Q +-${PN_IND_Q_BAR_PCT} %,"
  echo "  fit ${PN_IND_FIT_BAR_PCT} %) apply. A movement inside the printed combined"
  echo "  spread is flagged in the reason column."
  echo "- **Row 6 is a proxy bracket**; the conservative lower end is used on"
  echo "  both sides. Ladder rungs are coarse, so margin movements are quantised."
  echo "- Stage 2 is a two-point large-signal secant across +-10 %; it is not a"
  echo "  substitute for row 9's pushing measurement and vice versa."
  echo "- Phase noise: baseline records without identity rows (older pilots) are"
  echo "  unidentifiable and therefore unavailable, not guessed."
} > "${MD}"

echo "stage-2 report: ${CSV}"
echo "stage-2 report: ${MD}"
echo "OVERALL: ${OVERALL}"
exit 0
