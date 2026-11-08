-- Behavior of today's events: reading agenda.sh's output, the card rows and the bar item.
-- Run through agenda_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local agenda = require("agenda")

local function at(hour, minute)
  return os.time({ year = 2026, month = 11, day = 7, hour = hour, min = minute or 0 })
end

local function line(start, finish, allDay, title)
  return start .. "\t" .. finish .. "\t" .. (allDay and "1" or "0") .. "\t" .. title .. "\n"
end

local day = agenda.decode(
  line(at(14), at(15), false, "Design review")
  .. line(at(9), at(9, 30), false, "Standup")
  .. line(at(0), at(0) + 86400, true, "Republic Day")
  .. line(at(16), at(16, 30), false, ""))

check.that("should read every event", #day.events == 4)
check.that("should list all-day events first, then by start time",
  day.events[1].title == "Republic Day" and day.events[2].title == "Standup" and day.events[3].title == "Design review")
check.that("should read start and end times", day.events[2].start == at(9) and day.events[2].finish == at(9, 30))
check.that("should mark all-day events", day.events[1].allDay and not day.events[2].allDay)
check.that("should name an untitled event Event", day.events[4].title == "Event")
check.that("should not be denied with events", day.denied == false)
check.that("should read denied as refused access", agenda.decode("denied\n").denied == true)
check.that("should read empty output as no events", #agenda.decode("").events == 0)

local rows, more = agenda.rows(day, at(14, 30))
check.that("should show the time of each event", rows[2].time == "09:00" and rows[3].time == "14:00")
check.that("should show all day for all-day events", rows[1].time == "all day")
check.that("should mark events already over", rows[2].past and not rows[3].past)
check.that("should mark the event going on now", rows[3].current and not rows[4].current)
check.that("should leave nothing out when all fit", more == 0 and #rows == 4)

local busy = { events = {} }
for hour = 8, 15 do
  busy.events[#busy.events + 1] = { start = at(hour), finish = at(hour, 30), allDay = false, title = "Meeting " .. hour }
end
rows, more = agenda.rows(busy, at(12, 45))
check.that("should list at most five events", #rows == 5 and more == 3)
check.that("should leave out events already over first", rows[1].title == "Meeting 11" and rows[5].title == "Meeting 15")

check.that("should show nothing in the bar more than an hour before", agenda.bar(day.events, at(12, 59)) == nil)
local meeting = agenda.bar(day.events, at(13, 30))
check.that("should show the next meeting's start time within the hour", meeting and meeting.label == "14:00")
check.that("should keep the meeting title out of the bar", meeting and not meeting.label:find("Design", 1, true))
check.that("should not mark a meeting soon 30 minutes ahead", meeting and not meeting.soon)
check.that("should mark a meeting soon from 5 minutes before", agenda.bar(day.events, at(13, 55)).soon)
check.that("should keep the meeting until 5 minutes after it started", agenda.bar(day.events, at(14, 4)).soon)
check.that("should move on 5 minutes after it started", agenda.bar(day.events, at(14, 5)) == nil)
check.that("should leave all-day events out of the bar", agenda.bar({ day.events[1] }, at(0, 30)) == nil)

check.finish()
