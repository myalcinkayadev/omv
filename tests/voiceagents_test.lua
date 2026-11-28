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

check.finish()
