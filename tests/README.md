# tests/

Python known-answer tests for the repo's scripts (issue #118). Run through the
shared runner: `.github/scripts/check-all.sh py-tests` (stdlib) and
`py-klayout` (needs the `klayout` wheel pinned in
`.github/klayout-pip-version`; set `PYTHON` to a venv interpreter that has it).

- `stdlib/` -- stdlib `unittest` only: `layout/scripts/manifest.py`,
  `sim/bn-substrate-tank/{analyze,make_requests}.py`. The two sim scripts run
  at import time, so they are driven as `python3 -I` subprocesses on synthetic
  or temp-dir inputs and never write under `sim/`.
- `numeric/` -- stdlib `unittest` plus numpy and scipy (declared in
  `.github/numeric-requirements.txt`; use a venv, e.g.
  `PYTHON=/path/to/venv/bin/python`): the `sim/inductor-model/em-extraction`
  post/fit stages on synthetic solver-free fixtures (issue #167) -- failure
  contract, preserved outputs and a known-answer publish. Runs through
  `check-all.sh py-numeric` (missing numpy/scipy is a failure there; in `all` it
  is counted as a skip). Not part of `py-tests`/`test`, which stay stdlib-only.
- `klayout/` -- `snap_grid.py`, `break_ring.py`, `prune_spirals.py` (klayout
  macros: executed with `pya` and the `-rd` variables injected),
  `lvsdb_summary.py` (run against a tiny real `.lvsdb`), `lvs_inductor_ctl.py`,
  and, on toy streams with no PDK (issue #161): `verify.py` (flattened PCell
  counts incl. arrays and uniquified names, layer set, labels, bbox, fatal
  EM-only layer), `lvs_break.py` (remove-by-prefix, non-zero exit on an
  unmatched prefix, input untouched) and `ihp_deck_facts.py` (EdgeSeal shape
  count, merged flattened MIM area, Mim_gR from a stub rule table). All
  fixtures live in temp dirs; nothing is written under `layout/` or `sim/`.

Not covered, by design (only syntax-checked by `py-compile` where Python):

- `layout/scripts/measure_ports.py` -- reads real `klt gen --pdk-pcell` output
  and asserts PDK-specific geometry (pin boxes, PCell texts, GatPoly/nSD
  overlaps); a synthetic stand-in would only restate its own assumptions.
- `layout/scripts/floorplan.py`, `lvs_reference.py` -- need the IHP deck.
- `layout/scripts/ihp_deck_categories.py` -- static walk of IHP's DRC runset
  source; needs the deck checkout.
- `layout/scripts/activ_mask_overlay.py` -- one-off diagnostic experiment on
  the committed stream, deliberately never evidence.
- `layout/scripts/lvs_label_order.rb` -- Ruby, runs inside KLayout's LVS DSL
  ahead of IHP's runset; exercised by `layout/lvs.sh`, not here.
- `layout/scripts/native_drc_env.sh`, `pdk_env.sh` -- shell environment
  helpers, covered by shell lint.
- the openEMS solve scripts of `sim/inductor-model/em-extraction`
  (`run_openems.py`, `gen_geometry.py`, `compare_analytic.py`); its post/fit
  stages are covered by `numeric/`.
