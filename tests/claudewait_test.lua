-- Behavior of focusing a waiting Claude session. Run through claudewait_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local claudewait = require("claudewait")

local session = claudewait.parse("4242\t/dev/ttys009\tomv\t100\n")
check.that("should read Claude's PID", session.pid == 4242)
check.that("should read the terminal", session.tty == "/dev/ttys009")
check.that("should read the folder", session.folder == "omv")
check.that("should read when it started waiting", session.since == 100)
check.that("should refuse a line it cannot read", claudewait.parse("garbage") == nil)

local sessions = {
  { pid = 1, tty = "/dev/ttys001", folder = "api", since = 200 },
  { pid = 2, tty = "/dev/ttys002", folder = "omv", since = 100 },
  { pid = 3, tty = "/dev/ttys003", folder = "web", since = 50 },
}
local function alive(pid) return pid ~= 3 end
local rows = claudewait.rows(sessions, alive, 400)
check.that("should list the session waiting longest first", rows[1].label == "omv")
check.that("should list the others after it", rows[2].label == "api")
check.that("should leave out a session whose Claude has ended", #rows == 2)
check.that("should choose a row by its terminal", rows[1].id == "/dev/ttys002")
check.that("should hint how long it has waited", rows[1].hint == "5 min")
check.that("should hint now under a minute",
  claudewait.rows({ { pid = 1, tty = "/dev/ttys001", folder = "api", since = 370 } }, alive, 400)[1].hint == "now")
check.that("should list no rows when every Claude has ended", #claudewait.rows(sessions, function() return false end, 400) == 0)
check.that("should list no rows when no session waits", #claudewait.rows({}, alive, 400) == 0)

check.that("should focus the Ghostty terminal on that tty",
  claudewait.focusScript("/dev/ttys009") == 'tell application "Ghostty" to focus (first terminal whose tty is "/dev/ttys009")')
check.that("should give no script for a session outside a terminal", claudewait.focusScript("-") == nil)
check.that("should give no script for a tty that is not a plain device path",
  claudewait.focusScript('/dev/ttys1" & do shell script "x') == nil)

check.finish()
