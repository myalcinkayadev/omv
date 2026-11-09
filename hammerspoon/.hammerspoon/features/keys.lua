-- Key list (Option+/): every shortcut at once, and runs the one picked.
-- init.lua adds each key it binds to launchers, so the list can show and run it.

local shell = require("shell")
local keymap = require("keymap")

local feature = {}

local AEROSPACE_CONFIG = shell.HOME .. "/.config/aerospace/aerospace.toml"
-- Enter on a row runs that shortcut. The list closes and focus goes back first, because
-- commands like "focus left" act on whichever window has focus.
local KEY_LIST_DELAY = 0.15

-- { label, description, group, run, runs }: runs is false for a key that can't run from the list.
feature.launchers = {}

local keyListBindings = {}

local function runSteps(steps, index)
  local step = steps[index]
  if not step then return end
  local program = step.program == "aerospace" and shell.AEROSPACE or step.program
  hs.task.new(program, function() runSteps(steps, index + 1) end, step.args):start()
end

local function runKeyListRow(id)
  local kind, index = id:match("^(%a+):(%d+)$")
  index = tonumber(index)
  if kind == "binding" and keyListBindings[index] then
    local steps = keymap.steps(keyListBindings[index].commands)
    return function() runSteps(steps, 1) end
  end
  local launcher = kind == "launcher" and feature.launchers[index]
  return launcher and launcher.runs and launcher.run or nil
end

local function onKeyListMessage(message)
  if message.type ~= "choose" then return shell.close() end
  local action = runKeyListRow(message.id)
  shell.close()
  if action then hs.timer.doAfter(KEY_LIST_DELAY, action) end
end

function feature.toggle()
  if shell.isOpen("keys") then return shell.close() end
  local bindings = keymap.read(AEROSPACE_CONFIG)
  keyListBindings = bindings
  local layout = keymap.layout(keymap.lines(keymap.rows(bindings, feature.launchers)), hs.screen.mainScreen():frame())
  shell.show("keys", shell.centered(layout.w, layout.h), keymap.html(bindings, feature.launchers, layout.columns), onKeyListMessage)
end

return feature
