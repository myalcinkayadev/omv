-- Behavior of the Pomodoro break cards. Run through pomo_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local pomo = require("pomo")
local card = require("card")

local function ids(screen)
  local result = {}
  for _, row in ipairs(screen.rows) do result[#result + 1] = row.id end
  return table.concat(result, ",")
end

local done = pomo.doneScreen({ task = "write tests", count = 2, postponed = false })
check.that("should title the done card Time for a break", done.title == "Time for a break.")
check.that("should show the task and its length on the done card", done.sub == "write tests · 25 minutes")
check.that("should show the count on the done card", done.kicker == "POMODORO DONE · 2 OF 4 TODAY")
check.that("should select Start break first on the done card", done.rows[done.selected].id == "break.start")
check.that("should offer 5 more minutes once per pomo", ids(done) == "break.start,pomo.postpone,break.skip")
check.that("should leave out 5 more minutes after postponing",
  ids(pomo.doneScreen({ task = "write tests", count = 2, postponed = true })) == "break.start,break.skip")

local brk = pomo.breakScreen({ ends = 1300, seconds = 300, count = 2, tip = 1 })
check.that("should end the break card with End break early", ids(brk) == "break.end")
check.that("should count the break down to its end time", brk.countdown.ends == 1300 and brk.countdown.seconds == 300)
check.that("should show a tip on the break card", brk.tip == pomo.tip(1))
check.that("should rotate the tip each break", pomo.tip(1) ~= pomo.tip(2) and pomo.tip(1) == pomo.tip(1 + #pomo.TIPS))

local over = pomo.overScreen({ task = "write tests", count = 2 })
check.that("should ask Back to work? when the break is over", over.title == "Back to work?")
check.that("should name the next task on the back-to-work card", over.sub == "Next: write tests")
check.that("should select Start next pomo first", ids(over) == "pomo.next,pomo.stop" and over.selected == 1)
check.that("should name the next pomo Pomodoro when the break had no task", pomo.overScreen({ count = 0 }).sub == "Next: Pomodoro")

check.that("should show the count as dots, 4 per row", pomo.dots(2).filled == 2 and pomo.dots(2).total == 4)
check.that("should add a row of dots past 4", pomo.dots(5).total == 8)

local record = pomo.finished(pomo.decode(""), "2026-11-08")
record = pomo.finished(record, "2026-11-08")
check.that("should count finished pomos for today", pomo.countFor(pomo.decode(pomo.encode(record)), "2026-11-08") == 2)
check.that("should start the count over on a new day", pomo.countFor(record, "2026-11-09") == 0)
check.that("should restart at 1 when a pomo finishes on a new day", pomo.countFor(pomo.finished(record, "2026-11-09"), "2026-11-09") == 1)

local page = card.big(done)
check.that("should render the large card over a dimmed background", check.contains(page, "class=\"big\""))
check.that("should render the large card's title", check.contains(page, "Time for a break."))
check.that("should render the countdown with its end time, for the page to tick",
  check.contains(card.big(brk), 'data-ends="1300"') and check.contains(card.big(brk), 'data-seconds="300"'))

local function keyOf(screen, id)
  for _, row in ipairs(screen.rows) do if row.id == id then return row.key, row.hint end end
end
check.that("should give Start break the key B", keyOf(done, "break.start") == "b" and select(2, keyOf(done, "break.start")) == "b")
check.that("should give 5 more minutes the key R", keyOf(done, "pomo.postpone") == "r")
check.that("should give Skip break the key C", keyOf(done, "break.skip") == "c")
check.that("should give End break early the key C", keyOf(brk, "break.end") == "c")
check.that("should give Done for now the key C", keyOf(over, "pomo.stop") == "c")
check.that("should pick a row by its letter key", check.contains(card.big(done), 'data-key="b"'))

check.finish()
