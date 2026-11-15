# sg13g2-vco — agent instructions

- **Some files are hash-pinned by signoff.** T1 items 1, 9 and 10 pin file
  content by sha256; the authoritative member list is
  `signoff/evidence/inventory-*.json` (includes `README.md`, the CI
  workflows and every `sim/*/testbench/*`). Editing any member — **even a
  pure prose fix** — turns CI red until you run the guarded regen wrapper
  (it regenerates the inventories and renders the verdict of record at the
  `.github/klt-version` pin, writing only on a clean, gated render):

  ```bash
  .github/scripts/regen-signoff.sh
  ```

  Editing `spec/target-spec.md` additionally requires
  `python3 -I signoff/characterization.py --regen` (item 8 pins it as a
  characterization input digest).

<!-- BEGIN LOOM ORCHESTRATION (AGENTS) -->
This repository uses [Loom](https://github.com/rjwalters/loom) for AI-powered development orchestration (dual-runtime: Claude Code reads `CLAUDE.md`; OpenAI Codex CLI and other AGENTS.md-aware runtimes read this file). See the Loom repository for the full guide (roles, labels, worktrees, configuration). When installed, Loom also writes a locally-substituted copy of the runtime-neutral guide to `.loom/AGENTS.md`.
<!-- END LOOM ORCHESTRATION (AGENTS) -->
