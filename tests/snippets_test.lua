-- Behavior of snippets: text kept in ~/.config/omv/snippets, picked in the palette, then
-- pasted where you were typing. Run through snippets_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local snippets = require("snippets")
local palette = require("palette")

local FILE = [[
# My snippets
reply = Thanks, I'll take a look today.

email=me@example.com
sign = Best regards,\nAlex
broken line
 = no name
email = work@example.com
]]

local list = snippets.parse(FILE)
local function find(name)
  for _, snippet in ipairs(list) do
    if snippet.name == name then return snippet end
  end
end

check.that("should read a name = text line", find("reply").text == "Thanks, I'll take a look today.")
check.that("should read a line written without spaces around =", find("email") ~= nil)
check.that("should skip comments and blank lines", #list == 3)
check.that("should turn \\n into a line break", find("sign").text == "Best regards,\nAlex")
check.that("should keep the last one when a name appears twice", find("email").text == "work@example.com")
check.that("should skip a line with no =", find("broken line") == nil)
check.that("should skip a line with no name", find("") == nil)
check.that("should give no snippets when the file is missing", #snippets.parse(nil) == 0)

local rows = snippets.rows(list)
check.that("should list a snippet in the palette by its name", rows[1].label == "reply")
check.that("should group snippets under Snippets", rows[1].group == "Snippets")
check.that("should show the start of a snippet's text beside it", rows[3].hint == "Best regards, Alex")
check.that("should cut a long snippet's text short beside it", #snippets.rows({ { name = "long", text = string.rep("x", 80) } })[1].hint <= 40 + 3)
check.that("should read a snippet row as a snippet", palette.parse(rows[2].id) == "snippet")
check.that("should read which snippet a row is", select(2, palette.parse(rows[2].id)) == 2)
local all = palette.rows("1|Ghostty|1|~", { { name = "Zed", path = "/Applications/Zed.app" } }, {}, "Option+Space", rows)
check.that("should list snippets after the windows", all[1].group == "Windows" and all[2].group == "Snippets")
check.that("should list snippets before the apps", all[#rows + 2].group == "Apps")

check.that("should paste when focus is back where you were typing", snippets.way(true, 7, 7) == "paste")
check.that("should only copy when another window has focus", snippets.way(true, 7, 9) == "copy")
check.that("should only copy when no window had focus before", snippets.way(true, nil, nil) == "copy")
check.that("should only copy without Accessibility", snippets.way(false, 7, 7) == "copy")

check.finish()
