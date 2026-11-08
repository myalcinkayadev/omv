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
check.that("should say a pomo is done when no text is given", select(2, parsed("pomo")) == "Pomodoro done, take a break")
check.that("should keep the text after pomo", select(2, parsed("pomo write tests")) == "write tests")
check.that("should read pomo in any case", (parsed("  Pomo ")) == 25 * 60)
check.that("should read break as 5 minutes", (parsed("break")) == 5 * 60 and select(2, parsed("break")) == "Break over")
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

check.finish()
