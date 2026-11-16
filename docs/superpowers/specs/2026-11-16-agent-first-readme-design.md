# Agent-first README and AGENTS.md

## Why
omv is aimed at more users as an agent-first macOS setup. The README opens as a feature tour,
with the agent features one bullet among 23, so a reader can't see what sets omv apart.

## What (approved: A with a B section)
- **A, the lead:** README opens with omv as the desktop for working alongside coding agents
  (Claude Code, Codex, OpenCode, pi): sessions in the bar, the waiting pill and Option+Shift+A,
  the Agents card, dev layout and agent grid. Then a 60-second install with `bin/omv install`.
- **B, a section:** "Let your agent set it up": an agent edits `~/.config/omv/` and runs
  `omv reload`, guided by a new root `AGENTS.md`.
- `AGENTS.md`: two parts. Changing a user's setup (the settings files, `omv reload`,
  `omv doctor`, `omv flags`, `omv theme`; never edit the clone, it blocks `omv update`).
  Working on omv itself (layout, `bash tests/run.sh`, migrations' rules).
- The feature tour and reference sections stay, below the new opening.

## Non-goals
A `CLAUDE.md` in the repo (it would steer every development session here); new screenshots.

## Approaches
Opening rewrite over the existing reference (picked) vs a full rewrite of all 705 lines (the
reference is accurate and tested by readers; rewriting it adds risk for no gain).

## Tests
Contract: README has an agents section before Features that links `AGENTS.md`; `AGENTS.md`
names every file in `~/.config/omv/`, `omv reload`, and says not to edit the clone.
