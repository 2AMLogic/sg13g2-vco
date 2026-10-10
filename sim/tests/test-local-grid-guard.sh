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
    !w && /ngspice|build-osdi|curl|reserve_record_id|osc_bench\.sh/ { w = NR }
    END { print g + 0, w + 0 }
  ' "$1"
}
for script in \
  oscillator-core/run_pvt_sweep.sh \
  tank-characterization/run_pvt_sweep.sh \
  varactor-characterization/run_varactor_sweep.sh; do
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

echo "${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
