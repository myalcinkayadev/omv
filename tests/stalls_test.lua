-- Behavior of the stall detector: which gaps count and the lines it writes.
-- Run through stalls_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local stalls = require("stalls")

check.that("should count a gap as a stall when it's over the limit", stalls.gap(10, 10.4) ~= nil)
check.that("should give the stall's length when it's over the limit", math.abs(stalls.gap(10, 10.4) - 0.4) < 1e-9)
check.that("should count nothing when the gap is under the limit", stalls.gap(10, 10.1) == nil)
check.that("should count nothing when the gap is the limit", stalls.gap(0, stalls.LIMIT) == nil)
check.that("should count a gap of a minute as a stall, since sleep never shows on the awake clock", stalls.gap(10, 70) ~= nil)
check.that("should give a long stall's full length", math.abs(stalls.gap(10, 50) - 40) < 1e-9)

check.that("should write the time, the length in ms and the card", stalls.line("12:00:01", 1.2345, "agents") == "12:00:01  1235 ms agents\n")
check.that("should write no card when none is showing", stalls.line("12:00:01", 0.3, "") == "12:00:01   300 ms no card\n")

local path = os.tmpname()
stalls.append(path, "a\n")
stalls.append(path, "b\n")
local file = io.open(path)
local text = file:read("*a")
file:close()
os.remove(path)
check.that("should add each line to the end of the log", text == "a\nb\n")
check.that("should fail quietly when the log can't be written", stalls.append("/nonexistent/folder/stalls.log", "a\n") == false)

check.that("should write the Lua memory and unfinished tasks in a health line",
  stalls.healthLine("12:00:00", 2048.6, 3) == "12:00:00 health  2049 KB Lua, 3 tasks running\n")
check.that("should write zero tasks when none is running", stalls.healthLine("12:00:00", 10, 0):find("0 tasks running", 1, true) ~= nil)
check.that("should check the health every 10 minutes", stalls.HEALTH_SECONDS == 600)

check.finish()
