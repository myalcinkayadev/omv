-- Do Not Disturb: which Focus is on, from macOS's own files in ~/Library/DoNotDisturb/DB,
-- and the Shortcuts shortcut that switches it, since macOS has no other way to.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local focus = {}

-- Made once by the user in Shortcuts, with the single action Set Focus: Do Not Disturb, Toggle.
focus.SHORTCUT = "omv Do Not Disturb"

local function first(data)
  return type(data) == "table" and type(data.data) == "table" and data.data[1] or nil
end

-- Assertions.json: the Focus switched on by hand or by a shortcut. A scheduled Focus isn't
-- listed there, so it doesn't show.
function focus.activeMode(assertions)
  local store = first(assertions)
  local records = type(store) == "table" and store.storeAssertionRecords
  local record = type(records) == "table" and records[1]
  local details = type(record) == "table" and record.assertionDetails
  return type(details) == "table" and details.assertionDetailsModeIdentifier or nil
end

-- ModeConfigurations.json: the name the user sees for a Focus.
function focus.modeName(configurations, identifier)
  local store = first(configurations)
  local modes = type(store) == "table" and store.modeConfigurations
  local configured = type(modes) == "table" and modes[identifier]
  local mode = type(configured) == "table" and configured.mode
  return type(mode) == "table" and type(mode.name) == "string" and mode.name or "Focus"
end

-- `shortcuts list`: one name a line.
function focus.hasShortcut(list)
  for name in (list or ""):gmatch("[^\n]+") do
    if name == focus.SHORTCUT then return true end
  end
  return false
end

return focus
