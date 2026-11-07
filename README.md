# omv

A keyboard-driven macOS desktop. AeroSpace tiles the windows, SketchyBar draws the top bar, Hammerspoon launches apps, and Ghostty, Neovim and btop share the Vantablack look. It is based on [Koen van Gilst's setup](https://koenvangilst.nl/lab/aerospace-sketchybar-macos-setup), with the [fixes listed at the end](#differences-from-the-article).

![Workspace 1 with btop and Vim, under the top bar](docs/workspace-1.png)

## What's inside

Each folder is a GNU Stow package, linked into `$HOME`.

| Package | Links | What it does |
|---|---|---|
| `aerospace` | `~/.config/aerospace` | Tiling, workspaces and window keys |
| `sketchybar` | `~/.config/sketchybar` | The top bar and its plugins |
| `hammerspoon` | `~/.hammerspoon` | App keys, the keep-awake key and the key cheat sheet |
| `ghostty` | `~/.config/ghostty` | Terminal config and window scripts |
| `nvim` | `~/.config/nvim` | Neovim config |
| `btop` | `~/.config/btop` | btop config |
| `claude` | `~/.claude/bar-usage.sh` | Feeds Claude's usage limits to the bar |

## Requirements

- Homebrew and `stow`, which `install.sh` checks for.
- `jq`, used by the calendar popup and the Claude usage item.
- The JetBrainsMono Nerd Font, in both the Mono and Propo variants.
- The apps the keys and workspaces expect: Ghostty, Hammerspoon, Zed, Helium, Neovim and btop.

`install.sh` installs only AeroSpace and SketchyBar. Everything else on this list must already be there.

## Install

```sh
./install.sh
```

It is safe to run again. It:

1. Trusts the third-party taps `nikitabobko/tap` and `felixkratz/formulae`, then installs AeroSpace and SketchyBar from them.
2. Links all seven packages with Stow.
3. Adds the Claude usage line to your status line wrapper, as described in [Claude usage](#claude-usage).
4. Hides the macOS menu bar, and turns off "Displays have separate Spaces".

Then do these by hand:

1. Open AeroSpace from Finder and grant Accessibility in System Settings.
2. Log out and back in, so "Displays have separate Spaces" turns off.
3. If the menu bar still shows, set System Settings > Menu Bar > "Automatically hide and show the menu bar" to Always.
4. In System Settings > Displays > Arrange, leave each display a free bottom corner, because AeroSpace hides windows there.

When you pull new files later, run `./install.sh` again. Stow links files one by one, so a new file has no link until then.

## Keys

Every shortcut starts with Option. Option alone goes somewhere or acts on the current window. Adding Shift takes the window with it or launches an app. H/J/K/L mean left, down, up and right, as in Vim.

Press Option+/ to see every key on screen. The sheet is built from `aerospace.toml` and `init.lua`, so it never goes stale. Escape also closes it.

### Windows

| Keys | Action |
|---|---|
| Option+H/J/K/L | Focus the window in that direction |
| Option+Shift+H/J/K/L | Move the window in that direction |
| Option+F | Toggle fullscreen |
| Option+T | Toggle floating or tiled |
| Option+R | Toggle the split between horizontal and vertical |
| Option+B | Make window sizes even |
| Option+Shift+R | Enter resize mode, shown as `RESIZE` in the bar |

In resize mode, H / L make the window narrower / wider, and K / J make it shorter / taller. Escape or Enter leaves. Other shortcuts stay off until you leave. Height only changes when windows are stacked vertically.

### Workspaces and monitors

| Keys | Action |
|---|---|
| Option+1-6 | Go to that workspace |
| Option+Shift+1-6 | Send the window to that workspace, and stay where you are |
| Option+Tab | Go back to the previous workspace |
| Option+, / Option+. | Focus the left / right monitor |
| Option+Shift+, / Option+Shift+. | Send the window to the left / right monitor |

A pinned workspace always opens on its own monitor, so Option+4 from the main monitor moves focus to the secondary one.

### Apps and tools

| Keys | Action | Goes to |
|---|---|---|
| Option+Enter | New Ghostty window | Workspace 1 |
| Option+Shift+T | btop in a new Ghostty window | Workspace 1 |
| Option+Shift+N | Open Zed | Workspace 2 |
| Option+Shift+Enter | New Helium window | Workspace 3 |
| Option+Shift+F | Finder at your home folder | Current workspace, floating |
| Option+` | Drop-down terminal | Over the current workspace |
| Option+Shift+I | Keep the Mac awake, or stop | |
| Option+Shift+Space | Show or hide the bar | |
| Option+/ | Show or hide the key cheat sheet | |

### Who handles each key

- **AeroSpace** (`aerospace.toml`): the window and workspace keys, and Option+Enter.
- **Hammerspoon** (`init.lua`): the other app and tool keys, and Option+/.
- **Ghostty** (`config`): Option+\`.

A key should be bound in only one of them. `tests/run.sh` fails if one is bound in both.

### Clashes

These tools take the keys system-wide, so apps never receive them:

- **Turkish-QWERTY-PC:** these characters can't be typed, because their keys are taken: `>` `£` `#` `$` `½` (Option+1-5), `^` (Option+H), `₺` (Option+T) and `€` (Option+Shift+2).
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
| 6 | Apple Music, Spotify | Secondary, or main if there is only one |

- Each app opens on its workspace. Finder, System Settings and Calculator float on the current workspace instead.
- There are six workspaces in total, not six per monitor, because AeroSpace workspaces are global.
- When the secondary display is unplugged, workspaces 4-6 move to the main one, and they return when it is plugged back in.
- `btop` opens on workspace 1 when AeroSpace starts, unless one is already running.
- Ghostty windows share one process. The first time you use Option+Enter or Option+Shift+T, macOS asks to let AeroSpace and Hammerspoon control Ghostty, and those keys need that permission.

## The bar

Workspace numbers sit on the left. The focused workspace is a white pill, the one visible on the other monitor is a gray pill, and the mode shows next to them while it isn't the normal mode. Click a number to go there, or scroll over the numbers to move one workspace at a time, wrapping around.

On the right, from left to right:

| Item | Shows | Click | Scroll |
|---|---|---|---|
| Keep-awake | A crossed-out Zzz, only while keep-awake is on | Turn it off | |
| Claude | Usage limits, as `5h 23%  7d 41%` | Swap to the reset times | |
| Clock | Day and time | Show this month's calendar, which closes when the pointer leaves | |
| Wi-Fi | Connected or not | Open Wi-Fi settings | |
| Volume | Level | Mute or unmute | Change the volume by 5% |
| Battery | Charge | Show or hide the percentage | |

### Keep-awake

Option+Shift+I runs `caffeinate -di`, which keeps both the display and the system awake. This is useful during long builds or Claude Code runs. Press the key again or click the icon to stop.

- It stays on when the bar restarts, and turns off at reboot.
- Only the `caffeinate` this item started is checked or stopped. Its process ID is saved in `~/.local/state/omv/keep-awake.pid`.
- Closing the lid on battery still puts the Mac to sleep. `caffeinate` can't prevent that.
- The key sends an event to the bar, so it does nothing while SketchyBar isn't running.

### Claude usage

The item shows Claude's 5-hour and 7-day usage, with the Claude logo. The higher of the two sets its look:

| Highest usage | Look |
|---|---|
| Under 70% | Gray |
| 70-89% | White |
| 90% and up | White pill |

- The numbers come from Claude Code's status line, so they only update while Claude Code runs. Usage from elsewhere, such as claude.ai, shows after your next response in Claude Code.
- A window past its reset time shows 0%.
- `install.sh` adds one line to `~/.claude/statusline-wrapper.sh` through `claude-usage.sh`. If that file doesn't exist, the item stays hidden.
- Only the four numbers are stored, in `~/.local/state/omv/claude-usage`.

## Uninstall

```sh
./uninstall.sh        # removes AeroSpace and SketchyBar, keeps the older tool links
./uninstall.sh --all  # also unlinks ghostty, nvim, btop and hammerspoon
```

It:

1. Quits AeroSpace and SketchyBar, and stops keep-awake if it is on.
2. Removes the Claude usage line from your status line wrapper.
3. Unlinks the packages.
4. Returns both macOS settings to their defaults.
5. Uninstalls both tools and untaps both taps.
6. Prints the steps left for you.

It leaves this repo, other Homebrew packages, fonts, `~/.config/omniwm` and `~/.config-backup` alone.

## Tests

```sh
tests/run.sh
```

The tests use stubs and a temporary `HOME`, so they never change the real system. They need `stow`, `python3` and `luajit`.

## Differences from the article

- Trusts the taps first, because Homebrew refuses to load untrusted ones.
- Starts SketchyBar from AeroSpace, which the article never does.
- Sets `PATH` and `LANG` for apps started at login.
- Raises the top gap on external displays, so windows don't slide under the bar.
- Pins workspaces to monitors and updates the bar when monitor focus changes.
- Turns off "Displays have separate Spaces", as AeroSpace's guide recommends.
- Makes launch keys switch workspace first, because new windows route away without following.
- Keeps the recovered Vantablack bar and plugins, because the article doesn't copy the example plugins.
