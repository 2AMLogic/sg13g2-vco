#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# drc.sh -- re-run the design-rule and guard-ring evidence for layout/vco.gds
# and rewrite the committed reports under layout/drc/.
#
#   layout/drc.sh
#
# No arguments, no GUI, no PDK overlay (none of these checks instantiates a
# PCell -- they all read the committed stream).  It is the DRC counterpart of
# layout/generate.sh: generate.sh produces the layout, this produces the
# evidence about it.  Exit status is 0 when every check lands on the verdict
# recorded in layout/PROVENANCE.md sections 12-13, non-zero on any drift -- so a
# PDK, PCell or deck change that moves a verdict fails here rather than
# silently rewriting the record.
#
# WHAT IT WRITES (all committed, all repo-root-relative inside, no host paths):
#   layout/drc/vco-drc.json         `klt drc --deck sg13g2` (curated deck) --
#                                   kept as a diagnostic: its 8 Cnt.c hits
#                                   are a deck artefact (section 12)
#   layout/drc/vco-drc-ihp.json     IHP's own primary runset (tech/drc/
#                                   ihp-sg13g2.drc) via `klt drc --engine
#                                   klayout --expect-rule-categories N` --
#                                   the DRC report of record (status clean)
#   layout/drc/vco-drc-ihp-assertion.json  how N was derived (static deck
#                                   review, not the run), the tool/engine
#                                   revisions, the exact invocation, the
#                                   negative controls and the scope limits
#   layout/drc/vco-ring-check.json  guard-ring annulus evidence + its negative
#                                   control
#   layout/drc/vco-cnt-c-control.json  the same deck re-run against a
#                                   DIAGNOSTIC copy of the stream carrying the
#                                   one `Cnt.c` term klt's deck drops, which
#                                   is what shows the remaining
#                                   `activ.enclosing.cont.1` hits are an
#                                   artefact of that approximation
#
# READ layout/PROVENANCE.md sections 12 and 13 BEFORE CITING ANY OF THIS.
# The curated-engine report (vco-drc.json) is NOT `status: clean`, and the
# reason is a deck defect rather than a layout defect (section 12); it is
# kept as a diagnostic.  The IHP-native report is `status: clean` with known
# coverage ONLY because the run vouches, via --expect-rule-categories, for a
# rule-category count derived independently from the deck source
# (layout/scripts/ihp_deck_categories.py) -- a caller's documented claim
# about this deck and invocation, not proof that every process rule in the
# DRM ran.  Chip-level density/fill, antenna and the `maximal` runset are
# outside the deck that ran (section 13).
#
# TOOLS.  The curated deck, ring-check and Cnt.c control use `klt` on PATH
# (the repo's release pin, 0.6.0) and `klayout` on PATH for the helper
# scripts.  The IHP-native run needs klayout-tools at the PR #2803 merge
# revision and KLayout 0.30.12; layout/scripts/native_drc_env.sh provisions
# both, pinned, into the gitignored scratch area (NATIVE_DRC_ENV, default
# layout/build/native-drc-env) -- see that script.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"
OUT="${HERE}/drc"
SCRATCH="${DRC_SCRATCH_DIR:-${HERE}/build/drc}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not on PATH" >&2; exit 1; }; }
need klt
need klayout
need python3

mkdir -p "${OUT}" "${SCRATCH}"
cd "${REPO_ROOT}"   # every path recorded in a report is repo-root-relative

GDS="layout/vco.gds"
# The guard ring's Activ outer box (floorplan.py RING), as the clip window
# that isolates it from the rest of the block on these shared layers.
RING_REGION='[-80.0,-106.0,105.0,-16.0]'
# ptap1 draws the ring on Activ (1/0), pSD (14/0) and Metal1 (8/0).
RING_LAYERS="1,0 14,0 8,0"

# KLayout emits a `psutil` warning per library load that is pure noise.
# Same noise filter as generate.sh: the psutil warning and the headless-host
# tkinter notice are both pure noise for these read-back helpers.
filt() { grep -v -e "^Warning: Python package 'psutil' not found!$" \
                 -e "^Could not import tkinter. No callback support.$" \
                 -e "^Warning: No tkinter installed. No callback support.*$" \
                 || true; }
KLSCRATCH="${SCRATCH}/klayout-scratch"
mkdir -p "${KLSCRATCH}"

echo "== tools: $(klt --version 2>&1 | head -1) / $(klayout -v 2>&1 | head -1)"
# The curated deck's hash and `released: true` (section 12) are the TAGGED
# 0.6.0 wheel's -- the one .github/workflows/signoff.yml pins.  A post-tag
# git build also reports "0.6.0+g<sha>" but ships a different curated deck,
# so it would silently rewrite the diagnostic reports with another deck.
[[ "$(klt --version 2>&1 | head -1)" == "klt 0.6.0" ]] || {
  echo "error: \`klt\` on PATH is '$(klt --version 2>&1 | head -1)', not the" \
       "tagged release 'klt 0.6.0' the curated reports are recorded with." \
       "Put a throwaway venv first on PATH, e.g." \
       "uv venv layout/build/klt-0.6.0 && VIRTUAL_ENV=layout/build/klt-0.6.0" \
       "uv pip install klayout-tools==0.6.0 (README, 'DRC')." >&2; exit 1; }

# ------------------------------------------------------------------- drc --
# `klt drc` exits 3 on `status: violations`; that is a verdict, not a crash,
# so the exit status is captured rather than allowed to kill the script.
echo "== drc: klt drc --deck sg13g2 --top vco"
rc=0
klt drc "${GDS}" --deck sg13g2 --top vco --format json \
  > "${OUT}/vco-drc.json" || rc=$?
[[ "${rc}" -eq 0 || "${rc}" -eq 3 ]] || {
  echo "error: klt drc failed (exit ${rc}), not a violations verdict" >&2
  cat "${OUT}/vco-drc.json" >&2; exit 1; }

# ------------------------------------------------------------- ring-check --
# A `continuous` verdict is only evidence if the SAME invocation reports
# `broken` on a layout whose ring is actually open, so every layer set is run
# twice: once on the committed stream and once on a copy with one of the four
# ptap1 bars deleted.  A layer whose negative control also comes back
# `continuous` is NOT discriminating -- the ring shares that layer with
# unrelated geometry inside the clip window -- and is recorded as such instead
# of being counted as evidence.
echo "== ring-check: guard-ring annulus, with a negative control per layer"
BROKEN="${SCRATCH}/vco_broken_ring.gds"
KLAYOUT_PATH="${KLSCRATCH}" klayout -zz -r "${HERE}/scripts/break_ring.py" \
  -rd gds="${GDS}" -rd out="${BROKEN}" -rd cell=ptap1 2>&1 | filt

for ld in ${RING_LAYERS}; do
  l="${ld%,*}"; d="${ld#*,}"
  for which in intact broken; do
    in="${GDS}"; [[ "${which}" == broken ]] && in="${BROKEN}"
    klt ring-check "${in}" --layers "[[${l},${d}]]" --region "${RING_REGION}" \
      --top vco --ignore-enclosed --format json \
      > "${SCRATCH}/ring-${l}-${d}-${which}.json" || true
  done
done

# shellcheck disable=SC2086  # RING_LAYERS is a deliberate argv list, one per layer
python3 - "${OUT}/vco-ring-check.json" "${SCRATCH}" "${GDS}" "${RING_REGION}" \
         ${RING_LAYERS} <<'PY'
import json, sys
out, scratch, gds, region = sys.argv[1:5]
rec = {"schema_version": 1, "file": gds, "region_um": json.loads(region),
       "ring_source": "the guard ring's four SG13_dev/ptap1 bars",
       "negative_control": "layout/scripts/break_ring.py deletes one of the "
                           "four ptap1 bars, opening the annulus on one side",
       "layers": []}
for ld in sys.argv[5:]:
    l, d = (int(v) for v in ld.split(","))
    got = {}
    for which in ("intact", "broken"):
        with open("%s/ring-%d-%d-%s.json" % (scratch, l, d, which)) as fh:
            r = json.load(fh)
        got[which] = {"status": r["status"],
                      "violation_count": r["violation_count"]}
    discriminating = got["broken"]["status"] == "broken"
    rec["layers"].append({
        "layer": [l, d],
        "committed_layout": got["intact"],
        "negative_control": got["broken"],
        "discriminating": discriminating,
        "evidence": (
            "guard-ring continuity on this layer is VERIFIED: continuous on "
            "the committed layout, broken on the negative control"
            if discriminating and got["intact"]["status"] == "continuous" else
            "NOT evidence: the negative control also passes, so a "
            "`continuous` verdict on this layer can come from non-ring "
            "geometry sharing it inside the clip window"
            if not discriminating else
            "FAILED: the committed layout's ring is not a closed annulus "
            "on this layer"),
    })
with open(out, "w") as fh:
    json.dump(rec, fh, indent=2, sort_keys=True)
    fh.write("\n")
for e in rec["layers"]:
    print("  ring %-6s committed=%-10s control=%-10s discriminating=%s"
          % ("%d/%d" % tuple(e["layer"]), e["committed_layout"]["status"],
             e["negative_control"]["status"], e["discriminating"]))
PY

# ----------------------------------------------------------- Cnt.c control --
# Are the remaining violations the layout's or the deck's?  Answered with
# klt's OWN check rather than a re-implementation of it: the same deck, same
# engine and same layout are re-run against a diagnostic copy that carries the
# single rule term klt's curated `Cnt.c` drops (`.join(activ_mask)`).  See
# layout/scripts/activ_mask_overlay.py -- that copy is an experiment, not a
# layout, and is written to scratch, never committed.
echo "== cnt-c-control: supply the one dropped Cnt.c term and re-run the deck"
OVERLAY="${SCRATCH}/vco_activ_mask_overlay.gds"
KLAYOUT_PATH="${KLSCRATCH}" klayout -zz -r "${HERE}/scripts/activ_mask_overlay.py" \
  -rd gds="${GDS}" -rd out="${OVERLAY}" 2>&1 | filt
rc=0
klt drc "${OVERLAY}" --deck sg13g2 --top vco --format json \
  > "${SCRATCH}/overlay-drc.json" || rc=$?
[[ "${rc}" -eq 0 || "${rc}" -eq 3 ]] || {
  echo "error: klt drc on the control stream failed (exit ${rc})" >&2; exit 1; }

python3 - "${OUT}/vco-cnt-c-control.json" "${OUT}/vco-drc.json" \
         "${SCRATCH}/overlay-drc.json" "${GDS}" <<'PY'
import json, sys
out, base_p, ovl_p, gds = sys.argv[1:5]
base = json.load(open(base_p))
ovl = json.load(open(ovl_p))
rec = {
    "schema_version": 1,
    "question": ("are the activ.enclosing.cont.1 violations in "
                 "layout/drc/vco-drc.json a defect in this layout, or an "
                 "artefact of klt's curated deck approximating IHP's Cnt.c?"),
    "method": ("single-variable control: the same deck (same content_hash), "
               "same engine and same layout are re-run against a diagnostic "
               "copy of the stream in which Activ:mask (1/20) has been "
               "copied onto Activ:drawing (1/0) -- i.e. carrying the "
               "`.join(activ_mask)` term that IHP's own Cnt.c has and klt's "
               "approximation drops, and carrying no other change. The "
               "control stream is scratch (layout/build/drc/), never "
               "committed: it is an experiment, not a layout."),
    "deck_content_hash": base["provenance"]["deck"]["content_hash"],
    "layout": {"file": gds,
               "content_hash": base["provenance"]["input"]["content_hash"]},
    "committed_stream": {"status": base["status"],
                         "violation_count": base["violation_count"],
                         "rule_counts": base["rule_counts"]},
    "control_stream_with_activ_mask_joined": {
        "status": ovl["status"], "violation_count": ovl["violation_count"],
        "rule_counts": ovl["rule_counts"]},
}
rec["conclusion"] = (
    "the one dropped rule term accounts for every remaining violation and "
    "introduces none of its own: supplying it alone takes the identical deck "
    "from %d violation(s) to %s. The layout satisfies IHP's Cnt.c as written; "
    "klt's approximation of it does not."
    % (base["violation_count"], ovl["status"])
    if ovl["violation_count"] == 0 else
    "INCONCLUSIVE / CHANGED: the control stream still reports %d violation(s) "
    "(%s). The remaining violations are NOT fully explained by the dropped "
    "activ_mask term and must be re-diagnosed before any of them is called a "
    "false positive." % (ovl["violation_count"], ovl["rule_counts"]))
with open(out, "w") as fh:
    json.dump(rec, fh, indent=2, sort_keys=True)
    fh.write("\n")
print("  cnt-c-control: committed=%s(%d)  with Cnt.c's activ_mask term=%s(%d)"
      % (base["status"], base["violation_count"],
         ovl["status"], ovl["violation_count"]))
PY

# ------------------------------------------------- IHP-native deck of record --
# IHP's own primary DRC runset, run through klt's klayout engine against the
# same committed stream.  This is the deck that implements the process rules
# the curated deck approximates -- including Cnt.c as IHP wrote it, NBL.b,
# the 5 nm grid (rule 3.1) and the 0/45/90 edge-angle rules (3.2) -- so it
# is the strongest available statement about the layout itself, and its
# report is the DRC report of record (PROVENANCE.md section 13).
#
# Its `clean` label rests on klt's opt-in coverage assertion
# (`--expect-rule-categories N`, klayout-tools PR #2803): without it klt
# caps every zero-finding external-deck run at `coverage_unknown`.  N is NOT
# read off the run it is asserted against.  It is the reviewed constant
# below, derived from the deck SOURCE (layout/scripts/ihp_deck_categories.py
# under this invocation's switches, plus the two data-dependent categories'
# stream facts from layout/scripts/ihp_deck_facts.py), and it is pinned to
# the deck's content hash: a different deck fails here until a human
# re-reviews the count, instead of being re-vouched automatically.
IHP_DECK_SHA256="0620b737538af7c86dfb7c6ca0ba3a38f8410b0d51412978ca977ea3df3fb693"
IHP_EXPECT_CATEGORIES=590
NATIVE_KLT_REV="70dee3b679a6451c5f4d830fb995c5eeb16084ee"
NATIVE_KLAYOUT_VERSION="0.30.12"
# `threads` is the only deck-var passed: it sets KLayout's worker count
# (ihp-sg13g2.drc, "Threads") and gates no rule; 2 keeps the run modest on a
# shared host.  Every rule-group switch stays at the deck's default.
NATIVE_DECK_VARS=(--deck-var threads=2)

if [[ -n "${IHP_PDK_ROOT:-}" ]]; then
  PDK="${IHP_PDK_ROOT}"
elif [[ -n "${PDK_ROOT:-}" && -d "${PDK_ROOT}/ihp-sg13g2" ]]; then
  PDK="${PDK_ROOT}/ihp-sg13g2"
elif [[ -d "${HOME}/share/pdk/ihp-sg13g2" ]]; then
  PDK="${HOME}/share/pdk/ihp-sg13g2"
else
  echo "error: cannot find an IHP-Open-PDK install for the native deck (set IHP_PDK_ROOT)" >&2
  exit 1
fi
IHDECK="${PDK}/libs.tech/klayout/tech/drc/ihp-sg13g2.drc"
[[ -f "${IHDECK}" ]] || { echo "error: no ihp-sg13g2.drc under ${PDK}" >&2; exit 1; }
deck_sha="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${IHDECK}")"
[[ "${deck_sha}" == "${IHP_DECK_SHA256}" ]] || {
  echo "error: ${IHDECK} is sha256:${deck_sha}, not the reviewed" \
       "sha256:${IHP_DECK_SHA256}.  The expected rule-category count" \
       "(${IHP_EXPECT_CATEGORIES}) was reviewed for that deck only; re-run" \
       "layout/scripts/ihp_deck_categories.py, re-review, and update both" \
       "constants together (PROVENANCE.md section 13)." >&2; exit 1; }

# The pinned native-run environment (scratch, gitignored; see the script).
NENV="${NATIVE_DRC_ENV:-${HERE}/build/native-drc-env}"
bash "${HERE}/scripts/native_drc_env.sh" "${NENV}"
KLT_N="${NENV}/klt/bin/klt"
NBIN="${SCRATCH}/native-bin"
mkdir -p "${NBIN}"
ln -sfn "${NATIVE_KLAYOUT:-${NENV}/bin/klayout}" "${NBIN}/klayout"
nkl_ver="$("${NBIN}/klayout" -v 2>/dev/null | awk '{print $2}')"
[[ "${nkl_ver}" == "${NATIVE_KLAYOUT_VERSION}" ]] || {
  echo "error: native-run KLayout is '${nkl_ver}', expected" \
       "${NATIVE_KLAYOUT_VERSION}" >&2; exit 1; }
nklt_rev="$("${NENV}/klt/bin/python" -c 'import json,importlib.metadata as m;print(json.loads(m.distribution("klayout-tools").read_text("direct_url.json"))["vcs_info"]["commit_id"])')"
[[ "${nklt_rev}" == "${NATIVE_KLT_REV}" ]] || {
  echo "error: native-run klt is revision ${nklt_rev}, expected ${NATIVE_KLT_REV}" >&2
  exit 1; }
echo "== native tools: $("${KLT_N}" --version 2>&1 | head -1) @ ${nklt_rev} / KLayout ${nkl_ver}"

native() {   # native <scratch-stem> [extra klt args...]; sets nrc
  local stem="$1"; shift
  nrc=0
  PATH="${NBIN}:${PATH}" "${KLT_N}" drc "${GDS}" --engine klayout \
    --deck-file "${IHDECK}" "${NATIVE_DECK_VARS[@]}" --format json "$@" \
    > "${SCRATCH}/${stem}.json" 2> "${SCRATCH}/${stem}.err" || nrc=$?
}

# The expected count, re-derived from the deck source every run and required
# to equal the reviewed constant.
echo "== ihp-native: static rule-category review of ihp-sg13g2.drc"
KLAYOUT_PATH="${KLSCRATCH}" klayout -zz -r "${HERE}/scripts/ihp_deck_facts.py" \
  -rd gds="${GDS}" -rd deck="${IHDECK}" -rd out="${SCRATCH}/ihp-facts.json" 2>&1 | filt
python3 "${HERE}/scripts/ihp_deck_categories.py" "${IHDECK}" \
  --facts "${SCRATCH}/ihp-facts.json" > "${SCRATCH}/ihp-categories.json"

echo "== ihp-native: klt drc --engine klayout --expect-rule-categories ${IHP_EXPECT_CATEGORIES}"
native ihp-record --expect-rule-categories "${IHP_EXPECT_CATEGORIES}"
echo "   run of record: exit ${nrc}"
rc_record=${nrc}
# Negative controls, all scratch.  The assertion is only evidence if it can
# fail: a wrong count, and the right count with one rule group gated off
# (ANGLE: 210 categories), must both refuse to produce any report; and the
# same run without the assertion must keep klt's conservative verdict.
N1=$((IHP_EXPECT_CATEGORIES + 1))
native ihp-ctl-wrong-count --expect-rule-categories "${N1}"
echo "   control, --expect-rule-categories ${N1}: exit ${nrc}"
rc_wrong=${nrc}
native ihp-ctl-gated-group --deck-var no_angle=true \
  --expect-rule-categories "${IHP_EXPECT_CATEGORIES}"
echo "   control, no_angle=true with the reviewed count: exit ${nrc}"
rc_gated=${nrc}
native ihp-ctl-no-assertion
echo "   control, no assertion: exit ${nrc}"
rc_none=${nrc}

# The native contract, enforced before anything is committed: the run of
# record is copied into layout/drc/ only if every check below holds, so a
# mismatched assertion, a partial or deck-error run, an unknown verdict or a
# new finding fails this script and leaves the committed report untouched.
python3 - "${OUT}" "${SCRATCH}" "${GDS}" "${IHP_EXPECT_CATEGORIES}" \
         "${IHP_DECK_SHA256}" "${NATIVE_KLT_REV}" "${NATIVE_KLAYOUT_VERSION}" \
         "${rc_record}" "${rc_wrong}" "${rc_gated}" "${rc_none}" \
         "${NATIVE_KLAYOUT:+caller-supplied NATIVE_KLAYOUT binary}" <<'PY'
import hashlib, json, os, shutil, sys
(out, scratch, gds, n, deck_sha, klt_rev, kl_ver,
 rc_record, rc_wrong, rc_gated, rc_none, kl_src) = sys.argv[1:13]
n = int(n)
rc = {"record": int(rc_record), "wrong": int(rc_wrong),
      "gated": int(rc_gated), "none": int(rc_none)}
S = lambda stem, ext: os.path.join(scratch, "%s.%s" % (stem, ext))
fail = []

def load(stem):
    try:
        with open(S(stem, "json")) as fh:
            txt = fh.read()
        return json.loads(txt) if txt.strip() else None
    except ValueError as e:
        fail.append("%s: stdout is not a JSON report (%s)" % (stem, e))
        return None

def err_msg(stem):
    try:
        return json.load(open(S(stem, "err")))["error"]["message"]
    except Exception:
        return open(S(stem, "err")).read().strip()

static = json.load(open(os.path.join(scratch, "ihp-categories.json")))
if static["expected_unique_categories"] != n:
    fail.append("static deck review now derives %d categories, the reviewed "
                "constant is %d -- re-review (PROVENANCE.md section 13)"
                % (static["expected_unique_categories"], n))

gds_sha = hashlib.sha256(open(gds, "rb").read()).hexdigest()
rec = load("ihp-record")
if rc["record"] != 0 or rec is None:
    fail.append("run of record exited %d (expected 0, clean): %s"
                % (rc["record"],
                   "status %s, NEW NATIVE FINDING(S) %s"
                   % (rec["status"], rec["rule_counts"]) if rec is not None
                   else err_msg("ihp-record")[:600]))
else:
    cov, prov = rec["coverage"], rec["provenance"]
    want = {"kind": "expected_rule_categories", "expected": n,
            "observed": n, "satisfied": True}
    checks = [
        (rec["status"] == "clean", "status is %r, not clean" % rec["status"]),
        (rec["violation_count"] == 0 and rec["rule_counts"] == {},
         "NEW NATIVE FINDING(S): %d %s"
         % (rec["violation_count"], rec["rule_counts"])),
        (rec.get("coverage_assertion") == want,
         "coverage_assertion is %r, expected %r"
         % (rec.get("coverage_assertion"), want)),
        (cov["known"] is True and cov["unknown"] == []
         and not cov["nothing_checked"],
         "coverage is not known: known=%r unknown=%r"
         % (cov["known"], cov["unknown"])),
        (not rec.get("engine_deck_errors"),
         "the run tolerated deck errors: %r" % rec.get("engine_deck_errors")),
        (set(cov["rule_categories"]) == set(static["categories"]),
         "declared categories differ from the static review: +%s -%s"
         % (sorted(set(cov["rule_categories"]) - set(static["categories"])),
            sorted(set(static["categories"]) - set(cov["rule_categories"])))),
        (prov["deck"]["content_hash"] == "sha256:" + deck_sha,
         "deck hash %s" % prov["deck"]["content_hash"]),
        (prov["input"]["content_hash"] == "sha256:" + gds_sha,
         "input hash %s is not %s's" % (prov["input"]["content_hash"], gds)),
        (prov["klayout_version"] == kl_ver
         and prov.get("klayout_version_mismatch") is False,
         "engine KLayout %r (mismatch=%r)"
         % (prov["klayout_version"], prov.get("klayout_version_mismatch"))),
        (prov["klt_version"].endswith("+g" + klt_rev[:12]),
         "klt_version %r is not revision %s" % (prov["klt_version"], klt_rev)),
    ]
    fail += [msg for ok, msg in checks if not ok]

controls = []
for stem, key, what in (
        ("ihp-ctl-wrong-count", "wrong",
         "--expect-rule-categories %d (reviewed count + 1)" % (n + 1)),
        ("ihp-ctl-gated-group", "gated",
         "--deck-var no_angle=true --expect-rule-categories %d (the 3.2 "
         "angle group gated off, reviewed count kept)" % n)):
    got = load(stem)
    msg = err_msg(stem)
    ok = (rc[key] not in (0, 3, 4) and got is None
          and "coverage assertion failed" in msg)
    if not ok:
        fail.append("negative control %s did not fail as required (exit %d, "
                    "report written: %s)" % (what, rc[key], got is not None))
    controls.append({"control": what, "exit": rc[key],
                     "report_written": got is not None,
                     "error": msg, "discriminating": ok})
none = load("ihp-ctl-no-assertion")
ok = (rc["none"] == 4 and none is not None
      and none["status"] == "coverage_unknown"
      and none["violation_count"] == 0 and none["coverage"]["known"] is False
      and none.get("coverage_assertion") is None)
if not ok:
    fail.append("no-assertion control did not keep the conservative "
                "coverage_unknown verdict (exit %d)" % rc["none"])
controls.append({"control": "same invocation without --expect-rule-categories",
                 "exit": rc["none"],
                 "status": none and none["status"],
                 "violation_count": none and none["violation_count"],
                 "coverage_known": none and none["coverage"]["known"],
                 "keeps_conservative_verdict": ok})

if fail:
    print("\n== NATIVE DRC CONTRACT NOT MET -- layout/drc/vco-drc-ihp.json "
          "left untouched")
    for f in fail:
        print("  [FAIL] %s" % f)
    sys.exit(1)

shutil.copyfile(S("ihp-record", "json"), os.path.join(out, "vco-drc-ihp.json"))
side = {
    "schema_version": 1,
    "report": "layout/drc/vco-drc-ihp.json",
    "verdict": {"status": rec["status"],
                "violation_count": rec["violation_count"],
                "coverage_known": rec["coverage"]["known"],
                "coverage_assertion": rec["coverage_assertion"]},
    "tools": {
        "klt": {"package": "klayout-tools",
                "source": "git+https://github.com/2AMLogic/klayout-tools",
                "revision": klt_rev,
                "why": "the merge commit of PR #2803, which added "
                       "--expect-rule-categories; no release carries it yet",
                "reported_version": rec["provenance"]["klt_version"],
                "provisioned_by": "layout/scripts/native_drc_env.sh"},
        "klayout_engine": {
            "version": rec["provenance"]["klayout_version"],
            "source": kl_src or (
                "KLayout's own Ubuntu-24 package klayout_0.30.12-1_amd64.deb "
                "(sha256 23480767fec91bc9a15e075a9bd6906ba85cd7fdda8b4040dde4"
                "ffc95c26a742), extracted, not installed, by "
                "layout/scripts/native_drc_env.sh")},
    },
    "deck": {"pdk_relative_path": "libs.tech/klayout/tech/drc/ihp-sg13g2.drc",
             "content_hash": "sha256:" + deck_sha},
    "input": {"file": gds, "content_hash": "sha256:" + gds_sha},
    "invocation": ["klt", "drc", gds, "--engine", "klayout", "--deck-file",
                   "$IHP_PDK_ROOT/libs.tech/klayout/tech/drc/ihp-sg13g2.drc",
                   "--deck-var", "threads=2",
                   "--expect-rule-categories", str(n), "--format", "json"],
    "assertion_rationale": {
        "expected_unique_categories": n,
        "derived_from": "the deck SOURCE, not this run: "
                        "layout/scripts/ihp_deck_categories.py enumerates "
                        "every .output(...) name reachable under the "
                        "modelled invocation, expanding each interpolated "
                        "name over the loop domain its own file defines",
        "invocation_modelled": static["invocation_modelled"],
        "included_files": static["included_files"],
        "per_file": static["per_file"],
        "data_dependent_categories": static["conditional_categories"],
        "stream_facts": static["facts"],
        "cross_check": "the run's declared category SET equals the "
                       "statically enumerated set (not only its size)",
        "pinned_to_deck_hash": "sha256:" + deck_sha,
    },
    "negative_controls": controls,
    "limits": [
        "the assertion is a caller's documented claim about which rule "
        "categories this deck declares under this invocation; KLayout creates "
        "a category when a rule's output() is reached, so it shows every "
        "rule's code ran, not that each rule faithfully transcribes the DRM",
        "scope is IHP's PRIMARY runset ihp-sg13g2.drc only; IHP's own "
        "run_drc.py additionally runs rule_decks/density.drc and "
        "rule_decks/sg13g2_maximal.drc by default and antenna.drc on "
        "request -- none of them is covered by this report "
        "(PROVENANCE.md sections 12 and 13)",
        "chip-level density/fill is deferred to chip assembly: the block "
        "ships un-filled and fails the min-global-density rules by design",
        "Seal.l and MIM.gR are data-dependent categories this stream does "
        "not trigger (no EdgeSeal boundary; MIM area far below Mim_gR)",
        "block-level run: sealring, pad, bump and pillar rules are declared "
        "and pass vacuously because the block carries no such structures",
        "DRC only: no LVS claim (issue #62)",
    ],
}
with open(os.path.join(out, "vco-drc-ihp-assertion.json"), "w") as fh:
    json.dump(side, fh, indent=2, sort_keys=True)
    fh.write("\n")
print("  ihp-native: status=%s violations=%d assertion %d/%d satisfied; "
      "controls discriminating" % (rec["status"], rec["violation_count"],
                                    n, rec["coverage_assertion"]["observed"]))
PY

# ------------------------------------------------------------- assertions --
# The recorded verdict, asserted rather than described.  Any drift fails.
python3 - "${OUT}" <<'PY'
import json, sys, os
out = sys.argv[1]
drc = json.load(open(os.path.join(out, "vco-drc.json")))
ring = json.load(open(os.path.join(out, "vco-ring-check.json")))
cnt = json.load(open(os.path.join(out, "vco-cnt-c-control.json")))
fail = []

# 1. The only rule the deck still reports is the one PROVENANCE.md section 12
#    demonstrates is a false positive.  A violation of ANY other rule is a
#    real layout defect and must fail this script.
other = {k: v for k, v in drc["rule_counts"].items()
         if k != "activ.enclosing.cont.1"}
if other:
    fail.append("klt drc reports rules beyond the known deck artefact: %s" % other)

# 2. ... and the artefact's count is exactly the four HBT instances' worth.
if drc["rule_counts"].get("activ.enclosing.cont.1", 0) != 8:
    fail.append("activ.enclosing.cont.1 count moved from 8 to %s"
                % drc["rule_counts"].get("activ.enclosing.cont.1", 0))

# 3. The guard ring is a closed annulus on every layer where the check is
#    shown to be able to fail.
if not any(e["discriminating"] for e in ring["layers"]):
    fail.append("no ring-check layer is discriminating -- the guard-ring "
                "evidence has no negative control and is unsupported")
for e in ring["layers"]:
    if e["discriminating"] and e["committed_layout"]["status"] != "continuous":
        fail.append("guard ring is %s on layer %s"
                    % (e["committed_layout"]["status"], e["layer"]))

# 4. The Cnt.c artefact is still an artefact: the control stream, carrying
#    the one dropped rule term, is clean.  If it ever is not, the remaining
#    violations are REAL and must not be described as a deck artefact.
ctl = cnt["control_stream_with_activ_mask_joined"]
if ctl["violation_count"] != 0:
    fail.append("the Cnt.c control stream reports %d violation(s) %s -- the "
                "remaining violations are no longer explained by the deck's "
                "dropped activ_mask term and must be re-diagnosed"
                % (ctl["violation_count"], ctl["rule_counts"]))

# 5. The IHP-native report of record is CLEAN under the reviewed coverage
#    assertion: zero findings (any finding is a real process-rule violation
#    in this layout -- that deck implements the process rules, not an
#    approximation of them), known coverage, and a satisfied assertion whose
#    expected count is the reviewed one.  The native section above already
#    refused to commit anything weaker; this re-reads what was committed.
ihp = json.load(open(os.path.join(out, "vco-drc-ihp.json")))
side = json.load(open(os.path.join(out, "vco-drc-ihp-assertion.json")))
ca = ihp.get("coverage_assertion") or {}
if ihp["violation_count"] != 0:
    fail.append("the IHP-native deck reports %d violation(s) %s"
                % (ihp["violation_count"], ihp["rule_counts"]))
if ihp["status"] != "clean":
    fail.append("the IHP-native deck's status is %r, expected clean"
                % ihp["status"])
if not (ca.get("satisfied") is True and ca.get("expected") == ca.get("observed")
        == side["assertion_rationale"]["expected_unique_categories"]):
    fail.append("the IHP-native coverage assertion is not the reviewed, "
                "satisfied one: %r" % ca)
if not all(c.get("discriminating", c.get("keeps_conservative_verdict"))
           for c in side["negative_controls"]):
    fail.append("an IHP-native negative control is not discriminating")

if fail:
    print("\n== DRIFT: the committed verdict no longer holds")
    for f in fail:
        print("  [FAIL] %s" % f)
    sys.exit(1)

print("\n== verdict (unchanged from layout/PROVENANCE.md sections 12-13)")
print("  klt drc        : status=%s  %s" % (drc["status"], drc["rule_counts"]))
print("                   all %d are activ.enclosing.cont.1 inside the PDK's"
      % drc["violation_count"])
print("                   own npn13G2V PCell -- a curated-deck approximation")
print("                   artefact, shown by vco-cnt-c-control.json, NOT a")
print("                   layout defect.  NOT a clean report; see section 12.")
for e in ring["layers"]:
    print("  ring %-6s    : %s" % ("%d/%d" % tuple(e["layer"]),
                                   e["evidence"].split(":")[0]))
print("  ihp-native    : status=%s, %d violation(s), coverage known, "
      "assertion %d/%d satisfied -- the DRC report of record; its scope "
      "and limits are section 13" % (ihp["status"], ihp["violation_count"],
                                     ca["expected"], ca["observed"]))
PY
