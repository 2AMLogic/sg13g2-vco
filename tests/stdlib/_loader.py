"""Shared helpers for the stdlib known-answer tests (no third-party imports)."""
import importlib.util
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def load_module(name, rel_path):
    """Import a repo script by path. Only for scripts with a main guard."""
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, rel_path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run_script(rel_path, *args):
    """Run a top-level-code script in a subprocess (isolated mode)."""
    return subprocess.run(
        [sys.executable, "-I", os.path.join(ROOT, rel_path)] + list(args),
        capture_output=True, text=True)
