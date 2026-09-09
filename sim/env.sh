# Source me:  source sim/env.sh
#
# Resolves the SG13G2 PDK install every testbench under sim/ simulates
# against, so an interactive ngspice session and every sim/*/run_*.sh script
# agree on which install is in use instead of each re-deriving it.
#
# Resolution order:
#   1. $PDK_ROOT / $PDK if already exported (an explicit choice always wins);
#   2. otherwise the usual open_pdks-shaped install prefixes, in this order:
#      /usr/share/pdk, /usr/local/share/pdk, ~/share/pdk, ~/.ciel, ~/.volare.
#
# A prefix only counts as a hit if $prefix/$PDK/libs.tech/ngspice/models
# exists -- a PDK checkout without the ngspice model libraries is useless to
# every testbench in this tree, and silently selecting one would produce a
# confusing "unknown subckt" failure several layers down instead of a clear
# message here.
#
# Exports on success: PDK, PDK_ROOT, SG13G2_NGSPICE_MODELS.
#
# This file is sourced, not executed, so it has no shebang; the directive
# below tells shellcheck which dialect to assume.
# shellcheck shell=bash

# ${(%):-%x} is the zsh equivalent of ${BASH_SOURCE[0]} -- this file is
# sourced from both shells; shellcheck cannot parse the zsh half.
# shellcheck disable=SC2296
_sg13g2_env_self="${BASH_SOURCE[0]:-${(%):-%x}}"
_sg13g2_sim_dir="$(cd "$(dirname "${_sg13g2_env_self}")" && pwd)"

export PDK="${PDK:-ihp-sg13g2}"

if [[ -z "${PDK_ROOT:-}" ]]; then
  for _sg13g2_candidate in /usr/share/pdk /usr/local/share/pdk \
                           "${HOME}/share/pdk" "${HOME}/.ciel" "${HOME}/.volare"; do
    if [[ -d "${_sg13g2_candidate}/${PDK}/libs.tech/ngspice/models" ]]; then
      export PDK_ROOT="${_sg13g2_candidate}"
      break
    fi
  done
fi

if [[ -n "${PDK_ROOT:-}" && -d "${PDK_ROOT}/${PDK}/libs.tech/ngspice/models" ]]; then
  export SG13G2_NGSPICE_MODELS="${PDK_ROOT}/${PDK}/libs.tech/ngspice/models"
  echo "sg13g2: PDK_ROOT=${PDK_ROOT} PDK=${PDK}"
else
  echo "sg13g2: no ${PDK} install found under PDK_ROOT or the usual prefixes." >&2
  echo "sg13g2: set PDK_ROOT to an open_pdks-shaped IHP-Open-PDK checkout and re-source," >&2
  echo "sg13g2: e.g. via klayout-tools' scripts/fetch-ihp-sg13g2.sh, then:" >&2
  echo "sg13g2:   export PDK_ROOT=/path/to/ihp-open-pdk PDK=ihp-sg13g2" >&2
  echo "sg13g2: see sim/pdk.json for the pinned release this repo's records target." >&2
fi

# Note on OSDI: nothing under sim/tank-characterization/ needs the PDK's
# Verilog-A (OSDI) device models -- cap_cmim, cap_rfcmim and the parasitic
# subcircuits in capacitors_mod.lib are built entirely from ngspice's native
# R/L/C primitives and a `.model ... C` card. sim/varactor-characterization/
# (#18) is the first study that does: `sg13_hv_svaricap` is a Verilog-A
# ("mosvar") compact model, only instantiable via a compiled .osdi shared
# library. SG13G2_OSDI_DIR below is that resolution -- deferred until now on
# purpose, per this comment's earlier revision, so this file never carried an
# untested code path.
if [[ -n "${PDK_ROOT:-}" && -d "${PDK_ROOT}/${PDK}/libs.tech/ngspice/models" ]]; then
  export SG13G2_OSDI_DIR="${PDK_ROOT}/${PDK}/libs.tech/ngspice/osdi"
  if [[ ! -f "${SG13G2_OSDI_DIR}/mosvar.osdi" ]]; then
    echo "sg13g2: mosvar.osdi not built yet in ${SG13G2_OSDI_DIR}" >&2
    echo "sg13g2: sg13_hv_svaricap will not simulate until it is." >&2
    echo "sg13g2: Build it with:  sim/tools/build-osdi.sh" >&2
    echo "sg13g2: (sim/varactor-characterization/run_varactor_sweep.sh does this itself)." >&2
  fi
fi

unset _sg13g2_env_self _sg13g2_sim_dir _sg13g2_candidate
