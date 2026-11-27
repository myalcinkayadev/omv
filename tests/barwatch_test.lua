-- Behavior of the bar watchdog: when it starts SketchyBar again, and the line it writes.
-- Run through barwatch_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local barwatch = require("barwatch")

local UP = { bar = true, aerospace = true }
local GONE = { bar = false, aerospace = true }

-- Feeds checks, { seen, time }, to a fresh watchdog; gives each check's action, "-" for none.
local function run(checks)
  local state, actions = barwatch.new(), {}
  for _, step in ipairs(checks) do actions[#actions + 1] = barwatch.check(state, step[1], step[2]) or "-" end
  return table.concat(actions, " ")
end

check.that("should not start the bar while it runs", run({ { UP, 0 }, { UP, 5 }, { UP, 60 } }) == "- - -")
check.that("should not start the bar before it has been gone 10 s", run({ { GONE, 0 }, { GONE, 9 } }) == "- -")
check.that("should start the bar after it has been gone 10 s", run({ { GONE, 0 }, { GONE, 10 } }) == "- start")
check.that("should not start the bar when AeroSpace isn't running",
  run({ { { bar = false, aerospace = false }, 0 }, { { bar = false, aerospace = false }, 60 } }) == "- -")
check.that("should wait 60 s before starting it again when a start didn't bring it back",
  run({ { GONE, 0 }, { GONE, 10 }, { GONE, 40 }, { GONE, 70 } }) == "- start - start")
check.that("should start again 10 s after a new exit once the bar came back",
  run({ { GONE, 0 }, { GONE, 10 }, { UP, 15 }, { GONE, 20 }, { GONE, 30 } }) == "- start - - start")
check.that("should count the gone time from when it was first missed",
  run({ { UP, 0 }, { GONE, 3 }, { GONE, 8 }, { GONE, 13 } }) == "- - - start")
check.that("should give how long the bar was gone with a start", select(2, (function()
  local state = barwatch.new()
  barwatch.check(state, GONE, 0)
  return barwatch.check(state, GONE, 12)
end)()) == 12)
check.that("should say how long the bar was gone",
  barwatch.line("2026-11-27 19:16:03", 12) == "2026-11-27 19:16:03 bar restarted after 12 s gone\n")

check.finish()
