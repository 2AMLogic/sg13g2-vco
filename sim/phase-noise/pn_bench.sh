# Source me:  source "${EXPERIMENT_DIR}/pn_bench.sh"
#
# EXPERIMENT-LOCAL shared driver for sim/phase-noise/. Not an entry point: it
# has no shebang and is never executed. The entry points are the no-argument
# run_*.sh scripts next to it (sim/README.md's directory contract):
#
#   run_isf_pilot.sh     the measured ISF + L(df) at a DECLARED SINGLE corner
#   run_method_check.sh  known-answer check of the estimator (does NOT source
#                        this file -- it needs no PDK and must stay that way)
#
# IT SOURCES sim/oscillator-core/osc_bench.sh, ON PURPOSE
# -------------------------------------------------------
# This experiment is the second half of the bench sim/oscillator-core/ (issue
# #47) is the first half of, and it measures the SAME netlist. Rather than
# re-implement the PDK preflight, the design/vco.spice device-section
# derivation and the template rendering, it reuses that file's osc_preflight /
# osc_derive_body / osc_render verbatim. That is not only less code: it is a
# correctness property. A phase-noise number and a frequency number that claim
# to be about the same circuit are only about the same circuit if they were
# generated from the same derived device section, by the same code, behind the
# same `design/netlist.sh --check` freshness gate. Issue #16 is why this repo
# reuses rather than copies.
#
# The visible consequence is that a run of this experiment prints
# "oscillator-core: ..." preflight lines. They are accurate -- that is whose
# code is running -- and are left unchanged rather than cosmetically renamed,
# so a reader can see the reuse in the log.
#
# What this file adds on top is only what is specific to measuring PHASE NOISE:
# the impulse-train bench constants, the two injection ports, and the two
# per-run drivers.
#
# Bash-3.2 clean, for the same reason sim/lib.sh and osc_bench.sh are.
#
# shellcheck shell=bash
#
# Every PN_* constant below is read by the run_*.sh scripts that source this
# file, never here, so shellcheck's "appears unused" is a false positive for
# the whole block -- and PN_IMP_DT / PN_IMP_TIMES / PN_TSTOP_S are set BY the
# caller before pn_isf_run is invoked (they are derived once per record, so
# every run in a record shares one breakpoint schedule).
# shellcheck disable=SC2034,SC2153

# --------------------------------------------------------------------------
# Bench constants. These are METHOD, so they are declared once, here, and
# every record states them -- a phase-noise number without its method is not a
# result (CLAUDE.md), and row 4 of spec/target-spec.md says so in its own
# condition column.
# --------------------------------------------------------------------------

# --- the transient the ISF is measured from --------------------------------
# The ceiling and the discarded startup window are NOT re-derived here: they
# are sim/oscillator-core's, measured there and restated so this deck reads on
# its own.
#   * 2 ps ceiling  ~100 samples per period at 5 GHz. Measured on this netlist
#     NOT to be a cost lever (169 s at 2 ps vs 183 s at 5 ps for the same 2 ns
#     transient): the cost is Newton iterations per accepted point, not the
#     number of accepted points, so coarsening buys only discretisation error.
#   * 2.5 ns discard  2.0x the slowest 90 %-envelope settling time
#     sim/oscillator-core's pilot measured across its corners (0.487..1.256 ns,
#     record 20260926-010627-e391693).
PN_TSTEP="1p"
PN_TMAX="2p"
PN_TMEAS_START="2.5e-9"

# --- the impulse train -----------------------------------------------------
# PN_F0_NOM is the carrier frequency the train's SPACING is designed around,
# taken from sim/oscillator-core's measured pilot at this same corner
# (mos_tt / cap_typ / hbt_typ, 27 C, Vctrl = 1.65 V: 5.384 GHz, record
# 20260926-010627-e391693). It is a GRID-DESIGN parameter and nothing else:
# the phase at which each impulse actually landed is measured from the run's
# own crossings, so a carrier off this nominal degrades the uniformity of the
# phase grid (which every record states, as `max_phase_gap_rad`) and changes
# no measured quantity.
PN_F0_NOM="5.384e9"
PN_N_IMP="10"
PN_IMP_NPER="3"          # integer part of the spacing, in carrier periods
PN_IMP_T1="3.5e-9"       # first impulse: 1.0 ns of baseline after the discard
PN_IMP_HW="2e-12"        # triangular half-width; q = amp * hw

# Why the spacing is (PN_IMP_NPER + 1/PN_N_IMP) periods and not an integer:
# the fractional part walks the carrier phase by one PN_N_IMP-th of a period
# per impulse, so ONE transient samples the whole ISF. The integer part is
# what separates the impulses in time. PN_IMP_NPER = 3 is 3 periods = 557 ps,
# against an amplitude relaxation time constant this netlist's own startup
# implies is ~0.14 ns (its 90 %-envelope settling time of ~1.26 ns is about
# nine e-foldings), i.e. ~4 time constants between impulses. That is not
# assumed: the plateau each step is read from is taken over only the LAST
# PN_PLATEAU_FRAC of the interval, and the plateau's own ripple is recorded
# per impulse, so an amplitude transient that had not decayed shows up in the
# evidence instead of biasing a step silently.
PN_PLATEAU_FRAC="0.35"

# Injected charge. PN_DQ0 is sized to put the largest excess-phase step at a
# few 1e-2 rad, i.e. a crossing-time shift of order 1 ps against a crossing
# interpolation error of order 0.02 ps at the 2 ps ceiling -- measurable by
# nearly two orders of magnitude -- while displacing the differential tank
# voltage by only a few per cent of its amplitude, which is what keeps the
# FIRST-order ISF the right object to be measuring.
#
# The realisation list is the variance ensemble. It is not a Monte Carlo
# ensemble, because this estimator has no random input (see README.md,
# "What the variance here is, and what it is not"): each entry is an
# independent determination of the same quantity under a different nuisance
# parameter -- the sign of the injected charge (which cancels any even-order
# term in the phase response) and its magnitude (which is the linearity test
# the first-order ISF assumption stands on). The spread across them is what
# the record reports as the estimate's variance.
PN_DQ0="4e-15"
PN_TANK_DQ_LIST="4e-15 -4e-15 8e-15 -8e-15"
PN_TAIL_DQ_LIST="4e-15"

# --- the offsets row 4 is stated at ----------------------------------------
PN_OFFSETS="1e6 10e6"

# --- port noise ------------------------------------------------------------
# The band the input-referred port noise is read over. Swept rather than taken
# at a point so the record can show whether the referral was flat -- see
# tb_vco_port_noise.spice.tmpl's header on why it can be ill conditioned.
PN_NOISE_NPTS="7"
PN_NOISE_FSTART="3e9"
PN_NOISE_FSTOP="9e9"

# --- the declared operating point ------------------------------------------
PN_VCTRL="1.65"          # band-centre control voltage, the point row 4 is stated at

# --- spec bounds this experiment MEASURES against --------------------------
# Read from, never written to: agents do not relax a ratified row to make a
# result pass (CLAUDE.md). These are copies of spec/target-spec.md row 4's
# numbers, used only to print a verdict, and a miss is recorded as a miss.
PN_ROW4_1M_TARGET="-105"
PN_ROW4_1M_STRETCH="-115"
PN_ROW4_10M_TARGET="-125"
PN_ROW4_10M_STRETCH="-135"

# --- the non-PDK inductor model's stated error bars ------------------------
# sim/README.md rule 6: the model's own stated accuracy limits propagate to
# every number derived from it. design/vco.sch instantiates
# w=8.22u s=3.74u d=141.975u nr_r=4, which IS one of the three geometries
# sim/inductor-model/em-extraction/ actually extracted ("p11"), so these are
# that geometry's own numbers rather than an extrapolation:
#   * EM lumped-fit residual 0.90 % rms on Zse over its 0.3 .. 8.008 GHz fit
#     band (which covers the measured 5.4 GHz carrier);
#   * +-10 % convergence bar on the EM-measured Q.
# How each propagates into L(df) is derived in README.md and recomputed in
# every record from these two constants.
PN_IND_Q_BAR_PCT="10"
PN_IND_FIT_BAR_PCT="0.90"

# --------------------------------------------------------------------------
# pn_isf_run <run-id> <dq_tank_c> <dq_tail_c> <mos> <cap> <hbt> <temp> <vctrl>
# One impulse-train transient. Renders the deck (reference = both charges 0),
# freezes it, runs it, and leaves the wrdata trace in ${WORKDIR} for the
# caller to extract from. Prints "rc=<n> model_error=<0|1>".
#
# Uses the globals NETLIST_DIR / LOG_DIR / WORKDIR and the PN_IMP_TIMES /
# PN_TSTOP_S the caller derived once (so every run in a record shares one
# breakpoint schedule -- the property the reference run's exactness depends
# on).
# --------------------------------------------------------------------------
pn_isf_run() {
  local run_id="$1" dq_tank="$2" dq_tail="$3" mos="$4" cap="$5" hbt="$6" temp="$7" vctrl="$8"
  local netlist="${NETLIST_DIR}/${run_id}.spice"
  local log="${LOG_DIR}/${run_id}.log"
  local amp_tank amp_tail
  amp_tank="$(awk -v q="${dq_tank}" -v hw="${PN_IMP_HW}" 'BEGIN{ printf "%.10e", q/hw }')"
  amp_tail="$(awk -v q="${dq_tail}" -v hw="${PN_IMP_HW}" 'BEGIN{ printf "%.10e", q/hw }')"

  # osc_render substitutes @@TSTOP@@ from OSC_TSTOP and @@TMEAS_START@@ from
  # OSC_TMEAS_START, so they are swapped around the call rather than
  # duplicated as second tokens -- one token, one meaning, in both
  # experiments' templates.
  local saved_tstop="${OSC_TSTOP}" saved_tstep="${OSC_TSTEP}" saved_tmeas="${OSC_TMEAS_START}"
  OSC_TSTOP="${PN_TSTOP_S}"; OSC_TSTEP="${PN_TSTEP}"; OSC_TMEAS_START="${PN_TMEAS_START}"
  osc_render "${EXPERIMENT_DIR}/testbench/tb_vco_isf_impulse.spice.tmpl" \
             "${netlist}" "${run_id}" \
             -e "s|@@HBT_SECTION@@|${hbt}|g" \
             -e "s|@@MOS_SECTION@@|mos_${mos}|g" \
             -e "s|@@CAP_SECTION@@|${cap}|g" \
             -e "s|@@TEMP_C@@|${temp}|g" \
             -e "s|@@VCTRL@@|${vctrl}|g" \
             -e "s|@@TMAX@@|${PN_TMAX}|g" \
             -e "s|@@N_IMP@@|${PN_N_IMP}|g" \
             -e "s|@@IMP_NPER@@|${PN_IMP_NPER}|g" \
             -e "s|@@IMP_DT@@|${PN_IMP_DT}|g" \
             -e "s|@@IMP_T1@@|${PN_IMP_T1}|g" \
             -e "s|@@PWL_TANK@@|$(pn_pwl_train "${PN_IMP_TIMES}" "${PN_IMP_HW}" "${amp_tank}")|g" \
             -e "s|@@PWL_TAIL@@|$(pn_pwl_train "${PN_IMP_TIMES}" "${PN_IMP_HW}" "${amp_tail}")|g" \
             -e "s|@@OUT_PREFIX@@|pn_${run_id}|g" \
    || { OSC_TSTOP="${saved_tstop}"; OSC_TSTEP="${saved_tstep}"; OSC_TMEAS_START="${saved_tmeas}"; return 1; }
  OSC_TSTOP="${saved_tstop}"; OSC_TSTEP="${saved_tstep}"; OSC_TMEAS_START="${saved_tmeas}"

  osc_run_ngspice "${netlist}" "${log}"
}

# --------------------------------------------------------------------------
# pn_require_valid_trace <run-id> <wrdata-file> <t_start_s> <t_stop_s>
# Raw-waveform gate (issue #157), run on the reference trace and on every
# perturbed trace BEFORE any mean, crossing or metric is formed from it.
# Reuses osc_trace_validity (sim/oscillator-core/osc_bench.sh) unchanged:
# a trace that is missing, empty, malformed, non-finite (including decimal
# overflow), unordered, or does not cover <t_start>..<t_stop> is a broken
# MEASUREMENT, and derived scalar checks cannot recover the integrity of
# the source waveform. On failure it names the run and the reason token on
# stderr and returns 1; the caller keeps the frozen decks and logs and
# publishes no summary. A valid trace that merely misses a target is NOT
# rejected here -- that is a finding, not a broken measurement.
# --------------------------------------------------------------------------
pn_require_valid_trace() {
  local run_id="$1" dat="$2" ts="$3" te="$4" v
  v="$(osc_trace_validity "${dat}" "${ts}" "${te}")"
  if [[ "${v}" != "ok" ]]; then
    echo "error: run ${run_id}: raw differential trace ${dat} is invalid over ${ts}..${te} s (reason: ${v}); no summary published (decks: ${NETLIST_DIR:-?}, logs: ${LOG_DIR:-?})." >&2
    return 1
  fi
}

# --------------------------------------------------------------------------
# pn_noise_run <port> <mos> <cap> <hbt> <temp> <vctrl>
# One small-signal port-noise analysis. <port> is "tank" or "tail"; the probe
# card and the noise output node are substituted as a MATCHED PAIR so the two
# can never name different ports. Prints "rc=<n> model_error=<0|1>"; the
# caller reads the spectrum out of ${LOG_DIR}/pnoise_<port>.log with
# pn_inoise_table.
# --------------------------------------------------------------------------
pn_noise_run() {
  local port="$1" mos="$2" cap="$3" hbt="$4" temp="$5" vctrl="$6"
  local run_id="pnoise_${port}"
  local netlist="${NETLIST_DIR}/${run_id}.spice"
  local log="${LOG_DIR}/${run_id}.log"
  local probe out
  case "${port}" in
    tank) probe="IPROBE OUTN OUTP dc 0 ac 1"; out="v(OUTP,OUTN)" ;;
    tail) probe="IPROBE 0 TAIL dc 0 ac 1";    out="v(TAIL)" ;;
    *) echo "error: pn_noise_run: unknown port '${port}'" >&2; return 1 ;;
  esac

  osc_render "${EXPERIMENT_DIR}/testbench/tb_vco_port_noise.spice.tmpl" \
             "${netlist}" "${run_id}" \
             -e "s|@@HBT_SECTION@@|${hbt}|g" \
             -e "s|@@MOS_SECTION@@|mos_${mos}|g" \
             -e "s|@@CAP_SECTION@@|${cap}|g" \
             -e "s|@@TEMP_C@@|${temp}|g" \
             -e "s|@@VCTRL@@|${vctrl}|g" \
             -e "s|@@PORT_ID@@|${port}|g" \
             -e "s|@@PROBE_CARD@@|${probe}|g" \
             -e "s|@@NOISE_OUT@@|${out}|g" \
             -e "s|@@NPTS@@|${PN_NOISE_NPTS}|g" \
             -e "s|@@FSTART@@|${PN_NOISE_FSTART}|g" \
             -e "s|@@FSTOP@@|${PN_NOISE_FSTOP}|g" || return 1

  osc_run_ngspice "${netlist}" "${log}"
}

# --------------------------------------------------------------------------
# pn_ind_bar_db
# The non-PDK inductor model's stated error bars, propagated into dB on L(df),
# from PN_IND_Q_BAR_PCT and PN_IND_FIT_BAR_PCT. Derivation (also in README.md):
#
#   * L is proportional to S_i, the port's equivalent noise current PSD, and
#     the tank's loss noise is 4kT*G_p. If the inductor is the dominant loss
#     -- which is the usual case for an LC VCO and is why row 5 is stated on
#     the tank Q at all -- a +-x % bar on the inductor's Q is at most a
#     -+x % bar on G_p, hence at most +-10*log10(1+x/100) dB on L.
#   * L is proportional to Gq_rms^2 ~ 1/q_max^2 ~ 1/(C*A)^2. A +-y % bar on
#     the modelled reactance is at most a +-y % bar on the resonating C, hence
#     at most +-20*log10(1+y/100) dB on L.
#
# Both are UPPER bounds: a loss the inductor does not dominate moves G_p by
# less than its own bar. They are added in quadrature, which is the right
# combination for two independent bars and is stated as such.
# --------------------------------------------------------------------------
pn_ind_bar_db() {
  awk -v q="${PN_IND_Q_BAR_PCT}" -v f="${PN_IND_FIT_BAR_PCT}" 'BEGIN {
    a = 10*log(1 + q/100)/log(10)
    b = 20*log(1 + f/100)/log(10)
    printf "%.3f %.3f %.3f\n", a, b, sqrt(a*a + b*b)
  }'
}

# --------------------------------------------------------------------------
# pn_verdict <L_dBc> <target_dBc> <stretch_dBc>
# Print the row-4 verdict for one offset. Row 4 is a MAXIMUM, so "met" means
# the measured L is at or below the bound. A number that misses is recorded as
# a miss: this experiment measures the row, it does not ratify or relax it.
# --------------------------------------------------------------------------
pn_verdict() {
  # Every input must be a finite number: NaN/inf in any case, empty or
  # malformed values are UNDETERMINED, never "met" (issue #137).
  awk -v l="${1-}" -v t="${2-}" -v s="${3-}" "${PN_AWK_FINITE}"' BEGIN {
    if (!pn_fin(l) || !pn_fin(t) || !pn_fin(s)) { print "UNDETERMINED"; exit }
    if (l + 0 <= s + 0) { print "TARGET AND STRETCH BOTH MET"; exit }
    if (l + 0 <= t + 0) { print "TARGET MET / STRETCH NOT MET"; exit }
    print "TARGET NOT MET"
  }'
}

# --------------------------------------------------------------------------
# pn_reduce_ports <real_csv>
# The ONE definition of the ISF reduce-and-publish prerequisites that
# run_isf_pilot.sh and klt-sim/reduce_isf_fleet.sh share (issue #341). Both
# used to carry byte-identical copies of this block -- two definitions of the
# published schema, where a fix to a column index or a guard landed in one
# copy and silently not the other, for records that claim the same metric
# names. The same argument pn_bench.sh's header makes for reusing
# osc_bench.sh applies one level up: a pilot L(1 MHz) and a per-corner grid
# L(1 MHz) are only comparable if they were reduced and labelled by the same
# code.
#
# Runs the ensemble coverage/finiteness guard first (issue #137): on an
# incomplete or non-finite ensemble it returns 1 and prints nothing, so the
# caller keeps its own error text and exits without publishing. On success it
# sets globally (as the callers of pn_reduce_ensemble already rely on):
#
#   GQ_MEAN GQ_SD GQ_N L1_MEAN L1_SD L1_MIN L1_MAX L10_MEAN L10_SD
#   GQ_TAIL L1_TAIL PORT_RATIO_DB LINEARITY_PCT
#   IND_BAR_Q_DB IND_BAR_FIT_DB IND_BAR_DB
#
# The REAL_CSV column layout is asserted HERE, once, by name:
#   col 1 = port ("tank"/"tail"), col 3 = injected charge dq_c,
#   col 6 = gq_rms_trapz, col 16 = l_1mhz_dbc
# (the header both emitters write into the file). The no-op
# `if (q < qmin || qmin==0) { }` one copy carried is NOT reproduced: an if
# with an empty body over a never-assigned qmin cannot affect the result.
# --------------------------------------------------------------------------
pn_reduce_ports() {
  if ! REDUCED="$(pn_reduce_ensemble "${1}" \
        "$(echo "${PN_TANK_DQ_LIST}" | wc -w | tr -d ' ')" \
        "$(echo "${PN_TAIL_DQ_LIST}" | wc -w | tr -d ' ')" "${PN_N_IMP}")"; then
    return 1
  fi
  read -r GQ_MEAN GQ_SD GQ_N L1_MEAN L1_SD L1_MIN L1_MAX L10_MEAN L10_SD <<<"${REDUCED}"

  GQ_TAIL="$(awk -F, -v col=6 'NR>1 && $1=="tail" { print $col; exit }' "${1}")"
  L1_TAIL="$(awk -F, -v col=16 'NR>1 && $1=="tail" { print $col; exit }' "${1}")"
  PORT_RATIO_DB="$(awk -v a="${GQ_TAIL}" -v b="${GQ_MEAN}" \
    'BEGIN{ if (a=="nan"||b=="nan"||a<=0||b<=0) print "nan"; else printf "%.2f", 20*log(a/b)/log(10) }')"
  LINEARITY_PCT="$(awk -F, -v col_dq=3 -v col_gq=6 'NR>1 && $1=="tank" {
      q=$col_dq+0; if (q<0) q=-q
      key=sprintf("%.4g", q); s[key]+=$col_gq; c[key]++
    }
    END {
      n=0; for (k in s) { n++; m[n]=s[k]/c[k] }
      if (n<2) { print "nan"; exit }
      lo=m[1]; hi=m[1]
      for (i=1;i<=n;i++) { if (m[i]<lo) lo=m[i]; if (m[i]>hi) hi=m[i] }
      printf "%.3f", 100*(hi-lo)/(0.5*(hi+lo))
    }' "${1}")"

  read -r IND_BAR_Q_DB IND_BAR_FIT_DB IND_BAR_DB <<<"$(pn_ind_bar_db)"
}

# --------------------------------------------------------------------------
# pn_summary_rows_common <head|mid|tail> [mos cap hbt temp_c vsup_v vsup_desc]
# The 27 summary rows the two ISF emitters publish identically, written down
# ONCE (issue #341): this is the column contract every record under
# sim/phase-noise/records/ is read against, and it had two independent
# definitions. Emitted to stdout in publish order, split into the three
# contiguous runs both callers share (each caller keeps its own extra rows,
# in its own order, around these):
#
#   head: the corner preamble (mos .. vsup_v). Takes the caller's model
#         sections, temperature and supply rail as arguments; the rail's
#         description is a parameter too -- the pilot's names the startup
#         .ic it is centred on, the fleet reducer's does not. Those are
#         published strings, not variants to unify.
#   mid:  f0_measured, vpp_diff.
#   tail: the estimator rows (si_tank .. inductor_bar_total).
#
# Number formats (%.2f, %.3f, %e) and description strings are part of the
# published contract: change nothing here without a decision record.
# --------------------------------------------------------------------------
pn_summary_rows_common() {
  case "${1}" in
  head)
    echo "mos,${2},,process model section"
    echo "cap,${3},,process model section"
    echo "hbt,${4},,process model section"
    echo "temp_c,${5},C,simulation temperature"
    echo "vctrl_v,${PN_VCTRL},V,control voltage"
    echo "vsup_v,${6},V,${7}"
    ;;
  mid)
    echo "f0_measured,${F0_MEAS},Hz,crossing-counted over the reference run"
    echo "vpp_diff,${VPP_MEAS},V,peak-to-peak of v(OUTP)-v(OUTN) over the measurement window"
    ;;
  tail)
    echo "si_tank,${SI_TANK},A^2/Hz,input-referred one-sided noise current at the differential tank port"
    echo "si_tail,${SI_TAIL},A^2/Hz,input-referred one-sided noise current at the tail node"
    echo "si_tank_band_spread_pct,${NOISE_FLAT_TANK},%,peak-to-peak over ${PN_NOISE_FSTART}..${PN_NOISE_FSTOP} Hz"
    echo "si_tail_band_spread_pct,${NOISE_FLAT_TAIL},%,peak-to-peak over ${PN_NOISE_FSTART}..${PN_NOISE_FSTOP} Hz"
    echo "gq_rms_tank_mean,${GQ_MEAN},rad/C,mean over ${GQ_N} realisations"
    echo "gq_rms_tank_sd,${GQ_SD},rad/C,sample standard deviation over ${GQ_N} realisations"
    echo "gq_rms_tail,${GQ_TAIL},rad/C,single realisation"
    echo "isf_linearity_spread_pct,${LINEARITY_PCT},%,spread of Gq_rms between the two injected-charge magnitudes"
    echo "l_1mhz_mean,${L1_MEAN},dBc/Hz,mean over the tank-port realisations"
    echo "l_1mhz_sd,${L1_SD},dBc/Hz,sample standard deviation over the tank-port realisations"
    echo "l_1mhz_min,${L1_MIN},dBc/Hz,best realisation"
    echo "l_1mhz_max,${L1_MAX},dBc/Hz,worst realisation"
    echo "l_10mhz_mean,${L10_MEAN},dBc/Hz,mean over the tank-port realisations"
    echo "l_10mhz_sd,${L10_SD},dBc/Hz,sample standard deviation over the tank-port realisations"
    echo "l_1mhz_tail_port,${L1_TAIL},dBc/Hz,the same circuit noise weighted by the TAIL port ISF instead"
    echo "port_isf_ratio_db,${PORT_RATIO_DB},dB,20*log10(Gq_rms tail / Gq_rms tank)"
    echo "inductor_bar_q,${IND_BAR_Q_DB},dB,propagated from the EM model's +-${PN_IND_Q_BAR_PCT}% Q bar"
    echo "inductor_bar_fit,${IND_BAR_FIT_DB},dB,propagated from the EM model's ${PN_IND_FIT_BAR_PCT}% rms fit residual"
    echo "inductor_bar_total,${IND_BAR_DB},dB,the two added in quadrature"
    ;;
  esac
}
