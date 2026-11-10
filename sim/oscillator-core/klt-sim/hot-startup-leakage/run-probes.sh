#!/usr/bin/env bash
# Issue #309 single-unit local probes, 125 C only: ONE `ngspice -b` per variant, run sequentially (not a grid, no
# background jobs). Reads ../hot-startup-trace/{body,svar,ind}-*.spice read-only; writes body-*/svar-*/deck-*.cir and
# evidence/<name>.log here. PDK from $PDK_ROOT (default ~/share/pdk).
set -uo pipefail
cd "$(dirname "$0")" || exit 1
: "${PDK_ROOT:=$HOME/share/pdk}"; PDK=ihp-sg13g2
M=$PDK_ROOT/$PDK/libs.tech/ngspice
T=$PWD/../hot-startup-trace
mkdir -p evidence
# deck <name> <body-file> <temp> <control-lines>
deck() {
  cat > "deck-$1.cir" <<EOD
* issue #309 single-unit probe $1 (temp $3)
.lib $M/models/cornerMOShv.lib mos_tt
.lib $M/models/cornerHBT.lib hbt_typ
.lib $M/models/cornerCAP.lib cap_typ
.include $PWD/$2
.temp $3
.control
pre_osdi $M/osdi/mosvar.osdi
save all
$4
quit
.endc
.end
EOD
}
TRAN='tran 1p 2n 0 2p
let vdiff_pp = vecmax(vdiff)-vecmin(vdiff)
print vdiff_pp'
OP='op
print vsup#branch l.xl1.lk1#branch l.xl2.lk1#branch
print @d.xcvp1.dsubw[id] @d.xcvn16.dsubw[id]
print @q.xq1.qnpn13g2v[ic] @q.xq2.qnpn13g2v[ic] @q.xq3.qnpn13g2v[ic] @q.xq4.qnpn13g2v[ic]'
# trace bodies with absolute includes (svar-<v> optionally redirected to a local svar-<name>.spice)
body() { # <src body> <out> [svar-file]
  sed -E "s#^\.include (ind_orig)\.spice#.include $T/\1.spice#; s#^\.include svar-[a-z0-9]+\.spice#.include ${3:-$T/svar-fd.spice}#" "$T/body-$1.spice" > "$2"
}
RAMP='s/^VSUP VDD 0 dc 3.3/VSUP VDD 0 pwl(0 0 500p 3.3)/; s/^\.ic .*/.ic v(OUTP)=0.005 v(OUTN)=0/'
ICW=""; for s in P N; do for i in $(seq 1 16); do ICW+=" v(xcv$s$i.w0)=3.3 v(xcv$s$i.w1)=0"; done; done
body c0 body-c0.spice "$T/svar-fd.spice"
sed -i "s#^\.include $T/svar-fd.spice##" body-c0.spice    # c0 uses the PDK subckt, no local copy
body fd body-fd.spice; body rd body-rd.spice "$T/svar-rd.spice"
sed -e "$RAMP" body-fd.spice > body-fd-ramp.spice
{ cat body-fd.spice; echo ".ic$ICW"; } > body-fd-icw.spice
{ cat body-fd-ramp.spice; echo ".ic$ICW"; } > body-fd-ramp-icw.spice
sed -e "$RAMP" body-rd.spice > body-rd-ramp.spice
# dsubw sidewall-current (jsw*pj dominates the leakage; is*area is ~1e-28 A) scale ladder (keeps tnom=27 referencing); and the PDK "off" initial-guess flag removed
for k in 0.1 0.01 0.0033; do
  sed -E "s/ jsw = 5\.959E-10 / jsw = $(awk -v k=$k 'BEGIN{printf "%.4g", 5.959e-10*k}') /" "$T/svar-fd.spice" > "svar-fd-is$k.spice"
  body fd "body-fd-is$k.spice" "$PWD/svar-fd-is$k.spice"
done
sed -E 's/^(dsubw W1  W dsubw) off /\1 /' "$T/svar-fd.spice" > svar-fd-nooff.spice
body fd body-fd-nooff.spice "$PWD/svar-fd-nooff.spice"
# dsubw junction capacitances zeroed (still tnom=27): separates the diode's capacitance/potential temperature scaling from its leakage
sed -E 's/ cjo = 1\.444E-15 / cjo = 0 /; s/ cjp = 1\.117E-09 / cjp = 0 /' "$T/svar-fd.spice" > svar-fd-nocj.spice
body fd body-fd-nocj.spice "$PWD/svar-fd-nocj.spice"
# dsubw vj raised 0.1 -> 0.5 (only change, still tnom=27): tests whether the temperature-adjusted junction potential going negative is the trigger
sed -E 's/ vj = 0\.1 / vj = 0.5 /' "$T/svar-fd.spice" > svar-fd-vj.spice
body fd body-fd-vj.spice "$PWD/svar-fd-vj.spice"
deck op-c0-125 body-c0.spice 125 "$OP"
deck op-rd-125 body-rd.spice 125 "$OP"
deck op-fd-is0.0033-125 body-fd-is0.0033.spice 125 "$OP"
for v in fd rd fd-ramp fd-icw fd-ramp-icw rd-ramp fd-is0.1 fd-is0.01 fd-is0.0033 fd-nooff fd-nocj fd-vj; do deck "tran-$v-125" "body-$v.spice" 125 "$TRAN"; done
for d in deck-*.cir; do n=${d#deck-}; n=${n%.cir}; timeout 300 ngspice -b "$d" > "evidence/$n.log" 2>&1; echo "$n rc=$?"; done
