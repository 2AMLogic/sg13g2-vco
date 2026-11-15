# klt-pin.sh — the single home for the klt pin (issue #360). Sourced, never
# executed: check-signoff.sh uses the assert half (grade only at the pin),
# regen-signoff.sh the resolve half (ambient-if-matching, else uvx, else
# hard fail). The pin lives in exactly one place: .github/klt-version, next
# to this file (not --root, which may be a throwaway tree).
#
# Never falls back to a mismatched tool, and never recommends a host-wide
# install: the pinned release is selected through `uvx --from
# "klayout-tools==$KLT_PIN"`, so no host-wide-install advice lives here.
# shellcheck shell=bash

KLT_PIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KLT_VERSION_FILE="$KLT_PIN_DIR/klt-version"

# klt_pin_read: set KLT_PIN from the pin file. Fails on a missing or empty
# file — an unparsable pin must stop the caller, not silently grade.
klt_pin_read() {
  if [ ! -f "$KLT_VERSION_FILE" ]; then
    echo "FAIL: missing pin file $KLT_VERSION_FILE" >&2
    return 1
  fi
  KLT_PIN="$(tr -d '[:space:]' < "$KLT_VERSION_FILE")"
  if [ -z "$KLT_PIN" ]; then
    echo "FAIL: pin file $KLT_VERSION_FILE is empty" >&2
    return 1
  fi
}

# klt_pin_assert: checker mode. The caller's klt must be exactly the pin —
# a mismatched host klt must not silently grade the record. No uvx fallback
# here on purpose: CI installs the pinned wheel, and a silent fallback would
# change the checker's verdict semantics (and hit the network from a
# self-test fixture). Sets KLT_ACTUAL to the observed version.
klt_pin_assert() {
  if ! command -v klt >/dev/null 2>&1; then
    echo "FAIL: klt not on PATH — run with the pinned release (see signoff/README.md): uvx --from \"klayout-tools==$KLT_PIN\" bash .github/scripts/check-signoff.sh" >&2
    return 1
  fi
  KLT_ACTUAL="$(klt --version 2>/dev/null | awk '{print $NF; exit}')"
  if [ "$KLT_ACTUAL" != "$KLT_PIN" ]; then
    echo "FAIL: klt version mismatch: PATH has '${KLT_ACTUAL:-unknown}', pin (.github/klt-version) is '$KLT_PIN' — use: uvx --from \"klayout-tools==$KLT_PIN\" bash .github/scripts/check-signoff.sh" >&2
    return 1
  fi
}

# klt_pin_resolve: regen mode. Set KLT_CMD to a pinned-tool command: the
# ambient klt when it matches the pin, else `uvx --from
# "klayout-tools==$KLT_PIN" klt`, else hard fail naming the pin, the actual
# version and both remedies.
klt_pin_resolve() {
  KLT_ACTUAL=""
  if command -v klt >/dev/null 2>&1; then
    KLT_ACTUAL="$(klt --version 2>/dev/null | awk '{print $NF; exit}')"
  fi
  if [ "$KLT_ACTUAL" = "$KLT_PIN" ]; then
    KLT_CMD=(klt)
    return 0
  fi
  if command -v uvx >/dev/null 2>&1; then
    KLT_CMD=(uvx --from "klayout-tools==$KLT_PIN" klt)
    return 0
  fi
  {
    echo "FAIL: no pinned klt available: PATH has '${KLT_ACTUAL:-no klt}', pin (.github/klt-version) is '$KLT_PIN'."
    echo "  remedy 1: run inside an environment that has klayout-tools==$KLT_PIN (a throwaway venv is enough)"
    echo "  remedy 2: uvx --from \"klayout-tools==$KLT_PIN\" <command>"
  } >&2
  return 1
}
