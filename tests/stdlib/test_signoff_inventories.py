"""Drift tests for signoff/inventories.py (issue #243; stdlib unittest only).

Each case runs in a throwaway copy of the files the inventories read, never in
the real tree. A drift gate that cannot fail is indistinguishable from no gate.

The drift cases drive the real `--check` / `--regen` CLI with `--root` rather
than calling `verify()` / `regen()` in-process, so the entry point CI invokes
is covered too (issue #334; before it, `main()` parsed no `--root` and these
cases had to bypass it).
"""
import os
import shutil
import tempfile
import unittest

from _loader import ROOT, load_module, run_script

inv = load_module("signoff_inventories", "signoff/inventories.py")

SKIP = shutil.ignore_patterns("records", "netlist-snapshots", "corners", "em-extraction")


def copy_tree(dst):
    for d in ("design", "spec", ".github", "signoff"):
        shutil.copytree(os.path.join(ROOT, d), os.path.join(dst, d), ignore=SKIP)
    shutil.copytree(os.path.join(ROOT, "sim"), os.path.join(dst, "sim"), ignore=SKIP)
    for f in ("README.md", "LICENSE"):
        shutil.copy(os.path.join(ROOT, f), dst)


class InventoryDrift(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name
        copy_tree(self.root)

    def check(self):
        """Run `--check --root <tmp>` and return the drift messages it named."""
        proc = run_script("signoff/inventories.py", "--check", "--root", self.root)
        fails = [l[len("FAIL: "):] for l in proc.stderr.splitlines() if l.startswith("FAIL: ")]
        # The exit code must agree with what was reported: 1 on drift, 0 clean.
        self.assertEqual(proc.returncode, 1 if fails else 0, proc.stderr)
        return fails

    def edit(self, rel, text="\n* drift\n"):
        with open(os.path.join(self.root, rel), "a") as f:
            f.write(text)

    def test_clean_tree_passes(self):
        self.assertEqual(self.check(), [])

    def test_edited_schematic_fails_by_name(self):
        self.edit("design/vco.sch")
        errs = self.check()
        self.assertTrue(any("design/vco.sch changed" in e for e in errs), errs)

    def test_edited_testbench_fails(self):
        self.edit("sim/phase-noise/testbench/tb_vco_port_noise.spice.tmpl")
        self.assertTrue(any("tb_vco_port_noise" in e for e in self.check()))

    def test_edited_readme_fails(self):
        self.edit("README.md")
        self.assertTrue(any("README.md" in e for e in self.check()))

    def test_new_testbench_fails(self):
        self.edit("sim/phase-noise/testbench/tb_new.spice.tmpl", "* new\n")
        self.assertTrue(any("tb_new" in e and "not in the inventory" in e for e in self.check()))

    def test_deleted_member_fails(self):
        os.remove(os.path.join(self.root, "LICENSE"))
        self.assertTrue(self.check())

    def test_regen_after_edit_passes(self):
        self.edit("design/vco.sch")
        proc = run_script("signoff/inventories.py", "--regen", "--root", self.root)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(self.check(), [])

    def test_cli_root_is_honored_not_silently_ignored(self):
        """`--root` must grade the named tree, not the repository it lives in.

        Before issue #334, `main()` parsed no `--root`: `--check --root <tmp>`
        graded the real tree instead and so passed however drifted <tmp> was.
        """
        self.edit("README.md")
        proc = run_script("signoff/inventories.py", "--check", "--root", self.root)
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("README.md", proc.stderr)
        # The real tree is clean -- exactly what a --root-ignoring CLI reports.
        self.assertEqual(run_script("signoff/inventories.py", "--check").returncode, 0)

    def test_cli_rejects_unknown_mode(self):
        proc = run_script("signoff/inventories.py", "--bogus")
        self.assertEqual(proc.returncode, 2, proc.stderr)
        self.assertIn("Audited inventories", proc.stderr)

    def test_hand_edited_envelope_fails(self):
        self.edit(inv.ITEM_INVENTORY[10], "\n")
        self.assertTrue(any("not bound" in e or "pin" in e for e in self.check()))

    def test_blocked_benches_listed_not_omitted(self):
        tb = inv.build_testbenches(inv.REPO_ROOT)["testbenches"]
        blocked = {t["path"]: t for t in tb if t["status"] == "shipped-but-not-yet-graded"}
        core = "sim/oscillator-core/testbench/tb_vco_core_margin.spice.tmpl"
        pn = "sim/phase-noise/testbench/tb_vco_port_noise.spice.tmpl"
        self.assertEqual(blocked[core]["blocked_by"], ["#50", "#94"])
        self.assertEqual(blocked[pn]["blocked_by"], ["#53", "#94"])

    def test_item1_summary_states_gate_did_not_run(self):
        self.assertIn("did NOT run", inv.SUMMARY[1])


if __name__ == "__main__":
    unittest.main()
