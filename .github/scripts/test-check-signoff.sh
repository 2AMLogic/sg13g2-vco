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
#   13-24. T1 direction gate (issue #449), all with --base against a
#      committed synthetic base report in the throwaway repo (klt only
#      renders HEAD, so the base variant is committed verbatim and the
#      head record stays the real klt-rendered verdict):
#      13. --base "" fails closed; 14. unresolvable --base fails closed;
#      15. merge-base without the report fails closed; 16. merge-base
#      with an invalid report fails closed; 17. identical base/head
#      passes; 18. item swap (item 2 -> unmet, item 4 -> met, count
#      unchanged at 5) fails — the item-level gate, not the count;
#      19. the same swap with a full opt-out trailer passes and prints
#      OK (opt-out); 20. opt-out naming a non-regressed item fails;
#      21. empty-reason opt-out trailer fails; 22. two-item regression
#      with both ids opted out passes / 23. with one id fails;
#      24. pure improvement (base 4 met -> head 5) passes without any
#      trailer; plus a PYTHONOPTIMIZE=1 regression case and output-shape
#      greps (failure names items and the trailer syntax; opt-out names
#      the allowed ids).

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
  # run_case <name> <expected: 0=pass 1=fail> <tree> [checker-args...]
  name="$1"
  expect="$2"
  tree="$3"
  shift 3
  if "$CHECKER" --root "$tree" "$@" >/dev/null 2>&1; then
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

# --- 13-24. T1 direction gate, --base (issue #449) ---------------------------
#
# klt signoff renders only HEAD, so the base report is committed verbatim
# as a synthetic variant and the head record stays the pristine committed
# verdict (which case 1 already proves matches the fresh render): only the
# direction comparison can reject. The base variants never need synthetic
# LVS evidence because they are never re-rendered.
git_prep() {
  git -C "$1" config user.email t@t
  git -C "$1" config user.name t
}

# edit_base_report <tree> <mode>: rewrite the working-tree record into the
# synthetic base variant, then commit it (caller restores the pristine
# record for head).
edit_base_report() {
  python3 - "$1/signoff/t1-report.json" "$2" <<'PY'
import json, sys

path, mode = sys.argv[1], sys.argv[2]
report = json.load(open(path))
items = {it.get("id"): it for it in report["items"] if it.get("tier") == "T1"}

def unmet(iid, reason):
    items[iid]["status"] = "unmet"
    items[iid]["reason"] = reason

def met(iid):
    items[iid]["status"] = "met"
    items[iid].pop("reason", None)

if mode == "swap":
    # item 2 out, item 4 in: t1_met_count stays 5, so only the item-level
    # gate can catch it (the count is unchanged).
    unmet(2, "stale_evidence")
    met(4)
elif mode == "gain2":
    # items 4 and 5 met in the base (count 7) regressed to unmet in the
    # pristine head (count 5): both the per-item gate and the count drop.
    met(4)
    met(5)
    report["t1_met_count"] = 7
elif mode == "improve":
    unmet(3, "no_evidence")
    report["t1_met_count"] = 4
elif mode == "broken":
    pass  # caller overwrites the file with invalid JSON
json.dump(report, open(path, "w"), indent=2)
PY
}

# commit_base <tree> <mode>: commit the synthetic base variant and restore
# + commit the pristine head record; HEAD~1 is then the base.
commit_base() {
  local t="$1" mode="$2"
  git_prep "$t"
  if [ "$mode" = broken ]; then
    printf 'not json\n' > "$t/signoff/t1-report.json"
  else
    edit_base_report "$t" "$mode"
  fi
  git -C "$t" add -A
  git -C "$t" commit -q -m "base: synthetic ${mode} verdict"
  cp "$ROOT/signoff/t1-report.json" "$t/signoff/t1-report.json"
  git -C "$t" add -A
  git -C "$t" commit -q -m "head: restore pristine verdict"
}

# opt_out <tree> <count> <trailer-body...>: commit an empty commit carrying
# the trailer; the base stays <count> commits back.
opt_out() {
  local t="$1" back="$2" body="$3"
  git -C "$t" commit -q --allow-empty -m "opt out" -m "$body"
  echo "HEAD~$back"
}

# 13. An explicitly empty --base fails closed (merge_group base_sha missing).
t="$(fresh_tree)"
run_case "empty --base fails closed" 1 "$t" --base ""

# 14. An unresolvable --base fails closed with a named error.
t="$(fresh_tree)"
run_case "unresolvable --base fails closed" 1 "$t" --base no-such-ref

# 15. A merge-base without signoff/t1-report.json fails closed.
t="$(fresh_tree)"
git_prep "$t"
( cd "$t" && git add -A && git rm -q --cached signoff/t1-report.json \
    && git commit -q -m "base: no record" )
git -C "$t" add -A
git -C "$t" commit -q -m "head: add the record"
run_case "merge-base without the report fails closed" 1 "$t" --base HEAD~1

# 16. A merge-base with an invalid (unparsable) report fails closed.
t="$(fresh_tree)"
commit_base "$t" broken
run_case "merge-base with an invalid report fails closed" 1 "$t" --base HEAD~1

# 17. Identical base and head reports pass with the direction gate on.
t="$(fresh_tree)"
git_prep "$t"
git -C "$t" add -A
git -C "$t" commit -q -m base
git -C "$t" commit -q --allow-empty -m head
run_case "identical base and head passes with --base" 0 "$t" --base HEAD~1

# 18. Item swap (item 2 -> unmet, item 4 -> met, count still 5) fails: the
#     per-item gate catches what a count-only check would miss.
t="$(fresh_tree)"
commit_base "$t" swap
run_case "item swap without opt-out fails (item-level gate)" 1 "$t" --base HEAD~1
o="$(mktemp)"
if "$CHECKER" --root "$t" --base HEAD~1 >"$o" 2>&1; then
  echo "FAIL: swap failure output shape (checker passed)" >&2
  fail=$((fail + 1))
elif grep -q "item 4 (LVS clean): met -> unmet (no_evidence)" "$o" \
   && grep -q "t1_met_count: 5 -> 5" "$o" \
   && grep -q "Allow-Signoff-Regression: <id\[,id...\]>: <non-empty reason>" "$o"; then
  echo "PASS: swap failure names the item, statuses and trailer syntax"
  pass=$((pass + 1))
else
  echo "FAIL: swap failure output shape (wrong details)" >&2
  fail=$((fail + 1))
fi

# 19. The same swap with a full opt-out trailer passes — and the bypass is
#     visible in the log.
ref="$(opt_out "$t" 2 "Allow-Signoff-Regression: 4: deliberate swap while DR-006 lands")"
run_case "item swap with a full opt-out passes" 0 "$t" --base "$ref"
if "$CHECKER" --root "$t" --base "$ref" >"$o" 2>&1 \
   && grep -q "OK (opt-out): T1 item(s) 4 " "$o"; then
  echo "PASS: opt-out pass prints OK (opt-out) naming the id"
  pass=$((pass + 1))
else
  echo "FAIL: opt-out output shape" >&2
  fail=$((fail + 1))
fi

# 20. An opt-out naming a non-regressed item does not cover the regressed
#     one (fresh tree: earlier trailers stay out of the range).
t="$(fresh_tree)"
commit_base "$t" swap
ref="$(opt_out "$t" 2 "Allow-Signoff-Regression: 5: unrelated item")"
run_case "opt-out naming a non-regressed item fails" 1 "$t" --base "$ref"

# 21. A trailer with an empty reason allows nothing.
t="$(fresh_tree)"
commit_base "$t" swap
ref="$(opt_out "$t" 2 "Allow-Signoff-Regression: 4:")"
run_case "empty-reason opt-out trailer fails" 1 "$t" --base "$ref"

# 22/23. Two regressed items (base counts 7 -> head 5): both ids opted out
#        passes, one id fails.
t="$(fresh_tree)"
commit_base "$t" gain2
run_case "two-item regression without opt-out fails" 1 "$t" --base HEAD~1
if ! "$CHECKER" --root "$t" --base HEAD~1 >"$o" 2>&1 \
   && grep -q "t1_met_count: 7 -> 5" "$o"; then
  echo "PASS: regression failure names the base vs head counts"
  pass=$((pass + 1))
else
  echo "FAIL: regression failure count output shape" >&2
  fail=$((fail + 1))
fi
ref="$(opt_out "$t" 2 "Allow-Signoff-Regression: 4, 5: retiring stale evidence")"
run_case "two-item regression with both ids opted out passes" 0 "$t" --base "$ref"
t="$(fresh_tree)"
commit_base "$t" gain2
ref="$(opt_out "$t" 2 "Allow-Signoff-Regression: 4: partial cover")"
run_case "two-item regression with one id opted out fails" 1 "$t" --base "$ref"

# 24. A pure improvement (base 4 met -> head 5) needs no trailer.
t="$(fresh_tree)"
commit_base "$t" improve
run_case "pure improvement passes without opt-out" 0 "$t" --base HEAD~1

# 25. The direction gate also fires under PYTHONOPTIMIZE=1: it runs under
#     python3 -I with no bare asserts, so optimization cannot strip it.
t="$(fresh_tree)"
commit_base "$t" swap
o="$(mktemp)"
if PYTHONOPTIMIZE=1 "$CHECKER" --root "$t" --base HEAD~1 >"$o" 2>&1; then
  echo "FAIL: regression gate rejects under PYTHONOPTIMIZE=1 (checker passed)" >&2
  fail=$((fail + 1))
elif grep -q "T1 regression vs the merge-base report" "$o"; then
  echo "PASS: regression gate rejects under PYTHONOPTIMIZE=1"
  pass=$((pass + 1))
else
  echo "FAIL: regression gate rejects under PYTHONOPTIMIZE=1 (wrong reason)" >&2
  fail=$((fail + 1))
fi

echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
