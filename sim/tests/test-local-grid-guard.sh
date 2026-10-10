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
  *sim/oscillator-core/klt-sim/README.md*SIM_ALLOW_LOCAL_GRID*|*sim/oscillator-core/klt-sim/README.md*) ok "refusal points at klt-sim/README.md";;
  *) bad "refusal message lacks README pointer: ${GUARD_ERR}";;
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

echo "${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
