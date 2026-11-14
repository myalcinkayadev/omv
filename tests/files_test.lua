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

local DATES = "((kMDItemLastUsedDate >= $time.today(-30)) || (kMDItemFSContentChangeDate >= $time.today(-30)))"
check.that("should search each word on its own", (files.arguments("read md", HOME) or {})[3]
  == '(kMDItemFSName == "*read*"cd) && (kMDItemFSName == "*md*"cd) && ' .. DATES)
check.that("should count letters, not spaces, toward the minimum", files.arguments("a b", HOME) == nil)
check.that("should search two words that have 3 letters between them", files.arguments("ab c", HOME) ~= nil)
check.that("should ignore extra spaces between words",
  (files.arguments("read   md", HOME) or {})[3] == (files.arguments("read md", HOME) or {})[3])

local function labels(found)
  local out = {}
  for _, row in ipairs(found) do out[#out + 1] = row.hint .. "/" .. row.label end
  return out
end
local function dated(dates) return function(path) return dates[path] end end

local ranked = files.rows("/Users/me/notes-readme.md\n/Users/me/README.md\n", HOME, "readme", dated({}))
check.that("should rank a name that starts with the word first", ranked[1].label == "README.md")
ranked = files.rows("/Users/me/areadmex.md\n/Users/me/my-readme.md\n", HOME, "readme", dated({}))
check.that("should rank a word start inside the name before a plain contains", ranked[1].label == "my-readme.md")
ranked = files.rows("/Users/me/a/README.md\n/Users/me/b/README.md\n", HOME, "readme",
  dated({ ["/Users/me/a/README.md"] = 100, ["/Users/me/b/README.md"] = 200 }))
check.that("should rank newer first within the same match", labels(ranked)[1] == "~/b/README.md")
local crowd = {}
for index = 1, 25 do crowd[#crowd + 1] = "/Users/me/my" .. index .. "readme.txt" end
crowd[#crowd + 1] = "/Users/me/README.md"
ranked = files.rows(table.concat(crowd, "\n"), HOME, "readme", dated({}))
check.that("should rank before cutting to 20", #ranked == 20 and ranked[1].label == "README.md")
ranked = files.rows("/Users/me/a/README.md\n/Users/me/b/README.md\n", HOME, "readme",
  dated({ ["/Users/me/b/README.md"] = 200 }))
check.that("should not count a file without a date as newest", labels(ranked)[1] == "~/b/README.md")

check.that("should pick the code icon for a .lua file", files.icon("init.lua") == files.ICONS.code)
check.that("should pick the document icon for a .md file", files.icon("README.md") == files.ICONS.document)
check.that("should pick the image icon whatever the case of the extension", files.icon("SHOT.PNG") == files.ICONS.image)
check.that("should keep the plain file icon for an unknown extension", files.icon("data.xyz") == files.ICONS.file)
check.that("should show a file's icon in its row", files.rows("/Users/me/a.pdf\n", HOME)[1].icon == files.ICONS.pdf)

check.finish()
