# Personal settings (restructure stage 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every personal setting lives in `~/.config/omv/`; omv's configs load the user's file last; omv builds `aerospace.toml` from its defaults plus the user's.

**Architecture:** Ghostty, SketchyBar, Hammerspoon and Neovim gain a last line that loads an optional user file. A pure Lua module merges aerospace.toml line by line; a bash step runs it with luajit to write `~/.config/aerospace/aerospace.toml`, called from install, update's relink and a new `omv reload`. A second migration removes omv's old `~/.config/aerospace` link.

**Tech Stack:** bash, Lua (luajit), Stow, `tests/lib.sh` sandboxes, `tests/check.lua`, Python contract tests.

**Spec:** `docs/superpowers/specs/2026-11-16-personal-settings-design.md`

## Global Constraints

- Build in a git worktree, not `~/workspace/omv` (live config).
- User files: `~/.config/omv/ghostty`, `sketchybar.sh`, `hammerspoon.lua`, `nvim.lua`, `aerospace.toml`. Missing means defaults; omv never creates or writes them.
- Built file: `~/.config/aerospace/aerospace.toml`, first line exactly `# Built by omv from its defaults and ~/.config/omv/aerospace.toml. Edit that file, then run omv reload.`
- Foreign file backup: `~/.config/aerospace/aerospace.toml.before-omv`; never deleted.
- Migration: `migrations/202611161400-built-aerospace.sh`.
- Test names "should <behavior> when <condition>"; conventional commits ≤ 50 chars, no trailers.

## Review Focus

1. A user value spanning lines (`after-startup-command = [` … `]`) replacing omv's multi-line one: no leftover lines of omv's value.
2. A `#` inside a quoted string (`'exec-and-forget echo #1'`): not taken as a comment.
3. The same table header appearing twice in the user's file: both parts merge into omv's table.
4. Rebuild with no user file after one existed: the built file goes back to omv's defaults.
5. `omv reload` when AeroSpace isn't running: rebuilds, skips the reload, exits 0.

Each has its test in Task 2 or Task 3.

---

### Task 1: omv's configs load the user's file last

**Files:** Modify `config/ghostty/.config/ghostty/config`, `config/sketchybar/.config/sketchybar/sketchybarrc`, `config/hammerspoon/init.lua`, `config/nvim/.config/nvim/init.lua`. Test: `tests/config_contract_test.py`.

- [ ] **Step 1: Failing contract tests:**
  - should load the user's Ghostty file last → last `config-file` line is `config-file = ?~/.config/omv/ghostty` and comes after the theme's `config-file` line
  - should source the user's SketchyBar file before the redraw → sketchybarrc has `"$HOME/.config/omv/sketchybar.sh"` sourced, guarded by `-f`, before `sketchybar --update`
  - should load the user's Hammerspoon file last in pcall → init.lua's last non-blank statement block loads `/.config/omv/hammerspoon.lua` through `pcall(dofile, …)` and alerts on failure
  - should load the user's Neovim file in pcall → nvim init.lua has `pcall(dofile, …/.config/omv/nvim.lua)` guarded by a readable check
- [ ] **Step 2: Run** `python3 -I tests/config_contract_test.py` — expect the four FAIL.
- [ ] **Step 3: Implement** the four lines (Hammerspoon: `hs.alert` with the error and `print` to the console).
- [ ] **Step 4: Run** `bash tests/run.sh` — exit 0.
- [ ] **Step 5: Commit** `feat: load personal settings from ~/.config/omv`

### Task 2: The aerospace.toml merge

**Files:** Create `install/aerospace_merge.lua`, `tests/aerospace_merge_test.lua`, `tests/aerospace_merge_test.sh`.

**Interfaces:**
- `merge.build(defaults: string, user: string|nil) -> string|nil, string|nil`: the built text (header line first, then omv's text with the user's keys applied), or `nil, "line N: <reason>"` for a user line it can't read.
- Runner: `luajit install/aerospace_merge.lua <defaults> <user-or-missing>` prints the built text; on error prints `~/.config/omv/aerospace.toml line N: <reason>` to stderr and exits 1.
- Reading: a statement is `key = value`, the value continuing over lines while `[`/`{` outnumber `]`/`}` outside quotes; `[name]` opens a table, `[[name]]` an array entry; `#` outside quotes starts a comment.

- [ ] **Step 1: Failing tests** (`aerospace_merge_test.lua`, through `check.lua`; defaults and user texts inline):
  - should start the built file with the header → first line equals the header
  - should keep omv's file when there's no user file → `build(d, nil)` = header .. "\n" .. d
  - should replace a key inside a table → user `[gaps]\ninner.horizontal = 4` → built has `inner.horizontal = 4`, not `= 10`
  - should replace a multi-line value whole → user `after-startup-command = ['x']` → built has it, and none of omv's array lines
  - should add a key omv doesn't have to its table → `[mode.main.binding]\nalt-z = 'close'` lands under that table
  - should add a table omv doesn't have → `[key-mapping]\npreset = 'qwerty'` present
  - should append the user's window rules after omv's → user `[[on-window-detected]]` block after omv's last one
  - should keep omv's comments → a `# Workspace 2` line from omv survives
  - should ignore brackets and hashes inside quotes → user `x = ['a ] # b']` read as one statement
  - should merge a table the user names twice → two `[gaps]` blocks both applied
  - should name the line it can't read → user `[gaps\n` → `nil`, `"line 1: …"`
- [ ] **Step 2: Run** `bash tests/aerospace_merge_test.sh` — FAIL (module missing).
- [ ] **Step 3: Implement** `install/aerospace_merge.lua`.
- [ ] **Step 4: Run** `bash tests/aerospace_merge_test.sh`, then `bash tests/run.sh` — exit 0.
- [ ] **Step 5: Commit** `feat: merge aerospace.toml with the user's`

### Task 3: Build it, `omv reload`, and the migration

**Files:** Create `install/aerospace.sh` (sourced), `migrations/202611161400-built-aerospace.sh`, `tests/built_aerospace_migration_test.sh`. Modify `install/packages.sh` (drop `aerospace`), `install/install.sh`, `bin/omv` (relink, `reload` command, usage), `tests/omv_test.sh`, `tests/install_test.sh`, and tests listing aerospace as a Stow package.

**Interfaces:**
- `install/aerospace.sh`: `AEROSPACE_BUILT=$HOME/.config/aerospace/aerospace.toml`, `AEROSPACE_USER=$HOME/.config/omv/aerospace.toml`, `AEROSPACE_DEFAULTS=$REPO_DIR/config/aerospace/.config/aerospace/aerospace.toml`; `build_aerospace()`: moves a real built-path file without the header to `.before-omv` (prints `moved your aerospace.toml to aerospace.toml.before-omv`), runs the merge with `luajit` into a temp file, and only on success moves it into place; returns non-zero on a merge error, leaving the old file.
- `omv reload`: `build_aerospace`, then `aerospace reload-config` when `pgrep -x AeroSpace` prints a pid, then the existing `reload` (Hammerspoon, SketchyBar).
- relink calls `build_aerospace` after Stow; install calls it after `link_configs` (dry run: `would run: build ~/.config/aerospace/aerospace.toml`).

- [ ] **Step 1: Failing tests:**
  - omv_test (real luajit on PATH for these; a fake defaults file in the fake repo): should build aerospace.toml when updating → built file starts with the header; should build it on reload; should keep the old built file when the user's has an error → content unchanged and exit non-zero; should go back to omv's defaults when the user file is removed (Review Focus 4); should rebuild without reloading AeroSpace when it isn't running → exit 0, no `aerospace reload-config` call (Review Focus 5); should reload AeroSpace when it's running → `aerospace reload-config` called.
  - install_test: should move a foreign aerospace.toml aside → `.before-omv` holds `mine`; should leave an omv-built one in place → no `.before-omv`; should only print the build on a dry run.
  - migration test: should remove omv's ~/.config/aerospace link; should keep a real folder; should keep a link elsewhere; should succeed when run twice.
- [ ] **Step 2: Run** those files — the new ones FAIL.
- [ ] **Step 3: Implement**; `aerospace` leaves `CONFIG_PACKAGES`, and uninstall removes the built file only when it carries the header (default run, as aerospace was).
- [ ] **Step 4: Run** `bash tests/run.sh` — exit 0.
- [ ] **Step 5: Commit** `feat: build aerospace.toml with omv reload`

### Task 4: Doctor and README

**Files:** Modify `install/doctor.sh`, `README.md`. Test: `tests/doctor_test.sh`.

- [ ] **Step 1: Failing tests:** should accept a built aerospace.toml that's up to date → `✓ aerospace.toml is built from omv and your settings`; should report an out-of-date one → `✗ aerospace.toml is out of date — fix: omv reload`; should report one omv didn't build → `✗ aerospace.toml isn't omv's — fix: omv reload`; should report a user file it can't read → `✗ ~/.config/omv/aerospace.toml line 1:` …
- [ ] **Step 2: Run** `bash tests/doctor_test.sh` — FAIL.
- [ ] **Step 3: Implement** (doctor builds into a temp file and compares); README: a "Your settings" section with the five files, one short example each, and `omv reload`; the package table drops aerospace's link row for "built".
- [ ] **Step 4: Run** `bash tests/run.sh` — exit 0.
- [ ] **Step 5: Commit** `docs: describe personal settings`

### Task 5: This Mac (on the user's word)

- [ ] Merge into `main`, then `bin/omv update --finish moved`; check `~/.config/aerospace/aerospace.toml` has the header, AeroSpace keys work, `omv doctor` is clean. Push on the user's word.
