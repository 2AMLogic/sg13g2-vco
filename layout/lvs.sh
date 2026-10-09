#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# lvs.sh -- re-run the layout-vs-schematic evidence for layout/vco.gds against
# design/vco.spice and rewrite the committed record under layout/lvs/.
#
#   layout/lvs.sh
#
# No arguments, no GUI, no PDK overlay (nothing here instantiates a PCell).
# The LVS counterpart of layout/drc.sh.  Exit status is 0 when every compare
# lands on the verdict recorded in layout/PROVENANCE.md section 14, non-zero
# on any drift -- so a schematic, layout, PDK-deck or tool change that moves
# a verdict fails here instead of silently rewriting the record.
#
# THE VERDICT OF RECORD IS `mismatch`.  READ PROVENANCE.md SECTION 14 FIRST.
# The device-aware compare runs IHP's own KLayout LVS runset (the only
# extractor available that recognizes all 42 of this block's devices) and
# finds exactly one class of difference, isolated below by a
# single-variable control:
#   (The 32 varactors' `bn` (substrate) pin used to be a third class: the
#   schematic tied it to the tank node.  Issue #79 corrected design/vco.sch to
#   tie it to `0`; that difference is gone -- PROVENANCE.md section 14.)
#   1. spiral L1's two winding terminals: IHP's extractor orders inductor
#      terminals by x position, and L1 is the mirrored instance -- the LA/LB
#      labels show the layout itself is wired as the schematic says
#      (prerequisite issue #80).
# Neither is reconciled in the reference of record.  `klt lvs` (the repo's
# pinned 0.6.0, and the newest release 0.7.0 -- section 14.5) cannot run this
# compare at all; both refusals are recorded (2AMLogic/klayout-tools#2849).
#
# WHAT IT WRITES (all committed, repo-root-relative inside, no host paths):
#   layout/lvs/vco-reference.cir    LVS reference DERIVED from design/vco.spice
#   layout/lvs/vco-reference.json   per-line trace of that derivation (T1..T6)
#   layout/lvs/vco-extracted.cir    IHP runset's device-aware extraction of
#                                   layout/vco.gds (its date stamp removed)
#   layout/lvs/vco-lvs-ihp.json     the compare of record, read back from
#                                   KLayout's own .lvsdb cross-reference
#   layout/lvs/vco-lvs-record.json  tools, deck hash, inputs, invocation,
#                                   the controls and their outcomes, the klt
#                                   attempt, and the limits
#
# TOOLS.  IHP's runset needs a standalone KLayout >= 0.30.2; the pinned
# environment layout/scripts/native_drc_env.sh provisions for the native DRC
# (KLayout 0.30.12, extracted into gitignored scratch) is reused, together
# with the `klayout` Python module of its venv.  The klt leg uses the tagged
# klayout-tools==0.6.0 wheel CI pins, in a throwaway venv
# (KLT_RELEASE_ENV, default layout/build/klt-0.6.0) -- never the host's.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"
OUT="${HERE}/lvs"
SCRATCH="${LVS_SCRATCH_DIR:-${HERE}/build/lvs}"

NATIVE_KLAYOUT_VERSION="0.30.12"
# sha256 over "<sha256>  <path>\n" of sg13g2.lvs, run_lvs.py and
# rule_decks/*.lvs (sorted), relative to libs.tech/klayout/tech/lvs/.  The
# transformations and expectations below were reviewed against exactly this
# runset; any other one fails before running, with an instruction to re-review.
IHP_LVS_DECK_SHA="fd11fced5b0bd5ee0bb66b700acbe359f23c30c5900b16e5f647ed9a430dcc09"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not on PATH" >&2; exit 1; }; }
need python3

mkdir -p "${OUT}" "${SCRATCH}"
rm -rf "${SCRATCH:?}"/run-* "${SCRATCH:?}"/ref "${SCRATCH:?}"/ctl "${SCRATCH:?}"/klt
mkdir -p "${SCRATCH}/ref" "${SCRATCH}/ctl" "${SCRATCH}/klt"
cd "${REPO_ROOT}"   # every path recorded is repo-root-relative

GDS="layout/vco.gds"
SRC="design/vco.spice"

# ------------------------------------------------------------------ pdk --
if [[ -n "${IHP_PDK_ROOT:-}" ]]; then
  PDK="${IHP_PDK_ROOT}"
elif [[ -n "${PDK_ROOT:-}" && -d "${PDK_ROOT}/ihp-sg13g2" ]]; then
  PDK="${PDK_ROOT}/ihp-sg13g2"
elif [[ -d "${HOME}/share/pdk/ihp-sg13g2" ]]; then
  PDK="${HOME}/share/pdk/ihp-sg13g2"
else
  echo "error: cannot find an IHP-Open-PDK install (set IHP_PDK_ROOT)" >&2; exit 1
fi
LVSDIR="${PDK}/libs.tech/klayout/tech/lvs"
[[ -f "${LVSDIR}/run_lvs.py" ]] || { echo "error: no ${LVSDIR}/run_lvs.py" >&2; exit 1; }
deck_sha="$(cd "${LVSDIR}" && for f in $(ls sg13g2.lvs run_lvs.py rule_decks/*.lvs | LC_ALL=C sort); do
  printf '%s  %s\n' "$(sha256sum "$f" | awk '{print $1}')" "$f"; done | sha256sum | awk '{print $1}')"
[[ "${deck_sha}" == "${IHP_LVS_DECK_SHA}" ]] || {
  echo "error: IHP LVS runset under ${LVSDIR} hashes to ${deck_sha}, not the" \
       "reviewed ${IHP_LVS_DECK_SHA}.  Re-review the reference transformations" \
       "(layout/scripts/lvs_reference.py) and the expectations below against" \
       "it, then update IHP_LVS_DECK_SHA (PROVENANCE.md section 14)." >&2; exit 1; }

# ---------------------------------------------------------------- tools --
NENV="${NATIVE_DRC_ENV:-${HERE}/build/native-drc-env}"
bash "${HERE}/scripts/native_drc_env.sh" "${NENV}"
NPY="${NENV}/klt/bin/python"
NBIN="${SCRATCH}/native-bin"
mkdir -p "${NBIN}"
ln -sfn "${NATIVE_KLAYOUT:-${NENV}/bin/klayout}" "${NBIN}/klayout"
nkl_ver="$("${NBIN}/klayout" -b -v 2>/dev/null | awk '{print $2}')"
[[ "${nkl_ver}" == "${NATIVE_KLAYOUT_VERSION}" ]] || {
  echo "error: KLayout for the runset is '${nkl_ver}', expected ${NATIVE_KLAYOUT_VERSION}" >&2; exit 1; }
npy_kl="$("${NPY}" -c 'import klayout; print(klayout.__version__)')"

KLT_REL="${KLT_RELEASE_ENV:-${HERE}/build/klt-0.6.0}"
if [[ ! -x "${KLT_REL}/bin/klt" ]]; then
  need uv
  uv venv -q "${KLT_REL}"
  VIRTUAL_ENV="${KLT_REL}" uv pip install -q "klayout-tools==0.6.0"
fi
[[ "$("${KLT_REL}/bin/klt" --version 2>&1 | head -1)" == "klt 0.6.0" ]] || {
  echo "error: ${KLT_REL} does not hold the tagged klayout-tools 0.6.0" >&2; exit 1; }
echo "== tools: KLayout ${nkl_ver} (runset), klayout module ${npy_kl}, $("${KLT_REL}/bin/klt" --version | head -1) (klt leg)"
echo "== deck:  IHP sg13g2.lvs runset @ sha256:${deck_sha}"

# ------------------------------------------------------------ reference --
echo "== reference: derive the LVS reference (published to layout/lvs/ only if the gate passes) from ${SRC}"
python3 -I "${HERE}/scripts/lvs_reference.py" "${SRC}" \
  "${SCRATCH}/ref/vco-reference.cir" "${SCRATCH}/ref/vco-reference.json"
python3 -I "${HERE}/scripts/lvs_reference.py" "${SRC}" \
  "${SCRATCH}/ref/diag-l1.cir" "${SCRATCH}/ref/diag-l1.json" \
  --swap-inductor=L1

# Independent cross-check of transformation T3: xschem's own LVS-mode
# netlist of design/vco.sch applies each PDK symbol's lvs_format itself.
XCHECK="skipped: xschem not on PATH"
if command -v xschem >/dev/null 2>&1 && [[ -f "${PDK}/libs.tech/xschem/xschemrc" ]]; then
  mkdir -p "${SCRATCH}/ref/xschem"
  if xschem -n -q -r --rcfile "${PDK}/libs.tech/xschem/xschemrc" \
       --tcl 'set lvs_netlist 1' -o "${SCRATCH}/ref/xschem" design/vco.sch \
       > "${SCRATCH}/ref/xschem/xschem.log" 2>&1; then
    # xschem < 3.4.7 ignores `set lvs_netlist 1` and the symbols' lvs_format:
    # it writes the simulation X-cards, which is no cross-check of T3.
    if grep -q '^XQ1 ' "${SCRATCH}/ref/xschem/vco.spice"; then
      XCHECK="skipped: $(xschem --version 2>&1 | head -1) does not apply lvs_format (needs >= 3.4.7)"
    else
      XCHECK="${SCRATCH}/ref/xschem/vco.spice"
    fi
  else
    XCHECK="skipped: xschem LVS netlisting failed (see scratch log)"
  fi
fi

# ----------------------------------------------------------------- runs --
# run <stem> <gds> <reference>: IHP runset, then the .lvsdb read back.
# run_lvs.py exits 0 whether or not the netlists match, so its exit status
# is only checked for a crash; the verdict comes from the database.
run() {
  local stem="$1" gds="$2" ref="$3" d="${SCRATCH}/run-$1"
  rm -rf "${d}"
  PATH="${NBIN}:${PATH}" "${NPY}" "${LVSDIR}/run_lvs.py" --layout="${gds}" \
    --netlist="${ref}" --topcell=vco --run_dir="${d}" > "${SCRATCH}/run-$1.log" 2>&1 || {
    echo "error: run_lvs.py crashed for ${stem}; log: ${SCRATCH}/run-$1.log" >&2; exit 1; }
  # run_lvs.py names its outputs after the stream file's basename.
  local db
  db="${d}/$(basename "${gds}" .gds).lvsdb"
  [[ -f "${db}" ]] || { echo "error: ${stem}: no ${db##*/} written" >&2; exit 1; }
  "${NPY}" -I "${HERE}/scripts/lvsdb_summary.py" "${db}" > "${SCRATCH}/run-$1.json"
  echo "   ${stem}: $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["verdict"])' "${SCRATCH}/run-$1.json")"
}

echo "== ihp runset: record + single-variable controls + negative controls"
run record "${REPO_ROOT}/${GDS}" "${SCRATCH}/ref/vco-reference.cir"
run c1-l1 "${REPO_ROOT}/${GDS}" "${SCRATCH}/ref/diag-l1.cir"
# Negative controls: scratch copies of the stream with ONE connection removed
# each, compared against the reference that matches the intact stream (c1),
# so a `match` here would mean the compare cannot see a broken layout.
"${NPY}" -I "${HERE}/scripts/lvs_break.py" "${GDS}" "${SCRATCH}/ctl/n1-supply.gds" VS_VDD_REF__
"${NPY}" -I "${HERE}/scripts/lvs_break.py" "${GDS}" "${SCRATCH}/ctl/n2-signal.gds" VS_Q1B__
"${NPY}" -I "${HERE}/scripts/lvs_break.py" "${GDS}" "${SCRATCH}/ctl/n3-device.gds" C1__
run n1-supply "${SCRATCH}/ctl/n1-supply.gds" "${SCRATCH}/ref/diag-l1.cir"
run n2-signal "${SCRATCH}/ctl/n2-signal.gds" "${SCRATCH}/ref/diag-l1.cir"
run n3-device "${SCRATCH}/ctl/n3-device.gds" "${SCRATCH}/ref/diag-l1.cir"

# --------------------------------------------------------------- klt leg --
# The repo's pinned klt, on its own documented path: inline extraction with
# the curated sg13g2 deck against the simulation-form reference (T1/T2 only).
echo "== klt leg: klt 0.6.0 lvs (inline curated extraction) + extract census"
python3 -I - "${SRC}" "${SCRATCH}/klt/ref-subckt.spice" <<'PY'
import sys
out, ctl = [], False
for raw in open(sys.argv[1]).read().splitlines():
    s = raw.strip(); lo = s.lower()
    if lo.startswith(".control"): ctl = True
    if ctl:
        ctl = not lo.startswith(".endc"); continue
    if not s or s[0] in "*." or s.split()[0] in ("VSUP", "VCT"): continue
    out.append(s)
open(sys.argv[2], "w").write(".SUBCKT vco 0 VDD OUTP OUTN VCTRL TAIL NBIAS TE RE\n"
                             + "\n".join(out) + "\n.ENDS vco\n")
PY
cat > "${SCRATCH}/klt/request.json" <<JSON
{"layout": {"file": "${REPO_ROOT}/${GDS}", "deck": "sg13g2", "top": "vco"},
 "reference": {"netlist": "ref-subckt.spice", "form": "subckt-call", "deck": "sg13g2", "top": "vco"}}
JSON
klt_rc=0
"${KLT_REL}/bin/klt" lvs "${SCRATCH}/klt/request.json" --format json \
  > "${SCRATCH}/klt/lvs.json" 2> "${SCRATCH}/klt/lvs.err" || klt_rc=$?
xrc=0
"${KLT_REL}/bin/klt" extract "${GDS}" --deck sg13g2 --top vco --format json \
  -o "${SCRATCH}/klt/extract.spice" > "${SCRATCH}/klt/extract.json" 2> "${SCRATCH}/klt/extract.err" || xrc=$?
echo "   klt lvs exit ${klt_rc}; klt extract exit ${xrc}"

# The newest tagged release, so the record says whether the gap still holds
# beyond the CI pin (PROVENANCE.md section 14.5).  Same request, plus the one
# other documented klt route: a pre-extracted layout netlist (the runset's
# own extraction of this stream) against the derived reference.  Throwaway
# venv (KLT_LATEST_ENV), never the host's klt.
KLT_LATEST_VER="0.7.0"
KLT_LAT="${KLT_LATEST_ENV:-${HERE}/build/klt-${KLT_LATEST_VER}}"
if [[ ! -x "${KLT_LAT}/bin/klt" ]]; then
  need uv
  uv venv -q "${KLT_LAT}"
  VIRTUAL_ENV="${KLT_LAT}" uv pip install -q "klayout-tools==${KLT_LATEST_VER}"
fi
[[ "$("${KLT_LAT}/bin/klt" --version 2>&1 | head -1)" == "klt ${KLT_LATEST_VER}"* ]] || {
  echo "error: ${KLT_LAT} does not hold the tagged klayout-tools ${KLT_LATEST_VER}" >&2; exit 1; }
LAT="${SCRATCH}/klt-latest"
mkdir -p "${LAT}"
cp "${SCRATCH}/klt/ref-subckt.spice" "${LAT}/ref-subckt.spice"
cp "${SCRATCH}/klt/request.json" "${LAT}/request.json"
cp "${SCRATCH}/run-record/vco_extracted.cir" "${LAT}/runset-extracted.cir"
cp "${SCRATCH}/ref/vco-reference.cir" "${LAT}/reference.cir"
cat > "${LAT}/request-netlist.json" <<JSON
{"layout": {"netlist": "runset-extracted.cir", "top": "vco"},
 "reference": {"netlist": "reference.cir", "top": "vco"}}
JSON
lat_rc=0
"${KLT_LAT}/bin/klt" lvs "${LAT}/request.json" --format json \
  > "${LAT}/lvs.json" 2> "${LAT}/lvs.err" || lat_rc=$?
latn_rc=0
"${KLT_LAT}/bin/klt" lvs "${LAT}/request-netlist.json" --format json \
  > "${LAT}/lvs-netlist.json" 2> "${LAT}/lvs-netlist.err" || latn_rc=$?
latx_rc=0
"${KLT_LAT}/bin/klt" extract "${GDS}" --deck sg13g2 --top vco --format json \
  -o "${LAT}/extract.spice" > "${LAT}/extract.json" 2> "${LAT}/extract.err" || latx_rc=$?
echo "   klt ${KLT_LATEST_VER}: lvs exit ${lat_rc}; lvs (pre-extracted) exit ${latn_rc}; extract exit ${latx_rc}"
export LAT_RC="${lat_rc}" LATN_RC="${latn_rc}" LATX_RC="${latx_rc}" KLT_LATEST_VER

# ------------------------------------------------------- gate + record --
python3 -I - "${SCRATCH}" "${OUT}" "${REPO_ROOT}" "${XCHECK}" "${klt_rc}" "${xrc}" \
  "${deck_sha}" "${nkl_ver}" "${npy_kl}" <<'PY'
import hashlib, json, os, re, sys
scratch, out, root, xcheck, klt_rc, xrc, deck_sha, kl_ver, py_kl = sys.argv[1:]
klt_rc, xrc = int(klt_rc), int(xrc)
fail = []

def S(stem):
    return json.load(open(os.path.join(scratch, "run-%s.json" % stem)))

def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()

def cmp(stem):
    return S(stem)["circuits"][0]

EXPECT_CENSUS = {"cap_cmim": 1, "inductor": 2, "npn13g2v": 4, "ptap1": 1,
                 "rppd": 3, "sg13_hv_svaricap": 32}

def census(c, side):
    return {k.lower(): v for k, v in c["devices"][side].items()}

# -- the record: mismatch, full device census on both sides -------------
rec = S("record"); rc = rec["circuits"][0]
if rec["verdict"] != "mismatch":
    fail.append("record compare is %r, not the recorded 'mismatch' -- "
                "update PROVENANCE.md section 14 before the record" % rec["verdict"])
for side in ("layout", "reference"):
    if census(rc, side) != EXPECT_CENSUS:
        fail.append("%s device census %r != %r" % (side, census(rc, side), EXPECT_CENSUS))

# -- C1: L1 swapped -> match (L1's terminal order is the ONLY difference)
c1 = S("c1-l1")
c1_ok = c1["verdict"] == "match" and cmp("c1-l1")["device_pairs"]["not_matched"] == []
if not c1_ok:
    fail.append("control C1 (L1 order) is %r, not 'match'" % c1["verdict"])
# -- the record must differ from C1 in exactly the one L1 device pair ----
nm = rc["device_pairs"]["not_matched"]
rec_ok = (len(nm) == 1 and nm[0]["layout"] and nm[0]["layout"]["class"] == "inductor"
          and nm[0]["reference"] and nm[0]["reference"]["name"] == "L1")
if rec_ok:
    lt = list(nm[0]["layout"]["terminals"].values())[:2]
    rt = list(nm[0]["reference"]["terminals"].values())[:2]
    rec_ok = (rt == ["VDD", "OUTP"] and "OUTP" in lt[0] and "VDD" in lt[1])
if not rec_ok:
    fail.append("the record no longer differs only in the L1 terminal-order "
                "pair (bn must be gone): %s" % json.dumps(nm)[:600])

# -- negative controls: each must be rejected -----------------------------
neg = []
for stem, what in (("n1-supply", "VS_VDD_REF via ladder removed: RREF's VDD end "
                    "detached from the VDD strap (supply connection)"),
                   ("n2-signal", "VS_Q1B via ladder removed: Q1's base detached "
                    "from OUTN (cross-coupling signal connection)"),
                   ("n3-device", "C1 MIM instance removed (a missing device)")):
    s = S(stem); c = s["circuits"][0]
    ok = s["verdict"] == "mismatch"
    if not ok:
        fail.append("negative control %s compared %r against the matching "
                    "reference -- the compare cannot see this break" % (stem, s["verdict"]))
    neg.append({"control": stem, "change": what, "reference": "C1 diagnostic "
                "(matches the intact stream)", "verdict": s["verdict"],
                "rejected": ok,
                "nets_not_matched": len(c["nets"]["not_matched"]),
                "device_pairs_not_matched": len(c["device_pairs"]["not_matched"]),
                "layout_census": census(c, "layout")})

# -- T3 cross-check against xschem's own LVS netlist ----------------------
_SI = {"t": 1e12, "g": 1e9, "meg": 1e6, "k": 1e3, "m": 1e-3, "u": 1e-6,
       "n": 1e-9, "p": 1e-12, "f": 1e-15}
def num(t):
    m = re.fullmatch(r"([-+]?[0-9.]+(?:e[-+]?\d+)?)(meg|[tgkmunpf])?", t.lower())
    return float(m.group(1)) * _SI.get(m.group(2) or "", 1.0) if m else t
def cards(path, mapped):
    d = {}
    for l in open(path):
        t = l.split()
        if not t or t[0][0] not in "QLC" or t[0].startswith("*"):
            continue
        model_i = next(i for i, x in enumerate(t) if not "=" in x and i > 1
                       and x in ("npn13G2v", "inductor", "cap_cmim", "sg13_hv_svaricap"))
        nodes = t[1:model_i]
        if mapped:  # our T5a: substrate `0` -> `sub`; compare as the source wrote it
            nodes = ["0" if n == "sub" else n for n in nodes]
        prm = {k.lower(): num(v) for k, v in (x.split("=", 1) for x in t[model_i + 1:])}
        d[t[0]] = (nodes, t[model_i], prm)
    return d
if os.path.isfile(xcheck):
    ours, theirs = cards(os.path.join(scratch, "ref", "vco-reference.cir"), True), cards(xcheck, False)
    diffs = []
    for k in sorted(set(ours) | set(theirs)):
        a, b = ours.get(k), theirs.get(k)
        if a is None or b is None or a[0] != b[0] or a[1] != b[1] or any(
                abs(a[2].get(p, 0) - b[2].get(p, 0)) > 1e-9 * max(1, abs(b[2].get(p, 0)))
                for p in set(a[2]) | set(b[2])):
            diffs.append(k)
    xc = {"status": "agree" if not diffs else "disagree", "devices_compared":
          len(theirs), "differences": diffs,
          "scope": "every Q/L/C card (T3 device-form mapping): nodes, model, "
                   "parameters; xschem keeps ideal resistors and writes "
                   "substrate as 0, so R cards and T4/T5 are outside it"}
    if diffs:
        fail.append("T3 cross-check: our reference disagrees with xschem's LVS "
                    "netlist on %s" % diffs)
else:
    xc = {"status": xcheck}
    # Carry the last real cross-check forward, labelled as NOT re-run.
    try:
        prev = json.load(open(os.path.join(out, "vco-lvs-record.json")))["reference_crosscheck_xschem"]
        if prev.get("status") == "agree":
            xc["last_rerun_agreement"] = prev
            xc["note"] = ("not re-run in this regeneration; the carried block is the "
                          "agreement recorded against the pre-#79 netlist (xschem "
                          "3.4.7). The #79 change only re-points the 4th terminal "
                          "of the 32 varactor cards (OUTP/OUTN -> 0); re-run with "
                          "xschem >= 3.4.7 to refresh")
        elif "last_rerun_agreement" in prev:
            xc["last_rerun_agreement"] = prev["last_rerun_agreement"]
            xc["note"] = prev.get("note")
    except Exception:
        pass

# -- klt leg -------------------------------------------------------------
def scrub(o):
    return json.loads(json.dumps(o).replace(root + "/", "").replace(
        os.path.join(scratch, "klt") + "/", "<scratch>/"))
# klt writes its error envelope to stderr and a report to stdout.
klt_lvs = None
for f in ("lvs.json", "lvs.err"):
    try:
        klt_lvs = json.load(open(os.path.join(scratch, "klt", f)))
        break
    except Exception:
        continue
klt_lvs = klt_lvs or {"unparsable": "neither stdout nor stderr held JSON"}
kmsg = (klt_lvs.get("error") or {}).get("message", "")
klt_refused = klt_rc == 1 and "'inductor' is not a known device" in kmsg
if not klt_refused:
    fail.append("klt 0.6.0 lvs no longer refuses this reference (exit %d) -- "
                "the klt gap may be closed: re-evaluate, update section 14" % klt_rc)
kx = json.load(open(os.path.join(scratch, "klt", "extract.json")))
if xrc != 0 or kx.get("device_counts") != {"cap_cmim": 1}:
    fail.append("klt 0.6.0 extract census changed: exit %d, %r -- re-evaluate "
                "the klt leg" % (xrc, kx.get("device_counts")))

# -- klt leg, newest release (section 14.5) -------------------------------
lat_dir = os.path.join(scratch, "klt-latest")
lat_ver = os.environ["KLT_LATEST_VER"]
lat_rc, latn_rc, latx_rc = (int(os.environ[k]) for k in ("LAT_RC", "LATN_RC", "LATX_RC"))
def scrub_lat(o):
    return json.loads(json.dumps(o).replace(lat_dir + "/", "<scratch>/").replace(
        root + "/", ""))
def envelope(stem):
    for f in (stem + ".json", stem + ".err"):
        try:
            return json.load(open(os.path.join(lat_dir, f)))
        except Exception:
            continue
    return {"unparsable": "neither stdout nor stderr held JSON"}
lat_lvs, lat_net = envelope("lvs"), envelope("lvs-netlist")
lmsg = (lat_lvs.get("error") or {}).get("message", "")
nmsg = (lat_net.get("error") or {}).get("message", "")
if not (lat_rc == 1 and "'inductor' is not a known device" in lmsg):
    fail.append("klt %s lvs no longer refuses this reference (exit %d) -- the "
                "klt gap may be closed: re-evaluate, update section 14.5" % (lat_ver, lat_rc))
if not (latn_rc == 1 and "could not parse layout netlist" in nmsg):
    fail.append("klt %s lvs now reads the runset's extracted netlist (exit %d) -- "
                "re-evaluate the pre-extracted route, update section 14.5" % (lat_ver, latn_rc))
lkx = json.load(open(os.path.join(lat_dir, "extract.json")))
if latx_rc != 0 or lkx.get("device_counts") != {"cap_cmim": 1}:
    fail.append("klt %s extract census changed: exit %d, %r -- re-evaluate "
                "the klt leg" % (lat_ver, latx_rc, lkx.get("device_counts")))

if fail:
    print("\n== LVS RECORD DRIFTED -- layout/lvs/ record files left as they were")
    for f in fail:
        print("  [FAIL] %s" % f)
    sys.exit(1)

def supply(stem):
    c = cmp(stem); want = {"VDD", "0", "SUB"}
    got = [p for p in c["nets"]["pairs"] if (p["reference"] or "").upper() in want]
    bad = [n for n in c["nets"]["not_matched"]
           if (n["reference"] or "").upper() in want]
    return {"paired": got, "not_paired": bad}

if supply("c1-l1")["not_paired"] or len(supply("c1-l1")["paired"]) != 3:
    print("[FAIL] C1 does not pair VDD/0/substrate 1:1"); sys.exit(1)

# -- write the committed record ------------------------------------------
import shutil
for f in ("vco-reference.cir", "vco-reference.json"):
    shutil.copyfile(os.path.join(scratch, "ref", f), os.path.join(out, f))
ext_src = os.path.join(scratch, "run-record", "vco_extracted.cir")
ext = [l for l in open(ext_src).read().splitlines(True)
       if not l.startswith("* Extracted by KLayout with SG13G2 LVS runset on")]
open(os.path.join(out, "vco-extracted.cir"), "w").write(
    "* Extracted from layout/vco.gds by IHP's sg13g2.lvs runset (layout/lvs.sh);\n"
    "* the runset's date-stamp comment line is removed so reruns are byte-stable.\n"
    + "".join(ext))

gds_sha = sha(os.path.join(root, "layout/vco.gds"))
ref_sha = sha(os.path.join(out, "vco-reference.cir"))
ihp = {"schema_version": 1,
       "engine": "KLayout %s LVS (NetlistComparer), IHP-Open-PDK sg13g2.lvs runset" % kl_ver,
       "deck": {"pdk_relative_path": "libs.tech/klayout/tech/lvs/sg13g2.lvs",
                "content_hash": "sha256:" + deck_sha,
                "hash_scope": "sha256 over '<sha256>  <path>' lines of sg13g2.lvs, "
                              "run_lvs.py and rule_decks/*.lvs, sorted"},
       "input": {"file": "layout/vco.gds", "content_hash": "sha256:" + gds_sha},
       "reference": {"file": "layout/lvs/vco-reference.cir",
                     "content_hash": "sha256:" + ref_sha,
                     "derived_from": json.load(open(os.path.join(
                         out, "vco-reference.json")))["source"]},
       "status": rec["verdict"],
       "compare": rc}
json.dump(ihp, open(os.path.join(out, "vco-lvs-ihp.json"), "w"), indent=2)
open(os.path.join(out, "vco-lvs-ihp.json"), "a").write("\n")

record = {
    "schema_version": 1,
    "verdict_of_record": {
        "status": "mismatch",
        "report": "layout/lvs/vco-lvs-ihp.json",
        "device_census": {"layout": census(rc, "layout"),
                          "reference": census(rc, "reference"),
                          "devices_in_design": 42,
                          "extra": "ptap1 = the guard-ring substrate tie (T5b)"},
        "explained_differences": [
            {"id": "L1-terminal-order", "devices": 1, "kind": "extractor artefact",
             "detail": "IHP's GeneralNTerminalExtractor sorts inductor ports by x "
                       "position; L1 is placed mirrored (m90), so its LA (on VDD) "
                       "sorts second, while the inductor class declares its two "
                       "winding terminals non-equivalent. The LA/LB labels in the "
                       "stream put LA on VDD for both spirals, as the schematic "
                       "says. Isolated by control C1.",
             "resolution": "upstream runset fix or a reviewed accommodation: "
                           "issue #80"}],
        "supply_pairing": {
            "record": supply("record"), "control_C1": supply("c1-l1"),
            "reading": "in the record compare the supply nets do not pair "
                       "cleanly because the L1 terminal-order artefact "
                       "perturbs VDD/OUTP; with it isolated (C1), VDD, 0 and the "
                       "substrate each pair 1:1 with the reference"},
        "power_connectivity": {
            "status": "not_produced",
            "why": "klt lvs's power_connectivity block exists only in a klt lvs "
                   "report, and klt 0.6.0 cannot produce one for this design "
                   "(klt_leg below). Supply pairing in the device-aware compare "
                   "is reported per net in vco-lvs-ihp.json -> compare.nets."}},
    "tools": {"runset_engine": {"klayout": kl_ver, "klayout_python_module": py_kl,
                                "source": "layout/scripts/native_drc_env.sh "
                                          "(KLayout's own 0.30.12 .deb, extracted)"},
              "runset": {"path": "$IHP_PDK_ROOT/libs.tech/klayout/tech/lvs/run_lvs.py",
                         "content_hash": "sha256:" + deck_sha},
              "klt_leg": "klayout-tools==0.6.0 (tagged wheel, the CI pin)"},
    "inputs": {"layout": {"file": "layout/vco.gds", "content_hash": "sha256:" + gds_sha},
               "schematic_netlist": json.load(open(os.path.join(
                   out, "vco-reference.json")))["source"],
               "reference": {"file": "layout/lvs/vco-reference.cir",
                             "content_hash": "sha256:" + ref_sha}},
    "invocation": ["python3", "$IHP_PDK_ROOT/libs.tech/klayout/tech/lvs/run_lvs.py",
                   "--layout=layout/vco.gds", "--netlist=layout/lvs/vco-reference.cir",
                   "--topcell=vco", "--run_dir=<scratch>"],
    "invocation_notes": "run_lvs.py defaults: flat mode, simplify on, strict "
                        "top-port mode (flag_missing_ports); run_lvs.py exits 0 "
                        "on a mismatch, so the verdict is read from the .lvsdb",
    "reference_crosscheck_xschem": xc,
    "single_variable_controls": [
        {"control": "C1", "reference_change": "L1 winding terminals swapped",
         "verdict": c1["verdict"],
         "device_pairs_matched": cmp("c1-l1")["device_pairs"]["matched"],
         "nets_matched": cmp("c1-l1")["nets"]["matched"],
         "pins_matched": cmp("c1-l1")["pins"]["matched"]}],
    "control_scope": "C1 reference is a scratch diagnostic produced by "
                     "lvs_reference.py's --swap-inductor switch; it is never "
                     "committed and is not a reference of record. It "
                     "establishes that L1's terminal order is the ONLY "
                     "difference, not that the layout matches.",
    "negative_controls": neg,
    "klt_leg": {
        "lvs": {"request": {"layout": {"file": "layout/vco.gds", "deck": "sg13g2", "top": "vco"},
                            "reference": {"netlist": "<design/vco.spice minus T1, wrapped per T2>",
                                          "form": "subckt-call", "deck": "sg13g2", "top": "vco"}},
                "exit": klt_rc, "response": scrub(klt_lvs)},
        "extract": {"exit": xrc, "device_counts": kx.get("device_counts"),
                    "net_count": kx.get("net_count"),
                    "devices_in_design": 42},
        "reading": "klt 0.6.0 refuses the reference (no inductor / 4-terminal "
                   "varactor / HBT device class for sg13g2) and its curated "
                   "extraction recognizes 1 of 42 devices, so no klt lvs report "
                   "of this block can exist at this pin (PROVENANCE.md section "
                   "14; 2AMLogic/klayout-tools#2849)"},
    "klt_leg_latest_release": {
        "klt": "klayout-tools==%s (tagged wheel, throwaway venv; not the CI pin)" % lat_ver,
        "lvs_inline_extraction": {"request": "same as klt_leg.lvs.request",
                                  "exit": lat_rc, "response": scrub_lat(lat_lvs)},
        "lvs_pre_extracted": {
            "request": {"layout": {"netlist": "<the runset's own extraction of "
                                              "layout/vco.gds (the record run)>",
                                   "top": "vco"},
                        "reference": {"netlist": "layout/lvs/vco-reference.cir",
                                      "top": "vco"}},
            "exit": latn_rc, "response": scrub_lat(lat_net)},
        "extract": {"exit": latx_rc, "device_counts": lkx.get("device_counts"),
                    "net_count": lkx.get("net_count"), "devices_in_design": 42},
        "reading": "the newest release behaves as the pin does: it refuses the "
                   "reference, recognizes 1 of 42 devices on inline extraction, "
                   "and cannot read the runset's device-aware extraction as a "
                   "pre-extracted layout netlist -- the gap tracked by "
                   "2AMLogic/klayout-tools#2849 is open in %s too "
                   "(PROVENANCE.md section 14.5)" % lat_ver},
    "limits": [
        "the verdict is IHP's runset's; klt lvs could not run it, so no "
        "klt-native LVS envelope (and no klt power_connectivity block) exists",
        "one engine only: no second, independent extractor recognizes this "
        "block's HBT/varactor/inductor devices",
        "the reference is DERIVED (T1..T6); T4 (rppd for ideal R) and T5 "
        "(substrate net + guard-ring tie) are the layout phase's own physical "
        "choices restated, so their parameters are checked against the "
        "generator's intent, not against the schematic",
        "a topological + parameter compare; no parasitic, matching or "
        "geometric check"]}
json.dump(record, open(os.path.join(out, "vco-lvs-record.json"), "w"), indent=2)
open(os.path.join(out, "vco-lvs-record.json"), "a").write("\n")
print("\n== LVS record written: status mismatch (L1 terminal order only; varactor bn resolved by #79) -- "
      "control C1 confirms it is the only difference; negative controls "
      "rejected; klt 0.6.0 refuses (recorded)")
PY
