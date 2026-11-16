-- The dev layout: a project's editor, Claude Code and a shell, on one workspace. AeroSpace
-- sends each app to its own workspace, so the new windows are found and moved afterwards.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local windows = require("windows")
local agents = require("agents")

local devlayout = {}

devlayout.quote = agents.shellQuote

-- The dev workspace: no app is sent there, so the layout has the screen to itself.
devlayout.WORKSPACE = "7"

-- The apps the layout opens, as AeroSpace names them.
local APPS = { Zed = true, Ghostty = true }

-- tools = { editor, editorCli, ghosttyWindow, claudeIn, shellIn }. Returns { program, arguments }
-- each. A new task's folder opens in a new editor window, through the editor's CLI when there
-- is one; a project opens wherever the editor already has it.
function devlayout.commands(folder, tools, newWindow)
  local quoted = agents.shellQuote(folder)
  local editor = (newWindow and tools.editorCli) and { tools.editorCli, { "-n", folder } }
    or { "/usr/bin/open", { "-a", tools.editor, folder } }
  return {
    editor,
    { tools.ghosttyWindow, { tools.claudeIn .. " " .. quoted } },
    { tools.ghosttyWindow, { tools.shellIn .. " " .. quoted } },
  }
end

local function ids(output)
  local found = {}
  for _, row in ipairs(windows.rows(output)) do found[row.id] = row.hint:match("^(.-) · ") end
  return found
end

-- The ids of the editor and terminal windows in after that weren't in before, in order.
function devlayout.newWindows(before, after)
  local old, fresh = ids(before), {}
  for _, row in ipairs(windows.rows(after)) do
    local app = row.hint:match("^(.-) · ")
    if not old[row.id] and APPS[app] then fresh[#fresh + 1] = row.id end
  end
  return fresh
end

-- Zed names a window after its project: "omv — README.md".
local function editorFor(output, folder)
  local name = folder:match("([^/]+)/*$")
  for line in output:gmatch("[^\n]+") do
    local id, app, title = line:match("^(%d+)|([^|]*)|[^|]*|(.*)$")
    local prefix = name .. " — "
    if app == "Zed" and (title == name or title:sub(1, #prefix) == prefix) then return id end
  end
  return nil
end

-- The windows to gather: the editor's, new or already open on the project, then the new
-- terminals. Zed reuses a window already open on the folder rather than opening another.
function devlayout.windowsToMove(before, after, folder)
  local fresh = devlayout.newWindows(before, after)
  local editor = editorFor(after, folder)
  local ids = editor and { editor } or {}
  for _, id in ipairs(fresh) do
    if id ~= editor then ids[#ids + 1] = id end
  end
  return ids
end

-- All three windows are there: the editor and two terminals.
function devlayout.ready(ids)
  return #ids >= 3
end

-- The editor, Claude's window, then the shell, in that order, whatever order they opened in;
-- Claude's terminal is the one titled after Claude Code.
function devlayout.ordered(output, ids)
  local titles = {}
  for line in output:gmatch("[^\n]+") do
    local id, app, title = line:match("^(%d+)|([^|]*)|[^|]*|(.*)$")
    if id then titles[id] = { app = app, title = title } end
  end
  local editor, claude, others = {}, {}, {}
  for _, id in ipairs(ids) do
    local window = titles[id] or { app = "", title = "" }
    if window.app == "Zed" then editor[#editor + 1] = id
    elseif window.title:find("Claude", 1, true) then claude[#claude + 1] = id
    else others[#others + 1] = id end
  end
  local result = {}
  for _, group in ipairs({ editor, claude, others }) do
    for _, id in ipairs(group) do result[#result + 1] = id end
  end
  return result
end

-- AeroSpace commands that lay the moved windows out: side by side, the shell under Claude.
-- A workspace may be stacked, so its tree is flattened and tiled first.
function devlayout.arrange(workspace, ordered)
  local commands = {
    { "flatten-workspace-tree", "--workspace", workspace },
    { "layout", "--workspace", workspace, "--root", "tiles", "horizontal" },
  }
  if ordered[3] then commands[#commands + 1] = { "join-with", "--window-id", ordered[3], "left" } end
  return commands
end

-- Where each app's windows usually live; anything else goes to workspace 1.
local HOMES = { Zed = "2", Ghostty = "1" }

-- Commands that send the windows on the dev workspace back to their usual workspaces, so a
-- new layout starts clean without closing anything still running there.
function devlayout.sendHome(output)
  local commands = {}
  for line in output:gmatch("[^\n]+") do
    local id, app = line:match("^(%d+)|([^|]*)|")
    if id then commands[#commands + 1] = { "move-node-to-workspace", "--window-id", id, HOMES[app] or "1" } end
  end
  return commands
end

-- A task's branch and folder name, from when it started; numbered when several start at once.
function devlayout.taskName(time, index)
  return os.date("task-%Y%m%d-%H%M", time) .. (index and ("-" .. index) or "")
end

-- Worktrees live outside the repo, so its git status stays clean.
function devlayout.worktreePath(home, folder, name)
  return home .. "/.local/share/omv/worktrees/" .. folder:match("([^/]+)/*$") .. "/" .. name
end

function devlayout.worktreeCommand(folder, path, name)
  return { "/usr/bin/git", { "-C", folder, "worktree", "add", "-b", name, path } }
end

-- What to do with a picked project; a worktree only for a git repo.
function devlayout.choices(isRepo)
  local rows = { { id = "open", icon = "󰉋", label = "Open project" } }
  if isRepo then rows[2] = { id = "worktree", icon = "󰘬", label = "New task in a worktree", hint = "own branch" } end
  return rows
end

function devlayout.gridSizes()
  return {
    { id = "2", icon = "󰕰", label = "2 agents" },
    { id = "3", icon = "󰕰", label = "3 agents" },
    { id = "4", icon = "󰕰", label = "4 agents" },
  }
end

function devlayout.rows(folders, home)
  return agents.projectRows(folders, home)
end

return devlayout
