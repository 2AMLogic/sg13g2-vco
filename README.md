# sg13g2-vco

An LC voltage-controlled oscillator on IHP SG13G2 on
[IHP SG13G2](https://github.com/IHP-GmbH/IHP-Open-PDK), IHP's open-source 130 nm SiGe BiCMOS PDK — designed by AI agents driving
[klayout-tools](https://github.com/2AMLogic/klayout-tools) and the
open-source xschem + ngspice flow.

**Status: schematic and layout committed; validation incomplete.** The
[target specification](spec/target-spec.md) is ratified as targets. The
[schematic](design/README.md), [simulation benches](sim/README.md), and
[reproducible layout](layout/README.md) are committed, with native DRC
evidence and coverage limits documented in
[layout provenance](layout/PROVENANCE.md). LVS closure and the graded PVT
simulation grids remain outstanding. A device-aware LVS has run: IHP's runset as shipped
still reports `mismatch`, but after the reviewed spiral label-order step (#80)
the cross-reference compare reaches `match`, while its strict top-port check
still logs three port-name findings (#162; provenance §14.6). That is not LVS
closure: no `klt lvs` report exists (klayout-tools#2849) and the acceptable
signoff envelope is still owed (#62; [signoff notes](signoff/README.md)). Simulation numbers in the tree
predate #79 and are not current; the re-tune closed with no defensible candidate (#93), the decision is pending in [DR-006](spec/decision-records/DR-006-row2-shortfall-bn-substrate-varactor.md) (#184, status proposed), and regeneration (#94) is sequenced after it. The
[signoff report](signoff/t1-report.json) is the verdict of record.

**Built agent-native.** Every specification, decision record, testbench, and
line of documentation here is produced by AI agents working from a ratified
spec and an append-only evidence trail — not human-authored work that agents
merely assisted with. Verification is the product: every claim traces to a
recorded result under PVT corners. Where the agents hit friction with the
open-source tooling — most often
[klayout-tools](https://github.com/2AMLogic/klayout-tools) — that friction is
filed as a public issue against the tool itself, so the fix benefits everyone
using this PDK, not just this repo.

## Why this block, on this PDK

An LC VCO is the first block in this catalog that exists *because* of what
SG13G2 is: a SiGe BiCMOS process whose HBTs and PDK-shipped passives (MIM
caps, spiral inductors) are meant for RF work. The sibling PLL canaries
(gf180-pll, sky130-pll, sg13g2-pll) use ring or CMOS oscillators; nothing in
the catalog yet demonstrates an LC tank, a cross-coupled negative-gm pair,
or a phase-noise budget. This is a new block, not a port — start from the
published LC-VCO literature and the PDK's own passive/HBT models, not from a
sibling repo's schematics.

The honest centerpiece is **phase noise, and how it is measured with open
tools**. ngspice has no PSS/pnoise analysis; a phase-noise number here must
come from a documented open-tool method (long transient plus spectral
estimation, or an ISF/impulse method), with the method's limits stated next
to every number. A phase-noise claim without its measurement method is not a
result. Expect and file tool friction — that is this canary's job.

## Target specification (ratified targets)

All 12 rows of the [target specification](spec/target-spec.md) are ratified
as targets through DR-003 and DR-004, including the frequency band, tuning
range, phase noise, supply/power, and output swing. Ratification sets the
requirements; it does not establish that measurements meet them. The graded
corner grids and remaining validation evidence are still outstanding.

## Local checks

The repository's PDK-free gates run through one runner,
[`.github/scripts/check-all.sh`](.github/scripts/check-all.sh). The CI
workflows call its named targets step by step, and the npm scripts call its
aggregates, so local runs and CI use the same list of gates. The runner
installs nothing and fetches nothing. A missing required tool or a failing
gate makes the run exit nonzero. Every gate in an aggregate runs, and a
summary at the end counts the passed, failed and skipped gates.

| Command | Gates run | Requires |
|---|---|---|
| `npm test` | self-tests for shell lint, signoff drift, sim append-only, spec-DR and record-id reservation, plus the runner's own self-test, the grader-constants-vs-ratified-spec agreement gate and its mutation self-test, the record-currency gates, the simulator-free grading fixtures (emit-tuning, row 3, row 7, waveform-validity, stage-2 supply; run from a disposable copy of the tracked tree, roughly 80 s), then the Python gates (their self-test with a deliberately failing fixture, `py_compile` of every tracked `*.py`, and the stdlib known-answer tests in `tests/stdlib`) | bash, git, `shellcheck`, `python3`, `klt` at the version in [`.github/klt-version`](.github/klt-version) |
| `npm run check:ci` | `lint` (shellcheck at warning+), then everything in `npm test` | same as `npm test` |
| `npm run check:all` | `check:ci`, then the real signoff drift gate, then the klayout-dependent Python tests (`tests/klayout`; skipped if the `klayout` wheel is not importable), then the PR diff gates (only when `--base` is given), then the method known-answer checks | same, plus the `klayout` wheel at the version in [`.github/klayout-pip-version`](.github/klayout-pip-version) and ngspice 42 for the method checks |
| `npm run check:pr -- --base REF [--head REF]` | sim append-only and spec-change-has-DR, comparing REF with the checked-out HEAD | git, plus REF fetched locally |

`check:ci` is the lightweight lint-plus-self-test contract. Passing it does
not prove that every workflow will pass: the real signoff gate, the PR diff
gates and the method checks are only in `check:all`, or you can run them as
single targets (`check-all.sh grading-fixtures` runs just the grading fixtures; `check-all.sh signoff`, `check-all.sh pr-diff --base
origin/main`, `check-all.sh method [artifact-dir]`).

In `check:all`, two kinds of gate are optional. If ngspice 42 is not on
PATH, or a different version is, the runner prints `SKIPPED: method: ngspice
42 not found (...)`. If no `--base` is given, it prints `SKIPPED: pr-diff`.
The summary counts these as skipped, never as passed. Add `--strict`
(`npm run check:all -- --strict --base origin/main`) to make any skip fail
the run. Run as a single target, `method` always requires ngspice 42. It
forwards the artifact directory to
[`run-method-checks.sh`](.github/scripts/run-method-checks.sh), so the logs
stay there even when a check fails. `method` runs the same grading fixtures through the shared
[`run-grading-fixtures.sh`](.github/scripts/run-grading-fixtures.sh), so the two cannot drift.

To run the diff gates locally, fetch the base first (`git fetch origin
main`) and pass `--base origin/main`. If you name a ref with `--base` or
`--head` and it does not resolve to a commit, the run fails; it is not
skipped. The append-only checker always compares against the checked-out
HEAD, so `pr-diff` rejects a `--head` that points anywhere else.

To get the pinned `klt` without changing tools installed for the whole host,
install it into a throwaway virtual environment and put that on PATH. For
example:

```sh
python3 -m venv /tmp/klt-venv
/tmp/klt-venv/bin/pip install "klayout-tools==$(cat .github/klt-version)"
PATH="/tmp/klt-venv/bin:$PATH" npm test
```

If `python3 -m venv` is not available, `uv venv` followed by
`uv pip install --python /tmp/klt-venv/bin/python ...` works the same way.
The `shellcheck-py` package provides a `shellcheck` binary for the same
environment if your system does not have shellcheck.

## klayout-tools friction ledger

The friction protocol in [`CLAUDE.md`](CLAUDE.md) makes tool gaps a deliverable,
so [`.github/klt-friction-ledger.json`](.github/klt-friction-ledger.json) lists
every `2AMLogic/klayout-tools` issue this repository cites. Each entry has the
issue number, a one-line generic description of the gap, its status as last
checked (`open`, `closed` or `merged`) and the date, the klt version it was
verified against (`klt_version_verified`), and the in-tree paths of the
workarounds it justifies (`workarounds`, which may be empty). The ledger is
hand-maintained and never queries the upstream tracker. The initial statuses
were read once, by hand, on 2026-10-09 against klt 0.6.0.

The `friction` gate (`check-all.sh friction`, part of `npm test` and CI) is
offline and stdlib-only. It fails when:

- a tracked file cites an issue (`klayout-tools#N`, `klayout-tools #N` or
  `klayout-tools/issues/N`) that has no ledger entry. Files under
  `sim/**/records/` are read for citations but never edited, because that
  evidence is append-only; a ledger entry covers their citations instead;
- a ledger entry lists a workaround path that does not exist;
- an entry's `klt_version_verified` differs from
  [`.github/klt-version`](.github/klt-version) and its optional `reverified`
  field does not name the current pin.

Adding a citation: add the ledger entry in the same change. Keep design detail
out of the gap text and out of the upstream issue.

Re-verify procedure on a pin bump: after changing `.github/klt-version`, run
`check-all.sh friction`. Every entry now fails as stale, and the list is the
re-check queue. For each one, read the upstream issue state, run or read the
workaround to see whether it is still needed, remove or keep the workaround,
update `status` and `status_checked_on`, and set `klt_version_verified` to the
new pin. Set `"reverified": "<pin>"` instead only when you checked the entry
at the new pin but deliberately keep the older stamp. Claims in prose that
depended on a changed behavior are corrected in the same PR (never in
`sim/**/records/`).

## License

Apache-2.0.
