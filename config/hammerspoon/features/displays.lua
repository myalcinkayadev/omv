-- Display profiles: when displays connect or disconnect, and on wake, the first profile in
-- ~/.config/omv/displays whose displays are plugged in applies: AeroSpace's layout and gaps, Do
-- Not Disturb, the theme, Ghostty's font size and the bar. Leaving a profile puts back what it
-- changed. A notice names the profile; a mistake in the file is named instead, and nothing
-- else changes. The system menu and the palette can pick one by hand.
-- Without the file, none of this does anything.

local shell = require("shell")
local card = require("card")
local displays = require("displays")
local focus = require("focus")

local feature = {}

local REPO = hs.configdir:gsub("/config/hammerspoon/?$", "")
local OMV = REPO .. "/bin/omv"
local SHORTCUTS = "/usr/bin/shortcuts"
local DND_DB = shell.HOME .. "/Library/DoNotDisturb/DB/Assertions.json"
local AEROSPACE_PROFILE = shell.STATE_DIR .. "/aerospace-profile.toml"
local GHOSTTY_PROFILE = shell.STATE_DIR .. "/ghostty-profile"
-- What's in use, kept across reloads, so a reload doesn't apply the same profile twice.
local STATE = shell.STATE_DIR .. "/display-profile.json"
-- Displays often connect in steps; the profile is worked out once they've settled.
local SETTLE_SECONDS = 1.5

local function readState()
  -- hs.json.read logs an error for a file that isn't there, so that's checked first.
  if not hs.fs.attributes(STATE) then return {} end
  local ok, saved = pcall(hs.json.read, STATE)
  return ok and type(saved) == "table" and saved or {}
end

local function writeState(saved)
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
  hs.json.write(saved, STATE, false, true)
end

local function writeFile(path, text)
  if not text then return os.remove(path) end
  local file = io.open(path, "w")
  if not file then return end
  file:write(text)
  file:close()
end

-- { { name, builtin } } for each display plugged in.
local function screens()
  local found = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local name = screen:name() or ""
    found[#found + 1] = { name = name, builtin = name:find("Built%-in") ~= nil }
  end
  return found
end

local function focusOn()
  local ok, data = pcall(hs.json.decode, shell.readText(DND_DB) or "")
  return focus.activeMode(ok and data or nil) ~= nil
end

-- The user's "omv Do Not Disturb" shortcut toggles it, when there is one.
local function setQuiet(on)
  if focusOn() == on then return end
  hs.task.new(SHORTCUTS, function(_, list)
    if focus.hasShortcut(list) then hs.task.new(SHORTCUTS, nil, { "run", focus.SHORTCUT }):start() end
  end, { "list" }):start()
end

local function setLayout(layout)
  local mode = layout == "tabs" and "accordion" or "tiles"
  local output = hs.execute(shell.AEROSPACE .. " list-workspaces --all") or ""
  for workspace in output:gmatch("[^\n]+") do
    hs.task.new(shell.AEROSPACE, nil, { "layout", "--workspace", workspace, mode }):start()
  end
end

local function run(command)
  if command then hs.task.new("/bin/sh", nil, { "-c", command }):start() end
end

local function summary(profile)
  local settings, parts = profile.settings, {}
  if settings.layout then parts[#parts + 1] = settings.layout end
  if settings.gapsOuter or settings.gapsInner then parts[#parts + 1] = "gaps " .. (settings.gapsOuter or settings.gapsInner) end
  if settings.quiet == "on" then parts[#parts + 1] = "quiet" end
  if settings.theme then parts[#parts + 1] = settings.theme end
  if settings.font then parts[#parts + 1] = "font " .. settings.font end
  return table.concat(parts, " · ")
end

-- Applies the move from the profile in use to profile, either nil, and remembers it.
-- The profile in use is kept with its settings, so leaving it puts things back even after the
-- file changed or was removed.
local function apply(profile, saved)
  local before = saved.active and { name = saved.active, settings = saved.settings or {} } or nil
  local changes = displays.changes(before, profile)
  run(changes.onLeave)
  if changes.layout then setLayout(changes.layout == "default" and "tiles" or changes.layout) end
  if changes.gapsInner or changes.gapsOuter then
    writeFile(AEROSPACE_PROFILE, profile and displays.aerospaceGaps(profile.settings) or nil)
    -- Hammerspoon's tasks get a bare PATH; omv needs Homebrew's luajit and aerospace.
    hs.task.new(OMV, nil, { "reload", "aerospace" })
      :setEnvironment({ HOME = shell.HOME, PATH = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" }):start()
  end
  if changes.quiet then
    if changes.quiet == "default" then setQuiet(saved.quietBefore == true)
    else
      if saved.quietBefore == nil then saved.quietBefore = focusOn() end
      setQuiet(changes.quiet == "on")
    end
  end
  if changes.theme then
    local themes = require("features.theme")
    if changes.theme == "default" then
      if saved.themeBefore then themes.set(saved.themeBefore) end
      saved.themeBefore = nil
    else
      saved.themeBefore = saved.themeBefore or themes.current()
      themes.set(changes.theme)
    end
  end
  if changes.font then writeFile(GHOSTTY_PROFILE, changes.font ~= "default" and ("font-size = " .. changes.font .. "\n") or nil) end
  if changes.bar then hs.task.new(shell.SKETCHYBAR, nil, { "--bar", "hidden=" .. (changes.bar == "hidden" and "on" or "off") }):start() end
  if changes.quiet == "default" then saved.quietBefore = nil end
  run(changes.onEnter)
  saved.active = profile and profile.name or nil
  saved.settings = profile and profile.settings or nil
  writeState(saved)
  if type(omvOnDisplayProfile) == "function" then pcall(omvOnDisplayProfile, saved.active) end
  if profile then shell.alert(profile.name .. (summary(profile) ~= "" and ("  ·  " .. summary(profile)) or ""), 2)
  elseif before then shell.alert("No display profile", 1.5) end
end

-- Works out the profile for the displays now, and applies it when it isn't the one in use, or
-- is but its settings were edited since.
function feature.check()
  local text = shell.readText(displays.PATH)
  local read = displays.parse(text)
  if #read.problems > 0 then
    return shell.alert("~/.config/omv/displays " .. read.problems[1], 5)
  end
  local saved = readState()
  local profile = displays.current(saved.choice, read.profiles, screens())
  if (profile and profile.name or nil) == saved.active and displays.sameSettings(profile and profile.settings, saved.settings) then return end
  apply(profile, saved)
end

-- The card: each profile, the one in use marked, and Follow the displays.
function feature.open()
  local read = displays.parse(shell.readText(displays.PATH))
  if #read.profiles == 0 then return shell.alert("No profiles yet: add them to ~/.config/omv/displays", 3) end
  local saved = readState()
  local rows = {}
  for _, profile in ipairs(read.profiles) do
    local hint = profile.name == saved.active and ("in use" .. ((saved.choice or {}).picked and " · picked" or "")) or summary(profile)
    rows[#rows + 1] = { id = "profile:" .. profile.name, icon = "󰍹", label = profile.name, hint = hint }
  end
  rows[#rows + 1] = { id = "follow", icon = "󰑐", label = "Follow the displays", hint = "automatic" }
  shell.show("displays", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows)),
    card.html({ prompt = "Display profile…", rows = rows, compact = true }), function(message)
      if message.type ~= "choose" then return shell.close() end
      shell.close()
      local state = readState()
      local name = message.id:match("^profile:(.+)$")
      local chosen = nil
      for _, profile in ipairs(read.profiles) do
        if profile.name == name then chosen = profile end
      end
      state.choice = displays.choose(state.choice, chosen, screens())
      writeState(state)
      feature.check()
    end)
end

local pending = hs.timer.delayed.new(SETTLE_SECONDS, feature.check)

-- Kept on the feature, so they aren't garbage-collected.
feature.screens = hs.screen.watcher.new(function() pending:start() end):start()
feature.wake = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then pending:start() end
end):start()
pending:start()

return feature
