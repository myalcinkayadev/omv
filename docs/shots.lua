-- The README's card screenshots and the sample data each is drawn from, so no real network,
-- place, event, path or clipboard ever reaches an image. docs/shoot.lua takes them in
-- Hammerspoon; tests/shots_test.lua checks the list against the README.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.
--
-- Each shot is { file, kind, ... }:
--   card  { html, width, height } drawn as a card, or { html, width, crop } cut to the
--         page's element crop, for cards that size themselves; script runs before the capture
--   live  { feature, call }: the real card, for the key list, which reads init.lua's keys
--   osd   { icon, level }: the volume or brightness pop-up

local agenda = require("agenda")
local agents = require("agents")
local battery = require("battery")
local bluetooth = require("bluetooth")
local calendar = require("calendar")
local capture = require("capture")
local card = require("card")
local clipboard = require("clipboard")
local devlayout = require("devlayout")
local disk = require("disk")
local menu = require("menu")
local network = require("network")
local notepad = require("notepad")
local osd = require("osd")
local palette = require("palette")
local panel = require("panel")
local pomo = require("pomo")
local procs = require("procs")
local prs = require("prs")
local quicknote = require("quicknote")
local reminders = require("reminders")
local sound = require("sound")
local tailscale = require("tailscale")
local theme = require("theme")
local weather = require("weather")

local shots = {}

-- The same sizes the features use.
local MENU_WIDTH, LIST_WIDTH, REMINDER_WIDTH, NOTE_WIDTH = 320, 720, 480, 640
local MINUTE, HOUR, DAY = 60, 3600, 86400

local function menuHeight(screen)
  return 28 + 46 + math.max(1, #screen.rows) * 44 + 4
end

-- A compact list, with a line for each group's header.
local function listHeight(screen)
  local lines, last = #screen.rows, nil
  for _, row in ipairs(screen.rows) do
    if row.group and row.group ~= last then lines = lines + 1 end
    last = row.group
  end
  return 28 + 46 + math.max(1, lines) * 30 + 8
end

local function menuShot(file, width, screen)
  return { file = file, kind = "card", width = width, height = menuHeight(screen), html = card.html(screen) }
end

local function listShot(file, width, screen)
  screen.compact = true
  return { file = file, kind = "card", width = width, height = listHeight(screen), html = card.html(screen) }
end

local function bigShot(file, screen)
  return { file = file, kind = "card", big = true, crop = ".card", html = card.big(screen) }
end

local function weatherShot()
  local reading = weather.reading({
    current = { temperature_2m = 4.6, apparent_temperature = 0.8, relative_humidity_2m = 43, wind_speed_10m = 19.7, weather_code = 0, is_day = 0 },
    daily = { time = { "2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11" }, weather_code = { 3, 2, 73, 45 },
      temperature_2m_max = { 7, 8.2, 4.6, 11.4 }, temperature_2m_min = { -2, -3.4, -1, 0.3 } },
  })
  return { file = "weather.png", kind = "card", width = weather.WIDTH, height = weather.height(reading), html = weather.html(reading, "Ankara") }
end

local function networkShots()
  local wifi = { power = true, ssid = "Home-5G", rssi = -52, ip = "192.168.1.24", router = "192.168.1.1", channel = 36, band = "5GHz" }
  local wired = { port = "en5", ip = "192.168.1.31", router = "192.168.1.1", mbps = 1000, duplex = "full" }
  local function shot(file, model)
    return { file = file, kind = "card", width = network.WIDTH, height = network.HEIGHT, html = network.html(model) }
  end
  return {
    shot("wifi.png", network.wifiModel(wifi, { down = 412, up = 48 })),
    shot("wifi-speedtest.png", network.wifiModel(wifi, { running = true, down = 318 })),
    shot("ethernet.png", network.ethernetModel(wired, { down = 754, up = 55 })),
  }
end

local function batteryShot()
  local status = battery.parseBatt("Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t78%; discharging; 6:05 remaining present: true\n")
  local health = battery.parseSmartBattery('"Amperage" = 18446744073709551232\n"AppleRawCurrentCapacity" = 3773\n'
    .. '"CycleCount" = 188\n"AppleRawMaxCapacity" = 5092\n"Voltage" = 12131\n')
  return { file = "battery.png", kind = "card", width = battery.WIDTH, height = battery.HEIGHT, html = battery.html(battery.model(status, health)) }
end

local function soundShot()
  local state = {
    outputs = {
      { uid = "spk", name = "MacBook Pro Speakers", transport = "Built-in", current = true },
      { uid = "air", name = "AirPods Pro", transport = "Bluetooth", current = false },
      { uid = "dell", name = "DELL G2724D", transport = "DisplayPort", current = false },
    },
    inputs = {
      { uid = "mic", name = "MacBook Pro Microphone", transport = "Built-in", current = true },
      { uid = "air-in", name = "AirPods Pro", transport = "Bluetooth", current = false },
    },
    outputVolume = 56, inputVolume = 80, muted = false,
  }
  return { file = "sound.png", kind = "card", width = sound.WIDTH, height = sound.height(state), html = sound.html(state), script = "omvLevel(0.46)" }
end

local function agentsShot(now, logo)
  local usage = agents.parseUsage(string.format("34 %d 41.0 %d\n", now + 2 * HOUR + 14 * MINUTE, now + 3 * DAY + 5 * HOUR), now)
  local sessions = {
    { id = "/dev/ttys004", label = "api", hint = "asks · 1 min", state = "asks" },
    { id = "/dev/ttys002", label = "omv", hint = "working · 3 min", state = "working" },
  }
  local background = agents.background({
    { id = "cd3bc75e", cwd = "/Users/me/work/game", kind = "background", name = "doodle-shooter", state = "done", startedAt = 2 },
    { id = "edbc65df", cwd = "/Users/me/work/site", kind = "background", name = "fix-build", state = "blocked", startedAt = 1 },
  })
  local model = { plan = "Pro", usage = usage, logo = logo, sessions = sessions, background = background }
  return { file = "agents.png", kind = "card", width = agents.WIDTH, height = agents.height(#sessions, #background), html = agents.html(model) }
end

local function diskShot(now)
  local status = disk.parseStatus({ disks = { { mount = "/", used = 302768385864, total = 494384795648, purgeable = 9423282360 } } })
  local model = disk.model({ installed = true, space = status,
    previews = { clean = { size = "12.70 GB", at = now - 10 * MINUTE }, purge = { size = "4.12 GB", at = now - 3 * HOUR - MINUTE } } }, now)
  return { file = "disk.png", kind = "card", width = 420, height = disk.height(model), html = panel.html(model) }
end

local function calendarShot(now)
  local t = os.date("*t", now)
  local today = { year = t.year, month = t.month, day = t.day }
  local function at(hour, minute) return os.time({ year = t.year, month = t.month, day = t.day, hour = hour, min = minute or 0 }) end
  local function line(start, finish, title) return start .. "\t" .. finish .. "\t0\t" .. title .. "\n" end
  local day = agenda.decode(line(at(9), at(9, 30), "Standup") .. line(at(11), at(12), "Design review")
    .. line(at(14), at(14, 45), "1:1 with Ada") .. line(at(16, 30), at(17), "Release planning"))
  local clock = at(10, 20)
  local model = calendar.month(today.year, today.month, today)
  return { file = "calendar.png", kind = "card", width = 360, height = calendar.height(day, clock), html = calendar.html(model, today, day, clock) }
end

local function reminderShots(now)
  local input = { prompt = "Remind me…", rows = {}, input = true, hint = "25m · 14:30 call · pomo · b break · c cancel" }
  local list = { prompt = "Cancel a reminder…", rows = {
    { id = "1", icon = "󰔛", label = "Stretch", hint = reminders.leftIn(12 * MINUTE) },
    { id = "2", icon = "󰔛", label = "Call the dentist", hint = reminders.leftIn(95 * MINUTE) },
  } }
  return {
    { file = "reminder.png", kind = "card", width = REMINDER_WIDTH, height = 28 + 46 + 44 + 4, html = card.html(input) },
    menuShot("reminder-list.png", REMINDER_WIDTH, list),
    bigShot("reminder-due.png", reminders.dueScreen({ due = now - MINUTE, text = "Call the dentist" })),
    bigShot("pomo-done.png", pomo.doneScreen({ task = "write tests", count = 2 })),
    bigShot("pomo-break.png", pomo.breakScreen({ ends = now + 4 * MINUTE + 12, seconds = 5 * MINUTE, count = 2, tip = 3 })),
    bigShot("pomo-over.png", pomo.overScreen({ task = "write tests", count = 2 })),
  }
end

local function paletteShot()
  local windows = "12|Ghostty|1|~/omv — nvim\n13|btop|1|btop\n21|Helium|2|Pull requests · GitHub\n31|Zed|3|omv — README.md\n41|Spotify|4|Spotify Premium\n"
  local apps = { { name = "Calculator", path = "/System/Applications/Calculator.app" }, { name = "Zed", path = "/Applications/Zed.app" } }
  local launchers = {
    { label = "Option+Shift+Enter", description = "New Helium window", group = "Apps", runs = true },
    { label = "Option+Shift+N", description = "Open Zed", group = "Apps", runs = true },
    { label = "Option+Shift+F", description = "Finder at home", group = "Apps", runs = true },
    { description = "Dev layout: Zed, Claude Code and a shell", group = "Apps", runs = true },
    { description = "Agent grid: 2–4 Claude agents in worktrees", group = "Apps", runs = true },
  }
  return listShot("windows.png", LIST_WIDTH, { prompt = "Windows, apps, commands…", rows = palette.rows(windows, apps, launchers, "Option+Space"), calc = true })
end

local function bluetoothShot()
  local devices = bluetooth.devices({
    { address = "aa-bb-cc-dd-ee-01", name = "Magic Keyboard", connected = true, paired = true },
    { address = "aa-bb-cc-dd-ee-02", name = "AirPods Pro", connected = true, paired = true },
    { address = "aa-bb-cc-dd-ee-04", name = "MX Master 3S", connected = false, paired = true },
  })
  return listShot("bluetooth.png", 420, { prompt = "Bluetooth…", rows = bluetooth.rows({ installed = true, power = true, devices = devices }) })
end

local function tailscaleShot()
  local status = tailscale.parseStatus({ BackendState = "Running",
    Self = { HostName = "mac", TailscaleIPs = { "100.64.0.1" }, Online = true },
    Peer = {
      a = { HostName = "homelab", TailscaleIPs = { "100.64.0.9" }, Online = true, OS = "linux" },
      b = { HostName = "iphone", TailscaleIPs = { "100.64.0.2" }, Online = false, OS = "iOS" },
      c = { HostName = "nas", TailscaleIPs = { "100.64.0.3" }, Online = true, OS = "linux" },
    } })
  return menuShot("tailscale.png", 480, tailscale.screen(status))
end

local function clipboardShot(now)
  local history = clipboard.new()
  local copies = {
    { "git switch -c fix/bar-clock", "Ghostty", "com.mitchellh.ghostty", HOUR },
    { "https://github.com/acme/api/pull/42", "Helium", "net.imput.helium", 25 * MINUTE },
    { "local rows = palette.rows(output, apps)", "Zed", "dev.zed.Zed", 10 * MINUTE },
    { "brew bundle --file Brewfile", "Ghostty", "com.mitchellh.ghostty", 4 * MINUTE },
    { "Meeting moved to 14:30", "Slack", "com.tinyspeck.slackmacgap", MINUTE },
  }
  for _, copy in ipairs(copies) do
    clipboard.add(history, { text = copy[1], app = copy[2], bundle = copy[3], types = { "public.utf8-plain-text" } }, now - copy[4])
  end
  return listShot("clipboard.png", LIST_WIDTH, { prompt = "Clipboard…", rows = clipboard.rows(history, now) })
end

local function procsShot()
  local list = procs.parse(table.concat({
    "65076  85.7  161888 node /usr/local/bin/vite",
    "  667  10.7  646112 /System/Applications/Music.app/Contents/MacOS/Music",
    "98422   8.0 2682960 claude",
    " 7001   6.2 1402960 /Applications/Zed.app/Contents/MacOS/zed",
    " 7002   2.1  802960 /Applications/Helium.app/Contents/MacOS/Helium",
    " 7003   1.4  302960 btop",
  }, "\n"), 1)
  local folders = procs.folders("p65076\nfcwd\nn/Users/me/work/site\np98422\nfcwd\nn/Users/me/work/omv\n", "/Users/me")
  return listShot("procs.png", LIST_WIDTH, { prompt = "Hungry processes…", tab = true, rows = procs.rows(procs.sorted(list, "cpu"), folders, "cpu") })
end

local function prsShot()
  return listShot("prs.png", LIST_WIDTH, { prompt = "Pull requests…", rows = prs.rows({
    { number = 42, title = "Fix login redirect loop", url = "https://github.com/acme/api/pull/42", repository = { nameWithOwner = "acme/api" } },
    { number = 118, title = "Add dark mode to settings", url = "https://github.com/acme/web/pull/118", repository = { nameWithOwner = "acme/web" } },
    { number = 7, title = "Document the release steps", url = "https://github.com/acme/docs/pull/7", repository = { nameWithOwner = "acme/docs" } },
  }) })
end

local function waitingShot()
  return listShot("waiting.png", LIST_WIDTH, { prompt = "Waiting…", rows = {
    { id = "1", icon = "󰚩", label = "api", hint = "asks · 1 min" },
    { id = "2", icon = "󰚩", label = "omv", hint = "done · 4 min" },
  } })
end

local function devlayoutShot()
  local rows = devlayout.rows({ "/Users/me/work/omv", "/Users/me/work/api", "/Users/me/work/site" }, "/Users/me")
  return listShot("devlayout.png", LIST_WIDTH, { prompt = "Dev layout for…", rows = rows })
end

local function noteShots(now)
  local t = os.date("*t", now)
  local function daysAgo(days, hour) return os.time({ year = t.year, month = t.month, day = t.day - days, hour = hour, min = 0 }) end
  local rows = quicknote.rows({
    { path = "/v/00 - Daily/" .. os.date("%Y-%m-%d", now) .. ".md", folder = "Daily", modified = now - 10 * MINUTE },
    { path = "/v/Inbox/Sprint plan.md", folder = "Inbox", modified = daysAgo(0, 9) },
    { path = "/v/00 - Daily/" .. os.date("%Y-%m-%d", daysAgo(1, 12)) .. ".md", folder = "Daily", modified = daysAgo(1, 18) },
    { path = "/v/Inbox/Q4 roadmap.md", folder = "Inbox", modified = daysAgo(5, 10) },
  }, now)
  local text = "## Sprint plan\n\n- Ship the speed test\n- Retake the README screenshots\n- Look at the bar on the notch"
  return {
    { file = "note-editor.png", kind = "card", width = NOTE_WIDTH, crop = "body", html = notepad.html(text, "Sprint plan") },
    menuShot("note-list.png", NOTE_WIDTH, { prompt = "Notes…", rows = rows }),
  }
end

local function menuShots()
  local system = menu.screen("system")
  local rows, selected = theme.rows({ "catppuccin", "everforest", "gruvbox", "kanagawa", "nord", "rose-pine", "tokyo-night" }, "vantablack")
  return {
    menuShot("system-menu.png", system.width or MENU_WIDTH, system),
    menuShot("themes.png", 420, { prompt = "Theme…", rows = rows, selected = selected }),
    menuShot("capture.png", MENU_WIDTH, capture.screen()),
  }
end

local function add(list, items)
  if items.file then items = { items } end
  for _, item in ipairs(items) do list[#list + 1] = item end
end

-- Every shot, drawn as at now. logo is Claude's logo as a data URL, which only
-- Hammerspoon can read; without it the Agents card shows its glyph.
function shots.build(now, logo)
  local list = {}
  add(list, weatherShot())
  add(list, networkShots())
  add(list, batteryShot())
  add(list, soundShot())
  add(list, agentsShot(now, logo))
  add(list, diskShot(now))
  add(list, calendarShot(now))
  add(list, reminderShots(now))
  add(list, paletteShot())
  add(list, bluetoothShot())
  add(list, tailscaleShot())
  add(list, clipboardShot(now))
  add(list, procsShot())
  add(list, prsShot())
  add(list, waitingShot())
  add(list, devlayoutShot())
  add(list, noteShots(now))
  add(list, menuShots())
  add(list, { file = "key-list.png", kind = "live", feature = "features.keys", call = "toggle" })
  add(list, {
    { file = "osd-volume.png", kind = "osd", icon = osd.volumeIcon(62, false), level = 62 },
    { file = "osd-brightness.png", kind = "osd", icon = osd.ICONS.brightness, level = 44 },
  })
  return list
end

return shots
