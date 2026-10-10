#!/usr/bin/env bash
# Simulator-free DRIVER-BOUNDARY fixture for the raw-waveform gate (issue
# #157). It runs the real sim/phase-noise/run_isf_pilot.sh from a throwaway
# copy of the repo in which only the outside world is stubbed: design/
# netlist.sh and sim/tools/build-osdi.sh (no xschem/OpenVAF), a fake PDK
# model tree, and a fake `ngspice` on PATH that writes a chosen wrdata trace.
# No ngspice, PDK or xschem is used; nothing is written to the real repo.
#
# Asserted per faulty trace (reference run, and a perturbed run):
#   * the driver exits non-zero and names the offending run and the reason;
#   * the frozen decks and logs are retained;
#   * no <id>.md summary is published.
# A complete valid trace passes the gate and the driver proceeds into the
# perturbed runs (the existing extraction path).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_REPO="$(cd "${HERE}/../../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# ---- throwaway repo copy with stubs ----------------------------------------
R="${T}/repo"; mkdir -p "${R}"
( cd "${REAL_REPO}" && git ls-files -z design sim | grep -zv '^sim/.*/records/' \
    | tar --null -T - -cf - ) | tar -C "${R}" -xf -
printf '#!/usr/bin/env bash\nexit 0\n' > "${R}/design/netlist.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${R}/sim/tools/build-osdi.sh"
chmod +x "${R}/design/netlist.sh" "${R}/sim/tools/build-osdi.sh"
PDKR="${T}/pdk"; M="${PDKR}/ihp-sg13g2/libs.tech/ngspice/models"
mkdir -p "${M}" "${PDKR}/ihp-sg13g2/libs.tech/ngspice/osdi"
for f in cornerHBT cornerMOShv cornerCAP sg13g2_svaricaphv_mod sg13g2_hbt_mod; do echo "* stub" > "${M}/${f}.lib"; done
echo stub > "${PDKR}/ihp-sg13g2/libs.tech/ngspice/osdi/mosvar.osdi"

BIN="${T}/bin"; mkdir -p "${BIN}"
cat > "${BIN}/ngspice" <<'STUB'
#!/usr/bin/env bash
# fake ngspice: -b <netlist>. Port-noise decks print a valid table; transient
# decks write the wrdata file named in the deck, per FAKE_MODE / FAKE_RUN.
[[ "$1" == "--version" ]] && { echo "** ngspice-99 (stub)"; exit 0; }
net="$2"
if grep -q '^noise' "${net}"; then
  echo "Index   frequency       inoise_spectrum"; echo "-----------------------------"
  echo "0	3e9 2e-11"; echo "1	6e9 4e-11"; echo "2	9e9 3e-11"; echo; exit 0
fi
out="$(sed -n 's/^wrdata \([^ ]*\) .*/\1/p' "${net}" | head -1)"
run="${out#pn_}"; run="${run%_vdiff}"
mode=ok; [[ "${run}" == "${FAKE_RUN:-}" ]] && mode="${FAKE_MODE}"
good() { awk 'BEGIN { for (i = 0; i <= 2000; i++) { t = i * 5e-12; printf "%.6e %.6e\n", t, 0.4*sin(6.283185307179586*5.384e9*t) } }'; }
case "${mode}" in
  ok) good > "${out}" ;;
  missing) ;;
  empty) : > "${out}" ;;
  malformed) { good | head -300; echo "1.6e-9 oops"; good | tail -n +302; } > "${out}" ;;
  nan) good | awk 'NR==700 { print $1, "nan"; next } { print }' > "${out}" ;;
  inf) good | awk 'NR==700 { print $1, "-inf"; next } { print }' > "${out}" ;;
  overflow) good | awk 'NR==700 { print $1, "1e999"; next } { print }' > "${out}" ;;
  overflow-time) good | awk 'NR==700 { print "-1e999", $2; next } { print }' > "${out}" ;;
  unordered) good | awk 'NR==700 { print "1e-12", $2; next } { print }' > "${out}" ;;
  truncated) good | head -300 > "${out}" ;;
esac
exit 0
STUB
chmod +x "${BIN}/ngspice"

records() { ls "${R}/sim/phase-noise/records" 2>/dev/null; }
run_driver() { # <fake-run> <fake-mode>; sets OUT, RC
  rm -rf "${R}/sim/phase-noise/records" "${R}/sim/phase-noise/corners" "${R}/sim/phase-noise/netlist-snapshots"
  mkdir -p "${R}/sim/phase-noise/records"
  OUT="$(cd "${R}" && PATH="${BIN}:${PATH}" PDK_ROOT="${PDKR}" PDK=ihp-sg13g2 \
         FAKE_RUN="$1" FAKE_MODE="$2" "${R}/sim/phase-noise/run_isf_pilot.sh" 2>&1)"; RC=$?
}
has_summary() { compgen -G "${R}/sim/phase-noise/records/*.md" >/dev/null; }

for mode in missing empty malformed nan inf overflow overflow-time unordered truncated; do
  for run in ref tank_r1; do
    run_driver "${run}" "${mode}"
    want="$mode"; case "${mode}" in missing) want="wrote no trace" ;; overflow|overflow-time|nan|inf) want="reason: nonfinite" ;;
      empty|malformed|unordered|truncated) want="reason: ${mode}" ;; esac
    ok=1
    [[ "${RC}" -ne 0 ]] || ok=0
    grep -q "error: .*${run}.*${want}\|error: run ${run}.*${want}" <<<"${OUT}" || ok=0
    has_summary && ok=0
    compgen -G "${R}/sim/phase-noise/netlist-snapshots/*/${run}.spice" >/dev/null || ok=0
    compgen -G "${R}/sim/phase-noise/corners/*/${run}.log" >/dev/null || ok=0
    if [[ "${ok}" == 1 ]]; then pass "${run} ${mode}: nonzero, named, decks+logs kept, no summary"
    else fail "${run} ${mode}: rc=${RC} summary=$(has_summary && echo yes || echo no)"; echo "${OUT}" | tail -5; fi
  done
done

# complete valid traces: the gate passes everywhere and the driver proceeds
# into the perturbed runs (a pure sine carries no ISF, so the later ensemble
# check -- a different, existing guard -- may still stop it).
run_driver none ok
if ! grep -q "raw differential trace" <<<"${OUT}" && grep -q '^\[ref\]' <<<"${OUT}" \
   && grep -q '^\[tank_r1\]' <<<"${OUT}"; then
  pass "valid traces pass the gate and reach the extraction path"
else fail "valid traces: rc=${RC}"; echo "${OUT}" | tail -8; fi

if [[ "${fails}" -ne 0 ]]; then echo "${fails} check(s) failed"; exit 1; fi
echo "all cases passed"
