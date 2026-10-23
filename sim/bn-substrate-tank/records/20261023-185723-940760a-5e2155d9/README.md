# Tank A/B live artifact-store run (issue #253)

- Run id: `20261023-185723-940760a-5e2155d9`, commit `940760a`, host `loom-worker-2`.
- Command: `sim/bn-substrate-tank/run_tank_ab.sh` (default matrix, batch backend).
- Result: 10 units, `collection failures: 0`.
- Storage: each unit's `out/` packed into `<variant>__<corner>.out.tar.gz`
  (reproducible tar + `gzip -n`) and stored with `klt artifact put`: 10 broker
  calls, no HTTP 429 (the per-file attempt of 270 puts was rate limited).
- Manifest: `manifests/artifacts/bn-substrate-tank-20261023-185723-940760a-5e2155d9.manifest.json`
  (10 entries, every `uri` starts with `artifact:`). Raw bytes are not committed.
- `klt artifact verify <manifest>`: exit 0, `ok (0 of 10 failed)`, using
  `klt 0.7.1.dev2518+g5f7d2a67bd80` on this worker.
