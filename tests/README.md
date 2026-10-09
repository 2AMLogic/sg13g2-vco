# tests/

Python known-answer tests for the repo's scripts (issue #118). Run through the
shared runner: `.github/scripts/check-all.sh py-tests` (stdlib) and
`py-klayout` (needs the `klayout` wheel pinned in
`.github/klayout-pip-version`; set `PYTHON` to a venv interpreter that has it).

- `stdlib/` -- stdlib `unittest` only: `layout/scripts/manifest.py`,
  `sim/bn-substrate-tank/{analyze,make_requests}.py`. The two sim scripts run
  at import time, so they are driven as `python3 -I` subprocesses on synthetic
  or temp-dir inputs and never write under `sim/`.
- `klayout/` -- `snap_grid.py`, `break_ring.py`, `prune_spirals.py` (klayout
  macros: executed with `pya` and the `-rd` variables injected) and
  `lvsdb_summary.py` (run against a tiny real `.lvsdb`).

Not covered, by design: `floorplan.py` and `lvs_reference.py` (IHP deck), and
the `sim/inductor-model/em-extraction` scripts (numpy/scipy/openEMS); those are
only syntax-checked by `py-compile`.
