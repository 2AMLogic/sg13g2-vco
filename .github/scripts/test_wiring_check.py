#!/usr/bin/env python3
"""Orphan-test guard (issue #228): every tracked shell self-test must be
reachable through an executable chain rooted in a check-all.sh target that
the `test` aggregate runs.  Parses only; never executes a registered test.

Registry: .github/scripts/test-wiring.tsv, one row per test, tab separated:
    <test path>  <root check-all.sh target>  <launcher path>
'#' lines and blank lines are ignored.  All paths are complete
repository-relative paths (never basenames).

Population (git ls-files, so untracked scratch files never count):
    .github/scripts/test-*.sh   sim/tests/test-*.sh   sim/*/tests/test*.sh
Python tests are out of scope (check-python.sh tests owns them, issue #202).

Accepted launcher syntax (deliberately narrow; a new wiring form must update
this checker and its mutation fixtures):
  * a non-comment command, after splitting on && || ; | & ( ) and `case`
    labels, whose words are one of
        run_gate    <name> <PATH> ...     (check-all.sh arms)
        run_fixture <name> <PATH> ...     (run-grading-fixtures.sh)
        <PATH> ...                        (bare invocation)
  * <PATH> is `$ROOT/<rel>`, `$SCRIPTS/<rel under .github/scripts>` or a plain
    repo-relative path; after normalisation it must equal the test path
    exactly.  Comments, echo/prose, substrings and `bash <path>` do not count.
Chain: root arm in check-all.sh gate() -> launcher (one level) -> test; when
the launcher is check-all.sh itself the arm invokes the test directly.  The
root target must also be a `gate <root>` line inside agg_test(), and the
`test)` arm of the final dispatch must call agg_test.

Exit: 0 wired, 1 violations (printed), 2 setup error.
"""
import argparse
import os
import posixpath
import re
import shlex
import subprocess
import sys

PATTERNS = [
    re.compile(r"^\.github/scripts/test-[^/]*\.sh$"),
    re.compile(r"^sim/tests/test-[^/]*\.sh$"),
    re.compile(r"^sim/[^/]+/tests/test[^/]*\.sh$"),
]
CHECK_ALL = ".github/scripts/check-all.sh"
OPS = {"&&", "||", ";", ";;", "|", "&", "(", ")"}
PATH_OK = re.compile(r"^[A-Za-z0-9._+@=-]+(/[A-Za-z0-9._+@=-]+)*$")


def tracked(root):
    out = subprocess.run(["git", "-C", root, "ls-files", "-z"], check=True,
                         stdout=subprocess.PIPE).stdout.decode()
    return set(p for p in out.split("\0") if p)


def bad_path(p):
    if not PATH_OK.match(p) or p.startswith("/"):
        return "not a clean repository-relative path"
    if any(c in ("", ".", "..") for c in p.split("/")):
        return "path traversal or empty component"
    return None


def words_of(line):
    lex = shlex.shlex(line, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    try:
        return list(lex)
    except ValueError:
        return []


def segments(line):
    seg = []
    for w in words_of(line):
        if w in OPS:
            if seg:
                yield seg
            seg = []
        else:
            seg.append(w)
    if seg:
        yield seg


def norm(word):
    word = word.replace("${ROOT}", "$ROOT").replace("${SCRIPTS}", "$SCRIPTS")
    if word.startswith("$ROOT/"):
        word = word[len("$ROOT/"):]
    elif word.startswith("$SCRIPTS/"):
        word = ".github/scripts/" + word[len("$SCRIPTS/"):]
    elif "$" in word or word.startswith("/"):
        return None
    return posixpath.normpath(word)


def invokes(lines, path):
    for line in lines:
        if line.lstrip().startswith("#"):
            continue
        for seg in segments(line):
            if seg[0] in ("run_gate", "run_fixture"):
                cand = seg[2] if len(seg) > 2 else None
            else:
                cand = seg[0]
            if cand is not None and norm(cand) == path:
                return True
    return False


def func_body(lines, name):
    start = None
    for i, l in enumerate(lines):
        if re.match(r"^%s\(\)\s*\{" % re.escape(name), l):
            start = i + 1
        elif start is not None and l.startswith("}"):
            return lines[start:i]
    return None if start is None else lines[start:]


def arms(body):
    """case arms of a function body: {label: [lines]}."""
    res, cur = {}, None
    for l in body:
        if cur is None:
            m = re.match(r"^\s*([A-Za-z0-9_-]+(?:\|[A-Za-z0-9_-]+)*)\)(.*)$", l)
            if not m:
                continue
            cur = [m.group(1).split("|"), []]
            l = m.group(2)
        cur[1].append(l)
        if ";;" in re.sub(r"\s#.*$", "", l):
            for lab in cur[0]:
                res[lab] = cur[1]
            cur = None
    return res


def read_registry(path, errors):
    rows = []
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        print("test-wiring: cannot read registry %s: %s" % (path, e),
              file=sys.stderr)
        sys.exit(2)
    for n, raw in enumerate(text.splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        f = raw.split("\t")
        if len(f) != 3 or any(not x for x in f):
            errors.append("MALFORMED registry line %d: expected 3 "
                          "tab-separated fields: %r" % (n, raw))
            continue
        test, target, launcher = f
        ok = True
        for what, p in (("test", test), ("launcher", launcher)):
            why = bad_path(p)
            if why:
                errors.append("MALFORMED registry line %d: %s path %r: %s"
                              % (n, what, p, why))
                ok = False
        if not re.match(r"^[A-Za-z0-9_-]+$", target):
            errors.append("MALFORMED registry line %d: bad root target %r"
                          % (n, target))
            ok = False
        if ok:
            rows.append((test, target, launcher, n))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.abspath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
    ap.add_argument("--registry")
    a = ap.parse_args()
    root = a.root
    reg = a.registry or os.path.join(root, ".github/scripts/test-wiring.tsv")
    try:
        files = tracked(root)
    except (OSError, subprocess.CalledProcessError) as e:
        print("test-wiring: git ls-files failed in %s: %s" % (root, e),
              file=sys.stderr)
        return 2
    errors = []
    rows = read_registry(reg, errors)

    seen = {}
    for test, target, launcher, n in rows:
        if test in seen:
            errors.append("DUPLICATE registry row for %s (lines %d and %d)"
                          % (test, seen[test], n))
        seen[test] = n

    candidates = set(f for f in files if any(p.match(f) for p in PATTERNS))
    reg_tests = set(r[0] for r in rows)
    for p in sorted(candidates - reg_tests):
        errors.append("ORPHAN: %s is a tracked shell self-test with no "
                      "registry row" % p)
    for p in sorted(reg_tests - candidates):
        errors.append("STALE: registry path %s is not a tracked file "
                      "matching the shell-test patterns" % p)

    def load(p):
        if p not in files:
            return None
        try:
            return open(os.path.join(root, p), encoding="utf-8").read().splitlines()
        except OSError:
            return None

    ca = load(CHECK_ALL)
    if ca is None:
        print("test-wiring: %s not tracked/readable" % CHECK_ALL,
              file=sys.stderr)
        return 2
    gate_arms = arms(func_body(ca, "gate") or [])
    agg = func_body(ca, "agg_test") or []
    agg_gates = set()
    for l in agg:
        if l.lstrip().startswith("#"):
            continue
        w = words_of(l)
        if len(w) == 2 and w[0] == "gate":
            agg_gates.add(w[1])
    final = arms(ca[[i for i, l in enumerate(ca)
                     if re.match(r"^case \"\$TARGET\" in", l)][-1] + 1:]
                 ) if any(re.match(r"^case \"\$TARGET\" in", l) for l in ca) else {}
    test_arm = final.get("test", [])
    if not any(w == "agg_test" for l in test_arm
               if not l.lstrip().startswith("#") for w in words_of(l)):
        errors.append("`test` aggregate in %s does not call agg_test" % CHECK_ALL)

    lcache = {}
    for test, target, launcher, n in rows:
        if test not in candidates:
            continue
        where = "%s (root %s, launcher %s)" % (test, target, launcher)
        if launcher not in files:
            errors.append("UNTRACKED launcher for %s" % where)
            continue
        if launcher != CHECK_ALL:
            if launcher not in lcache:
                lcache[launcher] = load(launcher)
            if lcache[launcher] is None or not invokes(lcache[launcher], test):
                errors.append("NOT LAUNCHED: %s has no executable invocation "
                              "of that exact path (comments/prose/basenames "
                              "do not count)" % where)
                continue
        arm = gate_arms.get(target)
        if arm is None:
            errors.append("NO ROOT: target %s has no arm in %s gate() for %s"
                          % (target, CHECK_ALL, where))
            continue
        if not invokes(arm, test if launcher == CHECK_ALL else launcher):
            errors.append("UNREACHABLE: arm %s in %s does not execute %s for "
                          "%s" % (target, CHECK_ALL,
                                  test if launcher == CHECK_ALL else launcher,
                                  where))
            continue
        if target not in agg_gates:
            errors.append("NOT IN TEST AGGREGATE: root target %s of %s is "
                          "not run by agg_test (the `test` aggregate)"
                          % (target, test))

    for e in errors:
        print("FAIL: " + e, file=sys.stderr)
    if errors:
        print("test-wiring: %d violation(s)" % len(errors), file=sys.stderr)
        return 1
    print("test-wiring: %d shell self-tests, all reachable from a `test` "
          "aggregate target" % len(candidates))
    return 0


if __name__ == "__main__":
    sys.exit(main())
