#!/usr/bin/env bash
# Regression test for issue #96: sim/tools/build-osdi.sh must never write the
# PDK install, must validate a staged candidate with the selected ngspice
# before publishing it atomically, and must leave a previously published
# library byte-for-byte unchanged on every failure path.
#
# Fully stubbed in a temp dir: a fake PDK, a fake pinned compiler tarball
# (the pin copies in a THROWAWAY copy of the helper are rewritten to the stub
# tarball's digest; the repo's real pins are untouched), a fake ngspice and a
# curl that fails and records any call. No real PDK, toolchain, download or
# ngspice is used.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SIM="$(cd "${HERE}/.." && pwd)"
T="$(mktemp -d)"
cleanup() { chmod -R u+w "$T" 2>/dev/null; rm -rf "${T:?}"; }
trap cleanup EXIT
fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
# check DESC BODY: BODY is one single-quoted shell string, evaluated here so
# its variables expand at check time (hence eval as a string, not an array).
check() { local d="$1"; shift; if eval "$*"; then pass "$d"; else fail "$d"; fi; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- throwaway sim/ copy with the pins rewritten to the stub tarballs -------
S="${T}/repo/sim"; mkdir -p "${S}/tools" "${T}/cache" "${T}/bin" "${T}/marks"
cp "${REAL_SIM}/env.sh" "${REAL_SIM}/lib.sh" "${S}/"
cp "${REAL_SIM}/tools/build-osdi.sh" "${S}/tools/build-osdi.sh"

for k in macos-aarch64 macos-x86_64 linux-x86_64; do
  asset="openvaf-r-v24.0.1mob-${k}.tar.gz"
  pre="${T}/mk/${asset%.tar.gz}"; mkdir -p "${pre}/bin"
  cat > "${pre}/bin/openvaf-r" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == "--version" ]] && { echo "openvaf-r stub"; exit 0; }
echo called >> "${MARKS}/compiler.called"
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && { out="$2"; shift; }; shift; done
case "${STUB_VAF:-ok}" in
  fail) exit 1 ;;
  partial) echo PARTIAL > "${out}"; exit 1 ;;
  slow) echo PARTIAL > "${out}"; echo $$ > "${MARKS}/vaf.pid"; exec sleep 30 ;;
esac
echo "${STUB_CONTENT:-GOOD}-${STUB_TAG:-}" > "${out}"
STUB
  chmod +x "${pre}/bin/openvaf-r"
  tar -C "${T}/mk" -czf "${T}/cache/${asset}" "${asset%.tar.gz}"
  mkdir -p "${T}/cache"; cp -r "${pre}" "${T}/cache/"
  key="${k//-/_}"
  sed -i "s|^OPENVAF_SHA_${key}=.*|OPENVAF_SHA_${key}=\"$(sha "${T}/cache/${asset}")\"|" "${S}/tools/build-osdi.sh"
done
# libLLVM stand-in so the Linux path never downloads.
LL="${T}/cache/libllvm21_21.1.8-noble_amd64/usr/lib/x86_64-linux-gnu"
mkdir -p "${LL}"; : > "${LL}/libLLVM.so.21.1"

# ---- fake PDK: models dir, Verilog-A source, a sentinel prebuilt osdi -------
PDKR="${T}/pdk"; P="${PDKR}/ihp-sg13g2/libs.tech"
mkdir -p "${P}/ngspice/models" "${P}/ngspice/osdi" "${P}/verilog-a/mosvar"
echo "* stub" > "${P}/ngspice/models/cornerMOShv.lib"
echo "// stub va" > "${P}/verilog-a/mosvar/mosvar.va"
echo "PDK-SENTINEL" > "${P}/ngspice/osdi/mosvar.osdi"
PDK_SHA="$(sha "${P}/ngspice/osdi/mosvar.osdi")"

# ---- stub ngspice / curl ----------------------------------------------------
cat > "${T}/bin/ngspice" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "--version" ]] && { echo "** ngspice-42 (stub)"; exit 0; }
echo called >> "${MARKS}/ngspice.called"
lib="$(sed -n 's/^pre_osdi //p' "$2" | head -1)"
c="$(cat "${lib}" 2>/dev/null)"
case "${c}" in
  GOOD*|PDK-SENTINEL*) echo "v(hot) = 1.0e+00,0.0e+00"; exit 0 ;;
  ABI*) echo "ngspice only supports OSDI v0.3 but ${lib} targets v0.4"; echo "v(hot) = 1.0e+00,0.0e+00"; exit 0 ;;
  NOAC*) echo "loaded"; exit 0 ;;
  BADEXIT*) echo "boom"; exit 1 ;;
esac
exit 1
STUB
printf '#!/usr/bin/env bash\necho called >> "${MARKS}/curl.called"\nexit 22\n' > "${T}/bin/curl"
chmod +x "${T}/bin/ngspice" "${T}/bin/curl"
NOSIM="${T}/bin-nosim"; mkdir -p "${NOSIM}"
for b in bash env dirname mktemp cat sed grep head cut mv rm mkdir sleep uname tr sha256sum awk cp chmod ls kill tar gzip date basename readlink cd pwd; do
  p="$(command -v "$b" 2>/dev/null)" && [[ "$p" == /* ]] && ln -sf "$p" "${NOSIM}/$b"
done

export MARKS="${T}/marks" PDK_ROOT="${PDKR}" PDK=ihp-sg13g2 SG13G2_TOOLS_CACHE="${T}/cache" HOME="${T}/home"
mkdir -p "${HOME}"
unset SG13G2_OSDI_DIR
OUT="${T}/cache/osdi"   # default resolution
BUILD="${S}/tools/build-osdi.sh"
run() { PATH="${T}/bin:${PATH}" "${BUILD}" "$@" > "${T}/out.log" 2>&1; }
reset_marks() { rm -f "${MARKS}"/*.called "${MARKS}"/vaf.pid; }
stage_left() { compgen -G "${1}/.stage.*" >/dev/null; }

# ---- 1. default build: success, outside the PDK -----------------------------
export STUB_VAF=ok STUB_CONTENT=GOOD STUB_TAG=1
check "default build succeeds" 'run'
check "published into the cache dir, not the PDK" '[[ -f "${OUT}/mosvar.osdi" ]] && [[ "$(sha "${P}/ngspice/osdi/mosvar.osdi")" == "${PDK_SHA}" ]]'
check "no staging dir left after success" '! stage_left "${OUT}"'
GOOD_SHA="$(sha "${OUT}/mosvar.osdi")"

# ---- 2. the PDK stays untouched and read-only is fine -----------------------
chmod -R a-w "${PDKR}"
export STUB_TAG=2
check "build works against a read-only PDK" 'run --force'
check "PDK sentinel unchanged (read-only PDK)" '[[ "$(sha "${P}/ngspice/osdi/mosvar.osdi")" == "${PDK_SHA}" ]]'
chmod -R u+w "${PDKR}"
GOOD_SHA="$(sha "${OUT}/mosvar.osdi")"

# ---- 3. failure paths keep the previous published library -------------------
expect_fail_keeps() {  # desc, expected-text, args...
  local desc="$1" text="$2"; shift 2
  if run "$@"; then fail "${desc}: exited zero"; return; fi
  if [[ "$(sha "${OUT}/mosvar.osdi")" == "${GOOD_SHA}" ]] && ! stage_left "${OUT}" \
     && [[ "$(sha "${P}/ngspice/osdi/mosvar.osdi")" == "${PDK_SHA}" ]] \
     && grep -qiE "${text}" "${T}/out.log"; then pass "${desc}"; else fail "${desc}"; sed 's/^/    /' "${T}/out.log" | tail -8; fi
}
( export STUB_VAF=fail; expect_fail_keeps "compiler failure (--force) keeps previous" "compiler failed" --force )
( export STUB_VAF=partial; expect_fail_keeps "compiler partial output then failure keeps previous" "compiler failed" --force )
( export STUB_CONTENT=ABI; expect_fail_keeps "incompatible ABI (zero-exit ngspice error) keeps previous" "only supports OSDI" --force )
( export STUB_CONTENT=NOAC; expect_fail_keeps "zero exit without AC result keeps previous" "no AC result" --force )
( export STUB_CONTENT=BADEXIT; expect_fail_keeps "nonzero ngspice exit keeps previous" "non-zero" --force )
reset_marks
( PATH="${NOSIM}"; "${BUILD}" --force > "${T}/out.log" 2>&1 ) && fail "absent ngspice exited zero" || {
  if [[ "$(sha "${OUT}/mosvar.osdi")" == "${GOOD_SHA}" ]] && grep -q "ngspice not on PATH" "${T}/out.log" \
     && [[ ! -e "${MARKS}/compiler.called" ]] && [[ ! -e "${MARKS}/curl.called" ]]; then
    pass "absent ngspice fails before compiling/downloading, previous kept"; else fail "absent ngspice handling"; fi; }

# ---- 4. --force with a good compiler replaces (validated) -------------------
export STUB_VAF=ok STUB_CONTENT=GOOD STUB_TAG=3
check "--force rebuild publishes a validated candidate" 'run --force && [[ "$(sha "${OUT}/mosvar.osdi")" != "${GOOD_SHA}" ]]'
GOOD_SHA="$(sha "${OUT}/mosvar.osdi")"

# ---- 5. --check: read-only, no compiler, no downloader ----------------------
reset_marks
check "--check passes on the resolved library" 'run --check && grep -qF "${OUT}" "${T}/out.log"'
check "--check leaves files unchanged" '[[ "$(sha "${OUT}/mosvar.osdi")" == "${GOOD_SHA}" ]] && ! stage_left "${OUT}"'
check "--check invokes neither compiler nor downloader" '[[ ! -e "${MARKS}/compiler.called" && ! -e "${MARKS}/curl.called" ]]'
echo ABI-bad > "${OUT}/mosvar.osdi"
check "--check rejects a library that only has a plausible name" '! run --check'
check "--check does not repair the library" '[[ "$(cat "${OUT}/mosvar.osdi")" == "ABI-bad" ]] && [[ ! -e "${MARKS}/compiler.called" ]]'
check "--check on missing library fails without building" 'rm -f "${OUT}/mosvar.osdi"; ! run --check && [[ ! -e "${OUT}/mosvar.osdi" && ! -e "${MARKS}/compiler.called" ]]'
export STUB_TAG=4; run >/dev/null; GOOD_SHA="$(sha "${OUT}/mosvar.osdi")"

# ---- 6. resolution: helper and parent consumers agree, override honoured ----
res() { ( cd / && bash -c 'source "$1" >/dev/null 2>&1; printf %s "$SG13G2_OSDI_DIR"' _ "${S}/env.sh" ); }
check "default env.sh resolution is the cache dir" '[[ "$(res)" == "${OUT}" ]]'
check "helper --check names the same dir as env.sh" 'run --check && grep -qF "in $(res) " "${T}/out.log"'
# shellcheck disable=SC2034  # read inside the single-quoted check bodies below (eval'd by check)
OVR="${T}/override"
check "explicit override honoured by env.sh" '[[ "$(SG13G2_OSDI_DIR="${OVR}" res)" == "${OVR}" ]]'
check "override: helper publishes there, not in the default or PDK dir" \
  'SG13G2_OSDI_DIR="${OVR}" run && [[ -f "${OVR}/mosvar.osdi" ]] && [[ "$(sha "${OUT}/mosvar.osdi")" == "${GOOD_SHA}" ]] && [[ "$(sha "${P}/ngspice/osdi/mosvar.osdi")" == "${PDK_SHA}" ]]'
check "override: --check verifies the override library" 'SG13G2_OSDI_DIR="${OVR}" run --check && grep -qF "in ${OVR} " "${T}/out.log"'
check "publishing into the PDK osdi dir is refused" \
  '! SG13G2_OSDI_DIR="${P}/ngspice/osdi" run --force && [[ "$(sha "${P}/ngspice/osdi/mosvar.osdi")" == "${PDK_SHA}" ]] && grep -q refusing "${T}/out.log"'

# ---- 7. interrupted staging -------------------------------------------------
reset_marks
( export STUB_VAF=slow
  PATH="${T}/bin:${PATH}" "${BUILD}" --force > "${T}/out.log" 2>&1 & echo $! > "${MARKS}/build.pid"; wait )  &
for _ in $(seq 1 100); do [[ -s "${MARKS}/vaf.pid" ]] && break; sleep 0.1; done
if [[ -s "${MARKS}/vaf.pid" ]]; then
  stage_left "${OUT}" && pass "staging dir exists mid-build" || fail "staging dir exists mid-build"
  bp="$(cat "${MARKS}/build.pid")"
  kill -TERM "${bp}" 2>/dev/null; kill -TERM "$(cat "${MARKS}/vaf.pid")" 2>/dev/null
  wait 2>/dev/null
  check "interrupt: staging cleaned" '! stage_left "${OUT}"'
  check "interrupt: previous library unchanged" '[[ "$(sha "${OUT}/mosvar.osdi")" == "${GOOD_SHA}" ]]'
else
  kill %1 2>/dev/null; fail "slow compiler never started"
fi

# ---- 8. simultaneous invocations --------------------------------------------
rm -rf "${OUT:?}"; reset_marks
export STUB_VAF=ok STUB_CONTENT=GOOD STUB_TAG=5
pids=()
for i in 1 2 3; do
  ( PATH="${T}/bin:${PATH}" "${BUILD}" --force > "${T}/par$i.log" 2>&1 ) & pids+=($!)
done
# shellcheck disable=SC2034  # read inside the single-quoted check body below (eval'd by check)
{ rc=0; for p in "${pids[@]}"; do wait "$p" || rc=1; done; }
check "simultaneous builds all succeed" '[[ ${rc} -eq 0 ]]'
check "simultaneous builds leave one valid library and no staging" 'run --check && ! stage_left "${OUT}"'

echo
if [[ ${fails} -eq 0 ]]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
