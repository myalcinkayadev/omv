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
| Ctrl+Option+H / L | Make the window narrower / wider |
| Ctrl+Option+K / J | Make the window shorter / taller |
| Option+F | Toggle fullscreen |
| Option+T | Toggle floating or tiled |
| Option+R | Toggle the split between horizontal and vertical |
| Option+B | Make window sizes even |

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
| Option+Shift+Enter | New Helium window | Workspace 2 |
| Option+Shift+N | Open Zed | Workspace 3 |
| Option+Shift+F | Finder at your home folder | Current workspace, floating |
| Option+Shift+Space | Show or hide the bar | |

### Who handles each key

AeroSpace handles the window and workspace keys and Option+Enter, in `aerospace.toml`. Hammerspoon handles the other app keys, in `init.lua`. A key should be bound in only one of them, and `tests/run.sh` fails if one is bound in both.

### Clashes

These tools take the keys system-wide, so apps never receive them:

- **Turkish-QWERTY-PC:** Option+1-5 and Option+T may be unable to type their characters, likely including `#` and `$`.
- **Shell:** Option+B and Option+F no longer jump by word.
- **Neovim and other terminal apps:** any Alt mapping on these keys stops working.

## Workspaces

| Workspace | Apps | Monitor |
|---|---|---|
| 1 | Ghostty | Main |
| 2 | Helium | Main |
| 3 | Zed | Main |
| 4 | Obsidian, Notion, Linear | Secondary, or main if there is only one |
| 5 | Notes, Messages, WhatsApp, Discord | Secondary, or main if there is only one |

Finder, System Settings and Calculator float on the current workspace.

There are five workspaces in total, not five per monitor, because AeroSpace workspaces are global. In the bar, the focused workspace is white and the one visible on the other monitor is gray.

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
