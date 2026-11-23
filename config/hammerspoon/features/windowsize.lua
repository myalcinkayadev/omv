-- Window sizing: Ctrl+Option+Left and Right for halves (pressed again, a third, then
-- two-thirds), Up for almost full, Down for centred at two-thirds, C to centre it as it is.
-- A tiled window is floated first, so the keys always do something; Option+T tiles it again.
-- windowsize.lua holds the sizes; this asks AeroSpace and moves the window, never waiting.

local shell = require("shell")
local windowsize = require("windowsize")
local workspaces = require("workspaces")

local feature = {}

-- The last press, so the same key again soon steps to the next size.
local memory = {}

-- The [screen] section in ~/.config/omv/workspaces for screen, or nil.
local function sectionFor(screen)
  local list = workspaces.parse(shell.readText(workspaces.PATH))
  local screens = require("features.workspaces").screens()
  for _, entry in ipairs(screens) do
    if entry.name == screen:name() then return workspaces.sectionOf(list, entry, screens) end
  end
  return nil
end

local function move(window, action, step)
  local screen = window:screen()
  local builtin = (screen:name() or ""):find("Built%-in") ~= nil
  local area = windowsize.area(screen:frame(), windowsize.outer(sectionFor(screen), builtin))
  local now = window:frame()
  window:setFrame(windowsize.place(action, area, { x = now.x, y = now.y, w = now.w, h = now.h }, step), 0)
end

-- Sizes the focused window: left, right, up, down or center.
function feature.size(action)
  local window = hs.window.focusedWindow()
  if not window then return end
  local step
  step, memory = windowsize.nextStep(memory, action, hs.timer.secondsSinceEpoch())
  shell.execute(shell.AEROSPACE .. " list-windows --focused --format '%{window-layout}'", function(output)
    if not windowsize.needsFloat((output or ""):match("%S+") or "") then return move(window, action, step) end
    shell.execute(shell.AEROSPACE .. " layout floating", function()
      -- AeroSpace lets go of the window first; moving it at once could be undone by its layout.
      hs.timer.doAfter(0.05, function() move(window, action, step) end)
    end)
  end)
end

return feature
