#!/usr/bin/env bash
# PDK-FREE checks of the DR-004 stage-2 supply machinery (issue #113).
# Runs no PDK simulation: decks are RENDERED (never run), the one measurement
# path exercised uses stubbed ngspice and synthetic traces, and the report is
# fed synthetic CSV/markdown fixtures. Needs only bash and awk.
#
# Covers:
#   * exactly 18 distinct sub-corners with DR-004's aggregate mappings
#   * the actual rail in every generated deck (VSUP, common-mode offset,
#     startup .ic) for both the oscillator-core and the phase-noise templates
#   * nominal defaults byte-for-byte unchanged (no rail rewrite)
#   * rail determines power; CSV identity column; no mixed-rail aggregation
#   * escalation / no escalation / unavailable baseline / provenance mismatch
#     on synthetic fixtures, and row 7 reported MISSING, never defaulted
# Usage: tests/test_supply_stage2.sh
# shellcheck disable=SC2034  # globals read by the sourced bench functions
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENT_DIR="$(cd "${HERE}/.." && pwd)"
SIM_DIR="$(cd "${EXPERIMENT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SIM_DIR}/.." && pwd)"   # read by osc_derive_body
# no PDK of any kind may be needed
unset PDK_ROOT PDK SG13G2_NGSPICE_MODELS SG13G2_OSDI_DIR OPENVAF_OSDI OSDI_DIR

W="$(mktemp -d)"; trap 'rm -rf "${W}"' EXIT
FAIL=0
check() { if [[ "$2" == ok ]]; then echo "PASS $1"; else echo "FAIL $1: ${3:-}"; FAIL=1; fi; }
eq() { if [[ "$2" == "$3" ]]; then check "$1" ok; else check "$1" bad "got '$2' want '$3'"; fi; }

# shellcheck source=../supply_stage2.sh
source "${EXPERIMENT_DIR}/supply_stage2.sh"
# shellcheck source=../../lib.sh
source "${SIM_DIR}/lib.sh"
# shellcheck source=../osc_bench.sh
source "${EXPERIMENT_DIR}/osc_bench.sh"
# shellcheck source=../../phase-noise/pn_bench.sh
source "${SIM_DIR}/phase-noise/pn_bench.sh"

# --------------------------------------------------------- 1. enumeration
s2_check_enumeration && check enumeration-self-check ok || check enumeration-self-check bad
eq stage2-count "$(s2_enumerate | wc -l | tr -d ' ')" 18
eq stage2-distinct "$(s2_enumerate | sort -u | wc -l | tr -d ' ')" 18
eq margin-corners "$(s2_enumerate_margin | wc -l | tr -d ' ')" 8
eq map-SLOW "$(s2_process_map SLOW)" "ss cap_wcs hbt_wcs"
eq map-TYP  "$(s2_process_map TYP)"  "tt cap_typ hbt_typ"
eq map-FAST "$(s2_process_map FAST)" "ff cap_bcs hbt_bcs"
eq rails-in-enumeration "$(s2_enumerate | awk '{print $2}' | sort -u | tr '\n' ' ')" "2.970 3.630 "
eq temps-in-enumeration "$(s2_enumerate | awk '{print $3}' | sort -un | tr '\n' ' ')" "-40 27 125 "
# every (process, rail, temp) combination present exactly once, mappings applied
bad=0
for r in ${S2_RAILS}; do for p in ${S2_PROCESSES}; do for t in ${S2_TEMPS}; do
  exp="$p $r $t $(s2_process_map "$p")"
  [[ "$(s2_enumerate | grep -cFx "${exp}")" == 1 ]] || { bad=1; echo "  missing/dup: ${exp}"; }
done; done; done
[[ ${bad} == 0 ]] && check full-cross-of-declared-axes ok || check full-cross-of-declared-axes bad
# the aggregate is NOT a cross: no mixed triple such as ss/cap_typ/hbt_typ
[[ "$(s2_enumerate | awk '{print $4"/"$5"/"$6}' | sort -u | wc -l | tr -d ' ')" == 3 ]] \
  && check process-vertices-not-a-cross ok || check process-vertices-not-a-cross bad
eq vertex-inverse "$(s2_vertex_of ff cap_bcs hbt_bcs)" FAST
s2_vertex_of ss cap_typ hbt_typ >/dev/null && check mixed-triple-rejected bad || check mixed-triple-rejected ok
# stage 2 must sweep the SAME Vctrl axis as the stage-1 grid it is compared to
S1_V="$(sed -n 's/^VCTRL_LIST="\(.*\)"$/\1/p' "${EXPERIMENT_DIR}/run_pvt_sweep.sh")"
eq vctrl-axis-matches-stage1 "${S2_VCTRL_LIST}" "${S1_V}"
# point ids carry the rail
eq point-id "$(s2_point_id SLOW 2.970 -40 1.65)" "s2_SLOW_2.970v_-40c_1.65v"
eq driver-check "$(env -u PDK_ROOT "${EXPERIMENT_DIR}/run_supply_stage2.sh" --check)" "stage 2: 18 distinct sub-corners, mappings consistent"
eq driver-list-rows "$("${EXPERIMENT_DIR}/run_supply_stage2.sh" --list | grep -c '^[SFT][A-Z]* ')" 18
eq pn-driver-list-rows "$("${SIM_DIR}/phase-noise/run_supply_stage2.sh" --list | grep -c '^[SFT][A-Z]* ')" 18

# ---------------------------------------------------- 2. s2_status rule
eq status-esc       "$(s2_status 1 -0.5)"  ESCALATION_REQUIRED
eq status-equal     "$(s2_status 1 2)"     NO_ESCALATION
eq status-fav-large "$(s2_status 1 2.5)"   ESCALATION_REQUIRED
eq status-small     "$(s2_status 1 0.4)"   NO_ESCALATION
eq status-m1-zero-worse "$(s2_status 0 -0.1)" ESCALATION_REQUIRED
eq status-m1-neg-better "$(s2_status -1 0)"   NO_ESCALATION
eq status-m1-neg-worse  "$(s2_status -1 -2)"  ESCALATION_REQUIRED
eq status-nan "$(s2_status nan 1)" INSUFFICIENT

# ------------------------------------------------------ 3. rendered decks
WORKDIR="${W}/work"; mkdir -p "${WORKDIR}"
RECORD_ID=testrec
SG13G2_NGSPICE_MODELS="${W}/models"; mkdir -p "${SG13G2_NGSPICE_MODELS}"
for f in cornerHBT cornerMOShv cornerCAP sg13g2_svaricaphv_mod sg13g2_hbt_mod; do echo "* ${f}" > "${SG13G2_NGSPICE_MODELS}/${f}.lib"; done
OSC_IND_MODEL="${W}/ind.spice"; echo "* ind" > "${OSC_IND_MODEL}"
OSC_OSDI_MOSVAR="${W}/mosvar.osdi"; echo "osdi" > "${OSC_OSDI_MOSVAR}"
PDK=ihp-sg13g2; PDK_ROOT="${W}/pdk"
osc_derive_body >/dev/null || check derive-body bad
NETLIST_DIR="${W}/nl"; LOG_DIR="${W}/log"; mkdir -p "${NETLIST_DIR}" "${LOG_DIR}"

render_tran() { # mos cap hbt temp -> path
  local out; out="$(mktemp "${W}/tran.XXXXXX")"
  osc_render "${EXPERIMENT_DIR}/testbench/tb_vco_core_tran.spice.tmpl" "${out}" c1 \
    -e "s|@@HBT_SECTION@@|$3|g" -e "s|@@MOS_SECTION@@|mos_$1|g" -e "s|@@CAP_SECTION@@|$2|g" \
    -e "s|@@TEMP_C@@|$4|g" -e "s|@@VCTRL@@|1.65|g" -e "s|@@TMAX@@|2p|g" -e "s|@@OUT_PREFIX@@|p|g" || return 1
  echo "${out}"
}
render_margin() {
  local out; out="$(mktemp "${W}/margin.XXXXXX")"
  osc_render "${EXPERIMENT_DIR}/testbench/tb_vco_core_margin.spice.tmpl" "${out}" c1 \
    -e "s|@@HBT_SECTION@@|$3|g" -e "s|@@MOS_SECTION@@|mos_$1|g" -e "s|@@CAP_SECTION@@|$2|g" \
    -e "s|@@TEMP_C@@|$4|g" -e "s|@@VCTRL@@|1.65|g" -e "s|@@TMAX@@|2p|g" -e "s|@@OUT_PREFIX@@|p|g" \
    -e "s|@@RREF_LADDER@@|20500|g" || return 1
  echo "${out}"
}
# deck_rail_ok <deck> <rail> <has-vcm> : rail is in VSUP (exactly once), .ic centred, Bvcm offset
deck_rail_ok() {
  local d="$1" rail="$2" ic
  ic="$(osc_rail_ic)"
  [[ "$(grep -c '^VSUP ' "${d}")" == 1 ]] || return 1
  [[ "$(grep '^VSUP ' "${d}")" == "VSUP VDD 0 dc ${rail}" ]] || return 1
  if grep -q '^\.ic ' "${d}"; then
    [[ "$(grep '^\.ic ' "${d}")" == ".ic v(OUTP)=${ic% *} v(OUTN)=${ic#* }" ]] || return 1
  fi
  if grep -q '^Bvcm' "${d}"; then grep -q "^Bvcm .* - ${rail}\$" "${d}" || return 1; fi
  return 0
}
all_ok=1; n_decks=0
while read -r proc rail temp mos cap hbt; do
  OSC_VSUP_V="${rail}"
  for kind in tran margin; do
    d="$(render_${kind} "${mos}" "${cap}" "${hbt}" "${temp}")" || { all_ok=0; continue; }
    n_decks=$((n_decks + 1))
    deck_rail_ok "${d}" "${rail}" || { all_ok=0; echo "  rail wrong in ${kind} deck ${proc} ${rail} ${temp}"; }
    grep -q "^\.lib .*cornerHBT.lib ${hbt}\$" "${d}" && grep -q "^\.lib .*cornerMOShv.lib mos_${mos}\$" "${d}" \
      && grep -q "^\.lib .*cornerCAP.lib ${cap}\$" "${d}" && grep -q "^\.temp ${temp}\$" "${d}" \
      || { all_ok=0; echo "  mapping/temp wrong in ${kind} deck ${proc} ${rail} ${temp}"; }
    # the only difference from the nominal deck is the three rail-carrying lines
    OSC_VSUP_V=""; nom="$(render_${kind} "${mos}" "${cap}" "${hbt}" "${temp}")"; OSC_VSUP_V="${rail}"
    [[ "$(diff "${nom}" "${d}" | grep -c '^>')" == 3 || "$(diff "${nom}" "${d}" | grep -c '^>')" == 2 ]] \
      || { all_ok=0; echo "  unexpected extra differences vs nominal deck (${kind})"; }
  done
done < <(s2_enumerate)
OSC_VSUP_V=""
[[ ${all_ok} == 1 && ${n_decks} == 36 ]] && check rails-in-all-36-oscillator-decks ok || check rails-in-all-36-oscillator-decks bad "decks=${n_decks}"

# phase-noise decks go through the same osc_render: check one per rail/process
PN_IMP_DT="1.9e-10"; PN_IMP_TIMES="3.5e-9,3.69e-9"; PN_TSTOP_S="1e-8"
osc_run_ngspice() { echo "rc=0 model_error=0"; }
pn_ok=1
OSC_EXPERIMENT_DIR="${EXPERIMENT_DIR}"; EXPERIMENT_DIR="${SIM_DIR}/phase-noise"
for rail in ${S2_RAILS}; do
  OSC_VSUP_V="${rail}"
  pn_isf_run ref 0 0 ss cap_wcs hbt_wcs -40 1.65 >/dev/null || pn_ok=0
  deck_rail_ok "${NETLIST_DIR}/ref.spice" "${rail}" || { pn_ok=0; echo "  ISF deck rail wrong at ${rail}"; }
  pn_noise_run tank ff cap_bcs hbt_bcs 125 1.65 >/dev/null || pn_ok=0
  deck_rail_ok "${NETLIST_DIR}/pnoise_tank.spice" "${rail}" || { pn_ok=0; echo "  port-noise deck rail wrong at ${rail}"; }
done
OSC_VSUP_V=""
EXPERIMENT_DIR="${OSC_EXPERIMENT_DIR}"
[[ ${pn_ok} == 1 ]] && check rails-in-phase-noise-decks ok || check rails-in-phase-noise-decks bad

# ----------------------------------------- 4. nominal defaults reproducible
for kind in tran margin; do
  nom="$(render_${kind} tt cap_typ hbt_typ 27)"
  [[ "$(grep '^VSUP ' "${nom}")" == "VSUP VDD 0 dc 3.3" ]] && grep -q '^\.ic v(OUTP)=3.305 v(OUTN)=3.295$' "${nom}" \
    && cmp -s <(grep -v '^\*' "${nom}" | sed -n '/^XL1 /,/^VCT /p') <(grep -v '^\*' "${OSC_VCO_BODY}" | sed -n '/^XL1 /,/^VCT /p') \
    && check "nominal-${kind}-deck-verbatim" ok || check "nominal-${kind}-deck-verbatim" bad
done
OSC_VSUP_V="3.30"
nom2="$(render_tran tt cap_typ hbt_typ 27)"
[[ "$(grep '^VSUP ' "${nom2}")" == "VSUP VDD 0 dc 3.3" ]] && check nominal-rail-spelled-3.30-is-nominal ok || check nominal-rail-spelled-3.30-is-nominal bad
OSC_VSUP_V=""
eq nominal-ic "$(osc_rail_ic)" "3.305 3.295"
# Point-CSV width: 29 base columns + 8 row-7 columns (#112) = 37; the stage-2
# rail identity column (#113) trails them as column 38.
eq nominal-csv-header-has-no-rail "$(OSC_CSV_RAIL=0; CSV_OUT="${W}/h0.csv"; osc_write_csv_headers; awk -F, '{print NF","$NF}' "${W}/h0.csv")" "37,vce_max_upper_v"
eq stage2-csv-header-rail-last "$(OSC_CSV_RAIL=1; CSV_OUT="${W}/h1.csv"; osc_write_csv_headers; awk -F, '{print NF","$NF}' "${W}/h1.csv")" "38,vsup_v"
( OSC_CSV_RAIL=1; CSV_OUT="${W}/a"; TUNING_CSV="${W}/b"; KVCO_CSV="${W}/c"; MARGIN_CSV="${W}/d"; MARGIN_SUM_CSV="${W}/e"; osc_write_csv_headers
  for f in a b c d e; do tail -c 20 "${W}/${f}" | grep -q 'vsup_v$' || exit 1; done ) \
  && check every-stage2-csv-has-rail-column ok || check every-stage2-csv-has-rail-column bad
( OSC_CSV_RAIL=0; CSV_OUT="${W}/a0"; TUNING_CSV="${W}/b0"; KVCO_CSV="${W}/c0"; MARGIN_CSV="${W}/d0"; MARGIN_SUM_CSV="${W}/e0"; osc_write_csv_headers
  grep -l vsup_v "${W}"/[a-e]0 >/dev/null && exit 1; exit 0 ) \
  && check no-nominal-csv-has-rail-column ok || check no-nominal-csv-has-rail-column bad

# ------------------------- 5. rail determines startup and power (stubbed sim)
gen_trace() { # file kind amp offset
  awk -v k="$2" -v a="$3" -v o="$4" 'BEGIN { pi = 3.14159265358979
    for (i = 0; i <= 2500; i++) { t = i * 2e-12
      v = (k == "sin") ? o + a * sin(2*pi*5e9*t) : o
      printf "%.6e %.8e\n", t, v } }' > "$1"
}
osc_render() { return 0; }
OSC_TMEAS_START="2.5e-9"
CSV_OUT="${W}/pt.csv"; : > "${CSV_OUT}"
for rail in 2.970 3.630 3.3; do
  OSC_VSUP_V="${rail}"; [[ "${rail}" == 3.3 ]] && OSC_VSUP_V=""
  id="ptest_${rail}"
  gen_trace "${WORKDIR}/tr_${id}_vdiff" sin 0.5 0
  gen_trace "${WORKDIR}/tr_${id}_vcm" const 0 0
  gen_trace "${WORKDIR}/tr_${id}_vtail" const 0 2.5
  gen_trace "${WORKDIR}/tr_${id}_isup" const 0 1e-3
  printf 'v(tail) = 2.5\ni(vsup) = -1.0e-3\n' > "${LOG_DIR}/${id}.log"
  OSC_CSV_RAIL=1 osc_simulate_point "${id}" ss cap_wcs hbt_wcs -40 1.65 2p >/dev/null || true
done
for rail in 2.970 3.630 3.3; do
  row="$(grep "^ptest_${rail}," "${CSV_OUT}")"
  p="$(echo "${row}" | awk -F, '{print $27}')"; r="$(echo "${row}" | awk -F, '{print $NF}')"; pop="$(echo "${row}" | awk -F, '{print $26}')"
  expp="$(awk -v v="${rail}" 'BEGIN{printf "%.6e", 1e-3*v}')"
  [[ "$(awk -v a="${p}" -v b="${expp}" 'BEGIN{d=a-b; if(d<0)d=-d; print (d<1e-9*1e-3)?"ok":"bad"}')" == ok \
     && "$(awk -v a="${pop}" -v b="${expp}" 'BEGIN{d=a-b; if(d<0)d=-d; print (d<1e-9*1e-3)?"ok":"bad"}')" == ok \
     && "${r}" == "${rail}" ]] \
    && check "power-and-identity-at-${rail}" ok || check "power-and-identity-at-${rail}" bad "p=${p} pop=${pop} rail=${r}"
done
unset -f osc_render
# shellcheck source=../osc_bench.sh
source "${EXPERIMENT_DIR}/osc_bench.sh"

# ------------------------------- 6. no mixed-rail aggregation in the tuning
TUNING_CSV="${W}/t.csv"; KVCO_CSV="${W}/k.csv"
FULL="${S2_VCTRL_LIST}"
prow() { # rail v f   (38-col points row: 37 point columns incl. row-7 (#112) + vsup_v; ss/cap_wcs/hbt_wcs, -40 C)
  echo "c,ss,cap_wcs,hbt_wcs,-40,$2,${OSC_TMAX},PASS,$3,20,1e-12,0.1,0.1,1,1e-9,0,0,0,0,0,0,0,0,0,0,0,0,VALID,-,nan,nan,nan,nan,nan,nan,nan,nan,$1"
}
{ echo "$(OSC_CSV_RAIL=1; CSV_OUT="${W}/hh"; osc_write_csv_headers; cat "${W}/hh")"
  n=0; for v in ${FULL}; do
    prow 2.970 "${v}" "$(awk -v i="${n}" 'BEGIN{printf "%.6e", 5.40e9 - 0.80e9*i/9}')"
    prow 3.630 "${v}" "$(awk -v i="${n}" 'BEGIN{printf "%.6e", 5.60e9 - 0.80e9*i/9}')"
    n=$((n+1)); done; } > "${CSV_OUT}"
: > "${TUNING_CSV}"; : > "${KVCO_CSV}"
osc_emit_tuning ss cap_wcs hbt_wcs -40 "${OSC_TMAX}" "${FULL}" >/dev/null 2>&1
rc=$?
[[ ${rc} == 2 && ! -s "${TUNING_CSV}" ]] && check mixed-rail-aggregation-refused ok || check mixed-rail-aggregation-refused bad "rc=${rc}"
: > "${TUNING_CSV}"; : > "${KVCO_CSV}"
osc_emit_tuning ss cap_wcs hbt_wcs -40 "${OSC_TMAX}" "${FULL}" 2.970
row="$(cat "${TUNING_CSV}")"
eq per-rail-curve-n10-and-rail-last "$(echo "${row}" | awk -F, '{print $5","$NF}')" "10,2.970"
eq per-rail-curve-fmax-is-this-rails "$(echo "${row}" | awk -F, '{printf "%.3e", $7}')" "5.400e+09"
eq per-rail-kvco-rail-column "$(awk -F, '{print $NF}' "${KVCO_CSV}" | sort -u)" "2.970"
# a nominal (rail-less) CSV must not be handed a rail
{ OSC_CSV_RAIL=0; CSV_OUT="${W}/hn"; osc_write_csv_headers; cat "${W}/hn"; echo "c,m,c1,h,27,0.0,${OSC_TMAX},PASS,5e9,20,1e-12,0.1,0.1,1,1e-9,0,0,0,0,0,0,0,0,0,0,0,0,VALID,-,nan,nan,nan,nan,nan,nan,nan,nan"; } > "${W}/nom.csv"
CSV_OUT="${W}/nom.csv" osc_emit_tuning m c1 h 27 "${OSC_TMAX}" "${FULL}" 3.3 >/dev/null 2>&1; eq nominal-csv-refuses-rail $? 2

# ----------------------------------------------- 7. report on fixtures
REPORT="${EXPERIMENT_DIR}/report_supply_stage2.sh"
RAILN="${S2_NOMINAL_RAIL}"

# Fixture records. Margins are chosen so the intended statuses are unambiguous:
#   baseline row 1: f in 4.70..5.30 GHz     -> margin 0.20 GHz
#   baseline row 8: 5.0 mW                  -> margin 5 mW
#   baseline row 6: ratio lower bound 4.0   -> margin 1.0
#   baseline row 4: -110/-130 dBc/Hz        -> margin 5 dB
# and the stage-2 values differ a little (no escalation) or, in the "escalate"
# scenario, blow through the bound at FAST / 3.630 V / 125 C only.
write_md() { # file
  {
    echo "# Record x"
    echo "- Device section sha256"
    echo "  \`$(printf 'body' | sha256sum | cut -d' ' -f1)\`; the schematic"
    echo "- **Non-PDK model**: \`sim/inductor-model/sg13g2_inductor_em.spice\`"
    echo "  sha256 \`$(printf 'ind' | sha256sum | cut -d' ' -f1)\`. The PDK ships none"
    osc_provenance_md
  } > "$1"
}
fixture_points() { # kind -> "<proc> <rail> <temp> <mos> <cap> <hbt>" lines
  local proc temp mos cap hbt
  if [[ "$1" == s2 ]]; then s2_enumerate; return; fi
  for proc in ${S2_PROCESSES}; do for temp in ${S2_TEMPS}; do
    read -r mos cap hbt <<<"$(s2_process_map "${proc}")"
    echo "${proc} ${RAILN} ${temp} ${mos} ${cap} ${hbt}"
  done; done
}
mk_osc() { # dir id kind(base|s2) scen
  local dir="$1" id="$2" kind="$3" scen="$4" p="$1/$2" hp="" suf
  mkdir -p "${dir}"
  [[ "${kind}" == s2 && "${scen}" != norailcol ]] && hp=",vsup_v"
  echo "corner_id,mos,cap,hbt,temp_c,vctrl_v,tmax,status,f_osc_hz,cycles,dt_max_s,qi,qc,vpp,ts,vcm,r,fcm,fcr,ft,ftr,vto,vtm,iop,ils,pop,pls,meas_status,meas_reason${hp}" > "${p}.csv"
  echo "mos,cap,hbt,temp_c,n_points,f_min_hz,f_max_hz,vmin,vmax,ratio,pct,fgeo,km,kp,kn,lin,floor,row1_verdict,row2_verdict,row2_stretch_verdict${hp}" > "${p}-tuning.csv"
  echo "corner,mos,cap,hbt,temp_c,itail_nominal_a,itail_last_osc_a,itail_first_fail_a,margin_lower_bound,margin_upper_bound,row6_verdict,row6_bound,ngspice_rc,model_error${hp}" > "${p}-margin-summary.csv"
  local proc rail temp mos cap hbt fmin fmax pw lo
  while read -r proc rail temp mos cap hbt; do
    fmin=4.70e9; fmax=5.30e9; pw=5.0e-3; lo=4.0
    if [[ "${kind}" == s2 ]]; then fmin=4.68e9; fmax=5.33e9; pw=5.5e-3; lo=3.8; fi
    if [[ "${scen}" == escalate && "${proc}" == FAST && "${temp}" == 125 ]]; then
      if [[ "${kind}" == base ]]; then pw=9.0e-3; fmax=5.40e9; lo=3.4
      elif [[ "${rail}" == 3.630 ]]; then pw=1.2e-2; fmax=5.62e9; lo=2.0
      else pw=8.8e-3; fmax=5.41e9; lo=3.3; fi
    fi
    # a baseline that never ran FAST / 125 C (unavailable-baseline scenario)
    if [[ "${scen}" == basegap && "${kind}" == base && "${proc}" == FAST && "${temp}" == 125 ]]; then continue; fi
    suf=""; [[ -n "${hp}" ]] && suf=",${rail}"
    echo "${mos},${cap},${hbt},${temp},10,${fmin},${fmax},0,3.3,1.1,10,5e9,0,0,0,0,0.1,BOTH ENDPOINTS INSIDE,MET,NOT MET${suf}" >> "${p}-tuning.csv"
    echo "c,${mos},${cap},${hbt},${temp},1.65,${OSC_TMAX},PASS,5e9,20,1e-12,0.1,0.1,1,1e-9,0,0,0,0,0,0,0,0,0,1e-3,0,${pw},VALID,-${suf}" >> "${p}.csv"
    if [[ "${proc}" != TYP && "${temp}" != 27 ]]; then
      echo "m,${mos},${cap},${hbt},${temp},2e-4,1e-4,5e-5,${lo},${lo},MET,3.0,rc=0,model_error=0${suf}" >> "${p}-margin-summary.csv"
    fi
  done < <(fixture_points "${kind}")
  if [[ "${scen}" == badprov && "${kind}" == base ]]; then
    echo "* different" > "${W}/models/cornerCAP.lib"; write_md "${p}.md"; echo "* cornerCAP" > "${W}/models/cornerCAP.lib"
  else
    write_md "${p}.md"
  fi
}
mk_pn_set() { # dir idprefix kind(base|s2) l1 l10 [noid]
  local n=0 proc rail temp mos cap hbt p
  while read -r proc rail temp mos cap hbt; do
    n=$((n+1)); p="$1/$2${n}"
    {
      echo "quantity,value,unit,note"
      if [[ "${6:-}" != noid ]]; then
        echo "mos,${mos},,x"; echo "cap,${cap},,x"; echo "hbt,${hbt},,x"; echo "temp_c,${temp},C,x"
        echo "vctrl_v,1.65,V,x"; echo "vsup_v,${rail},V,x"
      fi
      echo "l_1mhz_mean,$4,dBc/Hz,x"; echo "l_1mhz_sd,0.3,dBc/Hz,x"
      echo "l_10mhz_mean,$5,dBc/Hz,x"; echo "l_10mhz_sd,0.3,dBc/Hz,x"
    } > "${p}-pilot-summary.csv"
    write_md "${p}.md"
  done < <(fixture_points "$3")
}
pn_args() { # dir idprefix flag -> prints args, one per line
  local f; for f in "$1"/"$2"*-pilot-summary.csv; do [[ -f "${f}" ]] && printf '%s\n%s\n' "$3" "${f%-pilot-summary.csv}"; done
}
cnt() { awk -F, -v r="$2" -v s="$3" 'NR > 1 && $1 == r && $13 == s { n++ } END { print n + 0 }' "$1"; }
overall() { grep '^OVERALL:' <<<"$1" | tail -1; }
run_report() { # outdir tag stage2prefix extra args...  -> sets C, OUTTXT
  local d="$1" tag="$2" s2="$3"; shift 3
  OUTTXT="$("${REPORT}" --stage2-osc "${s2}" "$@" --out "${d}/${tag}" 2>&1)"
  C="${d}/${tag}-supply-stage2.csv"
}
mapfile_lines() { local l; while IFS= read -r l; do ARR+=("${l}"); done; }

echo "* cornerCAP" > "${W}/models/cornerCAP.lib"

# --- 7a. no escalation -------------------------------------------------
FX="${W}/fx-ok"; mk_osc "${FX}" base1 base ok; mk_osc "${FX}" s2a s2 ok
mk_pn_set "${FX}" pnbase base -110.0 -130.0; mk_pn_set "${FX}" pns2 s2 -108.0 -128.0
ARR=(); mapfile_lines < <(pn_args "${FX}" pnbase --baseline-pn; pn_args "${FX}" pns2 --stage2-pn)
run_report "${FX}" ok "${FX}/s2a" --baseline-osc "${FX}/base1" "${ARR[@]}"
eq report-ok-rows "$(($(wc -l < "${C}") - 1))" 80
for r in 1 4 8; do eq "no-escalation-row-${r}-18-compared" "$(cnt "${C}" ${r} NO_ESCALATION)" 18; done
eq no-escalation-row-6-8-compared "$(cnt "${C}" 6 NO_ESCALATION)" 8
eq no-escalation-zero-escalations "$(cnt "${C}" 1 ESCALATION_REQUIRED)$(cnt "${C}" 4 ESCALATION_REQUIRED)$(cnt "${C}" 6 ESCALATION_REQUIRED)$(cnt "${C}" 8 ESCALATION_REQUIRED)" 0000
eq row7-missing-18 "$(cnt "${C}" 7 MISSING)" 18
eq row7-never-graded "$(awk -F, 'NR>1 && $1==7 && $13!="MISSING"' "${C}" | wc -l | tr -d ' ')" 0
eq overall-with-row7-missing "$(overall "${OUTTXT}")" "OVERALL: INSUFFICIENT_EVIDENCE"
grep -q 'Row 7 is MISSING' "${FX}/ok-supply-stage2.md" && check md-states-row7-missing ok || check md-states-row7-missing bad
grep -q 'OVERALL: INSUFFICIENT_EVIDENCE' "${FX}/ok-supply-stage2.md" && check md-overall ok || check md-overall bad
# every point of every row carries the rail and nothing is aggregated across rails
eq csv-rails "$(awk -F, 'NR>1{print $3}' "${C}" | sort -u | tr '\n' ' ')" "2.970 3.630 "
# append-only: re-running onto an existing report id is refused
"${REPORT}" --stage2-osc "${FX}/s2a" --baseline-osc "${FX}/base1" --out "${FX}/ok" >/dev/null 2>&1; eq report-refuses-overwrite $? 2
# row-4 reason carries the estimator-spread caveat
grep -q 'combined realisation spread' "${C}" && check row4-carries-method-spread ok || check row4-carries-method-spread bad

# --- 7b. escalation ----------------------------------------------------
FE="${W}/fx-esc"; mk_osc "${FE}" base1 base escalate; mk_osc "${FE}" s2a s2 escalate
mk_pn_set "${FE}" pnbase base -110.0 -130.0; mk_pn_set "${FE}" pns2 s2 -108.0 -128.0
ARR=(); mapfile_lines < <(pn_args "${FE}" pnbase --baseline-pn; pn_args "${FE}" pns2 --stage2-pn)
run_report "${FE}" esc "${FE}/s2a" --baseline-osc "${FE}/base1" "${ARR[@]}"
eq escalation-overall "$(overall "${OUTTXT}")" "OVERALL: ESCALATION_REQUIRED"
for r in 1 6 8; do
  eq "escalation-row-${r}-exactly-one" "$(cnt "${C}" ${r} ESCALATION_REQUIRED)" 1
  eq "escalation-row-${r}-at-FAST-3.630-125" "$(awk -F, -v r=${r} 'NR>1 && $1==r && $13=="ESCALATION_REQUIRED" {print $2","$3","$4}' "${C}")" "FAST,3.630,125"
done
eq escalation-row-4-none "$(cnt "${C}" 4 ESCALATION_REQUIRED)" 0
grep -q 'superseding decision record' "${FE}/esc-supply-stage2.md" && check md-routes-to-superseding-record ok || check md-routes-to-superseding-record bad

# --- 7c. unavailable baseline -----------------------------------------
FU="${W}/fx-unavail"; mk_osc "${FU}" s2a s2 ok
run_report "${FU}" nobase "${FU}/s2a"
eq nobase-no-escalation-claimed "$(cnt "${C}" 1 NO_ESCALATION)$(cnt "${C}" 6 NO_ESCALATION)$(cnt "${C}" 8 NO_ESCALATION)$(cnt "${C}" 4 NO_ESCALATION)" 0000
eq nobase-rows-insufficient "$(cnt "${C}" 1 INSUFFICIENT) $(cnt "${C}" 4 INSUFFICIENT) $(cnt "${C}" 6 INSUFFICIENT) $(cnt "${C}" 8 INSUFFICIENT)" "18 18 8 18"
eq nobase-overall "$(overall "${OUTTXT}")" "OVERALL: INSUFFICIENT_EVIDENCE"
grep -q 'no baseline supplied' "${C}" && check nobase-reason ok || check nobase-reason bad

mk_osc "${FU}" base_gap base basegap; mk_osc "${FU}" base_full base ok
run_report "${FU}" gap "${FU}/s2a" --baseline-osc "${FU}/base_gap"
eq gap-only-missing-point-insufficient "$(cnt "${C}" 1 INSUFFICIENT) $(cnt "${C}" 1 NO_ESCALATION)" "2 16"
eq gap-row8 "$(cnt "${C}" 8 INSUFFICIENT) $(cnt "${C}" 8 NO_ESCALATION)" "2 16"

mk_osc "${FU}" base_prov base badprov
run_report "${FU}" prov "${FU}/s2a" --baseline-osc "${FU}/base_prov"
eq provenance-mismatch-insufficient "$(cnt "${C}" 1 INSUFFICIENT) $(cnt "${C}" 6 INSUFFICIENT) $(cnt "${C}" 8 INSUFFICIENT)" "18 8 18"
grep -q 'provenance mismatch: cornerCAP(differs)' "${C}" && check provenance-mismatch-names-key ok || check provenance-mismatch-names-key bad

mk_osc "${FU}" s2_norail s2 norailcol
run_report "${FU}" norail "${FU}/s2_norail" --baseline-osc "${FU}/base_full"
eq stage2-without-rail-column-never-compared "$(cnt "${C}" 1 NO_ESCALATION)$(cnt "${C}" 8 NO_ESCALATION)$(cnt "${C}" 6 NO_ESCALATION)" 000

# phase-noise records without identity rows (older pilots) are unidentifiable
mk_pn_set "${FU}" pnold base -110.0 -130.0 noid; mk_pn_set "${FU}" pnnew s2 -108.0 -128.0
ARR=(); mapfile_lines < <(pn_args "${FU}" pnold --baseline-pn; pn_args "${FU}" pnnew --stage2-pn)
run_report "${FU}" pnold "${FU}/s2a" --baseline-osc "${FU}/base_full" "${ARR[@]}"
eq pn-baseline-unidentifiable "$(cnt "${C}" 4 INSUFFICIENT) $(cnt "${C}" 4 NO_ESCALATION)" "18 0"
eq osc-rows-still-compared "$(cnt "${C}" 1 NO_ESCALATION)" 18

# a nominal-rail PN record must not be matched to a 2.970 V point (rail identity)
mk_pn_set "${FU}" pnwrong s2 -108.0 -128.0
for f in "${FU}"/pnwrong*-pilot-summary.csv; do sed 's/^vsup_v,.*/vsup_v,3.3,V,x/' "${f}" > "${f}.n" && mv "${f}.n" "${f}"; done
ARR=(); mapfile_lines < <(pn_args "${FU}" pnwrong --stage2-pn)
run_report "${FU}" pnrail "${FU}/s2a" --baseline-osc "${FU}/base_full" "${ARR[@]}"
eq pn-rail-mismatch-not-matched "$(cnt "${C}" 4 INSUFFICIENT)" 18

if [[ ${FAIL} == 0 ]]; then echo "all stage-2 supply checks passed"; fi
exit ${FAIL}
