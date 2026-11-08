# omv

A keyboard-driven macOS desktop with one look throughout. AeroSpace tiles the windows, SketchyBar draws the top bar, Hammerspoon adds menus, cards and app keys, and Ghostty, Neovim and btop share the Vantablack theme. It started from [Koen van Gilst's setup](https://koenvangilst.nl/lab/aerospace-sketchybar-macos-setup), with the [fixes listed at the end](#differences-from-the-article).

![Workspace 1 with btop and Neovim, under the top bar](docs/workspace-1.png)

## Features

- [**Tiling and workspaces**](#tiling-and-workspaces): six workspaces with fixed homes for each app, Vim-style keys, a focus border, and three-finger swipes.
- [**The bar**](#the-bar): workspaces, the playing track, reminders, meetings, Claude usage, and a macOS-style clock that stays clear of the notch.
- [**Window list**](#window-list): Option+Space jumps to any window on any workspace.
- [**Key list**](#key-list): Option+/ shows every shortcut at once.
- [**System menu and Sound**](#system-menu-and-sound): lock, sleep, restart, reload the tools, and pick where sound plays.
- [**Calendar and today's events**](#calendar-and-todays-events): click the clock for the month and today's Calendar.app events.
- [**Reminders and Pomodoro**](#reminders-and-pomodoro): `25m check deploy`, or `pomo` for focus blocks with break cards.
- [**Capture menu**](#capture-menu): screenshots, text from the screen, and a color picker.
- [**Smaller tools**](#smaller-tools): keep the Mac awake, copy the browser's URL, a drop-down terminal, and notifications when long commands finish.

Every card shares one design: a black card with a gray border, a title that doubles as a search field, and Up, Down, Enter and Escape to drive it.

## Tiling and workspaces

Every shortcut starts with Option. Option alone goes somewhere or acts on the current window, and adding Shift takes the window with it or launches an app. H/J/K/L mean left, down, up and right, as in Vim.

| Workspace | Apps | Monitor |
|---|---|---|
| 1 | Ghostty | Main |
| 2 | Zed | Main |
| 3 | Helium | Main |
| 4 | Obsidian, Notion, Linear | Secondary, or main if there is only one |
| 5 | Notes, Messages, WhatsApp, Discord | Secondary, or main if there is only one |
| 6 | Apple Music, Spotify | Secondary, or main if there is only one |

- **Each app opens on its workspace.** Finder, System Settings and Calculator float on the current workspace instead.
- **Six workspaces in total,** not six per monitor, because AeroSpace workspaces are global. A pinned workspace always opens on its own monitor, so Option+4 from the main monitor moves focus to the secondary one. When the secondary display is unplugged, workspaces 4-6 move to the main one, and they return when it's plugged back in.
- **Focus border:** the focused window gets a 2pt gray outline, the same gray as the cards' border, drawn by [JankyBorders](https://github.com/FelixKratz/JankyBorders). It starts with AeroSpace.
- **Trackpad:** swipe three fingers left or right to move one workspace, wrapping around. A swipe stays on the focused monitor, so with two monitors it cycles 1-3 on the main one and 4-6 on the secondary.
- **Option+Tab** goes back to the previous workspace.
- **Tabbed layout:** Option+A switches the workspace between tiles and tabs. In tabs, the focused window takes almost the whole width and the others peek out at the edges, which suits a laptop screen. Option+H / L move between them. AeroSpace remembers the layout per workspace.
- **Dragging:** Ctrl+Cmd+drag moves a floating window by any part of it. A tiled window snaps back to its tile when you let go.
- **Resize mode:** Option+Shift+R, shown as `RESIZE` in the bar. H / L make the window narrower / wider, and K / J shorter / taller. Escape or Enter leaves, and other shortcuts stay off until you do. Height only changes when windows are stacked vertically.
- **btop** opens on workspace 1 when AeroSpace starts, unless one is already running.

![Tiles against tabbed: three code windows in thirds, where long lines wrap, and the same three tabbed, where the focused window gets the width and the others wait as strips at the edges](docs/tabbed.png)

## The bar

![The bar: workspaces and the playing track on the left, a reminder, Claude usage, status icons and the clock on the right](docs/bar.png)

**On the left**, workspace numbers: the focused one is a white pill, and the one visible on the other monitor is a gray pill. Click a number to go there, or scroll over them to move one workspace at a time across all six, wrapping around. The binding mode shows next to them while it isn't the normal one.

While Music or Spotify plays, the track follows as `Artist — Title`, cut at 40 characters. Click it to play or pause, and scroll for the next or previous track. It hides when nothing plays and never opens a player that is closed.

**On the right**, from left to right:

| Item | Shows | Click | Scroll |
|---|---|---|---|
| Meeting | The next Calendar event's start time, from an hour before | Open the [calendar](#calendar-and-todays-events) | |
| Reminder | Time left on the next reminder, plus `+N` for others | List them, to cancel one | |
| Keep-awake | A crossed-out Zzz, while keep-awake is on | Turn it off | |
| Claude | Usage limits, as `5h 23%  7d 41%` | Show the reset times for 10 seconds | |
| Wi-Fi | Connected or not | Open Wi-Fi settings | |
| Volume | Level | Mute or unmute. Right-click to pick the output | Change the volume by 5% |
| Battery | Charge | Show or hide the percentage | |
| Clock | Date and time, as `Sun Nov 8 12:09` | Open the [calendar](#calendar-and-todays-events) | |

**Clear of the notch:** when the right side gets too full, items give way in this order until it fits: Claude's numbers (its logo stays), then the meeting's time (its icon stays), then the Claude logo. Keep-awake, the reminder and the status icons always stay, and everything comes back once there's room.

**Claude usage** shows the 5-hour and 7-day limits. The higher one sets the look: gray under 70%, white from 70%, and a white pill from 90%.

- The numbers come from Claude Code's status line, so they only update while Claude Code runs. Usage from elsewhere, such as claude.ai, shows after your next response in Claude Code.
- A window past its reset time shows 0%.
- `install.sh` adds one line to `~/.claude/statusline-wrapper.sh` through `claude-usage.sh`. If that file doesn't exist, the item stays hidden.
- Only the four numbers are stored, in `~/.local/state/omv/claude-usage`.

Option+Shift+Space shows or hides the bar.

## Window list

Option+Space lists every open window with its app and workspace. Type to filter by title, app or workspace number, and press Enter to go there.

<img src="docs/windows.png" alt="The window list, with btop selected" width="720">

## Key list

Option+/ shows every key at once, in a searchable two-column list. Type to filter by description or key, and press Enter (or click) on a row to run that shortcut: the list closes, focus goes back to your window, and the action runs. The list is built from `aerospace.toml` and `init.lua`, so it never goes stale.

![The key list, showing every shortcut in two columns](docs/key-list.png)

## System menu and Sound

Option+Escape opens a menu modeled on Omarchy's.

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

**Sound** lists every output device, with the one in use selected and marked `current`. It's read each time it opens, so AirPods show up as soon as they connect. Virtual devices, such as the ones Zoom and Teams add, are left out unless they're in use. Right-clicking the volume item in the bar opens it too.

<img src="docs/sound.png" alt="The Sound card, with the speakers in use and AirPods listed" width="420">

## Calendar and today's events

Click the clock for a calendar card. Weeks start on Monday and show their ISO week number, today is a white square, and the footer shows today's date and week. Left and Right (or ‹ and ›) change month, T goes back to today, and Escape or a click elsewhere closes it.

<img src="docs/calendar.png" alt="The calendar card, with today marked and today's events under it" width="360">

Under the footer are today's events from Calendar.app, so every account added there counts, such as iCloud, Google and Exchange.

- Each event shows its start time, or `all day`. Events already over are dimmed, and the one going on now is white.
- It lists five at most, then `+N more`. When there are more, events already over are left out first. Cancelled events and ones you declined are left out.
- **In the bar,** the meeting item shows the next timed event's start time, as `14:00`, from an hour before it starts. It turns into a white pill 5 minutes before the start and goes away 5 minutes after. All-day events stay out of the bar.
- Events are read when Hammerspoon starts, every 5 minutes, when the Mac wakes, and when the card opens.
- They're read by a small Swift helper, `agenda.swift`, built the first time into `~/.cache/omv/Agenda.app`. It runs as its own app because macOS asks the app that reads calendars for permission, and Hammerspoon can't ask. The first time, macOS asks to let "omv agenda" access your calendars. If you refuse, the card says so, and you can allow it later in System Settings > Privacy & Security > Calendars.

## Reminders and Pomodoro

Option+Shift+M asks "Remind me…". Type a time, then what to remember, and press Enter.

<img src="docs/reminder.png" alt="The reminder card, with its hint: 25m check deploy, pomo, b break, c cancel" width="480">

| Type | Does |
|---|---|
| `25m check deploy`, `1h30m stand up` | A reminder. Times use `h`, `m` and `s`, and can be combined |
| `r 25m check deploy` | The same, with an optional `r` |
| `pomo`, `pomo write tests` | 25 minutes of focus, optionally named |
| `b`, `break` | A 5-minute break, straight away |
| `c` | Cancels the soonest reminder |

- The bar shows the time left on the soonest reminder, with a target icon during a pomo and a coffee cup during a break.
- When a plain reminder is due, you get a notification and an alert, and the bar item turns into a white pill with the start of its text for 10 seconds.
- Click the bar item to list your reminders, and press Enter on one to cancel it.
- Reminders are saved in `~/.local/state/omv/reminders`, so they survive a Hammerspoon reload. One whose time passed while Hammerspoon wasn't running is dropped.

**Pomodoro.** When a pomo's time is up, the screen dims and a large card takes over. Nothing after it starts on its own: you pick each step.

1. **Time for a break.** The task and today's count, as `2 OF 4 TODAY` with dots. `b` starts the break, which is 15 minutes after every 4th pomo and 5 minutes otherwise, `r` gives 5 more minutes (once per pomo), and `c` skips the break.
2. **Break.** A large countdown, a progress line and a tip that changes each break. The bar shows a coffee cup with the time left. `c` ends it early.
3. **Back to work?** Enter starts the next pomo with the same task, and `c` stops for now.

<img src="docs/pomo-done.png" alt="Time for a break: start the break, 5 more minutes, or skip it" width="560">
<img src="docs/pomo-break.png" alt="The break: a countdown, a progress line and a tip" width="560">
<img src="docs/pomo-over.png" alt="Back to work: start the next pomo or stop for now" width="560">

- In a pomo's last 30 seconds, the bar's target item turns into a white pill, so the card never comes as a surprise.
- Escape does the same as `c` on each card.
- The cards stay open when focus moves away, since the break is the point. During a break, clicking the bar item reopens the countdown.
- A break survives a Hammerspoon reload: the bar keeps counting down, and "Back to work?" opens when it ends.
- Today's count is kept in `~/.local/state/omv/pomo` and starts over each day.

## Capture menu

Option+Shift+S opens a card for screen captures.

<img src="docs/capture.png" alt="The capture menu" width="320">

| Item | Does |
|---|---|
| Region to clipboard | Select an area, copy it as a picture |
| Region to file | Select an area, save it to the Desktop, named like macOS's own screenshots |
| Window to clipboard | Click a window, copy it |
| Screen to clipboard | Copy the whole screen |
| Text from screen | Select an area, copy the text in it, read by macOS's Vision framework |
| Pick a color | Click anywhere, copy its color as `#RRGGBB` |

- The first capture asks you to give Hammerspoon Screen Recording, in System Settings > Privacy & Security > Screen & System Audio Recording. Every item except Pick a color needs it.
- Text and color use a small Swift helper, `capture.swift`, built with `swiftc` the first time and kept in `~/.cache/omv/capture`.

## Smaller tools

- **Keep awake (Option+Shift+I):** runs `caffeinate -di`, keeping the display and system awake during long builds or Claude Code runs. Press the key again or click the icon to stop. It stays on when the bar restarts and turns off at reboot. Only the `caffeinate` it started is checked or stopped, through its process ID in `~/.local/state/omv/keep-awake.pid`. Closing the lid on battery still puts the Mac to sleep, and the key does nothing while SketchyBar isn't running.
- **Copy URL (Option+Shift+U):** copies Helium's current URL. The first time, macOS asks to let Hammerspoon control Helium.
- **Drop-down terminal (Option+\`):** Ghostty's quick terminal, over any workspace.
- **Long commands:** in Ghostty, a command that runs longer than 10 seconds sends a notification when it finishes while you're in another window. The first one makes macOS ask to allow notifications from Ghostty.
- **Scripting:** each card opens with `hs -c`: `omvToggleSystemMenu()`, `omvToggleSound()`, `omvToggleKeyList()`, `omvToggleCalendar()`, `omvToggleWindows()`, `omvToggleCapture()`, `omvNewReminder()` and `omvToggleReminders()`.

## Keys

### Windows and workspaces

| Keys | Action |
|---|---|
| Option+H/J/K/L | Focus the window in that direction |
| Option+Shift+H/J/K/L | Move the window in that direction |
| Option+F | Toggle fullscreen |
| Option+T | Toggle floating or tiled |
| Option+R | Toggle the split between horizontal and vertical |
| Option+A | Toggle tabbed or tiled |
| Option+B | Make window sizes even |
| Option+Shift+R | Enter resize mode |
| Option+1-6 | Go to that workspace |
| Option+Shift+1-6 | Send the window to that workspace, and stay where you are |
| Option+Tab | Go back to the previous workspace |
| Option+, / Option+. | Focus the left / right monitor |
| Option+Shift+, / Option+Shift+. | Send the window to the left / right monitor |
| Option+Space | Go to any window, on any workspace |

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
| Option+Shift+S | Capture menu | |
| Option+Shift+M | Set a reminder | |
| Option+Shift+Space | Show or hide the bar | |
| Option+Escape | System menu | |
| Option+/ | Show or hide the key list | |

Ghostty windows share one process. The first time you use Option+Enter or Option+Shift+T, macOS asks to let AeroSpace and Hammerspoon control Ghostty, and those keys need that permission.

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

## Install

### Requirements

- Homebrew and `stow`, which `install.sh` checks for.
- `jq`, used by the bar.
- Xcode's Command Line Tools, for `swiftc`, used by the capture menu's text and color items and by the calendar's events.
- The JetBrainsMono Nerd Font, in both the Mono and Propo variants.
- The apps the keys and workspaces expect: Ghostty, Hammerspoon, Zed, Helium, Neovim and btop.

`install.sh` installs only AeroSpace, SketchyBar, borders and SwipeAeroSpace. Everything else on this list must already be there.

### Run it

```sh
./install.sh
```

It's safe to run again. It:

1. Trusts the third-party taps `nikitabobko/tap`, `felixkratz/formulae` and `mediosz/tap`, then installs AeroSpace, SketchyBar, borders and SwipeAeroSpace from them.
2. Links all eight packages with Stow.
3. Adds the Claude usage line to your status line wrapper.
4. Hides the macOS menu bar, turns off "Displays have separate Spaces", turns off window-opening animations, lets Ctrl+Cmd drag a window from anywhere, and turns off macOS's three-finger horizontal swipe, so a swipe only switches workspace.

Then, by hand:

1. Open AeroSpace from Finder and grant Accessibility in System Settings.
2. Log out and back in, so "Displays have separate Spaces" and macOS's three-finger swipe turn off.
3. If the menu bar still shows, set System Settings > Menu Bar > "Automatically hide and show the menu bar" to Always.
4. In System Settings > Displays > Arrange, leave each display a free bottom corner, because AeroSpace hides windows there.
5. Open SwipeAeroSpace, grant Accessibility, and turn on Launch at Login in its Settings.

When you pull new files later, run `./install.sh` again. Stow links files one by one, so a new file has no link until then.

### Doctor

```sh
./doctor.sh
```

Checks that everything is in place, and says how to fix what isn't: the tools, apps and font, that every package is linked with no broken links left behind, that AeroSpace, SketchyBar, borders, Hammerspoon and SwipeAeroSpace are running with the omv config loaded, the macOS settings, AeroSpace's Accessibility, and the Claude usage line. It only reads, and exits non-zero when something fails.

It also lists what macOS doesn't let a script read, to check by hand: Screen Recording for Hammerspoon, Calendar access for "omv agenda", and Accessibility for SwipeAeroSpace.

### What's inside

Each folder is a GNU Stow package, linked into `$HOME`.

| Package | Links | What it does |
|---|---|---|
| `aerospace` | `~/.config/aerospace` | Tiling, workspaces and window keys |
| `sketchybar` | `~/.config/sketchybar` | The top bar and its plugins |
| `hammerspoon` | `~/.hammerspoon` | App keys and every card: menus, lists, calendar, reminders, capture |
| `ghostty` | `~/.config/ghostty` | Terminal config and window scripts |
| `nvim` | `~/.config/nvim` | Neovim config |
| `btop` | `~/.config/btop` | btop config |
| `claude` | `~/.claude/bar-usage.sh` | Feeds Claude's usage limits to the bar |
| `swipeaerospace` | `~/.config/swipeareospace` | Three-finger swipe between workspaces |

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
