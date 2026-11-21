-- Behavior of the away digest's rows. Run through digest_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local digest = require("digest")

local LOCKED, NOW = 10000, 10000 + 3600
local function session(id, state, since, extra)
  local found = { id = id, tty = "/dev/ttys00" .. id:sub(-1), pid = 100, folder = "project-" .. id, state = state, since = since, agent = "claude" }
  for key, value in pairs(extra or {}) do found[key] = value end
  return found
end

local before = { session("s1", "working", LOCKED - 60), session("s2", "working", LOCKED - 60), session("s3", "done", LOCKED - 600) }
local after = {
  session("s1", "done", LOCKED + 600),
  session("s2", "asks", LOCKED + 1200),
  session("s4", "working", LOCKED + 1800),
}
local rows = digest.rows(before, after, LOCKED, NOW)

check.that("should list each session that changed and each that ended", #rows == 4)
check.that("should list a session asking for approval first", rows[1].id == "session:s2")
check.that("should say a session needs your approval", rows[1].hint == "needs your approval")
check.that("should list a finished session after the asking ones", rows[2].id == "session:s1")
check.that("should say when a session finished", rows[2].hint == "finished 50 min ago")
check.that("should list a session that started working while away", rows[3].hint == "started working 30 min ago")
check.that("should list a session that ended last", rows[4].id == "ended:s3")
check.that("should say a session ended", rows[4].hint == "ended")
check.that("should name the session by its folder", rows[1].label == "project-s2")
check.that("should keep the terminal to go to", rows[1].tty == "/dev/ttys002")
check.that("should leave out a session that didn't change",
  #digest.rows({ session("s5", "working", LOCKED - 60) }, { session("s5", "working", LOCKED - 60) }, LOCKED, NOW) == 0)
check.that("should name an agent other than Claude",
  digest.rows({}, { session("s6", "done", LOCKED + 60, { agent = "codex" }) }, LOCKED, NOW)[1].hint:match("^codex · ") ~= nil)
check.that("should list nothing without sessions", #digest.rows(nil, nil, LOCKED, NOW) == 0)
check.that("should put the earliest change first within one state", (function()
  local found = digest.rows({}, { session("s7", "done", LOCKED + 900), session("s8", "done", LOCKED + 100) }, LOCKED, NOW)
  return found[1].id == "session:s8"
end)())
check.that("should count hours for an old change",
  digest.rows({}, { session("s9", "done", LOCKED + 1) }, LOCKED, LOCKED + 3 * 3600)[1].hint == "finished 2 h ago")

local prs = digest.prRows({
  { number = 42, title = "Fix login", url = "https://github.com/acme/api/pull/42", repository = { nameWithOwner = "acme/api" } },
  { number = 1, title = "No URL" },
})
check.that("should make a row per pull request with a URL", #prs == 1)
check.that("should name the repository and number", prs[1].hint == "acme/api#42 · pull request opened")
check.that("should keep the URL to open", prs[1].url == "https://github.com/acme/api/pull/42")
check.that("should make no pull request rows when gh's answer could not be read", #digest.prRows(nil) == 0)

check.that("should ask gh for pull requests created since the lock, in UTC",
  digest.createdSince(0) == ">=1970-01-01T00:00:00Z")

check.that("should show after a long break with something in it", digest.shows(LOCKED, NOW, rows))
check.that("should not show after a short break", not digest.shows(LOCKED, LOCKED + digest.MIN_AWAY - 1, rows))
check.that("should not show with nothing in it", not digest.shows(LOCKED, NOW, {}))
check.that("should not show without a lock", not digest.shows(nil, NOW, rows))

check.that("should say how long you were away", digest.prompt(LOCKED, LOCKED + 25 * 60) == "While you were away, 25 min…")
check.that("should say hours for a long break", digest.prompt(LOCKED, LOCKED + 135 * 60) == "While you were away, 2 h 15 min…")

check.finish()
