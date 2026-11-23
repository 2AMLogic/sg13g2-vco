#!/usr/bin/env bash
# check-signoff.sh — keep the committed klt signoff verdict-of-record
# honest.
#
# Re-renders the T1-T4 tier report from the committed block manifest and
# the vendored design-evidence-tiers doc, then compares the fresh render
# byte-for-byte against signoff/t1-report.json. Any drift — a manifest
# citation whose artifact changed, a reworded checklist, a stale record —
# fails here instead of rotting. Refreshing the record is a deliberate
# act with a guarded entry point (it renders at the pin and only writes
# on a clean, gated render):
#
#   .github/scripts/regen-signoff.sh
#
# "Runs clean" follows docs/cli/signoff.md's exit-code contract: 0 (all
# T1 items met) and 3 (ran successfully, at least one item unmet) are
# both successful renders — an all-unmet report is a correct verdict,
# not a CI failure. Everything else (bad manifest, unparsable tiers doc,
# usage error) is a hard failure. The payload's own fields are the real
# gate (the doc's rule: "gate on status/tier, not the exit code"): the
# fresh render must parse, carry the expected block/kind, and contain no
# top-level error block.
#
# Simulation citations: manifest evidence under sim/**/records/ must be
# "current" per .github/scripts/record_currency.py (see the check below).
#
# T1 direction gate (issue #449): with --base REF, after the byte-drift
# check passes, the committed verdict is also compared against the
# merge-base's signoff/t1-report.json — any tier=="T1" item going
# met -> non-met (or disappearing), or a t1_met_count drop, fails even
# when the render is perfectly self-consistent. A deliberate regression
# (evidence legitimately retired) opts out via a commit-message trailer in
# merge-base..HEAD:
#
#   Allow-Signoff-Regression: <id[,id...]>: <non-empty reason>
#
# every regressed item id must be listed with a non-empty reason; see
# signoff/README.md. Without --base none of this runs (push-to-main CI
# keeps the bare form; PRs and the merge queue pass the base explicitly).
# Needs git only when --base is given.
#
# Requirements: python3, and klt on PATH at exactly the version in .github/klt-version
# (see signoff/README.md; regen-signoff.sh selects that release itself, so no
# host-wide install is needed). Headless — needs no PDK, no KLayout project, no network.

set -u

payload_rc=0

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASE=""
BASE_EXPLICIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "usage: $0 [--root DIR] [--base REF]" >&2; exit 2; }
            ROOT="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || { echo "usage: $0 [--root DIR] [--base REF]" >&2; exit 2; }
            BASE="$2"; BASE_EXPLICIT=1; shift 2 ;;
    *) echo "usage: $0 [--root DIR] [--base REF]" >&2; exit 2 ;;
  esac
done

MANIFEST="signoff/manifest.json"
TIERS_DOC="signoff/design-evidence-tiers.md"
RECORD="signoff/t1-report.json"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# The pin lives in exactly one place: the sourced klt-pin.sh helper next to
# this script (not --root, which may be a throwaway tree). Assert mode: the
# checker grades only with the pinned release and never falls back.
# shellcheck source=./klt-pin.sh
. "$(cd "$(dirname "$0")" && pwd)/klt-pin.sh" || exit 1
klt_pin_read || exit 1
klt_pin_assert || exit 1

# The classifier lives next to this script (not under --root); resolve it
# before the cd below so a relative $0 still works.
CLASSIFIER="$(cd "$(dirname "$0")" && pwd)/record_currency.py"
[ -f "$CLASSIFIER" ] || fail "missing $CLASSIFIER"

cd "$ROOT" || fail "cannot cd to $ROOT"
[ -f "$MANIFEST" ] || fail "missing $MANIFEST"
[ -f "$TIERS_DOC" ] || fail "missing $TIERS_DOC"
[ -f "$RECORD" ] || fail "missing $RECORD"

tmp="$(mktemp)"
err="$(mktemp)"
basejson="$(mktemp)"
commitlog="$(mktemp)"
trap 'rm -f "$tmp" "$err" "$basejson" "$commitlog"' EXIT

# Fail-closed base resolution (issue #449): an explicit --base must be
# non-empty, resolve to a commit, share a merge-base with HEAD, and that
# merge-base must carry a valid signoff/t1-report.json. Any failure is a
# named error, never a silently skipped direction gate.
MB=""
if [ "$BASE_EXPLICIT" -eq 1 ]; then
  if [ -z "$BASE" ]; then
    fail "--base is empty (merge_group base_sha missing from the event?)"
  fi
  if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1; then
    fail "base ref '$BASE' does not resolve to a commit (fetch it, e.g. fetch-depth: 0)"
  fi
  MB="$(git merge-base "$BASE" HEAD 2>/dev/null)" || MB=""
  if [ -z "$MB" ]; then
    fail "no merge-base between '$BASE' and HEAD (shallow clone?)"
  fi
  if ! git show "$MB:$RECORD" >"$basejson" 2>/dev/null; then
    fail "merge-base ${MB:0:12} has no $RECORD (cannot grade T1 direction)"
  fi
  baseval_rc=0
  python3 -I - "$basejson" <<'PY' || baseval_rc=1
import json, sys

try:
    with open(sys.argv[1]) as f:
        report = json.load(f)
except (OSError, ValueError) as e:
    print(f"FAIL: merge-base report is not valid JSON: {e}", file=sys.stderr)
    raise SystemExit(1)
if (not isinstance(report, dict)
        or not isinstance(report.get("items"), list)
        or not isinstance(report.get("t1_met_count"), int)):
    print("FAIL: merge-base report has no items/t1_met_count", file=sys.stderr)
    raise SystemExit(1)
PY
  if [ "$baseval_rc" -ne 0 ]; then
    fail "merge-base ${MB:0:12} lacks a valid $RECORD"
  fi
  # Commit messages in merge-base..HEAD carry the opt-out trailers. Empty
  # range (base == HEAD) is fine: no trailers, and the compare below sees
  # identical reports.
  git log --format=%B "$MB..HEAD" >"$commitlog" 2>/dev/null || true
fi

klt signoff --manifest "$MANIFEST" --tiers-doc "$TIERS_DOC" --format json \
  >"$tmp" 2>"$err"
rc=$?

# Report payload gates before drift comparison: a failing manifest whose
# fresh render accidentally matches a stale committed record must still
# fail.
python3 -I - "$tmp" <<'PY' || payload_rc=1
import json, sys

with open(sys.argv[1]) as f:
    report = json.load(f)

assert isinstance(report, dict), "report is not a JSON object"
assert "error" not in report, f"report is a klt error envelope: {report.get('error')}"
assert report.get("schema_version") == 1, "unexpected report schema_version"
assert report.get("block") == "sg13g2-vco", "report does not grade this block"
assert report.get("kind") == "analog", "report does not grade kind=analog"
assert report.get("t1_item_count") == 11, "report does not render the 11-item checklist"
PY
if [ "${payload_rc:-0}" -ne 0 ]; then
  cat "$err" >&2
  fail "fresh render did not produce a valid sg13g2-vco/analog tier report"
fi

case "$rc" in
  0|3) ;;  # ran clean: all-met (0) or tier: null with unmet items (3)
  *) cat "$err" >&2; fail "klt signoff did not run clean (exit $rc) — 0 (all T1 met) and 3 (>=1 unmet) are both valid verdicts; any other exit is a broken manifest/doc" ;;
esac

# Simulation-record citations (issue #122): any manifest evidence file under
# sim/**/records/ must belong to exactly one record whose FRESHLY computed
# currency against design/vco.spice is "current" (and the committed
# sim/record-currency.json must match that fresh computation). This runs
# before the rendered-report comparison and is independent of it: a stale
# citation fails even when the render matches byte-for-byte. A DRC-only
# manifest has no such citation and is unaffected. See sim/README.md,
# "Record currency".
if ! python3 -I "$CLASSIFIER" --root "$ROOT" cite --manifest "$MANIFEST" >&2; then
  fail "the manifest cites a sim record that is not current against design/vco.spice (or the record-currency index is stale) — cite a current record, or refresh the index with: python3 .github/scripts/record_currency.py write"
fi

if cmp -s "$tmp" "$RECORD"; then
  met="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["t1_met_count"])' "$RECORD")"
  count="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(r["t1_item_count"])' "$RECORD")"
  echo "OK: signoff/t1-report.json matches the fresh klt render (T1: $met/$count items met; tier: $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tier"])' "$RECORD"))"
  if [ "$BASE_EXPLICIT" -eq 1 ]; then
    # T1 direction gate (issue #449): the verdict of record may not lose
    # met T1 items against the merge-base report. Runs under python3 -I
    # with no bare asserts, so PYTHONOPTIMIZE cannot strip it.
    if ! python3 -I - "$basejson" "$RECORD" "$commitlog" "${MB:0:12}" <<'PY'
import json, re, sys

base_path, head_path, log_path, mb_short = sys.argv[1:5]

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)

def load(path, what):
    try:
        with open(path) as f:
            report = json.load(f)
    except (OSError, ValueError) as e:
        die(f"{what} is not valid JSON ({e})")
    if not isinstance(report, dict) or not isinstance(report.get("items"), list):
        die(f"{what} has no items array")
    if not isinstance(report.get("t1_met_count"), int):
        die(f"{what} has no integer t1_met_count")
    return report

def t1_index(report, what):
    # Only tier=="T1" rows carry an integer id; T2-T4 summary rows have
    # id null and are never gated (they cannot collide on None here).
    index = {}
    for item in report["items"]:
        if not isinstance(item, dict) or item.get("tier") != "T1":
            continue
        iid = item.get("id")
        if isinstance(iid, bool) or not isinstance(iid, int):
            die(f"{what} has a T1 item without an integer id: {item.get('title')!r}")
        index[iid] = item
    return index

base = load(base_path, "merge-base report")
head = load(head_path, "head report")
base_t1 = t1_index(base, "merge-base report")
head_t1 = t1_index(head, "head report")

regressed = []
for iid in sorted(base_t1):
    if base_t1[iid].get("status") != "met":
        continue
    hit = head_t1.get(iid)
    head_status = hit.get("status") if isinstance(hit, dict) else None
    if head_status != "met":
        reason = hit.get("reason") if isinstance(hit, dict) else None
        regressed.append((iid, base_t1[iid].get("title"), head_status, reason))

base_met = base["t1_met_count"]
head_met = head["t1_met_count"]

# Allow-Signoff-Regression: <id[,id...]>: <non-empty reason>  — a trailer
# with an empty reason does not match and allows nothing.
trailer_re = re.compile(
    r"(?m)^Allow-Signoff-Regression:[ \t]*([0-9]+(?:[ \t]*,[ \t]*[0-9]+)*)"
    r"[ \t]*:[ \t]*(\S.*)$")
try:
    with open(log_path) as f:
        log = f.read()
except OSError as e:
    die(f"cannot read the merge-base..HEAD commit log ({e})")
allowed = set()
for match in trailer_re.finditer(log):
    for token in match.group(1).split(","):
        token = token.strip()
        if token:
            allowed.add(int(token))

regressed_ids = sorted(iid for iid, _, _, _ in regressed)
unlisted = [iid for iid in regressed_ids if iid not in allowed]
# The count rule is defensive: a met item that vanished from the report
# entirely is already in `regressed`, so an unexplained drop means the
# report itself changed shape (item list or count arithmetic).
count_drop_unexplained = head_met < base_met and (
    not regressed or head_met < base_met - len(regressed))

if unlisted or count_drop_unexplained:
    print(f"FAIL: T1 regression vs the merge-base report {mb_short}", file=sys.stderr)
    for iid, title, head_status, reason in regressed:
        suffix = f" ({reason})" if reason else ""
        shown = head_status if head_status is not None else "missing"
        print(f"  item {iid} ({title}): met -> {shown}{suffix}", file=sys.stderr)
    if count_drop_unexplained and not regressed:
        print(f"  t1_met_count dropped {base_met} -> {head_met} "
              "with no met -> non-met T1 item transition", file=sys.stderr)
    else:
        print(f"  t1_met_count: {base_met} -> {head_met}", file=sys.stderr)
    print("A deliberate T1 regression must carry, on a commit in merge-base..HEAD:", file=sys.stderr)
    print("  Allow-Signoff-Regression: <id[,id...]>: <non-empty reason>", file=sys.stderr)
    print("(every regressed item id listed; a trailer with an empty reason allows nothing)", file=sys.stderr)
    raise SystemExit(1)

if regressed:
    ids = ", ".join(str(iid) for iid in regressed_ids)
    print(f"OK (opt-out): T1 item(s) {ids} went met -> non-met vs merge-base "
          f"{mb_short}, allowed by Allow-Signoff-Regression trailer(s) in "
          f"merge-base..HEAD (t1_met_count {base_met} -> {head_met})")
else:
    print(f"OK: no T1 met-item regression vs merge-base {mb_short} "
          f"(t1_met_count {base_met} -> {head_met})")
PY
    then
      fail "T1 direction regressed vs merge-base ${MB:0:12} of $BASE (details above)"
    fi
  fi
  exit 0
fi

echo "FAIL: signoff/t1-report.json does not match the fresh klt render — the verdict of record has drifted." >&2
echo "" >&2
echo "A manifest citation, the vendored tiers doc, or the klt pin changed" >&2
echo "without refreshing the record. Diff (committed vs fresh):" >&2
echo "" >&2
diff "$RECORD" "$tmp" >&2 || true
echo "" >&2
echo "If the change is deliberate, refresh the verdict of record and commit it:" >&2
echo "  .github/scripts/regen-signoff.sh" >&2
exit 1
