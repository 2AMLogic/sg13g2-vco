#!/usr/bin/env bash
# Self-test for lint-shell.sh: a lint gate that cannot fail is no gate.
#   1. clean tracked tree                 -> passes
#   2. temp script with a SC2034 warning  -> FAILS
#   3. temp clean script                  -> passes
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="$HERE/lint-shell.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
check() { # check <name> <expected rc zero?:0|1> <actual rc>
  if { [ "$2" = 0 ] && [ "$3" -eq 0 ]; } || { [ "$2" = 1 ] && [ "$3" -ne 0 ]; }; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (rc=$3)"; fail=1
  fi
}
"$LINT" >/dev/null 2>&1; check "tracked tree is clean" 0 $?
printf '#!/usr/bin/env bash\nunused_var=1\n' > "$T/bad.sh"
"$LINT" "$T/bad.sh" >/dev/null 2>&1; check "injected SC2034 is rejected" 1 $?
printf '#!/usr/bin/env bash\necho ok\n' > "$T/good.sh"
"$LINT" "$T/good.sh" >/dev/null 2>&1; check "clean temp script passes" 0 $?
exit "$fail"
