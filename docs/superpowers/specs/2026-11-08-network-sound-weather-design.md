# Wi-Fi, Ethernet, Sound and Weather cards — design

Date: 2026-11-08

## Intent

Clicking a status icon in the bar today either does one small thing (mute) or throws
you into System Settings (Wi-Fi). The user wants each icon to open a card, in the same
black-and-gray look as every other omv card, that shows the state at a glance and lets
them act on it without leaving the keyboard-driven desktop. Weather is new: it gets its
own bar item and card.

The reference designs are three screenshots the user shared (Battery, Audio, Weather),
reproduced in words below. The Battery screenshot is a **layout reference** for the
Wi-Fi and Ethernet cards only; no battery card is built.

## Goals

1. Click the Wi-Fi icon → Wi-Fi card.
2. Click the Ethernet icon (new, shown only while a cable is connected) → Ethernet card.
3. Click the volume icon → Sound card, replacing today's click-to-mute and the Sound
   list in the system menu.
4. New weather item in the bar → Weather card on click. Weather follows the Mac's
   location.

## Non-goals

- A battery card. Clicking the battery icon keeps toggling the percentage.
- A list of nearby Wi-Fi networks or joining one from the card.
- Per-app volume, or any list of apps playing sound ("Sources" in the Audio screenshot
  was dropped: macOS can't change one app's volume without a third-party audio driver,
  and a list without control wasn't worth it).
- Settings for units or a fixed city. °C and km/h, location from the Mac.

## Anti-goals

- A card that looks different from the rest of omv. Same fonts, black background,
  `#8d8d8d` 2px border, `#7a7a7a` muted text, white for the selected/active state.
- Anything that leaves the mic open after the Sound card closes.
- A bar that collides with the notch because of the new items.

## Shared behavior (all four cards)

- Drawn by Hammerspoon in the one shared webview (`showPanel` in `init.lua`), like the
  calendar. Escape or a click elsewhere closes; clicking the same bar icon again toggles
  it closed.
- Right-aligned just under the bar (like `showCalendar`, `y = screen.y + 40`), not
  centered.
- Each card's HTML comes from a pure Lua module with no Hammerspoon dependency, so it
  can be tested with luajit like `calendar.lua` and `menu.lua`. `init.lua` gathers the
  data and handles messages.
- Opened from the bar with `hs -c 'omvToggle…()'`, wrapped in `later()` like the others,
  and listed in the README's Scripting line.
- Values that can be missing render as `—`, never `nil` or an empty string.
- **Shortcuts** (the user asked for them; the letters are the designer's call), bound in
  `init.lua` with `bindKey`, so they show in the key list and can run from it. Each
  toggles its card, opened in the same spot under the bar:

  | Keys | Card |
  |---|---|
  | Option+Shift+W | Wi-Fi |
  | Option+Shift+E | Ethernet; with no cable connected, an alert says so instead |
  | Option+Shift+V | Sound (V for volume) |
  | Option+Shift+O | Weather (O for outside) |

  None is bound in AeroSpace or Ghostty today. Add them to the README key table and to
  the Turkish-QWERTY-PC clashes list if they swallow a character there.
- **Keys inside the Wi-Fi, Ethernet and Weather cards:** Left/Right move between the
  action buttons, Enter presses the selected one, Escape closes. The Weather card has no
  buttons, so only Escape.

## Wi-Fi card

Battery layout, top to bottom:

- **Header:** Wi-Fi icon, title `Wi-Fi`, status line under it in muted uppercase with
  letter spacing: the network name (SSID), or `NOT CONNECTED`, or `OFF` when Wi-Fi power
  is off. Big number on the right: signal as a percentage.
- **Bar:** signal percentage, white on `#2a2a2a`. Percentage from RSSI:
  −90 dBm = 0%, −30 dBm = 100%, linear, clamped.
- **Stats grid**, two columns of label/value pairs:
  `IP address` / `Signal` (dBm), `Router` / `Channel` (number and band, e.g. `36 (5GHz)`).
- **ACTIONS** section, two buttons side by side:
  - `󰖪 Turn off` (or `󰖩 Turn on` when off): toggles Wi-Fi power.
  - `󰒓 Wi-Fi settings`: opens `x-apple.systempreferences:com.apple.wifi-settings-extension`
    and closes the card.
- Disconnected: `NOT CONNECTED`, empty bar, `—` in the grid.

## Ethernet card and bar item

- **Bar item:** new `ethernet` item next to Wi-Fi, icon `󰈀`, hidden unless a wired
  interface has an active link and an IP. Checked on the same 60s timer and `system_woke`
  as Wi-Fi.
- **Card**, Battery layout:
  - Header: icon, title `Ethernet`, status `CONNECTED`; big number is the link speed
    (`1 Gb/s`, `100 Mb/s`, `2.5 Gb/s`, `10 Gb/s`), with the unit in smaller muted text.
  - Bar: full when connected.
  - Grid: `IP address` / `Port` (BSD name, e.g. `en5`), `Router` / `Duplex` (`full` or
    `half`).
  - ACTIONS: one button, `󰒓 Network settings`, opening the Network pane of System
    Settings, then closing the card.

A Mac with several wired interfaces up: the card shows the one carrying the default
route, falling back to the first active one. (Builder's call how to detect; `route -n
get default` and `ifconfig` media lines are the obvious sources.)

## Sound card

Replaces the current Sound menu. Matches the Audio screenshot minus Sources.

- **Opening:** left- or right-click on the volume icon opens it. Scrolling over the icon
  still changes the volume by 5%. The system menu's `Sound ›` row opens this card
  instead of the old list; `omvToggleSound()` keeps its name and now opens this card.
  The old list screen in `menu.lua` goes away. *(Designer's call:)* opened from the
  system menu, the card replaces the menu and moves to its usual spot under the bar; it
  is not pushed on `menuStack`, so there is no way back to the menu — Escape closes.
- **Header:** speaker icon, title `Audio`, status line = current output device name in
  muted uppercase. A switch on the right shows and toggles mute (on = sound on).
- **OUTPUT** section: label left, level `NN%` right; a slider for output volume; then
  the output devices, one row each with an icon (reuse `menu.lua`'s `soundIcon` rules:
  headphones, display, AirPlay, speaker). The current device's row is highlighted
  (`#2a2a2a`-ish background, bold white text, as in the screenshot). Clicking a row or
  Enter on it makes it the default output. Virtual devices are hidden unless in use
  (existing rule).
- **INPUT** section: label and `NN%`; a slider for the input volume of the current input
  device; a **live level meter** under it (thin bar, white fill on dark track); then the
  input devices with a mic icon, current one highlighted, click/Enter to switch.
- **Keys:** Up/Down move a selection through all device rows (outputs then inputs),
  Enter picks, Left/Right change output volume by 5%, `m` toggles mute, Escape closes.
- **Live updates:** switching device, volume or mute redraws the card from fresh state.
  Changing the output volume or mute also updates the bar's volume icon (trigger
  SketchyBar's `volume_change` or set the icon directly).
- A device that can't take a volume (some HDMI outputs) shows its slider disabled and
  `—` instead of a percentage.

### Mic level meter

- A small Swift helper reads the default input's level (e.g. AVAudioEngine input tap,
  RMS → 0–1, smoothed) while the Sound card is open, and stops when it closes. It must
  never outlive the card: on close, on switching to another card, on Hammerspoon reload.
- macOS will show its orange mic indicator while the card is open. This is accepted.
- It needs microphone permission. Follow the `agenda.sh` pattern: build into an app
  bundle in `~/.cache/omv/` with an `NSMicrophoneUsageDescription`, ad-hoc signed, so
  macOS asks for "omv" by name. Unlike agenda it streams, so it needs a way to hand
  levels to Hammerspoon about 10–20 times a second (builder's call: a file Hammerspoon
  polls, a FIFO, a local socket, or distributed notifications).
- *(Designer's call:)* the permission prompt takes focus, which would close the card and
  stop the helper mid-prompt. So the Sound card opens with `keepOnBlur` while the helper
  has not yet reported a permission answer, and switches to closing on blur once it has.
- Permission refused, or the helper fails to build: the meter stays empty; everything
  else in the card works.
- `doctor.sh` lists Microphone access for the helper among the things to check by hand,
  next to Calendar access.

## Weather bar item and card

- **Bar item:** `weather`, on the right, directly left of Wi-Fi/Ethernet: it is added
  in `sketchybarrc` right after them, so Claude, keep-awake, reminder and meeting each
  move one place left *(designer's call)*. `bar_fit.sh` includes it when finding the
  leftmost item. Condition icon plus
  temperature, e.g. `󰖙 5°`. Set by Hammerspoon (like `meeting`), not by a plugin
  script. Clicking it runs `omvToggleWeather()`.
- **Notch:** add it to `bar_fit.sh`. It gives way after the meeting's time and before
  the Claude logo: its temperature hides first, its icon stays. Update the order comment
  in `bar_fit.sh` and the README.
- **Card** (matches the Weather screenshot), wider than tall, right-aligned under the
  bar:
  - Left: large condition icon, large temperature, small `°C`.
  - Right: map-pin icon and city in muted uppercase; then three columns `FEELS`,
    `WIND`, `HUMID` with values `1°C`, `20 km/h`, `43%`.
  - Divider, then three forecast columns for the next three days (not today): icon,
    weekday in muted uppercase (`MONDAY`), high in white, low in muted gray.
  - Day/night: the current icon uses the night variant after sunset.
- **Location:** `hs.location` (macOS Location Services). macOS asks the first time to let
  Hammerspoon use the location. City name from macOS's reverse geocoder
  (`hs.location.geocoder`).
- **Data:** Open-Meteo forecast API, no key: current temperature, apparent temperature,
  wind speed (km/h), relative humidity, weather code, is_day; daily weather code, max,
  min; `timezone=auto`. Fetched with `hs.http.asyncGet`.
- **Refresh:** every 30 minutes, on wake, and when the card opens. The card shows the
  last reading at once and redraws if a newer one arrives while it's open.
- **Failure:** keep and show the last good reading. With no reading ever: the bar item is
  hidden, and the card says why (`Allow Location for Hammerspoon in System Settings`,
  `No connection`, …). The last reading is not persisted across reloads (builder's
  call if it's cheap to persist).
- WMO weather codes map to a small set of Nerd Font icons (clear, partly cloudy, cloudy,
  fog, drizzle, rain, snow, thunderstorm), with day/night variants for clear and partly
  cloudy. That mapping lives in the pure Lua module and is tested.

## Permission note

Since macOS 14, reading the Wi-Fi network name (SSID) also requires Location Services
for the app asking. So the one Location permission for Hammerspoon covers both the Wi-Fi
card's network name and the weather. Without it the Wi-Fi card shows `—` for the name
but still shows signal, IP and router. `doctor.sh` lists Location for Hammerspoon among
the things to check by hand.

## Bar changes summary

| Item | Change |
|---|---|
| `wifi` | Click opens the Wi-Fi card instead of System Settings |
| `ethernet` | New, hidden unless a cable is connected |
| `volume` | Left/right click open the Sound card; scroll unchanged |
| `weather` | New, set by Hammerspoon |
| `bar_fit` | Weather temperature joins the give-way order |

## Testing

Follow the repo's existing pattern: pure Lua modules tested with luajit through
`tests/*_test.sh` / `*_test.lua` using `tests/check.lua`; shell plugins tested with stubs
and a temporary `HOME`; no real network, location, audio or clock. The test plan is
proposed and approved before implementation (user's rule).

## Docs

README: update the bar table, the Sound section (now a card, with a screenshot later),
add Wi-Fi/Ethernet and Weather sections, the Scripting line, the notch give-way order,
and the permissions (Location for Hammerspoon, Microphone for the meter helper).

## Left to the builder

- File and module names (suggested: `network.lua`, `sound.lua`, `weather.lua` next to
  `calendar.lua`; the mic helper as `meter.swift` + `meter.sh`).
- Exact glyphs, spacing and card sizes, as long as they match the screenshots' feel.
- How data is read (hs.wifi / hs.network / shell tools), and how the meter streams.
- Whether the Wi-Fi and Ethernet cards share one renderer (likely: same layout).
