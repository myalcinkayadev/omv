-- Behavior of quick reminders: reading what you type, the bar label and the saved file.
-- Run through reminders_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local reminders = require("reminders")
local card = require("card")

local function parsed(text)
  local seconds, message = reminders.parse(text)
  return seconds, message
end

check.that("should read 25m as 25 minutes", (parsed("25m check deploy")) == 25 * 60)
check.that("should read 1h30m as 90 minutes", (parsed("1h30m stand up")) == 90 * 60)
check.that("should read 45s as 45 seconds", (parsed("45s tea")) == 45)
check.that("should keep the text after the duration", select(2, parsed("25m check deploy")) == "check deploy")
check.that("should name a reminder without text Reminder", select(2, parsed("10m")) == "Reminder")
check.that("should refuse text without a duration", parsed("check deploy") == nil)
check.that("should refuse a zero duration", parsed("0m nothing") == nil)
check.that("should refuse a duration glued to the text", parsed("25mcheck") == nil)
check.that("should read pomo as 25 minutes", (parsed("pomo")) == 25 * 60)
check.that("should name a pomo without text Pomodoro", select(2, parsed("pomo")) == "Pomodoro")
check.that("should keep the text after pomo", select(2, parsed("pomo write tests")) == "write tests")
check.that("should read pomo in any case", (parsed("  Pomo ")) == 25 * 60)
check.that("should read break as 5 minutes", (parsed("break")) == 5 * 60)
check.that("should give typed pomo the pomo kind", select(3, reminders.parse("pomo write tests")) == "pomo")
check.that("should give typed break the break kind", select(3, reminders.parse("break")) == "break")
check.that("should give a timed reminder no kind", select(3, reminders.parse("25m check deploy")) == nil)
check.that("should refuse a word that is not a preset", parsed("pomodoro") == nil)
check.that("should refuse a preset glued to the text", parsed("pomo25") == nil)

check.that("should format time left as m:ss under an hour", reminders.left(24 * 60 + 13) == "24:13")
check.that("should format time left as 2h05 when an hour or more", reminders.left(2 * 3600 + 5 * 60 + 30) == "2h05")
check.that("should pad the minutes when an hour or more", reminders.left(3600 + 5 * 60) == "1h05")
check.that("should show 0:00 when the time has passed", reminders.left(-30) == "0:00")
check.that("should phrase a list row's time left as in 12 min when under an hour", reminders.leftIn(12 * 60) == "in 12 min")
check.that("should phrase a list row's time left as in 1h35 when an hour or more", reminders.leftIn(95 * 60) == "in 1h35")
check.that("should say in 1 min rather than in 0 min when under a minute is left", reminders.leftIn(20) == "in 1 min")

local now = 1000
local list = {
  { due = now + 600, text = "later" },
  { due = now + 90, text = "soon" },
  { due = now + 3000, text = "last" },
}
check.that("should show the soonest time left in the bar", reminders.label(list, now) == "1:30 +2")
check.that("should leave out the count with one reminder", reminders.label({ list[2] }, now) == "1:30")
check.that("should show the bar label with hours as 1h30 +2",
  reminders.label({ { due = now + 5400 }, { due = now + 6000 }, { due = now + 7000 } }, now) == "1h30 +2")
check.that("should keep the reminder text out of the bar", not check.contains(reminders.label(list, now), "soon"))
check.that("should cut a due reminder's text at 10 characters", reminders.short("check the deploy pipeline") == "check the…")
check.that("should keep a short text whole", reminders.short("stand up") == "stand up")
check.that("should give an empty label with no reminders", reminders.label({}, now) == "")

local saved = reminders.decode(reminders.encode(list), now)
check.that("should save and reload reminders unchanged", #saved == 3 and saved[1].text == "soon" and saved[1].due == now + 90)
check.that("should keep text with tabs and newlines on one line",
  reminders.decode(reminders.encode({ { due = now + 5, text = "a\tb\nc" } }), now)[1].text == "a b c")
check.that("should still drop a missed Pomodoro or break when reloading",
  #reminders.decode(reminders.encode({ { due = now - 1, text = "write tests", kind = "pomo" }, { due = now - 1, text = "Break", kind = "break" } }), now) == 0)

local input = card.html({ prompt = "Remind me…", rows = {}, input = true, hint = "25m check deploy" })
check.that("should mark a card that takes typed input", check.contains(input, "data-input"))
check.that("should show the input hint", check.contains(input, "25m check deploy"))

local kinds = reminders.decode(reminders.encode({ { due = 2000, text = "Break", kind = "break" }, { due = 3000, text = "call" } }), 1000)
check.that("should resume a break saved before a reload", kinds[1].kind == "break")
check.that("should reload a plain reminder without a kind", kinds[2].kind == nil)
check.that("should read reminders saved before kinds existed", reminders.decode("2000\tcall", 1000)[1].text == "call")

local long = reminders.decode(reminders.encode({ { due = 2000, text = "Break", kind = "break", length = 900 } }), 1000)
check.that("should keep a break's length when saved and read back", long[1].length == 900)
check.that("should read a break saved before lengths existed", reminders.decode("2000\tBreak\tbreak", 1000)[1].kind == "break")

check.that("should show a coffee cup in the bar during a break", reminders.icon({ { due = 1, text = "Break", kind = "break" } }) == "\u{F0176}")
check.that("should show a target in the bar during a pomo", reminders.icon({ { due = 1, text = "write tests", kind = "pomo" } }) == "\u{F08C9}")
check.that("should show a target for a postponed pomo", reminders.icon({ { due = 1, text = "write tests", kind = "postponed" } }) == "\u{F08C9}")
check.that("should show the timer for a plain reminder", reminders.icon({ { due = 1, text = "call" } }) == "\u{F051B}")
check.that("should pick the icon from the soonest reminder",
  reminders.icon({ { due = 9, text = "call" }, { due = 2, text = "write tests", kind = "pomo" } }) == "\u{F08C9}")

check.that("should read r 25m check deploy like 25m check deploy",
  (parsed("r 25m check deploy")) == 25 * 60 and select(2, parsed("r 25m check deploy")) == "check deploy")
check.that("should read b as a 5-minute break", (parsed("b")) == 5 * 60 and select(3, reminders.parse("b")) == "break")
check.that("should read c as cancel", select(3, reminders.parse("c")) == "cancel" and parsed("c") == nil)
check.that("should still refuse an unknown single letter", parsed("x") == nil and select(3, reminders.parse("x")) == nil)

check.that("should not leave a space before the ellipsis", reminders.short("Pomodoro done, take a break") == "Pomodoro…")

-- A due reminder stays until it is dealt with, and one missed while Hammerspoon was off still fires.
local missed = reminders.decode(reminders.encode({ { due = now - 60, text = "call the bank" } }), now)
check.that("should keep a missed reminder as due when reloaded", missed[1] and reminders.isDue(missed[1]))
check.that("should mark a missed reminder as late", missed[1].kind == "late")
check.that("should say a missed reminder is new, so it is announced once", missed[1].missed == true)
local again = reminders.decode(reminders.encode(missed), now + 600)
check.that("should not announce a late reminder again on the next reload", again[1].kind == "late" and not again[1].missed)

local fired = reminders.fire({ due = now, text = "stand up" })
check.that("should keep a due reminder until it is dismissed", reminders.isDue(fired) and fired.text == "stand up")
local saved = reminders.decode(reminders.encode({ fired }), now + 3600)
check.that("should save and reload due reminders unchanged", saved[1].kind == "due" and saved[1].text == "stand up")
check.that("should not count a waiting reminder as due", not reminders.isDue({ due = now + 60, text = "later" }))

local mixed = {
  { due = now - 300, text = "older due", kind = "due" },
  { due = now - 100, text = "newer due", kind = "late" },
  { due = now + 600, text = "waiting" },
}
check.that("should show the oldest due reminder's text in the bar", reminders.dueLabel(mixed) == "older due +1")
check.that("should give no due label when nothing is due", reminders.dueLabel({ { due = now + 60, text = "later" } }) == nil)
check.that("should leave due reminders out of the countdown", reminders.label(mixed, now) == "10:00")
check.that("should list due reminders oldest first", reminders.dueList(mixed)[1].text == "older due")

local snoozed = reminders.snooze(mixed[1], now, 5 * 60)
check.that("should snooze a due reminder for 5 minutes", snoozed.due == now + 300 and not reminders.isDue(snoozed))
check.that("should keep a snoozed reminder's text", snoozed.text == "older due")
check.that("should snooze a due reminder for 15 minutes", reminders.snooze(mixed[1], now, 15 * 60).due == now + 900)

local function at(hour, minute)
  return os.time({ year = 2026, month = 11, day = 11, hour = hour, min = minute, sec = 0 })
end
local lateScreen = reminders.dueScreen({ due = at(14, 5), text = "call the bank", kind = "late" })
check.that("should mark a missed reminder as late, with its time", check.contains(lateScreen.kicker, "LATE · WAS 14:05"))
check.that("should title the due card with the reminder", lateScreen.title == "call the bank")
check.that("should offer Dismiss first on the due card", lateScreen.rows[lateScreen.selected].id == "due.dismiss")
check.that("should give Snooze 5 minutes the key S", lateScreen.rows[2].id == "due.snooze5" and lateScreen.rows[2].key == "s")
check.that("should offer Snooze 15 minutes", lateScreen.rows[3].id == "due.snooze15")

-- Clock times: "14:30 call" is the time until 14:30, tomorrow when already past.
local noon = at(12, 0)
local seconds, message = reminders.parse("14:30 call", noon)
check.that("should read 14:30 as the time until 14:30 today", seconds == at(14, 30) - noon)
check.that("should keep the text after the clock time", message == "call")
check.that("should read a clock time already past as tomorrow",
  (reminders.parse("09:00 stand up", noon)) == os.time({ year = 2026, month = 11, day = 12, hour = 9, min = 0, sec = 0 }) - noon)
check.that("should read 9:05 with a single-digit hour", (reminders.parse("9:05 tea", at(8, 0))) == 65 * 60)
check.that("should name a clock reminder without text Reminder", select(2, reminders.parse("14:30", noon)) == "Reminder")
check.that("should refuse 25:00", reminders.parse("25:00 call", noon) == nil)
check.that("should refuse 14:60", reminders.parse("14:60 call", noon) == nil)
check.that("should read a clock time after r", (reminders.parse("r 14:30 call", noon)) == at(14, 30) - noon)
check.that("should keep reading 25m with a clock passed in", (reminders.parse("25m check", noon)) == 25 * 60)

check.finish()
