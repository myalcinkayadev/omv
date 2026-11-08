-- Behavior of the calendar card's month grid. Run through calendar_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local calendar = require("calendar")

local today = { year = 2026, month = 11, day = 7 }
local november = calendar.month(2026, 11, today)
local first = november.weeks[1].days
local last = november.weeks[#november.weeks].days

check.that("should title the month with its name and year", november.title == "November 2026")
check.that("should start each week on Monday", first[1].day == 26 and first[7].day == 1)
check.that("should fill the first week with days from the previous month", not first[1].inMonth)
check.that("should fill the last week with days from the next month", last[2].day == 1 and not last[2].inMonth)
check.that("should mark today", november.weeks[2].days[6].today == true)
check.that("should mark only one day as today", (function()
  local count = 0
  for _, week in ipairs(november.weeks) do
    for _, day in ipairs(week.days) do if day.today then count = count + 1 end end
  end
  return count == 1
end)())
check.that("should show six weeks when the month needs only five", #calendar.month(2026, 12, today).weeks == 6)
check.that("should show six weeks when the month needs only four", #calendar.month(2021, 2, today).weeks == 6)
check.that("should mark weekends", first[7].weekend and not first[5].weekend)
check.that("should give each row its ISO week number", november.weeks[2].week == 45)
check.that("should number the last days of 2020 as week 53", calendar.month(2020, 12, today).weeks[5].week == 53)
check.that("should not mark today in another month", calendar.month(2026, 10, today).weeks[1].days[1].today == false)

local year, month = calendar.shift(2026, 12, 1)
check.that("should go from December to January of the next year", year == 2027 and month == 1)
year, month = calendar.shift(2026, 1, -1)
check.that("should go from January to December of the previous year", year == 2025 and month == 12)

local page = calendar.html(november, today)
check.that("should show today's full date in the footer", check.contains(check.visible(page), "Saturday, 7 November"))
check.that("should show this week's number in the footer", check.contains(page, "week 45"))

check.that("should list nothing before the events are read", not check.contains(page, "class=agenda"))
check.that("should keep its height before the events are read", calendar.height(nil, 0) == 384)

local function at(hour, minute)
  return os.time({ year = 2026, month = 11, day = 7, hour = hour, min = minute })
end
local day = { denied = false, events = {
  { start = at(9, 0), finish = at(9, 30), allDay = false, title = "Standup" },
  { start = at(14, 0), finish = at(15, 0), allDay = false, title = "Design <review>" },
} }
local withEvents = calendar.html(november, today, day, at(10, 0))
check.that("should list today's events under the footer",
  check.contains(check.visible(withEvents), "09:00Standup") and check.contains(check.visible(withEvents), "14:00Design"))
check.that("should escape event titles", check.contains(withEvents, "Design &lt;review&gt;"))
check.that("should dim events already over", check.contains(withEvents, "event past\"><span class=time>09:00"))
check.that("should grow by one line per event", calendar.height(day, at(10, 0)) == 384 + 10 + 2 * 22)
check.that("should say when there are no events today",
  check.contains(calendar.html(november, today, { denied = false, events = {} }, at(10, 0)), "No events today"))
check.that("should ask for Calendar access when it was refused",
  check.contains(calendar.html(november, today, { denied = true, events = {} }, at(10, 0)), "Allow Calendar access"))

check.finish()
