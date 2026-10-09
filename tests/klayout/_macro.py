"""Helpers for the klayout-dependent tests (needs the pinned `klayout` wheel).

snap_grid.py, break_ring.py and prune_spirals.py are `klayout -zz -r` macros:
they have no imports and rely on a global `pya` plus `-rd` variables. They are
executed here with exec(), injecting klayout.db as `pya` and the -rd variables
as globals -- the same contract the klayout binary provides.
"""
import contextlib
import io
import os

import klayout.db as kdb

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def run_macro(rel_path, **variables):
    """Execute a macro; return (exit_code, stdout, stderr). 0 on clean return."""
    path = os.path.join(ROOT, rel_path)
    with open(path) as fh:
        code = compile(fh.read(), path, "exec")
    env = {"__name__": "__main__", "__file__": path, "pya": kdb}
    env.update(variables)
    out, err = io.StringIO(), io.StringIO()
    rc = 0
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            exec(code, env)
        except SystemExit as e:
            rc = e.code if isinstance(e.code, int) else 1
    return rc, out.getvalue(), err.getvalue()
