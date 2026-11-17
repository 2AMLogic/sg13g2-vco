#!/usr/bin/env bash
# Self-test for check-signoff.sh — a drift checker that cannot fail is
# indistinguishable from no checker at all (same rationale as the hygiene
# self-test convention in 2AMLogic/sg13g2-bandgap): before trusting the
# checker's verdict on the real tree, prove it still rejects each defect
# class it exists to catch.
#
# Cases (each in a throwaway copy of signoff/, never the real tree):
#   1. pristine copy               -> check-signoff.sh passes
#   2. tampered committed record   -> check-signoff.sh FAILS (drift gate)
#   3. tampered vendored tiers doc -> check-signoff.sh FAILS (drift gate)
#   4. broken manifest JSON        -> check-signoff.sh FAILS (runs-clean gate)
#   5. pin disagrees with PATH klt -> check-signoff.sh FAILS (version gate)
#   6-11. simulation citations (issue #122): a manifest that cites a sim
#      record file passes only if the record is freshly computed "current"
#      against design/vco.spice. Each case re-renders signoff/t1-report.json
#      with klt so the rendered-report comparison matches perfectly; only the
#      citation gate can then reject: superseded, unknown (filename-only),
#      missing file, unmapped name, stale committed index. A current record
#      passes, and the DRC-only manifest (case 1) is unaffected.
#   12. PYTHONOPTIMIZE=1 + a manifest whose render carries a block the
#      payload gate must reject, with the record re-rendered to match so
#      only the payload gate can reject -> check-signoff.sh FAILS (the
#      gate runs python3 -I, so optimization cannot strip its asserts).

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECKER="$HERE/check-signoff.sh"

if [ ! -x "$CHECKER" ]; then
  echo "FAIL: $CHECKER not found or not executable" >&2
  exit 1
fi

pass=0
fail=0

run_case() {
  # run_case <name> <expected: 0=pass 1=fail> <tree>
  name="$1"
  expect="$2"
  tree="$3"
  if "$CHECKER" --root "$tree" >/dev/null 2>&1; then
    got=0
  else
    got=1
  fi
  if [ "$got" -eq "$expect" ]; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (expected $expect, got $got)" >&2
    fail=$((fail + 1))
  fi
}

fresh_tree() {
  # signoff/ plus every file the manifest cites, and the artifact each cited
  # klt envelope names as its input: `file` for sim-record envelopes, and a
  # yield envelope's `samples`/`limits` documents (relative to the envelope's
  # own directory).  klt signoff re-hashes those inputs for `input_verified`,
  # so a tree without them would render a different report and the pristine
  # case could never pass.  Paths are repo-root-relative, as the manifest
  # contract requires.
  tree="$(mktemp -d)"
  # klt resolves an artifact-anchored envelope's `scope: "repo"` path against
  # the enclosing git toplevel (issue #243), so the throwaway tree is a repo.
  git init -q "$tree"
  cp -R "$ROOT/signoff" "$tree/signoff"
  python3 - "$ROOT" "$tree" <<'PY'
import json, os, shutil, sys
root, tree = sys.argv[1], sys.argv[2]

def copy(rel):
    src = os.path.join(root, rel)
    if not rel or os.path.isabs(rel) or not os.path.isfile(src):
        return
    os.makedirs(os.path.dirname(os.path.join(tree, rel)), exist_ok=True)
    shutil.copyfile(src, os.path.join(tree, rel))

manifest = json.load(open(os.path.join(root, "signoff", "manifest.json")))
for entry in (manifest.get("evidence") or {}).values():
    # An entry is a single citation (str or dict) or a list of them.
    for one in (entry if isinstance(entry, list) else [entry]):
        rel = one if isinstance(one, str) else (one or {}).get("file")
        if not isinstance(rel, str):
            continue
        copy(rel)
        try:
            env = json.load(open(os.path.join(root, rel)))
        except (OSError, ValueError):
            continue
        if isinstance(env, dict):
            # Envelope schema 2 carries `file` as a repo-relative string;
            # schema 3 carries {"path": ..., "scope": ...}.  A klt yield
            # envelope instead names its backing documents (`samples`,
            # `limits`) as filenames relative to its own directory.
            src = env.get("file")
            if isinstance(src, dict):
                src = src.get("path")
            if isinstance(src, str):
                copy(src)
            here = os.path.dirname(rel)
            for key in ("samples", "limits"):
                doc = env.get(key)
                if isinstance(doc, str):
                    copy(os.path.normpath(os.path.join(here, doc)))
PY
  echo "$tree"
}

# 1. Pristine copy passes.
t="$(fresh_tree)"
run_case "pristine tree passes" 0 "$t"

# 2. Tampered committed record fails: the verdict-of-record no longer
#    matches what klt actually renders.
t="$(fresh_tree)"
sed -i.bak 's/"t1_met_count": [0-9]*/"t1_met_count": 99/' "$t/signoff/t1-report.json"
rm -f "$t/signoff/t1-report.json.bak"
run_case "tampered record fails" 1 "$t"

# 3. Tampered vendored tiers doc fails: a silently reworded checklist
#    changes the rendered report, and the committed record must be
#    refreshed deliberately, not drift past.
t="$(fresh_tree)"
sed -i.bak 's/DRC clean/DRC tampered/' "$t/signoff/design-evidence-tiers.md"
rm -f "$t/signoff/design-evidence-tiers.md.bak"
run_case "tampered tiers doc fails" 1 "$t"

# 4. Broken manifest fails: klt signoff must run clean (exit 0 or 3,
#    valid report payload) — a non-rendering manifest is a hard error,
#    never a silent pass.
t="$(fresh_tree)"
printf '{ oops\n' > "$t/signoff/manifest.json"
run_case "broken manifest fails" 1 "$t"

# 5. Version mismatch fails: a copy of the checker whose .github/klt-version
#    names a release that is not the klt on PATH must refuse to grade, even
#    on an otherwise pristine tree.
t="$(fresh_tree)"
v="$(mktemp -d)"
mkdir -p "$v/.github/scripts"
cp "$CHECKER" "$v/.github/scripts/check-signoff.sh"
# The pin assertion is a sourced helper (klt-pin.sh) resolving next to $0,
# so case 5's fixture must copy it beside the copied checker.
cp "$HERE/klt-pin.sh" "$v/.github/scripts/klt-pin.sh"
echo "0.0.0-mismatch" > "$v/.github/klt-version"
if "$v/.github/scripts/check-signoff.sh" --root "$t" 2>"$v/err" >/dev/null; then
  echo "FAIL: version mismatch fails (checker passed)" >&2
  fail=$((fail + 1))
elif grep -q "version mismatch" "$v/err"; then
  echo "PASS: version mismatch fails"
  pass=$((pass + 1))
else
  echo "FAIL: version mismatch fails (wrong reason)" >&2
  fail=$((fail + 1))
fi

# --- 6-11. simulation-record citations (issue #122) ------------------------
CLASSIFIER="$HERE/record_currency.py"
REC="20261001-000000-abc1234"
RDIR="sim/oscillator-core/records"

# sim_tree <sidecar-hash|none> <cite-path|default>: a tree whose manifest
# cites a sim record file, with the index written and the verdict of record
# re-rendered by klt so the render comparison matches.
sim_tree() {
  local hash="$1" cite="$2" t
  t="$(fresh_tree)"
  mkdir -p "$t/design" "$t/$RDIR"
  cp "$ROOT/design/vco.spice" "$t/design/vco.spice"
  echo "# record" > "$t/$RDIR/$REC.md"
  if [ "$hash" != "none" ]; then
    printf '{"design_netlist_sha256": "%s"}\n' "$hash" > "$t/$RDIR/$REC-source-provenance.json"
  fi
  [ "$cite" = default ] && cite="$RDIR/$REC.md"
  python3 - "$t/signoff/manifest.json" "$cite" <<'PY'
import json, sys
p, cite = sys.argv[1], sys.argv[2]
m = json.load(open(p))
m["evidence"]["3"] = {"file": cite, "content_hash": "sha256:" + "0" * 64}
json.dump(m, open(p, "w"), indent=2)
PY
  echo "$t"
}

# finish_tree <tree> [noindex]: write the index and re-render the record.
finish_tree() {
  [ "${2:-}" = noindex ] || python3 -I "$CLASSIFIER" --root "$1" write >/dev/null
  ( cd "$1" && klt signoff --manifest signoff/manifest.json \
      --tiers-doc signoff/design-evidence-tiers.md --format json \
      > signoff/t1-report.json 2>/dev/null ) || true
}

CUR="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$ROOT/design/vco.spice")"

t="$(sim_tree "$CUR" default)"; finish_tree "$t"
run_case "current sim citation passes" 0 "$t"

t="$(sim_tree "$(printf 'f%.0s' $(seq 64))" default)"; finish_tree "$t"
run_case "superseded sim citation fails despite matching render" 1 "$t"

t="$(sim_tree none default)"; finish_tree "$t"
run_case "unknown (filename-only) sim citation fails despite matching render" 1 "$t"

t="$(sim_tree "$CUR" "$RDIR/20269999-000000-abc1234.md")"; finish_tree "$t"
run_case "missing sim citation fails despite matching render" 1 "$t"

t="$(sim_tree "$CUR" "$RDIR/notes.txt")"; echo x > "$t/$RDIR/notes.txt"; finish_tree "$t"
run_case "unmapped sim citation fails despite matching render" 1 "$t"

t="$(sim_tree "$CUR" default)"; finish_tree "$t"
echo '{}' > "$t/sim/record-currency.json"
run_case "stale committed currency index fails" 1 "$t"

t="$(sim_tree "$CUR" "./$RDIR/../records/$REC.md")"; finish_tree "$t"
run_case "unnormalized current citation path still maps and passes" 0 "$t"

# 12. Payload gate under PYTHONOPTIMIZE=1: a bare `python3 -` puts cwd on
#     sys.path AND honors PYTHONOPTIMIZE, which strips the gate's asserts —
#     a gate that cannot run while looking like one that passed. The tree's
#     manifest carries a block the payload gate must reject, and the
#     committed record is re-rendered from it so every other gate (klt
#     runs-clean, currency, byte-for-byte comparison) passes: only the
#     payload assert can reject, and it must still fire under optimization.
t="$(fresh_tree)"
python3 - "$t/signoff/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["block"] = "zzz-payload-canary"
json.dump(m, open(p, "w"), indent=2)
PY
( cd "$t" && klt signoff --manifest signoff/manifest.json \
    --tiers-doc signoff/design-evidence-tiers.md --format json \
    > signoff/t1-report.json 2>/dev/null ) || true
o="$(mktemp)"
if PYTHONOPTIMIZE=1 "$CHECKER" --root "$t" >/dev/null 2>"$o"; then
  echo "FAIL: payload gate rejects under PYTHONOPTIMIZE=1 (checker passed)" >&2
  fail=$((fail + 1))
elif grep -q "did not produce a valid sg13g2-vco/analog tier report" "$o"; then
  echo "PASS: payload gate rejects under PYTHONOPTIMIZE=1"
  pass=$((pass + 1))
else
  echo "FAIL: payload gate rejects under PYTHONOPTIMIZE=1 (wrong reason)" >&2
  fail=$((fail + 1))
fi

echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
