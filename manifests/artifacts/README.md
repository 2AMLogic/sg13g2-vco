# manifests/artifacts — pointers to stored sim evidence

New sim and signoff evidence bytes live in the fleet artifact store, not in
git (issue #253). This directory holds one manifest per run,
`<bench>-<run-id>.manifest.json`, in `klt artifact` format
(`{"schema_version": 1, "entries": [...]}`; each entry has `sha256`, `size`,
`kind`, `producer`, `uri`, optional `name`/`media_type`). Every `uri` is
`artifact:<key>`; no storage-location string (bucket, account id, URL scheme of the store) may appear here. A
manifest is safe to commit to a public repo; the bytes are private.

Write one with `sim/store-evidence.sh <bench> <run-id> FILE...` (raw outputs
staged outside git, e.g. the ignored `sim/build/`), then commit the manifest
and the run's Markdown record under `sim/<bench>/records/`. The writer fails
closed: with `$KLT_ARTIFACT_BROKER` unset, a klt lacking `artifact put`, or an
unreachable broker it exits nonzero and writes nothing; there is no fallback
to committing bytes.

Checks:

- CI, offline: `.github/scripts/check_artifact_manifests.py` (run by the
  `py-tests` gate through `tests/stdlib/test_artifact_manifests.py`) validates
  schema and `artifact:` URIs, rejects storage locations, and fails if the
  bytes of a stored object are also committed.
- Fleet worker, live: `klt artifact verify manifests/artifacts/<file>` must
  exit 0. The pinned klt in `.github/klt-version` predates `klt artifact`, so
  CI cannot run this.

Manifest-forward only: evidence committed before this existed stays in place.
