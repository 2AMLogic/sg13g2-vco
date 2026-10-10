#!/usr/bin/env bash
# Fault-injection self-test for validated checkpoint reuse (issue #154).
# PDK-free, no simulator: sources the real lib.sh and osc_bench.sh, stubs only
# osc_render and osc_run_ngspice (ngspice is never started), and drives the
# real osc_run_point / osc_try_reuse over a small fixture grid in a mktemp
# tree. Checks that
#   1. a run interrupted after completed points checkpoints exactly the
#      finished PASS/NOSC points (a failed point gets none);
#   2. resuming under a NEW record id skips those points, executes the rest,
#      leaves every source byte untouched and distinguishes reused from
#      executed evidence (counters, reuse manifest, checkpoint lineage);
#   3. a missing, empty, truncated or digest-mismatched artifact, a truncated
#      or edited checkpoint, a missing checkpoint (legacy record) and a
#      point-identity mismatch each refuse reuse with a diagnostic and re-run;
#   4. a change of design source, template, model inputs, simulator,
#      measurement settings, rail, extractor code or CSV layout refuses reuse
#      naming the changed identity;
#   5. a reused NOSC stays NOSC (never PASS) and a failed point is retried;
#   6. a cold start (no resume source) is unchanged apart from writing
#      checkpoints, and bad restart arguments fail before reserving a record.
# shellcheck disable=SC2034  # variables are read by sourced osc_bench.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SIM_DIR="$(cd "${HERE}/.." && pwd)"
REAL_OSC="${SIM_DIR}/oscillator-core"
# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"

T="$(mktemp -d)"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
bad() { fail=$((fail + 1)); echo "FAIL - $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

REPO_ROOT="$T/repo"
EXPERIMENT_DIR="$REPO_ROOT/sim/oscillator-core"
mkdir -p "$EXPERIMENT_DIR/testbench" "$EXPERIMENT_DIR/records" "$EXPERIMENT_DIR/corners" "$T/bundle"
cp "$REAL_OSC/testbench/tb_vco_core_tran.spice.tmpl" "$EXPERIMENT_DIR/testbench/"
# shellcheck source=../oscillator-core/osc_bench.sh
source "$REAL_OSC/osc_bench.sh"

# ---- stubs: no renderer, no simulator -------------------------------------
EXEC_LOG="$T/exec.log"; : > "$EXEC_LOG"
FAIL_POINT=""; NOSC_POINT=""
osc_render() { echo "deck $3" > "$2"; }
osc_run_ngspice() {
  local c; c="$(basename "$1" .spice)"
  echo "$c" >> "$EXEC_LOG"
  echo "ngspice log $c" > "$2"
  local amp=0.2 n
  [[ "$c" == "$NOSC_POINT" ]] && amp=0
  for n in vdiff vcm vtail isup vdd; do
    awk -v a="$amp" 'BEGIN { for (i = 0; i <= 5000; i++) { t = i * 1e-12
      printf "%.6e %.6e\n", t, 1.0 + a * sin(6.283185307179586 * 5e9 * t) } }' > "$WORKDIR/tr_${c}_${n}"
  done
  if [[ "$c" == "$FAIL_POINT" ]]; then echo "rc=1 model_error=0"; else echo "rc=0 model_error=0"; fi
}

# fixture grid: id mos cap hbt temp vctrl
P1="vco_tt_cap_typ_hbt_typ_27c_1.65v"; P2="vco_tt_cap_typ_hbt_typ_27c_3.3v"
P3="vco_ss_cap_typ_hbt_typ_27c_1.65v"; P4="vco_ss_cap_typ_hbt_typ_27c_3.3v"
point_args() {
  case "$1" in
    "$P1") echo "tt cap_typ hbt_typ 27 1.65" ;; "$P2") echo "tt cap_typ hbt_typ 27 3.3" ;;
    "$P3") echo "ss cap_typ hbt_typ 27 1.65" ;; "$P4") echo "ss cap_typ hbt_typ 27 3.3" ;;
  esac
}

printf 'R1 a b 1\n' > "$T/body.spice"
printf 'models\tcornerHBT.lib\taaaa\t/x/a\ninductor\tind.spice\tbbbb\t/x/b\n' > "$T/bundle/MANIFEST.tsv"
cp "$T/body.spice" "$T/body.orig"; cp "$T/bundle/MANIFEST.tsv" "$T/manifest.orig"
cp "$EXPERIMENT_DIR/testbench/tb_vco_core_tran.spice.tmpl" "$T/tmpl.orig"
cp "$REAL_OSC/osc_bench.sh" "$T/extractor.a"; cp "$SIM_DIR/lib.sh" "$T/extractor.b"
cp "$T/extractor.a" "$T/extractor.a.orig"
OSC_EXTRACTOR_FILES="$T/extractor.a $T/extractor.b"
PDK=ihp-sg13g2

# start_run <id> [resume-source]: a fresh reserved record + scratch dir
start_run() {
  RECORD_ID="$1"
  WORKDIR="$T/work-$1"; mkdir -p "$WORKDIR"
  mkdir -p "$EXPERIMENT_DIR/corners/$1" "$EXPERIMENT_DIR/netlist-snapshots/$1"
  NETLIST_DIR="$EXPERIMENT_DIR/netlist-snapshots/$1"; LOG_DIR="$EXPERIMENT_DIR/corners/$1"
  CSV_OUT="$EXPERIMENT_DIR/records/$1.csv"
  OSC_VCO_BODY="$T/body.spice"; OSC_BUNDLE_DIR="$T/bundle"; OSC_BUNDLE_MANIFEST="$T/bundle/MANIFEST.tsv"
  OSC_NGSPICE_VERSION="ngspice-46"
  OSC_N_EXECUTED=0; OSC_N_REUSED=0; OSC_N_REJECTED=0; OSC_RESUME_FROM=""; OSC_FP_LINES=""
  osc_write_csv_headers
  if [[ -n "${2:-}" ]]; then osc_resume_init "$2" || return 1; fi
}
# run_points <points...>: one osc_run_point each, stderr to $T/err
run_points() {
  local p a
  : > "$T/err"
  for p in "$@"; do
    a="$(point_args "$p")"
    # shellcheck disable=SC2086
    osc_run_point "$p" $a "${OSC_TMAX}" >> "$T/out" 2>> "$T/err" || true
  done
}
execd() { tr '\n' ' ' < "$EXEC_LOG"; : > "$EXEC_LOG"; }
tree_sum() { # <record> -- every file the record owns, content hashed
  ( cd "$EXPERIMENT_DIR" && find "corners/$1" "netlist-snapshots/$1" records -type f -name "*$1*" -o -path "corners/$1/*" -o -path "netlist-snapshots/$1/*" 2>/dev/null \
    | sort -u | while read -r f; do echo "$f $(sha256_of "$f")"; done | sha256sum | cut -d' ' -f1 ); }
row_of() { awk -F, -v c="$2" '$1 == c' "$EXPERIMENT_DIR/records/$1.csv"; }

# -------------------- 1. interrupted run: only finished points checkpoint
SRC="20261101-000000-aaaaaaa"
FAIL_POINT="$P3"; NOSC_POINT="$P2"
start_run "$SRC"
run_points "$P1" "$P2" "$P3"      # interrupted before P4
check "cold start executed 3 points, reused 0" '[ "$OSC_N_EXECUTED $OSC_N_REUSED" = "3 0" ]'
check "PASS point checkpointed" '[ -f "$LOG_DIR/$P1.ckpt" ] && [ -f "$LOG_DIR/$P1.row" ]'
check "NOSC point checkpointed (a finding is a finished measurement)" '[ -f "$LOG_DIR/$P2.ckpt" ]'
check "failed point has no checkpoint" '[ ! -e "$LOG_DIR/$P3.ckpt" ]'
check "never-reached point has no checkpoint" '[ ! -e "$LOG_DIR/$P4.ckpt" ]'
check "no temp files left behind" '[ -z "$(find "$LOG_DIR" -name "*.tmp.*")" ]'
check "checkpoint ends with its digest trailer and complete=1" \
  '[ "$(tail -n 1 "$LOG_DIR/$P1.ckpt" | cut -d= -f1)" = ckpt_sha256 ] && grep -q "^complete=1\$" "$LOG_DIR/$P1.ckpt"'
check "checkpoint records point, inputs and artifact digests" \
  'for k in corner_id vctrl_v status design_body_sha256 tran_template_sha256 model_inputs_sha256 simulator extractor_sha256 settings netlist_sha256 log_sha256 row_sha256; do grep -q "^$k=" "$LOG_DIR/$P1.ckpt" || exit 1; done'
check "P2 is NOSC in the source" '[ "$(row_of "$SRC" "$P2" | cut -d, -f8)" = NOSC ]'
check "P3 is a failure in the source" '[ "$(row_of "$SRC" "$P3" | cut -d, -f8)" = FAIL ]'
SRC_SUM="$(tree_sum "$SRC")"; execd >/dev/null

# -------------------- 2. resume under a new id
FAIL_POINT=""
NEW="20261101-000100-bbbbbbb"
: > "$T/out"
start_run "$NEW" "$SRC"
run_points "$P1" "$P2" "$P3" "$P4"
check "resume executed only the missing/failed points" '[ "$(execd)" = "$P3 $P4 " ]'
check "resume counts: 2 executed, 2 reused" '[ "$OSC_N_EXECUTED $OSC_N_REUSED $OSC_N_REJECTED" = "2 2 2" ]'
check "source record byte-identical after resume" '[ "$(tree_sum "$SRC")" = "$SRC_SUM" ]'
check "reused P1 row identical to the source's" '[ "$(row_of "$NEW" "$P1")" = "$(row_of "$SRC" "$P1")" ]'
check "reused NOSC stays NOSC, not PASS" '[ "$(row_of "$NEW" "$P2" | cut -d, -f8)" = NOSC ] && grep -q "$P2.*NOSC REUSED\|\[$P2\] NOSC REUSED" "$T/out"'
check "previously failed point retried and now PASS" '[ "$(row_of "$NEW" "$P3" | cut -d, -f8)" = PASS ]'
check "new record has all 4 rows once" '[ "$(tail -n +2 "$CSV_OUT" | wc -l | tr -d " ")" = 4 ]'
check "reuse manifest lists exactly the reused points" \
  '[ "$(tail -n +2 "$OSC_REUSE_CSV" | cut -d, -f1,2 | tr "\n" " ")" = "$P1,$SRC $P2,$SRC " ]'
check "reuse manifest digests match the copied artifacts" \
  'awk -F, "NR==2 { print \$1, \$5, \$6 }" "$OSC_REUSE_CSV" | { read -r c ns ls; [ "$ns" = "$(sha256_of "$NETLIST_DIR/$c.spice")" ] && [ "$ls" = "$(sha256_of "$LOG_DIR/$c.log")" ]; }'
check "new checkpoint names its source record and the source checkpoint digest" \
  '[ "$(osc_ckpt_get "$LOG_DIR/$P1.ckpt" source_record)" = "$SRC" ] && [ "$(osc_ckpt_get "$LOG_DIR/$P1.ckpt" source_ckpt_sha256)" = "$(sha256_of "$EXPERIMENT_DIR/corners/$SRC/$P1.ckpt")" ]'
check "executed point checkpoints name no source" '[ "$(osc_ckpt_get "$LOG_DIR/$P3.ckpt" source_record)" = - ]'
# a refusal must name why (P3/P4 had no checkpoint in the source)
start_run "20261101-000101-bbbbbbb" "$SRC"; run_points "$P3"; execd >/dev/null
check "missing checkpoint diagnostic" 'grep -q "NOT reusing $P3 .*no completion checkpoint" "$T/err"'

# -------------------- chained restart keeps the origin
THIRD="20261101-000200-ccccccc"
start_run "$THIRD" "$NEW"; run_points "$P1" "$P2" "$P3" "$P4"
check "full chained resume executes nothing" '[ "$(execd)" = "" ] && [ "$OSC_N_REUSED" = 4 ]'
check "chain keeps the origin record" '[ "$(osc_ckpt_get "$LOG_DIR/$P1.ckpt" origin_record)" = "$SRC" ] && [ "$(osc_ckpt_get "$LOG_DIR/$P3.ckpt" origin_record)" = "$NEW" ]'

# -------------------- 3. artifact / checkpoint faults
n=0
# fault <label> <expected-diagnostic-regex> <mutator-function>; mutates a COPY of $SRC's files
fault() {
  local label="$1" want="$2" mut="$3" id
  n=$((n + 1)); id="20261102-0000$(printf %02d $n)-ddddddd"
  local fs
  fs="20261102-9000$(printf %02d $n)-eeeeeee"
  mkdir -p "$EXPERIMENT_DIR/corners/$fs" "$EXPERIMENT_DIR/netlist-snapshots/$fs"
  cp "$EXPERIMENT_DIR/corners/$SRC/"* "$EXPERIMENT_DIR/corners/$fs/"
  cp "$EXPERIMENT_DIR/netlist-snapshots/$SRC/"* "$EXPERIMENT_DIR/netlist-snapshots/$fs/"
  F_CK="$EXPERIMENT_DIR/corners/$fs/$P1.ckpt"; F_ROW="$EXPERIMENT_DIR/corners/$fs/$P1.row"
  F_LOG="$EXPERIMENT_DIR/corners/$fs/$P1.log"; F_NET="$EXPERIMENT_DIR/netlist-snapshots/$fs/$P1.spice"
  "$mut"
  start_run "$id" "$fs"; execd >/dev/null; run_points "$P1"
  if [ "$(execd)" = "$P1 " ] && [ "$OSC_N_REUSED" = 0 ]; then ok "$label: not reused, re-executed"; else bad "$label: not reused, re-executed"; fi
  check "$label: diagnostic" 'grep -q -- "NOT reusing $P1 .*$want" "$T/err"'
  check "$label: result row still complete" '[ "$(row_of "$id" "$P1" | cut -d, -f8)" = PASS ]'
}
m_rm_net() { rm -f "$F_NET"; }
m_rm_log() { rm -f "$F_LOG"; }
m_empty_log() { : > "$F_LOG"; }
m_trunc_log() { head -c 5 "$F_LOG" > "$F_LOG.t" && mv "$F_LOG.t" "$F_LOG"; }
m_edit_net() { echo "# edited" >> "$F_NET"; }
m_rm_row() { rm -f "$F_ROW"; }
m_edit_row() { sed 's/PASS/NOSC/' "$F_ROW" > "$F_ROW.t" && mv "$F_ROW.t" "$F_ROW"; }
m_trunc_row() { head -c 40 "$F_ROW" > "$F_ROW.t" && mv "$F_ROW.t" "$F_ROW"; }
m_trunc_ckpt() { sed '$d' "$F_CK" > "$F_CK.t" && mv "$F_CK.t" "$F_CK"; }
m_half_ckpt() { head -c 200 "$F_CK" > "$F_CK.t" && mv "$F_CK.t" "$F_CK"; }
m_edit_ckpt() { sed 's/^status=PASS/status=NOSC/' "$F_CK" > "$F_CK.t" && mv "$F_CK.t" "$F_CK"; }
m_rm_ckpt() { rm -f "$F_CK"; }
fault "missing netlist" "netlist artifact missing" m_rm_net
fault "missing log" "log artifact missing" m_rm_log
fault "empty log" "log artifact missing or empty" m_empty_log
fault "truncated log" "log artifact digest mismatch" m_trunc_log
fault "edited netlist" "netlist artifact digest mismatch" m_edit_net
fault "missing row" "row artifact missing" m_rm_row
fault "edited row" "row artifact digest mismatch" m_edit_row
fault "truncated row" "row artifact digest mismatch" m_trunc_row
fault "checkpoint without trailer" "truncated" m_trunc_ckpt
fault "half-written checkpoint" "truncated" m_half_ckpt
fault "edited checkpoint" "checkpoint digest mismatch" m_edit_ckpt
fault "legacy record (no checkpoint)" "no completion checkpoint" m_rm_ckpt

# legacy: a record with only CSV/log/netlist and no checkpoints at all
LEG="20261102-800000-fffffff"
mkdir -p "$EXPERIMENT_DIR/corners/$LEG" "$EXPERIMENT_DIR/netlist-snapshots/$LEG"
cp "$EXPERIMENT_DIR/corners/$SRC/$P1.log" "$EXPERIMENT_DIR/corners/$LEG/"
cp "$EXPERIMENT_DIR/netlist-snapshots/$SRC/$P1.spice" "$EXPERIMENT_DIR/netlist-snapshots/$LEG/"
cp "$EXPERIMENT_DIR/records/$SRC.csv" "$EXPERIMENT_DIR/records/$LEG.csv"
start_run "20261102-800001-fffffff" "$LEG"; execd >/dev/null; run_points "$P1"
check "legacy record is never reused" '[ "$(execd)" = "$P1 " ] && [ "$OSC_N_REUSED" = 0 ]'

# point-identity mismatch: same corner id requested at another control voltage
start_run "20261102-810000-fffffff" "$SRC"; : > "$T/err"; execd >/dev/null
osc_run_point "$P1" tt cap_typ hbt_typ 27 2.0 "${OSC_TMAX}" >/dev/null 2>"$T/err"
check "point identity mismatch refused" 'grep -q "point identity vctrl_v differs" "$T/err" && [ "$OSC_N_REUSED" = 0 ]'
execd >/dev/null

# -------------------- 4. input / simulator / measurement identity changes
nid=0
# ident <label> <expected-key> <apply-fn> <restore-fn>
ident() {
  local label="$1" key="$2" apply="$3" restore="$4"
  nid=$((nid + 1))
  "$apply"
  start_run "20261103-0000$(printf %02d $nid)-1111111" "$SRC"; execd >/dev/null; run_points "$P1"
  if [ "$(execd)" = "$P1 " ] && [ "$OSC_N_REUSED" = 0 ]; then ok "$label: reuse refused"; else bad "$label: reuse refused"; fi
  check "$label: diagnostic names $key" 'grep -q "NOT reusing $P1 .*incompatible inputs.*$key" "$T/err"'
  "$restore"
}
a_body() { echo "R2 a b 2" >> "$T/body.spice"; }
r_body() { cp "$T/body.orig" "$T/body.spice"; }
a_tmpl() { echo "* tweak" >> "$EXPERIMENT_DIR/testbench/tb_vco_core_tran.spice.tmpl"; }
r_tmpl() { cp "$T/tmpl.orig" "$EXPERIMENT_DIR/testbench/tb_vco_core_tran.spice.tmpl"; }
a_model() { printf 'models\tcornerHBT.lib\tcccc\t/x/a\ninductor\tind.spice\tbbbb\t/x/b\n' > "$T/bundle/MANIFEST.tsv"; }
r_model() { cp "$T/manifest.orig" "$T/bundle/MANIFEST.tsv"; }
a_osdi() { printf 'models\tcornerHBT.lib\taaaa\t/x/a\ninductor\tind.spice\tbbbb\t/x/b\nosdi\tmosvar.osdi\tdddd\t/x/c\n' > "$T/bundle/MANIFEST.tsv"; }
a_tstop() { OSC_TSTOP="6n"; }
r_tstop() { OSC_TSTOP="5n"; }
a_tmeas() { OSC_TMEAS_START="3.0e-9"; }
r_tmeas() { OSC_TMEAS_START="2.5e-9"; }
a_settle() { OSC_SETTLE_FRAC="0.8"; }
r_settle() { OSC_SETTLE_FRAC="0.9"; }
a_rail() { OSC_VSUP_V="3.0"; }
r_rail() { OSC_VSUP_V=""; }
a_ext() { echo "# change" >> "$T/extractor.a"; }
r_ext() { cp "$T/extractor.a.orig" "$T/extractor.a"; }
a_csvrail() { OSC_CSV_RAIL=1; }
r_csvrail() { OSC_CSV_RAIL=0; }
ident "design source edit" design_body_sha256 a_body r_body
ident "template edit" tran_template_sha256 a_tmpl r_tmpl
ident "model input digest change" model_inputs_sha256 a_model r_model
ident "extra model input" model_inputs_sha256 a_osdi r_model
ident "transient stop time" settings a_tstop r_tstop
ident "measurement window" settings a_tmeas r_tmeas
ident "settling fraction" settings a_settle r_settle
ident "supply rail" settings a_rail r_rail
ident "extractor code" extractor_sha256 a_ext r_ext
ident "CSV layout (rail column)" csv_header_sha256 a_csvrail r_csvrail
# simulator version: start_run resets the version, so change it by hand
start_run "20261103-000900-1111111" "$SRC" >/dev/null 2>&1
OSC_NGSPICE_VERSION="ngspice-47"; OSC_FP_LINES="$(osc_fingerprint)"
execd >/dev/null; run_points "$P1"
check "simulator version change: reuse refused and named" \
  '[ "$(execd)" = "$P1 " ] && [ "$OSC_N_REUSED" = 0 ] && grep -q "incompatible inputs.*simulator" "$T/err"'
OSC_NGSPICE_VERSION="ngspice-46"
check "source record still byte-identical after all refusals" '[ "$(tree_sum "$SRC")" = "$SRC_SUM" ]'
start_run "20261103-001000-1111111" "$SRC"; execd >/dev/null; run_points "$P1"
check "restoring every input makes the point reusable again" '[ "$(execd)" = "" ] && [ "$OSC_N_REUSED" = 1 ]'

# -------------------- 5. restart-source validation
start_run "20261104-000000-2222222"
check "unknown source refused" '! osc_resume_init "nosuchrecord" 2>/dev/null'
check "self as source refused" '! osc_resume_init "$RECORD_ID" 2>/dev/null'
check "path-like source refused" '! osc_resume_init "../$SRC" 2>/dev/null && ! osc_resume_init "a/b" 2>/dev/null && ! osc_resume_init "" 2>/dev/null'

# -------------------- 6. cold start unchanged; argument handling
FAIL_POINT=""; NOSC_POINT=""
start_run "20261105-000000-3333333"; run_points "$P1" "$P4"; execd >/dev/null
check "cold start: all executed, nothing reused, no reuse manifest" \
  '[ "$OSC_N_EXECUTED $OSC_N_REUSED" = "2 0" ] && [ ! -e "$EXPERIMENT_DIR/records/$RECORD_ID-reuse.csv" ]'
check "cold start CSV has the unchanged header and column count" \
  '[ "$(head -n 1 "$CSV_OUT" | awk -F, "{print NF}")" = "$(row_of "$RECORD_ID" "$P1" | awk -F, "{print NF}")" ]'
cnt_before="$(ls "$REAL_OSC/corners" | wc -l | tr -d ' ')"
for args in "--resume-from" "--resume-from nosuchrecord-154" "--bogus" "--resume-from ../x" "--resume-from a b"; do
  # shellcheck disable=SC2086
  "$REAL_OSC/run_pvt_sweep.sh" $args >/dev/null 2>&1; rc=$?
  check "run_pvt_sweep.sh $args: usage error before any record is reserved" '[ "$rc" = 2 ]'
done
check "no record reserved by the failed invocations" '[ "$(ls "$REAL_OSC/corners" | wc -l | tr -d " ")" = "$cnt_before" ]'

echo
echo "resume-checkpoint fixtures: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
