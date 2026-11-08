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
check.that("should pick the session waiting longest", claudewait.oldest(sessions, alive).folder == "omv")
check.that("should skip a session whose Claude has ended", claudewait.oldest(sessions, alive).pid ~= 3)
check.that("should pick nothing when every Claude has ended", claudewait.oldest(sessions, function() return false end) == nil)
check.that("should pick nothing when no session waits", claudewait.oldest({}, alive) == nil)

check.that("should focus the Ghostty terminal on that tty",
  claudewait.focusScript("/dev/ttys009") == 'tell application "Ghostty" to focus (first terminal whose tty is "/dev/ttys009")')
check.that("should give no script for a session outside a terminal", claudewait.focusScript("-") == nil)
check.that("should give no script for a tty that is not a plain device path",
  claudewait.focusScript('/dev/ttys1" & do shell script "x') == nil)

check.finish()
