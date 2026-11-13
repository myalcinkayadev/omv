-- Behavior of the agent grid: a tmux session with a Claude pane per worktree, reattaching
-- to it, ending it, and finding a waiting agent's pane. Run through agentgrid_test.sh.

local check = dofile(arg[1] .. "/tests/check.lua")
local grid = require("agentgrid")

local function line(command) return table.concat(command, " ") end

check.that("should name the session after the project", grid.sessionName("/Users/me/workspace/omv") == "omv-omv")
check.that("should make a session name tmux accepts", grid.sessionName("/Users/me/my.app:v2") == "omv-my-app-v2")

local start = grid.startCommands("omv-x", { "/w/t-1", "/w/my t-2", "/w/t-3" }, "/h/claude-in.sh")
check.that("should start the session with the first agent",
  line(start[1]) == "new-session -d -s omv-x -c /w/t-1 /h/claude-in.sh '/w/t-1'")
check.that("should add a pane per further agent",
  start[2][1] == "split-window" and start[3][1] == "split-window" and start[3][5] == "/w/t-3")
check.that("should quote worktree paths with spaces", start[2][6] == "/h/claude-in.sh '/w/my t-2'")
check.that("should put 3 agents side by side", line(start[4]) == "select-layout -t omv-x even-horizontal")
local two = grid.startCommands("omv-x", { "/w/1", "/w/2" }, "c")
check.that("should put 2 agents side by side", line(two[3]) == "select-layout -t omv-x even-horizontal")
local four = grid.startCommands("omv-x", { "/w/1", "/w/2", "/w/3", "/w/4" }, "c")
check.that("should put 4 agents in a 2x2 grid", line(four[5]) == "select-layout -t omv-x tiled")
check.that("should give the status bar the theme's background",
  line(start[6]) == "set-option -t omv-x status-style bg=default,fg=colour244")
check.that("should turn on mouse scrolling for the session", line(start[5]) == "set-option -t omv-x mouse on")
check.that("should attach in a Ghostty window", grid.attachCommand("omv-x", "/opt/homebrew/bin/tmux")
  == "/opt/homebrew/bin/tmux attach -t omv-x")

local running = grid.running("omv-omv\nsomething-else\n")
check.that("should read the running grids", running["omv-omv"] and not running["omv-site"])
check.that("should read no grids when tmux has no server", next(grid.running("")) == nil)
local rows = grid.projectRows({ { id = "/w/omv", label = "omv", hint = "~/w/omv" }, { id = "/w/site", label = "site" } }, running)
check.that("should mark a project with a running grid", rows[1].hint == "running")
check.that("should leave a project without one as it was", rows[2].hint == nil)
local choices = grid.runningChoices()
check.that("should offer reattach or end for a running grid", choices[1].id == "reattach" and choices[2].id == "end")
local confirm = grid.confirmEnd("omv")
check.that("should ask before ending all agents, with Cancel selected",
  confirm.rows[1].id == "cancel" and confirm.selected == 1 and confirm.rows[2].id == "end.confirmed")

local panes = "/dev/ttys004 omv-omv:0.0\n/dev/ttys005 omv-omv:0.1\n/dev/ttys006 work:1.0\n"
check.that("should find the tmux pane for a waiting session's terminal", grid.paneFor(panes, "/dev/ttys005") == "omv-omv:0.1")
check.that("should find no pane for a terminal outside tmux", grid.paneFor(panes, "/dev/ttys009") == nil)
local clients = "/dev/ttys010 omv-omv\n/dev/ttys011 work\n"
check.that("should find the terminal attached to that session", grid.clientFor(clients, "omv-omv:0.1") == "/dev/ttys010")
check.that("should find no terminal for a detached session", grid.clientFor(clients, "omv-site:0.0") == nil)

check.finish()
