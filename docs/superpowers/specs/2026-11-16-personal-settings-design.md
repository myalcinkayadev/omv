# Stage 2 of the restructure: personal settings

## Why

omv's configs are links into the clone, so a user who edits one changes the clone, and
`omv update` refuses to run on a clone with changes. For omv to work for other people, their
tweaks must live outside the clone, in files omv never overwrites, while updates keep
shipping omv's own changes. Omarchy does the same: its defaults load first, the user's file
last.

## Goals

- Every personal setting lives in `~/.config/omv/`, next to the existing `flags` file.
- Each omv config loads the user's file last, so the user's lines win.
- `omv update` keeps changing omv's defaults and never touches the user's files.
- A missing user file means omv's defaults; nothing is created for the user.

## Non-goals

- btop: `btop.conf` is already btop's own file, not omv's; omv only ships a theme.
- SwipeAeroSpace: two settings, no user demand; stays omv's.
- A settings UI, or moving a user's tweaks out of the clone automatically.

## Anti-goals

- An install or update that overwrites a config the user wrote.
- A mistake in a user file that takes all of omv down with it.

## Per app

| App | omv's file | Loads last |
|---|---|---|
| Ghostty | `config/ghostty/.../config` | `config-file = ?~/.config/omv/ghostty` (after the theme line, so the user wins) |
| SketchyBar | `sketchybarrc` | `~/.config/omv/sketchybar.sh`, sourced before the final redraw, when it exists |
| Hammerspoon | `config/hammerspoon/init.lua` | `~/.config/omv/hammerspoon.lua`, when it exists, in `pcall`: an error shows an alert and the console line, and omv's keys keep working |
| Neovim | `init.lua` | `~/.config/omv/nvim.lua`, when it exists, in `pcall` |
| AeroSpace | see below | `~/.config/omv/aerospace.toml` |

## AeroSpace: omv builds the file (option A, picked)

AeroSpace reads one `aerospace.toml` and has no include, so omv builds it:

- `~/.config/aerospace/aerospace.toml` becomes a real file omv writes: omv's defaults from the
  repo merged with `~/.config/omv/aerospace.toml`. Its first line says it's built and to edit
  `~/.config/omv/aerospace.toml` instead.
- Merge rules:
  - A key the user sets (top level, or inside a `[table]` such as `[mode.main.binding]` or
    `[gaps]`) replaces omv's same key, whole value, multi-line arrays included.
  - A key omv doesn't have is added to its table; a table omv doesn't have is added.
  - `[[on-window-detected]]` entries (any `[[array]]`) are appended after omv's.
  - Comments in the user's file are dropped; the built file keeps omv's.
- The merge is a line-based reader for the TOML aerospace.toml uses (`key = value`, values
  spanning lines while brackets are open, brackets inside quotes ignored, `[table]`,
  `[[array]]`, comments), not a full TOML parser. A line it can't read stops the build: the
  old built file stays, and omv names the user file's line.
- Written in Lua (`install/aerospace_merge.lua`, a module plus a small runner), run with
  `luajit` (already in the Brewfile), tested with luajit like the Hammerspoon modules.
- Built by `omv install`, by `omv update` (in relink), and by a new `omv reload`, which
  rebuilds and then reloads AeroSpace (`aerospace reload-config`), SketchyBar and
  Hammerspoon: the command to run after editing any file in `~/.config/omv/`.
- aerospace stops being a Stow package. Migration 2 removes the `~/.config/aerospace` folder
  link when it's omv's, so the built file can go there.
- A real `aerospace.toml` that omv didn't build (no header) is moved to
  `aerospace.toml.before-omv` before the first build, and install says so. Never deleted.

## Doctor

- AeroSpace's file: `✓ aerospace.toml is built from omv and your settings`, or
  `✗ aerospace.toml is out of date` / `isn't omv's` — fix: `omv reload`.
- A user file with a merge error: `✗ ~/.config/omv/aerospace.toml line N: <reason>`.

## Tests

- Merge (luajit): replaces a key in a table; replaces a top-level multi-line array; adds a
  new key; adds a new table; appends `[[on-window-detected]]`; keeps omv's comments; ignores
  a `]` inside quotes; reports an unreadable line with its number; an empty or missing user
  file gives omv's file plus the header.
- `omv reload` and update build the file and reload AeroSpace; a merge error keeps the old
  file and exits non-zero.
- Install moves a foreign `aerospace.toml` aside; leaves an omv-built one.
- Migration 2: removes omv's `~/.config/aerospace` link; keeps a real folder; safe twice.
- Contract: Ghostty's last `config-file` line is the user's; sketchybarrc sources the user
  file before the redraw; init.lua loads the user file in `pcall` last; nvim the same.
- Doctor: out-of-date and foreign file reported; up-to-date file passes.

## Approaches

- **AeroSpace built by omv (picked):** updates keep shipping keys; user's tweaks survive; cost
  is a tested merge step and editing a file other than the one AeroSpace reads.
- Copy once, then the user's: simple; omv's new keys never reach the user.
- omv's file, add-only tweaks: simple; no rebinding a key.
- For the other apps, user file includes omv's (Omarchy's direction) vs omv's file loads the
  user's (picked): the second keeps omv's files linked and updatable, and puts every personal
  file in one folder.

## Left to the builder

The Lua module's internal shape; how `omv reload` waits; the exact header text.
