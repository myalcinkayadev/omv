-- The sound matcher shared by the palette and voice commands. Run through soundmatch_test.sh
-- with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local soundmatch = require("soundmatch")

-- key
check.that("should give the same key for said and Zed", soundmatch.key("said") == soundmatch.key("Zed"))
check.that("should give the same key for Ghasti and Ghostty", soundmatch.key("Ghasti") == soundmatch.key("Ghostty"))
check.that("should keep a leading vowel", soundmatch.key("omv"):sub(1, 1) == "o")

-- score
check.that("should score exact above prefix above spelling above sound", soundmatch.score("zed", "Zed") > soundmatch.score("ze", "Zed")
  and soundmatch.score("ze", "Zed") > soundmatch.score("ghosty", "Ghostty") and soundmatch.score("ghosty", "Ghostty") > soundmatch.score("said", "Zed")
  and soundmatch.score("said", "Zed") > 0)
check.that("should give 0 when the query is under 3 letters and only sounds alike", soundmatch.score("sd", "Zed") == 0)
check.that("should match on any word of a label", soundmatch.score("said", "Zed — notes.md") > 0)
check.that("should match a label of several words when said as one", soundmatch.score("night light", "Night light") == soundmatch.WHOLE)

-- rank
local items = { { label = "Zed" }, { label = "Zoom" }, { label = "Safari" }, { label = "Slack" } }
check.that("should give strong for one clear best", (function()
  local ranked, verdict = soundmatch.rank("said", items)
  return verdict == "strong" and ranked[1].label == "Zed"
end)())
check.that("should give tied when two share the best score", select(2, soundmatch.rank("z", { { label = "Zed" }, { label = "Zoom" } })) == "tied")
check.that("should give weak when nothing scores", select(2, soundmatch.rank("banana", items)) == "weak")

check.that("should score a whole label above one of its words", soundmatch.score("zed", "Zed") > soundmatch.score("zed", "Open Zed"))

-- Command verbs are words, not names: they don't sound-match.
check.that("should not sound-match said to Set a reminder", soundmatch.score("said", "Set a reminder") == 0)
check.that("should still sound-match said to Open Zed through Zed", soundmatch.score("said", "Open Zed") == soundmatch.SOUND)
check.that("should still match set exactly to Set a reminder", soundmatch.score("set", "Set a reminder") == soundmatch.EXACT)

check.finish()
