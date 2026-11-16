# New repo layout (restructure stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move omv into `bin/ config/ agents/ install/ migrations/`, load Hammerspoon straight from the repo, and move existing installs over with one migration, with no change in behavior.

**Architecture:** `git mv` into the new folders with every path reference following; Stow now links from two folders (`config`, `agents`); Hammerspoon is pointed at `config/hammerspoon/init.lua` through its `MJConfigFile` default instead of being stowed; a migration removes links into the old folders, and `bin/omv` runs migrations before linking.

**Tech Stack:** bash, GNU Stow, `defaults`, Hammerspoon Lua, `tests/lib.sh` sandboxes, luajit and Python contract tests.

**Spec:** `docs/superpowers/specs/2026-11-16-repo-layout-design.md`

## Global Constraints

- **Build in a git worktree, never in `~/workspace/omv`:** that clone's files are this Mac's live config, and moving them breaks every link at once.
- Old packages (the migration's list): `aerospace sketchybar claude swipeaerospace ghostty nvim btop hammerspoon opencode pi`.
- `config/` packages: `aerospace sketchybar swipeaerospace ghostty nvim btop`. `agents/` packages: `claude`, plus optional `opencode`, `pi`.
- Hammerspoon key: `defaults write org.hammerspoon.Hammerspoon MJConfigFile <repo>/config/hammerspoon/init.lua`.
- Migration file: `migrations/202611161200-new-layout.sh`; safe on a fresh setup, safe twice, starts with `set -euo pipefail` (`migrations/README.md`).
- Update order: migrations, relink, `brew bundle --no-upgrade`, reload, doctor. Install order: migrations, then `install/install.sh`.
- Test names: "should <behavior> when <condition>". Conventional commits, subject ≤ 50 chars, no trailers.

## Review Focus

1. A **folder** link (`~/.config/aerospace -> ../workspace/omv/aerospace/.config/aerospace`, how Stow links a folder it owns whole): the migration removes it like a file link.
2. A clone whose path holds a space, or isn't named `omv`: the migration still matches its old links, and only those.
3. Hammerspoon not running when linking: the key is written and Hammerspoon is not opened.
4. A link into the **new** layout (`.../config/aerospace/...`), as after a first run: the migration keeps it.
5. `$HOME` reached through a symlinked folder: the link's folder is resolved physically before its text is joined, so the match still holds.

Each has its test in the task that owns the code (Tasks 2 and 3).

---

### Task 1: Move into the new layout

Hammerspoon stays a Stow package for now, at `config/hammerspoon/.hammerspoon/`, so this task changes paths only.

**Files:**
- Move (`git mv`): `aerospace sketchybar swipeaerospace ghostty nvim btop hammerspoon` → `config/`; `claude opencode pi claude-hooks.sh claude-usage.sh codex-hooks.sh` → `agents/`; `install.sh uninstall.sh doctor.sh` → `install/`; `lib/packages.sh` → `install/packages.sh` (remove `lib/`).
- Modify: `bin/omv`, `install/*.sh`, `agents/*.sh` (if they locate the repo), every test naming a moved path (`tests/check.lua`, `tests/config_contract_test.py`, `tests/omv_test.sh` `make_repo`, `tests/doctor_test.sh` `complete_setup`, and the ~35 files `grep` finds).

**Interfaces:**
- Produces, in `install/packages.sh` (sourced after `REPO_DIR` is set):
  - `CONFIG_PACKAGES=(aerospace sketchybar swipeaerospace ghostty nvim btop hammerspoon)` (Task 2 drops `hammerspoon`)
  - `AGENT_PACKAGES=(claude)`
  - `package_dir <name> -> "$REPO_DIR/agents"` for `claude opencode pi`, else `"$REPO_DIR/config"`
- `install/*.sh`: `REPO_DIR` is the parent of the script's folder.
- `bin/omv` runs `install/install.sh`, `install/uninstall.sh`, `install/doctor.sh`.

- [ ] **Step 1: Move** with `git mv`, then point every reference at the new paths. Stow calls become one per folder: `stow --dir="$REPO_DIR/config" … "${CONFIG_PACKAGES[@]}"` and `stow --dir="$REPO_DIR/agents" … "${AGENT_PACKAGES[@]}"`; opencode and pi from `agents`. Doctor's link check and uninstall's `SETUP_PACKAGES`/`OLDER_PACKAGES` use `package_dir` per name.
- [ ] **Step 2: Run** `grep -rnE --exclude-dir=.git --exclude-dir=docs '(REPO_DIR|REPO|repo)[^a-z]*/(aerospace|sketchybar|swipeaerospace|ghostty|nvim|btop|hammerspoon|claude|opencode|pi|lib)/|/(install|uninstall|doctor|claude-hooks|claude-usage|codex-hooks)\.sh' . | grep -vE '/(config|agents|install)/'` — expect nothing.
- [ ] **Step 3: Run** `bash tests/run.sh` — expect exit 0, same count as on main (1757).
- [ ] **Step 4: Commit** `refactor: move omv into the new layout`

### Task 2: Hammerspoon loads from the repo

**Files:**
- Move: `config/hammerspoon/.hammerspoon/*` → `config/hammerspoon/` (flat).
- Create: `install/hammerspoon.sh` (sourced).
- Modify: `install/packages.sh` (drop `hammerspoon`), `install/install.sh`, `bin/omv` (`relink`, `FLAG_DEFAULTS`), `install/uninstall.sh`, `install/doctor.sh`, `tests/check.lua`, `tests/config_contract_test.py`.
- Test: `tests/omv_test.sh`, `tests/install_test.sh`, `tests/uninstall_test.sh`, `tests/doctor_test.sh`.

**Interfaces:**
- Produces, in `install/hammerspoon.sh`:
  - `HAMMERSPOON_CONFIG="$REPO_DIR/config/hammerspoon/init.lua"`
  - `point_hammerspoon()`: does nothing when `defaults read org.hammerspoon.Hammerspoon MJConfigFile` already equals `HAMMERSPOON_CONFIG`; otherwise writes it, and if `pgrep -x Hammerspoon` finds it, restarts it: `pkill -x Hammerspoon`, wait up to 5s, `pkill -9 -x Hammerspoon` if still there, `open -a Hammerspoon`. Not running: not opened.
- `bin/omv relink` calls `point_hammerspoon` after Stow. `install.sh` calls it after `link_configs`; with `--dry-run` it prints `would run: defaults write org.hammerspoon.Hammerspoon MJConfigFile <path>` instead.

- [ ] **Step 1: Failing tests:**
  - omv_test: should point Hammerspoon at the repo's config when relinking → `assert_called "^defaults write org.hammerspoon.Hammerspoon MJConfigFile $REPO/config/hammerspoon/init.lua$"`
  - omv_test: should leave Hammerspoon running when it already loads the repo's config → defaults stub answers the path; `assert_not_called '^pkill'`
  - omv_test: should restart Hammerspoon when its config changed → defaults stub answers `~/.hammerspoon/init.lua`; `assert_called '^open -a Hammerspoon$'`
  - omv_test: should not open Hammerspoon when it isn't running → `pgrep -x Hammerspoon` exits 1; `assert_not_called '^open -a Hammerspoon'`
  - install_test: should point Hammerspoon at the repo's config → the `defaults write … MJConfigFile` call
  - install_test: should only print the Hammerspoon setting on a dry run → `would run: defaults write org.hammerspoon.Hammerspoon MJConfigFile` in output, no such call
  - uninstall_test: should forget the Hammerspoon setting with --all when it's omv's → `assert_called '^defaults delete org.hammerspoon.Hammerspoon MJConfigFile$'`
  - uninstall_test: should keep a Hammerspoon setting that isn't omv's → stub answers `/elsewhere/init.lua`; no delete
  - doctor_test: should report Hammerspoon not loading omv's config → stub answers nothing; `✗ Hammerspoon doesn't load omv's config — fix: omv install`
  - doctor_test: `complete_setup` makes the stub answer the repo's path; expect `✓ Hammerspoon loads omv's config`
- [ ] **Step 2: Run** `bash tests/omv_test.sh; bash tests/install_test.sh; bash tests/uninstall_test.sh; bash tests/doctor_test.sh` — expect the new ones FAIL.
- [ ] **Step 3: Implement** the flatten (`git mv`), `install/hammerspoon.sh`, the calls above, `FLAG_DEFAULTS=$REPO_DIR/config/hammerspoon/flags.lua`, `check.lua` and contract paths. The doctor check goes under Links.
- [ ] **Step 4: Run** `bash tests/run.sh` — expect exit 0.
- [ ] **Step 5: Commit** `feat: load Hammerspoon straight from the repo`

### Task 3: The migration, and running it before linking

**Files:**
- Create: `migrations/202611161200-new-layout.sh`, `tests/new_layout_migration_test.sh`
- Modify: `bin/omv` (`finish_update`, `install` order)
- Test: `tests/omv_test.sh`

**Interfaces:**
- The migration finds the repo from its own path (`cd "$(dirname "$0")/.." && pwd -P`), takes no arguments, prints `removed <path relative to $HOME>` per link.
- Where it looks: `find` without following links in `~/.hammerspoon` (maxdepth 2), `~/.config` (maxdepth 4), `~/.claude` (maxdepth 1), `~/.pi/agent/extensions` (maxdepth 1); missing folders skipped.
- A link is removed when the path its text names, resolved without needing it to exist, starts with `<repo>/<old package>/` or equals `<repo>/<old package>`. Resolving: the link's folder via `cd … && pwd -P`, joined with the text unless it's absolute, then `.` and `..` collapsed segment by segment.

- [ ] **Step 1: Failing tests** in `tests/new_layout_migration_test.sh` (sandbox `$HOME`, a fake repo folder `$SANDBOX/my omv` with `migrations/` holding a copy of the script):
  - should remove a file link into an old package → `~/.hammerspoon/init.lua -> ../my omv/hammerspoon/.hammerspoon/init.lua` gone
  - should remove a folder link into an old package → `~/.config/aerospace -> ../../my omv/aerospace/.config/aerospace` gone
  - should remove a link with an absolute target into an old package
  - should keep a link into the new layout → `~/.config/aerospace -> ../../my omv/config/aerospace/.config/aerospace` kept
  - should keep a link that points outside the clone → `~/.config/foo -> /opt/x` kept
  - should keep a real file → `~/.hammerspoon/Spoons/a.lua` kept
  - should keep a link into a different clone with a similar name → `../../my omv2/aerospace/…` kept
  - should do nothing when the home has no omv links → exit 0, nothing removed
  - should succeed when run twice → second run exit 0
  - should match links when the home is reached through a symlink → run with `HOME` set to a symlink to the sandbox home
- [ ] **Step 2: Failing tests** in `tests/omv_test.sh` (the call log holds `migration <name>` lines from `add_migration`):
  - should run migrations before relinking when updating → the `migration` line's number is below the first `stow` line's
  - should relink before installing missing packages when updating → the first `stow` line's number is below the `brew bundle --no-upgrade` line's
  - should run migrations before installing → `migration` line below `install.sh` line
- [ ] **Step 3: Run** `bash tests/new_layout_migration_test.sh; bash tests/omv_test.sh` — expect the new ones FAIL.
- [ ] **Step 4: Implement** the migration and the two orders.
- [ ] **Step 5: Run** `bash tests/run.sh` — expect exit 0.
- [ ] **Step 6: Commit** `feat: move existing installs to the new layout`

### Task 4: Hints and README

**Files:**
- Modify: `install/doctor.sh` (fix hints), `README.md` (install command, the package table, Update, Doctor), `migrations/README.md` (migrations run before linking)
- Test: `tests/doctor_test.sh` (expected strings)

- [ ] **Step 1: Change** the expected hints in `doctor_test.sh`: `./install.sh` → `omv install`; `./doctor.sh --fix` → `omv doctor --fix`; `./claude-usage.sh add` → `agents/claude-usage.sh add`; `./claude-hooks.sh add` → `agents/claude-hooks.sh add`; `./codex-hooks.sh add` → `agents/codex-hooks.sh add`.
- [ ] **Step 2: Run** `bash tests/doctor_test.sh` — expect those FAIL.
- [ ] **Step 3: Implement** the hints. README: install is `git clone … && cd omv && bin/omv install`; the table lists `config/<package>` and says Hammerspoon loads from `config/hammerspoon`; Update notes that an update which ran a migration can't be undone.
- [ ] **Step 4: Run** `bash tests/run.sh` — expect exit 0.
- [ ] **Step 5: Commit** `docs: describe the new layout`

### Task 5: Move this Mac over (after review, on the user's word)

- [ ] **Step 1:** In `~/workspace/omv` on clean `main`: `git merge --ff-only <branch>`, then at once `bin/omv update --finish moved` (the same path a pulled update takes).
- [ ] **Step 2: Check:** `find ~/.hammerspoon ~/.config ~/.claude -maxdepth 4 -type l ! -exec test -e {} \; -print` prints nothing; `defaults read org.hammerspoon.Hammerspoon MJConfigFile` is the repo path; `hs -t 3 -c 'return hs.configdir'` answers `…/config/hammerspoon`; `omv doctor` reports no problems; Option+Space, a bar click and a Claude hook still work.
- [ ] **Step 3:** Push only when the user says so.
