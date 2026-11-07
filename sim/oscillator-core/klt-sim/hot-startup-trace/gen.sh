#!/usr/bin/env bash
# Regenerates every body-*.spice / request-*.json / ind-*.spice / svar-*.spice in this directory from the
# #297 base (../hot-startup-bisect/body-e.spice + request-e.json), ind_orig.spice and svar_loc.tmpl.
# Pure text transforms; no simulation is run here. Variant table: see the record.
set -euo pipefail
cd "$(dirname "$0")"
B=../hot-startup-bisect
mk_ind() { # name tnom_or_none  -> ind-<name>.spice ; keeps tc1 resistors but moves them onto an R model
  local n=$1 t=$2
  if [ "$t" = orig ]; then return; fi
  sed -E -e 's/^(R(ser|k[0-9]+)\s+\S+\s+\S+\s+)(r=\{[a-z_]+\})\s+tc1=\{ind_tc2\}/\1rindm \3/' \
         -e "s/^Lk10 .*/&\n.model rindm R (tnom=$t tc1={ind_tc2})/" ind_orig.spice > "ind-$n.spice"
}
mk_svar() { # name dio_tnom_or_orig mosvar_tr -> svar-<name>.spice
  local n=$1 d=$2 tr=$3
  sed -e "s/^\(\.model dsubw d \)/\1${d:+tnom = $d }/" -e "s/^+ tr = 27/+ tr = $tr/" svar_loc.tmpl > "svar-$n.spice"
}
# name | tnom option | ind variant (orig|27|125) | svar (pdk | loc:<dio tnom or ''>:<tr>)
VARIANTS=(
  "c0|none|orig|pdk"          # control: #297 base minus tnom option
  "e0|125|orig|pdk"           # control: #297 variant (e) replicated
  "c1|none|orig|loc::27"      # control: local varactor copy, nothing changed
  "e1|125|orig|loc::27"       # control: local varactor copy, tnom=125
  "ci0|none|27|pdk"           # control: inductor R-model with tnom=27 under default tnom
  "fi|125|27|pdk"             # forward: inductor tc1 resistors re-pinned to 27
  "fd|125|orig|loc:27:27"     # forward: varactor-subckt diode dsubw re-pinned to 27
  "fid|125|27|loc:27:27"      # forward: both of the above
  "ri|none|125|pdk"           # converse: inductor tc1 resistors referenced to 125
  "rd|none|orig|loc:125:27"   # converse: dsubw referenced to 125
  "ro|none|orig|loc::125"     # converse: OSDI mosvar tr=125
)
for v in "${VARIANTS[@]}"; do
  v=${v%%#*}; v=$(echo "$v" | sed 's/[[:space:]]*$//')
  IFS='|' read -r name tn ind sv <<<"$v"
  mk_ind "$name" "$ind"
  incl=ind-$name.spice; [ "$ind" = orig ] && incl=ind_orig.spice
  body=$(sed -e "s#^\.include sg13g2_inductor_em.spice#.include $incl#" "$B/body-e.spice")
  [ "$tn" = none ] && body=$(grep -v '^\.options tnom=125' <<<"$body")
  if [ "$sv" != pdk ]; then
    IFS=: read -r _ d tr <<<"$sv"
    mk_svar "$name" "$d" "$tr"
    body=$(sed -e "s#^\(\.include $incl\)#\1\n.include svar-$name.spice#" -e 's/ sg13_hv_svaricap / svar_loc /' <<<"$body")
  fi
  printf '%s\n' "$body" > "body-$name.spice"
  sed "s/body-e.spice/body-$name.spice/" "$B/request-e.json" > "request-$name.json"
done
