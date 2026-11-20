#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# erc.sh -- re-run the klt erc supply-spec evidence for layout/vco.gds and
# rewrite the committed reports under layout/erc/.
#
#   layout/erc.sh
#
# No arguments, no GUI, no PDK install (the device-body carve-outs come from
# klt's curated sg13g2 deck, not from a PDK overlay).  It is the ERC sibling
# of layout/drc.sh and layout/lvs.sh: those produce the DRC and LVS evidence
# about the committed stream, this produces the supply-connectivity evidence
# (the ERC half of T1 item 11, issue #330; LVS closure stays with #62).
# Exit status is 0 when every verdict lands on the state recorded in
# layout/PROVENANCE.md section 16, non-zero on any drift -- so a layout,
# deck or tool change that moves a supply verdict fails here rather than
# silently rewriting the record.
#
# WHAT IT WRITES (all committed, all repo-root-relative inside, no host
# paths; the negative-control stream itself stays in gitignored scratch):
#   layout/erc/vco-erc-spec.json    the committed supply spec (an input:
#                                   nine stackup roles, eight vias, the two
#                                   supplies with island counts and owned
#                                   roles, and the guard-ring substrate tie)
#   layout/erc/vco-erc.json         `klt erc --format json` envelope of
#                                   record: erc_status clean, both supplies
#                                   one electrical island, zero findings,
#                                   the tie checked (issue #330)
#   layout/erc/vco-erc-control.json the AC3 negative control: the same
#                                   invocation against a copy of the stream
#                                   with one ptap1 guard-ring bar deleted
#                                   (layout/scripts/break_ring.py) must be
#                                   REJECTED -- erc_status violations with
#                                   erc.missing_tie / erc.unconnected_net
#                                   naming `0`.  A control that leaves the
#                                   verdict unchanged is a failed control and
#                                   fails this script (PROVENANCE.md section
#                                   12's standard), never a silent pass.
#
# WHAT IT DOES NOT CLAIM.  The envelope's antenna verdicts are `unchecked`
# (no --pdk limit table was passed); antenna is item 3's deck evidence
# (PROVENANCE.md section 13: 0 findings), not this item's subject, and item
# 11 grades `erc_status`/`erc_findings`/`erc_coverage`, not the envelope's
# overall `status`.  The envelope's overall status is therefore
# `not_checked` (exit 4) -- a verdict, not a crash, and captured as such.
# LVS is not touched: item 11's LVS half is item 4's own report (#62), and
# `klt lvs` at this pin refuses this compare (PROVENANCE.md section 14); the
# committed refusal is what item 11's second citation names.
#
# TOOLS.  `klt` 0.8.0, the tagged wheel the committed ERC record reproduces
# under (the claims pin, .github/klt-version, moved to 0.9.2 in #416; this
# record regenerates under it via #266), in a
# throwaway venv (KLT_RELEASE_ENV, default layout/build/klt-0.8.0) -- never
# the host's, which is a post-tag dev build.  The negative control needs
# `klayout` on PATH (it runs layout/scripts/break_ring.py inside KLayout's
# interpreter) and python3 for the record assembly.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"
OUT="${HERE}/erc"
SCRATCH="${ERC_SCRATCH_DIR:-${HERE}/build/erc}"

KLT_PIN="0.8.0"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not on PATH" >&2; exit 1; }; }
need python3
need klayout

mkdir -p "${OUT}" "${SCRATCH}"
cd "${REPO_ROOT}"   # every path recorded in a report is repo-root-relative

GDS="layout/vco.gds"
SPEC="layout/erc/vco-erc-spec.json"

# ----------------------------------------------------------------- tools --
# The tagged klayout-tools 0.8.0 wheel the committed records reproduce
# under (see the TOOLS note above), in a
# throwaway venv -- the same environment layout/lvs.sh provisions for its
# klt leg.  A post-tag host build ships a different curated deck and would
# silently rewrite the record with it (see layout/drc.sh's tool note).
KLT_REL="${KLT_RELEASE_ENV:-${HERE}/build/klt-${KLT_PIN}}"
if [[ ! -x "${KLT_REL}/bin/klt" ]]; then
  need uv
  uv venv -q "${KLT_REL}"
  VIRTUAL_ENV="${KLT_REL}" uv pip install -q "klayout-tools==${KLT_PIN}"
fi
KLT="${KLT_REL}/bin/klt"
[[ "$("${KLT}" --version 2>&1 | head -1)" == "klt ${KLT_PIN}" ]] || {
  echo "error: ${KLT_REL} does not hold the tagged klayout-tools ${KLT_PIN}" >&2; exit 1; }
KLAYOUT_PATH="${SCRATCH}/klayout-scratch"
mkdir -p "${KLAYOUT_PATH}"

echo "== tools: $("${KLT}" --version 2>&1 | head -1) / $(klayout -v 2>&1 | head -1)"

# --------------------------------------------------------- validate spec --
# Schema + cross-reference check, no layout read.  The committed spec must
# validate on its own before anything runs against the layout.
echo "== validate-spec: ${SPEC}"
"${KLT}" erc --validate-spec "${SPEC}"

# ------------------------------------------------------------------- run --
# `klt erc` exits 4 on `status: not_checked` (antenna verdicts unchecked
# without --pdk); that is the expected verdict of this form, not a crash,
# so the exit status is captured rather than allowed to kill the script.
echo "== erc: klt erc ${GDS} ${SPEC} --top vco --deck sg13g2"
rc=0
"${KLT}" erc "${GDS}" "${SPEC}" --top vco --deck sg13g2 --format json \
  > "${OUT}/vco-erc.json" || rc=$?
[[ "${rc}" -eq 0 || "${rc}" -eq 4 ]] || {
  echo "error: klt erc failed (exit ${rc}), not a not_checked verdict" >&2
  cat "${OUT}/vco-erc.json" >&2; exit 1; }

# ------------------------------------------------------- negative control --
# A clean supply verdict is only evidence if the SAME invocation FAILS on a
# layout whose substrate tie is actually broken, so the committed stream is
# re-run against a copy with one of the four ptap1 guard-ring bars deleted
# (scripts/break_ring.py, the same control layout/drc.sh uses for the
# ring-check).  That bar also carries the layout's only `0` label text, so
# the control moves the net-connectivity verdict as well as the tie verdict;
# both facts are recorded in the control record, with the exact finding
# rules that name `0`.
echo "== negative control: one ptap1 bar deleted (scripts/break_ring.py)"
BROKEN="${SCRATCH}/vco_broken_ring.gds"
KLAYOUT_PATH="${KLAYOUT_PATH}" klayout -zz -r "${HERE}/scripts/break_ring.py" \
  -rd gds="${GDS}" -rd out="${BROKEN}" -rd cell=ptap1 2>&1 \
  | grep -v -e "^Warning: Python package 'psutil' not found!$" \
           -e "^Could not import tkinter. No callback support.$" || true
[[ -f "${BROKEN}" ]] || { echo "error: break_ring.py wrote no control stream" >&2; exit 1; }

crc=0
"${KLT}" erc "${BROKEN}" "${SPEC}" --top vco --deck sg13g2 --format json \
  > "${SCRATCH}/vco-erc-control.json" || crc=$?
[[ "${crc}" -eq 0 || "${crc}" -eq 3 || "${crc}" -eq 4 ]] || {
  echo "error: klt erc on the control stream failed (exit ${crc}), not a verdict" >&2
  cat "${SCRATCH}/vco-erc-control.json" >&2; exit 1; }

# Assemble the committed control record: both verdicts side by side, the
# way layout/drc/vco-ring-check.json carries its own.  Deterministic: no
# timestamps, repo-relative paths only.
python3 - "${OUT}/vco-erc-control.json" "${OUT}/vco-erc.json" \
          "${SCRATCH}/vco-erc-control.json" "${GDS}" "${SPEC}" <<'PY'
import json, sys

out, intact_p, broken_p, gds, spec = sys.argv[1:6]
intact = json.load(open(intact_p))
broken = json.load(open(broken_p))

def verdicts(env):
    nets = {n["name"]: n["matched_islands"] for n in env.get("nets") or []}
    return {
        "erc_status": env.get("erc_status"),
        "finding_count": env.get("erc_finding_count"),
        "rules": sorted({f.get("rule") for f in env.get("erc_findings") or []}),
        "supply_islands": {k: v for k, v in nets.items()},
    }

intact_v = verdicts(intact)
broken_v = verdicts(broken)
names_zero = [
    f for f in broken.get("erc_findings") or []
    if f.get("rule") in ("erc.missing_tie", "erc.unconnected_net")
    and f.get("net") == "0"
]
rejected = (
    broken_v["erc_status"] == "violations"
    and intact_v["erc_status"] == "clean"
    and bool(names_zero)
)
rec = {
    "schema_version": 1,
    "file": gds,
    "spec": spec,
    "invocation": "klt erc <file> layout/erc/vco-erc-spec.json "
                  "--top vco --deck sg13g2 --format json",
    "negative_control": {
        "script": "layout/scripts/break_ring.py",
        "break": "deletes one of the guard ring's four SG13_dev/ptap1 bars",
        "observed": "that bar carries the layout's only `0` label text, so "
                    "the control removes the net's label together with its "
                    "substrate tie: erc.missing_tie (tap no longer wired to "
                    "`0`), erc.unconnected_net (`0` matches no labelled "
                    "geometry) and the roles measurement (unlabelled "
                    "remainder on every owned role) all fire together",
    },
    "committed_layout": intact_v,
    "negative_control_verdict": broken_v,
    "rejected": rejected,
    "evidence": (
        "the supply verdict is VERIFIED: clean on the committed layout, "
        "rejected (violations, findings naming `0`) on the negative control"
        if rejected else
        "FAILED CONTROL: the negative control did not move the verdict, so "
        "the committed run's clean verdict is indistinguishable from a "
        "check that cannot fail -- do not cite this evidence"
    ),
}
with open(out, "w") as fh:
    json.dump(rec, fh, indent=2, sort_keys=True)
    fh.write("\n")
print("  control: committed=%s control=%s rejected=%s"
      % (intact_v["erc_status"], broken_v["erc_status"], rejected))
PY

# ------------------------------------------------------------ check gate --
# The committed envelope must still re-hash clean against its recorded
# layout/spec/deck digests (cheap mode; exit 3 on drift).
echo "== check: klt erc --check ${OUT}/vco-erc.json"
"${KLT}" erc --check "${OUT}/vco-erc.json"

# ---------------------------------------------------------- verdict gates --
# Every expectation PROVENANCE.md section 16 records, re-derived from the
# just-written files.  Any drift fails the run (CI), leaving the drifted
# files in the tree for the reviewer to read.
python3 - "${OUT}/vco-erc.json" "${OUT}/vco-erc-control.json" <<'PY'
import json, sys

env = json.load(open(sys.argv[1]))
ctl = json.load(open(sys.argv[2]))
bad = []

def want(cond, msg):
    if not cond:
        bad.append(msg)

want(env.get("erc_status") == "clean",
     "committed envelope erc_status is %r, expected 'clean'" % env.get("erc_status"))
want(env.get("erc_finding_count") == 0,
     "committed envelope carries %r erc findings, expected 0"
     % env.get("erc_finding_count"))
for n in env.get("nets") or []:
    want(n.get("matched_islands") == 1,
         "supply %r resolves to %r islands, expected exactly 1"
         % (n.get("name"), n.get("matched_islands")))
    want(n.get("unlabelled_islands") == n.get("unlabelled_allowed_islands"),
         "supply %r: unlabelled islands %r exceed the declared carve-out %r"
         % (n.get("name"), n.get("unlabelled_islands"),
            n.get("unlabelled_allowed_islands")))
cov = env.get("erc_coverage") or {}
want(not (cov.get("skipped") or []),
     "erc_coverage.skipped is non-empty: %r" % (cov.get("skipped"),))
wac = cov.get("well_assertion_coverage") or []
want(wac and all(e.get("uncovered_tap_fraction") == 0.0 for e in wac),
     "well_assertion_coverage is missing or does not span every drawn tap")
ctl_ok = ctl.get("rejected") is True
want(ctl_ok, "the negative control was not rejected: rejected=%r" % ctl.get("rejected"))

for msg in bad:
    print("ERC VERDICT DRIFT: %s" % msg, file=sys.stderr)
sys.exit(1 if bad else 0)
PY

echo "== erc evidence reproduced: verdicts match PROVENANCE.md section 16"
