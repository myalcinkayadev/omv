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

check.finish()
