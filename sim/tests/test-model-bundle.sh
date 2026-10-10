#!/usr/bin/env bash
# Self-test for model-input capture (issue #133). PDK-free, no simulator:
# sources the real lib.sh and osc_bench.sh against a scratch repo and a
# FIXTURE model tree (corner libraries with nested .include/.lib references,
# one in a subdirectory climbing back with ../), a fixture inductor model, a
# fake OSDI binary and the experiment's .spiceinit. Checks that
#   1. the capture follows the transitive closure and retains its manifest
#      under the reserved record (repo-owned inputs as snapshots, PDK/OSDI
#      by digest only);
#   2. every deck renders against the bundle, never a live path;
#   3. a LIVE mutation after capture changes neither a later deck nor any
#      recorded digest, and the summary still publishes;
#   4. a BUNDLE mutation (nested library, OSDI, served .spiceinit, manifest,
#      retained manifest) fails verification and publishes nothing;
#   5. a missing nested dependency, a reference leaving the model root, an
#      absolute reference, an init file that loads something, and a template
#      naming an uncaptured library all fail BEFORE any deck exists;
#   6. existing records are untouched, the retained manifest is append-only,
#      and the design-currency classification is unchanged by the manifest.
# shellcheck disable=SC2034  # variables are read inside check()'s eval strings
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SIM_DIR="$(cd "${HERE}/.." && pwd)"
REAL_OSC="${SIM_DIR}/oscillator-core"
CLASSIFIER="${SIM_DIR}/../.github/scripts/record_currency.py"
# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"

T="$(mktemp -d)"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
bad() { fail=$((fail + 1)); echo "FAIL - $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# ------------------------------------------------------------------ fixtures
REPO_ROOT="$T/repo"
EXPERIMENT_DIR="$REPO_ROOT/sim/oscillator-core"
MODELS="$T/pdk/models"
mkdir -p "$REPO_ROOT/design" "$EXPERIMENT_DIR/records" "$REPO_ROOT/sim/inductor-model" \
         "$MODELS/sub" "$T/osdi"
cp "$REAL_OSC/.spiceinit" "$EXPERIMENT_DIR/.spiceinit"
cat > "$MODELS/cornerHBT.lib" <<'EOF'
* fixture HBT corner library
* .include commented_out_not_a_dependency.lib
.LIB hbt_typ
.include sg13g2_hbt_mod.lib
.lib "sub/nested.lib" nested_sec
.ENDL hbt_typ
EOF
cat > "$MODELS/sub/nested.lib" <<'EOF'
.LIB nested_sec
  .include '../deep.lib'   $ inline comment
.ENDL
EOF
echo "* deep v1" > "$MODELS/deep.lib"
printf '.LIB mos_tt\n  .include sg13g2_svaricaphv_mod.lib\n.ENDL\n.LIB mos_mm\n  .include sg13g2_svaricaphv_mod_mismatch.lib\n.ENDL\n' > "$MODELS/cornerMOShv.lib"
printf '.LIB cap_typ\n.INC "capacitors_mod.lib"\n.ENDL\n' > "$MODELS/cornerCAP.lib"
for f in sg13g2_hbt_mod capacitors_mod; do echo "* $f" > "$MODELS/$f.lib"; done
# svaricap fixtures: the one card line the overlay edits, plus unrelated bytes
# that must survive untouched. The overlay's expected-digest table is swapped
# for the fixtures' digests through the self-test hook SVARICAP_OVERLAY_SPEC.
mk_svar() { printf '* %s fixture\n.subckt svar G W bn\n.ends\n.model dsubw d is = 2.45E-17 n = 4 vj = 0.1 m = 0.1052 cjp = 1.117E-09\n* trailer vj = 0.1 mentioned elsewhere\n' "$1" > "$MODELS/$1.lib"; }
mk_svar sg13g2_svaricaphv_mod; mk_svar sg13g2_svaricaphv_mod_mismatch
write_spec() { printf '{"sg13g2_svaricaphv_mod.lib": "%s", "sg13g2_svaricaphv_mod_mismatch.lib": "%s"}\n' \
  "$(sha256_of "$MODELS/sg13g2_svaricaphv_mod.lib")" "$(sha256_of "$MODELS/sg13g2_svaricaphv_mod_mismatch.lib")" > "$T/spec.json"; }
write_spec
export SVARICAP_OVERLAY_SPEC="$T/spec.json"
SRC_SVAR_SHA="$(sha256_of "$MODELS/sg13g2_svaricaphv_mod.lib")"; SRC_SVARM_SHA="$(sha256_of "$MODELS/sg13g2_svaricaphv_mod_mismatch.lib")"
echo "* unrelated, never referenced" > "$MODELS/unreferenced.lib"
printf '.subckt ind_fixture a b\nL1 a b 1n\n.ends\n' > "$REPO_ROOT/sim/inductor-model/sg13g2_inductor_em.spice"
printf 'OSDI-v1\x00\x01binary' > "$T/osdi/mosvar.osdi"

# An OLD record that must never be touched (append-only evidence).
OLD_ID="20260101-000000-abc1234"
echo "# old record" > "$EXPERIMENT_DIR/records/${OLD_ID}.md"
echo "a,b" > "$EXPERIMENT_DIR/records/${OLD_ID}.csv"
old_sum() { cat "$EXPERIMENT_DIR/records/${OLD_ID}".* | sha256sum | cut -d' ' -f1; }
OLD_SUM="$(old_sum)"

cat > "$REPO_ROOT/design/vco.spice" <<'SRC'
** sch_path: x
XL1 a b ind
XC1 a b cap
XQ1 a b c hbt
XQ3 a b c hbt
RREF a b 10k
RTE a b 1k
VSUP VDD 0 dc 3.3
VCT a 0 1.65
XCV1 a b var
**** begin user architecture code
.control
.endc
SRC

SG13G2_NGSPICE_MODELS="$MODELS"
OSC_IND_MODEL="$REPO_ROOT/sim/inductor-model/sg13g2_inductor_em.spice"
OSC_OSDI_MOSVAR="$T/osdi/mosvar.osdi"
PDK=ihp-sg13g2; PDK_ROOT="$T/pdk"
# shellcheck source=../oscillator-core/osc_bench.sh
source "$REAL_OSC/osc_bench.sh"

# new_run <id> -- a fresh reserved record and scratch WORKDIR, no bundle yet
new_run() {
  RECORD_ID="$1"
  WORKDIR="$T/work-$1"; mkdir -p "$WORKDIR"
  cp "$EXPERIMENT_DIR/.spiceinit" "$WORKDIR/.spiceinit"   # make_scratch_workdir's copy
  mkdir -p "$EXPERIMENT_DIR/corners/$RECORD_ID"
  unset OSC_BUNDLE_DIR OSC_BUNDLE_MANIFEST OSC_BUNDLE_MANIFEST_SHA
}
render() { # <template> <out>
  osc_render "$1" "$2" c1 -e "s|@@HBT_SECTION@@|hbt_typ|g" -e "s|@@MOS_SECTION@@|mos_tt|g" \
    -e "s|@@CAP_SECTION@@|cap_typ|g" -e "s|@@TEMP_C@@|27|g" -e "s|@@VCTRL@@|1.65|g" \
    -e "s|@@TMAX@@|2p|g" -e "s|@@OUT_PREFIX@@|p|g" -e "s|@@RREF_LADDER@@|20500|g"
}
sha() { sha256_of "$1"; }

# design-currency verdict for the record this run must classify (no capture yet)
cls() { python3 -I "$CLASSIFIER" --root "$REPO_ROOT" show | python3 -I -c '
import json, sys
for r in json.load(sys.stdin)["records"]:
    if r["record_id"] == sys.argv[1]:
        print(r["state"], r["basis"], r["design_netlist_sha256"], r["reason"])' "$1"; }
OLD_CLS_BEFORE="$(cls "$OLD_ID")"

# ------------------------------------------------- 1. capture + retention
new_run "20261009-000000-abc1234"
osc_render "$REAL_OSC/testbench/tb_vco_core_tran.spice.tmpl" "$T/nobundle.spice" c1 >/dev/null 2>&1 \
  && bad "render without a bundle refused" || ok "render without a bundle refused"
osc_derive_body >/dev/null 2>&1 || bad "derive body"
EXP_HBT="$(sha "$MODELS/cornerHBT.lib")"; EXP_DEEP="$(sha "$MODELS/deep.lib")"
EXP_IND="$(sha "$OSC_IND_MODEL")"; EXP_OSDI="$(sha "$OSC_OSDI_MOSVAR")"
EXP_INIT="$(sha "$EXPERIMENT_DIR/.spiceinit")"
check "capture succeeds" 'osc_capture_model_bundle >/dev/null'
M="$OSC_BUNDLE_MANIFEST"
for rel in models/cornerHBT.lib models/cornerMOShv.lib models/cornerCAP.lib models/sg13g2_hbt_mod.lib \
           models/sg13g2_svaricaphv_mod.lib models/capacitors_mod.lib models/sub/nested.lib models/deep.lib \
           inductor/sg13g2_inductor_em.spice osdi/mosvar.osdi init/.spiceinit; do
  check "manifest holds $rel" 'input_bundle_sha "$M" "$rel" >/dev/null 2>&1 && [ -f "$OSC_BUNDLE_DIR/$rel" ]'
done
check "nested ../ reference resolved inside the bundle" '[ "$(osc_bundle_sha models/deep.lib)" = "$EXP_DEEP" ]'
check "unreferenced library not captured" '! grep -q unreferenced "$M"'
check "commented-out include ignored" '! grep -q commented_out "$M"'
check "bundle files are read-only" '[ ! -w "$OSC_BUNDLE_DIR/models/cornerHBT.lib" ] || [ "$(id -u)" = 0 ]'
check "WORKDIR .spiceinit served from the bundle" 'cmp -s "$WORKDIR/.spiceinit" "$OSC_BUNDLE_DIR/init/.spiceinit"'
JSON="$EXPERIMENT_DIR/records/${RECORD_ID}-model-inputs.json"
check "manifest retained under the reserved record" '[ -f "$JSON" ]'
check "retained manifest parses, schema and record id" \
  'python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert d[\"schema\"]==\"sg13g2-vco/model-inputs/1\" and d[\"record_id\"]==sys.argv[2] and len(d[\"inputs\"])==13" "$JSON" "$RECORD_ID"'
check "PDK libraries and OSDI are external (not retained)" \
  'python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert all((e[\"retained_snapshot\"] is None)==(e[\"role\"] in (\"pdk-model\",\"osdi-binary\")) for e in d[\"inputs\"])" "$JSON"'
SNAPDIR="$EXPERIMENT_DIR/netlist-snapshots/$RECORD_ID/model-inputs"
check "inductor model retained as a snapshot" '[ "$(sha "$SNAPDIR/inductor/sg13g2_inductor_em.spice")" = "$EXP_IND" ]'
check ".spiceinit retained as a snapshot" '[ "$(sha "$SNAPDIR/init/.spiceinit")" = "$EXP_INIT" ]'
check "repo-owned original path recorded repo-relative" 'grep -q "\"original_path\": \"sim/inductor-model/sg13g2_inductor_em.spice\"" "$JSON"'
check "second capture in the same run refused" '! osc_capture_model_bundle >/dev/null 2>&1'

# --------------------------------------------- 2. decks render against the bundle
for tmpl in tb_vco_core_tran tb_vco_core_margin; do
  check "$tmpl renders" 'render "$REAL_OSC/testbench/$tmpl.spice.tmpl" "$T/$tmpl.a.spice"'
  check "$tmpl: no live model/inductor/OSDI path" \
    '! grep -qF -e "$MODELS" -e "$OSC_IND_MODEL" -e "$OSC_OSDI_MOSVAR" "$T/$tmpl.a.spice"'
  check "$tmpl: libraries, inductor and OSDI from the bundle" \
    'grep -q "^\.lib $OSC_BUNDLE_DIR/models/cornerHBT.lib hbt_typ\$" "$T/$tmpl.a.spice" &&
     grep -q "^\.include $OSC_BUNDLE_DIR/inductor/sg13g2_inductor_em.spice\$" "$T/$tmpl.a.spice" &&
     grep -q "pre_osdi $OSC_BUNDLE_DIR/osdi/mosvar.osdi\$" "$T/$tmpl.a.spice"'
done
check "phase-noise templates use only bundle-served model tokens" \
  '! grep -hoE "@@MODELS_DIR@@/[^[:space:]]+" "$SIM_DIR"/phase-noise/testbench/*.tmpl | sed "s|@@MODELS_DIR@@/||" | sort -u | grep -vxF -e cornerHBT.lib -e cornerMOShv.lib -e cornerCAP.lib'
osc_provenance_md > "$T/prov.before"

# ---------------------------------- 3. live mutation after capture is inert
echo "* HBT v2 (edited mid-run)" >> "$MODELS/cornerHBT.lib"
echo "* deep v2 (edited mid-run)" > "$MODELS/deep.lib"
echo "* inductor edited mid-run" >> "$OSC_IND_MODEL"
printf 'OSDI-v2-rebuilt' > "$OSC_OSDI_MOSVAR"
echo "set ngbehavior=ps" >> "$EXPERIMENT_DIR/.spiceinit"
for tmpl in tb_vco_core_tran tb_vco_core_margin; do
  render "$REAL_OSC/testbench/$tmpl.spice.tmpl" "$T/$tmpl.b.spice"
  check "$tmpl: later deck identical after live mutation" 'cmp -s "$T/$tmpl.a.spice" "$T/$tmpl.b.spice"'
done
check "bundle bytes unchanged by live mutation" 'verify_input_bundle "$OSC_BUNDLE_DIR" "$M"'
osc_provenance_md > "$T/prov.after"
check "recorded provenance unchanged by live mutation" 'cmp -s "$T/prov.before" "$T/prov.after"'
check "recorded digests are the captured ones" \
  'grep -q "cornerHBT.lib\` sha256 \`$EXP_HBT\`" "$T/prov.after" && grep -q "mosvar.osdi\` (this run.s build) sha256 \`$EXP_OSDI\`" "$T/prov.after"'
check "inductor narrative digest is the captured one" '[ "$(osc_ind_model_sha)" = "$EXP_IND" ]'
check "provenance names the retained manifest" 'grep -qF "records/${RECORD_ID}-model-inputs.json" "$T/prov.after"'
echo "# summary" > "$WORKDIR/summary.md"
MD="$EXPERIMENT_DIR/records/${RECORD_ID}.md"
check "summary publishes after a live-only mutation" 'osc_publish_summary "$WORKDIR/summary.md" "$MD" 2>/dev/null && [ -f "$MD" ]'
check "published summary never overwritten" '! osc_publish_summary "$WORKDIR/summary.md" "$MD" 2>/dev/null'

# ------------------------------- 4. bundle mutation fails verification
# tamper <file> <cmd...>: make writable, mutate, verify must fail, then restore
tamper() {
  local f="$1" label="$2" saved="$T/saved"; shift 2
  rm -f "$saved"; cp "$f" "$saved"; chmod u+w "$f"
  "$@" "$f"
  local dest="$EXPERIMENT_DIR/records/tamper-$label.md"
  if osc_publish_summary "$WORKDIR/summary.md" "$dest" 2>"$T/err"; then
    bad "bundle mutation ($label) detected"
  else
    ok "bundle mutation ($label) detected"
  fi
  check "nothing published after bundle mutation ($label)" '[ ! -e "$dest" ]'
  rm -f "$f"; cp "$saved" "$f"
}
append_x() { echo "* tampered" >> "$1"; }
tamper "$OSC_BUNDLE_DIR/models/deep.lib" nested-library append_x
check "verification message names the changed file" 'grep -q "models/deep.lib" "$T/err"'
tamper "$OSC_BUNDLE_DIR/osdi/mosvar.osdi" osdi append_x
tamper "$WORKDIR/.spiceinit" served-spiceinit append_x
tamper "$OSC_BUNDLE_DIR/MANIFEST.tsv" manifest append_x
tamper "$JSON" retained-manifest append_x
rm_file() { rm -f "$1"; }
tamper "$OSC_BUNDLE_DIR/models/sub/nested.lib" deleted-library rm_file
check "restored bundle verifies again" 'osc_verify_model_bundle 2>/dev/null'

# --------------------------- 5. failures before any simulation
# capture_fails <label> <expected-stderr-fragment>: in a subshell, on a fresh run
capture_fails() {
  local label="$1" want="$2" id="20261009-0000$3-abc1234"
  ( new_run "$id"; osc_capture_model_bundle >/dev/null 2>"$T/err.$label" ) && { bad "$label fails capture"; return; }
  ok "$label fails capture"
  check "$label: message names the problem" 'grep -q -- "$want" "$T/err.$label"'
  check "$label: no manifest retained" '[ ! -e "$EXPERIMENT_DIR/records/${id}-model-inputs.json" ]'
}
cp "$MODELS/cornerCAP.lib" "$T/cap.saved"
printf '.LIB cap_typ\n.include capacitors_mod.lib\n.include missing_nested.lib\n.ENDL\n' > "$MODELS/cornerCAP.lib"
capture_fails missing-nested-dependency "missing dependency .*missing_nested.lib (referenced from .*cornerCAP.lib)" 01
printf '.LIB cap_typ\n.include ../../outside.lib\n.ENDL\n' > "$MODELS/cornerCAP.lib"
capture_fails reference-leaves-root "leaves the capture root" 02
printf '.LIB cap_typ\n.include /etc/hostname\n.ENDL\n' > "$MODELS/cornerCAP.lib"
capture_fails absolute-reference "absolute or home-relative path" 03
cp "$T/cap.saved" "$MODELS/cornerCAP.lib"
mv "$MODELS/sg13g2_hbt_mod.lib" "$T/hbtmod.saved"
capture_fails missing-root-library "missing dependency .*sg13g2_hbt_mod.lib" 04
mv "$T/hbtmod.saved" "$MODELS/sg13g2_hbt_mod.lib"
cp "$EXPERIMENT_DIR/.spiceinit" "$T/init.saved"
echo "pre_osdi /somewhere/else.osdi" >> "$EXPERIMENT_DIR/.spiceinit"
capture_fails init-loads-a-file "loads a file" 05
cp "$T/init.saved" "$EXPERIMENT_DIR/.spiceinit"
# a template naming a library that is not in the bundle renders nothing
printf '.lib @@MODELS_DIR@@/cornerDIO.lib dio_tt\n@@VCO_BODY@@\n' > "$T/uncaptured.tmpl"
( new_run "20261009-000006-abc1234"; osc_derive_body >/dev/null 2>&1; osc_capture_model_bundle >/dev/null 2>&1 || exit 2
  osc_render "$T/uncaptured.tmpl" "$T/uncaptured.spice" c1 2>/dev/null && exit 1; [ ! -e "$T/uncaptured.spice" ] ) \
  && ok "template naming an uncaptured library refused before any deck" \
  || bad "template naming an uncaptured library refused before any deck"

# --------------------------- 5b. svaricap vj overlay (issue #95)
OVL="$SIM_DIR/tools/svaricap_overlay.py"
tree_sum() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d' ' -f1); }
for f in sg13g2_svaricaphv_mod sg13g2_svaricaphv_mod_mismatch; do
  B="$OSC_BUNDLE_DIR/models/$f.lib"
  check "overlay: $f bundle copy carries vj = 0.3357 exactly once" \
    '[ "$(grep -c "vj = 0.3357 m = 0.1052" "$B")" = 1 ] && [ "$(grep -c "model dsubw.* vj = 0.1 " "$B")" = 0 ]'
  check "overlay: $f differs from the source in exactly one line" \
    '[ "$(diff "$MODELS/$f.lib" "$B" | grep -c "^>")" = 1 ] && [ "$(diff "$MODELS/$f.lib" "$B" | grep -c "^<")" = 1 ]'
  check "overlay: $f unrelated bytes (incl. a comment mentioning vj = 0.1) unchanged" \
    'grep -q "^\* trailer vj = 0.1 mentioned elsewhere\$" "$B" && [ "$(sed "s/vj = 0.3357/vj = 0.1/" "$B" | sha256sum | cut -d" " -f1)" = "$(sha256_of "$MODELS/$f.lib")" ]'
done
check "overlay: source fixtures untouched (PDK tree never written)" \
  '[ "$(sha256_of "$MODELS/sg13g2_svaricaphv_mod.lib")" = "$SRC_SVAR_SHA" ] && [ "$(sha256_of "$MODELS/sg13g2_svaricaphv_mod_mismatch.lib")" = "$SRC_SVARM_SHA" ] && [ ! -e "$MODELS/overlay" ]'
check "overlay: manifest digest is of the overlaid bytes" \
  '[ "$(osc_bundle_sha models/sg13g2_svaricaphv_mod.lib)" = "$(sha256_of "$OSC_BUNDLE_DIR/models/sg13g2_svaricaphv_mod.lib")" ] && [ "$(osc_bundle_sha models/sg13g2_svaricaphv_mod.lib)" != "$SRC_SVAR_SHA" ]'
OJ="$OSC_BUNDLE_DIR/overlay/svaricap-vj.json"
check "overlay: provenance holds original + overlaid digests and upstream refs" \
  'python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1])); f={e[\"name\"]:e for e in d[\"files\"]}
assert d[\"upstream_issue\"].endswith(\"#1098\") and d[\"upstream_pull_request\"].endswith(\"#1102\")
assert d[\"upstream_merge_commit\"]==\"0243d867c6b7493526b141d2e4d74afa027e5b8e\"
assert f[\"sg13g2_svaricaphv_mod.lib\"][\"original_sha256\"]==sys.argv[2] and f[\"sg13g2_svaricaphv_mod_mismatch.lib\"][\"original_sha256\"]==sys.argv[3]
assert f[\"sg13g2_svaricaphv_mod.lib\"][\"overlaid_sha256\"]!=sys.argv[2]" "$OJ" "$SRC_SVAR_SHA" "$SRC_SVARM_SHA"'
check "overlay: provenance md names original digests, PR and merge commit" \
  'osc_provenance_md | grep -q "$SRC_SVAR_SHA" && osc_provenance_md | grep -q "0243d867c6b7493526b141d2e4d74afa027e5b8e"'
check "overlay: the supply-stage-2 svaricap digest bullet still matches exactly once" \
  '[ "$(osc_provenance_md | grep -cE "sg13g2_svaricaphv_mod\.lib. sha256 .[0-9a-f]+")" = 1 ]'
check "overlay: provenance retained under the record" \
  'cmp -s "$OJ" "$SNAPDIR/overlay/svaricap-vj.json"'
check "overlay: the default (v0.3.0) digest table refuses the fixtures" \
  'mkdir -p "$T/ovl-default" && cp "$MODELS/sg13g2_svaricaphv_mod.lib" "$MODELS/sg13g2_svaricaphv_mod_mismatch.lib" "$T/ovl-default/" && ! python3 -I "$OVL" apply "$T/ovl-default" 2>/dev/null &&
   [ "$(sha256_of "$T/ovl-default/sg13g2_svaricaphv_mod.lib")" = "$SRC_SVAR_SHA" ]'
check "overlay: symlinked or hardlinked model copy refused" \
  'mkdir -p "$T/ovl-link" && cp "$MODELS/sg13g2_svaricaphv_mod_mismatch.lib" "$T/ovl-link/" && ln -s "$MODELS/sg13g2_svaricaphv_mod.lib" "$T/ovl-link/sg13g2_svaricaphv_mod.lib" &&
   ! python3 -I "$OVL" apply "$T/ovl-link" --spec "$T/spec.json" 2>/dev/null && [ "$(sha256_of "$MODELS/sg13g2_svaricaphv_mod.lib")" = "$SRC_SVAR_SHA" ]'

# overlay_refused <label> <expected-stderr-fragment> <n>: the source fixtures have
# been altered by the caller; capture must fail before any deck or retained manifest.
overlay_refused() {
  local label="$1" want="$2" id="20261009-0001$3-abc1234"
  ( new_run "$id"; osc_capture_model_bundle >/dev/null 2>"$T/err.$label" ) && { bad "overlay: $label refused"; return; }
  ok "overlay: $label refused"
  check "overlay: $label: message names the problem" 'grep -q -- "$want" "$T/err.$label"'
  check "overlay: $label: no manifest retained, no summary" \
    '[ ! -e "$EXPERIMENT_DIR/records/${id}-model-inputs.json" ] && [ ! -e "$EXPERIMENT_DIR/records/${id}.md" ]'
}
cp "$MODELS/sg13g2_svaricaphv_mod.lib" "$T/svar.saved"
# (a) unexpected source: bytes differ from the digest table
echo "* edited upstream" >> "$MODELS/sg13g2_svaricaphv_mod.lib"
overlay_refused unexpected-source "not the expected v0.3.0 digest" 01
# (b) already fixed (a pin that includes PR #1102)
sed "s/vj = 0.1 m/vj = 0.3357 m/" "$T/svar.saved" > "$MODELS/sg13g2_svaricaphv_mod.lib"; write_spec
overlay_refused already-fixed "already carries the upstream fix" 02
# (c) card text occurs twice although the digest matches the table
{ cat "$T/svar.saved"; echo ".model dsubw2 d vj = 0.1 m = 0.1052 x"; } > "$MODELS/sg13g2_svaricaphv_mod.lib"; write_spec
overlay_refused duplicate-card "expected exactly one" 03
# (d) card text absent although the digest matches the table
sed "s/vj = 0.1 m/vj = 0.2 m/" "$T/svar.saved" > "$MODELS/sg13g2_svaricaphv_mod.lib"; write_spec
overlay_refused card-absent "expected exactly one" 04
# (e) a covered file missing from the closure (cornerMOShv no longer reaches the mismatch library)
cp "$T/svar.saved" "$MODELS/sg13g2_svaricaphv_mod.lib"; write_spec
cp "$MODELS/cornerMOShv.lib" "$T/mos.saved"
printf '.LIB mos_tt\n  .include sg13g2_svaricaphv_mod.lib\n.ENDL\n' > "$MODELS/cornerMOShv.lib"
overlay_refused covered-file-not-in-closure "is missing or a symlink" 05
cp "$T/mos.saved" "$MODELS/cornerMOShv.lib"
cp "$T/svar.saved" "$MODELS/sg13g2_svaricaphv_mod.lib"; write_spec
check "overlay: fixtures restored, a clean capture works again" \
  '( new_run 20261009-000199-abc1234; osc_capture_model_bundle >/dev/null 2>&1 )'

# --------------------------- 6. append-only and design-currency semantics
check "old record untouched" '[ "$(old_sum)" = "$OLD_SUM" ]'
RID2="20261009-000007-abc1234"
echo '{"schema": "something else"}' > "$EXPERIMENT_DIR/records/${RID2}-model-inputs.json"
( new_run "$RID2"; osc_capture_model_bundle >/dev/null 2>"$T/err.append" ) \
  && bad "existing different manifest never overwritten" || ok "existing different manifest never overwritten"
check "pre-existing manifest bytes unchanged" 'grep -q "something else" "$EXPERIMENT_DIR/records/${RID2}-model-inputs.json"'
rm -f "$EXPERIMENT_DIR/records/${RID2}-model-inputs.json"
# a run without a reserved record id captures privately and writes nothing
( RECORD_ID=""; WORKDIR="$T/work-norecord"; mkdir -p "$WORKDIR"; unset OSC_BUNDLE_DIR
  before="$(find "$EXPERIMENT_DIR" -type f | wc -l)"
  osc_capture_model_bundle >/dev/null 2>&1 || exit 1
  [ "$(find "$EXPERIMENT_DIR" -type f | wc -l)" = "$before" ] ) \
  && ok "no reserved record id: nothing written under the experiment" \
  || bad "no reserved record id: nothing written under the experiment"

# The classifier's verdict for the record must not depend on the manifest.
FIRST_ID="20261009-000000-abc1234"
with="$(cls "$FIRST_ID")"
mv "$EXPERIMENT_DIR/records/${FIRST_ID}-model-inputs.json" "$T/mi.json"
without="$(cls "$FIRST_ID")"
mv "$T/mi.json" "$EXPERIMENT_DIR/records/${FIRST_ID}-model-inputs.json"
check "record classified current" '[ "${with%% *}" = current ]'
check "design-currency verdict unchanged by the model manifest" '[ -n "$with" ] && [ "$with" = "$without" ]'
check "old record's classification unchanged" '[ -n "$OLD_CLS_BEFORE" ] && [ "$(cls "$OLD_ID")" = "$OLD_CLS_BEFORE" ]'

echo "model-bundle: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
