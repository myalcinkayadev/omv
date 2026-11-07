-- Behavior of the window summon list. Run through windows_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local windows = require("windows")

local output = table.concat({
  "99|Helium|3|Docs - Helium",
  "4662|Ghostty|1|btop",
  "120|Zed|2|a | b",
  "121|Finder|5|",
}, "\n") .. "\n"
local rows = windows.rows(output)

check.that("should make one row per window", #rows == 4)
check.that("should use the window id as the row id", rows[1].id == "99")
check.that("should show the window title as the label", rows[2].label == "btop")
check.that("should show the app and workspace as the hint", rows[1].hint == "Helium · 3")
check.that("should keep a title that contains the separator", rows[3].label == "a | b")
check.that("should label a window without a title by its app name", rows[4].label == "Finder")
check.that("should return no rows for empty output", #windows.rows("") == 0)
check.that("should skip lines it cannot read", #windows.rows("garbage\n") == 0)

check.finish()
