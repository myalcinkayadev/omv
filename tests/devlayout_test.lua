-- Behavior of the dev layout: the project list, the three windows it opens, and finding
-- them afterwards. Run through devlayout_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local devlayout = require("devlayout")

local tools = { editor = "Zed", ghosttyWindow = "/h/.config/ghostty/new-window.sh",
  claudeIn = "/h/.hammerspoon/claude-in.sh", shellIn = "/h/.hammerspoon/shell-in.sh" }
local commands = devlayout.commands("/Users/me/omv", tools)
local function line(command) return command[1] .. " " .. table.concat(command[2], " ") end

check.that("should open three windows", #commands == 3)
check.that("should open the editor on the project", line(commands[1]) == "/usr/bin/open -a Zed /Users/me/omv")
check.that("should start Claude in the project in a new Ghostty window",
  line(commands[2]) == "/h/.config/ghostty/new-window.sh /h/.hammerspoon/claude-in.sh '/Users/me/omv'")
check.that("should open a shell in the project in a new Ghostty window",
  line(commands[3]) == "/h/.config/ghostty/new-window.sh /h/.hammerspoon/shell-in.sh '/Users/me/omv'")
local spaced = devlayout.commands("/Users/me/my project", tools)
check.that("should keep a folder with spaces whole for the editor", spaced[1][2][3] == "/Users/me/my project")
check.that("should quote a folder with spaces for Ghostty", spaced[2][2][1]:find("'/Users/me/my project'", 1, true) ~= nil)

local before = "1|Ghostty|1|btop\n2|Helium|3|news\n"
local after = "1|Ghostty|1|btop\n2|Helium|3|news\n7|Zed|2|omv\n8|Ghostty|1|claude\n9|Ghostty|1|zsh\n"
local fresh = devlayout.newWindows(before, after)
check.that("should find the windows that weren't there before", #fresh == 3 and fresh[1] == "7")
check.that("should find no new windows when nothing opened", #devlayout.newWindows(before, before) == 0)
check.that("should not count a new window of another app",
  #devlayout.newWindows(before, before .. "10|Music|6|Music\n") == 0)

local reused = "1|Ghostty|1|btop\n6|Zed|2|omv — README.md\n"
local reusedAfter = reused .. "8|Ghostty|1|claude\n9|Ghostty|1|zsh\n"
local moving = devlayout.windowsToMove(reused, reusedAfter, "/Users/me/omv")
check.that("should bring the editor window already open on the project", moving[1] == "6")
check.that("should bring the new terminal windows too", #moving == 3)
check.that("should not bring an editor window open on another project",
  #devlayout.windowsToMove("6|Zed|2|site — index.html\n", "6|Zed|2|site — index.html\n8|Ghostty|1|claude\n", "/Users/me/omv") == 1)
check.that("should not take a project whose name starts the same for this one",
  #devlayout.windowsToMove("6|Zed|2|omv-old — a.md\n", "6|Zed|2|omv-old — a.md\n", "/Users/me/omv") == 0)
check.that("should be ready once the editor and both terminals are found", devlayout.ready(moving))
check.that("should not be ready with only the terminals", not devlayout.ready({ "8", "9" }))

local rows = devlayout.rows({ "/Users/me/workspace/omv", "/Users/me/site" }, "/Users/me")
check.that("should list projects in the order given, the most recent first", rows[1].label == "omv" and rows[2].label == "site")
check.that("should name a project by its folder", rows[1].label == "omv")
check.that("should show where a project is", rows[1].hint == "~/workspace/omv")
check.that("should offer nothing when there are no projects", #devlayout.rows({}, "/Users/me") == 0)

check.finish()
