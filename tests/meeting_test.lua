-- Behavior of meeting mode: when it starts, what it changes and what leaving undoes.
-- Run through meeting_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local meeting = require("meeting")

local NOW = 1000000
local call = { start = NOW - 60, finish = NOW + 1800, allDay = false, title = "Standup", link = "https://meet.google.com/abc" }
local noLink = { start = NOW - 60, finish = NOW + 1800, allDay = false, title = "Focus time" }

check.that("should start for a meeting with a call link that just started", meeting.due({ call }, NOW, {}) == call)
check.that("should not start for an event without a call link", meeting.due({ noLink }, NOW, {}) == nil)
check.that("should not start for an all-day event",
  meeting.due({ { start = NOW - 60, finish = NOW + 60, allDay = true, title = "x", link = "https://meet.google.com/a" } }, NOW, {}) == nil)
check.that("should not start before the meeting starts",
  meeting.due({ { start = NOW + 60, finish = NOW + 600, title = "x", link = "https://meet.google.com/a" } }, NOW, {}) == nil)
check.that("should not start after the meeting ended",
  meeting.due({ { start = NOW - 600, finish = NOW, title = "x", link = "https://meet.google.com/a" } }, NOW, {}) == nil)
check.that("should not start for a meeting that started more than 5 minutes ago",
  meeting.due({ { start = NOW - meeting.LATE - 1, finish = NOW + 600, title = "x", link = "https://meet.google.com/a" } }, NOW, {}) == nil)
check.that("should not start again for a meeting already handled", meeting.due({ call }, NOW, { [meeting.key(call)] = true }) == nil)
check.that("should start for nothing without events", meeting.due(nil, NOW, {}) == nil)

local other = { start = NOW - 30, finish = NOW + 900, title = "1:1", link = "https://zoom.us/j/1" }
check.that("should find the joined meeting by its link", meeting.joined({ call, other }, NOW, "https://zoom.us/j/1") == other)
check.that("should fall back to the meeting running now", meeting.joined({ call }, NOW, "https://elsewhere.test") == call)
check.that("should find a meeting about to start when you join early",
  meeting.joined({ { start = NOW + 120, finish = NOW + 900, title = "x", link = "https://meet.google.com/a" } }, NOW, nil) ~= nil)
check.that("should find no meeting when none runs", meeting.joined({ noLink }, NOW, nil) == nil)

local apps = meeting.apps("com.apple.MobileSMS\nnet.whatsapp.WhatsApp\ncom.apple.MobileSMS\n\ncom.spotify.client\n")
check.that("should list each app once", #apps == 3)
check.that("should keep the apps' order", apps[1] == "com.apple.MobileSMS" and apps[3] == "com.spotify.client")
check.that("should list no apps without output", #meeting.apps(nil) == 0)

local record = meeting.enter({ focusOn = false, playing = { "Spotify" }, shown = { "com.apple.MobileSMS" } })
check.that("should turn Do Not Disturb on when it was off", record.focus == true)
check.that("should leave Do Not Disturb alone when it was on already", meeting.enter({ focusOn = true }).focus == false)
check.that("should pause the players that play", record.paused[1] == "Spotify")
check.that("should hide the apps shown on the chat and music workspaces", record.hidden[1] == "com.apple.MobileSMS")

local left = meeting.leave(record, { focusOn = true, paused = { "Spotify" } })
check.that("should turn Do Not Disturb off when entering turned it on", left.focus == true)
check.that("should leave Do Not Disturb on when it was on before the meeting",
  meeting.leave(meeting.enter({ focusOn = true }), { focusOn = true }).focus == false)
check.that("should not switch Do Not Disturb when you turned it off already", meeting.leave(record, { focusOn = false, paused = {} }).focus == false)
check.that("should resume a player it paused", left.resume[1] == "Spotify")
check.that("should not resume a player you started again", #meeting.leave(record, { focusOn = true, paused = {} }).resume == 0)
check.that("should not resume a player it never paused",
  #meeting.leave(meeting.enter({ focusOn = false }), { focusOn = false, paused = { "Music" } }).resume == 0)
check.that("should show again the apps it hid", left.unhide[1] == "com.apple.MobileSMS")

check.finish()
