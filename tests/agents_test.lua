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

local projects = agents.projects({
  { cwd = "/a/old", modified = 100 },
  { cwd = "/a/new", modified = 300 },
  { cwd = "/a/old", modified = 200 },
})
check.that("should list the most recent project first", projects[1] == "/a/new")
check.that("should list each project once", #projects == 2)

local rows = agents.projectRows({ "/Users/me/work/omv" }, "/Users/me")
check.that("should label a project by its folder name", rows[1].label == "omv")
check.that("should show a project's path from home as its hint", rows[1].hint == "~/work/omv")
check.that("should give a project row its path as its id", rows[1].id == "/Users/me/work/omv")

check.that("should quote a path for the shell", agents.shellQuote("/a b/c") == "'/a b/c'")
check.that("should quote a path with a single quote for the shell", agents.shellQuote("/it's") == [['/it'\''s']])

check.finish()
