-- Do Not Disturb (Option+Escape, then Do Not Disturb, or a click on the bar's moon): the bar
-- shows the Focus that is on, read from macOS's files, which needs Full Disk Access for
-- Hammerspoon. Switching runs the user's "omv Do Not Disturb" shortcut; the first time
-- without it, Shortcuts opens with the steps to make it.

local shell = require("shell")
local focus = require("focus")

local feature = {}

local DB = shell.HOME .. "/Library/DoNotDisturb/DB"
local SHORTCUTS = "/usr/bin/shortcuts"

local function readJson(path)
  local text = shell.readText(path)
  if not text then return nil end
  local ok, data = pcall(hs.json.decode, text)
  return ok and data or nil
end

-- The bar's moon and the Focus's name while one is on; hidden otherwise, and when the files
-- can't be read.
local function showState()
  local mode = focus.activeMode(readJson(DB .. "/Assertions.json"))
  local arguments = { "--set", "focus", "drawing=" .. (mode and "on" or "off") }
  if mode then arguments[#arguments + 1] = "label=" .. focus.modeName(readJson(DB .. "/ModeConfigurations.json"), mode) end
  hs.task.new(shell.SKETCHYBAR, nil, arguments):start()
end

function feature.toggle()
  shell.close()
  hs.task.new(SHORTCUTS, function(_, list)
    if not focus.hasShortcut(list) then
      shell.alert('Make a shortcut named "' .. focus.SHORTCUT .. '" with Set Focus: Do Not Disturb, Toggle', 6)
      return shell.open({ "-a", "Shortcuts" })()
    end
    hs.task.new(SHORTCUTS, function() showState() end, { "run", focus.SHORTCUT }):start()
  end, { "list" }):start()
end

-- Kept on the feature, so it isn't garbage-collected. macOS rewrites the files on every change.
feature.watcher = hs.pathwatcher.new(DB, showState):start()
showState()

return feature
