# Source me:  source "${EXPERIMENT_DIR}/supply_stage2.sh"
#
# PDK-FREE definition of DR-004 stage 2 (issue #113): the 18 supply
# sub-corners, their aggregate process mappings and the escalation criterion's
# constants. Not an entry point (no shebang). It loads no PDK, runs no
# simulator and needs only bash and awk, so .github/scripts/run-method-checks.sh
# can verify the enumeration on every pull request.
#
# WHAT DR-004 SAYS (spec/decision-records/DR-004-target-spec-ratification-pass-2.md,
# "Row 10's +-10 % supply sub-corners"):
#   stage 2 = {2.970, 3.630} V x {SLOW, TYP, FAST} x {-40, +27, +125} C
#   where the process vertices are AGGREGATE, not a cross:
#     SLOW = MOS ss + HBT hbt_wcs + MIM cap_wcs
#     TYP  = MOS tt + HBT hbt_typ + MIM cap_typ
#     FAST = MOS ff + HBT hbt_bcs + MIM cap_bcs
#   reported rows: 1, 4, 6, 7, 8.
#   stage 3 (conditional): if stage 2 moves any row's margin, at any of the 18
#   points, by more than the margin stage 1 left on that row, the full 405
#   point cross becomes required -- via a superseding decision record. This
#   code REPORTS that status; it never edits the spec and never launches the
#   405-point grid.
#
# shellcheck shell=bash
# shellcheck disable=SC2034  # every S2_* constant is read by the scripts that source this file

S2_RAILS="2.970 3.630"
S2_PROCESSES="SLOW TYP FAST"
S2_TEMPS="-40 27 125"
S2_N_POINTS=18

# The Vctrl axis stage 2 sweeps for rows 1/7/8. It MUST equal the stage-1
# axis in run_pvt_sweep.sh, or "matching nominal result" would compare curves
# on different abscissae; tests/test_supply_stage2.sh asserts the equality by
# reading both files.
S2_VCTRL_LIST="0.0 0.3 0.6 0.9 1.2 1.65 1.8 2.4 3.0 3.3"
S2_BAND_CENTRE_VCTRL="1.65"

# Row-6 margin pass: rails x {SLOW,FAST} x {-40,+125} (DR-004's 8 corners x 9
# rungs = 72 rungs), the process vertices and temperatures where the startup
# margin is worst/best.
S2_MARGIN_PROCESSES="SLOW FAST"
S2_MARGIN_TEMPS="-40 125"

# Nominal-rail value stage 1 ran at; the baseline a stage-2 point is compared to.
S2_NOMINAL_RAIL="3.3"

# s2_process_map <SLOW|TYP|FAST> -- print "<mos> <cap> <hbt>" ; rc 1 if unknown.
s2_process_map() {
  case "$1" in
    SLOW) echo "ss cap_wcs hbt_wcs" ;;
    TYP)  echo "tt cap_typ hbt_typ" ;;
    FAST) echo "ff cap_bcs hbt_bcs" ;;
    *) echo "s2_process_map: unknown process vertex '$1'" >&2; return 1 ;;
  esac
}

# s2_vertex_of <mos> <cap> <hbt> -- the inverse; prints the vertex name or
# nothing (rc 1) when the triple is not one of the three aggregates.
s2_vertex_of() {
  local v m
  for v in ${S2_PROCESSES}; do
    m="$(s2_process_map "${v}")"
    if [[ "${m}" == "$1 $2 $3" ]]; then echo "${v}"; return 0; fi
  done
  return 1
}

# s2_point_id <process> <rail> <temp> [vctrl] -- the stable identity of one
# stage-2 point. The rail is IN the id, so no two rails can collide in a
# corner_id column.
s2_point_id() {
  local id="s2_$1_$2v_$3c"
  [[ -n "${4:-}" ]] && id="${id}_$4v"
  echo "${id}"
}

# s2_enumerate -- one line per sub-corner:
#   <process> <rail> <temp> <mos> <cap> <hbt>
# in the order rail, process, temperature.
s2_enumerate() {
  local rail proc temp mos cap hbt
  for rail in ${S2_RAILS}; do
    for proc in ${S2_PROCESSES}; do
      read -r mos cap hbt <<<"$(s2_process_map "${proc}")"
      for temp in ${S2_TEMPS}; do
        echo "${proc} ${rail} ${temp} ${mos} ${cap} ${hbt}"
      done
    done
  done
}

# s2_enumerate_margin -- the row-6 subset, same line format.
s2_enumerate_margin() {
  local rail proc temp mos cap hbt
  for rail in ${S2_RAILS}; do
    for proc in ${S2_MARGIN_PROCESSES}; do
      read -r mos cap hbt <<<"$(s2_process_map "${proc}")"
      for temp in ${S2_MARGIN_TEMPS}; do
        echo "${proc} ${rail} ${temp} ${mos} ${cap} ${hbt}"
      done
    done
  done
}

# s2_check_enumeration -- self-consistency of the declaration; rc 0 or a
# message on stderr. Exactly 18 distinct points, every mapping an aggregate.
s2_check_enumeration() {
  local n nd
  n="$(s2_enumerate | wc -l | tr -d ' ')"
  nd="$(s2_enumerate | sort -u | wc -l | tr -d ' ')"
  if [[ "${n}" != "${S2_N_POINTS}" || "${nd}" != "${S2_N_POINTS}" ]]; then
    echo "stage 2 must enumerate exactly ${S2_N_POINTS} distinct sub-corners; got ${n} (${nd} distinct)" >&2
    return 1
  fi
  return 0
}

# s2_finite <value> -- rc 0 iff <value> is a finite real number in plain decimal
# or scientific notation: optional sign, digits, optional fraction, optional
# exponent. NaN/inf/Infinity spellings, empty strings, hex and text are
# rejected by the grammar; an exponent that overflows a double ("1e999") is
# rejected because the awk-coerced value x then lies outside [-DBL_MAX,
# DBL_MAX] (it became +/-inf). The bound comparison is used rather than the
# NaN-arithmetic idiom "x - x == 0", which is awk-implementation dependent:
# mawk 1.3.4 evaluates (inf - inf == 0) as true. The grammar admits no NaN
# spelling, so x is never NaN here. Every number the stage-2 grader does
# arithmetic on, or matches an identity by, passes this first, so awk's silent
# coercion of text to 0 never reaches a margin.
S2_DBL_MAX=1.7976931348623157e308
s2_finite() {
  [[ "$1" =~ ^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$ ]] || return 1
  awk -v v="$1" -v m="${S2_DBL_MAX}" 'BEGIN { x = v + 0; m = m + 0; exit (x >= -m && x <= m) ? 0 : 1 }'
}

# The same test for awk programs (the report getters read CSV fields in awk):
# prepend this to a program that calls s2_fin(field).
# shellcheck disable=SC2016  # awk source, expanded by awk, not by the shell
S2_AWK_FINITE='
function s2_fin(s,  x) {
  if (s !~ /^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/) return 0
  x = s + 0
  return (x >= -1.7976931348623157e308 && x <= 1.7976931348623157e308)
}
'

# s2_status_reason <m1> <m2> -- prints "-" when both margins are usable or are
# the legitimate "unavailable" markers (nan / empty: the getter has already said
# why); otherwise the field and reason a margin was rejected as invalid.
s2_status_reason() {
  local f v
  for f in m1 m2; do
    if [[ "${f}" == m1 ]]; then v="$1"; else v="$2"; fi
    [[ "${v}" == "nan" || -z "${v}" ]] && continue
    s2_finite "${v}" || { echo "${f} '${v}' is not a finite number"; return 0; }
  done
  echo "-"
}

# s2_status <m1> <m2> -- the escalation criterion for ONE (row, point), pure
# arithmetic on the two margins (both in the row's own unit, positive = inside
# the bound, "nan" = unavailable). Prints one status token:
#
#   INSUFFICIENT                 either margin unavailable
#   ESCALATION_REQUIRED          |m2 - m1| > m1        (m1 > 0: the movement
#                                 exceeds the margin stage 1 left)
#                                or m1 <= 0 and m2 < m1 (stage 1 left no
#                                 margin and the rail made it worse)
#   NO_ESCALATION                otherwise
#
# DR-004 words the trigger as "moves ... by MORE THAN the margin stage 1 left",
# which is read LITERALLY: the absolute movement is compared, so a favourable
# movement larger than the remaining margin also triggers it (it still shows
# the rail is not a small perturbation of stage 1). Where stage 1 left no
# margin (m1 <= 0) there is nothing for a favourable movement to exceed, so
# only an adverse movement counts. Equality is NOT a trigger ("more than").
#
# Both margins are validated (s2_finite) BEFORE any arithmetic: text, NaN/inf
# spellings and overflowing exponents are INSUFFICIENT, never coerced to 0
# (s2_status 1 garbage used to read NO_ESCALATION). The thresholds and the
# comparison below are unchanged.
s2_status() {
  local v
  for v in "$1" "$2"; do
    if [[ "${v}" == "nan" || -z "${v}" ]] || ! s2_finite "${v}"; then echo INSUFFICIENT; return 0; fi
  done
  awk -v m1="$1" -v m2="$2" 'BEGIN {
    if (m1 == "nan" || m2 == "nan" || m1 == "" || m2 == "") { print "INSUFFICIENT"; exit }
    d = m2 - m1; ad = (d < 0) ? -d : d
    if (m1 > 0) { print (ad > m1) ? "ESCALATION_REQUIRED" : "NO_ESCALATION"; exit }
    print (m2 < m1) ? "ESCALATION_REQUIRED" : "NO_ESCALATION"
  }'
}
