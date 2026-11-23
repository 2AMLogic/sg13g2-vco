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
# READ PROVENANCE.md SECTIONS 14 AND 14.6 FIRST.  The device-aware compare
# runs IHP's own KLayout LVS runset (the only extractor available that
# recognizes all 42 of this block's devices).
#
# THE RUNSET AS SHIPPED gives `mismatch`, with exactly one difference,
# isolated by single-variable control C1: spiral L1's two winding terminals.
# IHP's extractor orders inductor terminals by x position, and L1 is the
# mirrored instance; its LA/LB labels show the layout is wired as the
# schematic says (issue #80).  (The varactors' `bn` pin was a second
# difference until #79 corrected the schematic.)
#
# THE COMPARE OF RECORD (issue #80) is the same runset, unmodified and
# hash-pinned, with ONE reviewed, removable step added in front of its own
# `compare`: scripts/lvs_label_order.rb puts every extracted inductor's two
# winding terminals in the order of the LA/LB labels the runset itself used
# to find those ports (LA = terminal 1, the PDK's own convention), applied
# identically to every inductor and keyed on the labels at each device's
# terminals, never on instance names.  The reference is NOT edited.  Its
# verdict is `match` on the cross-reference (every device, net and pin
# paired); the runset's strict top-port check still logs three port-NAME
# findings ('LA,VDD' vs 'VDD', ...), recorded as they are (section 14.6).
# Controls: R0 (the same wrapper with the step computing but changing
# nothing reproduces the shipped runset's compare exactly), and negative
# controls through the step -- L1 genuinely wired the other way round, LA
# labels on the wrong net, and N1-N3 -- each of which must be rejected.
# Drop the step once the pinned runset orders inductor terminals by label
# (PROVENANCE.md section 14.6, "Removal").
#
# `klt lvs` (tagged 0.8.0, the version the committed records reproduce
# under; see layout/PROVENANCE.md
# section 14.5 for the 0.6.0 and 0.7.0 records) cannot run this compare at all; both refusals are recorded
# (2AMLogic/klayout-tools#2849).
#
# WHAT IT WRITES (all committed, repo-root-relative inside, no host paths):
#   layout/lvs/vco-reference.cir    LVS reference DERIVED from design/vco.spice
#   layout/lvs/vco-reference.json   per-line trace of that derivation (T1..T6)
#   layout/lvs/vco-extracted.cir    IHP runset's device-aware extraction of
#                                   layout/vco.gds (its date stamp removed)
#   layout/lvs/vco-extracted-label-ordered.cir
#                                   the same extraction after the
#                                   label-order step (what was compared)
#   layout/lvs/vco-lvs-ihp.json     the compare of record (after the step),
#                                   plus the runset-as-shipped compare, both
#                                   read back from KLayout's own .lvsdb
#   layout/lvs/vco-lvs-record.json  tools, deck hash, inputs, invocation,
#                                   the controls and their outcomes, the klt
#                                   attempt, and the limits
#
# TOOLS.  IHP's runset needs a standalone KLayout >= 0.30.2; the pinned
# environment layout/scripts/native_drc_env.sh provisions for the native DRC
# (KLayout 0.30.12, extracted into gitignored scratch) is reused, together
# with the `klayout` Python module of its venv.  The klt leg uses the tagged
# klayout-tools==0.8.0 wheel the committed records reproduce under (the
# claims pin, .github/klt-version, moved to 0.9.2 in #416; these records
# regenerate under it via #266), in a throwaway venv
# (KLT_RELEASE_ENV, default layout/build/klt-0.8.0) -- never the host's.

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
rm -rf "${SCRATCH:?}"/run-* "${SCRATCH:?}"/ref "${SCRATCH:?}"/ctl "${SCRATCH:?}"/klt \
  "${SCRATCH:?}"/label-order
mkdir -p "${SCRATCH}/ref" "${SCRATCH}/ctl" "${SCRATCH}/klt" "${SCRATCH}/label-order/bin"
cd "${REPO_ROOT}"   # every path recorded is repo-root-relative

GDS="layout/vco.gds"
SRC="design/vco.spice"

# ------------------------------------------------------------------ pdk --
# shellcheck source=layout/scripts/resolve_pdk.sh
source "${HERE}/scripts/resolve_pdk.sh"
resolve_ihp_pdk
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

KLT_REL="${KLT_RELEASE_ENV:-${HERE}/build/klt-0.8.0}"
if [[ ! -x "${KLT_REL}/bin/klt" ]]; then
  need uv
  uv venv -q "${KLT_REL}"
  VIRTUAL_ENV="${KLT_REL}" uv pip install -q "klayout-tools==0.8.0"
fi
[[ "$("${KLT_REL}/bin/klt" --version 2>&1 | head -1)" == "klt 0.8.0" ]] || {
  echo "error: ${KLT_REL} does not hold the tagged klayout-tools 0.8.0" >&2; exit 1; }
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
  PATH="${RUN_BIN:-${NBIN}}:${PATH}" "${NPY}" "${LVSDIR}/run_lvs.py" --layout="${gds}" \
    --netlist="${ref}" --topcell=vco --run_dir="${d}" > "${SCRATCH}/run-$1.log" 2>&1 || {
    echo "error: run_lvs.py crashed for ${stem}; log: ${SCRATCH}/run-$1.log" >&2; exit 1; }
  # run_lvs.py names its outputs after the stream file's basename.
  local db
  db="${d}/$(basename "${gds}" .gds).lvsdb"
  [[ -f "${db}" ]] || { echo "error: ${stem}: no ${db##*/} written" >&2; exit 1; }
  "${NPY}" -I "${HERE}/scripts/lvsdb_summary.py" "${db}" > "${SCRATCH}/run-$1.json"
  echo "   ${stem}: $(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["verdict"])' "${SCRATCH}/run-$1.json")"
}

# ---------------------------------------- label-order step (issue #80) --
# The compare of record runs the SAME run_lvs.py, with the SAME switches, on
# the SAME hash-pinned runset; the only difference is one Ruby fragment,
# scripts/lvs_label_order.rb, evaluated ahead of the runset so that it can
# wrap the runset's own `compare` (see its header).  Mechanism: a generated
# wrapper deck `# %include`s the fragment and then the unmodified
# sg13g2.lvs, and a `klayout` shim first on run_lvs.py's PATH swaps exactly
# the one `-r <runset>/sg13g2.lvs` argument for that wrapper, adding the
# step's two -rd switches; every switch run_lvs.py computed passes through
# untouched.  The shim refuses any other -r, and run_lo fails unless the
# step wrote its report, so the step can neither be skipped silently nor
# be applied to something else.
LO="${SCRATCH}/label-order"
RUNSET_LVS="$(realpath -- "${LVSDIR}/sg13g2.lvs")"
printf '%s\n' "# generated by layout/lvs.sh (issue #80): the label-order step, then" \
  "# IHP's runset, unmodified (its hash is checked by lvs.sh before this runs)." \
  "# %include ${HERE}/scripts/lvs_label_order.rb" \
  "# %include ${RUNSET_LVS}" > "${LO}/wrapper.lvs"
cat > "${LO}/bin/klayout" <<'SHIM'
#!/usr/bin/env bash
# klayout shim (generated by layout/lvs.sh, issue #80) -- see lvs.sh.
set -euo pipefail
args=() swapped=0
while (($#)); do
  if [[ "$1" == "-r" ]]; then
    [[ $# -ge 2 && "$(realpath -- "$2")" == "${LO_RUNSET}" ]] || {
      echo "label-order shim: refusing -r ${2:-<none>} (only ${LO_RUNSET})" >&2; exit 97; }
    args+=(-r "${LO_WRAPPER}" -rd "label_order_report=${LO_REPORT}"
           -rd "label_order_mode=${LO_MODE}")
    swapped=$((swapped + 1)); shift 2; continue
  fi
  args+=("$1"); shift
done
[[ ${swapped} -le 1 ]] || { echo "label-order shim: more than one -r" >&2; exit 97; }
exec "${LO_KLAYOUT}" "${args[@]}"
SHIM
chmod +x "${LO}/bin/klayout"

# run_lo <stem> <gds> <reference> <apply|report>: `run`, through the step.
run_lo() {
  local rep="${SCRATCH}/run-$1.label-order.json"
  rm -f "${rep}"
  RUN_BIN="${LO}/bin" LO_RUNSET="${RUNSET_LVS}" LO_WRAPPER="${LO}/wrapper.lvs" \
    LO_KLAYOUT="${NBIN}/klayout" LO_REPORT="${rep}" LO_MODE="$4" run "$1" "$2" "$3"
  [[ -f "${rep}" ]] || {
    echo "error: $1: the label-order step did not run (no ${rep##*/})" >&2; exit 1; }
}

echo "== ihp runset as shipped: record + single-variable control + negative controls"
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

echo "== ihp runset + label-order step: fidelity control, record, negative controls"
# R0: the step computes but changes nothing -> must reproduce `record` exactly.
run_lo lo-r0 "${REPO_ROOT}/${GDS}" "${SCRATCH}/ref/vco-reference.cir" report
# The compare of record: against the reference of record, never a swapped one.
run_lo lo-record "${REPO_ROOT}/${GDS}" "${SCRATCH}/ref/vco-reference.cir" apply
# N1-N3 again, now through the step and against the reference of record.
for n in n1-supply n2-signal n3-device; do
  run_lo "lo-${n}" "${SCRATCH}/ctl/${n}.gds" "${SCRATCH}/ref/vco-reference.cir" apply
done
# Spiral controls (scripts/lvs_inductor_ctl.py), each must be rejected:
#   (a)  L1 GENUINELY wired the other way round: re-placed mirrored about its
#        own axis, so its LA port lands on the OUTP wire, LB on VDD.
#   (b1) L2's LA/LB texts swapped: LA on the wrong net (OUTN).  L2 is the
#        unmirrored spiral the step otherwise leaves alone -- the step must
#        follow its labels, not its instance.
#   (b2) L1's LA/LB texts swapped: LA on the wrong net (OUTP).
#   (b3) L1's LA text moved onto its LB port: both labels on OUTP.
"${NPY}" -I "${HERE}/scripts/lvs_inductor_ctl.py" "${GDS}" "${SCRATCH}/ctl/a-l1-flipped.gds" flip L1__vco_ind
"${NPY}" -I "${HERE}/scripts/lvs_inductor_ctl.py" "${GDS}" "${SCRATCH}/ctl/b1-l2-labels-swapped.gds" swap-labels L2__vco_ind
"${NPY}" -I "${HERE}/scripts/lvs_inductor_ctl.py" "${GDS}" "${SCRATCH}/ctl/b2-l1-labels-swapped.gds" swap-labels L1__vco_ind
"${NPY}" -I "${HERE}/scripts/lvs_inductor_ctl.py" "${GDS}" "${SCRATCH}/ctl/b3-l1-la-moved.gds" move-la L1__vco_ind
for c in a-l1-flipped b1-l2-labels-swapped b2-l1-labels-swapped b3-l1-la-moved; do
  run_lo "lo-${c}" "${SCRATCH}/ctl/${c}.gds" "${SCRATCH}/ref/vco-reference.cir" apply
done
# Why the accommodation may not be a reference-side swap: the runset as
# shipped, against the C1 (L1-swapped) reference, cannot see control (a).
run a-plain-vs-c1 "${SCRATCH}/ctl/a-l1-flipped.gds" "${SCRATCH}/ref/diag-l1.cir"

# --------------------------------------------------------------- klt leg --
# The repo's pinned klt, on its own documented path: inline extraction with
# the curated sg13g2 deck against the simulation-form reference (T1/T2 only).
echo "== klt leg: klt 0.8.0 lvs (inline curated extraction) + extract census"
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
KLT_LATEST_VER="0.8.0"
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
python3 -I "${HERE}/scripts/lvs_record.py" "${SCRATCH}" "${OUT}" "${REPO_ROOT}" \
  "${XCHECK}" "${klt_rc}" "${xrc}" "${deck_sha}" "${nkl_ver}" "${npy_kl}"
