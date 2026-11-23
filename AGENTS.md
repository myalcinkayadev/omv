# AGENTS.md

Guidance for a coding agent (Claude Code, Codex, OpenCode, pi, or any other) working with omv,
a macOS desktop of AeroSpace, SketchyBar, Hammerspoon and Ghostty. Two jobs: changing a
user's own setup, and working on omv itself.

## Changing a user's setup

The user asks for something like "smaller gaps", "bind Option+Q to close the window" or "a
bigger font in the terminal". Make it in their personal settings, then apply it.

**Rule: never edit files in the omv folder** (the clone, usually `~/workspace/omv`) for a
user's own change. `omv update` refuses to run on a clone with changes, so an edit there
blocks every future update. Personal settings live in `~/.config/omv/`, which omv never
overwrites. Create a file there only when the change needs it.

| File | For | Format |
|---|---|---|
| `~/.config/omv/aerospace.toml` | AeroSpace: keys, gaps, window rules, workspaces | TOML; merged into omv's `aerospace.toml` |
| `~/.config/omv/ghostty` | Ghostty | Ghostty's `key = value` lines |
| `~/.config/omv/sketchybar.sh` | SketchyBar | bash, sourced at the end of omv's `sketchybarrc` |
| `~/.config/omv/hammerspoon.lua` | Hammerspoon: extra keys and behavior | Lua, run after omv's `init.lua` |
| `~/.config/omv/nvim.lua` | Neovim | Lua, run after omv's `init.lua` |
| `~/.config/omv/flags` | Feature flags | `name=on` or `name=off`; prefer `omv flags <name> on` |
| `~/.config/omv/apps` | The browser and editor omv's keys open | `browser = Google Chrome`, `editor = Cursor` |
| `~/.config/omv/snippets` | Text the palette pastes by name | `name = text` lines, `\n` for a line break |
| `~/.config/omv/workspaces` | Workspaces 1 to 9: their screens, apps, layout; each screen's gaps | `[workspace 1]` `on = DELL` `apps = Zed`; `[screen laptop]` `gaps = 4` |
| `~/.config/omv/away-digest` | How long a break opens the agents' inbox | `minutes = 10`; `0` for every break |
| `~/.config/omv/theme-clock` | A day and a night theme, switched at sunrise and sunset | `day = catppuccin-latte`, `night = vantablack` |

Then apply it:

```sh
omv reload    # rebuilds aerospace.toml, reloads AeroSpace, SketchyBar and Hammerspoon
omv doctor    # checks the whole setup; names the line if aerospace.toml can't be read
```

Ghostty applies its file on its reload key, Cmd+Shift+Comma; Neovim on its next start.

**AeroSpace.** omv builds `~/.config/aerospace/aerospace.toml` from its defaults and the
user's file; never edit the built file. In the user's file, write a key in the same table and
with the same name as omv's, and it replaces omv's:

```toml
[gaps]
inner.horizontal = 4

[mode.main.binding]
alt-q = 'close'

[[on-window-detected]]
if.app-id = 'com.apple.finder'
run = 'layout floating'
```

Keys omv doesn't have are added; `[[on-window-detected]]` rules come after omv's. Writing one
of omv's keys another way, such as `[gaps.inner]` or `inner = { horizontal = 4 }`, is
refused with the line and the form to use. Before binding a key, check it isn't taken: omv's
keys are in `config/aerospace/.config/aerospace/aerospace.toml` and
`config/hammerspoon/init.lua`, and `Option+/` lists them all.

**Workspaces.** Where workspaces, apps and gaps go is all in `~/.config/omv/workspaces`, an INI
file with two kinds of section. Edit only the lines the change needs; comments stay.

```ini
dev = 7
bar = {number} {name}      # the bar's text for a named workspace; {number} and {name}
[workspace 1]
name   = Code              # up to 16 characters, emoji too; without it the bar shows "1"
on     = DELL, laptop      # screens to try in order; main is always last, never written
apps   = Zed, Helium       # each app on one workspace only
layout = tabs              # tiles or tabs
open   = Zed               # opened when the workspace is switched to and empty

[screen laptop]            # main, laptop, screen N, or part of a display's name
gaps = 4                   # or gaps.inner / gaps.outer
layout = tabs
```

Without a `[workspace]` section, omv's seven apply with omv's apps (by bundle id, in
`config/hammerspoon/workspaces.lua`), and a first `[workspace]` section replaces them all, apps
included, so write each workspace and app the user keeps. `apps` takes names or bundle ids.
Screen words: `main` has the menu bar, `screen 2` and on are the others from the left, `laptop`
is the built-in one. `omv displays` prints display names for `on` and `[screen NAME]`. Saving
the file applies it: Hammerspoon rebuilds `aerospace.toml` and moves the windows of apps whose
workspace changed; no reload is needed. `[screen]` gaps win over the user's `aerospace.toml`.
`omv doctor` names a line it can't read. README.md's "Your own workspaces" lists every value.

**Other commands.** `omv theme` lists themes and `omv theme <name>` switches; `omv flags`
lists feature flags; `omv update` pulls omv's own changes; `omv doctor --fix` clears a stuck
bar or Hammerspoon.

## Working on omv itself

- Layout: `bin/omv` (the command), `config/` (one folder per app; Hammerspoon loads
  `config/hammerspoon` in place), `agents/` (hooks and plugins for coding agents),
  `install/` (install, uninstall, doctor), `migrations/`, `tests/`.
- Tests: `bash tests/run.sh` runs everything with stubs and a temporary `HOME`; it never
  touches the real system. Lua modules are tested with `luajit`, contracts between configs in
  `tests/config_contract_test.py`.
- A change that a pull alone can't make on an existing install (moving or renaming a linked
  file) needs a migration; `migrations/README.md` has the rules.
- The clone is the live config of the Mac it runs on: moving files there takes effect at once.
  Do larger changes in a git worktree.
