# `.github/klt-version`

Single source of truth for the pinned klayout-tools (`klt`) release: one
line, `X.Y.Z`. Read by `.github/workflows/signoff.yml` (what CI installs)
and `.github/scripts/check-signoff.sh` (what the checker expects; it fails
if `klt --version` on PATH disagrees). Bumping the pin means editing that
file, then refreshing `signoff/t1-report.json` (see `signoff/README.md`).

Verify a candidate pin without touching the host-wide tool:

    uvx --from "klayout-tools==X.Y.Z" klt --version

and run the checker against it with a throwaway tool directory:

    uvx --from "klayout-tools==X.Y.Z" bash .github/scripts/check-signoff.sh
