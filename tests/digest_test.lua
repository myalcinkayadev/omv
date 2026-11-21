-- Behavior of the agents' inbox: its sections, title, what opens, and clearing.
-- Run through digest_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local digest = require("digest")

local LOCKED, NOW = 10000, 10000 + 1500
local function session(id, state, since, extra)
  local found = { id = id, tty = "/dev/ttys00" .. id:sub(-1), pid = 100, folder = "project-" .. id, state = state, since = since, agent = "claude" }
  for key, value in pairs(extra or {}) do found[key] = value end
  return found
end
local function find(rows, id)
  for _, row in ipairs(rows) do if row.id == id then return row end end
  return nil
end

-- Sections.
local live = digest.liveRows({
  session("d1", "done", NOW - 1080),
  session("a1", "asks", NOW - 360),
  session("w1", "working", NOW - 60),
  session("d2", "done", NOW - 240, { agent = "codex" }),
}, NOW)
check.that("should put an asking session under Needs you", live[1].id == "session:a1" and live[1].group == "Needs you")
check.that("should say what an asking session wants and since when", live[1].hint == "approve · asked 6 min ago")
check.that("should mark an asking session with a dot in the ask tone", live[1].icon == "●" and live[1].tone == "ask")
check.that("should put a done session under Done", find(live, "session:d1").group == "Done")
check.that("should say when a done session finished", find(live, "session:d1").hint == "finished 18 min ago")
check.that("should mark a done session with a check in the ok tone", find(live, "session:d1").icon == "✓" and find(live, "session:d1").tone == "ok")
check.that("should list the session waiting longest first in Done", live[2].id == "session:d1")
check.that("should leave a working session out", find(live, "session:w1") == nil)
check.that("should name an agent other than Claude", find(live, "session:d2").hint == "codex · finished 4 min ago")
check.that("should keep a live session's terminal to go to", live[1].tty == "/dev/ttys001")
check.that("should mark live rows", live[1].live == true)
check.that("should list nothing without sessions", #digest.liveRows(nil, NOW) == 0)

local before = { session("e1", "working", LOCKED - 60), session("k1", "working", LOCKED - 60) }
local after = { session("k1", "done", LOCKED + 60) }
local prs = { { number = 42, title = "Fix login", url = "https://github.com/acme/api/pull/42", repository = { nameWithOwner = "acme/api" } },
  { number = 1, title = "No URL" } }
local away = digest.awayRows(before, after, LOCKED, NOW, prs)
check.that("should put a session that ended while away under While away", find(away, "ended:e1").group == "While away · 25 min")
check.that("should say a session ended", find(away, "ended:e1").hint == "ended")
check.that("should mark an ended session with a dash", find(away, "ended:e1").icon == "–")
check.that("should put a pull request you opened under While away", find(away, "pr:https://github.com/acme/api/pull/42").group == "While away · 25 min")
check.that("should name a pull request's repository and number", find(away, "pr:https://github.com/acme/api/pull/42").hint == "acme/api#42 · PR opened")
check.that("should mark a pull request with an arrow", find(away, "pr:https://github.com/acme/api/pull/42").icon == "↗")
check.that("should keep the pull request's URL to open", find(away, "pr:https://github.com/acme/api/pull/42").url == "https://github.com/acme/api/pull/42")
check.that("should skip a pull request without a URL", #away == 2)
check.that("should leave a session that is still there out of While away", find(away, "ended:k1") == nil)
check.that("should count a long break in hours and minutes",
  digest.awayRows({ session("e2", "working", 0) }, {}, 0, 135 * 60, nil)[1].group == "While away · 2 h 15 min")
check.that("should ask gh for pull requests created since the lock, in UTC", digest.createdSince(0) == ">=1970-01-01T00:00:00Z")

-- Title.
local inbox = digest.inbox(live, away)
check.that("should list the live rows before While away", inbox[1].live and not inbox[#inbox].live)
local summary = digest.summary(inbox)
check.that("should count every kind, While away included", summary.counts == "1 asks · 2 done · 1 ended · 1 PR")
check.that("should say how many need you when a session asks", summary.status == "1 needs you" and summary.tone == "ask")
check.that("should say nothing needs you when none asks",
  digest.summary(digest.liveRows({ session("d3", "done", NOW - 60) }, NOW)).status == "nothing needs you")
check.that("should leave out a kind with none", digest.summary(digest.liveRows({ session("d4", "done", NOW - 60) }, NOW)).counts == "1 done")

-- What opens.
local one = digest.liveRows({ session("d5", "done", NOW - 60) }, NOW)
check.that("should go straight to the terminal when one session waits and nothing is left from a break", digest.action(one, {}) == "jump")
check.that("should open the screen when two sessions wait", digest.action(live, {}) == "card")
check.that("should open the screen when one session waits after a break", digest.action(one, away) == "card")
check.that("should open the screen for a break alone", digest.action({}, away) == "card")
check.that("should open nothing when nothing waits", digest.action({}, {}) == nil)

local changes = digest.changed(before, after, LOCKED)
check.that("should count what changed during the break", #changes == 2)
check.that("should not count a session that didn't change",
  #digest.changed({ session("s5", "working", LOCKED - 60) }, { session("s5", "working", LOCKED - 60) }, LOCKED) == 0)
check.that("should open on unlock after a long break in which something changed", digest.shows(LOCKED, NOW, changes))
check.that("should not open on unlock after a break under 5 minutes", not digest.shows(LOCKED, LOCKED + digest.MIN_AWAY - 1, changes))
check.that("should not open on unlock when nothing changed", not digest.shows(LOCKED, NOW, {}))
check.that("should not open on unlock without a lock", not digest.shows(nil, NOW, changes))

-- The break that opens the screen on unlock, from ~/.config/omv/away-digest.
check.that("should wait 5 minutes without a file", digest.minAway(nil) == 5 * 60)
check.that("should read the minutes set", digest.minAway("minutes = 10\n") == 10 * 60)
check.that("should allow 0, so every break opens the screen", digest.minAway("minutes = 0") == 0)
check.that("should ignore spaces around the name and the value", digest.minAway("  minutes=2  ") == 2 * 60)
check.that("should ignore a comment line", digest.minAway("# minutes = 1") == 5 * 60)
check.that("should fall back to 5 minutes for a word", digest.minAway("minutes = ten") == 5 * 60)
check.that("should fall back to 5 minutes for a negative number", digest.minAway("minutes = -3") == 5 * 60)
check.that("should fall back to 5 minutes for a fraction", digest.minAway("minutes = 2.5") == 5 * 60)
check.that("should use the last line when the setting is there twice", digest.minAway("minutes = 1\nminutes = 7") == 7 * 60)
check.that("should open on unlock after the break set, not the default",
  digest.shows(LOCKED, LOCKED + 60, changes, digest.minAway("minutes = 1")))
check.that("should not open on unlock before the break set",
  not digest.shows(LOCKED, LOCKED + 59, changes, digest.minAway("minutes = 1")))

-- Clearing.
local cleared = digest.clear(inbox, "ended:e1")
check.that("should clear a While away row", find(cleared, "ended:e1") == nil and #cleared == #inbox - 1)
check.that("should leave a live row in place", #digest.clear(inbox, "session:a1") == #inbox)
check.that("should change nothing when the row isn't there", #digest.clear(inbox, "missing") == #inbox)
check.that("should leave no While away rows once the last is cleared",
  #digest.clear(digest.clear(away, "ended:e1"), "pr:https://github.com/acme/api/pull/42") == 0)

check.finish()
