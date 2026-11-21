-- Themes (Option+Escape, then Theme): Vantablack, built in, or one of Omarchy's themes,
-- fetched on request by theme-sync.sh. Picking one recolors the cards at once, writes the
-- bar's and Ghostty's colours to ~/.local/state/omv/theme and reloads the bar, and
-- recolors the focused window's outline. Ghostty picks up its colours in new windows, or
-- with its own config reload (Cmd+Shift+,). The choice is kept across reloads.

local shell = require("shell")
local card = require("card")
local theme = require("theme")
local themeclock = require("themeclock")

local feature = {}

local THEMES = shell.HOME .. "/.local/share/omv/themes"
local STATE = shell.STATE_DIR .. "/theme"
local CURRENT = STATE .. "/current"
local SYNC = hs.configdir .. "/theme-sync.sh"
local WIDTH = 420
local VISIBLE_ROWS = 12

local function names()
  local found = {}
  local ok, files, folder = pcall(hs.fs.dir, THEMES)
  for name in (ok and files) and files or function() end, folder do
    if theme.plainName(name) and hs.fs.attributes(THEMES .. "/" .. name .. "/colors.toml") then found[#found + 1] = name end
  end
  table.sort(found)
  return found
end

local function current()
  local name = (shell.readText(CURRENT) or ""):match("^%s*([%w%-]+)")
  return name or "vantablack"
end

local function tokensFor(name)
  if name == "vantablack" then return theme.tokens(nil) end
  return theme.tokens(theme.parse(shell.readText(THEMES .. "/" .. name .. "/colors.toml")))
end

local function write(path, text)
  local file = io.open(path, "w")
  if not file then return false end
  file:write(text)
  file:close()
  return true
end

-- borders started by AeroSpace takes new colours when run again; it's never started here.
local function outline(tokens)
  if (hs.execute("/usr/bin/pgrep -x borders") or "") == "" then return end
  hs.task.new("/opt/homebrew/bin/borders", nil, theme.bordersArguments(tokens)):start()
end

local function apply(name)
  local tokens = tokensFor(name)
  os.execute("/bin/mkdir -p '" .. STATE .. "'")
  write(STATE .. "/colors.sh", theme.sketchybarColors(tokens))
  write(STATE .. "/ghostty", theme.ghosttyConfig(tokens))
  write(CURRENT, name .. "\n")
  shell.setTheme(tokens)
  outline(tokens)
  hs.task.new(shell.SKETCHYBAR, nil, { "--reload" }):start()
end

-- The theme in use, by name; Vantablack when none was chosen.
feature.current = current

-- Switches to a theme by name, as omv theme <name> does. An unknown name changes nothing.
function feature.set(name)
  if not theme.plainName(name) then return end
  if name ~= "vantablack" and not hs.fs.attributes(THEMES .. "/" .. tostring(name) .. "/colors.toml") then return end
  apply(name)
end

local function sync()
  shell.close()
  shell.alert("Getting Omarchy's themes…", 2)
  hs.task.new(SYNC, function(code, output)
    if code ~= 0 then return shell.alert("Couldn't reach GitHub", 1.5) end
    shell.alert("Got " .. (output:match("%d+") or "0") .. " themes", 1.5)
    feature.open()
  end):start()
end

function feature.open()
  local rows, selected = theme.rows(names(), current())
  local screen = { prompt = "Theme…", rows = rows, selected = selected }
  shell.show("theme", shell.centered(WIDTH, shell.menuHeight(screen)), card.html(screen), function(message)
    if message.type == "back" then return require("features.menu").toggle() end
    if message.type ~= "choose" then return shell.close() end
    if message.id == "sync" then return sync() end
    local name = message.id:match("^theme:([%w%-]+)$")
    if not name then return end
    apply(name)
    -- Reopened, so the card shows itself in the new colours.
    feature.open()
  end)
end

-- Theme by the clock, when ~/.config/omv/theme-clock names a day and a night theme. The
-- theme switches only when day turns to night or back, so one picked by hand stays until
-- the next sunrise or sunset. The file is read each time, so a change needs no reload.
local CLOCK_PERIOD = STATE .. "/clock-period"
local CLOCK_SECONDS = 5 * 60

-- Where the Mac is, only when Hammerspoon may already know: the clock never asks.
local function location()
  if hs.location.authorizationStatus() ~= "authorized" then return nil end
  hs.location.start()
  local found = hs.location.get()
  hs.location.stop()
  return found
end

local function followClock()
  local config = themeclock.parse(shell.readText(themeclock.PATH))
  if not config then return end
  local now, today = os.time(), os.date("*t")
  local place = location()
  local sunrise, sunset
  if place then sunrise, sunset = themeclock.sun(today, place.latitude, place.longitude) end
  local period = themeclock.period(now, sunrise, sunset, today)
  if period == (shell.readText(CLOCK_PERIOD) or ""):match("^%a+") then return end
  os.execute("/bin/mkdir -p '" .. STATE .. "'")
  write(CLOCK_PERIOD, period .. "\n")
  if config[period] ~= current() then feature.set(config[period]) end
end

-- Kept on the feature, so they aren't garbage-collected.
feature.clockTimer = hs.timer.doEvery(CLOCK_SECONDS, followClock)
feature.clockWake = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then followClock() end
end):start()

-- The cards and the outline take the chosen theme as soon as this config loads; the bar's
-- and Ghostty's files are already written.
local chosen = current()
if chosen ~= "vantablack" then
  local tokens = tokensFor(chosen)
  shell.setTheme(tokens)
  outline(tokens)
end
followClock()

return feature
