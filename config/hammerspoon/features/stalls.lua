-- The stall detector, while the stalls flag is on: each time Hammerspoon's thread is blocked
-- for over a quarter of a second, a line goes to ~/.local/state/omv/stalls.log, never to the
-- console. Read it to see which card or key stalls. Every 10 minutes a health line adds the
-- Lua memory and the background commands still running, so a leak shows as a number growing.

local shell = require("shell")
local stalls = require("stalls")

local feature = {}

feature.PATH = shell.STATE_DIR .. "/stalls.log"

-- Seconds the Mac has been awake: hs.timer.absoluteTime stops while it sleeps, unlike the
-- wall clock, so a sleep, however short, never reads as a stall. The wall clock is read too,
-- so the gap around a sleep, the few hundred ms of waking, isn't one either.
local function awakeSeconds()
  return hs.timer.absoluteTime() / 1e9
end

local last, wallLast = awakeSeconds(), hs.timer.secondsSinceEpoch()

local function tick()
  local now, wallNow = awakeSeconds(), hs.timer.secondsSinceEpoch()
  local gap = stalls.gap(last, now, wallLast, wallNow)
  last, wallLast = now, wallNow
  if not gap then return end
  stalls.append(feature.PATH, stalls.line(os.date("%Y-%m-%d %H:%M:%S"), gap, shell.openName()))
end

-- A full collection first, so the memory is what's still held, not what's waiting to be freed:
-- only then does a leak show as a number that keeps rising.
local function health()
  collectgarbage("collect")
  stalls.append(feature.PATH, stalls.healthLine(os.date("%Y-%m-%d %H:%M:%S"), collectgarbage("count"), shell.runningCount()))
end

os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
-- Kept on the feature, so they aren't garbage-collected.
feature.timer = hs.timer.doEvery(stalls.TICK, tick)
feature.healthTimer = hs.timer.doEvery(stalls.HEALTH_SECONDS, health)
health()

return feature
