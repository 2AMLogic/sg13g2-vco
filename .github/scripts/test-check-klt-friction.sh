#!/usr/bin/env bash
# Self-test for the friction-ledger gate (issue #146). Each case builds a
# throwaway tree; a gate that cannot fail is no gate. Stdlib python3 only.
#
#   1. clean tree                          -> passes
#   2. citation with no ledger entry       -> FAILS (both citation forms)
#   3. entry with a missing workaround     -> FAILS
#   4. stale klt_version_verified          -> FAILS; reverified == pin passes
#   5. sim/**/records/ citation            -> read (uncovered fails, covered
#                                             passes) and never rewritten
#   6. the real tree                       -> passes
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECKER="$HERE/check-klt-friction.sh"
pass=0; fail=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# Built by concatenation so this file is not itself a citation.
UP="klayout-""tools"

run_case() { # name expect(0|1) tree
  local got=1
  "$CHECKER" --root "$3" >/dev/null 2>&1 && got=0
  if [ "$got" -eq "$2" ]; then echo "PASS: $1"; pass=$((pass + 1))
  else echo "FAIL: $1 (expected $2, got $got)" >&2; fail=$((fail + 1)); fi
}

# mk <dir> <version-in-ledger> [extra-entry-json]
mk() {
  local d="$1" ver="$2" extra="${3:-}"
  mkdir -p "$d/.github" "$d/layout" "$d/sim/x/records"
  echo "0.6.0" > "$d/.github/klt-version"
  echo "# helper" > "$d/layout/helper.sh"
  printf 'see %s#7 and %s/issues/8\n' "$UP" "$UP" > "$d/layout/NOTES.md"
  printf 'unrelated #99 text\n' > "$d/layout/other.md"
  cat > "$d/.github/klt-friction-ledger.json" <<JSON
{"schema": 1, "entries": [
 {"number": 7, "gap": "g7", "status": "open", "status_checked_on": "2026-10-09",
  "klt_version_verified": "$ver", "workarounds": ["layout/helper.sh"]},
 {"number": 8, "gap": "g8", "status": "closed", "status_checked_on": "2026-10-09",
  "klt_version_verified": "0.6.0", "workarounds": []}${extra:+,
 $extra}
]}
JSON
}

mk "$TMP/clean" 0.6.0
run_case "clean tree passes" 0 "$TMP/clean"

mk "$TMP/uncited-hash" 0.6.0
printf 'new gap %s#9\n' "$UP" >> "$TMP/uncited-hash/layout/other.md"
run_case "uncited #N citation fails" 1 "$TMP/uncited-hash"

mk "$TMP/uncited-url" 0.6.0
printf 'https://github.com/2AMLogic/%s/issues/10\n' "$UP" >> "$TMP/uncited-url/layout/other.md"
run_case "uncited /issues/N citation fails" 1 "$TMP/uncited-url"

mk "$TMP/nopath" 0.6.0 '{"number": 11, "gap": "g", "status": "open", "status_checked_on": "2026-10-09", "klt_version_verified": "0.6.0", "workarounds": ["layout/gone.sh"]}'
run_case "missing workaround path fails" 1 "$TMP/nopath"

mk "$TMP/stale" 0.5.0
run_case "stale verification version fails" 1 "$TMP/stale"

mk "$TMP/reverified" 0.5.0
sed -i 's/"klt_version_verified": "0.5.0"/"klt_version_verified": "0.5.0", "reverified": "0.6.0"/' \
  "$TMP/reverified/.github/klt-friction-ledger.json"
run_case "stale but reverified at the pin passes" 0 "$TMP/reverified"

mk "$TMP/bumped" 0.6.0
echo "0.7.0" > "$TMP/bumped/.github/klt-version"
run_case "pin bump makes every entry stale" 1 "$TMP/bumped"

mk "$TMP/rec-bad" 0.6.0
printf 'frozen: %s#12\n' "$UP" > "$TMP/rec-bad/sim/x/records/r.md"
run_case "uncovered citation inside sim records fails" 1 "$TMP/rec-bad"

mk "$TMP/rec-ok" 0.6.0
printf 'frozen: %s#8\n' "$UP" > "$TMP/rec-ok/sim/x/records/r.md"
before="$(cksum < "$TMP/rec-ok/sim/x/records/r.md")"
run_case "covered citation inside sim records passes" 0 "$TMP/rec-ok"
after="$(cksum < "$TMP/rec-ok/sim/x/records/r.md")"
if [ "$before" = "$after" ]; then echo "PASS: records file untouched"; pass=$((pass + 1))
else echo "FAIL: records file was modified" >&2; fail=$((fail + 1)); fi

mk "$TMP/bad-json" 0.6.0
echo '{' > "$TMP/bad-json/.github/klt-friction-ledger.json"
run_case "malformed ledger fails" 1 "$TMP/bad-json"

run_case "real tree passes" 0 "$ROOT"

echo "test-check-klt-friction: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
