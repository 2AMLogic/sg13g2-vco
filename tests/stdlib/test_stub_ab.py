"""Known-answer tests for sim/tank-stub-load/analyze.py (issue #462).

The analyzer runs all its work at import time (no main guard), so it is
exercised as a subprocess in isolated mode (python3 -I), never imported
(same contract as test_tank_ab.py). The tests only read the committed
inputs and write under a temp dir; they do not touch sim/ results.

Issue #462: the request/report inventory (union of returned reports and
submitted requests) is shared with sim/bn-substrate-tank/analyze.py, so a
unit whose report never came back still gets one NO-REPORT coverage row
per requested corner, --strict exits 2, and the complete committed record
still reproduces its four CSVs byte for byte.

Issue #470: the request-level coverage of a returned report (its request
file absent or unreadable) is likewise decided by the shared inventory
helper and recorded exactly once per returned report by both entry points,
whatever the report's corner list: an empty report no longer passes
--strict with a header-only coverage CSV.
"""
import csv
import json
import os
import shutil
import tempfile
import unittest

from _loader import ROOT, run_script

ANALYZE = "sim/tank-stub-load/analyze.py"
SUBSTRATE_ANALYZE = "sim/bn-substrate-tank/analyze.py"
RECORD = "sim/tank-stub-load/records/20261121-074401-e6b0670-226451eb"
CSVS = ("stub-ab.csv", "stub-ab-delta.csv", "stub-ab-tuning.csv",
        "stub-ab-coverage.csv")
ENTRY_POINTS = ((ANALYZE, "stub-ab-coverage.csv"),
                (SUBSTRATE_ANALYZE, "tank-ab-coverage.csv"))
EMPTY_REPORT = {"corners": []}


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        json.dump(obj, fh)


def report(f0, fp45, fm45, zpk, process="cap_typ", temp=27, status="pass"):
    ms = [{"name": "f0", "value": f0}, {"name": "f_p45", "value": fp45},
          {"name": "f_m45", "value": fm45}, {"name": "zpk", "value": zpk}]
    return {"corners": [{"process": process, "temperature_c": temp,
                         "status": status, "measurements": ms}],
            "environment": {"remote": {"job_id": "job-1"}}}


def multi_corner_report(*corners):
    """A returned report with one passing, valid corner per (process, temp)."""
    return {"corners": [report(5e9, 4.5e9, 5.5e9, 100.0, process, temp)["corners"][0]
                        for process, temp in corners]}


def add_point(rec, variant, mos, vctrl, rpt):
    name = "%s__%s_v%s" % (variant, mos, vctrl)
    write_json(os.path.join(rec, "reports", name + ".json"), rpt)
    write_json(os.path.join(rec, "decks", name + ".cell.json"),
               {"mos": mos, "vctrl": vctrl})


def add_request(rec, variant, mos, vctrl, processes, temps):
    name = "%s__%s_v%s" % (variant, mos, vctrl)
    write_json(os.path.join(rec, "decks", name + ".request.json"),
               {"corners": {"process": [{"name": p, "sections": [p]} for p in processes],
                            "temperature_c": list(temps)}})


def read_csv(path):
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh))


class SyntheticRecordTests(unittest.TestCase):
    """Fixture records built from scratch, exercising both CLI entry points
    with the absent-report fixture of tests/stdlib/test_tank_ab.py."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.rec = self._tmp.name

    def test_absent_report_with_request_is_no_report(self):
        # One request for two temperatures, no report at all: every requested
        # corner gets an explicit NO-REPORT outcome (never silently dropped),
        # from BOTH entry points sharing the inventory discovery.
        add_request(self.rec, "stub", "tt", 1.5, ["cap_typ"], [27, 125])
        for script, coverage_csv in ((ANALYZE, "stub-ab-coverage.csv"),
                                     (SUBSTRATE_ANALYZE, "tank-ab-coverage.csv")):
            with self.subTest(script=script):
                p = run_script(script, self.rec)
                self.assertEqual(p.returncode, 0, p.stderr)
                cov = read_csv(os.path.join(self.rec, coverage_csv))
                self.assertEqual([c["outcome"] for c in cov], ["NO-REPORT"] * 2)
                self.assertEqual([c["process"] for c in cov], ["cap_typ"] * 2)
                self.assertEqual(sorted(c["temp_c"] for c in cov), ["125", "27"])
                strict = run_script(script, self.rec, "--strict")
                self.assertEqual(strict.returncode, 2, strict.stderr)
        rows = read_csv(os.path.join(self.rec, "stub-ab.csv"))
        self.assertEqual([r["status"] for r in rows], ["NO-REPORT"])
        self.assertEqual(rows[0]["variant"], "stub")
        self.assertEqual(rows[0]["point"], "tt_v1.5")

    def test_report_without_request_still_reduced(self):
        # Union discovery must keep plain report-only names: the report is
        # still reduced, and its absent request gets one request-level
        # COVERAGE-UNCHECKED row (issue #470).
        add_point(self.rec, "nostub", "tt", 1.5, report(5e9, 4.5e9, 5.5e9, 100.0))
        p = run_script(ANALYZE, self.rec)
        self.assertEqual(p.returncode, 0, p.stderr)
        rows = read_csv(os.path.join(self.rec, "stub-ab.csv"))
        self.assertEqual([r["status"] for r in rows], ["ok"])
        cov = read_csv(os.path.join(self.rec, "stub-ab-coverage.csv"))
        self.assertEqual([c["outcome"] for c in cov], ["COVERAGE-UNCHECKED"])
        self.assertEqual(run_script(ANALYZE, self.rec, "--strict").returncode, 2)

    def test_empty_directory_is_gap(self):
        p = run_script(ANALYZE, self.rec)
        self.assertEqual(p.returncode, 0, p.stderr)
        cov = read_csv(os.path.join(self.rec, "stub-ab-coverage.csv"))
        self.assertEqual([c["outcome"] for c in cov], ["EMPTY-INVENTORY"])
        self.assertEqual(run_script(ANALYZE, self.rec, "--strict").returncode, 2)


class RequestLevelCoverageTests(unittest.TestCase):
    """Issue #470: the request-level status of a returned report -- request
    file absent (COVERAGE-UNCHECKED) or unreadable (REQUEST-UNREADABLE) -- is
    decided by the shared inventory helper and recorded exactly once per
    returned report by BOTH entry points, whatever the report's corner list.
    Before #470 the stub analyzer recorded it per visited corner, so an empty
    report left a header-only coverage CSV and --strict exited 0."""

    # request file body (None: absent), expected outcome, expected detail prefix
    REQUESTS = ((None, "COVERAGE-UNCHECKED", "no decks/"),
                ("{ nope", "REQUEST-UNREADABLE", "request unreadable"))

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name

    def _units(self, mos_list, rpt, body):
        """A fresh record holding one returned unit per mos (all stub, Vctrl
        1.5 V) with the same report and the same request state: body None
        leaves no request file, otherwise it is the raw request-file text."""
        rec = tempfile.mkdtemp(dir=self.root)
        for mos in mos_list:
            add_point(rec, "stub", mos, 1.5, rpt)
            if body is not None:
                with open(os.path.join(rec, "decks", "stub__%s_v1.5.request.json" % mos),
                          "w") as fh:
                    fh.write(body)
        return rec

    def _assert_one_request_level_row_per_report(self, rec, outcome, detail, mos_list):
        """Both entry points: exactly one request-level coverage row per
        returned unit (that unit's variant/point, blank process/temp), exit 0
        by default and 2 under --strict."""
        for script, coverage_csv in ENTRY_POINTS:
            with self.subTest(request=outcome, script=script):
                p = run_script(script, rec)
                self.assertEqual(p.returncode, 0, p.stderr)
                cov = read_csv(os.path.join(rec, coverage_csv))
                self.assertEqual([(c["outcome"], c["variant"], c["point"], c["process"],
                                   c["temp_c"]) for c in cov],
                                 [(outcome, "stub", "%s_v1.5" % mos, "", "")
                                  for mos in mos_list])
                for c in cov:
                    self.assertTrue(c["detail"].startswith(detail), c["detail"])
                strict = run_script(script, rec, "--strict")
                self.assertEqual(strict.returncode, 2, strict.stderr)

    def test_empty_report_records_absent_or_unreadable_request_once(self):
        # The issue's table: one returned report {"corners": []}; only the
        # request varies.  The gap must be recorded without visiting a corner.
        for body, outcome, detail in self.REQUESTS:
            rec = self._units(["tt"], EMPTY_REPORT, body)
            self._assert_one_request_level_row_per_report(rec, outcome, detail, ["tt"])

    def test_multi_corner_report_gets_one_row_per_report(self):
        # Once per returned report, never per visited corner: two units of
        # three corners each with the same request state give exactly two
        # request-level rows, one per unit.
        units = ["ss", "tt"]
        rpt = multi_corner_report(("cap_typ", 27), ("cap_typ", 125), ("cap_bcs", 27))
        for body, outcome, detail in self.REQUESTS:
            rec = self._units(units, rpt, body)
            self._assert_one_request_level_row_per_report(rec, outcome, detail, units)

    def test_valid_request_with_empty_report_is_missing_corner(self):
        # The third row of the issue's table: a readable request is covered
        # by its per-corner rows, so the empty report is all MISSING-CORNER.
        rec = self._units(["tt"], EMPTY_REPORT, None)
        add_request(rec, "stub", "tt", 1.5, ["cap_typ"], [27])
        for script, coverage_csv in ENTRY_POINTS:
            with self.subTest(script=script):
                p = run_script(script, rec)
                self.assertEqual(p.returncode, 0, p.stderr)
                cov = read_csv(os.path.join(rec, coverage_csv))
                self.assertEqual([(c["outcome"], c["process"], c["temp_c"]) for c in cov],
                                 [("MISSING-CORNER", "cap_typ", "27")])
                self.assertEqual(run_script(script, rec, "--strict").returncode, 2)


class PartialRecordTests(unittest.TestCase):
    """Issue #462 acceptance: the committed stub record with the returned
    report for stub__tt_v1.5 omitted and its request present -- 81 measured
    corners and nine explicit missing-report outcomes."""

    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.rec = os.path.join(cls._tmp.name, "record")
        shutil.copytree(os.path.join(ROOT, RECORD), cls.rec)
        for fn in CSVS:  # remove so stale copies cannot satisfy the checks
            os.remove(os.path.join(cls.rec, fn))
        os.remove(os.path.join(cls.rec, "reports", "stub__tt_v1.5.json"))
        cls.proc = run_script(ANALYZE, cls.rec)

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_default_mode_exits_zero(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stderr)

    def test_strict_mode_exits_two(self):
        s = run_script(ANALYZE, self.rec, "--strict")
        self.assertEqual(s.returncode, 2, s.stderr)

    def test_nine_explicit_missing_report_outcomes(self):
        cov = read_csv(os.path.join(self.rec, "stub-ab-coverage.csv"))
        missing = [c for c in cov if c["outcome"] == "NO-REPORT"]
        self.assertEqual(len(missing), 9)
        self.assertEqual({(c["variant"], c["point"]) for c in missing},
                         {("stub", "tt_v1.5")})
        self.assertEqual(sorted((c["process"], c["temp_c"]) for c in missing),
                         sorted((pr, str(t)) for pr in
                                ("cap_typ", "cap_bcs", "cap_wcs")
                                for t in (-40, 27, 125)))

    def test_measured_corners_unchanged(self):
        cov = read_csv(os.path.join(self.rec, "stub-ab-coverage.csv"))
        self.assertEqual(len(cov), 90)
        self.assertEqual(sum(c["outcome"] == "ok" for c in cov), 81)

    def test_stub_ab_csv_carries_one_no_report_row(self):
        rows = read_csv(os.path.join(self.rec, "stub-ab.csv"))
        self.assertEqual(len(rows), 82)
        self.assertEqual(sum(r["status"] == "ok" for r in rows), 81)
        self.assertEqual([r["status"] for r in rows if r["status"] != "ok"],
                         ["NO-REPORT"])

    def test_delta_pairs_drop_to_36(self):
        delta = read_csv(os.path.join(self.rec, "stub-ab-delta.csv"))
        self.assertEqual(len(delta), 36)


class CompleteRecordTests(unittest.TestCase):
    """Issue #462 acceptance: the untouched committed record reproduces all
    four CSVs byte for byte and --strict stays at exit 0 (no gaps)."""

    @classmethod
    def setUpClass(cls):
        cls._tmp = tempfile.TemporaryDirectory()
        cls.rec = os.path.join(cls._tmp.name, "record")
        shutil.copytree(os.path.join(ROOT, RECORD), cls.rec)
        for fn in CSVS:  # force regeneration, never compare stale copies
            os.remove(os.path.join(cls.rec, fn))
        cls.proc = run_script(ANALYZE, cls.rec)

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_exits_clean(self):
        self.assertEqual(self.proc.returncode, 0, self.proc.stderr)

    def test_strict_exits_zero(self):
        s = run_script(ANALYZE, self.rec, "--strict")
        self.assertEqual(s.returncode, 0, s.stderr)

    def test_all_four_csvs_byte_identical(self):
        for fn in CSVS:
            with open(os.path.join(self.rec, fn), "rb") as fh:
                got = fh.read()
            with open(os.path.join(ROOT, RECORD, fn), "rb") as fh:
                want = fh.read()
            self.assertEqual(got, want, fn)


if __name__ == "__main__":
    unittest.main()
