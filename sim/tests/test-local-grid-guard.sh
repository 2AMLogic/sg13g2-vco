#!/usr/bin/env bash
# Self-test for require_local_grid_ok / local_grid_record_note in sim/lib.sh
# (issue #160). No PDK, no simulator: env vars only.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib.sh
source "${HERE}/../lib.sh"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   - $1"; }
bad() { fail=$((fail + 1)); echo "FAIL - $1"; }

# guard <expected-rc> <label> <point-count> [VAR=value ...]
# Runs the guard in a clean env (only the given vars set) and checks status.
guard() {
  local want="$1" label="$2" n="$3" rc err
  shift 3
  err="$(env -u KLT_SIM_BACKEND -u SIM_ALLOW_LOCAL_GRID "$@" bash -c \
    'source "$0"; require_local_grid_ok "$1"' "${HERE}/../lib.sh" "$n" 2>&1 >/dev/null)"
  rc=$?
  if [ "${rc}" = "${want}" ]; then ok "${label} (rc=${rc})"; else bad "${label}: rc=${rc}, want ${want}"; fi
  GUARD_ERR="${err}"
}

guard 1 "batch + multi-point trips" 1350 KLT_SIM_BACKEND=batch
case "${GUARD_ERR}" in
  *sim/oscillator-core/klt-sim/README.md*) ok "refusal points at klt-sim/README.md";;
  *) bad "refusal message lacks README pointer: ${GUARD_ERR}";;
esac
case "${GUARD_ERR}" in
  *SIM_ALLOW_LOCAL_GRID=1*) ok "refusal names the SIM_ALLOW_LOCAL_GRID=1 override";;
  *) bad "refusal message lacks the override hint: ${GUARD_ERR}";;
esac
guard 1 "any non-local backend trips" 2 KLT_SIM_BACKEND=remote
guard 0 "backend unset passes" 1350
guard 0 "backend empty passes" 1350 KLT_SIM_BACKEND=
guard 0 "backend=local passes" 1350 KLT_SIM_BACKEND=local
guard 0 "batch + single point passes" 1 KLT_SIM_BACKEND=batch
guard 0 "batch + zero points passes" 0 KLT_SIM_BACKEND=batch
guard 0 "override passes with batch" 1350 KLT_SIM_BACKEND=batch SIM_ALLOW_LOCAL_GRID=1
guard 1 "override must be exactly 1" 1350 KLT_SIM_BACKEND=batch SIM_ALLOW_LOCAL_GRID=yes
guard 2 "non-numeric count is a usage error" abc KLT_SIM_BACKEND=batch

note() { env -u KLT_SIM_BACKEND -u SIM_ALLOW_LOCAL_GRID "$@" bash -c 'source "$0"; local_grid_record_note' "${HERE}/../lib.sh"; }
case "$(note KLT_SIM_BACKEND=batch SIM_ALLOW_LOCAL_GRID=1)" in
  *OVERRIDE*SIM_ALLOW_LOCAL_GRID=1*KLT_SIM_BACKEND=batch*) ok "record header names the override";; *) bad "override note missing";;
esac
case "$(note)" in *OVERRIDE*) bad "plain run flagged as override";; *"KLT_SIM_BACKEND=unset"*) ok "plain run note has no override";; *) bad "plain note: $(note)";; esac

# Static ordering check: in every grid script the guard call must come before
# the first non-comment line that touches ngspice (preflight, --version probe),
# the OSDI build (which may curl a toolchain and runs ngspice), a download, a
# record id reservation or the oscillator bench helpers. Catches a guard that
# drifts below the work it is meant to prevent.
# guard_first <script>: prints "<guard-line> <first-work-line>" (0 if none).
guard_first() {
  awk '
    /^[[:space:]]*#/ { next }
    !g && /^[[:space:]]*require_local_grid_ok[[:space:]]/ { g = NR }
    !w && /ngspice|build-osdi|curl|reserve_record_id|osc_bench\.sh|run_isf_pilot/ { w = NR }
    END { print g + 0, w + 0 }
  ' "$1"
}
for script in \
  oscillator-core/run_pvt_sweep.sh \
  tank-characterization/run_pvt_sweep.sh \
  varactor-characterization/run_varactor_sweep.sh \
  oscillator-core/run_supply_stage2.sh \
  phase-noise/run_supply_stage2.sh; do
  read -r gline wline <<EOT
$(guard_first "${HERE}/../${script}")
EOT
  if [ "${gline}" -eq 0 ]; then
    bad "${script}: no require_local_grid_ok call"
  elif [ "${wline}" -ne 0 ] && [ "${wline}" -lt "${gline}" ]; then
    bad "${script}: guard at line ${gline} runs after ngspice/OSDI/record work at line ${wline}"
  else
    ok "${script}: guard (line ${gline}) precedes ngspice/OSDI/record work"
  fi
done


# Invocation fixtures (issue #176): copy the two stage-2 parent drivers into a
# scratch tree whose env.sh, osc_bench.sh and run_isf_pilot.sh are stubs that
# drop a marker file, then prove that under a batch backend the run modes
# refuse (rc 1) before any stub runs or any evidence directory appears, that
# --list/--check still work, and that local/override runs reach the stubs.
FX="$(mktemp -d "${TMPDIR:-/tmp}/s2-guard-XXXXXX")"
trap 'rm -rf "${FX}"' EXIT
mkdir -p "${FX}/sim/oscillator-core" "${FX}/sim/phase-noise"
cp "${HERE}/../lib.sh" "${FX}/sim/lib.sh"
cp "${HERE}/../oscillator-core/supply_stage2.sh" "${HERE}/../oscillator-core/run_supply_stage2.sh" "${FX}/sim/oscillator-core/"
cp "${HERE}/../phase-noise/run_supply_stage2.sh" "${FX}/sim/phase-noise/"
printf '%s\n' '#!/usr/bin/env bash' 'echo "child ${PILOT_VSUP_V}" >> "${FX_MARK}"' > "${FX}/sim/phase-noise/run_isf_pilot.sh"
chmod +x "${FX}/sim/phase-noise/run_isf_pilot.sh"
# Stub env.sh ends the oscillator run right after marking: nothing past the
# guard needs to execute for the ordering proof.
printf '%s\n' 'echo env.sh >> "${FX_MARK}"; exit 77' > "${FX}/sim/env.sh"
MARK="${FX}/mark"

# fx <label> <want-rc> <want-marker-lines> <script> [args] -- [VAR=value ...]
fx() {
  local label="$1" want="$2" wmark="$3" script="$4" rc nm; shift 4
  local args=() envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do args+=("$1"); shift; done
  [ $# -eq 0 ] || shift
  envs=("$@")
  : > "${MARK}"
  env -u KLT_SIM_BACKEND -u SIM_ALLOW_LOCAL_GRID FX_MARK="${MARK}" ${envs[@]+"${envs[@]}"} \
    bash "${FX}/sim/${script}" ${args[@]+"${args[@]}"} >"${FX}/out" 2>"${FX}/err"
  rc=$?
  nm="$(wc -l < "${MARK}" | tr -d ' ')"
  if [ "${rc}" = "${want}" ] && [ "${nm}" = "${wmark}" ]; then ok "${label} (rc=${rc}, ${nm} stub call(s))"
  else bad "${label}: rc=${rc} stubs=${nm}, want rc=${want} stubs=${wmark}"; fi
  if [ "${wmark}" = 0 ] && [ -n "$(find "${FX}/sim" -type d \( -name records -o -name corners -o -name netlist-snapshots \) -print -quit)" ]; then
    bad "${label}: evidence directory created before refusal"
  fi
}

OSC=oscillator-core/run_supply_stage2.sh
PN=phase-noise/run_supply_stage2.sh
fx "osc stage2: batch refuses before env.sh/work" 1 0 "${OSC}" -- KLT_SIM_BACKEND=batch
case "$(cat "${FX}/err")" in *"18-point grid"*) ok "osc stage2 refusal counts 18 points";; *) bad "osc refusal text: $(cat "${FX}/err")";; esac
fx "pn stage2: batch refuses before any child" 1 0 "${PN}" -- KLT_SIM_BACKEND=batch
case "$(cat "${FX}/err")" in *"18-point grid"*) ok "pn stage2 refusal counts 18 points";; *) bad "pn refusal text: $(cat "${FX}/err")";; esac
fx "osc stage2: --list works under batch" 0 0 "${OSC}" --list -- KLT_SIM_BACKEND=batch
fx "osc stage2: --check works under batch" 0 0 "${OSC}" --check -- KLT_SIM_BACKEND=batch
fx "pn stage2: --list works under batch" 0 0 "${PN}" --list -- KLT_SIM_BACKEND=batch
fx "osc stage2: local backend reaches setup" 77 1 "${OSC}" -- KLT_SIM_BACKEND=local
fx "osc stage2: unset backend reaches setup" 77 1 "${OSC}"
fx "osc stage2: override reaches setup" 77 1 "${OSC}" -- KLT_SIM_BACKEND=batch SIM_ALLOW_LOCAL_GRID=1
fx "pn stage2: local backend runs 18 children" 0 18 "${PN}" -- KLT_SIM_BACKEND=local
fx "pn stage2: override runs 18 children" 0 18 "${PN}" -- KLT_SIM_BACKEND=batch SIM_ALLOW_LOCAL_GRID=1

echo "${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
