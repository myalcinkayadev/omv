-- Finds where Hammerspoon's thread stalls. A timer that should fire every TICK seconds
-- fires late when something on the thread blocks it, as hs.execute does; a gap over LIMIT is
-- one stall, written as a line with the time, its length and the card showing. Every
-- HEALTH_SECONDS a health line follows, to catch a slow leak.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local stalls = {}

stalls.TICK = 0.05
stalls.LIMIT = 0.25
-- How often a health line is written, so something growing over hours shows in the log.
stalls.HEALTH_SECONDS = 600

-- The stall between two ticks at last and now, in seconds, or nil when the gap is short.
function stalls.gap(last, now)
  local gap = now - last
  if gap <= stalls.LIMIT then return nil end
  return gap
end

-- One log line: the time the stall ended, its length in milliseconds and the card showing.
function stalls.line(time, gap, card)
  local where = (card and card ~= "") and card or "no card"
  return string.format("%s %5d ms %s\n", time, math.floor(gap * 1000 + 0.5), where)
end

-- A health line: the Lua memory in KB and the background commands still running.
function stalls.healthLine(time, memoryKb, tasks)
  return string.format("%s health %5d KB Lua, %d tasks running\n", time, math.floor(memoryKb + 0.5), tasks)
end

-- Appends line to the file at path. Fails quietly: a log that can't be written is no reason
-- to print, which is what the stalls come from.
function stalls.append(path, line)
  local ok, file = pcall(io.open, path, "a")
  if not ok or not file then return false end
  file:write(line)
  file:close()
  return true
end

return stalls
