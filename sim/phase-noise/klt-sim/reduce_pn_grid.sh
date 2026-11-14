#!/usr/bin/env bash
# Per-corner ISF reduction for the 135-corner graded grid (issue #329). Driven by
# `run_pn_sweep.sh --reduce OUTDIR`, which is the only entry point; this file is the glue,
# next to the single-corner reducer it drives.
#
#   reduce_pn_grid.sh OUTDIR        # OUTDIR is a --generate dir with returned evidence
#
# It turns a directory of returned grid units into OUTDIR/corners.csv -- the per-corner
# table grade_pn_grid.py reads -- and runs NO simulation and NO estimator of its own.
# Every number comes out of klt-sim/reduce_isf_fleet.sh, i.e. out of the same sim/lib.sh
# `pn_*` and pn_bench.sh functions run_isf_pilot.sh uses. What this file owns is the
# bookkeeping the single-corner reducer cannot: which units belong to which corner, which
# carrier and impulse spacing that corner was generated at, that corner's own port-noise
# points, the two per-corner aggregates the grader wants, and a non-pass row with a cause
# for every corner that cannot be reduced.
#
# WHAT IT EXPECTS UNDER OUTDIR
#   grid-plan.csv                 written by --generate: process, temp_c, f0_hz,
#                                 f0_source, n_units and nper PER CORNER
#   <process>_<T>C/<evidence>/    that corner's returned ISF job: report.json plus one
#                                 subdirectory per unit (corner.cir, corner.json,
#                                 waveform.raw.json)
#   noise-tank/, noise-tail/      the two port-noise jobs' returned evidence (each a
#                                 report.json covering the whole grid -- see below).
#                                 Override with PN_REDUCE_NOISE_TANK / _TAIL; pointing
#                                 either at a FILE instead passes it to the reducer as
#                                 that corner's own table (the single-corner layout).
#
# WHAT IT WRITES
#   OUTDIR/corners.csv            grade_pn_grid.py's 12 columns, in its order, plus
#                                 `cause` and `f0_source`. Extra columns are ignored by
#                                 the grader (it checks its own columns are present), so
#                                 AC "accepted unchanged" holds while a failed corner
#                                 still carries why it failed.
#   OUTDIR/reduce/<corner>/       that corner's traces + the four reducer CSVs
#   OUTDIR/reduce/<corner>.log    that corner's reduction log -- the row's raw_log
#
# Nothing is written under sim/phase-noise/records/: that tree is append-only committed
# evidence, and 135 corners x 4 CSVs would both flood it and make any re-run abort.
# Re-running --reduce over the same OUTDIR is therefore allowed and overwrites.
#
# THE CARRIER IS PER CORNER, AND SO IS THE SPACING. Each corner's f0_hz comes from
# grid-plan.csv (the oscillator-core fleet grid's measured f_osc at Vctrl 1.65 V, or that
# process's 27 C carrier where its 125 C point never oscillated) and is passed to the
# reducer as the grid-design carrier it must rebuild the impulse schedule from -- NOT
# re-measured here: the impulse instants are baked into that corner's PWL sources at
# generation time, so feeding a measured carrier back in would read the steps at instants
# the deck never injected at. The measured carrier still reaches the output, as the
# grader's f0_hz column (summary f0_measured) and as f0_grid_error_pct in the corner's own
# summary. `nper` travels the same way and for the same reason.
#
# A CORNER IS NEVER DROPPED AND NEVER GIVEN A NUMBER IT DID NOT EARN. Every row of
# grid-plan.csv produces exactly one row here. If anything -- missing evidence, a unit the
# fleet failed, an incomplete ensemble, an invalid trace, an unresolvable port-noise
# value -- stops the reduction, the row carries a non-pass status from the grader's own
# vocabulary (sim_error | no_oscillation | invalid), the cause, and its raw_log, with
# every measured column left empty. The 45 125 C corners are EXPECTED to land here: every
# oscillator-core fleet unit at 125 C aborted with timestep_too_small (README.md), so a
# corners.csv full of non-pass 125 C rows is a correct output, not a failure of this file.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENT_DIR="$(cd "${HERE}/.." && pwd)"; SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
# shellcheck source=../../lib.sh
source "${SIM_DIR}/lib.sh"
# shellcheck source=../pn_bench.sh
source "${EXPERIMENT_DIR}/pn_bench.sh"

REDUCER="${HERE}/reduce_isf_fleet.sh"
EXTRACT="${HERE}/extract_vdiff.py"
REPORT="${HERE}/fleet_report.py"

[[ -n "${1:-}" ]] || { echo "usage: $0 OUTDIR  (an OUTDIR from run_pn_sweep.sh --generate)" >&2; exit 2; }
OUTDIR="$(cd "$1" && pwd)" || exit 2
PLAN="${OUTDIR}/grid-plan.csv"
[[ -f "${PLAN}" ]] || { echo "error: ${PLAN} missing; run --generate first" >&2; exit 2; }
RED="${OUTDIR}/reduce"; mkdir -p "${RED}"
CORNERS_CSV="${OUTDIR}/corners.csv"
NOISE_TANK="${PN_REDUCE_NOISE_TANK:-${OUTDIR}/noise-tank}"
NOISE_TAIL="${PN_REDUCE_NOISE_TAIL:-${OUTDIR}/noise-tail}"

# ---- grid-plan.csv is read BY COLUMN NAME, never by position ------------------------
col() { awk -F, -v n="$1" 'NR==1 { for (i=1;i<=NF;i++) if ($i==n) { print i; exit } }' "${PLAN}"; }
C_PROC="$(col process)"; C_TEMP="$(col temp_c)"; C_F0="$(col f0_hz)"
C_SRC="$(col f0_source)"; C_UNITS="$(col n_units)"; C_NPER="$(col nper)"
for pair in "process:${C_PROC}" "temp_c:${C_TEMP}" "f0_hz:${C_F0}" "f0_source:${C_SRC}" "n_units:${C_UNITS}"; do
  [[ -n "${pair#*:}" ]] || { echo "error: ${PLAN} has no '${pair%%:*}' column" >&2; exit 2; }
done
# Fail closed rather than guess the spacing: reducing a corner at the wrong nper reads the
# excess-phase steps at instants the deck never injected at and reports nothing wrong.
[[ -n "${C_NPER}" ]] || {
  echo "error: ${PLAN} has no 'nper' column, so the impulse spacing each corner was" >&2
  echo "       generated at is unknown. Re-run --generate with the current" >&2
  echo "       gen_isf_request.py (which records it), or add the column by hand." >&2
  exit 2; }

# ---- helpers -------------------------------------------------------------------------
# sanitise <text>: one line, no commas -- corners.csv's `cause` column is unquoted.
sanitise() { tr '\n' ' ' | tr ',' ';' | sed 's/  */ /g; s/^ *//; s/ *$//' | cut -c1-400; }

# evidence_report <dir>: the single report.json at <dir> or one level below it.
evidence_report() {
  local d="$1" r n=0 hit=""
  [[ -d "${d}" ]] || { echo "no directory ${d}" >&2; return 1; }
  for r in "${d}/report.json" "${d}"/*/report.json; do
    [[ -f "${r}" ]] || continue
    n=$((n + 1)); hit="${r}"
  done
  [[ "${n}" -ne 0 ]] || { echo "no report.json at or under ${d} (nothing returned yet?)" >&2; return 1; }
  [[ "${n}" -eq 1 ]] || { echo "${n} report.json files at or under ${d} (ambiguous: keep one returned job per corner)" >&2; return 1; }
  echo "${hit}"
}

# noise_input <port> <proc> <temp> <dest>: write THIS corner's port-noise table to <dest>.
noise_input() {
  local port="$1" proc="$2" temp="$3" dest="$4" src rep
  src="${NOISE_TANK}"; [[ "${port}" == "tail" ]] && src="${NOISE_TAIL}"
  if [[ -f "${src}" ]]; then cp "${src}" "${dest}"; return 0; fi
  if ! rep="$(evidence_report "${src}" 2>&1)"; then
    echo "${port}-port noise: ${rep}" >&2; return 1
  fi
  python3 "${REPORT}" inoise "${rep}" --process "${proc}" --temp "${temp}" \
    --npts "${PN_NOISE_NPTS}" --fstart "${PN_NOISE_FSTART}" --fstop "${PN_NOISE_FSTOP}" > "${dest}"
}

# summary_value <summary.csv> <quantity>
summary_value() { awk -F, -v k="$2" '$1 == k { print $2; exit }' "$1"; }

# job_id_for <corner evidence report path> <corner dir>: evidence receipt, then the
# corner's own, then the batch-set receipt --submit wrote for the whole grid.
job_id_for() {
  local rep="$1" cdir="$2" r
  for r in "$(dirname "${rep}")/batch-receipt.json" "${cdir}/batch-receipt.json" "${OUTDIR}/batch-receipt.json"; do
    [[ -f "${r}" ]] || continue
    python3 "${REPORT}" job-id "${r}" 2>/dev/null && return 0
  done
  echo ""
}

# ---- the per-corner reduction ---------------------------------------------------------
# Sets STATUS and CAUSE; on STATUS=pass also L1 L10 L1SD BAR NPL RIP F0M JOB.
# Everything it prints goes to the corner's own log, which becomes the row's raw_log.
STATUS=""; CAUSE=""; L1=""; L10=""; L1SD=""; BAR=""; NPL=""; RIP=""; F0M=""; JOB=""
reduce_corner() {
  local proc="$1" temp="$2" f0="$3" nper="$4" nunits="$5"
  local cdir="${OUTDIR}/${proc}_${temp}C" wdir="${RED}/${proc}_${temp}C"
  local rep units nonpass got cid traces summary isf
  STATUS=""; CAUSE=""; L1=""; L10=""; L1SD=""; BAR=""; NPL=""; RIP=""; F0M=""; JOB=""
  rm -rf "${wdir}"; mkdir -p "${wdir}"

  echo "[corner] ${proc} ${temp}C  f0_nominal=${f0} Hz  nper=${nper}  expected units=${nunits}"
  if [[ ! -d "${cdir}" ]]; then
    STATUS=sim_error; CAUSE="no request directory ${cdir##*/} under OUTDIR (corner never generated)"; return 0
  fi
  if ! rep="$(evidence_report "${cdir}" 2>&1)"; then
    STATUS=sim_error; CAUSE="no returned ISF evidence: ${rep}"; return 0
  fi
  echo "[corner] report ${rep#"${OUTDIR}/"}"

  # (1) did the fleet run every unit of this corner?
  if ! units="$(python3 "${REPORT}" units "${rep}" 2>&1)"; then
    STATUS=sim_error; CAUSE="unreadable report: ${units}"; return 0
  fi
  printf '%s\n' "${units}"
  got="$(printf '%s\n' "${units}" | grep -c '[^[:space:]]' || true)"
  if [[ "${got}" -lt "${nunits}" ]]; then
    STATUS=sim_error; CAUSE="incomplete ensemble: ${got} of ${nunits} units returned"; return 0
  fi
  nonpass="$(printf '%s\n' "${units}" | awk -F'\t' '$1 != "pass" { printf "%s(%s) ", $2, $1 }')"
  if [[ -n "${nonpass}" ]]; then
    local why=""
    grep -rlq 'Timestep too small' "$(dirname "${rep}")" 2>/dev/null && why=" [ngspice: Timestep too small]"
    STATUS=sim_error; CAUSE="fleet did not pass every unit: ${nonpass}${why}"; return 0
  fi

  # (2) which units are this corner's? Derived from the report's own corner_ids rather
  #     than assumed from a filename, because extract_vdiff.py names its outputs from
  #     dqd/dqt alone and would silently overwrite across corners sharing a directory.
  cid="$(printf '%s\n' "${units}" | awk -F'\t' -v p="^${proc}/" -v t="/${temp}C/" \
         '$2 ~ p && index($2, t) > 0 { s = $2; sub(/params:.*$/, "", s); print s }' | sort -u)"
  if [[ -z "${cid}" ]]; then
    STATUS=sim_error; CAUSE="report has no unit whose corner_id is ${proc}/.../${temp}C/..."; return 0
  fi
  if [[ "$(printf '%s\n' "${cid}" | grep -c '[^[:space:]]')" -ne 1 ]]; then
    STATUS=sim_error; CAUSE="report mixes $(printf '%s\n' "${cid}" | tr '\n' ' ') for this corner"; return 0
  fi
  echo "[corner] unit prefix ${cid}"

  # (3) traces
  traces="${wdir}/traces"
  local xout
  if ! xout="$(python3 "${EXTRACT}" "$(dirname "${rep}")" "${traces}" --corner "${cid}" 2>&1)"; then
    printf '%s\n' "${xout}"
    STATUS=invalid; CAUSE="trace extraction failed for ${cid}: $(printf '%s' "${xout}" | tail -1)"; return 0
  fi
  printf '%s\n' "${xout}"

  # (4) this corner's own port noise -- NOT the job's cross-corner `worst=`
  local nout
  for port in tank tail; do
    if ! nout="$(noise_input "${port}" "${proc}" "${temp}" "${wdir}/inoise-${port}.txt" 2>&1)"; then
      printf '%s\n' "${nout}"
      STATUS=sim_error; CAUSE="${port}-port noise unresolved for ${proc} ${temp}C: $(printf '%s' "${nout}" | tail -1)"; return 0
    fi
    printf '%s\n' "${nout}"
  done

  # (5) the SAME single-corner reducer, with this corner's identity, carrier and spacing
  local rout err
  if ! rout="$("${REDUCER}" --process "${proc}" --temp "${temp}" --nper "${nper}" --f0 "${f0}" \
        --outdir "${wdir}" "${traces}" "${wdir}/inoise-tank.txt" "${wdir}/inoise-tail.txt" \
        "${proc}_${temp}C" 2>&1)"; then
    printf '%s\n' "${rout}"
    # Classify from what the reducer itself refused on -- captured here, not re-read from
    # the log this function's own stdout is still being written into -- so the row's
    # status is a fact about this corner rather than a catch-all.
    err="$(printf '%s\n' "${rout}" | grep -m1 '^error:' || true)"
    if printf '%s\n' "${rout}" | grep -q 'did not oscillate'; then STATUS=no_oscillation
    elif printf '%s\n' "${rout}" | grep -q 'is invalid over'; then STATUS=invalid
    elif printf '%s\n' "${rout}" | grep -qE 'ensemble incomplete|pn_reduce_ensemble:'; then STATUS=invalid
    else STATUS=sim_error; fi
    CAUSE="${err:-reduction failed with no error line}"; return 0
  fi
  printf '%s\n' "${rout}"

  summary="${wdir}/${proc}_${temp}C-pilot-summary.csv"
  isf="${wdir}/${proc}_${temp}C-pilot-isf.csv"
  L1="$(summary_value "${summary}" l_1mhz_mean)"
  L10="$(summary_value "${summary}" l_10mhz_mean)"
  L1SD="$(summary_value "${summary}" l_1mhz_sd)"
  BAR="$(summary_value "${summary}" inductor_bar_total)"
  F0M="$(summary_value "${summary}" f0_measured)"
  # The grader wants the two per-corner AGGREGATES of what the reducer records per
  # impulse: the MIN plateau crossing count (it gates on >= 3) and the WORST plateau
  # ripple. Both over every impulse of every realisation of this corner.
  NPL="$(awk -F, "${PN_AWK_FINITE}"'NR>1 && pn_fin($10) { if (m == "" || $10+0 < m) m = $10+0 }
          END { print (m == "") ? "nan" : m }' "${isf}")"
  RIP="$(awk -F, "${PN_AWK_FINITE}"'NR>1 && pn_fin($9) { if (m == "" || $9+0 > m) m = $9+0 }
          END { if (m == "") print "nan"; else printf "%.6e", m }' "${isf}")"
  JOB="$(job_id_for "${rep}" "${cdir}")"
  STATUS=pass; CAUSE=""
  echo "[corner] ${proc} ${temp}C: L(1MHz)=${L1} dBc/Hz sd=${L1SD}, L(10MHz)=${L10}, n_plateau_min=${NPL}"
}

# ---- drive every corner the plan declares --------------------------------------------
{
  printf 'process,temp_c,status,l_1mhz_dbc,l_10mhz_dbc,l_1mhz_sd_db,inductor_bar_db,'
  printf 'n_plateau_min,plateau_ripple_max_s,f0_hz,job_id,raw_log,cause,f0_source\n'
} > "${CORNERS_CSV}"
NPASS=0; NFAIL=0
while IFS=' ' read -r proc temp f0 src nper nunits; do
  [[ -n "${proc}" ]] || continue
  LOGFILE="${RED}/${proc}_${temp}C.log"
  reduce_corner "${proc}" "${temp}" "${f0}" "${nper}" "${nunits}" > "${LOGFILE}" 2>&1 || {
    STATUS=sim_error; CAUSE="reduce_corner aborted; see raw_log"; }
  # A status this driver did not set is not a pass. An unguarded failure inside
  # reduce_corner must surface as a listed non-pass corner, never as a blank cell the
  # grader has to interpret (sim/README.md rule 4).
  [[ -n "${STATUS}" ]] || { STATUS=sim_error; CAUSE="reduction left no status; see raw_log"; }
  CAUSE="$(printf '%s' "${CAUSE}" | sanitise)"
  if [[ "${STATUS}" == "pass" ]]; then NPASS=$((NPASS + 1)); else NFAIL=$((NFAIL + 1)); fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "${proc}" "${temp}" "${STATUS}" "${L1}" "${L10}" "${L1SD}" "${BAR}" \
    "${NPL}" "${RIP}" "${F0M}" "${JOB}" "reduce/${proc}_${temp}C.log" "${CAUSE}" "${src}" \
    >> "${CORNERS_CSV}"
  printf '%-14s %5sC  %-14s %s\n' "${proc}" "${temp}" "${STATUS}" "${CAUSE}"
done < <(awk -F, -v p="${C_PROC}" -v t="${C_TEMP}" -v f="${C_F0}" -v s="${C_SRC}" \
             -v n="${C_NPER}" -v u="${C_UNITS}" \
             'NR > 1 && NF > 1 { print $p, $t, $f, $s, $n, $u }' "${PLAN}")

echo "wrote ${CORNERS_CSV}: ${NPASS} pass, ${NFAIL} non-pass of $((NPASS + NFAIL)) corner(s)"
echo "grade it with: run_pn_sweep.sh --grade ${CORNERS_CSV}"
