#!/usr/bin/env bash
# Self-test for regen-signoff.sh (issue #360): a regen entry point that can
# still destroy the verdict of record is worse than the redirect it replaced.
# Proves, with stubbed tools on a disposable tree (no PDK, no network, no
# writes into the real signoff/), that the wrapper:
#   1. refuses a mismatched klt when uvx is unavailable, naming the pin, the
#      actual version and both remedies, leaving the record byte-identical;
#   2. leaves the record byte-identical (never 0 bytes) when the render
#      fails, whichever tool resolved;
#   3. leaves the record untouched when the render succeeds but fails a
#      payload gate (wrong block, error envelope, wrong item count) or the
#      build-identity gate (#368: non-release, dirty, mistagged, missing or
#      non-object build block);
#   4. falls back to uvx on a mismatched ambient klt and lands the pinned
#      render;
#   5. uses the ambient klt when it matches the pin (no network needed);
#   6. works from a subdirectory via a relative path, and refuses a missing
#      or empty pin file.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REAL_PYTHON3="$(command -v python3)"
[ -n "$REAL_PYTHON3" ] || { echo "FAIL: no python3 on PATH" >&2; exit 1; }
[ -x "$HERE/regen-signoff.sh" ] || { echo "FAIL: regen-signoff.sh missing" >&2; exit 1; }
[ -f "$HERE/klt-pin.sh" ] || { echo "FAIL: klt-pin.sh missing" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

PIN="0.8.0-test"
BADVER="9.9.9-mismatch"

# Valid build block for the pin, shared by the success-path stub bodies
# (#368): the regen payload gate asserts is_release/dirty/git_tag and derives
# its expectation from the pin (git_tag == "v$PIN"), so the stubs derive
# theirs the same way — a hardcoded tag here would break on any harness-pin
# change, and a hardcoded pair that still matched would prove nothing about
# the derivation.
STUB_BUILD_BLOCK="$(printf '{"version": "%s", "package_version": "%s", "git_commit": "0123456789abcdef0123456789abcdef01234567", "git_tag": "v%s", "dirty": false, "is_release": true, "grading_ruleset_id": "sha256:stub-grading-ruleset"}' "$PIN" "$PIN" "$PIN")"

# --- stub tools -------------------------------------------------------------
# bin-a: coreutils + stub python3 + stub klt + stub uvx + the pinned klt the
# stub uvx resolves to. bin-b: the same minus uvx (and minus the pinned klt),
# for the no-uvx refusal.
mk_common() {
  local d="$1" t p
  mkdir -p "$d"
  for t in bash env dirname awk tr cat mktemp mv rm; do
    p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$d/$t"
  done
  cat > "$d/python3" <<'EOF'
#!/usr/bin/env bash
# Delegate to the real interpreter; stub only the inventory regen, which the
# disposable tree has no real signoff/ for.
for a in "$@"; do
  case "$a" in signoff/inventories.py) echo "stub inventories regen" >> "$STUB_LOG"; exit 0 ;; esac
done
exec "$REAL_PYTHON3" "$@"
EOF
  cat > "$d/klt" <<'EOF'
#!/usr/bin/env bash
# Stub klt: --version prints $STUB_KLT_VERSION; a render emits the contents
# of $STUB_BODY_FILE (default $STUB_DEFAULT_BODY) and exits $STUB_SIGNOFF_RC.
case "${1:-}" in
  --version) printf 'klt %s\n' "${STUB_KLT_VERSION:-9.9.9-mismatch}"; exit 0 ;;
  signoff)
    if [ -n "${STUB_BODY_FILE:-}" ]; then cat "$STUB_BODY_FILE"; else cat "$STUB_DEFAULT_BODY"; fi
    printf 'render by %s\n' "$0" >> "$STUB_LOG"
    exit "${STUB_SIGNOFF_RC:-0}"
    ;;
esac
exit 0
EOF
  chmod +x "$d/python3" "$d/klt"
}

printf '%s\n' '{"schema_version": 1, "block": "sg13g2-vco", "kind": "analog", "t1_item_count": 11, "build": '"$STUB_BUILD_BLOCK"'}' > "$T/default-body.json"
export STUB_DEFAULT_BODY="$T/default-body.json"

BIN="$T/bin"; mk_common "$BIN"
cat > "$T/pinned-klt" <<EOF
#!/usr/bin/env bash
# The klt the stub uvx resolves to: always the pin, whatever the ambient one
# says. Body: \$STUB_PINNED_BODY_FILE, else \$STUB_BODY_FILE, else default.
case "\${1:-}" in
  --version) printf 'klt $PIN\n'; exit 0 ;;
  signoff)
    if [ -n "\${STUB_PINNED_BODY_FILE:-}" ]; then cat "\$STUB_PINNED_BODY_FILE"
    elif [ -n "\${STUB_BODY_FILE:-}" ]; then cat "\$STUB_BODY_FILE"
    else cat "\$STUB_DEFAULT_BODY"; fi
    printf 'render by pinned-klt\n' >> "\$STUB_LOG"
    exit "\${STUB_PINNED_RC:-\${STUB_SIGNOFF_RC:-0}}"
    ;;
esac
exit 0
EOF
chmod +x "$T/pinned-klt"
cat > "$BIN/uvx" <<EOF
#!/usr/bin/env bash
# Stub uvx: the wrapper invokes uvx --from "klayout-tools==PIN" klt ...
[ "\${1:-}" = --from ] || exit 64
shift 2
[ "\${1:-}" = klt ] && shift
exec "$T/pinned-klt" "\$@"
EOF
chmod +x "$BIN/uvx"

BIN2="$T/bin-nouvx"; mk_common "$BIN2"

# --- fixture tree -----------------------------------------------------------
# repo <dir>: a disposable repo with the wrapper, the pin file, dummy signoff
# inputs and a sentinel record.
repo() {
  local r="$1"
  mkdir -p "$r/.github/scripts" "$r/signoff"
  cp "$HERE/regen-signoff.sh" "$HERE/klt-pin.sh" "$r/.github/scripts/"
  chmod +x "$r/.github/scripts/regen-signoff.sh"
  echo "$PIN" > "$r/.github/klt-version"
  printf '{ "block": "sg13g2-vco" }\n' > "$r/signoff/manifest.json"
  printf '# tiers doc\n' > "$r/signoff/design-evidence-tiers.md"
  printf '{"sentinel": "previous good record"}\n' > "$r/signoff/t1-report.json"
  git -C "$r" init -q -b main 2>/dev/null || git -C "$r" init -q
}

record_digest() { sha256sum "$1/signoff/t1-report.json" | awk '{print $1}'; }

run_wrapper() {
  local r="$1" path="$2" dir="$3" rel="$4"
  STUB_LOG="$T/stub.log"
  : > "$STUB_LOG"
  export STUB_LOG REAL_PYTHON3
  ( cd "$r/$dir" && PATH="$path" "$rel" ) > "$T/out" 2> "$T/err"
}

# --- 1. mismatched klt, no uvx: refuse, name everything, keep the record ----
r="$T/case1"; repo "$r"
before="$(record_digest "$r")"
run_wrapper "$r" "$BIN2" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -ne 0 ] \
   && grep -q "$PIN" "$T/err" \
   && grep -q "$BADVER" "$T/err" \
   && grep -q "uvx --from" "$T/err" \
   && grep -q "throwaway venv" "$T/err" \
   && [ "$(record_digest "$r")" = "$before" ]; then
  ok "mismatch + no uvx: refused naming pin/actual/remedies, record kept"
else
  bad "case1: rc=$rc err=$(cat "$T/err")"
fi

# --- 2. failing render leaves the record untouched (never 0 bytes) ----------
printf 'partial garbage' > "$T/body-garbage"
# 2a. ambient klt matches the pin, render exits 1.
r="$T/case2a"; repo "$r"
before="$(record_digest "$r")"
STUB_KLT_VERSION="$PIN" STUB_SIGNOFF_RC=1 STUB_BODY_FILE="$T/body-garbage" \
  run_wrapper "$r" "$BIN" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -ne 0 ] && [ -s "$r/signoff/t1-report.json" ] \
   && [ "$(record_digest "$r")" = "$before" ]; then
  ok "failing render (exit 1, ambient match): record byte-identical"
else
  bad "case2a: rc=$rc digest-matches=$([ "$(record_digest "$r")" = "$before" ] && echo yes || echo no)"
fi
# 2b. ambient mismatched, uvx resolves, the pinned render itself fails.
r="$T/case2b"; repo "$r"
before="$(record_digest "$r")"
STUB_KLT_VERSION="$BADVER" STUB_PINNED_RC=1 \
  run_wrapper "$r" "$BIN" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -ne 0 ] && [ -s "$r/signoff/t1-report.json" ] \
   && [ "$(record_digest "$r")" = "$before" ]; then
  ok "failing render (exit 1 via uvx): record byte-identical"
else
  bad "case2b: rc=$rc"
fi
# 2c. render exits with a non-clean code (usage error), not 0/3.
r="$T/case2c"; repo "$r"
before="$(record_digest "$r")"
STUB_KLT_VERSION="$PIN" STUB_SIGNOFF_RC=2 \
  run_wrapper "$r" "$BIN" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -ne 0 ] && [ "$(record_digest "$r")" = "$before" ]; then
  ok "render exit 2 (non-clean): record byte-identical"
else
  bad "case2c: rc=$rc"
fi

# --- 3. payload-gate failures keep the record -------------------------------
# Each variant: name|expected-stderr-substring|body-JSON. An empty pattern
# only asserts non-zero exit and an untouched record; a non-empty one also
# asserts the failure names its reason (self-diagnosing red run).
for variant in \
  'error-envelope||{"error": "manifest unreadable"}' \
  'wrong-block||{"schema_version": 1, "block": "other-block", "kind": "analog", "t1_item_count": 11}' \
  'wrong-count||{"schema_version": 1, "block": "sg13g2-vco", "kind": "analog", "t1_item_count": 10}' \
  'no-build-block|no build block|{"schema_version": 1, "block": "sg13g2-vco", "kind": "analog", "t1_item_count": 11}' \
  'build-null|no build block|{"schema_version": 1, "block": "sg13g2-vco", "kind": "analog", "t1_item_count": 11, "build": null}' \
  'dev-build|is_release=False|{"schema_version": 1, "block": "sg13g2-vco", "kind": "analog", "t1_item_count": 11, "build": {"version": "0.8.0-test+gabc", "package_version": "0.8.0-test", "git_commit": "abc", "git_tag": null, "dirty": false, "is_release": false}}' \
  'dirty-build|dirty=True|{"schema_version": 1, "block": "sg13g2-vco", "kind": "analog", "t1_item_count": 11, "build": {"version": "0.8.0-test+gabc.dirty", "package_version": "0.8.0-test", "git_commit": "abc", "git_tag": "v0.8.0-test", "dirty": true, "is_release": true}}' \
  'tag-mismatch|expected v'"$PIN"'|{"schema_version": 1, "block": "sg13g2-vco", "kind": "analog", "t1_item_count": 11, "build": {"version": "0.8.0-test", "package_version": "0.8.0-test", "git_commit": "abc", "git_tag": "v0.7.0", "dirty": false, "is_release": true}}'; do
  name="${variant%%|*}"; rest="${variant#*|}"
  pattern="${rest%%|*}"; body="${rest#*|}"
  printf '%s\n' "$body" > "$T/body-$name"
  r="$T/case3-$name"; repo "$r"
  before="$(record_digest "$r")"
  STUB_KLT_VERSION="$PIN" STUB_BODY_FILE="$T/body-$name" \
    run_wrapper "$r" "$BIN" . "./.github/scripts/regen-signoff.sh"
  rc=$?
  if [ "$rc" -ne 0 ] \
     && { [ -z "$pattern" ] || grep -qF -- "$pattern" "$T/err"; } \
     && [ "$(record_digest "$r")" = "$before" ]; then
    ok "payload gate ($name): record untouched"
  else
    bad "case3-$name: rc=$rc err=$(cat "$T/err")"
  fi
done

# --- 4. uvx fallback on a mismatched ambient klt lands the pinned render ----
r="$T/case4"; repo "$r"
printf '%s\n' '{"schema_version": 1, "block": "sg13g2-vco", "kind": "analog", "t1_item_count": 11, "note": "pinned render", "build": '"$STUB_BUILD_BLOCK"'}' > "$T/body-pinned"
STUB_KLT_VERSION="$BADVER" STUB_PINNED_BODY_FILE="$T/body-pinned" \
  run_wrapper "$r" "$BIN" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$r/signoff/t1-report.json")" = "$(cat "$T/body-pinned")" ] \
   && grep -q 'render by pinned-klt' "$STUB_LOG" \
   && ! grep -q 'render by .*bin/klt' "$STUB_LOG"; then
  ok "uvx fallback: pinned render landed, ambient klt never ran"
else
  bad "case4: rc=$rc log=$(cat "$STUB_LOG")"
fi

# --- 5. ambient klt matching the pin is used directly (no uvx, no network) --
r="$T/case5"; repo "$r"
before="$(record_digest "$r")"
STUB_KLT_VERSION="$PIN" run_wrapper "$r" "$BIN2" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -eq 0 ] && grep -q 'render by .*bin-nouvx/klt' "$STUB_LOG" \
   && ! grep -q 'pinned-klt' "$STUB_LOG"; then
  ok "ambient match: ambient klt used, no uvx involved"
else
  bad "case5: rc=$rc log=$(cat "$STUB_LOG")"
fi
# and a matching ambient render landing a new payload means the record moved.
r="$T/case5b"; repo "$r"
STUB_KLT_VERSION="$PIN" run_wrapper "$r" "$BIN2" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$r/signoff/t1-report.json")" = "$(cat "$T/default-body.json")" ]; then
  ok "ambient match: successful render replaces the record"
else
  bad "case5b: rc=$rc"
fi
# exit 3 is a clean render (valid unmet verdict): record still lands.
r="$T/case5c"; repo "$r"
STUB_KLT_VERSION="$PIN" STUB_SIGNOFF_RC=3 \
  run_wrapper "$r" "$BIN2" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$r/signoff/t1-report.json")" = "$(cat "$T/default-body.json")" ]; then
  ok "exit 3 (>=1 unmet) is a clean render: record lands"
else
  bad "case5c: rc=$rc"
fi

# --- 6. subdirectory + relative invocation; missing/empty pin file ----------
r="$T/case6"; repo "$r"
STUB_KLT_VERSION="$PIN" run_wrapper "$r" "$BIN2" signoff "../.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -eq 0 ]; then
  ok "runs from a subdirectory via a relative path"
else
  bad "case6 relpath: rc=$rc err=$(cat "$T/err")"
fi
r="$T/case6b"; repo "$r"; : > "$r/.github/klt-version"
run_wrapper "$r" "$BIN2" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -ne 0 ] && grep -q "pin file .* is empty" "$T/err"; then
  ok "empty pin file refused"
else
  bad "case6b empty pin: rc=$rc err=$(cat "$T/err")"
fi
r="$T/case6c"; repo "$r"; rm "$r/.github/klt-version"
run_wrapper "$r" "$BIN2" . "./.github/scripts/regen-signoff.sh"
rc=$?
if [ "$rc" -ne 0 ] && grep -q "missing pin file" "$T/err"; then
  ok "missing pin file refused"
else
  bad "case6c missing pin: rc=$rc err=$(cat "$T/err")"
fi

echo "regen-signoff self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
