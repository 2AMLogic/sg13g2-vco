# Source me:  source "${EXPERIMENT_DIR}/osc_bench.sh"
#
# EXPERIMENT-LOCAL shared driver for sim/oscillator-core/. Not an entry point:
# it has no shebang and is never executed. The entry points are the no-argument
# run_*.sh scripts next to it (sim/README.md's directory contract):
#
#   run_pvt_sweep.sh     the graded row-10/11 PVT grid + the row-6 margin pass
#   run_pilot_grid.sh    a DECLARED SUBSET of that grid; grades no spec row
#   run_method_check.sh  known-answer check of the extractors (does NOT source
#                        this file -- it needs no PDK and must stay that way)
#
# WHY THIS FILE EXISTS AND sim/lib.sh DOES NOT ABSORB IT
# run_pvt_sweep.sh and run_pilot_grid.sh differ ONLY in which corners, control
# voltages and timestep ceilings they declare -- the deck generation, the
# per-point ngspice invocation, the extraction and the record writing are
# identical. That is deliberate: the pilot's numbers and the graded grid's
# come out of the same code path, so the pilot is a real rehearsal of the
# sweep rather than a lookalike. sim/lib.sh is the repo-wide scaffolding shared by all four
# experiments and deliberately knows nothing about oscillators or about this
# netlist; the genuinely reusable extractors (osc_metrics, osc_settle) were
# added THERE, and only the parts that are specific to design/vco.sch live
# here. Issues #12/#14/#16/#22/#25 are why that boundary is drawn explicitly
# rather than by habit.
#
# Bash-3.2 clean, for the same reason sim/lib.sh is: macOS still ships bash
# 3.2 as /bin/bash and spec/review-bar.md item 1 forbids a cold start that
# silently needs a newer one.
#
# shellcheck shell=bash

# --------------------------------------------------------------------------
# Bench constants. These are METHOD, so they are declared once, here, and
# every record states them -- a frequency without its method is not a result
# (CLAUDE.md).
# --------------------------------------------------------------------------

# Transient. See testbench/tb_vco_core_tran.spice.tmpl's header for the
# justification of each value; the record repeats it so a reader never has to
# open the template to know what was run.
#
# THE WINDOW IS SET FROM A MEASURED SETTLING TIME, NOT FROM A GUESS.
# design/vco.spice's own comments propose 20 ns / a 10 ns discard on the
# reasoning that startup "completes inside the first nanosecond". That
# reasoning is now MEASURED rather than asserted: a 2 ns exploratory transient
# at the nominal corner put the 90 %-envelope settling time at 0.883 ns, the
# window below was sized from it, and the pilot run then measured 0.487 ..
# 1.256 ns across its corners (record 20260926-010627-e391693, the
# t_settle_s column). The settings are therefore
#   * discard 0 .. 2.5 ns  -- 2.0x the slowest settling time observed so far,
#     so the recorded frequency and amplitude are of the settled oscillation.
#     A corner that settles slower still is NOT hidden by this: t_settle_s is
#     recorded per point and lands at nan when the envelope never reaches
#     90 % of its final amplitude and stays there.
#   * measure 2.5 .. 5.0 ns -- 10..13 cycles at the measured 4.6-5.4 GHz,
#     which put the interpolated quantization floor at dt_max*f/cycles =
#     0.082..0.092 % over the pilot (the no-interpolation floor would be
#     1/cycles = 7.7..10 %; both are recorded with every number, see
#     osc_quant_floor_pct).
# A 20 ns transient would buy a 0.02 % floor instead of a 0.08 % one and cost
# 4x the CPU time. Nothing this bench grades needs 0.02 %: the tightest
# comparison is row 2's 1.15 ratio, against which 0.08 % on each endpoint is
# four decimal places below the bound.
OSC_TSTEP="1p"        # requested print step; ngspice's own stepping dominates
OSC_TSTOP="5n"        # ~27 periods at the measured 5.4 GHz; see above
OSC_TMAX="2p"         # ceiling: ~100 samples/period at 5 GHz
OSC_TMEAS_START="2.5e-9"  # discard the startup ramp: 2.8x the measured t_settle
# shellcheck disable=SC2034  # read by the run_*.sh that source this file
OSC_TSTOP_S="5e-9"        # OSC_TSTOP as a number, for the extractors
OSC_SETTLE_FRAC="0.9"     # envelope fraction that defines "settled"
OSC_SETTLE_REF="3.75e-9"  # window whose peak-to-peak is the "final" amplitude

# THE TIMESTEP CEILING IS NOT A COST LEVER -- measured, because the obvious
# way to make this grid affordable would be to coarsen it. On this netlist the
# same 2 ns transient takes 169 s wall at OSC_TMAX=2p and 183 s at 5p (one
# core, ngspice-46, host under contention): raising the ceiling 2.5x produced
# NO speedup at all. The solver's cost is in the Newton iterations the 32 OSDI
# varactor instances and four HBTs demand per accepted point, not in the
# number of accepted points. Coarsening would therefore buy nothing but a
# larger discretization error -- the measured 2p -> 5p delta on f_osc is
# -0.19 % -- so the bench stays at 2 ps and run_pilot_grid.sh records that
# delta rather than leaving the question open.

# The margin bench gets a LONGER window than the frequency bench, deliberately.
# Near the oscillation threshold the startup time constant diverges, so a rung
# that would eventually oscillate can still be growing when a short window
# ends. That biases the measured threshold current UP and the reported margin
# DOWN (limit 4 in tb_vco_core_margin.spice.tmpl's header). 6 ns is 1.2x the
# frequency bench's window, and the per-rung oscillation criterion is evaluated
# over its last quarter (4.5 .. 6 ns). The ladder's per-rung envelope is
# recorded, so a rung sitting just under the criterion is visible as a
# near-miss rather than as a clean "did not oscillate".
OSC_MARGIN_TSTOP="6n"
OSC_MARGIN_TSTOP_S="6e-9"

# Startup initial condition. A 10 mV differential perturbation about the
# VDD rail -- the same mechanism design/vco.spice carries, restated here so
# the margin bench can compare an envelope against it by name.
OSC_VDD_NOM="3.3"
OSC_IC_DIFF_MV="10"
OSC_IC_OUTP="3.305"
OSC_IC_OUTN="3.295"

# SUPPLY RAIL (issue #113, DR-004 stage 2). OSC_VSUP_V is the rail a run
# simulates; EMPTY means the nominal rail (OSC_VDD_NOM) and leaves every
# generated deck, CSV and column byte-identical to the stage-1 behaviour. A
# non-nominal rail is carried through ONE place (osc_render) so the device
# section's VSUP, the common-mode observation offset, the startup .ic and the
# power calculation can never disagree about the rail. OSC_CSV_RAIL=1 (set by
# the stage-2 driver only) appends a `vsup_v` identity column to the CSVs so a
# row can never be aggregated across rails; nominal records keep their columns.
OSC_VSUP_V="${OSC_VSUP_V:-}"
OSC_CSV_RAIL="${OSC_CSV_RAIL:-0}"

# osc_rail -- the rail in volts this run simulates, as text.
osc_rail() { echo "${OSC_VSUP_V:-${OSC_VDD_NOM}}"; }

# osc_rail_is_nominal -- exit 0 when the active rail equals OSC_VDD_NOM.
osc_rail_is_nominal() {
  awk -v a="$(osc_rail)" -v b="${OSC_VDD_NOM}" \
    'BEGIN { d = a - b; if (d < 0) d = -d; exit (d < 1e-9) ? 0 : 1 }'
}

# osc_rail_ic -- "<outp> <outn>": the startup .ic pair, centred on the active
# rail with the same OSC_IC_DIFF_MV perturbation. At the nominal rail this is
# the OSC_IC_OUTP/OSC_IC_OUTN constants verbatim.
osc_rail_ic() {
  if osc_rail_is_nominal; then echo "${OSC_IC_OUTP} ${OSC_IC_OUTN}"; return 0; fi
  awk -v r="$(osc_rail)" -v d="${OSC_IC_DIFF_MV}" \
    'BEGIN { h = d * 1e-3 / 2; printf "%.6g %.6g\n", r + h, r - h }'
}

# Margin (row-6) proxy. See testbench/tb_vco_core_margin.spice.tmpl's header.
# RREF multipliers; rung 1 is the netlist's own nominal. The ladder keeps its
# finest spacing around the row-6 bound of 3.0 (rungs at 2/3/4) so a corner
# whose margin lands near the bound is bracketed tightly there, and then opens
# out geometrically so a comfortably-passing corner's threshold is actually
# FOUND rather than reported as an open-ended "greater than the last rung".
# A bracket is only a measurement if both ends exist; every extra rung is a
# full transient, which is why the ladder stops at 24x.
OSC_MARGIN_SCALES="1 2 3 4 6 8 12 16 24"
OSC_MARGIN_VCTRL="1.65"              # band-centre control voltage
OSC_OSC_CRIT_MULT="10"               # envelope must reach 10 x the .ic diff

# Spec bounds this experiment MEASURES against. They are read from, never
# written to: agents do not relax a ratified row to make a result pass
# (CLAUDE.md), so these are copies of spec/target-spec.md's numbers used only
# to print a verdict, and a miss is recorded as a miss.
OSC_ROW1_F_MIN_HZ="4.5e9"
OSC_ROW1_F_MAX_HZ="5.5e9"
OSC_ROW2_RATIO="1.15"
OSC_ROW2_RATIO_STRETCH="1.20"
# Row 3 (RATIFIED per DR-004): graded over the window W = [V_LO, V_HI].
OSC_ROW3_V_LO="1.65"
OSC_ROW3_V_HI="3.30"
OSC_ROW3_V_FULL_LO="0.0"
OSC_ROW3_COVERAGE_MIN="0.90"
OSC_ROW3_KVCO_MEAN_MIN_HZ_PER_V="381e6"
OSC_ROW3_CHORD_INL_PCT="30"
OSC_ROW3_CHORD_INL_PCT_STRETCH="20"
OSC_ROW3_MIN_SAMPLES="5"
# Row 7 (RATIFIED per DR-004 (d)/(e)): Vpp_diff at the tank nodes, no buffer,
# everywhere in the row-3 window W at every bound corner; and the HBT
# compliance inequality (VDD + Vpp_diff/4) - V(TAIL)_min <= BVCEO(min).
OSC_ROW7_VPP_MIN_V="0.40"
OSC_ROW7_VPP_MIN_STRETCH_V="0.65"
OSC_ROW7_BVCEO_MIN_V="2.2"
OSC_ROW7_MIN_WINDOW_SAMPLES="5"
OSC_ROW6_MARGIN="3.0"
# shellcheck disable=SC2034  # read by the run_*.sh that source this file
OSC_ROW8_P_MAX_W="10e-3"

# --------------------------------------------------------------------------
# osc_preflight
# Resolve and validate everything a PDK-dependent run needs, in the order
# that produces the clearest message when one is missing. Sets the globals
# OSC_IND_MODEL, OSC_OSDI_MOSVAR, OSC_NGSPICE_VERSION, OSC_VCO_BODY,
# OSC_RREF_NOM_OHM, OSC_RTE_OHM, and -- last -- captures the model-input
# bundle (OSC_BUNDLE_*; osc_capture_model_bundle). OSC_IND_MODEL /
# OSC_OSDI_MOSVAR / SG13G2_NGSPICE_MODELS stay the ORIGINAL locations, kept
# as context; decks never read them directly. Requires EXPERIMENT_DIR / SIM_DIR /
# REPO_ROOT and a sourced sim/env.sh + sim/lib.sh.
# --------------------------------------------------------------------------
osc_preflight() {
  local tool
  for tool in ngspice awk; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "error: ${tool} not found on PATH." >&2
      return 1
    fi
  done

  if [[ -z "${SG13G2_NGSPICE_MODELS:-}" \
        || ! -f "${SG13G2_NGSPICE_MODELS}/cornerHBT.lib" \
        || ! -f "${SG13G2_NGSPICE_MODELS}/cornerMOShv.lib" \
        || ! -f "${SG13G2_NGSPICE_MODELS}/cornerCAP.lib" ]]; then
    echo "error: could not resolve the SG13G2 ngspice model libraries." >&2
    echo "       expected \$PDK_ROOT/\$PDK/libs.tech/ngspice/models/{cornerHBT,cornerMOShv,cornerCAP}.lib" >&2
    echo "       see the message from sim/env.sh above, and sim/pdk.json." >&2
    return 1
  fi

  OSC_IND_MODEL="${SIM_DIR}/inductor-model/sg13g2_inductor_em.spice"
  if [[ ! -f "${OSC_IND_MODEL}" ]]; then
    echo "error: ${OSC_IND_MODEL} is missing -- the PDK ships no ngspice" >&2
    echo "       inductor model (sim/pdk.json known_model_gaps.spiral_inductor);" >&2
    echo "       this repo supplies its own and design/vco.sch depends on it." >&2
    return 1
  fi

  # Netlist freshness FIRST, before anything is generated: a run must never
  # be able to grade a netlist that has drifted from design/vco.sch.
  # design/netlist.sh --check diffs the committed netlist against a fresh
  # xschem netlisting and exits non-zero on any difference.
  echo "oscillator-core: checking design/vco.spice against design/vco.sch ..."
  "${REPO_ROOT}/design/netlist.sh" --check

  # sim/README.md rule 1: a run that needs a build step owns that step.
  echo "oscillator-core: ensuring mosvar.osdi is built and loadable ..."
  "${SIM_DIR}/tools/build-osdi.sh"
  OSC_OSDI_MOSVAR="${SG13G2_OSDI_DIR}/mosvar.osdi"
  if [[ ! -f "${OSC_OSDI_MOSVAR}" ]]; then
    echo "error: sim/tools/build-osdi.sh reported success but ${OSC_OSDI_MOSVAR} is missing." >&2
    return 1
  fi

  # shellcheck disable=SC2034  # read by the run_*.sh that source this file
  OSC_NGSPICE_VERSION="$(detect_ngspice_version)"

  osc_derive_body || return 1

  # LAST, after the OSDI build and before any simulation (issue #133): every
  # deck this run renders reads its models from this private copy.
  osc_capture_model_bundle || return 1
}

# --------------------------------------------------------------------------
# Model-input bundle (issue #133)
#
# osc_derive_body captures design/vco.spice once (issue #122); this does the
# same for everything else a deck reads by path. osc_capture_model_bundle
# copies, into ${WORKDIR}/model-bundle/:
#   models/    the PDK model libraries in OSC_MODEL_LIB_ROOTS plus the
#              TRANSITIVE closure of their .include/.lib references (every
#              section, so every corner this run can select is covered);
#   inductor/  the non-PDK inductor model (and anything it includes);
#   osdi/      the mosvar.osdi binary osc_preflight just built;
#   init/      this experiment's .spiceinit, which is then also what ngspice
#              reads from ${WORKDIR} (make_scratch_workdir's copy is replaced
#              by the captured bytes).
# MANIFEST.tsv records each copy's sha256 (sim/lib.sh capture_input_closure).
# osc_render points every deck at the bundle, osc_provenance_md and the
# runners' narratives read digests from the manifest -- never from the live
# files -- and osc_publish_summary re-verifies the bundle before a summary
# is written. A live file edited mid-run therefore reaches neither a later
# point nor a recorded digest, and a bundle edited mid-run fails the run
# instead of publishing a clean-looking summary.
# --------------------------------------------------------------------------

# The model libraries the testbenches load (the corner libraries) plus the two
# osc_provenance_md names explicitly. Their nested references are followed.
OSC_MODEL_LIB_ROOTS="cornerHBT.lib cornerMOShv.lib cornerCAP.lib sg13g2_svaricaphv_mod.lib sg13g2_hbt_mod.lib"

# osc_record_reserved -- exit 0 when this run owns a reserved record id (the
# same condition osc_write_source_provenance writes under). Fixtures and unit
# tests that source this file without one write nothing under records/.
osc_record_reserved() {
  [[ -n "${RECORD_ID:-}" && -n "${EXPERIMENT_DIR:-}" \
     && -d "${EXPERIMENT_DIR}/corners/${RECORD_ID}" ]]
}

# osc_require_bundle -- fail unless osc_capture_model_bundle has run.
osc_require_bundle() {
  if [[ -z "${OSC_BUNDLE_DIR:-}" || ! -f "${OSC_BUNDLE_MANIFEST:-}" ]]; then
    echo "error: no captured model bundle -- osc_capture_model_bundle (osc_preflight) must run before any deck is rendered or any digest is recorded." >&2
    return 1
  fi
}

# osc_bundle_sha <bundle-relative path> -- the CAPTURED digest of one input.
osc_bundle_sha() {
  osc_require_bundle || return 1
  input_bundle_sha "${OSC_BUNDLE_MANIFEST}" "$1"
}

# osc_ind_model_sha -- the captured digest of the non-PDK inductor model.
osc_ind_model_sha() { osc_bundle_sha "inductor/$(basename "${OSC_IND_MODEL}")"; }

# osc_model_inputs_rel -- repo-relative path of the retained manifest.
osc_model_inputs_rel() {
  echo "${EXPERIMENT_DIR#"${REPO_ROOT}"/}/records/${RECORD_ID}-model-inputs.json"
}

# osc_retained_rel <bundle-relative path> -- repo-relative path under which a
# repo-owned input (inductor model, .spiceinit) is retained for a reserved
# record. PDK libraries and the OSDI binary are external and not retained.
osc_retained_rel() {
  echo "${EXPERIMENT_DIR#"${REPO_ROOT}"/}/netlist-snapshots/${RECORD_ID}/model-inputs/$1"
}

# osc_capture_model_bundle
# Requires SG13G2_NGSPICE_MODELS, OSC_IND_MODEL, OSC_OSDI_MOSVAR (osc_preflight),
# EXPERIMENT_DIR (its .spiceinit) and WORKDIR. Sets OSC_BUNDLE_DIR,
# OSC_BUNDLE_MANIFEST, OSC_BUNDLE_MANIFEST_SHA. Fails -- before any
# simulation -- on a missing root or nested dependency, a reference that
# cannot be served from the bundle, or an init file that loads anything.
osc_capture_model_bundle() {
  local b="${WORKDIR}/model-bundle" m
  if [[ -e "${b}" ]]; then
    echo "error: ${b} already exists; a run captures its model inputs exactly once." >&2
    return 1
  fi
  mkdir -p "${b}" || return 1
  m="${b}/MANIFEST.tsv"; : > "${m}"

  # shellcheck disable=SC2086  # OSC_MODEL_LIB_ROOTS is a word list
  capture_input_closure "${SG13G2_NGSPICE_MODELS}" "${b}" models "${m}" pdk-model ${OSC_MODEL_LIB_ROOTS} || {
    echo "error: could not capture the SG13G2 model libraries and their nested references; no simulation was run." >&2
    return 1
  }
  capture_input_closure "$(dirname "${OSC_IND_MODEL}")" "${b}" inductor "${m}" inductor-model "$(basename "${OSC_IND_MODEL}")" || {
    echo "error: could not capture ${OSC_IND_MODEL} and its references; no simulation was run." >&2
    return 1
  }
  capture_input_file "${OSC_OSDI_MOSVAR}" "${b}" "osdi/$(basename "${OSC_OSDI_MOSVAR}")" "${m}" osdi-binary || return 1
  capture_input_file "${EXPERIMENT_DIR}/.spiceinit" "${b}" "init/.spiceinit" "${m}" simulator-init || return 1

  # The init file must not pull in anything this capture did not follow.
  if grep -qiE '^[[:space:]]*(source|osdi|pre_osdi|codemodel|pre_codemodel)[[:space:]]' "${b}/init/.spiceinit"; then
    echo "error: ${EXPERIMENT_DIR}/.spiceinit loads a file (source/osdi/codemodel), which the model bundle does not capture." >&2
    return 1
  fi
  # ngspice reads .spiceinit from its working directory: serve the captured bytes.
  cp "${b}/init/.spiceinit" "${WORKDIR}/.spiceinit" && cmp -s "${b}/init/.spiceinit" "${WORKDIR}/.spiceinit" || return 1

  OSC_BUNDLE_DIR="${b}"
  OSC_BUNDLE_MANIFEST="${m}"
  osc_model_inputs_json > "${b}/model-inputs.json" || return 1
  # Read-only copies: an accidental write fails instead of landing silently.
  # (Files only -- the directories stay writable so WORKDIR cleanup works.)
  find "${b}" -type f -exec chmod a-w {} + || return 1
  OSC_BUNDLE_MANIFEST_SHA="$(sha256_of "${m}")"
  osc_retain_model_inputs || return 1
  echo "oscillator-core: captured $(wc -l < "${m}" | tr -d ' ') model inputs into a private bundle" \
       "(manifest sha256 ${OSC_BUNDLE_MANIFEST_SHA})"
}

# osc_model_inputs_json -- the machine-readable manifest (schema
# sg13g2-vco/model-inputs/1, documented in sim/README.md), from MANIFEST.tsv.
osc_model_inputs_json() {
  local retain=0 rid="${RECORD_ID:-}" snap_prefix=""
  if osc_record_reserved; then
    retain=1
    snap_prefix="$(osc_retained_rel "")"
  fi
  awk -F'\t' -v rid="${rid}" -v root="${REPO_ROOT:-}/" -v retain="${retain}" -v sp="${snap_prefix}" '
    function js(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
    {
      orig = $4
      if (root != "/" && index(orig, root) == 1) orig = substr(orig, length(root) + 1)
      kept = (retain && ($1 == "inductor-model" || $1 == "simulator-init")) ? js(sp $2) : "null"
      line[++n] = sprintf("    {\"role\": %s, \"bundle_path\": %s, \"sha256\": %s, \"original_path\": %s, \"retained_snapshot\": %s}", \
                          js($1), js($2), js($3), js(orig), kept)
    }
    END {
      if (n == 0) exit 1
      print "{"
      print "  \"schema\": \"sg13g2-vco/model-inputs/1\","
      print "  \"record_id\": " js(rid) ","
      print "  \"note\": \"sha256 of the private copies every deck of this run was rendered against; retained_snapshot null = external input (PDK library or built OSDI binary), identified by digest only\","
      print "  \"inputs\": ["
      for (i = 1; i <= n; i++) print line[i] (i < n ? "," : "")
      print "  ]"
      print "}"
    }' "${OSC_BUNDLE_MANIFEST}"
}

# osc_put_append_only <src> <dest> -- copy <src> to <dest> unless <dest>
# already exists; an existing <dest> must be byte-identical (append-only).
osc_put_append_only() {
  if [[ -e "$2" ]]; then
    cmp -s "$1" "$2" && return 0
    echo "error: $2 already exists with different content (append-only)" >&2
    return 1
  fi
  mkdir -p "$(dirname "$2")" && cp "$1" "$2" && cmp -s "$1" "$2"
}

# osc_retain_model_inputs -- for a reserved record: the JSON manifest under
# records/, and copies of the repo-owned inputs under netlist-snapshots/.
# Append-only: an existing file with different content is refused.
osc_retain_model_inputs() {
  osc_record_reserved || return 0
  local json role rel sha dest
  json="${REPO_ROOT}/$(osc_model_inputs_rel)"
  while IFS='	' read -r role rel sha _; do
    case "${role}" in
      inductor-model|simulator-init)
        dest="${REPO_ROOT}/$(osc_retained_rel "${rel}")"
        osc_put_append_only "${OSC_BUNDLE_DIR}/${rel}" "${dest}" || return 1 ;;
    esac
  done < "${OSC_BUNDLE_MANIFEST}"
  osc_put_append_only "${OSC_BUNDLE_DIR}/model-inputs.json" "${json}"
}

# osc_verify_model_bundle
# Integrity check of everything the run's decks read and its records cite:
# every bundle file against its captured digest, the manifest itself, the
# .spiceinit ngspice reads from WORKDIR, and (for a reserved record) the
# retained manifest and snapshots. Fails, naming each discrepancy, if any
# changed after capture.
osc_verify_model_bundle() {
  osc_require_bundle || return 1
  local bad=0 role rel sha
  verify_input_bundle "${OSC_BUNDLE_DIR}" "${OSC_BUNDLE_MANIFEST}" || bad=1
  if [[ "$(sha256_of "${OSC_BUNDLE_MANIFEST}")" != "${OSC_BUNDLE_MANIFEST_SHA:-}" ]]; then
    echo "error: the bundle manifest changed after capture." >&2; bad=1
  fi
  if [[ "$(sha256_of "${WORKDIR}/.spiceinit")" != "$(osc_bundle_sha init/.spiceinit)" ]]; then
    echo "error: ${WORKDIR}/.spiceinit no longer matches the captured init file." >&2; bad=1
  fi
  if osc_record_reserved; then
    cmp -s "${OSC_BUNDLE_DIR}/model-inputs.json" "${REPO_ROOT}/$(osc_model_inputs_rel)" || {
      echo "error: retained $(osc_model_inputs_rel) is missing or differs from the captured manifest." >&2; bad=1
    }
    while IFS='	' read -r role rel sha _; do
      case "${role}" in
        inductor-model|simulator-init)
          [[ "$(sha256_of "${REPO_ROOT}/$(osc_retained_rel "${rel}")")" == "${sha}" ]] || {
            echo "error: retained snapshot $(osc_retained_rel "${rel}") does not match its captured digest." >&2; bad=1
          } ;;
      esac
    done < "${OSC_BUNDLE_MANIFEST}"
  fi
  [[ ${bad} -eq 0 ]]
}

# osc_publish_summary <draft> <dest>
# Publish a runner's narrative summary: verify the model bundle FIRST, then
# copy the draft (written into WORKDIR) to <dest>. On a failed verification
# nothing is written to <dest> and the call fails. Refuses to overwrite.
osc_publish_summary() {
  local draft="$1" dest="$2"
  if ! osc_verify_model_bundle; then
    echo "error: model-input bundle failed integrity verification; summary NOT published to ${dest}." >&2
    return 1
  fi
  if [[ -e "${dest}" ]]; then
    echo "error: ${dest} already exists (append-only); summary NOT published." >&2
    return 1
  fi
  cp "${draft}" "${dest}" && cmp -s "${draft}" "${dest}"
}

# --------------------------------------------------------------------------
# osc_provenance_md
# Print the PDK + loaded-library provenance bullets that every record written
# by a runner sourcing this file must carry: the pinned PDK, then the sha256
# digest of each model library the decks load and of the OSDI binary this run
# built, then the captured-bundle statement (issue #133). Every digest is
# read from the model bundle's manifest -- the bytes the decks consumed --
# never by re-hashing the live files. Emits markdown lines on stdout -- no `## Provenance`
# heading (only run_isf_pilot.sh wants one, and it prints its own) and no
# trailing blank line -- so a caller drops it inside its own record block
# without reflowing anything around it.
#
# WHY THIS IS A FUNCTION AND NOT COPIED PER RUNNER
# This block is the record's statement of WHICH model files produced its
# numbers, and sim/ records are append-only evidence (CLAUDE.md). A deck that
# gains a library, or an OSDI path that moves, has to be reflected in every
# runner's copy; a copy that is missed writes records with an incomplete
# provenance list, nothing fails, and the records cannot be corrected
# afterwards. One definition means the list cannot drift between runners.
#
# REQUIRES osc_preflight to have run: it reads the bundle osc_preflight
# captured (osc_capture_model_bundle; without one this fails rather than
# hashing live paths), plus PDK / PDK_ROOT from sim/env.sh. The line format
# of the six digest bullets is parsed by report_supply_stage2.sh -- keep it.
# --------------------------------------------------------------------------
osc_provenance_md() {
  osc_require_bundle || return 1
  local n_inputs where
  n_inputs="$(wc -l < "${OSC_BUNDLE_MANIFEST}" | tr -d ' ')"
  if osc_record_reserved; then where="retained as \`$(osc_model_inputs_rel)\`"
  else where="not retained (no reserved record id)"; fi
  echo "- **PDK**: \`${PDK}\` at \`${PDK_ROOT}\` -- pinned release in"
  echo "  \`sim/pdk.json\`. Loaded libraries and the OSDI binary by digest:"
  echo "  - \`cornerHBT.lib\` sha256 \`$(osc_bundle_sha models/cornerHBT.lib)\`"
  echo "  - \`cornerMOShv.lib\` sha256 \`$(osc_bundle_sha models/cornerMOShv.lib)\`"
  echo "  - \`cornerCAP.lib\` sha256 \`$(osc_bundle_sha models/cornerCAP.lib)\`"
  echo "  - \`sg13g2_svaricaphv_mod.lib\` sha256 \`$(osc_bundle_sha models/sg13g2_svaricaphv_mod.lib)\`"
  echo "  - \`sg13g2_hbt_mod.lib\` sha256 \`$(osc_bundle_sha models/sg13g2_hbt_mod.lib)\`"
  echo "  - \`mosvar.osdi\` (this run's build) sha256 \`$(osc_bundle_sha "osdi/$(basename "${OSC_OSDI_MOSVAR}")")\`"
  echo "  - **Captured model inputs** (issue #133): these digests are of private"
  echo "    copies taken after preflight/build and before the first simulation;"
  echo "    every deck was rendered against them. ${n_inputs} files (the transitive"
  echo "    \`.include\`/\`.lib\` closure, inductor model, OSDI binary, \`.spiceinit\`),"
  echo "    manifest sha256 \`${OSC_BUNDLE_MANIFEST_SHA}\`, ${where};"
  echo "    re-verified intact before this summary was published."
}

# osc_write_source_provenance <sha256> <captured-copy>
# Persist the source actually consumed, associated with the reserved record id:
#   <experiment>/netlist-snapshots/<id>/design-vco.spice   (captured bytes)
#   <experiment>/records/<id>-source-provenance.json       (sidecar)
# Only when a record id is reserved for this run (RECORD_ID set and its
# corners/<id> reservation directory exists); benches sourced without one
# (fixtures, unit tests) derive exactly as before and write nothing.
osc_write_source_provenance() {
  local sha="$1" captured="$2"
  [[ -n "${RECORD_ID:-}" && -n "${EXPERIMENT_DIR:-}" \
     && -d "${EXPERIMENT_DIR}/corners/${RECORD_ID}" ]] || return 0
  local rel_exp="${EXPERIMENT_DIR#"${REPO_ROOT}"/}"
  local snap="${EXPERIMENT_DIR}/netlist-snapshots/${RECORD_ID}/design-vco.spice"
  if [[ -e "${snap}" ]]; then
    cmp -s "${snap}" "${captured}" || {
      echo "error: ${snap} already exists with different content (append-only)" >&2
      return 1
    }
  else
    mkdir -p "$(dirname "${snap}")" && cp "${captured}" "${snap}" || return 1
  fi
  write_source_provenance "${EXPERIMENT_DIR}/records/${RECORD_ID}-source-provenance.json" \
    "${RECORD_ID}" "design/vco.spice" "${sha}" \
    "${rel_exp}/netlist-snapshots/${RECORD_ID}/design-vco.spice"
}

# --------------------------------------------------------------------------
# osc_derive_body
# Extract the DEVICE SECTION of design/vco.spice into ${WORKDIR}/vco_body.spice
# and set OSC_VCO_BODY to that path, plus OSC_RREF_NOM_OHM / OSC_RTE_OHM read
# out of it.
#
# design/vco.spice is a complete elaboration deck: schematic-derived device
# lines, then a `**** begin user architecture code` marker, then the
# elaboration harness (its .lib cards, its .ic and its own .control block).
# A graded testbench must reuse the devices and supply its OWN analysis, so
# this takes everything above that marker and drops:
#   * the `**` comment lines (xschem's `** sch_path:` header and the
#     commented-out `**.subckt vco` / `**.ends` wrapper);
#   * the `.save i(vsup)` card -- a .save RESTRICTS the saved set, so leaving
#     it in makes every node voltage unavailable and the differential-mode
#     check impossible.
# Nothing is rewritten. If design/vco.spice ever stops carrying the marker
# this fails loudly rather than silently netlisting half a circuit.
# --------------------------------------------------------------------------
osc_derive_body() {
  local src="${REPO_ROOT}/design/vco.spice"
  local out="${WORKDIR}/vco_body.spice"
  local captured="${WORKDIR}/vco_source.spice" src_sha

  # Source capture (issue #122): copy design/vco.spice once and derive from
  # the COPY, so the hash recorded in the provenance sidecar names exactly the
  # bytes consumed; an edit during the run is detected below and fails it.
  src_sha="$(snapshot_source "${src}" "${captured}")" || return 1

  if ! grep -q '^\*\*\*\* begin user architecture code' "${captured}"; then
    echo "error: ${src} has no '**** begin user architecture code' marker." >&2
    echo "       osc_bench.sh splits the netlist there to separate the" >&2
    echo "       schematic-derived devices from the elaboration harness;" >&2
    echo "       without the marker it cannot tell them apart. Re-read" >&2
    echo "       design/vco.spice and update osc_derive_body()." >&2
    return 1
  fi

  awk '
    /^\*\*\*\* begin user architecture code/ { exit }
    /^\*\*/ { next }
    /^[[:space:]]*\.save[[:space:]]/ { next }
    { print }
  ' "${captured}" > "${out}"

  assert_source_unchanged "${src}" "${src_sha}" || return 1
  osc_write_source_provenance "${src_sha}" "${captured}" || return 1

  # Every device line the circuit needs must be here. These three are the
  # load-bearing ones for this bench (the tank, the pair, the bias mirror);
  # a body that lost any of them would still "run" and silently measure
  # something else.
  local need
  for need in '^XL1 ' '^XC1 ' '^XQ1 ' '^XQ3 ' '^RREF ' '^RTE ' '^VSUP ' '^VCT '; do
    if ! grep -q "${need}" "${out}"; then
      echo "error: the device section derived from ${src} is missing a line matching '${need}'." >&2
      return 1
    fi
  done
  if ! grep -qc '^XCV' "${out}" >/dev/null; then
    echo "error: the derived device section carries no XCV* varactor instances." >&2
    return 1
  fi

  OSC_VCO_BODY="${out}"
  OSC_RREF_NOM_OHM="$(osc_body_r_ohm "${out}" RREF)" || return 1
  OSC_RTE_OHM="$(osc_body_r_ohm "${out}" RTE)" || return 1
  echo "oscillator-core: device section derived ($(grep -c . "${out}") lines);" \
       "RREF=${OSC_RREF_NOM_OHM} ohm, RTE=${OSC_RTE_OHM} ohm"
}

# osc_body_r_ohm <body-file> <instance-name>
# Print a resistor instance's value from the derived device section, in ohms,
# expanding ngspice's engineering suffixes. The margin bench needs RREF's
# nominal value to build its ladder and RTE's to turn V(TE) into a tail
# current; reading both out of the DERIVED netlist rather than hardcoding
# them means a resizing in design/vco.sch cannot leave this bench computing
# currents from a stale resistance.
osc_body_r_ohm() {
  local body="$1" name="$2" raw
  raw="$(awk -v n="${name}" 'toupper($1) == toupper(n) { print $4; exit }' "${body}")"
  if [[ -z "${raw}" ]]; then
    echo "error: no resistor instance '${name}' in the derived device section." >&2
    return 1
  fi
  awk -v v="${raw}" 'BEGIN {
    s = tolower(v); mult = 1
    if (s ~ /meg$/)      { mult = 1e6;  sub(/meg$/, "", s) }
    else if (s ~ /k$/)   { mult = 1e3;  sub(/k$/,   "", s) }
    else if (s ~ /m$/)   { mult = 1e-3; sub(/m$/,   "", s) }
    else if (s ~ /u$/)   { mult = 1e-6; sub(/u$/,   "", s) }
    printf "%.10g\n", (s + 0) * mult
  }'
}

# --------------------------------------------------------------------------
# osc_render <template> <out-netlist> <corner-id> <extra sed args...>
# Substitute the shared @@TOKEN@@ set into a testbench template, splice the
# derived device section in at the @@VCO_BODY@@ marker line, and fail if any
# token survived. Same mechanism the other three sim/ studies use, with the
# multi-line body splice added because a device section cannot go through sed.
# --------------------------------------------------------------------------
osc_render() {
  local tmpl="$1" out="$2" corner_id="$3"
  shift 3

  local rail ic_outp ic_outn ref missing=0
  rail="$(osc_rail)"
  read -r ic_outp ic_outn <<<"$(osc_rail_ic)"

  # Model paths come from the captured bundle only (issue #133), never from
  # the live install; a library the template names that the bundle does not
  # hold is a failure here, before the deck exists, not an "unknown subckt"
  # in a simulator log later.
  osc_require_bundle || return 1
  for ref in $(grep -oE '@@MODELS_DIR@@/[^[:space:]]+' "${tmpl}" | sed 's|^@@MODELS_DIR@@/||' | sort -u); do
    input_bundle_sha "${OSC_BUNDLE_MANIFEST}" "models/${ref}" >/dev/null || missing=1
  done
  [[ ${missing} -eq 0 ]] || { echo "error: ${tmpl} loads a model library the captured bundle does not hold." >&2; return 1; }

  sed \
    -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
    -e "s|@@CORNER_ID@@|${corner_id}|g" \
    -e "s|@@MODELS_DIR@@|${OSC_BUNDLE_DIR}/models|g" \
    -e "s|@@IND_MODEL@@|${OSC_BUNDLE_DIR}/inductor/$(basename "${OSC_IND_MODEL}")|g" \
    -e "s|@@OSDI_MOSVAR@@|${OSC_BUNDLE_DIR}/osdi/$(basename "${OSC_OSDI_MOSVAR}")|g" \
    -e "s|@@VDD_NOM@@|${rail}|g" \
    -e "s|@@IC_OUTP@@|${ic_outp}|g" \
    -e "s|@@IC_OUTN@@|${ic_outn}|g" \
    -e "s|@@IC_DIFF_MV@@|${OSC_IC_DIFF_MV}|g" \
    -e "s|@@TSTEP@@|${OSC_TSTEP}|g" \
    -e "s|@@TSTOP@@|${OSC_TSTOP}|g" \
    -e "s|@@TMEAS_START@@|${OSC_TMEAS_START}|g" \
    -e "s|@@SETTLE_FRAC@@|${OSC_SETTLE_FRAC}|g" \
    -e "s|@@OSC_CRIT_MULT@@|${OSC_OSC_CRIT_MULT}|g" \
    "$@" \
    "${tmpl}" > "${out}.pre"

  # The device section's own `VSUP VDD 0 dc <v>` line is the ONLY place the
  # rail lives in the netlist. At a non-nominal rail it is rewritten here --
  # exactly one line, loudly -- and nowhere else; at the nominal rail the body
  # is spliced verbatim.
  local rewrite=0
  osc_rail_is_nominal || rewrite=1
  awk -v body="${OSC_VCO_BODY}" -v rewrite="${rewrite}" -v rail="${rail}" '
    /^@@VCO_BODY@@[[:space:]]*$/ {
      while ((getline line < body) > 0) {
        if (rewrite && line ~ /^VSUP[ \t]+VDD[ \t]+0[ \t]+dc[ \t]+[-+0-9.eE]+/) {
          sub(/dc[ \t]+[-+0-9.eE]+/, "dc " rail, line); nsub++
        }
        print line
      }
      next
    }
    { print }
    END { if (rewrite && nsub != 1) exit 3 }
  ' "${out}.pre" > "${out}" || {
    echo "error: could not rewrite exactly one 'VSUP VDD 0 dc <v>' line for rail ${rail} V in ${out}." >&2
    return 1
  }
  rm -f "${out}.pre"

  if grep -vE '^[[:space:]]*\*' "${out}" | grep -q '@@'; then
    echo "error: unsubstituted placeholder token left in ${out}:" >&2
    grep -nE '@@' "${out}" | grep -vE ':[[:space:]]*\*' >&2
    return 1
  fi
}

# --------------------------------------------------------------------------
# osc_run_ngspice <netlist> <log>
# Run one corner and print "rc=<n> model_error=<0|1>". Never aborts the
# sweep: a corner that fails is a recorded finding (sim/README.md rule 4), so
# classification is returned as data and the caller decides.
#
# ngspice keeps going after an unresolvable device and can still exit 0, so
# the exit status alone is not a verdict -- the log is checked with
# sim/lib.sh's shared ngspice_model_error() (issue #55), the one place this
# pattern is now stated instead of a private copy here.
# --------------------------------------------------------------------------
osc_run_ngspice() {
  local netlist="$1" log="$2" rc=0 model_error=0
  ( cd "${WORKDIR}" && ngspice -b "${netlist}" ) > "${log}" 2>&1 || rc=$?
  if ngspice_model_error "${log}"; then
    model_error=1
  fi
  echo "rc=${rc} model_error=${model_error}"
}

# --------------------------------------------------------------------------
# osc_op_value <log> <node>
# Pull one operating-point voltage or current out of the `print` line the
# transient deck emits after `op`. ngspice batch-prints these as
# "v(tail) = <value>" style rows; a miss comes back empty so the caller can
# record "none" rather than a number.
#
# The comparison is LITERAL, on the text left of the first '=', and never a
# regex. The node names this is called with -- `v(tail)`, `i(vsup)` -- contain
# parentheses, which are grouping metacharacters in an awk dynamic regex: an
# earlier version of this function matched `$0 ~ "^v(tail)[ \t]*="`, which awk
# reads as "v" followed by the group "tail", i.e. it looked for `vtail =` and
# silently never matched. Every row-8 DC-operating-point current came back
# `nan` as a result, which looks exactly like "the print was missing" rather
# than like a bug in the reader.
# --------------------------------------------------------------------------
osc_op_value() {
  awk -v n="$(echo "$2" | tr '[:upper:]' '[:lower:]' | tr -d ' \t')" '
    { e = index($0, "=") }
    e > 1 {
      k = tolower(substr($0, 1, e - 1)); gsub(/[ \t]/, "", k)
      if (k == n) {
        v = substr($0, e + 1); gsub(/[ \t]/, "", v)
        print v; found = 1; exit
      }
    }
    END { if (!found) print "" }
  ' "$1"
}

# --------------------------------------------------------------------------
# osc_quant_floor_pct <f_hz> <cycles> <dt_max_s>
# The frequency quantization floor of a crossing count, as a percentage.
# Prints two numbers: the interpolated bound (dt_max * f / cycles -- the
# estimator actually used, whose crossing times are linearly interpolated)
# and the integer-count bound (100 / cycles -- what the floor would be
# without interpolation). Both are reported with every verdict, because a
# row-2 ratio that lands inside the floor of its bound is not a pass.
# --------------------------------------------------------------------------
osc_quant_floor_pct() {
  awk -v f="$1" -v cyc="$2" -v dt="$3" 'BEGIN {
    if (f <= 0 || cyc <= 0) { print "nan nan"; exit }
    printf "%.6g %.6g\n", 100.0 * dt * f / cyc, 100.0 / cyc
  }'
}

# --------------------------------------------------------------------------
# osc_trace_validity <datafile> <t_start_s> <t_stop_s>
# MEASUREMENT validity of one wrdata two-column trace, kept separate from the
# simulator's exit status (a clean ngspice run can still leave a trace
# missing, empty, mangled or cut short; osc_metrics() would turn each of
# those into a plausible 0). Prints "ok" or one reason token:
#   missing    no such file
#   empty      no data lines
#   malformed  a data line has fewer than 2 fields or a non-numeric field
#   nonfinite  a field is nan/inf, or a decimal literal that overflows
#              to infinity such as 1e999 (ngspice prints nan/inf on a
#              diverged solve)
#   truncated  the trace starts after t_start, ends before ~t_stop (0.1 %
#              tolerance), or has fewer than 3 samples in the window
#   unordered  time is not strictly increasing
# A reason is a FINDING about the output, never a number to be defaulted.
# --------------------------------------------------------------------------
osc_trace_validity() {
  if [[ ! -f "$1" ]]; then echo missing; return 0; fi
  awk -v ts="${2:-0}" -v te="${3:-0}" '
    function isnum(x) { return x ~ /^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$/ }
    function isnf(x)  { return tolower(x) ~ /^[-+]?(nan|inf|infinity)(\([^)]*\))?$/ }
    # Same finite semantics as pn_fin() in sim/lib.sh (PN_AWK_FINITE): a
    # well-spelled decimal whose value overflows to +-inf (1e999) is nonfinite.
    function ovf(x,   v) { v = x + 0; return !(v <= 1.7976931348623157e308 && v >= -1.7976931348623157e308) }
    /^[ \t]*$/ { next }
    {
      lines++
      if (NF < 2) { bad = 1; next }
      if (isnf($1) || isnf($2)) { nonfin = 1; next }
      if (!isnum($1) || !isnum($2)) { bad = 1; next }
      if (ovf($1) || ovf($2)) { nonfin = 1; next }
      t = $1 + 0
      if (lines > 1 && seen && t <= pt) unord = 1
      if (!seen) { t0 = t }
      seen = 1; pt = t
      if (t >= ts && (te <= 0 || t <= te)) nwin++
    }
    END {
      if (lines == 0)  { print "empty"; exit }
      if (bad)         { print "malformed"; exit }
      if (nonfin)      { print "nonfinite"; exit }
      if (unord)       { print "unordered"; exit }
      if (t0 > ts || (te > 0 && pt < te * 0.999) || nwin < 3) { print "truncated"; exit }
      print "ok"
    }' "$1"
}

# --------------------------------------------------------------------------
# osc_simulate_point <corner-id> <mos> <cap> <hbt> <temp> <vctrl> <tmax>
# One simulated (PVT, Vctrl, timestep-ceiling) point of the transient bench:
# render, freeze the netlist, run, extract, and append one row to
# ${CSV_OUT}. Also echoes a one-line progress summary. Uses the globals
# NETLIST_DIR / LOG_DIR / CSV_OUT / WORKDIR that the calling run_*.sh set up.
#
# Appends, in ${CSV_OUT}'s column order:
#   corner_id,mos,cap,hbt,temp_c,vctrl_v,tmax_s,status,
#   f_osc_hz,cycles,dt_max_s,quant_floor_interp_pct,quant_floor_count_pct,
#   vpp_diff_v,t_settle_s,vpp_cm_v,vpp_cm_over_diff,f_cm_hz,f_cm_over_diff,
#   f_tail_hz,f_tail_over_diff,v_tail_dc_op_v,v_tail_mean_v,
#   isup_dc_op_a,isup_ls_avg_a,p_core_dc_op_w,p_core_ls_w,
#   meas_status,meas_reason,
#   v_tail_min_v,t_tail_min_s,v_tail_pp_v,v_tail_min_err_v,vpp_diff_err_v,
#   vdd_v,vce_max_v,vce_max_upper_v
#
# Columns 30-37 (issue #112, row 7) are APPENDED so every column 1-29 keeps
# its meaning for readers of older records: the sampled cycle minimum of
# V(TAIL) over the settled window and its time, the tail ripple peak-to-peak,
# the sampling bounds on the tail minimum and on vpp_diff, the actual rail
# (sampled max of V(VDD) over the window), and the DR-004 (e) inequality's
# left side as measured and at its sampling-bound worst case (see
# osc_row7_point). Older records have 29 columns and are never re-graded.
#
# status is the SIMULATOR/oscillation classification (PASS/NOSC/FAIL, or NODATA
# when the clean run left no usable differential trace to classify with).
# meas_status is separate: VALID only when all five required traces (vdiff,
# vcm, vtail, isup, vdd) passed osc_trace_validity; otherwise INVALID with
# meas_reason naming each trace and its fault, and every value derived from an
# invalid trace is nan, never 0.
# --------------------------------------------------------------------------
osc_simulate_point() {
  local corner_id="$1" mos="$2" cap="$3" hbt="$4" temp="$5" vctrl="$6" tmax="$7"
  local netlist="${NETLIST_DIR}/${corner_id}.spice"
  local log="${LOG_DIR}/${corner_id}.log"
  local prefix="tr_${corner_id}"

  osc_render "${EXPERIMENT_DIR}/testbench/tb_vco_core_tran.spice.tmpl" \
             "${netlist}" "${corner_id}" \
             -e "s|@@HBT_SECTION@@|${hbt}|g" \
             -e "s|@@MOS_SECTION@@|mos_${mos}|g" \
             -e "s|@@CAP_SECTION@@|${cap}|g" \
             -e "s|@@TEMP_C@@|${temp}|g" \
             -e "s|@@VCTRL@@|${vctrl}|g" \
             -e "s|@@TMAX@@|${tmax}|g" \
             -e "s|@@OUT_PREFIX@@|${prefix}|g" || return 1

  local class rc model_error
  class="$(osc_run_ngspice "${netlist}" "${log}")"
  rc="${class#rc=}"; rc="${rc%% *}"
  model_error="${class##*model_error=}"

  local d_vdiff="${WORKDIR}/${prefix}_vdiff"
  local d_vcm="${WORKDIR}/${prefix}_vcm"
  local d_vtail="${WORKDIR}/${prefix}_vtail"
  local d_isup="${WORKDIR}/${prefix}_isup"
  local d_vdd="${WORKDIR}/${prefix}_vdd"

  local status=FAIL
  local f_osc=0 cycles=0 dtmax=0 vpp_d=0
  local f_cm=nan vpp_cm=nan f_tail=nan vtail_mean=nan isup_avg=nan
  local vpp_tail=nan dt_tail=nan vtail_min=nan t_tail_min=nan vdd=nan
  local t_settle=nan
  local floor_i=nan floor_c=nan

  # Measurement validity first, per trace, BEFORE any extractor sees the data:
  # a missing trace must stay unavailable (nan), not become a measured zero.
  local tstop_s="${OSC_TSTOP_S}"
  local meas_reason="" v name tv_vdiff tv_vcm tv_vtail tv_isup tv_vdd
  for name in vdiff vcm vtail isup vdd; do
    v="$(osc_trace_validity "${WORKDIR}/${prefix}_${name}" "${OSC_TMEAS_START}" "${tstop_s}")"
    [[ "${v}" != "ok" ]] && meas_reason="${meas_reason:+${meas_reason};}${name}:${v}"
    case "${name}" in
      vdiff) tv_vdiff="${v}" ;; vcm) tv_vcm="${v}" ;;
      vtail) tv_vtail="${v}" ;; isup) tv_isup="${v}" ;;
      vdd) tv_vdd="${v}" ;;
    esac
  done
  local meas_status=VALID
  [[ -n "${meas_reason}" ]] && meas_status=INVALID

  if [[ "${tv_vdiff}" == "ok" ]]; then
    read -r f_osc vpp_d cycles _mean_d _tx1 _tx2 dtmax _ns \
      <<<"$(osc_metrics "${d_vdiff}" "${OSC_TMEAS_START}")"
    read -r t_settle _vppf _nextrema \
      <<<"$(osc_settle "${d_vdiff}" "${OSC_SETTLE_FRAC}" "${OSC_SETTLE_REF}")"
    read -r floor_i floor_c <<<"$(osc_quant_floor_pct "${f_osc}" "${cycles}" "${dtmax}")"
  fi
  if [[ "${tv_vcm}" == "ok" ]]; then
    read -r f_cm vpp_cm _c _m _a _b _d _n \
      <<<"$(osc_metrics "${d_vcm}" "${OSC_TMEAS_START}")"
  fi
  if [[ "${tv_vtail}" == "ok" ]]; then
    read -r f_tail vpp_tail _c vtail_mean _a _b dt_tail _n \
      <<<"$(osc_metrics "${d_vtail}" "${OSC_TMEAS_START}")"
    # Row 7: the instantaneous (sampled) cycle minimum, never the mean or the
    # DC operating point (DR-004 (e) names both as stand-ins).
    read -r vtail_min t_tail_min _vmax _tmax _dt _n \
      <<<"$(osc_trace_extrema "${d_vtail}" "${OSC_TMEAS_START}")"
  fi
  if [[ "${tv_isup}" == "ok" ]]; then
    read -r _f _vpp _c isup_avg _a _b _d _n \
      <<<"$(osc_metrics "${d_isup}" "${OSC_TMEAS_START}")"
  fi
  if [[ "${tv_vdd}" == "ok" ]]; then
    # The point's ACTUAL rail: the sampled maximum of V(VDD) over the settled
    # window (the larger VDD is the worse case for the inequality). With the
    # netlist's ideal VSUP it equals the source value; a future supply
    # sub-corner or non-ideal rail is picked up without a code change.
    read -r _vmin _tmin vdd _tmax _dt _n \
      <<<"$(osc_trace_extrema "${d_vdd}" "${OSC_TMEAS_START}")"
  fi
  local vpp_d_err=nan vtail_min_err=nan vce=nan vce_up=nan
  if [[ "${tv_vdiff}" == "ok" ]]; then
    read -r vpp_d_err vtail_min_err vce vce_up \
      <<<"$(osc_row7_point "${vpp_d}" "${f_osc}" "${dtmax}" "${vpp_tail}" "${f_tail}" "${dt_tail}" "${vtail_min}" "${vdd}")"
  fi

  local vtail_op isup_op
  vtail_op="$(osc_op_value "${log}" "v(tail)")"
  isup_op="$(osc_op_value "${log}" "i(vsup)")"

  # A point PASSES when the simulator ran clean AND a countable oscillation
  # came out of it. A clean run that did not oscillate is NOSC, not FAIL:
  # they are different findings and the sweep must not blur them (row 6 in
  # particular is decided by which of the two it is).
  if [[ "${rc}" == "0" && "${model_error}" == "0" ]]; then
    if [[ "${tv_vdiff}" != "ok" ]]; then
      # Clean run, but no usable differential trace: neither PASS nor an
      # honest NOSC (which needs a trace that was measured and was flat).
      status=NODATA
    elif awk -v f="${f_osc}" 'BEGIN { exit (f > 1e9) ? 0 : 1 }'; then
      status=PASS
    else
      status=NOSC
    fi
  fi

  local row
  row="$(awk -v vpp_cm="${vpp_cm}" -v vpp_d="${vpp_d}" -v f_cm="${f_cm}" \
             -v f_tail="${f_tail}" -v f_osc="${f_osc}" -v isup_avg="${isup_avg}" \
             -v isup_op="${isup_op:-nan}" -v vdd="$(osc_rail)" 'BEGIN {
    r_cm    = (vpp_d  > 0 && vpp_cm != "nan") ? vpp_cm / vpp_d : "nan"
    fr_cm   = (f_osc  > 0 && f_cm   != "nan") ? f_cm   / f_osc : "nan"
    fr_tail = (f_osc  > 0 && f_tail != "nan") ? f_tail / f_osc : "nan"
    p_ls    = (isup_avg == "nan") ? "nan" : isup_avg * vdd
    # i(vsup) is current INTO the source, i.e. negative for a supply; the
    # transient trace is already sign-flipped, the op print is not.
    iop = (isup_op == "nan" || isup_op == "") ? "nan" : -isup_op
    p_op = (iop == "nan") ? "nan" : iop * vdd
    printf "%s,%s,%s,%s,%s,%s,%s", r_cm, fr_cm, fr_tail, iop, p_op, p_ls, ""
  }')"
  local r_cm fr_cm fr_tail iop p_op p_ls
  IFS=, read -r r_cm fr_cm fr_tail iop p_op p_ls _ <<<"${row}"

  echo "${corner_id},${mos},${cap},${hbt},${temp},${vctrl},${tmax},${status},${f_osc},${cycles},${dtmax},${floor_i},${floor_c},${vpp_d},${t_settle},${vpp_cm},${r_cm},${f_cm},${fr_cm},${f_tail},${fr_tail},${vtail_op:-nan},${vtail_mean},${iop},${isup_avg},${p_op},${p_ls},${meas_status},${meas_reason:--},${vtail_min},${t_tail_min},${vpp_tail},${vtail_min_err},${vpp_d_err},${vdd},${vce},${vce_up}$(osc_csv_rail_suffix)" >> "${CSV_OUT}"

  printf "[%s] %s  f=%s Hz  Vpp_d=%s V  t_settle=%s s  P_ls=%s W  (rc=%s model_error=%s meas=%s%s)\n" \
         "${corner_id}" "${status}" "${f_osc}" "${vpp_d}" "${t_settle}" "${p_ls}" \
         "${rc}" "${model_error}" "${meas_status}" "${meas_reason:+ ${meas_reason}}"

  # Keep the scratch dir bounded: a full grid writes five traces per point and
  # each is a few hundred kB. The frozen netlist and the raw log are the
  # committed evidence; the traces are intermediates the record derives from.
  rm -f "${d_vdiff}" "${d_vcm}" "${d_vtail}" "${d_isup}" "${d_vdd}"

  [[ "${status}" == "PASS" ]]
}

# --------------------------------------------------------------------------
# osc_margin_corner <corner-id-prefix> <mos> <cap> <hbt> <temp>
# One corner of the row-6 margin bench: walk the RREF ladder, record the
# measured tail current and envelope at each rung, and append both the
# per-rung rows (${MARGIN_CSV}) and the bracketed margin (${MARGIN_SUM_CSV}).
# --------------------------------------------------------------------------
osc_margin_corner() {
  local base="$1" mos="$2" cap="$3" hbt="$4" temp="$5"
  local corner_id="mg_${base}"
  local netlist="${NETLIST_DIR}/${corner_id}.spice"
  local log="${LOG_DIR}/${corner_id}.log"
  local prefix="mg_${base}"

  # Absolute ohms, computed here because ngspice's foreach cannot do
  # arithmetic. Integer-formatted so the per-rung wrdata filenames the
  # template builds ("..._vdiff_$rr") carry no '.' or 'e'.
  local ladder scale
  ladder=""
  for scale in ${OSC_MARGIN_SCALES}; do
    ladder="${ladder} $(awk -v r="${OSC_RREF_NOM_OHM}" -v s="${scale}" 'BEGIN{printf "%d", r*s}')"
  done
  ladder="${ladder# }"

  # The margin deck runs to OSC_MARGIN_TSTOP, not OSC_TSTOP (see that
  # constant's header: near threshold the envelope grows slowly and a short
  # window would bias the threshold current up). osc_render substitutes
  # @@TSTOP@@ from OSC_TSTOP, so it is swapped around the call rather than
  # duplicated as a second token -- one token, one meaning, in both templates.
  local saved_tstop="${OSC_TSTOP}"
  OSC_TSTOP="${OSC_MARGIN_TSTOP}"
  osc_render "${EXPERIMENT_DIR}/testbench/tb_vco_core_margin.spice.tmpl" \
             "${netlist}" "${corner_id}" \
             -e "s|@@HBT_SECTION@@|${hbt}|g" \
             -e "s|@@MOS_SECTION@@|mos_${mos}|g" \
             -e "s|@@CAP_SECTION@@|${cap}|g" \
             -e "s|@@TEMP_C@@|${temp}|g" \
             -e "s|@@VCTRL@@|${OSC_MARGIN_VCTRL}|g" \
             -e "s|@@TMAX@@|${OSC_TMAX}|g" \
             -e "s|@@RREF_LADDER@@|${ladder}|g" \
             -e "s|@@OUT_PREFIX@@|${prefix}|g" || { OSC_TSTOP="${saved_tstop}"; return 1; }
  OSC_TSTOP="${saved_tstop}"

  local class rc model_error
  class="$(osc_run_ngspice "${netlist}" "${log}")"
  rc="${class#rc=}"; rc="${rc%% *}"
  model_error="${class##*model_error=}"

  # Oscillation criterion, stated: the envelope's peak-to-peak over the last
  # quarter of the transient must reach OSC_OSC_CRIT_MULT x the .ic
  # differential. Measured, per rung, from the rung's own trace.
  local crit t_last_quarter
  crit="$(awk -v m="${OSC_OSC_CRIT_MULT}" -v ic="${OSC_IC_DIFF_MV}" 'BEGIN{printf "%.6e", m*ic*1e-3}')"
  t_last_quarter="$(awk -v t="${OSC_MARGIN_TSTOP_S}" 'BEGIN{printf "%.6e", 0.75*t}')"

  local i_nom="nan" i_last_osc="nan" i_first_fail="nan" rr
  local rung=0
  for rr in ${ladder}; do
    rung=$((rung + 1))
    local dv="${WORKDIR}/${prefix}_vdiff_${rr}"
    local dte="${WORKDIR}/${prefix}_vte_${rr}"
    local dtl="${WORKDIR}/${prefix}_vtail_${rr}"
    local vpp_late=0 f_late=0 vte_mean=nan vtail_mean=nan itail=nan osc=no

    if [[ -f "${dv}" ]]; then
      read -r f_late vpp_late _c _m _a _b _d _n \
        <<<"$(osc_metrics "${dv}" "${t_last_quarter}")"
    fi
    if [[ -f "${dte}" ]]; then
      read -r _f _v _c vte_mean _a _b _d _n \
        <<<"$(osc_metrics "${dte}" "${OSC_TMEAS_START}")"
      itail="$(awk -v v="${vte_mean}" -v r="${OSC_RTE_OHM}" 'BEGIN{ if (r>0) printf "%.6e", v/r; else print "nan" }')"
    fi
    if [[ -f "${dtl}" ]]; then
      read -r _f _v _c vtail_mean _a _b _d _n \
        <<<"$(osc_metrics "${dtl}" "${OSC_TMEAS_START}")"
    fi
    if awk -v v="${vpp_late}" -v c="${crit}" 'BEGIN { exit (v >= c) ? 0 : 1 }'; then
      osc=yes
    fi

    echo "${base},${mos},${cap},${hbt},${temp},${rung},${rr},${itail},${vte_mean},${vtail_mean},${vpp_late},${f_late},${crit},${osc}$(osc_csv_rail_suffix)" >> "${MARGIN_CSV}"

    if [[ ${rung} -eq 1 ]]; then i_nom="${itail}"; fi
    if [[ "${osc}" == "yes" ]]; then
      i_last_osc="${itail}"
    elif [[ "${i_first_fail}" == "nan" ]]; then
      i_first_fail="${itail}"
    fi
  done

  # Bracketed margin, never a single interpolated number: [nominal/last
  # oscillating] is the lower bound the ladder proves, [nominal/first
  # failing] the upper bound it does not exclude.
  local summary
  summary="$(awk -v inom="${i_nom}" -v ilast="${i_last_osc}" -v ifail="${i_first_fail}" \
                 -v bound="${OSC_ROW6_MARGIN}" 'BEGIN {
    lo = (inom != "nan" && ilast != "nan" && ilast > 0) ? inom/ilast : "nan"
    hi = (inom != "nan" && ifail != "nan" && ifail > 0) ? inom/ifail : "nan"
    v = "UNDETERMINED"
    if (lo != "nan") {
      if (lo + 0 >= bound + 0)      v = "MET"
      else if (hi == "nan")          v = "NOT MET"
      else if (hi + 0 <  bound + 0)  v = "NOT MET"
      else                           v = "STRADDLES BOUND"
    }
    printf "%s,%s,%s\n", lo, hi, v
  }')"
  echo "${base},${mos},${cap},${hbt},${temp},${i_nom},${i_last_osc},${i_first_fail},${summary},${OSC_ROW6_MARGIN},rc=${rc},model_error=${model_error}$(osc_csv_rail_suffix)" >> "${MARGIN_SUM_CSV}"
  printf "[%s] margin_proxy %s  (I_nom=%s A, last-osc=%s A, first-fail=%s A)\n" \
         "${corner_id}" "${summary}" "${i_nom}" "${i_last_osc}" "${i_first_fail}"

  rm -f "${WORKDIR}/${prefix}"_*
  [[ "${rc}" == "0" && "${model_error}" == "0" ]]
}

# --------------------------------------------------------------------------
# osc_write_csv_headers
# One place that declares the column order of every CSV this experiment
# writes, so a reader of an old record and a reader of the script never
# disagree about what column 14 was.
# --------------------------------------------------------------------------
osc_csv_rail_suffix() {
  if [[ "${OSC_CSV_RAIL}" == "1" ]]; then echo ",$(osc_rail)"; fi
}

osc_write_csv_headers() {
  local rc=""
  [[ "${OSC_CSV_RAIL}" == "1" ]] && rc=",vsup_v"
  echo "corner_id,mos,cap,hbt,temp_c,vctrl_v,tmax,status,f_osc_hz,cycles,dt_max_s,quant_floor_interp_pct,quant_floor_count_pct,vpp_diff_v,t_settle_s,vpp_cm_v,vpp_cm_over_diff,f_cm_hz,f_cm_over_diff,f_tail_hz,f_tail_over_diff,v_tail_dc_op_v,v_tail_mean_v,isup_dc_op_a,isup_ls_avg_a,p_core_dc_op_w,p_core_ls_w,meas_status,meas_reason,v_tail_min_v,t_tail_min_s,v_tail_pp_v,v_tail_min_err_v,vpp_diff_err_v,vdd_v,vce_max_v,vce_max_upper_v${rc}" > "${CSV_OUT}"
  if [[ -n "${TUNING_CSV:-}" ]]; then
    echo "mos,cap,hbt,temp_c,n_points,f_min_hz,f_max_hz,v_at_f_min,v_at_f_max,tuning_ratio,tuning_pct,f_center_geo_hz,kvco_mean_hz_per_v,kvco_peak_hz_per_v,kvco_min_hz_per_v,kvco_linearity_pct,quant_floor_worst_pct,row1_verdict,row2_verdict,row2_stretch_verdict${rc}" > "${TUNING_CSV}"
  fi
  if [[ -n "${KVCO_CSV:-}" ]]; then
    echo "mos,cap,hbt,temp_c,v_lo,v_hi,v_mid,f_lo_hz,f_hi_hz,kvco_hz_per_v${rc}" > "${KVCO_CSV}"
  fi
  if [[ -n "${ROW3_CSV:-}" ]]; then
    osc_row3_header > "${ROW3_CSV}"
  fi
  if [[ -n "${ROW7_CSV:-}" ]]; then
    osc_row7_header > "${ROW7_CSV}"
  fi
  if [[ -n "${MARGIN_CSV:-}" ]]; then
    echo "corner,mos,cap,hbt,temp_c,rung,rref_ohm,itail_a,v_te_mean_v,v_tail_mean_v,vpp_diff_late_v,f_late_hz,osc_criterion_v,oscillates${rc}" > "${MARGIN_CSV}"
  fi
  if [[ -n "${MARGIN_SUM_CSV:-}" ]]; then
    echo "corner,mos,cap,hbt,temp_c,itail_nominal_a,itail_last_osc_a,itail_first_fail_a,margin_lower_bound,margin_upper_bound,row6_verdict,row6_bound,ngspice_rc,model_error${rc}" > "${MARGIN_SUM_CSV}"
  fi
}

# --------------------------------------------------------------------------
# osc_emit_tuning <mos> <cap> <hbt> <temp>
# Derive the row-2 tuning ratio and the row-3 Kvco curve for one PVT point
# from the f_osc(Vctrl) rows already in ${CSV_OUT}. Kvco is the FIRST
# DIFFERENCE of the measured f_osc between consecutive swept Vctrl points --
# the same finite-difference derivation sim/varactor-characterization applies
# to C(V), so the two studies' dC/dV and df/dV are comparable by
# construction. Linearity is reported as the peak-to-peak spread of the
# per-segment slopes as a percentage of their mean: 0 % would be a perfectly
# linear Kvco, and the number is meaningless (printed nan) with fewer than
# three segments.
#
# A PVT point with any non-oscillating Vctrl point gets its ratio computed
# over the points that DID oscillate, with n_points recording how many those
# were -- a partial curve is a finding, not a reason to drop the corner.
# --------------------------------------------------------------------------
#
# The fifth argument is the timestep ceiling whose rows count (default
# OSC_TMAX). It is not decoration: run_pilot_grid.sh re-runs one point at a
# coarser ceiling to measure the circuit solution's own discretization error,
# and without this filter that point would enter its own corner's tuning curve
# as a second, slightly different sample at the same Vctrl.
#
# The sixth argument is the EXPECTED Vctrl list (space-separated volts) and is
# required. A curve is graded only when it is COMPLETE: every expected voltage
# has exactly one row at this tmax and that row is PASS (voltages compared
# numerically; a row at an unexpected voltage also makes it incomplete). An
# incomplete curve -- e.g. the two endpoints oscillating while every interior
# point failed -- still reports its numbers from the surviving PASS points
# (n_points = PASS count) but row1/row2/row2_stretch read INCOMPLETE, the
# linearity is nan, and Kvco is written only for segments whose two voltages
# are adjacent in the expected list (never a slope across a gap). Fewer than
# two PASS points stays INSUFFICIENT. Column layout is unchanged.
osc_emit_tuning() {
  local mos="$1" cap="$2" hbt="$3" temp="$4" tmax="${5:-${OSC_TMAX}}"
  local vlist="${6:-}" rail="${7:-}"
  if [[ -z "${vlist// /}" ]]; then
    echo "osc_emit_tuning: expected Vctrl list (6th argument) is required" >&2
    return 2
  fi
  # Rail identity (issue #113). A CSV that carries a vsup_v column (stage 2)
  # holds rows from several rails, so the rail is a REQUIRED 7th argument and
  # rows of any other rail are excluded: a curve is never aggregated across
  # rails. A CSV without the column is single-rail by construction and must
  # not be given one.
  # The rail column is located by NAME: it trails the point columns, whose
  # count grew with the row-7 columns (#112), so no fixed index is assumed.
  local csv_has_rail=0 rail_col
  rail_col="$(head -1 "${CSV_OUT}" | awk -F, '{ for (i = 1; i <= NF; i++) if ($i == "vsup_v") { print i; exit } print 0 }')"
  [[ "${rail_col}" -gt 0 ]] && csv_has_rail=1
  if [[ "${csv_has_rail}" == 1 && -z "${rail}" ]]; then
    echo "osc_emit_tuning: ${CSV_OUT} has a vsup_v column; the rail (7th argument) is required to prevent mixed-rail aggregation" >&2
    return 2
  fi
  if [[ "${csv_has_rail}" == 0 && -n "${rail}" ]]; then
    echo "osc_emit_tuning: a rail was given but ${CSV_OUT} has no vsup_v column" >&2
    return 2
  fi
  awk -F, -v vlist="${vlist}" -v rail="${rail}" -v rc="${rail_col}" -v mos="${mos}" -v cap="${cap}" -v hbt="${hbt}" -v temp="${temp}" \
      -v tmax="${tmax}" \
      -v f1lo="${OSC_ROW1_F_MIN_HZ}" -v f1hi="${OSC_ROW1_F_MAX_HZ}" \
      -v r2="${OSC_ROW2_RATIO}" -v r2s="${OSC_ROW2_RATIO_STRETCH}" \
      -v kvco_csv="${KVCO_CSV:-/dev/null}" '
    function near(a, b,  d) { d = a - b; if (d < 0) d = -d; return d < 1e-9 }
    BEGIN { ne = split(vlist, ev, " "); rs = (rail == "") ? "" : "," rail }
    NR == 1 { next }
    $2 == mos && $3 == cap && $4 == hbt && $5 == temp && $7 == tmax && (rail == "" || near($rc, rail)) {
      x = $6 + 0; ix = 0
      for (e = 1; e <= ne; e++) { d = x - ev[e]; if (d < 0) d = -d; if (d < 1e-9) { ix = e; break } }
      if (ix == 0) unexpected = 1
      else rows[ix]++
      if ($8 == "PASS") {
        n++; v[n] = x; f[n] = $9 + 0; xi[n] = ix
        fl = $12 + 0; if (fl > worstfloor) worstfloor = fl
        if (ix > 0) passrows[ix]++
      }
    }
    END {
      complete = !unexpected
      for (e = 1; e <= ne; e++) if (rows[e] != 1 || passrows[e] != 1) complete = 0
      if (n < 2) {
        printf "%s,%s,%s,%s,%d,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,INSUFFICIENT,INSUFFICIENT,INSUFFICIENT%s\n", \
               mos, cap, hbt, temp, n, rs
        exit
      }
      # the rows arrive in the sweep order the caller used, which is
      # monotonic in Vctrl; sort defensively anyway
      for (i = 1; i <= n; i++) for (j = i+1; j <= n; j++) if (v[j] < v[i]) {
        tv = v[i]; v[i] = v[j]; v[j] = tv; tf = f[i]; f[i] = f[j]; f[j] = tf
        tx = xi[i]; xi[i] = xi[j]; xi[j] = tx
      }
      fmin = f[1]; fmax = f[1]; vmin = v[1]; vmax = v[1]
      for (i = 1; i <= n; i++) {
        if (f[i] < fmin) { fmin = f[i]; vmin = v[i] }
        if (f[i] > fmax) { fmax = f[i]; vmax = v[i] }
      }
      ratio = (fmin > 0) ? fmax / fmin : "nan"
      pct   = (fmin > 0) ? 100.0 * (fmax/fmin - 1) : "nan"
      fgeo  = sqrt(fmin * fmax)
      ksum = 0; kn = 0; kpk = ""; kmn = ""
      for (i = 1; i < n; i++) {
        dv = v[i+1] - v[i]
        if (dv == 0) continue
        if (!complete && !(xi[i] > 0 && xi[i+1] == xi[i] + 1 && rows[xi[i]] == 1 && rows[xi[i+1]] == 1)) continue
        k = (f[i+1] - f[i]) / dv
        kn++; ksum += k
        ak = (k < 0) ? -k : k
        if (kpk == "" || ak > apk) { apk = ak; kpk = k }
        if (kmn == "" || ak < amn) { amn = ak; kmn = k }
        printf "%s,%s,%s,%s,%.6g,%.6g,%.6g,%.6e,%.6e,%.6e%s\n", \
               mos, cap, hbt, temp, v[i], v[i+1], 0.5*(v[i]+v[i+1]), \
               f[i], f[i+1], k, rs >> kvco_csv
      }
      kmean = (kn > 0) ? ksum / kn : "nan"
      lin = "nan"
      if (complete && kn >= 3 && kmean != 0) {
        lo = ""; hi = ""
        # recompute the slope spread; kpk/kmn are by |k|, the spread is signed
        for (i = 1; i < n; i++) {
          dv = v[i+1] - v[i]; if (dv == 0) continue
          k = (f[i+1] - f[i]) / dv
          if (lo == "" || k < lo) lo = k
          if (hi == "" || k > hi) hi = k
        }
        am = (kmean < 0) ? -kmean : kmean
        lin = 100.0 * (hi - lo) / am
      }
      row1 = (fmin >= f1lo && fmax <= f1hi) ? "BOTH ENDPOINTS INSIDE" : "AN ENDPOINT OUTSIDE"
      row2 = "NOT MET"; row2s = "NOT MET"
      if (ratio != "nan") {
        # a ratio inside the quantization floor of its bound is not a pass
        floorfrac = worstfloor / 100.0
        if (ratio >= r2 * (1 + floorfrac))      row2 = "MET"
        else if (ratio >= r2 * (1 - floorfrac)) row2 = "WITHIN QUANTIZATION FLOOR OF BOUND"
        if (ratio >= r2s * (1 + floorfrac))      row2s = "MET"
        else if (ratio >= r2s * (1 - floorfrac)) row2s = "WITHIN QUANTIZATION FLOOR OF BOUND"
      }
      if (!complete) { row1 = "INCOMPLETE"; row2 = "INCOMPLETE"; row2s = "INCOMPLETE" }
      printf "%s,%s,%s,%s,%d,%.6e,%.6e,%.6g,%.6g,%.6f,%.4f,%.6e,%.6e,%.6e,%.6e,%s,%.6g,%s,%s,%s%s\n", \
             mos, cap, hbt, temp, n, fmin, fmax, vmin, vmax, ratio, pct, fgeo, \
             kmean, kpk, kmn, lin, worstfloor, row1, row2, row2s, rs
    }' "${CSV_OUT}" >> "${TUNING_CSV}"
}

# --------------------------------------------------------------------------
# osc_row3_header / osc_emit_row3 <mos> <cap> <hbt> <temp> <tmax> <vlist>
# The RATIFIED row-3 grade (spec/target-spec.md row 3, DR-004 Row 3) for one
# PVT point, appended to ${ROW3_CSV} (no-op when unset). Over the window
# W = [OSC_ROW3_V_LO, OSC_ROW3_V_HI]:
#   (1) Kvco single-signed at every window segment (zero slope is not signed);
#   (2) f(V_LO)-f(V_HI) >= 90 % of the SAME corner's f(0.0)-f(V_HI);
#   (3) |Kvco|_mean = (f(V_LO)-f(V_HI))/(V_HI-V_LO) >= 381 MHz/V;
#   (4) chord (integral) nonlinearity, 100*max|f-chord|/|f(V_HI)-f(V_LO)|,
#       chord joining the window endpoints, <= 30 % target / 20 % stretch,
#       graded on >= 5 window samples including both endpoints.
# There is no stretch bound on (1)-(3); the stretch verdict is the target
# verdict AND the 20 % chord bound. The older kvco_linearity_pct (segment
# spread) in the tuning CSV is an ungraded descriptor and is not used here.
#
# Verdict values: MET, NOT MET, or INCOMPLETE. INCOMPLETE (never a pass) when
# the window/full-domain data cannot be graded: an expected Vctrl missing,
# duplicated, non-PASS or with an INVALID measurement (meas_status), an
# unexpected voltage, a list lacking the window endpoints or 0.0 V, fewer than
# 5 window samples, or a zero/negative full-domain span. Only rows at the
# given tmax count (as in osc_emit_tuning).
# --------------------------------------------------------------------------
osc_row3_header() {
  echo "mos,cap,hbt,temp_c,v_lo,v_hi,n_window_samples,f_full_lo_v_hz,f_lo_hz,f_hi_hz,full_span_hz,window_span_hz,coverage_pct,kvco_mean_hz_per_v,chord_inl_pct,req1_single_signed,req2_coverage,req3_mean_slope,req4_chord_target,req4_chord_stretch,row3_target_verdict,row3_stretch_verdict,reason"
}
osc_emit_row3() {
  [[ -n "${ROW3_CSV:-}" ]] || return 0
  local mos="$1" cap="$2" hbt="$3" temp="$4" tmax="${5:-${OSC_TMAX}}"
  local vlist="${6:-}"
  if [[ -z "${vlist// /}" ]]; then
    echo "osc_emit_row3: expected Vctrl list (6th argument) is required" >&2
    return 2
  fi
  awk -F, -v vlist="${vlist}" -v mos="${mos}" -v cap="${cap}" -v hbt="${hbt}" -v temp="${temp}" \
      -v tmax="${tmax}" -v vlo="${OSC_ROW3_V_LO}" -v vhi="${OSC_ROW3_V_HI}" -v vfull="${OSC_ROW3_V_FULL_LO}" \
      -v covmin="${OSC_ROW3_COVERAGE_MIN}" -v kmin="${OSC_ROW3_KVCO_MEAN_MIN_HZ_PER_V}" \
      -v inl="${OSC_ROW3_CHORD_INL_PCT}" -v inls="${OSC_ROW3_CHORD_INL_PCT_STRETCH}" \
      -v minn="${OSC_ROW3_MIN_SAMPLES}" '
    function abs(x) { return x < 0 ? -x : x }
    function near(a, b) { return abs(a - b) < 1e-9 }
    BEGIN { ne = split(vlist, ev, " ") }
    NR == 1 { next }
    $2 == mos && $3 == cap && $4 == hbt && $5 == temp && $7 == tmax {
      x = $6 + 0; ix = 0
      for (e = 1; e <= ne; e++) if (near(x, ev[e] + 0)) { ix = e; break }
      if (ix == 0) { unexpected = 1; next }
      rows[ix]++
      ok = ($8 == "PASS" && $9 ~ /^[-+]?[0-9.]+([eE][-+]?[0-9]+)?$/ && ($9 + 0) > 0)
      if (NF >= 28 && $28 != "VALID") ok = 0
      if (ok) { good[ix] = 1; fv[ix] = $9 + 0 } else bad[ix] = 1
    }
    function emit(reason, n, f0, flo, fhi, fs, ws, cov, km, ci, r1, r2, r3, r4, r4s, vt, vs) {
      printf "%s,%s,%s,%s,%s,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", \
             mos, cap, hbt, temp, vlo, vhi, n, f0, flo, fhi, fs, ws, cov, km, ci, r1, r2, r3, r4, r4s, vt, vs, reason
    }
    END {
      # window members: expected voltages inside [vlo, vhi], ascending
      nw = 0; ilo = 0; ihi = 0; ifull = 0
      for (e = 1; e <= ne; e++) {
        x = ev[e] + 0
        if (near(x, vlo + 0)) ilo = e
        if (near(x, vhi + 0)) ihi = e
        if (near(x, vfull + 0)) ifull = e
        if (x > vlo - 1e-9 && x < vhi + 1e-9) { nw++; wi[nw] = e }
      }
      for (i = 1; i <= nw; i++) for (j = i + 1; j <= nw; j++)
        if (ev[wi[j]] + 0 < ev[wi[i]] + 0) { t = wi[i]; wi[i] = wi[j]; wi[j] = t }
      INC = "INCOMPLETE"
      reason = ""
      if (!ilo || !ihi) reason = "window endpoint not in the expected Vctrl list"
      else if (!ifull) reason = "full-domain 0.0 V not in the expected Vctrl list"
      else if (nw < minn) reason = "fewer than " minn " window samples (" nw ")"
      else if (unexpected) reason = "row at an unexpected Vctrl"
      else {
        for (e = 1; e <= ne; e++) if (rows[e] > 1) { reason = "duplicate rows at Vctrl " ev[e]; break }
        if (reason == "") for (i = 1; i <= nw; i++) if (!good[wi[i]]) { reason = "window point " ev[wi[i]] " V missing, not PASS or INVALID measurement"; break }
        if (reason == "" && !good[ifull]) reason = "full-domain point " ev[ifull] " V missing, not PASS or INVALID measurement"
      }
      if (reason != "") {
        emit(reason, nw, "nan","nan","nan","nan","nan","nan","nan","nan", INC,INC,INC,INC,INC, INC, INC)
        exit
      }
      flo = fv[ilo]; fhi = fv[ihi]; f0 = fv[ifull]
      fs = f0 - fhi; ws = flo - fhi
      if (fs <= 0) {
        emit("zero or negative full-domain span", nw, f0, flo, fhi, fs, ws, "nan","nan","nan", INC,INC,INC,INC,INC, INC, INC)
        exit
      }
      dvw = (vhi + 0) - (vlo + 0)
      # (1) single-signed segment slopes
      npos = 0; nneg = 0; nzero = 0
      for (i = 1; i < nw; i++) {
        k = (fv[wi[i+1]] - fv[wi[i]]) / ((ev[wi[i+1]] + 0) - (ev[wi[i]] + 0))
        if (k > 0) npos++; else if (k < 0) nneg++; else nzero++
      }
      r1 = (nzero == 0 && (npos == 0 || nneg == 0)) ? "MET" : "NOT MET"
      # (2) coverage, (3) mean slope
      cov = 100.0 * ws / fs
      r2 = (ws >= covmin * fs) ? "MET" : "NOT MET"
      km = ws / dvw
      r3 = (km >= kmin + 0) ? "MET" : "NOT MET"
      # (4) chord nonlinearity
      if (ws == 0) { ci = "nan"; r4 = "NOT MET"; r4s = "NOT MET" }
      else {
        mx = 0
        for (i = 1; i <= nw; i++) {
          x = ev[wi[i]] + 0
          ch = flo + (fhi - flo) * (x - (vlo + 0)) / dvw
          d = abs(fv[wi[i]] - ch); if (d > mx) mx = d
        }
        ci = 100.0 * mx / abs(fhi - flo)
        r4 = (ci <= inl + 0) ? "MET" : "NOT MET"
        r4s = (ci <= inls + 0) ? "MET" : "NOT MET"
      }
      vt = (r1 == "MET" && r2 == "MET" && r3 == "MET" && r4 == "MET") ? "MET" : "NOT MET"
      vs = (vt == "MET" && r4s == "MET") ? "MET" : "NOT MET"
      printf "%s,%s,%s,%s,%s,%s,%d,%.6e,%.6e,%.6e,%.6e,%.6e,%.4f,%.6e,%s,%s,%s,%s,%s,%s,%s,%s,-\n", \
             mos, cap, hbt, temp, vlo, vhi, nw, f0, flo, fhi, fs, ws, cov, km, \
             (ci == "nan" ? "nan" : sprintf("%.4f", ci)), r1, r2, r3, r4, r4s, vt, vs
    }' "${CSV_OUT}" >> "${ROW3_CSV}"
}

# --------------------------------------------------------------------------
# Row 7 (RATIFIED per DR-004 (d) and (e), spec/target-spec.md row 7; issue
# #112): output swing and the cycle-minimum HBT compliance condition.
#
# THE INEQUALITY AND ITS ASSUMPTIONS (DR-004 (e), copied, not re-derived):
#   VCE_max = (VDD + Vpp_diff/4) - V(TAIL)_min  <=  BVCEO(min) = 2.2 V
# evaluated per simulated point with THAT point's own quantities:
#   * VDD        the sampled max of V(VDD) over the settled window (the
#                point's actual rail, not the 3.3 V nominal constant);
#   * Vpp_diff   vpp_diff_v (column 14), sampled max-min of V(OUTP)-V(OUTN);
#   * V(TAIL)_min the sampled INSTANTANEOUS minimum of V(TAIL) over the
#                settled window (column 30) -- NOT v_tail_dc_op_v and NOT
#                v_tail_mean_v, which DR-004 names as stand-ins.
# The formula's own assumptions, which this bench does not test: each tank
# node swings +/- Vpp_diff/4 about VDD (a differential, rail-centred swing --
# the per-point vpp_cm_over_diff column is the evidence for that premise);
# the pair emitters sit at TAIL (true in design/vco.spice: XQ1/XQ2 emitters
# are on TAIL with no degeneration); and the collector peak and the tail
# minimum are combined as if simultaneous, which over-states the true peak
# VCE (conservative). BVCEO is the base-open rating; the driven-base pair is
# rated higher (conservative). The tail device XQ3's own VCE is NOT covered.
#
# SAMPLING LIMIT, stated with every number: both extremes are SAMPLES of an
# adaptive-timestep trace (osc_trace_extrema), so the sampled V(TAIL)_min can
# sit ABOVE the true minimum and the sampled vpp_diff BELOW the true one --
# both errors make VCE_max look smaller than it is. osc_row7_point bounds each
# under a locally-sinusoidal assumption, A*(1-cos(pi*f*dt_max)): the tail at
# f = max(f_tail, 2*f_osc) with A = half its ripple peak-to-peak, the
# differential output at f_osc with A = vpp_diff/2 per extreme. vce_max_upper_v
# carries both bounds against the inequality. A compliance pass needs the
# UPPER value <= 2.2 V; a measured value under the limit whose upper value is
# not is WITHIN SAMPLING BOUND, which is NOT a pass. For swing the sampling
# error is in the safe direction (a sampled pk-pk can only under-read), so the
# swing verdict uses the measured vpp_diff directly. A cusp sharper than a
# sinusoid at the stated f can hide more than the bound: a stated limit.
# --------------------------------------------------------------------------
# shellcheck disable=SC2016  # awk source, expanded by awk, not by the shell
OSC_ROW7_AWK_LIB='
function r7_num(x) { return x ~ /^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$/ }
function r7_vce(vdd, vpp, vtmin) { return vdd + vpp / 4.0 - vtmin }
function r7_sample_err(halfpp, f, dt,   s) {
  if (halfpp + 0 == 0) return 0
  if (f + 0 <= 0 || dt + 0 < 0) return "nan"
  s = sin(3.141592653589793 * f * dt / 2.0)
  return halfpp * 2.0 * s * s
}
'

# osc_row7_point <vpp_diff> <f_osc> <dt_max> <vpp_tail> <f_tail> <dt_tail> <v_tail_min> <vdd>
# Print "vpp_diff_err_v v_tail_min_err_v vce_max_v vce_max_upper_v" for one
# point. Any non-numeric input that a value depends on makes that value nan.
osc_row7_point() {
  awk -v vpp="$1" -v fo="$2" -v dt="$3" -v vtp="$4" -v ft="$5" -v dtt="$6" \
      -v vtm="$7" -v vdd="$8" "${OSC_ROW7_AWK_LIB}"'
    function fmt(x) { return (x == "nan") ? "nan" : sprintf("%.6e", x) }
    BEGIN {
      ev = "nan"; et = "nan"; vce = "nan"; vup = "nan"
      if (r7_num(vpp) && r7_num(fo) && r7_num(dt)) ev = r7_sample_err(vpp, fo, dt)
      if (r7_num(vtp) && r7_num(dtt)) {
        fb = 0
        if (r7_num(ft) && ft + 0 > fb) fb = ft + 0
        if (r7_num(fo) && 2 * fo > fb) fb = 2 * fo
        et = r7_sample_err(vtp / 2.0, fb, dtt)
      }
      if (r7_num(vpp) && r7_num(vtm) && r7_num(vdd)) {
        vce = r7_vce(vdd, vpp, vtm)
        if (ev != "nan" && et != "nan") vup = r7_vce(vdd, vpp + ev, vtm - et)
      }
      printf "%s %s %s %s\n", fmt(ev), fmt(et), fmt(vce), fmt(vup)
    }'
}

# --------------------------------------------------------------------------
# osc_row7_header / osc_emit_row7 <mos> <cap> <hbt> <temp> <tmax> <vlist> [rail]
# The row-7 grade for one PVT point, appended to ${ROW7_CSV} (no-op when
# unset, so pilots grade nothing). Reads the rows already in ${CSV_OUT}.
#   swing      Vpp_diff >= 0.40 V target / 0.65 V stretch at EVERY expected
#              Vctrl in the row-3 window W = [OSC_ROW3_V_LO, OSC_ROW3_V_HI]
#              ("everywhere in W", DR-004 (d)), sampled on >= 5 window points
#              including both endpoints. A NOSC point in W is a measured swing
#              failure (NOT MET), never a pass.
#   compliance VCE_max upper value <= 2.2 V at EVERY expected Vctrl of the
#              full domain, not only W: DR-004 (e) states it per bound corner
#              without a window, and the largest swing (the worst case) sits
#              outside W at Vctrl = 0.0 V. One stretch-free bound.
# Verdicts: MET, NOT MET, WITHIN SAMPLING BOUND (compliance only; not a pass),
# or INCOMPLETE (never a pass): an expected Vctrl missing, duplicated, at a
# non-PASS/NOSC status, with an INVALID measurement, from a pre-row-7
# 29-column record, or with a non-numeric swing/tail-minimum/VDD; a row at an
# unexpected Vctrl; a list lacking either window endpoint or with fewer than 5
# window samples. A point whose sampling bound cannot be formed (only possible
# when it did not oscillate) leaves compliance INCOMPLETE unless another point
# is already NOT MET. target = swing target AND compliance; stretch = swing
# stretch AND compliance. Only rows at the given tmax count.
#
# RAIL IDENTITY (issue #119, DR-004 stage 2). The optional 7th argument is the
# rail in volts, exactly as for osc_emit_tuning: a points CSV that carries a
# vsup_v column (stage 2, OSC_CSV_RAIL=1) holds rows of BOTH supply rails for
# the same process/temperature/Vctrl identity, so the rail is then REQUIRED and
# only that rail's rows are graded (otherwise every expected Vctrl would be
# counted twice); a CSV without the column is single-rail by construction and
# must not be given one. The rail is appended to the grade line as a trailing
# vsup_v column, which osc_row7_header declares when OSC_CSV_RAIL=1. Nominal
# callers (run_pvt_sweep.sh) pass no rail and produce byte-identical output.
# --------------------------------------------------------------------------
osc_row7_header() {
  local rc=""
  [[ "${OSC_CSV_RAIL:-0}" == "1" ]] && rc=",vsup_v"
  echo "mos,cap,hbt,temp_c,v_lo,v_hi,n_domain_points,n_window_samples,vpp_diff_min_window_v,vctrl_at_vpp_min_v,vce_max_v,vce_max_upper_v,vctrl_at_vce_max_upper_v,vdd_at_vce_max_v,vpp_diff_at_vce_max_v,v_tail_min_at_vce_max_v,v_tail_mean_at_vce_max_v,v_tail_dc_op_at_vce_max_v,swing_target,swing_stretch,compliance,row7_target_verdict,row7_stretch_verdict,reason${rc}"
}
osc_emit_row7() {
  [[ -n "${ROW7_CSV:-}" ]] || return 0
  local mos="$1" cap="$2" hbt="$3" temp="$4" tmax="${5:-${OSC_TMAX}}"
  local vlist="${6:-}" rail="${7:-}"
  if [[ -z "${vlist// /}" ]]; then
    echo "osc_emit_row7: expected Vctrl list (6th argument) is required" >&2
    return 2
  fi
  local rail_col
  rail_col="$(head -1 "${CSV_OUT}" | awk -F, '{ for (i = 1; i <= NF; i++) if ($i == "vsup_v") { print i; exit } print 0 }')"
  if [[ "${rail_col:-0}" -gt 0 && -z "${rail}" ]]; then
    echo "osc_emit_row7: ${CSV_OUT} has a vsup_v column; the rail (7th argument) is required to prevent mixed-rail aggregation" >&2
    return 2
  fi
  if [[ "${rail_col:-0}" -eq 0 && -n "${rail}" ]]; then
    echo "osc_emit_row7: a rail was given but ${CSV_OUT} has no vsup_v column" >&2
    return 2
  fi
  awk -F, -v vlist="${vlist}" -v rail="${rail}" -v rc="${rail_col:-0}" \
      -v mos="${mos}" -v cap="${cap}" -v hbt="${hbt}" -v temp="${temp}" \
      -v tmax="${tmax}" -v vlo="${OSC_ROW3_V_LO}" -v vhi="${OSC_ROW3_V_HI}" \
      -v vt="${OSC_ROW7_VPP_MIN_V}" -v vs="${OSC_ROW7_VPP_MIN_STRETCH_V}" \
      -v bv="${OSC_ROW7_BVCEO_MIN_V}" -v minn="${OSC_ROW7_MIN_WINDOW_SAMPLES}" \
      "${OSC_ROW7_AWK_LIB}"'
    function abs(x) { return x < 0 ? -x : x }
    function near(a, b) { return abs(a - b) < 1e-9 }
    function and3(a, b) {
      if (a == "NOT MET" || b == "NOT MET") return "NOT MET"
      if (a == "MET" && b == "MET") return "MET"
      if (a == "INCOMPLETE" || b == "INCOMPLETE") return "INCOMPLETE"
      return b
    }
    function emit(reason, nd, nw, a, b, c, d, e, f, g, h, i, j, s1, s2, cp, tg, sg) {
      printf "%s,%s,%s,%s,%s,%s,%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s%s\n", \
             mos, cap, hbt, temp, vlo, vhi, nd, nw, a, b, c, d, e, f, g, h, i, j, s1, s2, cp, tg, sg, reason, rs
    }
    function g6(x) { return r7_num(x) ? sprintf("%.6g", x) : "nan" }
    BEGIN { ne = split(vlist, ev, " "); rc += 0; rs = (rail == "") ? "" : "," rail }
    NR == 1 { next }
    $2 == mos && $3 == cap && $4 == hbt && $5 == temp && $7 == tmax && (rc == 0 || near($rc, rail)) {
      x = $6 + 0; ix = 0
      for (e = 1; e <= ne; e++) if (near(x, ev[e] + 0)) { ix = e; break }
      if (ix == 0) { unexpected = 1; next }
      rows[ix]++
      # 37 point columns, plus the trailing rail column when there is one
      if (NF < 37 + (rc > 0) || (rc > 0 && rc < 38)) { why[ix] = "row predates the row-7 columns (" NF " columns)"; next }
      if ($28 != "VALID") { why[ix] = "INVALID measurement (" $29 ")"; next }
      if ($8 != "PASS" && $8 != "NOSC") { why[ix] = "status " $8; next }
      if (!r7_num($14) || !r7_num($30) || !r7_num($35)) { why[ix] = "swing, tail minimum or VDD is not a number"; next }
      good[ix] = 1; st[ix] = $8
      vpp[ix] = $14 + 0; vtm[ix] = $30 + 0; vdd[ix] = $35 + 0
      tmean[ix] = $23; top[ix] = $22
      vce[ix] = r7_vce(vdd[ix], vpp[ix], vtm[ix])
      if (r7_num($33) && r7_num($34)) { cok[ix] = 1; vup[ix] = r7_vce(vdd[ix], vpp[ix] + $34, vtm[ix] - $33) }
      else cok[ix] = 0
    }
    END {
      nw = 0; ilo = 0; ihi = 0
      for (e = 1; e <= ne; e++) {
        x = ev[e] + 0
        if (near(x, vlo + 0)) ilo = e
        if (near(x, vhi + 0)) ihi = e
        if (x > vlo - 1e-9 && x < vhi + 1e-9) { nw++; inw[e] = 1 }
      }
      INC = "INCOMPLETE"; reason = ""
      if (!ilo || !ihi) reason = "window endpoint not in the expected Vctrl list"
      else if (nw < minn) reason = "fewer than " minn " window samples (" nw ")"
      else if (unexpected) reason = "row at an unexpected Vctrl"
      else {
        for (e = 1; e <= ne; e++) if (rows[e] > 1) { reason = "duplicate rows at Vctrl " ev[e]; break }
        if (reason == "") for (e = 1; e <= ne; e++) if (!good[e]) {
          reason = "Vctrl " ev[e] " V: " (rows[e] == 0 ? "missing" : why[e]); break
        }
      }
      if (reason != "") {
        emit(reason, ne, nw, "nan","nan","nan","nan","nan","nan","nan","nan","nan","nan", INC, INC, INC, INC, INC)
        exit
      }
      # swing over W
      vmin = ""; nosc = ""
      for (e = 1; e <= ne; e++) if (inw[e]) {
        if (vmin == "" || vpp[e] < vmin) { vmin = vpp[e]; vatmin = ev[e] }
        if (st[e] == "NOSC" && nosc == "") nosc = ev[e]
      }
      s1 = (nosc == "" && vmin >= vt + 0) ? "MET" : "NOT MET"
      s2 = (nosc == "" && vmin >= vs + 0) ? "MET" : "NOT MET"
      # compliance over the full expected domain
      over = 0; unb = 0; mx = ""; mxu = ""; iw = 0
      for (e = 1; e <= ne; e++) {
        if (vce[e] > bv + 0) over = 1
        if (mx == "" || vce[e] > mx) mx = vce[e]
        if (!cok[e]) { unb = 1; continue }
        if (mxu == "" || vup[e] > mxu) { mxu = vup[e]; iw = e }
      }
      if (over) cp = "NOT MET"
      else if (unb) cp = INC
      else if (mxu <= bv + 0) cp = "MET"
      else cp = "WITHIN SAMPLING BOUND"
      t = and3(s1, cp); stv = and3(s2, cp)
      note = "-"
      if (nosc != "") note = "Vctrl " nosc " V in W did not oscillate (NOSC)"
      else if (unb) note = "a non-oscillating point has no sampling bound"
      if (iw) emit(note, ne, nw, sprintf("%.6g", vmin), vatmin, sprintf("%.6g", mx), sprintf("%.6g", mxu), ev[iw], \
                   sprintf("%.6g", vdd[iw]), sprintf("%.6g", vpp[iw]), sprintf("%.6g", vtm[iw]), g6(tmean[iw]), g6(top[iw]), s1, s2, cp, t, stv)
      else emit(note, ne, nw, sprintf("%.6g", vmin), vatmin, sprintf("%.6g", mx), "nan", "nan", "nan", "nan", "nan", "nan", "nan", s1, s2, cp, t, stv)
    }' "${CSV_OUT}" >> "${ROW7_CSV}"
}

# Row 3 global verdict over the declared grid. Args: <row3 csv> <required keys>
# where keys are space-separated "mos:cap:hbt:temp" identities derived from the
# declared axes. Row-3 CSV contract (osc_row3_header): columns 1-4 are the
# identity (mos,cap,hbt,temp_c), 21/22 are the target/stretch verdicts. The
# header is validated; every required identity must occur exactly once, with
# no unexpected key and no INCOMPLETE grade, or the row is NOT GRADED. A line
# count alone cannot establish coverage (135 copies of one corner).
osc_row3_summary() {
  local csv="$1" req="${2:-}"
  if [[ ! -f "${csv}" ]]; then echo "NOT GRADED: no row-3 CSV"; return 0; fi
  if [[ "$(head -1 "${csv}")" != "$(osc_row3_header)" ]]; then
    echo "NOT GRADED: row-3 CSV header does not match osc_row3_header; the column contract (mos,cap,hbt,temp_c key; verdicts in columns 21-22) cannot be trusted"
    return 0
  fi
  awk -F, -v req="${req}" '
    BEGIN { nr = split(req, rq, " "); for (i = 1; i <= nr; i++) isreq[rq[i]] = 1 }
    NR == 1 { next }
    {
      k = $1 ":" $2 ":" $3 ":" $4; cnt[k]++; tv[k] = $21; sv[k] = $22; ws[k] = $7
      if (!(k in isreq)) { unx++; if (ux == "") ux = k }
    }
    END {
      if (nr == 0) { print "NOT GRADED: no required row-3 corners declared"; exit }
      miss = 0; dup = 0; inc = 0; t = 0; s = 0; ns = ""
      for (i = 1; i <= nr; i++) {
        k = rq[i]
        if (cnt[k] == 0) { miss++; if (mk == "") mk = k; continue }
        if (cnt[k] > 1) { dup++; if (dk == "") dk = k; continue }
        if (tv[k] != "MET" && tv[k] != "NOT MET") { inc++; continue }
        if (sv[k] != "MET" && sv[k] != "NOT MET") { inc++; continue }
        if (tv[k] == "MET") t++
        if (sv[k] == "MET") s++
        if (ns == "" || ws[k] + 0 < ns) ns = ws[k] + 0
      }
      if (miss + dup + inc + unx > 0) {
        printf "NOT GRADED (partial): %d/%d required corners graded, %d missing%s, %d duplicated%s, %d INCOMPLETE, %d unexpected%s; per-corner lines are evidence only, no global verdict\n", \
               nr - miss - dup - inc, nr, miss, (miss ? " (e.g. " mk ")" : ""), dup, (dup ? " (e.g. " dk ")" : ""), inc, unx + 0, (unx ? " (e.g. " ux ")" : "")
        exit
      }
      printf "%s: target MET at %d/%d corners, stretch MET at %d/%d corners (min window samples %d)\n", \
             (t == nr ? (s == nr ? "MET (target and stretch)" : "MET (target); stretch NOT MET") : "NOT MET"), t, nr, s, nr, ns
    }' "${csv}"
}

# --------------------------------------------------------------------------
# osc_row7_summary <row7-csv> <required corners>
# One-line global row-7 verdict over a DECLARED set of required corners,
# given as space-separated mos:cap:hbt:temp tokens (run_pvt_sweep.sh passes
# the row-10 bound-corner set). Graded only when every required corner has
# exactly one non-INCOMPLETE line; otherwise NOT GRADED (partial) with counts.
# Corners in the CSV outside the required set are reported as descriptors and
# never rescue a missing required one.
#
# Even a complete pass is reported as "STAGE-1 MET", never a bare MET: the
# DR-004 stage-2 supply sub-corners ({2.970, 3.630} V x SLOW/TYP/FAST x T) are
# part of row 7's coverage. They are graded per rail by this file's
# osc_emit_row7 (run_supply_stage2.sh) and compared with the matching nominal
# corner by report_supply_stage2.sh (issue #119), not by this nominal-rail
# summary, so row 7 is not fully covered by a stage-1 pass alone. A rail-tagged
# (stage-2) row-7 CSV is refused here: its two rails share a corner key.
# --------------------------------------------------------------------------
osc_row7_summary() {
  local csv="$1" req="${2:-}"
  if [[ ! -f "${csv}" ]]; then echo "NOT GRADED: no row-7 CSV"; return 0; fi
  if head -1 "${csv}" | tr ',' '\n' | grep -qx vsup_v; then
    echo "NOT GRADED: rail-tagged (stage-2) row-7 CSV; per-rail results are compared by report_supply_stage2.sh"
    return 0
  fi
  awk -F, -v req="${req}" '
    BEGIN { nr = split(req, rq, " "); for (i = 1; i <= nr; i++) isreq[rq[i]] = 1 }
    NR == 1 { next }
    {
      k = $1 ":" $2 ":" $3 ":" $4; cnt[k]++
      tv[k] = $22; sv[k] = $23; cv[k] = $21; up[k] = $12; vm[k] = $9
      if (!(k in isreq)) { nx++; if ($22 != "MET") nxbad++ }
    }
    END {
      tail = "; stage-2 +/-10 % supply sub-corners NOT graded here -- row 7 is not fully covered until report_supply_stage2.sh compares them"
      if (nr == 0) { print "NOT GRADED: no required bound corners declared" tail; exit }
      miss = 0; dup = 0; inc = 0; t = 0; s = 0; cm = 0; cw = 0; worst = ""; vmin = ""
      for (i = 1; i <= nr; i++) {
        k = rq[i]
        if (cnt[k] == 0) { miss++; continue }
        if (cnt[k] > 1) { dup++; continue }
        if (tv[k] == "INCOMPLETE" || sv[k] == "INCOMPLETE" || cv[k] == "INCOMPLETE") { inc++; continue }
        if (tv[k] == "MET") t++
        if (sv[k] == "MET") s++
        if (cv[k] == "MET") cm++; else if (cv[k] ~ /SAMPLING/) cw++
        if (up[k] != "nan" && (worst == "" || up[k] + 0 > worst + 0)) { worst = up[k]; wk = k }
        if (vm[k] != "nan" && (vmin == "" || vm[k] + 0 < vmin + 0)) { vmin = vm[k]; vk = k }
      }
      ex = (nx > 0) ? sprintf("; %d further non-required corner(s) graded as descriptors, %d not target-MET", nx, nxbad) : ""
      if (miss + dup + inc > 0) {
        printf "NOT GRADED (partial): %d/%d required corners graded, %d missing, %d duplicated, %d INCOMPLETE; per-corner lines are evidence only%s%s\n", \
               nr - miss - dup - inc, nr, miss, dup, inc, ex, tail
        exit
      }
      lab = (t == nr) ? ((s == nr) ? "STAGE-1 MET (target and stretch)" : "STAGE-1 MET (target); stretch NOT MET") : "NOT MET"
      printf "%s: target MET at %d/%d, stretch MET at %d/%d, compliance MET at %d/%d (%d within sampling bound, not a pass); min window Vpp_diff %s V at %s; worst VCE_max upper %s V at %s%s%s\n", \
             lab, t, nr, s, nr, cm, nr, cw, vmin, vk, worst, wk, ex, tail
    }' "${csv}"
}
