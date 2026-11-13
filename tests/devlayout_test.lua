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

local arrangedAfter = reused .. "9|Ghostty|1|~/omv\n8|Ghostty|1|✳ Claude Code\n"
local order = devlayout.ordered(arrangedAfter, { "6", "9", "8" })
check.that("should move the editor, then Claude, then the shell", table.concat(order, ",") == "6,8,9")
local arrange = devlayout.arrange("4", order)
local function joined(command) return table.concat(command, " ") end
check.that("should flatten the workspace first", joined(arrange[1]) == "flatten-workspace-tree --workspace 4")
check.that("should tile the workspace side by side", joined(arrange[2]) == "layout --workspace 4 --root tiles horizontal")
check.that("should stack the shell under Claude", joined(arrange[3]) == "join-with --window-id 9 left")
check.that("should only tile when the shell is missing", #devlayout.arrange("4", { "6", "8" }) == 2)

check.that("should open on the dev workspace", devlayout.WORKSPACE == "7")

-- Switching project: what's on the dev workspace goes back to its usual workspace.
local onDev = "21|Ghostty|7|✳ Claude Code\n22|Ghostty|7|~/omv\n23|Zed|7|omv — a.md\n24|Helium|7|docs\n"
local home = devlayout.sendHome(onDev)
local function line2(command) return table.concat(command, " ") end
check.that("should send old terminal windows home to workspace 1", line2(home[1]) == "move-node-to-workspace --window-id 21 1")
check.that("should send an old editor window home to workspace 2", line2(home[3]) == "move-node-to-workspace --window-id 23 2")
check.that("should send any other window to workspace 1", line2(home[4]) == "move-node-to-workspace --window-id 24 1")
check.that("should do nothing when the dev workspace is empty", #devlayout.sendHome("") == 0)

-- New task in a worktree.
local at = os.time({ year = 2026, month = 11, day = 13, hour = 8, min = 15, sec = 0 })
check.that("should name a task by date and time", devlayout.taskName(at) == "task-20261113-0815")
check.that("should number a task when several start together", devlayout.taskName(at, 2) == "task-20261113-0815-2")
check.that("should put the worktree outside the repo",
  devlayout.worktreePath("/Users/me", "/Users/me/workspace/omv", "task-1") == "/Users/me/.local/share/omv/worktrees/omv/task-1")
local add = devlayout.worktreeCommand("/Users/me/workspace/omv", "/w/omv/task-1", "task-1")
check.that("should create the branch with the worktree",
  add[1] .. " " .. table.concat(add[2], " ") == "/usr/bin/git -C /Users/me/workspace/omv worktree add -b task-1 /w/omv/task-1")
local inTree = devlayout.commands("/w/omv/task-1", tools)
check.that("should open the layout in the worktree", inTree[1][2][3] == "/w/omv/task-1")
local choices = devlayout.choices(true)
check.that("should offer to open the project or start a task in a worktree",
  choices[1].id == "open" and choices[2].id == "worktree")
check.that("should offer no worktree for a folder that isn't a git repo", #devlayout.choices(false) == 1)

check.that("should offer 2 to 4 agents", #devlayout.gridSizes() == 3 and devlayout.gridSizes()[3].id == "4")

local newTools = { editor = "Zed", editorCli = "/Applications/Zed.app/Contents/MacOS/cli", ghosttyWindow = "g",
  claudeIn = "c", shellIn = "s" }
local task = devlayout.commands("/w/omv/task-1", newTools, true)
check.that("should open a task's editor in a new window",
  task[1][1] .. " " .. table.concat(task[1][2], " ") == "/Applications/Zed.app/Contents/MacOS/cli -n /w/omv/task-1")
check.that("should open a project's editor where it already is",
  devlayout.commands("/w/omv", newTools)[1][1] == "/usr/bin/open")

local rows = devlayout.rows({ "/Users/me/workspace/omv", "/Users/me/site" }, "/Users/me")
check.that("should list projects in the order given, the most recent first", rows[1].label == "omv" and rows[2].label == "site")
check.that("should name a project by its folder", rows[1].label == "omv")
check.that("should show where a project is", rows[1].hint == "~/workspace/omv")
check.that("should offer nothing when there are no projects", #devlayout.rows({}, "/Users/me") == 0)

check.finish()
