-- Behavior of the capture menu's rows and commands. Run through capture_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local capture = require("capture")

local function labels(screen)
  local result = {}
  for _, row in ipairs(screen.rows) do result[#result + 1] = row.label end
  return table.concat(result, ",")
end

local time = os.time({ year = 2026, month = 11, day = 7, hour = 21, min = 40, sec = 5 })
local function command(id)
  local program, arguments = capture.command(id, "/Users/me", "/x/capture.sh", time)
  return program .. " " .. table.concat(arguments, " ")
end

check.that("should list the six capture rows in order", labels(capture.screen()) ==
  "Region to clipboard,Region to file,Window to clipboard,Screen to clipboard,Text from screen,Pick a color")
check.that("should name a screenshot file with the date and time",
  capture.fileName(time) == "Screenshot 2026-11-07 at 21.40.05.png")
check.that("should copy a selected region", command("region.clipboard") == "/usr/sbin/screencapture -i -c")
check.that("should save a selected region to the Desktop",
  command("region.file") == "/usr/sbin/screencapture -i /Users/me/Desktop/Screenshot 2026-11-07 at 21.40.05.png")
check.that("should copy a picked window", command("window.clipboard") == "/usr/sbin/screencapture -i -W -c")
check.that("should copy the whole screen", command("screen.clipboard") == "/usr/sbin/screencapture -c")
check.that("should read text through the capture script", command("text") == "/x/capture.sh text")
check.that("should pick a color through the capture script", command("color") == "/x/capture.sh color")
check.that("should return nothing for an unknown row", capture.command("nope", "/Users/me", "/x/capture.sh", time) == nil)

check.finish()
