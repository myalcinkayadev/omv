# omv

Keyboard-driven macOS desktop: AeroSpace for tiling, SketchyBar for the top bar, and the Vantablack configs for Ghostty, Neovim and btop. Based on [Koen van Gilst's setup](https://koenvangilst.nl/lab/aerospace-sketchybar-macos-setup), with the corrections listed below. Every package is linked into `$HOME` with GNU Stow.

## Install

Requires Homebrew and `stow`.

```sh
./install.sh
```

This trusts the third-party taps `nikitabobko/tap` and `felixkratz/formulae`, installs both tools, links all six packages, and turns on the two macOS settings below. It is safe to run again.

Then do these by hand:

1. Open AeroSpace from Finder and grant Accessibility in System Settings.
2. Log out and back in, so "Displays have separate Spaces" turns off.
3. If the menu bar still shows, set System Settings > Menu Bar > "Automatically hide and show the menu bar" to Always.
4. In System Settings > Displays > Arrange, leave each display a free bottom corner, because AeroSpace hides windows there.

## Keys

Every shortcut starts with Option. Option alone goes somewhere or acts on the current window, and adding Shift takes the window with it or launches an app. H/J/K/L mean left, down, up and right, as in Vim.

### Windows

| Keys | Action |
|---|---|
| Option+H/J/K/L | Focus the window in that direction |
| Option+Shift+H/J/K/L | Move the window in that direction |
| Option+Shift+R | Enter resize mode, shown as `RESIZE` in the bar |
| Option+F | Toggle fullscreen |
| Option+T | Toggle floating or tiled |
| Option+R | Toggle the split between horizontal and vertical |
| Option+B | Make window sizes even |

In resize mode, H / L make the window narrower / wider, K / J make it shorter / taller, and Escape or Enter leaves. Other shortcuts stay off until you leave. Height only changes when windows are stacked vertically.

### Workspaces and monitors

| Keys | Action |
|---|---|
| Option+1-5 | Go to that workspace |
| Option+Shift+1-5 | Send the window to that workspace, and stay where you are |
| Option+, / Option+. | Focus the left / right monitor |
| Option+Shift+, / Option+Shift+. | Send the window to the left / right monitor |

A pinned workspace always opens on its own monitor, so Option+4 from the Dell moves focus to the laptop.

### Apps

| Keys | Action | Goes to |
|---|---|---|
| Option+Enter | New Ghostty window | Workspace 1 |
| Option+Shift+T | btop in a new Ghostty window | Workspace 1 |
| Option+Shift+N | Open Zed | Workspace 2 |
| Option+Shift+Enter | New Helium window | Workspace 3 |
| Option+Shift+F | Finder at your home folder | Current workspace, floating |
| Option+Shift+Space | Show or hide the bar | |
| Option+` | Drop-down terminal, over any workspace | Current workspace |
| Option+/ | Show or hide this list of keys, Escape also closes it | |

### Who handles each key

AeroSpace handles the window and workspace keys and Option+Enter, in `aerospace.toml`. Hammerspoon handles the other app keys and Option+/, in `init.lua`. Ghostty handles Option+\`, in its `config`. A key should be bound in only one of them, and `tests/run.sh` fails if one is bound in both.

### Clashes

These tools take the keys system-wide, so apps never receive them:

- **Turkish-QWERTY-PC:** these characters can't be typed, because the keys are taken: `>` `£` `#` `$` `½` (Option+1-5), `^` (Option+H), `₺` (Option+T) and `€` (Option+Shift+2).
- **Shell:** Option+B and Option+F no longer jump by word.
- **Neovim and other terminal apps:** any Alt mapping on these keys stops working.

## Workspaces

| Workspace | Apps | Monitor |
|---|---|---|
| 1 | Ghostty | Main |
| 2 | Zed | Main |
| 3 | Helium | Main |
| 4 | Obsidian, Notion, Linear | Secondary, or main if there is only one |
| 5 | Notes, Messages, WhatsApp, Discord | Secondary, or main if there is only one |

Finder, System Settings and Calculator float on the current workspace.

`btop` opens on workspace 1 when AeroSpace starts, unless one is already running.

Ghostty windows share one process. The first time you use Option+Enter or Option+Shift+T, macOS asks to let AeroSpace and Hammerspoon control Ghostty, and those keys need that permission.

There are five workspaces in total, not five per monitor, because AeroSpace workspaces are global. In the bar, the focused workspace is white and the one visible on the other monitor is gray.

## Claude usage limit

The bar shows Claude's limits to the left of the clock, with the Claude logo and `5h 23%  7d 41%`. Click it to swap to the reset times.

| Highest usage | Look |
|---|---|
| Under 70% | Gray |
| 70-89% | White |
| 90% and up | White pill |

The numbers come from Claude Code's status line, so they only update while Claude Code runs. Usage from elsewhere, such as claude.ai, shows after your next response here. A window past its reset time shows 0%.

`install.sh` adds one line to `~/.claude/statusline-wrapper.sh` through `claude-usage.sh`. If that file doesn't exist, the item stays hidden. Only the four numbers are stored, in `~/.local/state/omv/claude-usage`.

## Differences from the article

- Trusts the taps first, because Homebrew refuses to load untrusted ones.
- Starts SketchyBar from AeroSpace, which the article never does.
- Sets `PATH` and `LANG` for apps started at login.
- Raises the top gap on external displays, so windows don't slide under the bar.
- Pins workspaces to monitors and updates the bar when monitor focus changes.
- Turns off "Displays have separate Spaces", as AeroSpace's guide recommends.
- Makes launch keys switch workspace first, because new windows route away without following.
- Keeps the recovered Vantablack bar and plugins, because the article doesn't copy the example plugins.

## Uninstall

```sh
./uninstall.sh        # removes AeroSpace and SketchyBar, keeps the older tool links
./uninstall.sh --all  # also unlinks ghostty, nvim, btop and hammerspoon
```

It deletes both macOS settings, returning them to their defaults, then uninstalls both tools and untaps both taps. It leaves this repo, other Homebrew packages, fonts, `~/.config/omniwm` and `~/.config-backup` alone, and prints the steps left for you.

## Tests

```sh
tests/run.sh
```

The tests use stubs and a temporary `HOME`, so they never change the real system. They need `stow` and `python3`.
