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

check.that("should list the capture rows in order", labels(capture.screen()) ==
  "Region to clipboard,Region to file,Window to clipboard,Screen to clipboard,Text from screen,QR code from screen,"
  .. "Pick a color,Record a region,Record the screen")
check.that("should name a screenshot file with the date and time",
  capture.fileName(time) == "Screenshot 2026-11-07 at 21.40.05.png")
check.that("should copy a selected region", command("region.clipboard") == "/usr/sbin/screencapture -i -c")
check.that("should save a selected region to the Desktop",
  command("region.file") == "/usr/sbin/screencapture -i /Users/me/Desktop/Screenshot 2026-11-07 at 21.40.05.png")
check.that("should copy a picked window", command("window.clipboard") == "/usr/sbin/screencapture -i -W -c")
check.that("should copy the whole screen", command("screen.clipboard") == "/usr/sbin/screencapture -c")
check.that("should read text through the capture script", command("text") == "/x/capture.sh text")
check.that("should pick a color through the capture script", command("color") == "/x/capture.sh color")
check.that("should read a QR code through the capture script", command("qr") == "/x/capture.sh qr")
check.that("should name a recording file with the date and time",
  capture.recordingName(time) == "Screen Recording 2026-11-07 at 21.40.05.mov")
check.that("should record a selected region to the Desktop through the capture script",
  command("record.region") == "/x/capture.sh record /Users/me/Desktop/Screen Recording 2026-11-07 at 21.40.05.mov")
check.that("should record the whole screen to the Desktop, showing clicks",
  command("record.screen") == "/usr/sbin/screencapture -v -k /Users/me/Desktop/Screen Recording 2026-11-07 at 21.40.05.mov")
check.that("should record the display it is given",
  table.concat(select(2, capture.command("record.screen", "/Users/me", "/x/capture.sh", time, 2)), " ")
    == "-v -k -D2 /Users/me/Desktop/Screen Recording 2026-11-07 at 21.40.05.mov")
check.that("should mark the recording rows as recordings", capture.isRecording("record.region") and capture.isRecording("record.screen"))
check.that("should not mark a screenshot row as a recording", not capture.isRecording("region.clipboard"))
check.that("should return nothing for an unknown row", capture.command("nope", "/Users/me", "/x/capture.sh", time) == nil)

check.finish()
