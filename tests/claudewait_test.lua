-- Behavior of listing Claude sessions and focusing one. Run through claudewait_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local claudewait = require("claudewait")

local session = claudewait.parse("4242\t/dev/ttys009\tomv\t100\tasks\n")
check.that("should read Claude's PID", session.pid == 4242)
check.that("should read the terminal", session.tty == "/dev/ttys009")
check.that("should read the folder", session.folder == "omv")
check.that("should read when it entered its state", session.since == 100)
check.that("should read the state", session.state == "asks")
check.that("should read a line saved before states existed as done",
  claudewait.parse("4242\t/dev/ttys009\tomv\t100\n").state == "done")
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
check.that("should hint the state and how long it has been in it", rows[1].hint == "done · 5 min")
check.that("should hint now under a minute",
  claudewait.rows({ { pid = 1, tty = "/dev/ttys001", folder = "api", since = 370 } }, alive, 400)[1].hint == "done · now")

local mixed = claudewait.rows({
  { pid = 1, tty = "/dev/ttys001", folder = "working", since = 10, state = "working" },
  { pid = 2, tty = "/dev/ttys002", folder = "done", since = 20, state = "done" },
  { pid = 4, tty = "/dev/ttys004", folder = "asks", since = 300, state = "asks" },
}, alive, 400)
local order = {}
for index, row in ipairs(mixed) do order[index] = row.label end
check.that("should list asking sessions first, then done, then working", table.concat(order, ",") == "asks,done,working")
check.that("should hint an asking session as asks", mixed[1].hint == "asks · 1 min")
check.that("should mark an asking session as waiting", mixed[1].waiting == true)
check.that("should mark a working session as not waiting", mixed[3].waiting == false)
check.that("should keep each row's Claude PID", mixed[1].pid == 4)

-- Claude (100) runs in a login shell in Zed's terminal, as ps reports them.
local chain = {
  [100] = { 90, "claude" },
  [90] = { 80, "-zsh" },
  [80] = { 70, "/usr/bin/login" },
  [70] = { 1, "/Applications/Zed.app/Contents/MacOS/zed" },
}
local function parentIn(processes)
  return function(pid)
    assert(pid > 1, "walked past PID 1")
    local entry = processes[pid]
    if entry then return entry[1], entry[2] end
  end
end
check.that("should pick the nearest ancestor inside an app bundle", claudewait.appPid(100, parentIn(chain)) == 70)
local nested = { [100] = { 75, "claude" }, [75] = { 70, "/Applications/Zed.app/Contents/MacOS/cli" }, [70] = chain[70] }
check.that("should pick the nearest of several app bundles", claudewait.appPid(100, parentIn(nested)) == 75)
check.that("should give no app when no ancestor is inside an app bundle",
  claudewait.appPid(100, parentIn({ [100] = { 90, "claude" }, [90] = { 1, "/bin/zsh" } })) == nil)
check.that("should stop walking at the first process, PID 1",
  pcall(claudewait.appPid, 100, parentIn({ [100] = { 1, "claude" } })))
check.that("should list no rows when every Claude has ended", #claudewait.rows(sessions, function() return false end, 400) == 0)
check.that("should list no rows when no session waits", #claudewait.rows({}, alive, 400) == 0)

local GHOSTTY, ITERM, TERMINAL = "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal"
local function everyTerminal() return true end
local function scriptFor(bundle, tty)
  for _, entry in ipairs(claudewait.focusScripts(tty)) do
    if entry.bundle == bundle then return entry.script end
  end
end

check.that("should try Ghostty first when several terminals run",
  claudewait.focusScripts("/dev/ttys009")[1].bundle == GHOSTTY)
check.that("should focus the Ghostty terminal on that tty",
  check.contains(scriptFor(GHOSTTY, "/dev/ttys009"), 'first terminal whose tty is "/dev/ttys009"'))
check.that("should focus the iTerm2 session on that tty",
  check.contains(scriptFor(ITERM, "/dev/ttys009"), 'tty of aSession is "/dev/ttys009"'))
check.that("should focus the Terminal tab on that tty",
  check.contains(scriptFor(TERMINAL, "/dev/ttys009"), 'tty of aTab is "/dev/ttys009"'))
check.that("should give no scripts for a session outside a terminal", #claudewait.focusScripts("-") == 0)
check.that("should give no scripts for a tty that isn't a plain device path",
  #claudewait.focusScripts('/dev/ttys1" & do shell script "x') == 0)

local tried = {}
local function recording(found)
  tried = {}
  return function(script)
    tried[#tried + 1] = script
    return script == found
  end
end
claudewait.focus("/dev/ttys009", function(bundle) return bundle == TERMINAL end, recording(nil))
check.that("should skip a terminal that isn't running",
  #tried == 1 and tried[1] == scriptFor(TERMINAL, "/dev/ttys009"))
claudewait.focus("/dev/ttys009", everyTerminal, recording(scriptFor(ITERM, "/dev/ttys009")))
check.that("should stop at the first terminal that finds the tty", #tried == 2)
check.that("should report success when a terminal finds the tty",
  claudewait.focus("/dev/ttys009", everyTerminal, recording(scriptFor(TERMINAL, "/dev/ttys009"))) == true)
check.that("should report failure when no terminal has the tty",
  claudewait.focus("/dev/ttys009", everyTerminal, recording(nil)) == false)
check.that("should report failure for a session outside a terminal",
  claudewait.focus("-", everyTerminal, recording(nil)) == false)

-- A session you've seen leaves the pill until its state changes.
check.that("should build the AppleScript that reads Ghostty's focused tty",
  check.contains(claudewait.viewedScript(), 'tty of focused terminal of selected tab of front window'))
local saved = {
  { id = "a", pid = 1, tty = "/dev/ttys001", folder = "omv", since = 100, state = "done" },
  { id = "b", pid = 2, tty = "/dev/ttys002", folder = "api", since = 200, state = "asks" },
  { id = "c", pid = 3, tty = "/dev/ttys003", folder = "web", since = 300, state = "working" },
}
local seen = claudewait.seenNow(saved, "/dev/ttys001")
check.that("should mark a waiting session seen when its terminal is the one in view",
  #seen == 1 and seen[1].id == "a" and seen[1].since == 100)
check.that("should leave a session unseen when another terminal is in view", #claudewait.seenNow(saved, "/dev/ttys009") == 0)
check.that("should not mark a working session seen", #claudewait.seenNow(saved, "/dev/ttys003") == 0)
check.that("should mark nothing seen when no terminal is in view", #claudewait.seenNow(saved, nil) == 0)

check.finish()
