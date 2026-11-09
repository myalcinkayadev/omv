-- Behavior of the quick note: today's path, the line it adds and the note it leaves.
-- Run through quicknote_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local quicknote = require("quicknote")

-- Local time, so the test reads the same in any time zone.
local noon = os.time({ year = 2026, month = 11, day = 8, hour = 9, min = 5, sec = 0 })

check.that("should build today's path from the vault and the date",
  quicknote.path("/vault/work", noon) == "/vault/work/00 - Daily/2026-11-08.md")
check.that("should start the line with the time", quicknote.line("call Ali", noon) == "- 09:05 call Ali")
check.that("should trim spaces around the text", quicknote.line("  call Ali  ", noon) == "- 09:05 call Ali")
check.that("should refuse empty text", quicknote.line("", noon) == nil)
check.that("should refuse text that is only spaces", quicknote.line("   ", noon) == nil)
check.that("should keep text with newlines on one line", quicknote.line("one\ntwo", noon) == "- 09:05 one two")
check.that("should keep Turkish letters intact", quicknote.line("şöyle ğüzel", noon) == "- 09:05 şöyle ğüzel")

check.that("should create the note with the line when there is none",
  quicknote.appended(nil, "- 09:05 a") == "- 09:05 a\n")
check.that("should add the line after the existing content",
  quicknote.appended("# Day\n", "- 09:05 a") == "# Day\n- 09:05 a\n")
check.that("should start a new line when the note does not end with one",
  quicknote.appended("# Day", "- 09:05 a") == "# Day\n- 09:05 a\n")
check.that("should create the note with the line when the file is empty",
  quicknote.appended("", "- 09:05 a") == "- 09:05 a\n")

check.that("should format a single line as a timed bullet when the text has one line",
  quicknote.entry("call Ali", noon) == "- 09:05 call Ali")
check.that("should keep newlines when the text has several lines",
  check.contains(quicknote.entry("one\ntwo", noon), "one\ntwo"))
check.that("should put a timed heading above the block when the text has several lines",
  quicknote.entry("one\ntwo", noon):match("^### 09:05\n") ~= nil)
check.that("should trim trailing blank lines when the text ends with them",
  quicknote.entry("one\ntwo\n\n  \n", noon) == "### 09:05\none\ntwo")
check.that("should return nil when the text is only whitespace and newlines",
  quicknote.entry("  \n\n \t", noon) == nil)

check.that("should read the page title when the first line starts with a heading",
  quicknote.title("# Sprint plan\nbody") == "Sprint plan")
check.that("should return no title when the hash is not followed by a space",
  quicknote.title("#tag\nbody") == nil)
check.that("should return no title when the heading is not on the first line",
  quicknote.title("intro\n# Sprint plan") == nil)
check.that("should drop characters a filename cannot hold from the title",
  quicknote.title("# Q3: plan/v2 [draft]") == "Q3 planv2 draft")
check.that("should return no title when nothing is left after dropping characters",
  quicknote.title("# ///") == nil)

local nothing = function() return false end
check.that("should build the page path under Inbox from the title",
  quicknote.pagePath("/vault/work", "Sprint plan", nothing) == "/vault/work/Inbox/Sprint plan.md")
local taken = { ["/vault/work/Inbox/Sprint plan.md"] = true, ["/vault/work/Inbox/Sprint plan 2.md"] = true }
check.that("should number the page when a page with that title exists",
  quicknote.pagePath("/vault/work", "Sprint plan", function(path) return taken[path] end)
    == "/vault/work/Inbox/Sprint plan 3.md")
check.that("should write a wiki link line to the daily note when the note is a page",
  quicknote.link("/vault/work/Inbox/Sprint plan 3.md", noon) == "- 09:05 [[Sprint plan 3]]")

check.that("should keep a blank line between existing content and a new block",
  quicknote.appended("- 09:00 a\n", "### 09:05\none\ntwo") == "- 09:00 a\n\n### 09:05\none\ntwo\n\n")
check.that("should start the note with the block when the note is empty",
  quicknote.appended(nil, "### 09:05\none\ntwo") == "### 09:05\none\ntwo\n\n")
check.that("should not add a second blank line when the note already ends with one",
  quicknote.appended("- 09:00 a\n\n", "### 09:05\none\ntwo") == "- 09:00 a\n\n### 09:05\none\ntwo\n\n")

local function at(day, hour, min) return os.time({ year = 2026, month = 11, day = day, hour = hour, min = min, sec = 0 }) end
local today = { path = "/v/00 - Daily/2026-11-08.md", folder = "Daily", modified = at(8, 8, 0) }
local page = { path = "/v/Inbox/Sprint plan.md", folder = "Inbox", modified = at(8, 9, 0) }
local older = { path = "/v/00 - Daily/2026-11-07.md", folder = "Daily", modified = at(7, 18, 0) }
local oldest = { path = "/v/Inbox/Q3 roadmap.md", folder = "Inbox", modified = at(3, 10, 0) }
local rows = quicknote.rows({ oldest, page, older, today }, noon)

check.that("should put today's daily note first when it is not the newest", rows[1].id == today.path)
check.that("should order the other notes by last change, newest first",
  rows[2].id == page.path and rows[3].id == older.path and rows[4].id == oldest.path)
check.that("should label a note with its filename without .md", rows[2].label == "Sprint plan")
check.that("should name the folder in the hint", rows[2].hint:match("Inbox$") ~= nil)
check.that("should show today and the time when the note changed today", rows[2].hint:match("^today · 09:00") ~= nil)
check.that("should show yesterday when the note changed the day before", rows[3].hint:match("^yesterday") ~= nil)
check.that("should show the month and day when the note changed earlier", rows[4].hint:match("^Nov 3") ~= nil)
check.that("should return no rows when there are no notes", #quicknote.rows({}, noon) == 0)
check.that("should leave out files that are not Markdown",
  #quicknote.rows({ { path = "/v/Inbox/photo.png", folder = "Inbox", modified = at(8, 9, 0) } }, noon) == 0)
local many = {}
for index = 1, 250 do many[index] = { path = "/v/Inbox/n" .. index .. ".md", folder = "Inbox", modified = at(1, 0, 0) + index } end
check.that("should keep at most 200 rows when there are more notes", #quicknote.rows(many, noon) == 200)

check.that("should allow saving when the file has not changed since it was opened", quicknote.canSave(100, 100))
check.that("should refuse saving when the file changed since it was opened", not quicknote.canSave(100, 160))

check.finish()
