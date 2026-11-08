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
check.that("should format time left as h:mm from an hour up", reminders.left(2 * 3600 + 5 * 60 + 30) == "2:05")

local now = 1000
local list = {
  { due = now + 600, text = "later" },
  { due = now + 90, text = "soon" },
  { due = now + 3000, text = "last" },
}
check.that("should show the soonest time left in the bar", reminders.label(list, now) == "1:30 +2")
check.that("should leave out the count with one reminder", reminders.label({ list[2] }, now) == "1:30")
check.that("should keep the reminder text out of the bar", not check.contains(reminders.label(list, now), "soon"))
check.that("should cut a due reminder's text at 10 characters", reminders.short("check the deploy pipeline") == "check the…")
check.that("should keep a short text whole", reminders.short("stand up") == "stand up")
check.that("should give an empty label with no reminders", reminders.label({}, now) == "")

local saved = reminders.decode(reminders.encode(list), now)
check.that("should save and reload reminders unchanged", #saved == 3 and saved[1].text == "soon" and saved[1].due == now + 90)
check.that("should keep text with tabs and newlines on one line",
  reminders.decode(reminders.encode({ { due = now + 5, text = "a\tb\nc" } }), now)[1].text == "a b c")
check.that("should drop reminders already past when reloading",
  #reminders.decode(reminders.encode({ { due = now - 1, text = "gone" }, { due = now + 1, text = "kept" } }), now) == 1)

local input = card.html({ prompt = "Remind me…", rows = {}, input = true, hint = "25m check deploy" })
check.that("should mark a card that takes typed input", check.contains(input, "data-input"))
check.that("should show the input hint", check.contains(input, "25m check deploy"))

local kinds = reminders.decode(reminders.encode({ { due = 2000, text = "Break", kind = "break" }, { due = 3000, text = "call" } }), 1000)
check.that("should resume a break saved before a reload", kinds[1].kind == "break")
check.that("should reload a plain reminder without a kind", kinds[2].kind == nil)
check.that("should read reminders saved before kinds existed", reminders.decode("2000\tcall", 1000)[1].text == "call")

check.that("should show a coffee cup in the bar during a break", reminders.icon({ { due = 1, text = "Break", kind = "break" } }) == "\u{F0176}")
check.that("should show a target in the bar during a pomo", reminders.icon({ { due = 1, text = "write tests", kind = "pomo" } }) == "\u{F08C9}")
check.that("should show a target for a postponed pomo", reminders.icon({ { due = 1, text = "write tests", kind = "postponed" } }) == "\u{F08C9}")
check.that("should show the timer for a plain reminder", reminders.icon({ { due = 1, text = "call" } }) == "\u{F051B}")
check.that("should pick the icon from the soonest reminder",
  reminders.icon({ { due = 9, text = "call" }, { due = 2, text = "write tests", kind = "pomo" } }) == "\u{F08C9}")

check.finish()
