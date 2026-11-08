# Wi-Fi, Ethernet, Sound and Weather cards — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking the bar's Wi-Fi, Ethernet, volume and new weather items (or Option+Shift+W/E/V/O) opens a card in omv's style showing that state and acting on it.

**Architecture:** Each card is a pure Lua renderer (`network.lua`, `sound.lua`, `weather.lua`) with no Hammerspoon dependency, tested with luajit. `init.lua` gathers state with `hs.*` APIs, shows the HTML in the shared webview anchored under the bar, and handles `{ type, id }` messages. A small Swift helper (`meter.swift`, built by `meter.sh` into `~/.cache/omv/Meter.app`) streams the mic level to a file while the Sound card is open.

**Tech Stack:** Hammerspoon Lua, SketchyBar shell plugins, Swift (AVFoundation), Open-Meteo HTTP API, luajit + bash test harness.

**Spec:** `docs/superpowers/specs/2026-11-08-network-sound-weather-design.md`

## Global Constraints

- Card look: black background, `2px solid #8d8d8d` border, muted text `#7a7a7a`, fonts from `card.STYLE`.
- Missing values render as `—` (U+2014), never `nil` or empty.
- Signal %: −90 dBm = 0, −30 dBm = 100, linear, clamped, rounded.
- Units: `°C`, `km/h`. Forecast: the next three days, not today.
- Weather refresh: every 1800 s, on wake, and when the card opens.
- Shortcuts: Option+Shift+W Wi-Fi, Option+Shift+E Ethernet, Option+Shift+V Sound, Option+Shift+O Weather, all through `bindKey`.
- Settings URLs: Wi-Fi `x-apple.systempreferences:com.apple.wifi-settings-extension`, Network `x-apple.systempreferences:com.apple.Network-Settings.extension`.
- Button copy: `󰖪 Turn off` / `󰖩 Turn on`, `󰒓 Wi-Fi settings`, `󰒓 Network settings`.
- The mic helper never outlives the Sound card, and is stopped on Hammerspoon load.
- Tests: no real network, location, audio or clock. Test names: "should <behavior> when <condition>".

## Review Focus

1. Wi-Fi off or Location refused (SSID nil, RSSI 0) → card shows `OFF` / `—`, never errors. Test in Task 1.
2. Open-Meteo returns a payload missing `daily` or with fewer than 4 days → card shows what it has, no Lua error. Test in Task 3.
3. A device that can't take a volume (volume `nil`) → slider disabled, `—`. Test in Task 2.
4. Device names with `<`, `&`, `'` (e.g. "Mehmet's AirPods") → escaped in HTML and in `data-id`. Test in Task 2.
5. Ethernet adapter present but unplugged (`status: inactive`) → bar item hidden, card not shown. Test in Task 4.

## File Structure

| File | Responsibility |
|---|---|
| `hammerspoon/.hammerspoon/panel.lua` *(create)* | Shared Battery-layout CSS and header/grid/button HTML helpers, used by network and sound |
| `hammerspoon/.hammerspoon/network.lua` *(create)* | Wi-Fi and Ethernet card models and HTML; parsing `ifconfig` media and `networksetup` ports |
| `hammerspoon/.hammerspoon/sound.lua` *(create)* | Sound card HTML and device icons (moved from `menu.lua`) |
| `hammerspoon/.hammerspoon/weather.lua` *(create)* | Open-Meteo URL, reading from decoded JSON, WMO icons, bar label, card HTML |
| `hammerspoon/.hammerspoon/meter.swift`, `meter.sh` *(create)* | Mic level helper and its build/start/stop script |
| `hammerspoon/.hammerspoon/menu.lua` *(modify)* | Drop the Sound list; `sound` row becomes an action |
| `hammerspoon/.hammerspoon/init.lua` *(modify)* | Wiring, data gathering, shortcuts, `omvToggle*` globals |
| `sketchybar/.config/sketchybar/sketchybarrc`, `plugins/wifi.sh`, `plugins/volume.sh`, `plugins/ethernet.sh` *(create)*, `plugins/bar_fit.sh` | Bar items |
| `doctor.sh`, `README.md` | Permissions and docs |

---

### Task 1: Network cards (`panel.lua`, `network.lua`)

**Files:** Create `panel.lua`, `network.lua`, `tests/network_test.lua`, `tests/network_test.sh`.

**Interfaces — Produces:**
- `panel.STYLE: string` — CSS for `.head .icon .title .sub .big .track .grid .sec .btns .btn .btn.selected`.
- `panel.head(icon, title, sub, big: string) -> string`, `panel.track(percent: number) -> string`, `panel.grid(pairs: {{label, value}}) -> string`, `panel.buttons(buttons: {{id, icon, label}}) -> string`.
- `panel.SCRIPT: string` — Left/Right move `.btn.selected`, Enter/click send `choose` with `data-id`, Escape sends `close`.
- `network.signalPercent(rssi: number|nil) -> number` (0 for nil/0).
- `network.wifiModel(info) -> model`, info = `{ power: bool, ssid?, rssi?, ip?, router?, channel?: number, band?: string }`.
- `network.ethernetModel(info) -> model`, info = `{ port, ip?, router?, mbps?: number, duplex? }`.
- `network.html(model) -> string`; model = `{ icon, title, sub, big, percent, grid, buttons }`.
- `network.parseMedia(ifconfigText) -> { active: bool, mbps?: number, duplex?: "full"|"half" }`.
- `network.wiredPorts(listallhardwareportsText) -> { string }` — device names whose port is not Wi-Fi, Bluetooth PAN or Thunderbolt Bridge.
- `network.speedLabel(mbps) -> string` — `1000 → "1 Gb/s"`, `2500 → "2.5 Gb/s"`, `100 → "100 Mb/s"`, nil → `—`.
- Message ids: `wifi.power`, `wifi.settings`, `network.settings`.

- [ ] **Step 1: Write failing tests** in `tests/network_test.lua`:
  - should give 0% when RSSI is −90 or weaker; 100% at −30 or stronger; 50% at −60; 0% when RSSI is nil.
  - should show the SSID uppercased as status when connected (`HOME-5G`).
  - should show `NOT CONNECTED` and an empty bar when power is on and SSID is nil.
  - should show `OFF` and offer `󰖩 Turn on` when power is off.
  - should show `—` for IP, router, signal and channel when they are missing.
  - should show channel as `36 (5GHz)`.
  - should offer `Wi-Fi settings` on the Wi-Fi card and `Network settings` on the Ethernet card.
  - should read `1000baseT <full-duplex>` as 1000 Mb/s full; `status: inactive` as not active.
  - should label 1000 as `1 Gb/s`, 2500 as `2.5 Gb/s`, 100 as `100 Mb/s`.
  - should list `en5` from a `Hardware Port: USB 10/100/1000 LAN` block and skip Wi-Fi, Bluetooth PAN and Thunderbolt Bridge.
  - should escape an SSID containing `<b>&`.
  `tests/network_test.sh` mirrors `calendar_test.sh`.
- [ ] **Step 2:** `tests/network_test.sh` → FAIL (`module 'network' not found`).
- [ ] **Step 3:** Implement `panel.lua` and `network.lua`.
- [ ] **Step 4:** `tests/network_test.sh` → all ok.

### Task 2: Sound card (`sound.lua`, `menu.lua`)

**Files:** Create `sound.lua`, `tests/sound_test.lua`, `tests/sound_test.sh`. Modify `menu.lua`, `tests/menu_test.lua`.

**Interfaces — Produces:**
- `sound.icon(device) -> string` (moved from `menu.lua`'s `soundIcon`, same rules).
- `sound.html(state) -> string`; state = `{ outputs, inputs: {{uid, name, transport, current}}, outputVolume?: number, inputVolume?: number, muted: bool }`.
- `sound.height(state) -> number` — card height for its rows.
- Messages sent by the page: `output` / `input` (id = uid), `volume` / `inputVolume` (id = "0".."100"), `mute`, `close`.
- Page function `window.omvLevel(level: number)` sets the meter width (0–1).
- Keys in page: Up/Down through device rows (outputs then inputs), Enter picks, Left/Right send `volume` ±5 clamped 0–100, `m` sends `mute`.
- `menu.opens("sound")` now false; `menu.sound` removed; system row `sound` loses `submenu`.

- [ ] **Step 1: Write failing tests**:
  - should show the current output's name uppercased as the status line.
  - should highlight only the current output row and the current input row.
  - should hide virtual outputs unless current.
  - should show `NN%` for output and input volume, rounding 42.6 to `43%`.
  - should show `—` and a disabled slider when output volume is nil.
  - should show the mute switch off when muted.
  - should escape `Mehmet's <AirPods>` in labels and `data-id`.
  - should list no Sources section.
  - should use the headphones icon for AirPods (existing icon tests move from `menu_test.lua`).
  - menu: should not treat Sound as a screen to open; should list Sound without `›`.
- [ ] **Step 2:** `tests/sound_test.sh`, `tests/menu_test.sh` → FAIL.
- [ ] **Step 3:** Implement `sound.lua`; trim `menu.lua`.
- [ ] **Step 4:** Both → ok.

### Task 3: Weather (`weather.lua`)

**Files:** Create `weather.lua`, `tests/weather_test.lua`, `tests/weather_test.sh`.

**Interfaces — Produces:**
- `weather.url(lat, lon: number) -> string` — `https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=4`.
- `weather.reading(data: table) -> reading|nil` — data is the decoded JSON; reading = `{ temp, feels, wind, humidity: number, icon: string, days: {{ name, icon, high, low }} }` (up to 3, from `daily` index 2..4, name = uppercase weekday from the `YYYY-MM-DD` date). nil when `current` is missing.
- `weather.icon(code: number, isDay: bool) -> string` — clear `󰖙`/`󰖔`, partly cloudy (1–2) `󰖕`/`󰼱`, cloudy (3) `󰖐`, fog (45, 48) `󰖑`, drizzle (51–57) `󰖗`, rain (61–67, 80–82) `󰖖`, snow (71–77, 85–86) `󰖘`, thunder (95–99) `󰖓`; unknown → cloudy.
- `weather.barLabel(reading) -> string` — rounded temp with `°`, e.g. `5°`, `-3°`.
- `weather.html(reading|nil, city|nil, problem|nil) -> string`; `weather.WIDTH = 500`, `weather.height(reading) -> number`.

- [ ] **Step 1: Write failing tests** with a fixture table shaped like Open-Meteo's response:
  - should round 4.6 °C to `5` and show `°C`.
  - should show feels-like `1°C`, wind `20 km/h`, humidity `43%`.
  - should list the next three days by weekday, not today (`2026-11-09` → `MONDAY`).
  - should show highs and lows rounded (`8°` `-3°`).
  - should use the night icon for clear sky when `is_day` is 0.
  - should map code 73 to snow and an unknown code to cloudy.
  - should list only the days it has when `daily` has two entries; none when `daily` is missing.
  - should return nil when `current` is missing.
  - should show the city uppercased; `—` when city is nil.
  - should show the problem text when there is no reading.
  - should build a URL with the latitude, longitude and `timezone=auto`.
- [ ] **Step 2:** `tests/weather_test.sh` → FAIL.
- [ ] **Step 3:** Implement `weather.lua`.
- [ ] **Step 4:** → ok.

### Task 4: Bar items (`sketchybarrc`, plugins, `bar_fit.sh`)

**Files:** Create `plugins/ethernet.sh`, `tests/ethernet_test.sh`. Modify `sketchybarrc`, `plugins/wifi.sh`, `plugins/volume.sh`, `plugins/bar_fit.sh`, `tests/volume_test.sh`, `tests/bar_fit_test.sh`; add `tests/wifi_test.sh`.

**Interfaces — Produces:** bar items `ethernet` (plugin), `weather` (set by Hammerspoon: `drawing`, `icon`, `label`); click scripts `hs -c 'omvToggleWifi()'`, `omvToggleEthernet()`, `omvToggleWeather()`; volume clicks run `hs -c 'omvToggleSound()'`.

- `ethernet.sh`: lists ports with `networksetup -listallhardwareports`, skips Wi-Fi / Bluetooth PAN / Thunderbolt Bridge, draws `󰈀` when any port has `ipconfig getifaddr <dev>` output, else `drawing=off`.
- Order in `sketchybarrc`: clock, battery, volume, wifi, ethernet, weather, claude_usage, … (each added after the previous one sits to its left).
- `bar_fit.sh` order: Claude's numbers, meeting time, **weather temperature** (`label.drawing=off`, icon width 26), Claude logo. The restore line also sets `--set weather label.drawing=on`. `weather` and `ethernet` join the leftmost loop.

- [ ] **Step 1: Write failing tests**:
  - volume: should open the Sound card on a left click; should open it on a right click; should not mute on a click.
  - wifi: should open the Wi-Fi card on a click (`SENDER=mouse.clicked` → `hs -c omvToggleWifi()`).
  - ethernet: should show the item when a LAN port has an IP; should hide it when the port has no IP (unplugged); should hide it when only Wi-Fi exists.
  - bar_fit: should hide the weather temperature after the meeting time; should keep the weather temperature when shrinking the meeting is enough; should restore weather's label before measuring.
- [ ] **Step 2:** Run those test files → FAIL.
- [ ] **Step 3:** Implement. Wi-Fi click moves from `click_script` into `wifi.sh` (subscribe `mouse.clicked`) so it is testable.
- [ ] **Step 4:** → ok.

### Task 5: Mic meter helper (`meter.swift`, `meter.sh`)

**Files:** Create `meter.swift`, `meter.sh`, `tests/meter_test.sh`.

**Interfaces — Produces:** `meter.sh start <file>` builds `~/.cache/omv/Meter.app` (bundle id `dev.omv.meter`, name `omv meter`, `NSMicrophoneUsageDescription`, ad-hoc signed; same rebuild rule as `agenda.sh`) and launches it with `open -g -j`, returning at once. The helper writes one line to `<file>` about every 0.1 s: a level `0.000`–`1.000`, or `denied`. `meter.sh stop` runs `pkill -x meter`. The helper also exits by itself after 3 s if `<file>`'s parent `…/meter.alive` was not touched (watchdog against a crashed Hammerspoon).

- [ ] **Step 1: Write failing tests** (stub `swiftc`, `open`, `codesign`, `pkill` as `agenda_test.sh` does): should build the helper the first time; should not rebuild when the helper is newer than the source; should launch it hidden with the level file; should stop it with `pkill -x meter`; should fail with "Couldn't build the meter helper" when swiftc fails.
- [ ] **Step 2:** → FAIL. **Step 3:** Implement. **Step 4:** → ok. Then build the real helper once with `swiftc` to prove it compiles.

### Task 6: Wiring in `init.lua`, shortcuts

**Files:** Modify `init.lua`.

- `anchored(width, height) -> rect` (extract from `showCalendar`): right-aligned 10 pt from the edge, `y + 40`.
- **Wi-Fi:** state from `hs.wifi.interfaceDetails()` (`ssid`, `rssi`, `power`, `wlanChannel`), IP from `hs.network.addresses(interface)` (first IPv4), router from `hs.network.configuration.open():contents("State:/Network/Global/IPv4")`. `wifi.power` → `hs.wifi.setPower(not power)` then redraw. Settings buttons → `open` URL, close.
- **Ethernet:** `networksetup -listallhardwareports` + `ifconfig <dev>` via `hs.execute`; use the default-route device when wired, else first active. None active → alert `No cable connected`.
- **Sound:** state from `hs.audiodevice`; handlers call `setDefaultOutputDevice`, `setDefaultInputDevice`, `setOutputVolume`, `setInputVolume`, `setOutputMuted`, then redraw and `sketchybar --trigger volume_change`. Meter: on open, touch alive file and `meter.sh start`; a 0.1 s timer reads the level file, touches alive, and calls `view:evaluateJavaScript("omvLevel(x)")`. `keepOnBlur` while no level/denied line has been read yet. On close (any card change or `closePanel`) stop the timer and run `meter.sh stop`. Run `meter.sh stop` once at load. System menu's `sound` action opens the Sound card.
- **Weather:** `hs.location.start()`; `hs.location.get()`; city from `hs.location.geocoder.lookupLocation`; `hs.http.asyncGet(weather.url(...))`, `hs.json.decode`. Keep last good reading; problems: `Allow Location for Hammerspoon in System Settings` when `hs.location.servicesEnabled()`/authorization fails, `No connection` on HTTP error. Bar: `sketchybar --set weather drawing=on icon=<icon> label=<barLabel> --trigger bar_fit`, only on change. Refresh timer 1800 s, wake watcher, on open.
- `bindKey(SUPER_SHIFT, "w"|"e"|"v"|"o", ...)`; globals `omvToggleWifi`, `omvToggleEthernet`, `omvToggleSound`, `omvToggleWeather` via `later`.

- [ ] **Step 1:** `tests/run.sh` (config contract checks keys stay unique) → ok.
- [ ] **Step 2:** `hs -c 'omvToggleWifi()'` etc. with Hammerspoon reloaded; manual check of each card (needs the user's machine and permissions).

### Task 7: doctor and README

- `doctor.sh` manual list adds: Location for Hammerspoon (`System Settings > Privacy & Security > Location Services`), Microphone for "omv meter" (`… > Microphone`). Update `tests/doctor_test.sh` expectation if it pins that text.
- README: bar table (Wi-Fi, Ethernet, Volume, Weather rows), notch order, new sections "Wi-Fi and Ethernet", "Sound" (replaces the Sound list paragraph), "Weather", key table rows, Scripting line, Turkish clash list if Option+Shift+W/E/V/O swallow characters.
- [ ] `tests/run.sh` → all ok.
