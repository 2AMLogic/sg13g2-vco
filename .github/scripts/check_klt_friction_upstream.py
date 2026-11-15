#!/usr/bin/env python3
"""Upstream-state comparison for the friction ledger (issue #333).

Companion to check_klt_friction.py (issue #146), which validates ledger
structure offline. This gate reads the same
.github/klt-friction-ledger.json, fetches each entry's live state from the
upstream tracker named by the ledger's "upstream" field
(2AMLogic/klayout-tools) and compares it with the hand-maintained "status"
field using the three-way mapping the ledger's vocabulary requires:

    ledger "open"   => upstream issue/PR is open
    ledger "closed" => upstream is closed (merged or not)
    ledger "merged" => upstream is a pull request with merged == true

A state that cannot be read (network failure, 403/429 rate limit, 404)
is reported UNREADABLE and never counts as agreement
(.loom/docs/ci-principles.md rule 6: a check that cannot run must not
look like a check that passed).

--states-file PATH replaces the network with a JSON object mapping the
issue number (as a string) to "open" | "closed" | "merged" |
"unreadable" (null also means unreadable; a missing number is
unreadable). The self-test drives every comparison path through it, so
it stays offline and deterministic.

The tracker is public; the checker sends `Authorization: Bearer
$GITHUB_TOKEN` when that variable is non-empty and falls back to
anonymous, so no secret is required.

Usage: check_klt_friction_upstream.py [--root DIR] [--states-file PATH]

Exit: 0 every entry compared and agreeing,
      1 at least one real disagreement (each printed with both states);
        when disagreements and unreadables coexist, 1 wins - a definite
        violation outranks an incomplete comparison,
      3 no disagreement, but one or more states unreadable (printed),
      2 usage error, unreadable ledger or malformed entry (structure is
        check_klt_friction.py's job; run `check-all.sh friction` first).
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

LEDGER = ".github/klt-friction-ledger.json"
DEFAULT_UPSTREAM = "2AMLogic/klayout-tools"
STATUSES = ("open", "closed", "merged")
API_ROOT = "https://api.github.com"
TIMEOUT = 30  # seconds per request; 32 entries cost 32 (+PR) requests


class SetupError(Exception):
    """Usage or ledger problem: exit 2."""


class Unreadable(Exception):
    """The upstream state of one entry could not be read."""


def load_entries(root):
    """Return [(number, status)] from the ledger; raise SetupError if malformed."""
    path = os.path.join(root, LEDGER)
    try:
        with open(path, encoding="utf-8") as fh:
            ledger = json.load(fh)
    except (OSError, ValueError) as exc:
        raise SetupError("cannot read %s: %s (run check-all.sh friction first)"
                         % (LEDGER, exc))
    entries = ledger.get("entries") if isinstance(ledger, dict) else None
    if not isinstance(entries, list):
        raise SetupError("%s: top level must be an object with an 'entries' list"
                         % LEDGER)
    out = []
    for i, e in enumerate(entries):
        if not isinstance(e, dict) or not isinstance(e.get("number"), int) \
                or e.get("status") not in STATUSES:
            raise SetupError("%s entry %d is malformed (needs integer 'number' "
                             "and status in %s); run check-all.sh friction first"
                             % (LEDGER, i, list(STATUSES)))
        out.append((e["number"], e["status"]))
    upstream = ledger.get("upstream")
    if not isinstance(upstream, str) or "/" not in upstream:
        upstream = DEFAULT_UPSTREAM
    return out, upstream


def api_get(url, token):
    headers = {"Accept": "application/vnd.github+json",
               "X-GitHub-Api-Version": "2022-11-28",
               "User-Agent": "sg13g2-vco-friction-upstream-gate"}
    if token:
        headers["Authorization"] = "Bearer %s" % token
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_state(number, upstream, token, api_root):
    """Reduce the upstream item to "open" | "closed" | "merged".

    Raises Unreadable on any network, HTTP or payload problem: 403/429
    (rate limit), 404, 5xx, timeouts and malformed JSON are all "cannot
    read", never "agrees".
    """
    def get(path):
        try:
            return api_get("%s/repos/%s%s" % (api_root, upstream, path), token)
        except urllib.error.HTTPError as exc:
            raise Unreadable("HTTP %d for %s%s" % (exc.code, upstream, path))
        except (urllib.error.URLError, OSError, ValueError) as exc:
            raise Unreadable("%s: %s" % (path, exc))

    issue = get("/issues/%d" % number)
    if not isinstance(issue, dict) or "state" not in issue:
        raise Unreadable("issues/%d: unexpected payload" % number)
    if not isinstance(issue.get("pull_request"), dict):
        return issue["state"], ""
    # A PR's issues-endpoint state is "closed" whether merged or not;
    # the ledger's "merged" status needs the pulls endpoint.
    pull = get("/pulls/%d" % number)
    if not isinstance(pull, dict) or not isinstance(pull.get("merged"), bool):
        raise Unreadable("pulls/%d: unexpected payload" % number)
    if pull["merged"]:
        return "merged", str(pull.get("merged_at") or "")
    return "closed", str(pull.get("closed_at") or "")


def states_from_file(path):
    """Return {number: state-or-None} from a --states-file JSON object."""
    try:
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
    except (OSError, ValueError) as exc:
        raise SetupError("cannot read states file %s: %s" % (path, exc))
    if not isinstance(raw, dict):
        raise SetupError("states file %s must be a JSON object of "
                         "number -> state" % path)
    states = {}
    for key, value in raw.items():
        try:
            number = int(key)
        except (TypeError, ValueError):
            raise SetupError("states file %s: key %r is not an issue number"
                             % (path, key))
        if value is None:
            states[number] = None
            continue
        if value not in STATUSES and value != "unreadable":
            raise SetupError("states file %s: %r must be one of %s or "
                             "'unreadable'" % (path, value,
                                               list(STATUSES) + ["unreadable"]))
        states[number] = None if value == "unreadable" else value
    return states


def agrees(ledger_status, upstream_state):
    if ledger_status == "open":
        return upstream_state == "open"
    if ledger_status == "closed":
        return upstream_state in ("closed", "merged")
    return upstream_state == "merged"


def main(argv):
    default_root = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "..")
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--root", default=default_root)
    ap.add_argument("--states-file")
    args = ap.parse_args(argv[1:])
    root = os.path.abspath(args.root)

    try:
        entries, upstream = load_entries(root)
    except SetupError as exc:
        sys.stderr.write("FAIL: %s\n" % exc)
        return 2
    if args.states_file:
        try:
            states = states_from_file(args.states_file)
        except SetupError as exc:
            sys.stderr.write("FAIL: %s\n" % exc)
            return 2

        def lookup(number):
            if number not in states:
                return None, "absent from the states file"
            return states[number], ""
    else:
        token = os.environ.get("GITHUB_TOKEN", "").strip()
        api_root = os.environ.get("GITHUB_API_URL", API_ROOT).strip() or API_ROOT

        def lookup(number):
            try:
                return fetch_state(number, upstream, token, api_root)
            except Unreadable as exc:
                return None, str(exc)

    disagreements, unreadable = [], []
    for number, status in entries:
        state, why = lookup(number)
        if state is None:
            unreadable.append((number, why))
            sys.stderr.write("UNREADABLE: #%d: %s\n" % (number, why))
        elif not agrees(status, state):
            disagreements.append((number, status, state))
            sys.stderr.write("FAIL: ledger entry #%d: status '%s' but upstream "
                             "is '%s'\n" % (number, status, state))

    if disagreements:
        print("friction-upstream: %d disagreement(s), %d unreadable of %d "
              "entries" % (len(disagreements), len(unreadable), len(entries)))
        return 1
    if unreadable:
        print("friction-upstream INCOMPLETE: %d of %d entries agree, %d "
              "unreadable (listed above); unreadable never counts as agreement"
              % (len(entries) - len(unreadable), len(entries), len(unreadable)))
        return 3
    print("friction-upstream OK: %d entries agree with %s"
          % (len(entries), upstream))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
