# Stage 1 of the restructure: the new layout

## Why

omv is becoming a standalone, agent-first macOS setup for other people, not one person's
dotfiles. Today the repo root mixes eight Stow packages, six loose scripts and the docs, so
a newcomer can't see what omv is made of. And `~/.hammerspoon` is linked file by file: a pull
that adds a Hammerspoon file breaks every key until someone restows (it happened four times).

The restructure comes in two stages, each shipped to this Mac through `omv update` and a
migration. This is stage 1: **move into the new layout, with no change in behavior.**
Stage 2 (personal settings in files omv never overwrites, Omarchy's way) gets its own design.

## Goals

- A root a newcomer can read: what omv runs (`bin/`), what it configures (`config/`), how it
  talks to agents (`agents/`), how it's installed (`install/`, `migrations/`).
- Hammerspoon loads its config straight from the repo, so a new Hammerspoon file never needs
  a link again.
- This Mac moves over through `omv update` with no hand steps, and keeps working throughout.
- A fresh install lands in the new layout directly.

## Non-goals

- Personal settings, and anything that changes what a config does (stage 2).
- Core vs extras behind flags (later).
- A `themes/` folder: the only built-in theme files are Vantablack's Ghostty and btop files,
  which belong with their app's config. Omarchy's themes stay in `~/.local/share/omv/themes`.
- Moving the clone (it stays wherever it was cloned), a Homebrew tap, Linux.

## Anti-goals

- A key, bar item or agent hook that stops working after the update.
- A migration that removes anything that isn't an omv link.

## The layout

```
bin/omv
config/                 Stow packages, same inner shape as today
  aerospace/  sketchybar/  ghostty/  nvim/  btop/  swipeaerospace/
  hammerspoon/          init.lua and the rest, flat: no .hammerspoon wrapper, not stowed
agents/
  claude/  opencode/  pi/                 Stow packages, as today
  claude-hooks.sh  claude-usage.sh  codex-hooks.sh
install/
  install.sh  uninstall.sh  doctor.sh  packages.sh
migrations/
docs/  tests/
Brewfile  Brewfile.apps  README.md
```

- `lib/` goes; `packages.sh` moves to `install/`.
- The root `install.sh` goes. A first install is `bin/omv install`; README says so.
- `Brewfile` stays at the root, where `brew bundle` looks by convention.

## Hammerspoon from the repo

- Install sets `defaults write org.hammerspoon.Hammerspoon MJConfigFile <repo>/config/hammerspoon/init.lua`.
  Hammerspoon reads it at launch, so when the value changes, Hammerspoon is restarted (quit,
  then `open -a Hammerspoon`); when it's already right, nothing restarts.
- `hs.configdir` becomes `<repo>/config/hammerspoon` (Hammerspoon passes the config file's
  folder as `configdir` in `setup.lua`), so every `hs.configdir .. "/x.sh"` keeps working.
- `~/.hammerspoon` keeps Hammerspoon's own `Spoons` folder; omv no longer links into it.
- Uninstall deletes the `MJConfigFile` key, so Hammerspoon goes back to `~/.hammerspoon`.
- Doctor checks the key points at this clone's `config/hammerspoon/init.lua`; fix: `omv install`.

## Linking

- `install/packages.sh` lists the Stow packages with the folder each lives in: `config` for
  aerospace, sketchybar, swipeaerospace, ghostty, nvim, btop; `agents` for claude. hammerspoon
  is no longer a Stow package. opencode and pi stay optional, from `agents`, as today.
- install, update's relink, doctor's link check and uninstall all use that one list.
  Uninstall keeps its split between the packages it always removes and the ones only `--all`
  removes, now as names from that list rather than its own copy.
- Agent hooks are unaffected: Claude's, Codex's and the usage line all call
  `$HOME/.claude/...`, which is still a Stow link; nothing outside the repo stores a repo path
  except the `omv` command link, whose path (`bin/omv`) doesn't change.

## The migration

`migrations/202611161200-new-layout.sh`:

- Removes each symlink in `$HOME` whose target is inside one of the clone's **old** package
  folders (`<repo>/aerospace/`, `sketchybar/`, `claude/`, `swipeaerospace/`, `ghostty/`,
  `nvim/`, `btop/`, `hammerspoon/`, `opencode/`, `pi/`). After the pull those targets no
  longer exist, so the match is on the link's text, resolved against the link's folder, not on
  the file it points to. Links are relative today (`../workspace/omv/aerospace/...`).
- Looks only where omv links: `~/.hammerspoon`, `~/.config` (the omv app folders inside it),
  `~/.claude`, `~/.config/opencode/plugins`, `~/.pi/agent/extensions`.
- Leaves every real file and every other link alone.
- Safe on a fresh setup (finds nothing, exits 0) and safe to run twice.

## Order changes in `bin/omv`

Stow refuses to link over a link it doesn't own, and the old links point at the old folders.
So migrations must run **before** linking:

- `omv update --finish`: migrations, then relink (which also sets `MJConfigFile`), then
  `brew bundle --no-upgrade`, then reload, then doctor. (Today: brew, relink, migrations.)
- `omv install`: migrations, then `install/install.sh`. A fresh Mac has nothing to migrate.
- Undo refuses after this update, as for any update that ran a migration. That's the cost:
  the way back from stage 1 is a fix forward, not `omv update --undo`.

## Doctor hints

While their paths change anyway, every fix hint names the `omv` command where one exists:
`omv install` (was `./install.sh`), `omv doctor --fix` (was `./doctor.sh --fix`),
`agents/claude-hooks.sh add` and the like for the agent scripts.

## Tests

- Every test that names a moved path follows it (about 35 files); behavior tests stay as they are.
- New: the migration removes old omv links in each place it looks; keeps a link pointing
  elsewhere; keeps a real file; does nothing on a fresh home; runs twice cleanly.
- New: update runs migrations before Stow; install runs migrations before `install.sh`.
- New: linking sets `MJConfigFile` to the repo's `config/hammerspoon/init.lua`; restarts
  Hammerspoon only when the value changed; uninstall deletes the key; doctor reports a wrong
  or missing value.

## Check on this Mac

`omv update` from clean `main` after the merge: no dangling links left (`find ~ -maxdepth 4
-type l ! -exec test -e {} \; -print` limited to the omv folders), Hammerspoon restarted once
and answering, every key and bar item working, doctor clean.

## Approaches

- **Two stages (picked).** Layout now, personal settings next; each small enough to review
  and each proves a real migration on this Mac.
- One big change: layout and personal settings together. Too large to review, and one failed
  migration breaks the whole setup.
- Personal settings only, no folder move: cheapest, but no readable product layout.

## Left to the builder

How the migration resolves a relative link's text; the restart's wait and fallback (the doctor
already has a pattern: quit, wait, force-quit, open); file moves with `git mv`.
