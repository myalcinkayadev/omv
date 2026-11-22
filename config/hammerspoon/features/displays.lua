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
-- Each check and the load, so a check that didn't run shows; see displays.logLine.
local LOG = shell.STATE_DIR .. "/display-profile.log"
-- Displays often connect in steps; the profile is worked out once they've settled.
local SETTLE_SECONDS = 1.5
-- An editor can save a few times in a row; the file is read once they've stopped.
local SAVED_SECONDS = 1.0
local LIST_FOOTER = { { key = "Enter", text = "use it" }, { key = "Tab", text = "edit it" }, { key = "⌫", text = "delete" },
  { key = "Esc", text = "close" } }
-- How long a deleted profile is offered back once the card closes; while it's open, it stays.
local UNDO_SECONDS = 60
local EDIT_FOOTER = { { key = "Left/Right", text = "change" }, { key = "Enter", text = "open › or save" }, { key = "Esc", text = "cancel" } }
local WHEN_FOOTER = { { key = "Enter", text = "tick or untick" }, { key = "Esc", text = "back" } }
-- How much taller a footer makes a list card.
local FOOTER_HEIGHT = 24

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
local function apply(profile, saved, silent)
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
  if silent then return end
  if profile then shell.alert(profile.name .. (displays.summary(profile) ~= "" and ("  ·  " .. displays.summary(profile)) or ""), 2)
  elseif before then shell.alert("No display profile", 1.5) end
end

local function log(reason, result)
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
  writeFile(LOG, displays.appendLog(shell.readText(LOG), displays.logLine(os.time(), reason, result)))
end

-- Works out the profile for the displays now, and applies it when it isn't the one in use, or
-- is but its settings were edited since. reason is why it runs, for the log.
function feature.check(reason)
  local text = shell.readText(displays.PATH)
  local read = displays.parse(text)
  if #read.problems > 0 then
    log(reason, "problem: " .. read.problems[1])
    return shell.alert("~/.config/omv/displays " .. read.problems[1], 5)
  end
  local saved = readState()
  local profile = displays.current(saved.choice, read.profiles, screens())
  local name = profile and profile.name or nil
  if name == saved.active and displays.sameSettings(profile and profile.settings, saved.settings) then
    return log(reason, name and ("kept " .. name) or "none")
  end
  apply(profile, saved)
  log(reason, name and ("applied " .. name) or "none")
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

-- The profile being edited: its name, and its settings in the file and as edited. Nothing
-- applies until Enter writes the file, which applies it as any save does.
local editing = nil

-- Writes the lines that changed. A profile that isn't for these displays is only saved, so a
-- notice says when it applies.
local function saveEdits()
  local was = editing
  editing = nil
  shell.close()
  if not was then return end
  local text = displays.writeSettings(shell.readText(displays.PATH), was.name, was.before, was.edited)
  local name = was.newName or was.name
  if was.newName then
    text = displays.renameProfile(text, was.name, was.newName)
    -- The state follows the name, so a renamed profile isn't applied again.
    local state = readState()
    if state.active == was.name then state.active = name end
    if type(state.choice) == "table" and state.choice.picked == was.name then state.choice.picked = name end
    writeState(state)
  end
  writeFile(displays.PATH, text)
  local inUse = displays.current(readState().choice, displays.parse(text).profiles, screens())
  if not inUse or inUse.name ~= name then shell.alert(name .. " saved: it applies with its displays", 2.5) end
end

local function themeNames()
  local ok, themes = pcall(require, "features.theme")
  return ok and type(themes.names) == "function" and themes.names() or {}
end

local showEditor

-- Asks for a new name; Enter goes back to the editor with it, to be saved with the settings.
local function showRename(hint)
  local name = editing.newName or editing.name
  shell.show("displays", shell.centered(shell.LIST_WIDTH, 28 + 46 + 44 + 4),
    card.html({ prompt = "Rename " .. name .. "…", rows = {}, input = true,
      hint = hint or ("Enter keeps " .. name .. " · any name without [ ] or #") }), function(message)
      if not editing then return shell.close() end
      if message.type ~= "submit" then return showEditor(1) end
      local profiles = displays.parse(shell.readText(displays.PATH)).profiles
      local typed, problem = displays.checkName(message.id, profiles, editing.name)
      if not typed then return showRename(problem) end
      editing.newName = typed ~= editing.name and typed or nil
      showEditor(1)
    end, { onEscape = function() showEditor(1) end })
end

-- Whether the profile as edited is used with the displays plugged in now.
local function editedStatus()
  local profiles = displays.parse(shell.readText(displays.PATH)).profiles
  for _, profile in ipairs(profiles) do
    if profile.name == editing.name then
      profile.when = displays.parseWhen(editing.edited.when).items
    end
  end
  return displays.matchStatus(editing.name, profiles, screens())
end

local showWhen

-- Asks for part of a display's name omv hasn't seen; Enter adds it to the picker, ticked.
local function showTypeWhen()
  shell.show("displays", shell.centered(shell.LIST_WIDTH, 28 + 46 + 44 + 4),
    card.html({ prompt = "Part of a display's name…", rows = {}, input = true, hint = "Enter adds it, ticked · Esc goes back" }),
    function(message)
      if not editing then return shell.close() end
      if message.type == "submit" then editing.when = displays.addWhen(editing.when, message.id) end
      showWhen(1)
    end, { onEscape = function() showWhen(1) end })
end

-- The When picker: Enter ticks or unticks a display; Done takes the ticks back to the editor.
function showWhen(selected)
  local rows = displays.whenRows(editing.when, displays.parseSeen(shell.readText(displays.SEEN_PATH)))
  shell.show("displays", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows) + FOOTER_HEIGHT),
    card.html({ prompt = "When " .. (editing.newName or editing.name) .. " is used…", rows = rows, compact = true,
      footer = WHEN_FOOTER, selected = selected }), function(message)
      if not editing then return shell.close() end
      if message.type ~= "choose" then return showEditor(2) end
      local index = 1
      for position, row in ipairs(rows) do
        if row.id == message.id then index = position end
      end
      if message.id == "type" then return showTypeWhen() end
      if message.id == "done" then
        local text = displays.doneWhen(editing.when)
        if not text then return showWhen(index) end
        editing.edited.when = text
        return showEditor(2)
      end
      local display = message.id:match("^display:(.+)$")
      if display then editing.when = displays.toggleWhen(editing.when, display) end
      showWhen(index)
    end, { onEscape = function() showEditor(2) end })
end

function showEditor(selected)
  local rows = displays.editRows(editing.edited, editing.newName or editing.name, editedStatus())
  shell.show("displays", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows) + FOOTER_HEIGHT),
    card.html({ prompt = "Edit " .. (editing.newName or editing.name) .. "…", rows = rows, compact = true, step = true, footer = EDIT_FOOTER,
      selected = selected }), function(message)
      if message.type == "step" then
        local direction, id = message.id:match("^(%-?1):(.+)$")
        if not editing or not id then return end
        editing.edited = displays.step(editing.edited, id, tonumber(direction), themeNames())
        for index, row in ipairs(rows) do
          if row.id == id then selected = index end
        end
        return showEditor(selected)
      end
      if message.type == "choose" and message.id == "name" then return showRename() end
      if message.type == "choose" and message.id == "when" then
        editing.when = displays.parseWhen(editing.edited.when)
        return showWhen(1)
      end
      if message.type == "choose" then return saveEdits() end
      editing = nil
      shell.close()
    end)
end

-- Opens the editor on profile name; a file with a line it can't read is fixed first.
local function openEditor(name)
  local read = displays.parse(shell.readText(displays.PATH))
  if #read.problems > 0 then return shell.alert("~/.config/omv/displays " .. read.problems[1] .. ": fix it to edit", 5) end
  local found = nil
  for _, profile in ipairs(read.profiles) do
    if profile.name == name then found = profile end
  end
  if not found then return end
  local settings = { when = displays.whenText({ items = found.when or {} }) }
  for key, value in pairs(found.settings) do
    if key ~= "onEnter" and key ~= "onLeave" then settings[key] = value end
  end
  editing = { name = name, before = settings, edited = settings }
  showEditor(1)
end

local function saveDisplays(profiles)
  ensureFile()
  local text, name = displays.addProfile(shell.readText(displays.PATH), screens(), profiles, os.date("%Y-%m-%d"))
  writeFile(displays.PATH, text)
  openEditor(name)
end

-- The profile deleted last, offered back: its name, its row, the file before and after, the
-- lines taken out and when.
local deleted = nil

-- Removes profile name from the file; the save watcher then puts back what it changed.
local function deleteProfile(name, index)
  local before = shell.readText(displays.PATH)
  local after, block = displays.removeProfile(before, name)
  writeFile(displays.PATH, after)
  deleted = { name = name, index = index, before = before, after = after, block = block, at = os.time() }
end

-- Puts the deleted profile back; the save watcher applies it again when it's for these displays.
local function bringBack()
  local was = deleted
  deleted = nil
  if not was then return end
  writeFile(displays.PATH, displays.restoreProfile(shell.readText(displays.PATH), was.after, was.before, was.block))
  shell.alert(was.name .. " is back", 2)
  return was.index
end

-- The card: the profiles, then saving the displays as a profile and opening the file.
-- selected is the row to select, when the card opens again after a Backspace.
function feature.open(selected)
  if type(selected) ~= "number" then selected = nil end
  local read = displays.parse(shell.readText(displays.PATH))
  local saved = readState()
  if deleted and os.time() - deleted.at > UNDO_SECONDS then deleted = nil end
  local rows = displays.rows(read.profiles, { active = saved.active, picked = (saved.choice or {}).picked ~= nil,
    deleted = deleted and { name = deleted.name, index = deleted.index } }, screens())
  local footer = #read.profiles > 0 and LIST_FOOTER or nil
  shell.show("displays", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows) + (footer and FOOTER_HEIGHT or 0)),
    card.html({ prompt = "Display profile…", rows = rows, compact = true, tab = true, clearable = true,
      footer = footer, selected = selected }), function(message)
      if message.type == "clear" then
        local name = (message.id or ""):match("^profile:(.+)$")
        if not name then return end
        local index = 1
        for position, row in ipairs(rows) do
          if row.id == message.id then index = position end
        end
        deleteProfile(name, index)
        return feature.open(index)
      end
      if message.type == "choose" and message.id == "undo" then return feature.open(bringBack()) end
      if message.type == "tab" then
        local name = (message.id or ""):match("^profile:(.+)$")
        if name then openEditor(name) end
        return
      end
      if message.type ~= "choose" then return shell.close() end
      if message.id == "save" then return saveDisplays(read.profiles) end
      shell.close()
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
      feature.check("card")
    end)
end

-- Why the next settled check runs: the load, until displays change or the Mac wakes.
local pendingReason = "load"
local pending = hs.timer.delayed.new(SETTLE_SECONDS, function()
  recordSeen()
  feature.check(pendingReason)
end)
local edited = hs.timer.delayed.new(SAVED_SECONDS, function() feature.check("saved") end)

-- Kept on the feature, so they aren't garbage-collected.
feature.screens = hs.screen.watcher.new(function()
  pendingReason = "displays"
  pending:start()
end):start()
-- The folder, not the file: an editor often saves by replacing the file, and it may not exist yet.
feature.file = hs.pathwatcher.new(shell.HOME .. "/.config/omv", function(paths)
  for _, path in ipairs(paths) do
    if path:match("/displays$") then return edited:start() end
  end
end):start()
feature.wake = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then
    pendingReason = "wake"
    pending:start()
  end
end):start()
log("load")
pending:start()

return feature
