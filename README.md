# omv

A keyboard-driven macOS desktop with one look throughout. AeroSpace tiles the windows, SketchyBar draws the top bar, Hammerspoon adds menus, cards and app keys, and Ghostty, Neovim and btop share the Vantablack theme. It started from [Koen van Gilst's setup](https://koenvangilst.nl/lab/aerospace-sketchybar-macos-setup), with the [fixes listed at the end](#differences-from-the-article).

![Workspace 1 with btop and Neovim, under the top bar](docs/workspace-1.png)

## Features

- [**Tiling and workspaces**](#tiling-and-workspaces): six workspaces with fixed homes for each app, Vim-style keys, Option+Tab back to the last workspace, a tabbed layout, a focus border, and three-finger swipes.
- [**The bar**](#the-bar): workspaces, the playing track, reminders, meetings, Claude usage, and a macOS-style clock that stays clear of the notch.
- [**Window list**](#window-list): Option+Space jumps to any window on any workspace.
- [**Key list**](#key-list): Option+/ shows every shortcut at once, and runs the one you pick.
- [**System menu**](#system-menu): lock, sleep, restart and reload the tools.
- [**Sound**](#sound): volume, mute, output and input devices, and a live mic level.
- [**Wi-Fi and Ethernet**](#wi-fi-and-ethernet): the network, signal, address and router, a click away.
- [**Agents**](#agents): Claude Code's session and weekly limits, one click to continue or start a session, and a pill when a session waits for you.
- [**Battery**](#battery): charge, time left, cycles and power draw.
- [**Weather**](#weather): the temperature in the bar, and a three-day forecast for wherever the Mac is.
- [**Calendar and today's events**](#calendar-and-todays-events): click the clock for the month and today's Calendar.app events.
- [**Reminders and Pomodoro**](#reminders-and-pomodoro): `25m check deploy`, or `pomo` for focus blocks with break cards and a long break after every fourth.
- [**Capture menu**](#capture-menu): screenshots, text from the screen, and a color picker.
- [**Smaller tools**](#smaller-tools): keep the Mac awake, copy the browser's URL, a drop-down terminal, and notifications when long commands finish.
- [**Doctor**](#doctor): `./doctor.sh` checks the tools, links, running services and settings, and says how to fix whatever is wrong.

Every card shares one design: a black card with a gray border, a title that doubles as a search field, and Up, Down, Enter and Escape to drive it. With two displays, a card opens on the one the pointer is on, so a click on the bar opens it on that display. A card that belongs to a bar item, such as Agents, Wi-Fi or the calendar, opens just under that item.

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

- **Each app opens on its workspace.** Finder tiles on the current workspace instead, though its Get Info windows float, and System Settings and Calculator float there.
- **Six workspaces in total,** not six per monitor, because AeroSpace workspaces are global. A pinned workspace always opens on its own monitor, so Option+4 from the main monitor moves focus to the secondary one. When the secondary display is unplugged, workspaces 4-6 move to the main one, and they return when it's plugged back in.
- **Focus border:** the focused window gets a 2pt gray outline, the same gray as the cards' border, drawn by [JankyBorders](https://github.com/FelixKratz/JankyBorders). It starts with AeroSpace. It's drawn at 1x (`hidpi=off`), which takes about 40 MB instead of up to 209 MB. For a sharper outline on Retina, change `hidpi=off` to `hidpi=on` in `aerospace.toml`, then run `pkill -x borders` and restart AeroSpace.
- **Trackpad:** swipe three fingers left or right to move one workspace, wrapping around. A swipe stays on the focused monitor, so with two monitors it cycles 1-3 on the main one and 4-6 on the secondary.
- **Option+Tab** goes back to the previous workspace.
- **Tabbed layout:** Option+A switches the workspace between tiles and tabs. In tabs, the focused window takes almost the whole width and the others peek out at the edges, which suits a laptop screen. Option+H / L move between them. AeroSpace remembers the layout per workspace.
- **Dragging:** Ctrl+Cmd+drag moves a floating window by any part of it. A tiled window snaps back to its tile when you let go.
- **Resize mode:** Option+Shift+R, shown as `RESIZE` in the bar. H / L make the window narrower / wider, and K / J shorter / taller. Escape or Enter leaves, and other shortcuts stay off until you do. Height only changes when windows are stacked vertically.
- **btop** opens on workspace 1 when AeroSpace starts, unless one is already running.

![Tiles against tabbed: three code windows in thirds, where long lines wrap, and the same three tabbed, where the focused window gets the width and the others wait as strips at the edges](docs/tabbed.png)

## The bar

![The bar: workspaces on the left; keep-awake, Claude's 5-hour limit, the weather, status icons and the clock on the right](docs/bar.png)

**On the left**, workspace numbers: the focused one is a white pill, and the one visible on the other monitor is a gray pill. Click a number to go there, or scroll over them to move one workspace at a time across all six, wrapping around. The binding mode shows next to them while it isn't the normal one.

While Music or Spotify plays, the track follows as `Artist — Title`, cut at 40 characters. Click it to play or pause, and scroll for the next or previous track. It hides when nothing plays and never opens a player that is closed.

**On the right**, from left to right:

| Item | Shows | Click | Scroll |
|---|---|---|---|
| Meeting | The next Calendar event's start time, from an hour before | Join its video call, or open the [calendar](#calendar-and-todays-events) | |
| Reminder | Time left on the next reminder, plus `+N` for others | List them, to cancel one | |
| Pull requests | How many open pull requests ask for your review, checked with `gh` every 5 minutes. Hidden when none wait, or when `gh` is missing, logged out or offline | List them; Enter opens one in Helium | |
| Claude | The 5-hour usage limit, as `5h 23%` | Open the [Agents card](#agents) | |
| Waiting Claude | A white pill right of Claude's limit, `omv`, while a Claude Code session waits for you, or `? omv` while it asks for approval, plus `+N` for others | Go to that session's terminal, or pick one when several wait | |
| Keep-awake | A crossed-out Zzz, while keep-awake is on | Turn it off | |
| Weather | Condition and temperature, where the Mac is | Open the [weather card](#weather) | |
| Ethernet | A plug, only while a cable is connected | Open the [Ethernet card](#wi-fi-and-ethernet) | |
| Wi-Fi | Connected or not | Open the [Wi-Fi card](#wi-fi-and-ethernet) | |
| Volume | Level | Open the [Sound card](#sound), with either button | Change the volume by 5% |
| Battery | Charge | Open the [Battery card](#battery) | |
| Clock | Date and time, as `Sun Nov 8 12:09` | Open the [calendar](#calendar-and-todays-events) | |

**Clear of the notch:** when the right side gets too full, items give way in this order until it fits: Claude's limit (its logo stays), then the meeting's time (its icon stays), then the weather's temperature (its icon stays), then the Claude logo. Keep-awake, the waiting Claude, the pull request count, the reminder and the status icons always stay, and everything comes back once there's room.

**Claude usage** shows the 5-hour limit: gray under 70%, white from 70%, and a white pill from 90%. The 7-day limit is in the [Agents card](#agents).

- The numbers come from Claude Code's status line, so they only update while Claude Code runs. Usage from elsewhere, such as claude.ai, shows after your next response in Claude Code.
- A window past its reset time shows 0%.
- Once the 5-hour limit reaches 90%, a reminder is set for its reset, "Claude's 5-hour limit has reset", once per reset.
- `install.sh` adds one line to `~/.claude/statusline-wrapper.sh` through `claude-usage.sh`. If that file doesn't exist, the item stays hidden.
- Only the four numbers are stored, in `~/.local/state/omv/claude-usage`.

Option+Shift+Space shows or hides the bar.

## Window list

Option+Space lists every open window with its app and workspace. Type to filter by title, app or workspace number, and press Enter to go there.

<img src="docs/windows.png" alt="The window list, with btop selected" width="720">

## Key list

Option+/ shows every key at once, in a searchable two-column list. Type to filter by description or key, and press Enter (or click) on a row to run that shortcut: the list closes, focus goes back to your window, and the action runs. The list is built from `aerospace.toml` and `init.lua`, so it never goes stale.

![The key list, showing every shortcut in two columns](docs/key-list.png)

## System menu

Option+Escape opens a menu modeled on Omarchy's.

<img src="docs/system-menu.png" alt="The system menu, with Lock selected" width="320">

| Item | Does |
|---|---|
| Lock | Locks the screen |
| Screensaver | Starts the screensaver |
| Sleep | Puts the Mac to sleep |
| Log out, Restart, Shut down | Ask first, with Cancel selected |
| Sound | Opens the [Sound card](#sound) |
| Theme | Opens the [theme picker](#themes) |
| Reload › | Reloads AeroSpace, SketchyBar, Hammerspoon, or all three |

Type to filter, Up and Down to move, Enter or Right to pick, Left or Backspace to go back, and Escape or a click elsewhere to close.

## Themes

Option+Escape, then **Theme**, picks the colours for the cards, the bar, Ghostty and the focused window's outline. **Vantablack** is built in and stays the default. **Get Omarchy's themes** downloads the colours of [Omarchy's](https://github.com/basecamp/omarchy) themes (MIT), such as Tokyo Night, Gruvbox and Nord, and lists them; nothing else is fetched, and only when you pick it.

- **Cards** take the new colours at once. Each gray keeps its place between the theme's background and foreground, so a theme recolors every card without changing its look.
- **The bar** reloads with the theme's colours.
- **Ghostty** takes them in new windows, or after its own config reload, Cmd+Shift+,.
- **The focused window's outline** takes the theme's accent.
- The choice is saved in `~/.local/state/omv/theme`, so it survives reloads and restarts. Neovim and btop keep their own colours.

## Sound

Click the volume item in the bar, or press Option+Shift+V, for the Sound card under it.

- **Header:** the output in use, and a switch that mutes and unmutes.
- **Output:** a volume slider, then every output device, with the one in use highlighted. Click one to switch to it. They're read each time the card opens, so AirPods show up as soon as they connect.
- **Input:** a volume slider for the mic, a live level meter, then every input device.
- Virtual devices, such as the ones Zoom and Teams add, are left out unless they're in use.
- **Keys:** Up and Down move through the devices, Enter picks one, Left and Right change the volume by 5%, M mutes, and Escape or a click elsewhere closes.
- **The level meter** comes from a small Swift helper, `meter.swift`, built the first time into `~/.cache/omv/Meter.app`. It listens only while the card is open, so macOS shows its orange microphone dot until the card closes. The first time, macOS asks to let "omv meter" use the microphone. If you refuse, the meter stays empty and the rest of the card still works.

<img src="docs/sound.png" alt="The Sound card: the speakers in use, AirPods and a monitor listed, and the mic level meter" width="420">

## Wi-Fi and Ethernet

Click the Wi-Fi item, or press Option+Shift+W, for the Wi-Fi card: the network's name, the signal as a percentage and in dBm, the IP address, the router and the channel. **Turn off** (or **Turn on**) switches Wi-Fi, and **Wi-Fi settings** opens System Settings.

The Ethernet item shows only while a cable is connected. Click it, or press Option+Shift+E, for the Ethernet card: the link speed, the IP address, the router, the port and the duplex, and **Network settings**. With more than one cable, it shows the one the Mac's traffic goes out by.

Left and Right move between the buttons, Enter presses one, and Escape or a click elsewhere closes.

<img src="docs/wifi.png" alt="The Wi-Fi card: network name, signal, IP address, router and channel" width="420"> <img src="docs/ethernet.png" alt="The Ethernet card: link speed, IP address, router, port and duplex" width="420">

Since macOS 14, an app needs Location Services to read the Wi-Fi network's name. Hammerspoon asks for it once, for the weather, and without it the card shows `—` for the name.

## Agents

Click Claude's item in the bar for the Agents card: Claude Code's plan, and bars for the session (5-hour) and weekly limits with the time until each resets.

- **>_** continues your last Claude Code session, in the folder it ran in, with `claude --continue`.
- **+** lists the folders you've used Claude Code in, most recent first. Type to filter, and Enter starts a new session there.
- **󰋚** lists your recent sessions, newest first, each named by the title Claude Code gave it, else by its folder, with the folder and its age, such as `omv · 2h ago`. Type to filter, and Enter resumes it with `claude --resume`.
- All three open a Ghostty window on workspace 1. Left and Right move between the buttons, and Enter presses one. Folders that no longer exist are left out of all three.
- **Sessions:** under the limits, a row for each live Claude Code session, with its folder, its state and how long it has been in it, such as `asks · 3 min`. Sessions asking for approval come first, then the ones done, then the ones working. Down and Up move through them, and Enter goes to that session's terminal. With no session running, the card looks as before.
- **Background:** Claude Code's background sessions, the ones started with `claude --bg` or moved there with `/bg`, are listed under BACKGROUND, by name with their folder and state, such as `sila-v1 · asks`. They're read from `claude agents --json`, so they show even with the background service off. Enter opens one in a new Ghostty window on workspace 1, with `claude attach`. Hovering one shows a × at its right; clicking it, or `x` on the selected row, removes it after asking with Cancel selected: it runs `claude stop` and `claude rm`, so it leaves the list but its conversation stays, for `claude --resume`. When Claude's background service isn't running, it's started just for this and stopped after, leaving other sessions running.
- The plan comes from `~/.claude.json`, and only its `organizationType` is read. The folders come from Claude Code's own session files in `~/.claude/projects`.
- `claude` runs through your login shell, by `claude-in.sh`, so it's found on the PATH your shell sets up.

**Waiting sessions.** When Claude Code finishes or asks for approval, a white pill shows the session's folder, as `? omv` when it asks for approval, since that one is blocked until you answer. It sits right next to Claude's logo and 5-hour limit, so the two read as one group, and the limit stays in view. Click it, or press Option+Shift+A, to go to the session's terminal, even in another tab or on another workspace. When several sessions wait, a list opens with the asking ones first, then the one waiting longest, and each row shows its state and how long it has waited. The pill goes when you answer, when a tool runs after your approval, or when the session ends. Working sessions never show in the pill, only in the Agents card.

- **Seen sessions leave the pill.** While Ghostty is in front, the session in the terminal you're looking at is marked seen, so it leaves the pill until its state changes: a session that finishes, then asks, shows again. Ghostty is read every 2 seconds, and only while it's in front.
- **A notification when a session asks.** A session that starts asking for approval in a terminal you're not looking at sends a notification, "omv · needs your approval". Clicking it goes to that session. A session that only finishes never notifies; the pill covers that.

- `install.sh` adds hooks to `~/.claude/settings.json` through `claude-hooks.sh`: `UserPromptSubmit` and `PostToolUse` mark a session as working, `Stop` as done, a `Notification` that asks for you, such as one for approval, as asking, and `SessionEnd` removes it. Other notifications change nothing. Other hooks and settings stay as they are, and `uninstall.sh` removes only these.
- The session's terminal is found by its tty, in Ghostty, iTerm2 or Terminal, through each app's AppleScript, Ghostty first. A terminal app that isn't running is skipped, so it never opens on its own. The first time, macOS asks to let Hammerspoon control that app.
- Only Claude's PID, its tty, the folder name, the state and when the session entered it are saved, in `~/.local/state/omv/claude-sessions`. A session whose Claude has ended is dropped within 30 seconds.
- A session in any other app, such as Zed's terminal, still shows. Since no terminal app has its tty, the app it runs in comes forward instead, found among Claude's parent processes; macOS can't pick the exact window or pane. The drop-down terminal can't be focused.

<img src="docs/agents.png" alt="The Agents card: Claude Code on the Pro plan, with session and weekly limits" width="400">

## Battery

Click the battery item, or press Option+Shift+B, for the Battery card: the charge, whether it's draining, charging or charged, the battery's size in Wh, the time left (or to full), the charge cycles and the power going in or out.

**Battery settings** opens System Settings, where Low Power Mode is. The card doesn't switch it itself: macOS lets only its own apps do that without an admin password.

<img src="docs/battery.png" alt="The Battery card: charge, battery size, time left, charge cycles and power" width="420">

## Weather

The weather item shows the condition and the temperature where the Mac is. Click it, or press Option+Shift+O, for the weather card: the temperature, what it feels like, wind and humidity, and the next three days' highs and lows.

- The location comes from macOS's Location Services. The first time, macOS asks to let Hammerspoon use it. The city's name comes from macOS too.
- The weather comes from [Open-Meteo](https://open-meteo.com), which needs no key. Only the location, rounded to about a kilometre, is sent.
- It's read when Hammerspoon starts, every 30 minutes, when the Mac wakes, and when the card opens.
- When a reading fails, the last one stays. With none yet, the item stays hidden and the card says why.

<img src="docs/weather.png" alt="The weather card: temperature, feels-like, wind, humidity and three days ahead" width="500">

## Calendar and today's events

Click the clock for a calendar card. Weeks start on Monday and show their ISO week number, today is a white square, and the footer shows today's date and week. Left and Right (or ‹ and ›) change month, T goes back to today, and Escape or a click elsewhere closes it.

<img src="docs/calendar.png" alt="The calendar card, with today marked and today's events under it" width="360">

Under the footer are today's events from Calendar.app, so every account added there counts, such as iCloud, Google and Exchange.

- Each event shows its start time, or `all day`. Events already over are dimmed, and the one going on now is white.
- It lists five at most, then `+N more`. When there are more, events already over are left out first. Cancelled events and ones you declined are left out.
- **In the bar,** the meeting item shows the next timed event's start time, as `14:00`, from an hour before it starts. It turns into a white pill 5 minutes before the start and goes away 5 minutes after. All-day events stay out of the bar.
- **Joining:** from 5 minutes before a meeting until it ends, Option+Shift+C or a click on the meeting item opens its Zoom, Google Meet or Teams link. When several meetings can be joined, a card lists them, with the one starting next selected, else the one that started last. With none to join, the calendar card opens. The link comes from the event's URL, else its location, else its notes. Only those links are saved, never the notes themselves.
- Events are read when Hammerspoon starts, every 5 minutes, when the Mac wakes, and when the card opens.
- They're read by a small Swift helper, `agenda.swift`, built the first time into `~/.cache/omv/Agenda.app`. It runs as its own app because macOS asks the app that reads calendars for permission, and Hammerspoon can't ask. The first time, macOS asks to let "omv agenda" access your calendars. If you refuse, the card says so, and you can allow it later in System Settings > Privacy & Security > Calendars.

## Reminders and Pomodoro

Option+Shift+M asks "Remind me…". Type a time, then what to remember, and press Enter.

<img src="docs/reminder.png" alt="The reminder card, with its hint: 25m, 14:30 call, pomo, b break, c cancel" width="480">

| Type | Does |
|---|---|
| `25m check deploy`, `1h30m stand up` | A reminder. Times use `h`, `m` and `s`, and can be combined |
| `14:30 call`, `9:05 tea` | A reminder at that time, today, or tomorrow when it has already passed |
| `r 25m check deploy` | The same, with an optional `r` |
| `pomo`, `pomo write tests` | 25 minutes of focus, optionally named |
| `b`, `break` | A 5-minute break, straight away |
| `c` | Cancels the soonest reminder |

- The bar shows the time left on the soonest reminder, with a target icon during a pomo and a coffee cup during a break.
- When a plain reminder is due, you get a notification and an alert, and the bar item turns into a white pill with the start of its text, plus `+N` when several are due. It stays until you deal with it: click it for a large card with **Dismiss** (Enter), **Snooze 5 minutes** (`s`) and **Snooze 15 minutes** (`l`). Escape closes the card and leaves the reminder due.
- With nothing due, click the bar item to list your reminders, and press Enter on one to cancel it.
- Reminders are saved in `~/.local/state/omv/reminders`, so they survive a Hammerspoon reload, due ones included. One whose time passed while Hammerspoon wasn't running comes back due, marked late on its card (`LATE · WAS 14:05`), with a "Missed reminder" notification. A Pomodoro or break that passed then is dropped, since its moment is gone.

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
- **Quick note (Option+Shift+D):** a card that grows as you type, with Markdown marks shown dimmed. Enter carries a list on, Tab indents it, and Cmd+Enter saves. One line lands as `- 09:05 call the bank` at the end of today's daily note in `~/Documents/vault/work/00 - Daily/`. Several lines land as a block under `### 09:05`. A note that starts with `# Title` becomes its own page in `~/Documents/vault/work/Inbox/`, numbered when the name is taken, and the daily note gets `- 09:05 [[Title]]`. Escape on an empty card closes it. With text, the first Escape asks: a second Escape keeps the draft for next time, Cmd+Backspace throws it away. The draft is kept in `~/.local/state/omv/note-draft` until you save or discard it, so it survives a Hammerspoon reload. Cmd+O lists the notes in both folders, today's first, then newest first. Enter opens one in the same card to read or edit, and Cmd+Enter saves it, unless it changed in Obsidian since you opened it. Escape goes back a step, first asking when edits would be lost. Listing the folders needs Hammerspoon to have access to Documents. The vault is `~/Documents/vault/work` unless `~/.config/omv/vault` names another on its first line, such as `~/Notes/work`; it's read each time, so a change needs no reload. Every note is written to a temporary file beside it, then put in place, so a failed write never leaves a note cut short. A day without a note gets a plain file, not your template, because Obsidian only applies templates to notes it creates itself.

  <img src="docs/note-editor.png" alt="A note open in the editor card: headings bold and their # marks dimmed, the file name and Cmd+Enter save, Cmd+O notes at the bottom" width="480">

  <img src="docs/note-list.png" alt="The note list after Cmd+O: Notes… search, with Production note 1, changed today at 15:31, in Inbox" width="480">

- **Hungry processes (Option+Shift+P):** your 20 busiest processes by CPU, or by memory after Tab, each with the folder it runs in, so a dev server or build an agent left behind is easy to spot. Type to filter, and Enter asks, then quits it. A process still running 3 seconds later is offered Force quit. Only your own processes are listed, never `loginwindow`, `launchd` or Hammerspoon.
- **Drop-down terminal (Option+\`):** Ghostty's quick terminal, over any workspace.
- **Long commands:** in Ghostty, a command that runs longer than 10 seconds sends a notification when it finishes while you're in another window. The first one makes macOS ask to allow notifications from Ghostty.
- **Scripting:** each card opens with `hs -c`: `omvToggleSystemMenu()`, `omvToggleSound()`, `omvToggleWifi()`, `omvToggleEthernet()`, `omvToggleWeather()`, `omvToggleBattery()`, `omvToggleAgents()`, `omvToggleKeyList()`, `omvToggleCalendar()`, `omvJoinMeeting()`, `omvToggleWindows()`, `omvTogglePrs()`, `omvToggleProcesses()`, `omvFocusClaude()`, `omvToggleCapture()`, `omvNewReminder()` and `omvToggleReminders()`.

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
| Option+1-6, or Option and the numpad's 1-6 | Go to that workspace |
| Option+Shift+1-6, or with the numpad | Send the window to that workspace, and stay where you are |
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
| Option+Shift+F | Finder at your home folder | Current workspace, tiled |
| Option+` | Drop-down terminal | Over the current workspace |
| Option+Shift+I | Keep the Mac awake, or stop | |
| Option+Shift+U | Copy Helium's current URL | |
| Option+Shift+S | Capture menu | |
| Option+Shift+M | Set a reminder | |
| Option+Shift+D | Write a note into today's daily note | |
| Option+Shift+C | Join the meeting that is starting | |
| Option+Shift+A | Go to the Claude session waiting for you, or pick one when several wait | |
| Option+Shift+G | Pull requests waiting for your review, or GitHub's review requests page when none wait | |
| Option+Shift+P | Hungry processes: quit the busiest ones | |
| Option+Shift+Space | Show or hide the bar | |
| Option+Shift+W | Wi-Fi card | |
| Option+Shift+E | Ethernet card | |
| Option+Shift+V | Sound card | |
| Option+Shift+O | Weather card | |
| Option+Shift+B | Battery card | |
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

It also lists what macOS doesn't let a script read, to check by hand: Screen Recording for Hammerspoon, Calendar access for "omv agenda", Location Services for Hammerspoon, Microphone access for "omv meter", and Accessibility for SwipeAeroSpace.

### What's inside

Each folder is a GNU Stow package, linked into `$HOME`.

| Package | Links | What it does |
|---|---|---|
| `aerospace` | `~/.config/aerospace` | Tiling, workspaces and window keys |
| `sketchybar` | `~/.config/sketchybar` | The top bar and its plugins |
| `hammerspoon` | `~/.hammerspoon` | App keys and every card: menus, lists, calendar, reminders, capture, sound, network, battery, weather |
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

## Resource use

It won't slow the Mac down or noticeably drain the battery: together, these tools use less than a tenth of one CPU core even while you work, mostly AeroSpace reacting as windows open, close and move.

Memory, measured on a MacBook Pro (M3 Pro, 18 GB) with everything running and no card open, in three runs over two hours. It's each process's footprint, the figure Activity Monitor shows.

| Process | Memory |
|---|---|
| AeroSpace | 37–139 MB |
| borders | 40–45 MB |
| Hammerspoon | 27–36 MB |
| SwipeAeroSpace | 34 MB |
| SketchyBar | 23–24 MB |
| **Total** | **161–278 MB** |

- AeroSpace's memory varied the most: it was 136–139 MB in two runs and 37 MB in one. SketchyBar stayed steady.
- Hammerspoon takes 27 MB when it starts and 36 MB once the cards have been opened.
- borders draws the focus outline at 1x (`hidpi=off`). At 2x it took 149–209 MB for an outline that looks the same.
- The cards are drawn by one WebKit view that is made once and hidden between uses. WebKit runs it in a process of its own, which isn't in the table.
- The helpers run only when needed: "omv agenda" for a moment every 5 minutes, and "omv meter" only while the Sound card is open.

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
