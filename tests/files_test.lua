-- Which files the palette finds: the mdfind query for what's typed, and the rows from its
-- answer. Run through files_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local files = require("files")

local HOME = "/Users/me"
local QUERY = '(kMDItemFSName == "*readme*"cd) && ((kMDItemLastUsedDate >= $time.today(-30))'
  .. ' || (kMDItemFSContentChangeDate >= $time.today(-30)))'

local readme = files.arguments("readme", HOME)
check.that("should search names containing the text", readme ~= nil and readme[3] == QUERY)
check.that("should search only under home", readme ~= nil and readme[1] == "-onlyin" and readme[2] == HOME)
check.that("should ask nothing for fewer than 3 characters", files.arguments("re", HOME) == nil)
check.that("should drop quotes, backslashes and stars from the text",
  (files.arguments('re"a\\d*me', HOME) or {})[3] == QUERY)
check.that("should ask nothing when only stars and quotes were typed", files.arguments('"**"', HOME) == nil)

local rows = files.rows("/Users/me/w/omv/README.md\n", HOME)
check.that("should list a file by its name", rows[1] and rows[1].label == "README.md")
check.that("should hint its folder from home", rows[1] and rows[1].hint == "~/w/omv")
check.that("should open a file by its path", rows[1] and rows[1].id == "file:/Users/me/w/omv/README.md")
check.that("should group files under Files", rows[1] and rows[1].group == "Files")
check.that("should leave out Library, node_modules and .git", #files.rows(
  "/Users/me/Library/a.md\n/Users/me/w/node_modules/b.md\n/Users/me/w/.git/c.md\n", HOME) == 0)

local many = {}
for index = 1, 25 do many[#many + 1] = "/Users/me/f" .. index .. ".md" end
check.that("should list at most 20", #files.rows(table.concat(many, "\n"), HOME) == 20)
check.that("should skip blank lines", #files.rows("\n\n", HOME) == 0)

check.finish()
