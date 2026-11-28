-- Telling or replying to an agent by voice: what was said, which session it goes to, and what
-- happens on release. Run through voiceagents_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local voiceagents = require("voiceagents")

local function words(text) return voiceagents.parse(text).words end

-- As claudewait.rows gives them: asking first, then done (longest done first), then working.
local rows = {
  { id = "/dev/ttys002", label = "api", state = "asks", hint = "asks · 2 min" },
  { id = "/dev/ttys001", label = "omv", state = "done", hint = "done · 9 min" },
  { id = "/dev/ttys004", label = "omv-web", state = "done", hint = "done · 3 min" },
  { id = "/dev/ttys003", label = "dashboard", state = "working", hint = "working · now" },
}

-- parse
check.that("should give tell when the text starts with Tell,", voiceagents.parse("Tell, omv run it").verb == "tell")
check.that("should drop to when the text is reply to it", table.concat(words("reply to it now"), " ") == "it now")
check.that("should give nil when the first word is neither verb", voiceagents.parse("open Zed") == nil)
check.that("should give nil when the text is empty", voiceagents.parse("") == nil)

-- match
local function matched(text)
  local row, prompt = voiceagents.match(words(text), rows)
  return row and row.label or prompt, row and prompt or nil
end
check.that("should match the folder when it's said exactly", matched("tell omv run the tests") == "omv")
check.that("should give the rest as the prompt when matched", select(2, matched("tell omv run the tests")) == "run the tests")
check.that("should match when the case or punctuation differs", matched("tell OMV, run it") == "omv")
check.that("should match when the letters are spelled out", matched("tell o m v run it") == "omv")
check.that("should match a hyphenated folder when it's said with spaces", matched("tell omv web fix the build") == "omv-web")
check.that("should prefer the longer folder when both match", select(2, matched("tell omv web fix the build")) == "fix the build")
check.that("should match one edit away when the name is long", matched("tell dashbord stop") == "dashboard")
check.that("should not match one edit away when the name is short", matched("tell omb run it") == "unknown")
check.that("should give tied when two sessions match equally", select(2, voiceagents.match(words("tell omv go"),
  { { id = "/dev/ttys001", label = "omv", state = "done" }, { id = "/dev/ttys009", label = "omv", state = "done" } })) == "tied")
check.that("should give unknown when nothing matches", matched("tell banana run it") == "unknown")
check.that("should give empty when nothing follows the name", matched("tell omv") == "empty")

-- lastDone
check.that("should give the last done row when several are done", voiceagents.lastDone(rows).label == "omv-web")
check.that("should prefer the tty that spoke when it's done", voiceagents.lastDone(rows, "/dev/ttys001").label == "omv")
check.that("should give nil when none are done", voiceagents.lastDone({ rows[1], rows[4] }) == nil)

-- target
check.that("should give paste when the session is done", voiceagents.target("tell omv run it", rows).kind == "paste")
check.that("should give copy with working when the session works", voiceagents.target("tell dashboard stop", rows).why == "working")
check.that("should give copy with asks when the session asks", voiceagents.target("tell api yes", rows).why == "asks")
check.that("should give none when the verb is missing", voiceagents.target("open Zed", rows).kind == "none")
check.that("should reply to the last done session", voiceagents.target("reply looks good", rows).row.label == "omv-web")
check.that("should give none when nobody is done to reply to", voiceagents.target("reply ok", { rows[1] }).kind == "none")
check.that("should name both when the target is tied", voiceagents.target("tell omv go",
  { { id = "/dev/ttys001", label = "omv", state = "done" }, { id = "/dev/ttys009", label = "omv", state = "done" } }).hint:find("omv", 1, true) ~= nil)
check.that("should drop control characters from the prompt", voiceagents.target("tell omv run\27 it", rows).prompt == "run it")
check.that("should drop a trailing newline from the prompt", voiceagents.target("tell omv run it\n", rows).prompt == "run it")

-- resultLine
check.that("should name the project and state when the target is paste",
  voiceagents.resultLine(voiceagents.target("tell omv run it", rows)) == "→ omv · done · 9 min")
check.that("should say release copies it when the target is copy",
  voiceagents.resultLine(voiceagents.target("tell dashboard stop", rows)):find("release copies it", 1, true) ~= nil)

-- Numbered sessions: 1 is where reply goes, then the other done ones newest first, then
-- asking, then working.
local labels = function(list)
  local out = {}
  for _, row in ipairs(list) do out[#out + 1] = row.number .. row.label end
  return table.concat(out, " ")
end
local many = {
  { id = "/dev/ttys002", label = "api", state = "asks" },
  { id = "/dev/ttys001", label = "omv", state = "done" },
  { id = "/dev/ttys004", label = "web", state = "done" },
  { id = "/dev/ttys005", label = "docs", state = "done" },
  { id = "/dev/ttys003", label = "dashboard", state = "working" },
}
check.that("should put the reply target first when several are done", voiceagents.numbered(many)[1].label == "docs")
check.that("should put the session that spoke first when it's done", voiceagents.numbered(many, "/dev/ttys001")[1].label == "omv")
check.that("should order the done rows newest first when no session spoke", labels(voiceagents.numbered(many)) == "1docs 2web 3omv 4api 5dashboard")
check.that("should list asking and working rows after the done ones", labels(voiceagents.numbered(many, "/dev/ttys004")) == "1web 2docs 3omv 4api 5dashboard")
check.that("should leave out rows past 9", (function()
  local lots = {}
  for i = 1, 12 do lots[i] = { id = "/dev/ttys0" .. (10 + i), label = "s" .. i, state = "done" } end
  return #voiceagents.numbered(lots) == 9
end)())

-- parse numbers
local function index(text) local said = voiceagents.parse(text) return said and said.verb == "number" and said.index end
check.that("should pick 1 when the text starts with one", index("one run the tests") == 1)
check.that("should pick 3 when the text starts with 3", index("3 run the tests") == 3)
check.that("should pick 2 when the text starts with number two", index("number two run it") == 2)
check.that("should pick 1 when the text is tell one", index("tell one run it") == 1)
check.that("should pick 2 when the first word is to", index("to run it") == 2)
check.that("should pick 4 when the first word is for", index("for run it") == 4)
check.that("should ignore a comma after a number", index("One, run the tests.") == 1)
check.that("should give the words after the number as the prompt", table.concat(voiceagents.parse("One, run the tests.").words, " ") == "run the tests.")

-- target with numbers
check.that("should give paste to row 1 when it's done", (function()
  local t = voiceagents.target("one run the tests", many)
  return t.kind == "paste" and t.row.label == "docs" and t.prompt == "run the tests"
end)())
check.that("should give copy when the numbered row is working", voiceagents.target("five stop", many).kind == "copy")
check.that("should give none with No session 4 when there are only 3",
  voiceagents.target("four go", { many[2], many[3], many[4] }).hint == "No session 4")
check.that("should give none when a number is said with nothing after it", voiceagents.target("one", many).kind == "none")

-- leftover
check.that("should give all the text when there's no verb", voiceagents.leftover("run the tests", many) == "run the tests")
check.that("should drop the verb and the name guess when the text starts with tell", voiceagents.leftover("tell banana print hi", many) == "print hi")
check.that("should drop a two-word name guess when it's nearest a two-word folder",
  voiceagents.leftover("tell dash bored stop it", many) == "stop it")
check.that("should drop the verb when the text starts with reply", voiceagents.leftover("reply looks good", many) == "looks good")
check.that("should give nil when nothing is left", voiceagents.leftover("tell banana", many) == nil)

-- listLines
check.that("should show at most 6 rows", (function()
  local lots = {}
  for i = 1, 9 do lots[i] = { id = "/dev/ttys0" .. (10 + i), label = "s" .. i, state = "done" } end
  return #voiceagents.listLines(voiceagents.numbered(lots)) == 6
end)())
check.that("should mark the chosen row", (function()
  local lines = voiceagents.listLines(voiceagents.numbered(many), "/dev/ttys004")
  return lines[2].chosen == true and lines[1].chosen == false
end)())

check.finish()
