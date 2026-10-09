# `.github/klayout-pip-version`

Single source of truth for the pinned `klayout` pip wheel used by the
klayout-dependent Python tests (`tests/klayout/`): one line, `X.Y.Z`. Read by
`.github/workflows/python.yml` (what CI installs) and
`.github/scripts/check-python.sh klayout` (which fails if the importable wheel
disagrees). This is the KLayout Python bindings (`import klayout.db`), not
`klayout-tools`; that is pinned separately in `.github/klt-version`.

Verify a candidate pin without touching host-wide tools:

    uv venv /tmp/kl && uv pip install --python /tmp/kl/bin/python klayout==X.Y.Z
    PYTHON=/tmp/kl/bin/python .github/scripts/check-all.sh py-klayout
