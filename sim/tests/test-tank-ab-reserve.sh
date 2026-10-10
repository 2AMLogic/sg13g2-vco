#!/usr/bin/env bash
# Simulator-free integration fixture for sim/bn-substrate-tank/run_tank_ab.sh
# (issue #203): record/work namespaces come from reserve_record_id. Request
# generation and the fleet client are stubbed; nothing is simulated or submitted.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "${HERE}/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
bad() { fail=$((fail + 1)); echo "FAIL - $1"; }

# Scratch copy of the layout: $T/sim/{lib.sh,bn-substrate-tank/run_tank_ab.sh}
mkdir -p "$T/sim/bn-substrate-tank"
cp "$SRC/lib.sh" "$T/sim/lib.sh"
cp "$SRC/bn-substrate-tank/run_tank_ab.sh" "$T/sim/bn-substrate-tank/"
EXP="$T/sim/bn-substrate-tank"
cat > "$T/mkreq.py" <<'P'
import sys, pathlib
w = pathlib.Path(sys.argv[1]) / "v1" / "p1"
w.mkdir(parents=True)
(w / "tank.spice").write_text("* deck\n")
(w / "request.json").write_text("{}\n")
(w / "cell.json").write_text("{}\n")
P
cat > "$T/klt" <<'P'
#!/usr/bin/env bash
echo "$PWD" >> "${SUBMIT_LOG}"
echo '{"stub":true}'
P
chmod +x "$T/klt"
export SUBMIT_LOG="$T/submits.log"
export SIM_RECORD_TS=20260101-000000 SIM_RECORD_SHA=abc1234
export TANK_AB_MAKE_REQUESTS="$T/mkreq.py" TANK_AB_KLT="$T/klt"
run() { bash "$EXP/run_tank_ab.sh" 2>"$T/stderr.$$.$BASHPID"; }

# 1. two runs, same label, frozen ts/commit -> distinct namespaces
r1="$(TANK_AB_LABEL=cand14 run | sed -n '/records\//p' | head -1)"
r2="$(TANK_AB_LABEL=cand14 run | sed -n '/records\//p' | head -1)"
if [ -n "$r1" ] && [ "$r1" != "$r2" ] && [ -d "$r1/reports" ] && [ -d "$r2/reports" ]; then
  ok "same label twice -> distinct record dirs"; else bad "distinct: '$r1' '$r2'"; fi
nw="$(ls "$T/sim/build/bn-substrate-tank" | wc -l | tr -d ' ')"
[ "$nw" = 2 ] && ok "distinct work dirs" || bad "work dirs: $nw"

# 2. label recognizable and contained
case "$r1" in "$EXP"/records/20260101-000000-abc1234-*-cand14) ok "label kept as readable suffix, inside experiment dir";; *) bad "label shape: $r1";; esac
[ -s "$r1/reports/v1__p1.json" ] && [ -f "$r1/decks/v1__p1.spice" ] && ok "evidence written under record" || bad "evidence missing"

# 3. hostile labels rejected before any write or submission
before="$(find "$T/sim" | sort | md5sum)"; subs="$(wc -l < "$SUBMIT_LOG")"
for lbl in '../../escape' 'a/b' '.hidden' '-x' 'a..b' 'a b'; do
  if TANK_AB_LABEL="$lbl" run >/dev/null; then bad "label '$lbl' accepted"; else ok "label '$lbl' rejected"; fi
done
[ "$(find "$T/sim" | sort | md5sum)" = "$before" ] && [ "$(wc -l < "$SUBMIT_LOG")" = "$subs" ] \
  && ok "rejected labels wrote/submitted nothing" || bad "rejected labels left traces"

# 4. concurrent runs never share paths
for i in 1 2 3 4; do ( TANK_AB_LABEL=par run > "$T/par.$i" ) & done
wait
n="$(cat "$T"/par.* | grep records/ | sort -u | wc -l | tr -d ' ')"
[ "$n" = 4 ] && ok "4 concurrent runs -> 4 distinct record dirs" || bad "concurrent distinct: $n"

# 5. conflicting allocation leaves pre-existing sentinels byte-identical
pre="20260101-000000-abc1234-deadbeef"
mkdir -p "$EXP/corners/$pre" "$EXP/records/$pre-cand14/decks" "$EXP/records/$pre-cand14/reports" \
         "$T/sim/build/bn-substrate-tank/$pre-cand14"
for f in "$EXP/records/$pre-cand14/decks/v1__p1.spice" "$EXP/records/$pre-cand14/decks/v1__p1.request.json" \
         "$EXP/records/$pre-cand14/decks/v1__p1.cell.json" "$EXP/records/$pre-cand14/reports/v1__p1.json" \
         "$EXP/records/$pre-cand14/reports/v1__p1.err"; do echo "sentinel $f" > "$f"; done
sum_before="$(find "$EXP/records/$pre-cand14" -type f | sort | xargs md5sum)"
out="$(SIM_RECORD_SUFFIX=deadbeef TANK_AB_LABEL=cand14 run | grep records/ | head -1)"
sum_after="$(find "$EXP/records/$pre-cand14" -type f | sort | xargs md5sum)"
[ "$sum_before" = "$sum_after" ] && ok "sentinels byte-identical after conflicting allocation" || bad "sentinels changed"
[ -n "$out" ] && [ "$out" != "$EXP/records/$pre-cand14" ] && ok "conflict resolved to a fresh namespace" || bad "conflict out: '$out'"

# 6. reservation failure -> nonzero before any evidence write or submission
rm -rf "$T/sim/build" "$EXP/records"; rm -rf "$EXP/corners"; : > "$EXP/corners"
subs="$(wc -l < "$SUBMIT_LOG")"
if TANK_AB_LABEL=cand14 run >/dev/null; then bad "reservation failure returned 0"; else ok "reservation failure is nonzero"; fi
if [ ! -e "$EXP/records" ] && [ ! -e "$T/sim/build" ] && [ "$(wc -l < "$SUBMIT_LOG")" = "$subs" ]; then
  ok "no evidence written, no submission on reservation failure"; else bad "traces after reservation failure"; fi

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
