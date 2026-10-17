# Sourced helper: resolve the IHP-Open-PDK install into PDK (the full install
# path).  One copy of the search order shared by layout/ and the EM extraction
# so the scripts cannot disagree on which install they use:
#   1. $IHP_PDK_ROOT                      (taken as-is)
#   2. $PDK_ROOT/ihp-sg13g2               (if that directory exists)
#   3. $HOME/share/pdk/ihp-sg13g2         (if that directory exists)
# Not the same resolver as sim/env.sh, which sets PDK to the variant name.
#
# Usage: resolve_ihp_pdk ["context for the error message"]
# Sets PDK; prints an error and exits 1 when no install is found.

resolve_ihp_pdk() {
  if [[ -n "${IHP_PDK_ROOT:-}" ]]; then
    PDK="${IHP_PDK_ROOT}"
  elif [[ -n "${PDK_ROOT:-}" && -d "${PDK_ROOT}/ihp-sg13g2" ]]; then
    PDK="${PDK_ROOT}/ihp-sg13g2"
  elif [[ -d "${HOME}/share/pdk/ihp-sg13g2" ]]; then
    PDK="${HOME}/share/pdk/ihp-sg13g2"
  else
    echo "error: cannot find an IHP-Open-PDK install${1:+ ${1}} (set IHP_PDK_ROOT)" >&2
    exit 1
  fi
}
