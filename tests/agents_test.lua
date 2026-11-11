-- Behavior of the Agents card and its list of Claude Code projects. Run through
-- agents_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local agents = require("agents")

local DASH = "—"
local NOW = 1794150000

local usage = agents.parseUsage("88 1794159240 63.4 1794394800\n", NOW)
check.that("should read the session percentage rounded", usage.five.percent == 88)
check.that("should read the weekly percentage rounded", usage.seven.percent == 63)
check.that("should read the session time left in seconds", usage.five.left == 9240)
check.that("should give 0% when a window's reset time has passed",
  agents.parseUsage("90 1794140000 10 1794394800", NOW).five.percent == 0)
check.that("should give no time left when a window's reset time has passed",
  agents.parseUsage("90 1794140000 10 1794394800", NOW).five.left == nil)
check.that("should give nothing when the usage file is empty", agents.parseUsage("", NOW) == nil)
check.that("should give nothing when the usage file is not numbers", agents.parseUsage("oops", NOW) == nil)

check.that("should show hours and minutes when under a day", agents.left(9240) == "2h 34m")
check.that("should show days and hours when a day or more", agents.left(2 * 86400 + 19 * 3600 + 120) == "2d 19h")
check.that("should show a dash when there is no time left", agents.left(nil) == DASH)

check.that("should name the Pro plan", agents.plan("claude_pro") == "Pro")
check.that("should name the Max plan", agents.plan("claude_max") == "Max")
check.that("should name no plan when the type is unknown", agents.plan("something_else") == nil)
check.that("should name no plan when there is no type", agents.plan(nil) == nil)

local page = agents.html({ plan = "Pro", usage = usage })
local visible = check.visible(page)
check.that("should title the card Agents", check.contains(visible, "Agents"))
check.that("should show the plan", check.contains(visible, "Pro"))
check.that("should name Claude Code", check.contains(visible, "Claude Code"))
check.that("should fill the session bar to its percentage", check.contains(page, 'class=fill style="width: 88%"'))
check.that("should fill the weekly bar to its percentage", check.contains(page, 'class=fill style="width: 63%"'))
check.that("should show the session time left", check.contains(visible, "2h 34m"))
check.that("should give the continue button its id", check.contains(page, 'data-id="agents.continue"'))
check.that("should give the new-session button its id", check.contains(page, 'data-id="agents.new"'))
check.that("should leave out the make-something section", not check.contains(visible, "MAKE SOMETHING"))

check.that("should show the Claude logo when given one",
  check.contains(agents.html({ logo = "data:image/png;base64,AAAA" }), 'src="data:image/png;base64,AAAA"'))

local sessions = {
  { id = "/dev/ttys004", label = "api", hint = "asks · 1 min", state = "asks" },
  { id = "/dev/ttys002", label = "omv", hint = "working · 3 min", state = "working" },
}
local withSessions = agents.html({ sessions = sessions })
check.that("should show a row per live session", select(2, withSessions:gsub('class="session', "")) == 2)
check.that("should give a session row its terminal as its id", check.contains(withSessions, 'data-id="session:/dev/ttys004"'))
check.that("should show a session's state and wait", check.contains(check.visible(withSessions), "asks · 1 min"))
check.that("should show no session rows when no session is live", not check.contains(agents.html({}), 'class="session'))
check.that("should keep the card's height when no session is live", agents.height(0) == agents.HEIGHT)

-- Background sessions, from `claude agents --json`, decoded as hs.json.decode gives it.
local listed = agents.background({
  { id = "cd3bc75e", cwd = "/Users/me/work/game", kind = "background", name = "Doodleshooter", state = "done", startedAt = 2 },
  { id = nil, cwd = "/Users/me/work/omv", kind = "interactive", name = "omv-14", state = nil, startedAt = 3 },
  { id = "edbc65df", cwd = "/Users/me/work/sila-v1", kind = "background", name = "clear-state", state = "blocked", startedAt = 1 },
  { id = "aa11bb22", cwd = "/Users/me/work/api", kind = "background", state = "failed", startedAt = 4 },
})
check.that("should keep only background sessions", #listed == 3)
check.that("should list asking background sessions first", listed[1].id == "edbc65df")
check.that("should label a background session by its name", listed[1].label == "clear-state")
check.that("should label a background session without a name by its folder", listed[3].label == "api")
check.that("should map blocked to asks", listed[1].state == "asks")
check.that("should map done to done", listed[2].state == "done")
check.that("should show any other state as it is", listed[3].state == "failed")
check.that("should hint a background session's folder and state", listed[1].hint == "sila-v1 · asks")
check.that("should give no background sessions when the output isn't a list", #agents.background({ error = "x" }) == 0)
check.that("should give no background sessions without output", #agents.background(nil) == 0)

check.that("should attach to a background session by a plain id", agents.attachArguments("edbc65df") == "attach edbc65df")
check.that("should refuse a background id that isn't plain", agents.attachArguments("x; rm -rf ~") == nil)
check.that("should read a background row's id back", agents.backgroundId("background:edbc65df") == "edbc65df")
check.that("should read no background id from a session id", agents.backgroundId("session:/dev/ttys004") == nil)

local withBackground = agents.html({ sessions = sessions, background = listed })
check.that("should show a BACKGROUND section when there are background sessions",
  check.contains(check.visible(withBackground), "BACKGROUND"))
check.that("should show no BACKGROUND section without background sessions",
  not check.contains(check.visible(withSessions), "BACKGROUND"))
check.that("should give a background row its id", check.contains(withBackground, 'data-id="background:edbc65df"'))
check.that("should grow the card for the background section", agents.height(2, 1) > agents.height(2, 0))
check.that("should keep the card's height with neither kind of session", agents.height(0, 0) == agents.HEIGHT)

-- Removing a background session from the card: x on its row, then a confirmation.
check.that("should mark background rows as removable", listed[1].removable == true)
check.that("should mark background rows removable in the page", check.contains(withBackground, 'data-id="background:edbc65df" data-removable'))
check.that("should not mark Claude session rows as removable", not check.contains(withSessions, "data-removable"))
check.that("should show x remove in the BACKGROUND title", check.contains(check.visible(withBackground), "BACKGROUND · x remove"))
local commands = agents.removeCommands("edbc65df")
check.that("should stop, then remove a background session", commands and commands[1] == "stop edbc65df" and commands[2] == "rm edbc65df")
check.that("should build no remove commands for an id that isn't plain", agents.removeCommands("x; rm -rf ~") == nil)
local busy = agents.confirmRemove({ id = "aa11", label = "fix tests", state = "working" })
check.that("should label the confirm button Stop and remove for a working session", busy.rows[2].label == "Stop and remove")
local idle = agents.confirmRemove({ id = "aa11", label = "fix tests", state = "asks" })
check.that("should label the confirm button Remove for a session that isn't working", idle.rows[2].label == "Remove")
check.that("should select Cancel first on the confirm card", idle.rows[1].id == "cancel" and (idle.selected or 1) == 1)
check.that("should name the session on the confirm card", check.contains(idle.prompt, "fix tests"))
check.that("should grow the card by one row per session", agents.height(3) - agents.height(2) == agents.height(2) - agents.height(1))
check.that("should stop growing the card at six sessions", agents.height(7) == agents.height(6))
check.that("should read a session id back as its terminal", agents.sessionTty("session:/dev/ttys004") == "/dev/ttys004")
check.that("should read no terminal from a button id", agents.sessionTty("agents.new") == nil)

local empty = agents.html({})
check.that("should show empty bars when there is no usage", select(2, empty:gsub('style="width: 0%%"', "")) == 2)
check.that("should show dashes for times when there is no usage", select(2, check.visible(empty):gsub(DASH, "")) == 2)

local session = '{"type":"summary"}\nnot json\n{"cwd":"/Users/me/work/omv","type":"user"}\n{"cwd":"/elsewhere"}\n'
check.that("should read the first working folder from a session", agents.sessionCwd(session) == "/Users/me/work/omv")
check.that("should read no folder from a session without one", agents.sessionCwd('{"type":"summary"}\n') == nil)

local function everyFolder() return true end
local function notGone(folder) return folder ~= "/a/gone" end

local projects = agents.projects({
  { cwd = "/a/old", modified = 100 },
  { cwd = "/a/new", modified = 300 },
  { cwd = "/a/old", modified = 200 },
}, everyFolder)
check.that("should list the most recent project first", projects[1] == "/a/new")
check.that("should list each project once", #projects == 2)
check.that("should leave out a project whose folder no longer exists",
  #agents.projects({ { cwd = "/a/gone", modified = 300 }, { cwd = "/a/old", modified = 100 } }, notGone) == 1)

local recent = {
  { id = "s-gone", cwd = "/a/gone", modified = 300 },
  { id = "s-old", cwd = "/a/old", modified = 100 },
  { id = "s-new", cwd = "/a/new", modified = 200, title = "Fix the bar" },
}
check.that("should continue the latest session whose folder still exists", agents.latest(recent, notGone).id == "s-new")
check.that("should continue nothing when every folder is gone", agents.latest(recent, function() return false end) == nil)

local NOW = 1794150000
local resume = agents.resumeRows({
  { id = "s-gone", cwd = "/Users/me/gone", modified = NOW - 60 },
  { id = "s-old", cwd = "/Users/me/work/api", modified = NOW - 3 * 86400 },
  { id = "s-new", cwd = "/Users/me/work/omv", modified = NOW - 2 * 3600, title = "Fix the bar" },
}, function(folder) return folder ~= "/Users/me/gone" end, NOW)
check.that("should leave out sessions whose folder no longer exists from the resume list", #resume == 2)
check.that("should list sessions newest first", resume[1].id == "s-new")
check.that("should label a session by its title", resume[1].label == "Fix the bar")
check.that("should hint a session's folder and age", resume[1].hint == "omv · 2h ago")
check.that("should label a session without a title by its folder", resume[2].label == "api")
check.that("should hint an age in days from a day up", resume[2].hint == "api · 3d ago")

local file = '{"type":"user"}\n{"type":"ai-title","aiTitle":"First idea","sessionId":"s"}\n{"type":"ai-title","aiTitle":"Fix \\"the\\" bar","sessionId":"s"}\n'
check.that("should read a session's title from its file", agents.sessionTitle('{"type":"ai-title","aiTitle":"Swipe sorunu"}') == "Swipe sorunu")
check.that("should read the latest title when a session has several", agents.sessionTitle(file) == 'Fix "the" bar')
check.that("should read no title from a session without one", agents.sessionTitle('{"type":"user"}\n') == nil)

check.that("should resume a session by its id", agents.resumeArguments("7555d919-83ad-4e16") == "--resume 7555d919-83ad-4e16")
check.that("should refuse a session id that isn't a plain id", agents.resumeArguments("x; rm -rf ~") == nil)
check.that("should give the resume button its id", check.contains(agents.html({}), 'data-id="agents.resume"'))

local rows = agents.projectRows({ "/Users/me/work/omv" }, "/Users/me")
check.that("should label a project by its folder name", rows[1].label == "omv")
check.that("should show a project's path from home as its hint", rows[1].hint == "~/work/omv")
check.that("should give a project row its path as its id", rows[1].id == "/Users/me/work/omv")

check.that("should quote a path for the shell", agents.shellQuote("/a b/c") == "'/a b/c'")
check.that("should quote a path with a single quote for the shell", agents.shellQuote("/it's") == [['/it'\''s']])

check.finish()
