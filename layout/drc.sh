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
# recorded in layout/PROVENANCE.md section 12, non-zero on any drift -- so a
# PDK, PCell or deck change that moves a verdict fails here rather than
# silently rewriting the record.
#
# WHAT IT WRITES (all committed, all repo-root-relative inside, no host paths):
#   layout/drc/vco-drc.json         `klt drc --deck sg13g2` report of record
#   layout/drc/vco-ring-check.json  guard-ring annulus evidence + its negative
#                                   control
#   layout/drc/vco-cnt-c-control.json  the same deck re-run against a
#                                   DIAGNOSTIC copy of the stream carrying the
#                                   one `Cnt.c` term klt's deck drops, which
#                                   is what shows the remaining
#                                   `activ.enclosing.cont.1` hits are an
#                                   artefact of that approximation
#
# READ layout/PROVENANCE.md section 12 BEFORE CITING ANY OF THIS.  The report
# of record is NOT `status: clean`, and the reason is a deck defect rather
# than a layout defect; signoff/design-evidence-tiers.md item 3 is therefore
# NOT satisfied by it.

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
filt() { grep -v "^Warning: Python package 'psutil' not found!$" || true; }
KLSCRATCH="${SCRATCH}/klayout-scratch"
mkdir -p "${KLSCRATCH}"

echo "== tools: $(klt --version 2>&1 | head -1) / $(klayout -v 2>&1 | head -1)"

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

if fail:
    print("\n== DRIFT: the committed verdict no longer holds")
    for f in fail:
        print("  [FAIL] %s" % f)
    sys.exit(1)

print("\n== verdict (unchanged from layout/PROVENANCE.md section 12)")
print("  klt drc        : status=%s  %s" % (drc["status"], drc["rule_counts"]))
print("                   all %d are activ.enclosing.cont.1 inside the PDK's"
      % drc["violation_count"])
print("                   own npn13G2V PCell -- a curated-deck approximation")
print("                   artefact, shown by vco-cnt-c-control.json, NOT a")
print("                   layout defect.  NOT a clean report; see section 12.")
for e in ring["layers"]:
    print("  ring %-6s    : %s" % ("%d/%d" % tuple(e["layer"]),
                                   e["evidence"].split(":")[0]))
PY
