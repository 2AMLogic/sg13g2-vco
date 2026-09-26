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
OSC_ROW6_MARGIN="3.0"
# shellcheck disable=SC2034  # read by the run_*.sh that source this file
OSC_ROW8_P_MAX_W="10e-3"

# --------------------------------------------------------------------------
# osc_preflight
# Resolve and validate everything a PDK-dependent run needs, in the order
# that produces the clearest message when one is missing. Sets the globals
# OSC_IND_MODEL, OSC_OSDI_MOSVAR, OSC_NGSPICE_VERSION, OSC_VCO_BODY,
# OSC_RREF_NOM_OHM, OSC_RTE_OHM. Requires EXPERIMENT_DIR / SIM_DIR /
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

  if ! grep -q '^\*\*\*\* begin user architecture code' "${src}"; then
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
  ' "${src}" > "${out}"

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

  sed \
    -e "s|@@RECORD_ID@@|${RECORD_ID}|g" \
    -e "s|@@CORNER_ID@@|${corner_id}|g" \
    -e "s|@@MODELS_DIR@@|${SG13G2_NGSPICE_MODELS}|g" \
    -e "s|@@IND_MODEL@@|${OSC_IND_MODEL}|g" \
    -e "s|@@OSDI_MOSVAR@@|${OSC_OSDI_MOSVAR}|g" \
    -e "s|@@VDD_NOM@@|${OSC_VDD_NOM}|g" \
    -e "s|@@IC_OUTP@@|${OSC_IC_OUTP}|g" \
    -e "s|@@IC_OUTN@@|${OSC_IC_OUTN}|g" \
    -e "s|@@IC_DIFF_MV@@|${OSC_IC_DIFF_MV}|g" \
    -e "s|@@TSTEP@@|${OSC_TSTEP}|g" \
    -e "s|@@TSTOP@@|${OSC_TSTOP}|g" \
    -e "s|@@TMEAS_START@@|${OSC_TMEAS_START}|g" \
    -e "s|@@SETTLE_FRAC@@|${OSC_SETTLE_FRAC}|g" \
    -e "s|@@OSC_CRIT_MULT@@|${OSC_OSC_CRIT_MULT}|g" \
    "$@" \
    "${tmpl}" > "${out}.pre"

  awk -v body="${OSC_VCO_BODY}" '
    /^@@VCO_BODY@@[[:space:]]*$/ { while ((getline line < body) > 0) print line; next }
    { print }
  ' "${out}.pre" > "${out}"
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
# the exit status alone is not a verdict -- the log is grepped for the
# model-resolution failures explicitly, the same patterns
# design/run_elaborate.sh uses.
# --------------------------------------------------------------------------
osc_run_ngspice() {
  local netlist="$1" log="$2" rc=0 model_error=0
  ( cd "${WORKDIR}" && ngspice -b "${netlist}" ) > "${log}" 2>&1 || rc=$?
  if grep -qiE "unknown subckt|could not find a valid modelname|Unable to find definition of model|no such device or model name" "${log}"; then
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
#   isup_dc_op_a,isup_ls_avg_a,p_core_dc_op_w,p_core_ls_w
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

  local status=FAIL
  local f_osc=0 cycles=0 dtmax=0 vpp_d=0
  local f_cm=0 vpp_cm=0 f_tail=0 vtail_mean=0 isup_avg=0
  local t_settle=nan
  local floor_i=nan floor_c=nan

  if [[ -f "${d_vdiff}" ]]; then
    read -r f_osc vpp_d cycles _mean_d _tx1 _tx2 dtmax _ns \
      <<<"$(osc_metrics "${d_vdiff}" "${OSC_TMEAS_START}")"
    read -r t_settle _vppf _nextrema \
      <<<"$(osc_settle "${d_vdiff}" "${OSC_SETTLE_FRAC}" "${OSC_SETTLE_REF}")"
    read -r floor_i floor_c <<<"$(osc_quant_floor_pct "${f_osc}" "${cycles}" "${dtmax}")"
  fi
  if [[ -f "${d_vcm}" ]]; then
    read -r f_cm vpp_cm _c _m _a _b _d _n \
      <<<"$(osc_metrics "${d_vcm}" "${OSC_TMEAS_START}")"
  fi
  if [[ -f "${d_vtail}" ]]; then
    read -r f_tail _vpp _c vtail_mean _a _b _d _n \
      <<<"$(osc_metrics "${d_vtail}" "${OSC_TMEAS_START}")"
  fi
  if [[ -f "${d_isup}" ]]; then
    read -r _f _vpp _c isup_avg _a _b _d _n \
      <<<"$(osc_metrics "${d_isup}" "${OSC_TMEAS_START}")"
  fi

  local vtail_op isup_op
  vtail_op="$(osc_op_value "${log}" "v(tail)")"
  isup_op="$(osc_op_value "${log}" "i(vsup)")"

  # A point PASSES when the simulator ran clean AND a countable oscillation
  # came out of it. A clean run that did not oscillate is NOSC, not FAIL:
  # they are different findings and the sweep must not blur them (row 6 in
  # particular is decided by which of the two it is).
  if [[ "${rc}" == "0" && "${model_error}" == "0" ]]; then
    if awk -v f="${f_osc}" 'BEGIN { exit (f > 1e9) ? 0 : 1 }'; then
      status=PASS
    else
      status=NOSC
    fi
  fi

  local row
  row="$(awk -v vpp_cm="${vpp_cm}" -v vpp_d="${vpp_d}" -v f_cm="${f_cm}" \
             -v f_tail="${f_tail}" -v f_osc="${f_osc}" -v isup_avg="${isup_avg}" \
             -v isup_op="${isup_op:-nan}" -v vdd="${OSC_VDD_NOM}" 'BEGIN {
    r_cm    = (vpp_d  > 0) ? vpp_cm / vpp_d : "nan"
    fr_cm   = (f_osc  > 0) ? f_cm   / f_osc : "nan"
    fr_tail = (f_osc  > 0) ? f_tail / f_osc : "nan"
    p_ls    = isup_avg * vdd
    # i(vsup) is current INTO the source, i.e. negative for a supply; the
    # transient trace is already sign-flipped, the op print is not.
    iop = (isup_op == "nan" || isup_op == "") ? "nan" : -isup_op
    p_op = (iop == "nan") ? "nan" : iop * vdd
    printf "%s,%s,%s,%s,%s,%s,%s", r_cm, fr_cm, fr_tail, iop, p_op, p_ls, ""
  }')"
  local r_cm fr_cm fr_tail iop p_op p_ls
  IFS=, read -r r_cm fr_cm fr_tail iop p_op p_ls _ <<<"${row}"

  echo "${corner_id},${mos},${cap},${hbt},${temp},${vctrl},${tmax},${status},${f_osc},${cycles},${dtmax},${floor_i},${floor_c},${vpp_d},${t_settle},${vpp_cm},${r_cm},${f_cm},${fr_cm},${f_tail},${fr_tail},${vtail_op:-nan},${vtail_mean},${iop},${isup_avg},${p_op},${p_ls}" >> "${CSV_OUT}"

  printf "[%s] %s  f=%s Hz  Vpp_d=%s V  t_settle=%s s  P_ls=%s W  (rc=%s model_error=%s)\n" \
         "${corner_id}" "${status}" "${f_osc}" "${vpp_d}" "${t_settle}" "${p_ls}" \
         "${rc}" "${model_error}"

  # Keep the scratch dir bounded: a full grid writes four traces per point and
  # each is a few hundred kB. The frozen netlist and the raw log are the
  # committed evidence; the traces are intermediates the record derives from.
  rm -f "${d_vdiff}" "${d_vcm}" "${d_vtail}" "${d_isup}"

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

    echo "${base},${mos},${cap},${hbt},${temp},${rung},${rr},${itail},${vte_mean},${vtail_mean},${vpp_late},${f_late},${crit},${osc}" >> "${MARGIN_CSV}"

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
  echo "${base},${mos},${cap},${hbt},${temp},${i_nom},${i_last_osc},${i_first_fail},${summary},${OSC_ROW6_MARGIN},rc=${rc},model_error=${model_error}" >> "${MARGIN_SUM_CSV}"
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
osc_write_csv_headers() {
  echo "corner_id,mos,cap,hbt,temp_c,vctrl_v,tmax,status,f_osc_hz,cycles,dt_max_s,quant_floor_interp_pct,quant_floor_count_pct,vpp_diff_v,t_settle_s,vpp_cm_v,vpp_cm_over_diff,f_cm_hz,f_cm_over_diff,f_tail_hz,f_tail_over_diff,v_tail_dc_op_v,v_tail_mean_v,isup_dc_op_a,isup_ls_avg_a,p_core_dc_op_w,p_core_ls_w" > "${CSV_OUT}"
  if [[ -n "${TUNING_CSV:-}" ]]; then
    echo "mos,cap,hbt,temp_c,n_points,f_min_hz,f_max_hz,v_at_f_min,v_at_f_max,tuning_ratio,tuning_pct,f_center_geo_hz,kvco_mean_hz_per_v,kvco_peak_hz_per_v,kvco_min_hz_per_v,kvco_linearity_pct,quant_floor_worst_pct,row1_verdict,row2_verdict,row2_stretch_verdict" > "${TUNING_CSV}"
  fi
  if [[ -n "${KVCO_CSV:-}" ]]; then
    echo "mos,cap,hbt,temp_c,v_lo,v_hi,v_mid,f_lo_hz,f_hi_hz,kvco_hz_per_v" > "${KVCO_CSV}"
  fi
  if [[ -n "${MARGIN_CSV:-}" ]]; then
    echo "corner,mos,cap,hbt,temp_c,rung,rref_ohm,itail_a,v_te_mean_v,v_tail_mean_v,vpp_diff_late_v,f_late_hz,osc_criterion_v,oscillates" > "${MARGIN_CSV}"
  fi
  if [[ -n "${MARGIN_SUM_CSV:-}" ]]; then
    echo "corner,mos,cap,hbt,temp_c,itail_nominal_a,itail_last_osc_a,itail_first_fail_a,margin_lower_bound,margin_upper_bound,row6_verdict,row6_bound,ngspice_rc,model_error" > "${MARGIN_SUM_CSV}"
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
osc_emit_tuning() {
  local mos="$1" cap="$2" hbt="$3" temp="$4" tmax="${5:-${OSC_TMAX}}"
  awk -F, -v mos="${mos}" -v cap="${cap}" -v hbt="${hbt}" -v temp="${temp}" \
      -v tmax="${tmax}" \
      -v f1lo="${OSC_ROW1_F_MIN_HZ}" -v f1hi="${OSC_ROW1_F_MAX_HZ}" \
      -v r2="${OSC_ROW2_RATIO}" -v r2s="${OSC_ROW2_RATIO_STRETCH}" \
      -v kvco_csv="${KVCO_CSV:-/dev/null}" '
    NR == 1 { next }
    $2 == mos && $3 == cap && $4 == hbt && $5 == temp && $7 == tmax && $8 == "PASS" {
      n++; v[n] = $6 + 0; f[n] = $9 + 0
      fl = $12 + 0; if (fl > worstfloor) worstfloor = fl
    }
    END {
      if (n < 2) {
        printf "%s,%s,%s,%s,%d,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,nan,INSUFFICIENT,INSUFFICIENT,INSUFFICIENT\n", \
               mos, cap, hbt, temp, n
        exit
      }
      # the rows arrive in the sweep order the caller used, which is
      # monotonic in Vctrl; sort defensively anyway
      for (i = 1; i <= n; i++) for (j = i+1; j <= n; j++) if (v[j] < v[i]) {
        tv = v[i]; v[i] = v[j]; v[j] = tv; tf = f[i]; f[i] = f[j]; f[j] = tf
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
        k = (f[i+1] - f[i]) / dv
        kn++; ksum += k
        ak = (k < 0) ? -k : k
        if (kpk == "" || ak > apk) { apk = ak; kpk = k }
        if (kmn == "" || ak < amn) { amn = ak; kmn = k }
        printf "%s,%s,%s,%s,%.6g,%.6g,%.6g,%.6e,%.6e,%.6e\n", \
               mos, cap, hbt, temp, v[i], v[i+1], 0.5*(v[i]+v[i+1]), \
               f[i], f[i+1], k >> kvco_csv
      }
      kmean = (kn > 0) ? ksum / kn : "nan"
      lin = "nan"
      if (kn >= 3 && kmean != 0) {
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
      printf "%s,%s,%s,%s,%d,%.6e,%.6e,%.6g,%.6g,%.6f,%.4f,%.6e,%.6e,%.6e,%.6e,%s,%.6g,%s,%s,%s\n", \
             mos, cap, hbt, temp, n, fmin, fmax, vmin, vmax, ratio, pct, fgeo, \
             kmean, kpk, kmn, lin, worstfloor, row1, row2, row2s
    }' "${CSV_OUT}" >> "${TUNING_CSV}"
}
