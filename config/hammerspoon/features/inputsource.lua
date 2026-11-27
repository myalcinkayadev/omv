-- Input source (the bar item): the keyboard input source in use, as TR or US, hidden while
-- only one is enabled. A click switches to the next one. macOS announces each change, so
-- nothing polls, and SketchyBar is run only when the item would look different.

local shell = require("shell")
local inputsource = require("inputsource")

local feature = {}

-- What the item was last set to, so a repeated announcement doesn't run SketchyBar again.
local shown, drawing = nil, nil

-- Layouts first, then input methods such as a Japanese IME, by their ids.
local function enabledSources()
  local sources = hs.keycodes.layouts(true) or {}
  for _, method in ipairs(hs.keycodes.methods(true) or {}) do sources[#sources + 1] = method end
  return sources
end

local function drawBar()
  local properties = inputsource.barProperties(enabledSources(), hs.keycodes.currentSourceID())
  local key = table.concat(properties, "\n")
  if key == shown then return end
  shown = key
  local arguments = { "--set", "input_source" }
  for _, property in ipairs(properties) do arguments[#arguments + 1] = property end
  -- A tag is two letters in a monospaced font, so only showing or hiding the item changes
  -- how much room the right side needs.
  if properties[1] ~= drawing then
    arguments[#arguments + 1] = "--trigger"
    arguments[#arguments + 1] = "bar_fit"
  end
  drawing = properties[1]
  hs.task.new(shell.SKETCHYBAR, nil, arguments):start()
end

-- The bar redraws itself through the change macOS announces.
function feature.next()
  local source = inputsource.nextSource(enabledSources(), hs.keycodes.currentSourceID())
  if not source then return end
  hs.keycodes.currentSourceID(source)
end

-- A restarted bar has lost the item, so it's sent even when it hasn't changed.
function feature.redrawBar()
  shown, drawing = nil, nil
  drawBar()
end

-- hs.keycodes keeps one callback for all of Hammerspoon, so nothing here can be collected; a
-- later one, such as in ~/.config/omv/hammerspoon.lua, replaces this.
hs.keycodes.inputSourceChanged(drawBar)
drawBar()

return feature
