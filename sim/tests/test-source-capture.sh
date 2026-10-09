#!/usr/bin/env bash
# Self-test for design-source capture at the osc_derive_body boundary (issue
# #122). PDK-free, no simulator: sources the real lib.sh and osc_bench.sh in a
# scratch repo and checks that (1) the provenance sidecar's hash is the hash of
# the bytes the device section was derived from, (2) an edit of the source
# during derivation is detected and fails the run, (3) a run without a
# reserved record id writes nothing, (4) an existing sidecar is never
# overwritten, and (5) the classifier reads the result as current.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SIM_DIR="$(cd "${HERE}/.." && pwd)"
CLASSIFIER="${SIM_DIR}/../.github/scripts/record_currency.py"
# shellcheck source=../lib.sh
source "${SIM_DIR}/lib.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
bad() { fail=$((fail + 1)); echo "FAIL - $1"; }

REPO_ROOT="$T/repo"
EXPERIMENT_DIR="$REPO_ROOT/sim/oscillator-core"
WORKDIR="$T/work"
mkdir -p "$REPO_ROOT/design" "$EXPERIMENT_DIR/records" "$WORKDIR"
write_src() {
  cat > "$REPO_ROOT/design/vco.spice" <<SRC
** sch_path: x
XL1 a b ind
XC1 a b cap
XQ1 a b c hbt
XQ3 a b c hbt
RREF a b 10k
RTE a b 1k
VSUP a 0 3.3
VCT a 0 1.65
XCV1 a b var
$1
**** begin user architecture code
.control
.endc
SRC
}
write_src "* rev A"
# shellcheck source=../oscillator-core/osc_bench.sh
source "${SIM_DIR}/oscillator-core/osc_bench.sh"

RECORD_ID="20261001-000000-abc1234"
mkdir -p "$EXPERIMENT_DIR/corners/$RECORD_ID"
SHA_A="$(sha256_of "$REPO_ROOT/design/vco.spice")"
SIDECAR="$EXPERIMENT_DIR/records/${RECORD_ID}-source-provenance.json"
SNAP="$EXPERIMENT_DIR/netlist-snapshots/$RECORD_ID/design-vco.spice"

osc_derive_body >/dev/null 2>&1 && ok "derive succeeds" || bad "derive failed"
if [ -f "$SIDECAR" ] && grep -q "\"design_netlist_sha256\": \"$SHA_A\"" "$SIDECAR"; then
  ok "sidecar records the source hash"; else bad "sidecar missing/wrong"; fi
[ "$(sha256_of "$SNAP")" = "$SHA_A" ] && ok "snapshot bytes match recorded hash" || bad "snapshot differs"
grep -q 'rev A' "$WORKDIR/vco_body.spice" && ok "body derived from captured source" || bad "body content"
if python3 -I "$CLASSIFIER" --root "$REPO_ROOT" show | grep -q '"state": "current"'; then
  ok "classifier reads the sidecar as current"; else bad "classifier did not read current"; fi

# 4. second derivation with identical source is idempotent; changed source is
#    refused (append-only), never silently overwritten.
osc_derive_body >/dev/null 2>&1 && ok "identical re-derivation tolerated" || bad "re-derivation failed"
write_src "* rev B"
if osc_derive_body >/dev/null 2>&1; then bad "changed source overwrote existing sidecar"; else ok "existing sidecar never overwritten"; fi
grep -q "\"design_netlist_sha256\": \"$SHA_A\"" "$SIDECAR" && ok "sidecar unchanged" || bad "sidecar mutated"

# 2. edit during derivation (the awk step) is detected.
RECORD_ID="20261001-000001-abc1234"
mkdir -p "$EXPERIMENT_DIR/corners/$RECORD_ID"
write_src "* rev C"
awk() { write_src "* rev D (edited mid-run)"; command awk "$@"; }
if osc_derive_body >/dev/null 2>&1; then bad "mid-run edit not detected"; else ok "mid-run edit detected"; fi
[ ! -e "$EXPERIMENT_DIR/records/${RECORD_ID}-source-provenance.json" ] && ok "no sidecar for a refused run" || bad "sidecar written despite edit"
unset -f awk

# 3. no reserved record id -> no sidecar, derivation unchanged
RECORD_ID=""
write_src "* rev E"
before="$(find "$EXPERIMENT_DIR" -type f | wc -l | tr -d ' ')"
osc_derive_body >/dev/null 2>&1 && ok "derive without record id succeeds" || bad "derive without record id failed"
[ "$(find "$EXPERIMENT_DIR" -type f | wc -l | tr -d ' ')" = "$before" ] && ok "nothing written without a record id" || bad "files written without record id"

echo "source-capture: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
