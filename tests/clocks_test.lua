-- Behavior of the calendar card's world clocks file and rows. Run through clocks_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local clocks = require("clocks")
local calendar = require("calendar")

local nyc = clocks.parse("NYC = America/New_York\n")
check.that("should read a name when the line is NYC = America/New_York", nyc[1] and nyc[1].name == "NYC")
check.that("should read a zone when the line is NYC = America/New_York", nyc[1] and nyc[1].zone == "America/New_York")

local ordered = clocks.parse("Tokyo = Asia/Tokyo\nNYC = America/New_York\nDelhi = Asia/Kolkata\n")
check.that("should keep the file's order when there are several lines",
  ordered[1].name == "Tokyo" and ordered[2].name == "NYC" and ordered[3].name == "Delhi")

check.that("should skip a line when it has no =", #clocks.parse("Asia/Tokyo\n") == 0)
check.that("should skip a line when its name is empty", #clocks.parse(" = Asia/Tokyo\n") == 0)
check.that("should skip a line when its zone is empty", #clocks.parse("Tokyo =  \n") == 0)
check.that("should skip a line when it is a comment", #clocks.parse("# NYC = America/New_York\n") == 0)
check.that("should skip blank lines when they sit between clocks", #clocks.parse("\n\nNYC = America/New_York\n\n  \nTokyo = Asia/Tokyo") == 2)
check.that("should trim spaces when they surround the name and zone", (function()
  local clock = clocks.parse("   São Paulo   =   America/Sao_Paulo   ")[1]
  return clock.name == "São Paulo" and clock.zone == "America/Sao_Paulo"
end)())
check.that("should read nothing when there's no file", #clocks.parse(nil) == 0)
check.that("should keep at most eight clocks when the file lists more", (function()
  local lines = {}
  for index = 1, 12 do lines[index] = "Zone" .. index .. " = UTC" end
  return #clocks.parse(table.concat(lines, "\n")) == 8
end)())

check.that("should show no clocks section when there are no clocks", clocks.html({}) == "")
check.that("should show no clocks section when there's no file", clocks.html(clocks.parse(nil)) == "")
check.that("should add no height when there are no clocks", clocks.height({}) == 0 and clocks.height(nil) == 0)
check.that("should grow by a title and one line per clock when there are clocks",
  clocks.height(ordered) == 10 + 4 * 22)

local page = clocks.html(clocks.parse('<b>Home</b> = Europe/"Istanbul"'))
check.that("should escape a name when it holds HTML", check.contains(page, "&lt;b&gt;Home&lt;/b&gt;"))
check.that("should escape a zone when it holds a quote", check.contains(page, 'data-zone="Europe/&quot;Istanbul&quot;"'))
check.that("should title the section Clocks when there are clocks", check.contains(check.visible(page), "Clocks"))
check.that("should include the script that fills in the times when there are clocks", check.contains(page, "function omvClock("))

local today = { year = 2026, month = 11, day = 7 }
local november = calendar.month(2026, 11, today)
check.that("should keep the card's height when there are no clocks", calendar.height(nil, 0, {}) == 384)
check.that("should add the clocks to the card's height when there are clocks", calendar.height(nil, 0, nyc) == 384 + 10 + 2 * 22)
check.that("should put the clocks in the card when there are clocks",
  check.contains(calendar.html(november, today, nil, 0, nyc), 'data-zone="America/New_York"'))
check.that("should leave the clocks out of the card when there are none",
  not check.contains(calendar.html(november, today, nil, 0, nil), "class=clocks"))

check.finish()
