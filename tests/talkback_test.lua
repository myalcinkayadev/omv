-- Talk-back: the line spoken when an agent finishes, and when it may be spoken. Run through
-- talkback_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local talkback = require("talkback")

local function words(text)
  local count = 0
  for _ in tostring(text):gmatch("%S+") do count = count + 1 end
  return count
end

-- line
check.that("should keep whole sentences when they fit in 20 words",
  talkback.line("Tests pass. I changed two files. Then I updated the README and the changelog with every detail you asked for today.")
    == "Tests pass. I changed two files.")
check.that("should cut with an ellipsis when the first sentence is longer",
  talkback.line(string.rep("word ", 30) .. "end.") == string.rep("word ", 19) .. "word…")
check.that("should keep at most 20 words when cut", words(talkback.line(string.rep("word ", 30))) == 20)
check.that("should drop a fenced code block", talkback.line("Done.\n```lua\nlocal x = 1\n```\nAll good.") == "Done. All good.")
check.that("should keep link text", talkback.line("See [the plan](https://example.com/plan) now.") == "See the plan now.")
check.that("should shorten a path to its file name", talkback.line("I changed config/hammerspoon/dictation.lua today.") == "I changed dictation.lua today.")
check.that("should drop markdown marks", talkback.line("- **Tests** pass with `bash tests/run.sh`.") == "Tests pass with bash run.sh.")
check.that("should drop a heading line", talkback.line("# Tea\n\nFew drinks carry as much history as tea.") == "Few drinks carry as much history as tea.")
check.that("should drop a cut UTF-8 character at the end", talkback.line("Testler geçti ş" .. string.sub("ş", 1, 1)) == "Testler geçti ş")
check.that("should give nil when the text is empty", talkback.line("  \n ") == nil)
check.that("should give nil when there is no text", talkback.line(nil) == nil)

-- newlyDone
local before = { { id = "a", state = "working" }, { id = "b", state = "done" } }
local after = { { id = "a", state = "done" }, { id = "b", state = "done" }, { id = "c", state = "asks" } }
check.that("should list a session when it turned done", #talkback.newlyDone(before, after) == 1 and talkback.newlyDone(before, after)[1].id == "a")
check.that("should skip a session when it was done before", #talkback.newlyDone(after, after) == 0)

-- due
local function all(changes)
  local c = { flag = true, quiet = false, headphones = true, recording = false, tty = "/dev/ttys001", viewedTty = "/dev/ttys002" }
  for key, value in pairs(changes or {}) do c[key] = value end
  return c
end
check.that("should not be due when the flag is off", talkback.due(all({ flag = false })) == false)
check.that("should not be due in a meeting", talkback.due(all({ quiet = true })) == false)
check.that("should not be due without headphones", talkback.due(all({ headphones = false })) == false)
check.that("should not be due while recording", talkback.due(all({ recording = true })) == false)
check.that("should not be due when the session is in view", talkback.due(all({ viewedTty = "/dev/ttys001" })) == false)
check.that("should be due when all hold", talkback.due(all()) == true)

-- voice
check.that("should give tr when the text has ş", talkback.voice("Testler geçti, iş bitti.") == "tr")
check.that("should give nil when the text is English", talkback.voice("Tests pass.") == nil)

check.finish()
