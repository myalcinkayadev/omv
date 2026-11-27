-- The bar watchdog: SketchyBar is started once, by AeroSpace, and nothing restarts it, so a
-- bar that exits for any reason stays gone. Checked every CHECK_SECONDS, a bar gone GRACE
-- seconds while AeroSpace runs is started again; a start that didn't bring it back waits
-- RETRY seconds before the next. Without AeroSpace it's left alone: omv uninstall quits
-- AeroSpace before the bar, and quitting it on purpose means no bar either.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local barwatch = {}

barwatch.CHECK_SECONDS, barwatch.GRACE, barwatch.RETRY = 5, 10, 60

-- { missing, the time the bar was first missed; started, the time of the last start }.
function barwatch.new()
  return {}
end

-- What one check does, from seen { bar, aerospace }, whether each runs, at time in seconds:
-- "start" and how long the bar has been gone, or nil.
function barwatch.check(state, seen, time)
  if seen.bar then
    state.missing, state.started = nil, nil
    return nil
  end
  if not seen.aerospace then return nil end
  state.missing = state.missing or time
  local gone = time - state.missing
  if gone < barwatch.GRACE then return nil end
  if state.started and time - state.started < barwatch.RETRY then return nil end
  state.started = time
  return "start", gone
end

-- The log line for a start: the time, and how long the bar was gone.
function barwatch.line(time, gone)
  return string.format("%s bar restarted after %d s gone\n", time, math.floor(gone + 0.5))
end

return barwatch
