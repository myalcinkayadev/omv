-- The stall detector, while the stalls flag is on: each time Hammerspoon's thread is blocked
-- for over a quarter of a second, a line goes to ~/.local/state/omv/stalls.log, never to the
-- console. Read it to see which card or key stalls. Every 10 minutes a health line adds the
-- Lua memory and the background commands still running, so a leak shows as a number growing.

local shell = require("shell")
local stalls = require("stalls")

local feature = {}

feature.PATH = shell.STATE_DIR .. "/stalls.log"

local last = hs.timer.secondsSinceEpoch()

local function tick()
  local now = hs.timer.secondsSinceEpoch()
  local gap = stalls.gap(last, now)
  last = now
  if not gap then return end
  stalls.append(feature.PATH, stalls.line(os.date("%Y-%m-%d %H:%M:%S"), gap, shell.openName()))
end

local function health()
  stalls.append(feature.PATH, stalls.healthLine(os.date("%Y-%m-%d %H:%M:%S"), collectgarbage("count"), shell.runningCount()))
end

os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
-- Kept on the feature, so they aren't garbage-collected.
feature.timer = hs.timer.doEvery(stalls.TICK, tick)
feature.healthTimer = hs.timer.doEvery(stalls.HEALTH_SECONDS, health)
health()

return feature
