#!/usr/bin/env bash
# Self-test for check-grader-spec-agreement.sh (issue #138). Every case works
# on a temp copy of the tracked spec, DR-004 and the three graders, mutates
# exactly one thing, and asserts the verdict plus the offending name in the
# output. The checker reads expected values from the spec text only, so a
# grader-constant edit alone must fail.
#   baseline passes; equivalent numeric forms pass
#   isolated OSC_* / PN_ROW4_* / S2_* grader edits fail, naming the variable
#   isolated spec-table and DR-004 edits fail (grader unchanged)
#   window / rail / temperature / point-count drift fails
#   malformed or missing spec rows/fields, DR, or grader literals fail
#   a new unmapped ROW-numbered grader constant fails
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CHECKER="$HERE/check-grader-spec-agreement.sh"
[ -x "$CHECKER" ] || { echo "FAIL: $CHECKER not executable" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 missing" >&2; exit 1; }

OSC=sim/oscillator-core/osc_bench.sh
PN=sim/phase-noise/pn_bench.sh
S2=sim/oscillator-core/supply_stage2.sh
SPEC=spec/target-spec.md
DR="$(cd "$REPO" && ls spec/decision-records/DR-004-*.md | head -n1)"
[ -n "$DR" ] || { echo "FAIL: no DR-004 record" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "${T:?}"' EXIT
G="$T/w"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# fresh: a clean temp copy of everything the checker reads, at $G.
fresh() {
  rm -rf "${G:?}"
  local f
  for f in "$SPEC" "$DR" "$OSC" "$PN" "$S2"; do
    mkdir -p "$G/$(dirname "$f")"; cp "$REPO/$f" "$G/$f"
  done
}
# mutate <file> <old> <new>: replace exactly one occurrence in the copy.
mutate() {
  python3 -I - "$G/$1" "$2" "$3" <<'PY' || { echo "FIXTURE ERROR: mutate $1 '$2'" >&2; exit 99; }
import sys
p, old, new = sys.argv[1:4]
t = open(p, encoding="utf-8").read()
if t.count(old) != 1:
    sys.exit("expected exactly 1 occurrence of %r in %s, found %d" % (old, p, t.count(old)))
open(p, "w", encoding="utf-8").write(t.replace(old, new))
PY
}
expect_pass() {  # expect_pass <name>
  if out="$("$CHECKER" --root "$G" 2>&1)"; then ok "$1"; else bad "$1: $out"; fi
}
# expect_fail <name> <needle>...: nonzero exit, every needle in the output.
expect_fail() {
  local name="$1" n; shift
  if out="$("$CHECKER" --root "$G" 2>&1)"; then bad "$name: unexpectedly passed"; return; fi
  for n in "$@"; do
    case "$out" in *"$n"*) ;; *) bad "$name: output lacks '$n': $out"; return ;; esac
  done
  ok "$name"
}
gfail() {  # gfail <name> <file> <old> <new> <needle>...
  local name="$1" f="$2" o="$3" nw="$4"; shift 4
  fresh; mutate "$f" "$o" "$nw"; expect_fail "$name" "$@"
}
gpass() {  # gpass <name> <file> <old> <new>
  fresh; mutate "$2" "$3" "$4"; expect_pass "$1"
}

fresh; expect_pass "current tree values agree (temp copy)"
if "$CHECKER" --root "$REPO" >/dev/null 2>&1; then ok "checked-out tree passes"; else bad "checked-out tree fails"; fi

# --- isolated grader edits (spec untouched) ---------------------------------
gfail "OSC_ROW1_F_MAX_HZ edit fails" $OSC 'OSC_ROW1_F_MAX_HZ="5.5e9"' 'OSC_ROW1_F_MAX_HZ="5.6e9"' OSC_ROW1_F_MAX_HZ "spec row 1"
gfail "OSC_ROW2_RATIO_STRETCH edit fails" $OSC 'OSC_ROW2_RATIO_STRETCH="1.20"' 'OSC_ROW2_RATIO_STRETCH="1.25"' OSC_ROW2_RATIO_STRETCH "spec row 2"
gfail "OSC_ROW3_KVCO floor edit fails" $OSC 'OSC_ROW3_KVCO_MEAN_MIN_HZ_PER_V="381e6"' 'OSC_ROW3_KVCO_MEAN_MIN_HZ_PER_V="380e6"' OSC_ROW3_KVCO_MEAN_MIN_HZ_PER_V "spec row 3"
gfail "OSC_ROW3_CHORD_INL_PCT edit fails" $OSC 'OSC_ROW3_CHORD_INL_PCT="30"' 'OSC_ROW3_CHORD_INL_PCT="35"' OSC_ROW3_CHORD_INL_PCT "spec row 3"
gfail "OSC_ROW6_MARGIN edit fails" $OSC 'OSC_ROW6_MARGIN="3.0"' 'OSC_ROW6_MARGIN="2.5"' OSC_ROW6_MARGIN "spec row 6"
gfail "OSC_ROW7_BVCEO_MIN_V edit fails" $OSC 'OSC_ROW7_BVCEO_MIN_V="2.2"' 'OSC_ROW7_BVCEO_MIN_V="2.4"' OSC_ROW7_BVCEO_MIN_V "spec row 7"
gfail "OSC_ROW8_P_MAX_W edit fails" $OSC 'OSC_ROW8_P_MAX_W="10e-3"' 'OSC_ROW8_P_MAX_W="12e-3"' OSC_ROW8_P_MAX_W "spec row 8"
gfail "OSC_VDD_NOM edit fails" $OSC 'OSC_VDD_NOM="3.3"' 'OSC_VDD_NOM="3.0"' OSC_VDD_NOM "spec row 0"
gfail "PN_ROW4_1M_TARGET edit fails" $PN 'PN_ROW4_1M_TARGET="-105"' 'PN_ROW4_1M_TARGET="-100"' PN_ROW4_1M_TARGET "spec row 4"
gfail "PN_ROW4_10M_STRETCH edit fails" $PN 'PN_ROW4_10M_STRETCH="-135"' 'PN_ROW4_10M_STRETCH="-130"' PN_ROW4_10M_STRETCH "spec row 4"

# --- window / supply / temperature condition drift ---------------------------
gfail "OSC_ROW3_V_LO window drift fails" $OSC 'OSC_ROW3_V_LO="1.65"' 'OSC_ROW3_V_LO="1.5"' OSC_ROW3_V_LO "spec row 3"
gfail "OSC_ROW3_V_HI window drift fails" $OSC 'OSC_ROW3_V_HI="3.30"' 'OSC_ROW3_V_HI="3.00"' OSC_ROW3_V_HI "spec row 3"
gfail "OSC_ROW3_V_FULL_LO drift fails" $OSC 'OSC_ROW3_V_FULL_LO="0.0"' 'OSC_ROW3_V_FULL_LO="0.3"' OSC_ROW3_V_FULL_LO "spec row 3"
gfail "S2_RAILS drift fails" $S2 'S2_RAILS="2.970 3.630"' 'S2_RAILS="2.970 3.600"' S2_RAILS
gfail "S2_RAILS wrong element count fails" $S2 'S2_RAILS="2.970 3.630"' 'S2_RAILS="2.970"' S2_RAILS
gfail "S2_NOMINAL_RAIL drift fails" $S2 'S2_NOMINAL_RAIL="3.3"' 'S2_NOMINAL_RAIL="3.0"' S2_NOMINAL_RAIL
gfail "S2_TEMPS drift fails" $S2 'S2_TEMPS="-40 27 125"' 'S2_TEMPS="-40 27 85"' S2_TEMPS
gfail "S2_PROCESSES drift fails" $S2 'S2_PROCESSES="SLOW TYP FAST"' 'S2_PROCESSES="SLOW FAST"' S2_PROCESSES
gfail "S2_N_POINTS drift fails" $S2 'S2_N_POINTS=18' 'S2_N_POINTS=12' S2_N_POINTS

# --- isolated spec / DR edits (graders untouched) ----------------------------
gfail "spec row 1 minimum edit fails" $SPEC '| 1 | Center / target band | 4.5 GHz |' '| 1 | Center / target band | 4.6 GHz |' OSC_ROW1_F_MIN_HZ "spec row 1"
gfail "spec row 4 bound edit fails" $SPEC '≤ −105 dBc/Hz @ 1 MHz (target)' '≤ −104 dBc/Hz @ 1 MHz (target)' PN_ROW4_1M_TARGET "spec row 4"
gfail "spec row 4 companion edit fails" $SPEC '≤ −125 target / ≤ −135 stretch' '≤ −126 target / ≤ −135 stretch' PN_ROW4_10M_TARGET
gfail "spec row 3 window edit fails" $SPEC 'window `W` = [1.65, 3.30] V' 'window `W` = [1.60, 3.30] V' OSC_ROW3_V_LO
gfail "spec row 7 swing edit fails" $SPEC '| 0.40 V Vpp (0.65 V stretch) |' '| 0.45 V Vpp (0.65 V stretch) |' OSC_ROW7_VPP_MIN_V "spec row 7"
gfail "spec row 8 ceiling edit fails" $SPEC '≤ 10 mW core (target)' '≤ 9 mW core (target)' OSC_ROW8_P_MAX_W
gfail "spec row 0 maximum edit fails" $SPEC '| 3.63 V |' '| 3.60 V |' S2_RAILS "spec row 0"
gfail "DR-004 stage-2 rails edit fails" "$DR" '`{2.970, 3.630} V`' '`{2.970, 3.600} V`' S2_RAILS
gfail "DR-004 stage-2 temperatures edit fails" "$DR" '`{−40, +27, +125} °C`, where' '`{−40, +27, +85} °C`, where' S2_TEMPS
gfail "DR-004 point count edit fails" "$DR" 'sub-corner set: 18 points' 'sub-corner set: 12 points' S2_N_POINTS

# --- malformed / missing authority fields ------------------------------------
fresh
python3 -I - "$G/$SPEC" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
open(p, "w", encoding="utf-8").write("\n".join(l for l in lines if not l.startswith("| 4 |")))
PY
expect_fail "missing spec row 4 fails" "row 4 not found" PN_ROW4_1M_TARGET
gfail "unparseable row 4 prose fails" $SPEC '≤ −105 dBc/Hz @ 1 MHz (target)' 'about minus 105 at 1 MHz' "cannot parse" "row 4"
gfail "unsupported unit in row 1 fails" $SPEC '| 1 | Center / target band | 4.5 GHz |' '| 1 | Center / target band | 4.5 GHZZ |' "row 1" OSC_ROW1_F_MIN_HZ
gfail "row retitled fails" $SPEC '| 6 | Startup / negative-gm margin' '| 6 | Something else margin' "row 6" OSC_ROW6_MARGIN
gfail "row with wrong cell count fails" $SPEC '| 6 | Startup / negative-gm margin' '| 6 | Startup / negative-gm margin | extra' "row 6" OSC_ROW6_MARGIN
gfail "missing row 3 window prose fails" $SPEC 'window `W` = [1.65, 3.30] V' 'window W unspecified' "row 3" OSC_ROW3_V_LO
gfail "unparseable DR-004 stage-2 prose fails" "$DR" 'sub-corner set: 18 points' 'sub-corner set: eighteen points' "DR-004" S2_N_POINTS
fresh; rm "${G:?}/${DR:?}"
expect_fail "missing DR-004 fails" "DR-004" S2_RAILS
fresh; rm "${G:?}/${SPEC:?}"
expect_fail "missing spec file fails" "$SPEC"
gfail "removed grader constant fails" $PN 'PN_ROW4_1M_TARGET="-105"' '# removed' PN_ROW4_1M_TARGET "no top-level assignment"
gfail "non-literal grader constant fails" $OSC 'OSC_ROW6_MARGIN="3.0"' 'OSC_ROW6_MARGIN="${OSC_X:-3.0}"' OSC_ROW6_MARGIN "not a plain literal"
gfail "non-numeric grader token fails" $OSC 'OSC_ROW6_MARGIN="3.0"' 'OSC_ROW6_MARGIN="three"' OSC_ROW6_MARGIN "non-numeric"
fresh; printf 'OSC_ROW6_MARGIN="3.5"\n' >> "$G/$OSC"
expect_fail "conflicting duplicate assignment fails" OSC_ROW6_MARGIN "more than once"
fresh; printf 'OSC_ROW9_PUSH_MAX="50e6"\n' >> "$G/$OSC"
expect_fail "new constant for an unconsumed row fails" OSC_ROW9_PUSH_MAX "row 9" "no mapping"
fresh; printf 'OSC_ROW3_NEW_BOUND="1"\n' >> "$G/$OSC"
expect_fail "new unmapped ROW constant fails" OSC_ROW3_NEW_BOUND "no mapping"

# --- equivalent numeric forms compare equal ----------------------------------
gpass "grader 4.5e9 as 4500000000"            $OSC 'OSC_ROW1_F_MIN_HZ="4.5e9"' 'OSC_ROW1_F_MIN_HZ="4500000000"'
gpass "grader 5.5e9 as 5.50E9"                $OSC 'OSC_ROW1_F_MAX_HZ="5.5e9"' 'OSC_ROW1_F_MAX_HZ="5.50E9"'
gpass "grader S2_RAILS as 2.97 3.63"          $S2 'S2_RAILS="2.970 3.630"' 'S2_RAILS="2.97 3.63"'
gpass "grader unquoted S2_N_POINTS + comment" $S2 'S2_N_POINTS=18' 'S2_N_POINTS=18.0 # eighteen'
gpass "grader 10e-3 W as 0.010"               $OSC 'OSC_ROW8_P_MAX_W="10e-3"' 'OSC_ROW8_P_MAX_W="0.010"'
gpass "grader ratio 1.15 as 1.150"            $OSC 'OSC_ROW2_RATIO="1.15"' 'OSC_ROW2_RATIO="1.150"'
gpass "grader Kvco 381e6 as 3.81e8"           $OSC 'OSC_ROW3_KVCO_MEAN_MIN_HZ_PER_V="381e6"' 'OSC_ROW3_KVCO_MEAN_MIN_HZ_PER_V="3.81e8"'
gpass "grader -105 as -105.0"                 $PN 'PN_ROW4_1M_TARGET="-105"' 'PN_ROW4_1M_TARGET="-105.0"'
gpass "grader temps with explicit plus signs" $S2 'S2_TEMPS="-40 27 125"' 'S2_TEMPS="-40 +27 +125"'
gpass "spec 4.5 GHz written as 4500 MHz"      $SPEC '| 1 | Center / target band | 4.5 GHz |' '| 1 | Center / target band | 4500 MHz |'
gpass "spec 10 mW written as 0.01 W"          $SPEC '≤ 10 mW core (target)' '≤ 0.01 W core (target)'
gpass "spec 0.40 V swing written as 400 mV"   $SPEC '| 0.40 V Vpp (0.65 V stretch) |' '| 400 mV Vpp (0.65 V stretch) |'
gpass "spec 381 MHz/V written as 381000 kHz/V" $SPEC '381 MHz/V over' '381000 kHz/V over'
gpass "spec 15 % written as 15.0 %"           $SPEC '| ≥ 15 % |' '| ≥ 15.0 % |'
gpass "spec 2.97 V written as 2.970 V"        $SPEC '| 2.97 V |' '| 2.970 V |'

echo "check-grader-spec-agreement self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
