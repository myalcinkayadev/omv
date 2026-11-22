-- Display profiles: when displays connect or disconnect, and on wake, the first profile in
-- ~/.config/omv/displays whose displays are plugged in applies: AeroSpace's layout and gaps, Do
-- Not Disturb, the theme, Ghostty's font size and the bar. Leaving a profile puts back what it
-- changed. A notice names the profile; a mistake in the file is named instead, and nothing
-- else changes. The system menu and the palette can pick one by hand, save the displays
-- plugged in as a profile, or open the file in the editor; saving the file applies it.
-- Without the file, none of this does anything but remember the displays seen.

local shell = require("shell")
local card = require("card")
local displays = require("displays")
local focus = require("focus")
local apps = require("apps")

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
-- An editor can save a few times in a row; the file is read once they've stopped.
local SAVED_SECONDS = 1.0

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
  local output = hs.execute(shell.AEROSPACE .. " list-workspaces --all") or ""
  for workspace in output:gmatch("[^\n]+") do
    hs.task.new(shell.AEROSPACE, nil, displays.layoutArgs(workspace, layout)):start()
  end
end

local function run(command)
  if command then hs.task.new("/bin/sh", nil, { "-c", command }):start() end
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
  if profile then shell.alert(profile.name .. (displays.summary(profile) ~= "" and ("  ·  " .. displays.summary(profile)) or ""), 2)
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

-- Remembers the displays plugged in now, for the file's header and omv displays.
local function recordSeen()
  local seen = displays.recordSeen(displays.parseSeen(shell.readText(displays.SEEN_PATH)), screens(), os.date("%Y-%m-%d"))
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
  writeFile(displays.SEEN_PATH, displays.formatSeen(seen))
  return seen
end

-- Opens the file in the editor from ~/.config/omv/apps, or macOS's text editor without it.
local function openFile()
  local editor = apps.read(shell.readText(apps.PATH)).editor
  hs.task.new("/usr/bin/open", function(code)
    if code ~= 0 then hs.task.new("/usr/bin/open", nil, { "-t", displays.PATH }):start() end
  end, { "-a", editor, displays.PATH }):start()
end

-- Writes the starter file when there's none, so the editor opens on what to write.
local function ensureFile()
  if shell.readText(displays.PATH) then return end
  os.execute("/bin/mkdir -p '" .. shell.HOME .. "/.config/omv'")
  writeFile(displays.PATH, displays.starter(recordSeen()))
end

local function saveDisplays(profiles)
  ensureFile()
  local text, name = displays.addProfile(shell.readText(displays.PATH), screens(), profiles, os.date("%Y-%m-%d"))
  writeFile(displays.PATH, text)
  openFile()
  shell.alert("Saved as " .. name .. ": add its settings, then save", 3)
end

-- The card: the profiles, then saving the displays as a profile and opening the file.
function feature.open()
  local read = displays.parse(shell.readText(displays.PATH))
  local saved = readState()
  local rows = displays.rows(read.profiles, { active = saved.active, picked = (saved.choice or {}).picked ~= nil }, screens())
  shell.show("displays", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows)),
    card.html({ prompt = "Display profile…", rows = rows, compact = true }), function(message)
      if message.type ~= "choose" then return shell.close() end
      shell.close()
      if message.id == "save" then return saveDisplays(read.profiles) end
      if message.id == "file" then
        ensureFile()
        return openFile()
      end
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

local pending = hs.timer.delayed.new(SETTLE_SECONDS, function()
  recordSeen()
  feature.check()
end)
local edited = hs.timer.delayed.new(SAVED_SECONDS, feature.check)

-- Kept on the feature, so they aren't garbage-collected.
feature.screens = hs.screen.watcher.new(function() pending:start() end):start()
-- The folder, not the file: an editor often saves by replacing the file, and it may not exist yet.
feature.file = hs.pathwatcher.new(shell.HOME .. "/.config/omv", function(paths)
  for _, path in ipairs(paths) do
    if path:match("/displays$") then return edited:start() end
  end
end):start()
feature.wake = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then pending:start() end
end):start()
pending:start()

return feature
