# omv

A keyboard-driven macOS desktop. AeroSpace tiles the windows, SketchyBar draws the top bar, Hammerspoon launches apps, and Ghostty, Neovim and btop share the Vantablack look. It is based on [Koen van Gilst's setup](https://koenvangilst.nl/lab/aerospace-sketchybar-macos-setup), with the [fixes listed at the end](#differences-from-the-article).

![Workspace 1 with btop and Vim, under the top bar](docs/workspace-1.png)

## What's inside

Each folder is a GNU Stow package, linked into `$HOME`.

| Package | Links | What it does |
|---|---|---|
| `aerospace` | `~/.config/aerospace` | Tiling, workspaces and window keys |
| `sketchybar` | `~/.config/sketchybar` | The top bar and its plugins |
| `hammerspoon` | `~/.hammerspoon` | App keys, the system menu, the key list and the calendar |
| `ghostty` | `~/.config/ghostty` | Terminal config and window scripts |
| `nvim` | `~/.config/nvim` | Neovim config |
| `btop` | `~/.config/btop` | btop config |
| `claude` | `~/.claude/bar-usage.sh` | Feeds Claude's usage limits to the bar |
| `swipeaerospace` | `~/.config/swipeareospace` | Three-finger swipe between workspaces |

## Requirements

- Homebrew and `stow`, which `install.sh` checks for.
- `jq`, used by the Claude usage item.
- Xcode's Command Line Tools, for `swiftc`, used by the capture menu's text and color items and by the calendar's events.
- The JetBrainsMono Nerd Font, in both the Mono and Propo variants.
- The apps the keys and workspaces expect: Ghostty, Hammerspoon, Zed, Helium, Neovim and btop.

`install.sh` installs only AeroSpace, SketchyBar, borders and SwipeAeroSpace. Everything else on this list must already be there.

## Install

```sh
./install.sh
```

It is safe to run again. It:

1. Trusts the third-party taps `nikitabobko/tap`, `felixkratz/formulae` and `mediosz/tap`, then installs AeroSpace, SketchyBar, borders and SwipeAeroSpace from them.
2. Links all eight packages with Stow.
3. Adds the Claude usage line to your status line wrapper, as described in [Claude usage](#claude-usage).
4. Hides the macOS menu bar, turns off "Displays have separate Spaces", turns off window-opening animations, lets Ctrl+Cmd drag a window from anywhere, and turns off macOS's three-finger horizontal swipe, so a swipe only switches workspace.

Then do these by hand:

1. Open AeroSpace from Finder and grant Accessibility in System Settings.
2. Log out and back in, so "Displays have separate Spaces" and macOS's three-finger swipe turn off.
3. If the menu bar still shows, set System Settings > Menu Bar > "Automatically hide and show the menu bar" to Always.
4. In System Settings > Displays > Arrange, leave each display a free bottom corner, because AeroSpace hides windows there.
5. Open SwipeAeroSpace, grant Accessibility, and turn on Launch at Login in its Settings.

When you pull new files later, run `./install.sh` again. Stow links files one by one, so a new file has no link until then.

## Keys

Every shortcut starts with Option. Option alone goes somewhere or acts on the current window. Adding Shift takes the window with it or launches an app. H/J/K/L mean left, down, up and right, as in Vim.

Press Option+/ to see every key at once, in a searchable two-column list. Type to filter by description or key, and press Escape to close. The list is built from `aerospace.toml` and `init.lua`, so it never goes stale.

![The key list, showing every shortcut in two columns](docs/key-list.png)

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
| Option+Space | Go to any window, on any workspace |

A pinned workspace always opens on its own monitor, so Option+4 from the main monitor moves focus to the secondary one.

Option+Space lists every open window, with its app and workspace. Type to filter by title, app or workspace number, and press Enter to go there.

<img src="docs/windows.png" alt="The window list, with btop selected" width="720">

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
| Option+Shift+U | Copy Helium's current URL | |
| Option+Shift+S | Open the [capture menu](#capture-menu) | |
| Option+Shift+M | Set a [reminder](#reminders) | |
| Option+Shift+Space | Show or hide the bar | |
| Option+Escape | Open the [system menu](#system-menu) | |
| Option+/ | Show or hide the key list | |

The first time you use Option+Shift+U, macOS asks to let Hammerspoon control Helium, and the key needs that permission.

### Who handles each key

- **AeroSpace** (`aerospace.toml`): the window and workspace keys, and Option+Enter.
- **Hammerspoon** (`init.lua`): the other app and tool keys, Option+Space, Option+Escape and Option+/.
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
- Ctrl+Cmd+drag moves a floating window by any part of it. A tiled window snaps back to its tile when you let go.
- There are six workspaces in total, not six per monitor, because AeroSpace workspaces are global.
- Swipe three fingers left or right on the trackpad to move one workspace, wrapping around. A swipe stays on the focused monitor, so with two monitors it cycles 1-3 on the main one and 4-6 on the secondary. Scrolling over the bar's numbers crosses all six.
- When the secondary display is unplugged, workspaces 4-6 move to the main one, and they return when it is plugged back in.
- `btop` opens on workspace 1 when AeroSpace starts, unless one is already running.
- The focused window gets a 2pt gray outline, the same gray as the cards' border, drawn by [JankyBorders](https://github.com/FelixKratz/JankyBorders). It starts with AeroSpace.
- In Ghostty, a command that runs longer than 10 seconds sends a notification when it finishes while you're in another window. The first one makes macOS ask to allow notifications from Ghostty.
- Ghostty windows share one process. The first time you use Option+Enter or Option+Shift+T, macOS asks to let AeroSpace and Hammerspoon control Ghostty, and those keys need that permission.

## System menu

Option+Escape opens a menu modeled on Omarchy's: a card whose title is also a search field.

<img src="docs/system-menu.png" alt="The system menu, with Lock selected" width="320">

| Item | Does |
|---|---|
| Lock | Locks the screen |
| Screensaver | Starts the screensaver |
| Sleep | Puts the Mac to sleep |
| Log out, Restart, Shut down | Ask first, with Cancel selected |
| Sound › | Picks where sound plays: speakers, AirPods, a monitor |
| Reload › | Reloads AeroSpace, SketchyBar, Hammerspoon, or all three |

Type to filter, Up and Down to move, Enter or Right to pick, Left or Backspace to go back, and Escape or a click elsewhere to close.

Sound lists every output device, with the one in use selected and marked `current`. It's read each time it opens, so AirPods show up as soon as they connect. Virtual devices, such as the ones Zoom and Teams add, are left out unless they're in use. Right-clicking the volume item in the bar opens it too.

Scripts can open each card with `hs -c`: `omvToggleSystemMenu()`, `omvToggleSound()`, `omvToggleKeyList()`, `omvToggleCalendar()`, `omvToggleWindows()`, `omvToggleCapture()`, `omvNewReminder()` and `omvToggleReminders()`.

## Capture menu

Option+Shift+S opens a card for screen captures:

| Item | Does |
|---|---|
| Region to clipboard | Select an area, copy it as a picture |
| Region to file | Select an area, save it to the Desktop, named like macOS's own screenshots |
| Window to clipboard | Click a window, copy it |
| Screen to clipboard | Copy the whole screen |
| Text from screen | Select an area, copy the text in it, read by macOS's Vision framework |
| Pick a color | Click anywhere, copy its color as `#RRGGBB` |

<img src="docs/capture.png" alt="The capture menu" width="320">

- The first capture asks you to give Hammerspoon Screen Recording, in System Settings > Privacy & Security > Screen & System Audio Recording. Every item except Pick a color needs it.
- Text and color use a small Swift helper, `capture.swift`. It's built with `swiftc` the first time you use one of them, which takes a few seconds, and kept in `~/.cache/omv/capture`. `swiftc` comes with Xcode's Command Line Tools.

## The bar

Workspace numbers sit on the left. The focused workspace is a white pill, the one visible on the other monitor is a gray pill, and the mode shows next to them while it isn't the normal mode. Click a number to go there, or scroll over the numbers to move one workspace at a time, wrapping around.

While Music or Spotify plays, the track shows after the numbers as `Artist — Title`, cut at 40 characters. Click it to play or pause, and scroll up or down for the next or previous track. It hides when nothing plays, and it never opens a player that is closed. The first time, macOS asks to let SketchyBar control Music and Spotify.

On the right, from left to right:

| Item | Shows | Click | Scroll |
|---|---|---|---|
| Meeting | The next Calendar event, only from an hour before it starts | Open the [calendar](#calendar) | |
| Reminder | Time left on the next reminder, only while one is set | List them, to cancel one | |
| Keep-awake | A crossed-out Zzz, only while keep-awake is on | Turn it off | |
| Claude | Usage limits, as `5h 23%  7d 41%` | Show the reset times for 10 seconds | |
| Clock | Day and time | Open the [calendar](#calendar) | |
| Wi-Fi | Connected or not | Open Wi-Fi settings | |
| Volume | Level | Mute or unmute. Right-click to pick the output | Change the volume by 5% |
| Battery | Charge | Show or hide the percentage | |

### Calendar

Clicking the clock opens a calendar card under it. Weeks start on Monday and show their ISO week number, today is a white square, and the footer shows today's date and week. Left and Right (or ‹ and ›) change month, T goes back to today, and Escape or a click elsewhere closes it.

<img src="docs/calendar.png" alt="The calendar card, with today marked" width="360">

Under the footer, the card lists today's events from Calendar.app, so it covers every account added there, such as iCloud, Google and Exchange.

- Each event shows its start time, or `all day`. Events already over are dimmed, and the one going on now is white.
- It lists five at most, then `+N more`. When there are more, events already over are left out first.
- Cancelled events and ones you declined are left out.
- The meeting item in the bar shows the next timed event's start time, as `14:00`, from an hour before it starts. The title stays in the card, so the item doesn't run under the notch next to a reminder. It turns into a white pill 5 minutes before the start and goes away 5 minutes after. All-day events stay out of the bar.
- Events are read when Hammerspoon starts, every 5 minutes, when the Mac wakes and when the card opens.
- They're read by a small Swift helper, `agenda.swift`. It's built the first time into `~/.cache/omv/Agenda.app`, which takes a few seconds, and it runs as its own app, because macOS asks the app that reads calendars for permission, and Hammerspoon can't ask. The first time, macOS asks to let "omv agenda" access your calendars. If you refuse, the card says so, and you can allow it later in System Settings > Privacy & Security > Calendars.

### Reminders

Option+Shift+M asks "Remind me…". Type a time, then what to remember, such as `25m check deploy` or `1h30m stand up`, and press Enter. Times use `h`, `m` and `s`, and can be combined.

#### Pomodoro

`pomo` starts 25 minutes of focus, and `pomo write tests` names the task. When the time is up, the screen dims and a large card takes over. Nothing after it starts on its own: you pick each step.

1. **Time for a break.** Shows the task and today's count, as `2 OF 4 TODAY` with dots. Pick **Start 5-minute break**, **5 more minutes** (once per pomo), or **Skip break**.
2. **Break.** A large countdown, a progress line and a tip that changes each break. The bar shows a coffee cup with the time left. **End break early** stops it.
3. **Back to work?** Pick **Start next pomo**, which reuses the task, or **Done for now**.

- Escape skips the break on the first card, ends it early on the second, and stops on the last.
- The cards stay open when focus moves away, since the break is the point. During a break, clicking the bar item reopens the countdown.
- Typing `break` starts a 5-minute break straight away.
- A break survives a Hammerspoon reload: the bar keeps counting down, and "Back to work?" opens when it ends.
- Today's count is kept in `~/.local/state/omv/pomo`, and starts over each day.

<img src="docs/reminder.png" alt="The reminder card" width="480">

- The bar shows the time left on the soonest reminder, plus `+N` for the others, such as `24:10 +1`. The text stays out of the bar, so it doesn't run under the notch.
- When one is due, you get a notification and an alert, and the bar item turns into a white pill with the start of its text for 10 seconds.
- Click the bar item to list your reminders, and press Enter on one to cancel it.
- Reminders are saved in `~/.local/state/omv/reminders`, so they survive a Hammerspoon reload. One whose time passed while Hammerspoon wasn't running is dropped.

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
./uninstall.sh        # removes AeroSpace, SketchyBar, borders and SwipeAeroSpace, keeps the older tool links
./uninstall.sh --all  # also unlinks ghostty, nvim, btop and hammerspoon
```

It:

1. Quits AeroSpace, SwipeAeroSpace, SketchyBar and borders, and stops keep-awake if it is on.
2. Removes the Claude usage line from your status line wrapper.
3. Unlinks the packages.
4. Returns the macOS, animation, dragging and trackpad settings to their defaults.
5. Uninstalls the four tools and untaps their taps.
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
