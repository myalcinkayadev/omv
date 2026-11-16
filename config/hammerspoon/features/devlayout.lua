-- Dev layout (Option+Space, then Dev layout): pick a recent Claude Code project, then open
-- it or start a new task in a git worktree. Its editor, Claude Code and a shell open side by
-- side on the dev workspace, 7, on the main monitor: the editor on the left half, Claude
-- over the shell on the right.
-- Agent grid (Option+Space, then Agent grid): 2 to 4 Claude sessions on a project, each in
-- its own worktree, as panes of one tmux session in a window on the dev workspace. Closing
-- the window leaves them running; picking the project again reattaches or ends them.
-- Whatever was on the dev workspace goes back to its usual workspace first, so nothing
-- still running is closed. AeroSpace sends Zed and Ghostty to their own workspaces, so the
-- new windows are found and moved.

local shell = require("shell")
local card = require("card")
local devlayout = require("devlayout")
local windows = require("windows")
local agentsCard = require("features.agents")
local agentgrid = require("agentgrid")

local feature = {}

local TOOLS = {
  ghosttyWindow = shell.GHOSTTY_WINDOW,
  claudeIn = hs.configdir .. "/claude-in.sh",
  shellIn = hs.configdir .. "/shell-in.sh",
}
-- Zed's CLI opens a folder in a new window; open -a would reuse the one already there.
local ZED_CLI = "/Applications/Zed.app/Contents/MacOS/cli"
-- How long to wait for the new windows, checking twice a second.
local WAIT_SECONDS = 10
local CHECK_SECONDS = 0.5

local function aerospace(arguments)
  return hs.execute(shell.AEROSPACE .. " " .. table.concat(arguments, " "))
end

local function listWindows()
  return hs.execute(shell.AEROSPACE .. " list-windows --all --format '" .. windows.FORMAT .. "'") or ""
end

local function clearDevWorkspace()
  local output = hs.execute(shell.AEROSPACE .. " list-windows --workspace " .. devlayout.WORKSPACE
    .. " --format '" .. windows.FORMAT .. "'") or ""
  for _, command in ipairs(devlayout.sendHome(output)) do aerospace(command) end
end

local function launch(commands)
  for _, command in ipairs(commands) do hs.task.new(command[1], nil, command[2]):start() end
end

-- Waits until found(listWindows()) says the windows are there, or 10 seconds pass, then
-- hands them to done. The timer is kept on the feature: one nothing refers to can be
-- collected before it fires.
local function waitFor(found, ready, done, waited)
  local ids = found(listWindows())
  if not ready(ids) and waited < WAIT_SECONDS then
    feature.waiting = hs.timer.doAfter(CHECK_SECONDS, function() waitFor(found, ready, done, waited + CHECK_SECONDS) end)
    return
  end
  done(ids)
end

-- Moves the windows in order, lays them out, then goes to the dev workspace.
local function place(ordered, layout)
  local workspace = devlayout.WORKSPACE
  for _, id in ipairs(ordered) do aerospace({ "move-node-to-workspace", "--window-id", id, workspace }) end
  for _, command in ipairs(layout(workspace, ordered)) do aerospace(command) end
  aerospace({ "workspace", workspace })
end

-- newWindow opens the editor in a window of its own, for a task's new folder.
local function start(folder, editor, newWindow)
  clearDevWorkspace()
  local before = listWindows()
  local cli = editor == "Zed" and hs.fs.attributes(ZED_CLI) and ZED_CLI or nil
  launch(devlayout.commands(folder, { editor = editor, editorCli = cli, ghosttyWindow = TOOLS.ghosttyWindow,
    claudeIn = TOOLS.claudeIn, shellIn = TOOLS.shellIn }, newWindow))
  waitFor(function(after) return devlayout.windowsToMove(before, after, folder) end, devlayout.ready, function(ids)
    -- Moved in order, so the editor ends up left, then Claude, then the shell.
    place(devlayout.ordered(listWindows(), ids), devlayout.arrange)
  end, 0)
end

local function isRepo(folder)
  local _, ok = hs.execute("/usr/bin/git -C " .. devlayout.quote(folder) .. " rev-parse --git-dir 2>/dev/null")
  return ok == true
end

-- A new branch and folder for a task; nil, with an alert, when git refuses.
local function makeWorktree(folder, index)
  local name = devlayout.taskName(os.time(), index)
  local path = devlayout.worktreePath(shell.HOME, folder, name)
  local command = devlayout.worktreeCommand(folder, path, name)
  local quoted = {}
  for _, argument in ipairs(command[2]) do quoted[#quoted + 1] = devlayout.quote(argument) end
  local output, ok = hs.execute(command[1] .. " " .. table.concat(quoted, " ") .. " 2>&1")
  if ok then return path end
  shell.alert("Couldn't make a worktree: " .. (output or ""):gsub("%s+$", ""), 3)
  return nil
end

local function showList(name, prompt, rows, onPick)
  shell.show(name, shell.centered(shell.LIST_WIDTH, shell.listHeight(math.max(1, #rows))),
    card.html({ prompt = prompt, rows = rows, compact = true, hint = "No Claude Code projects yet" }), function(message)
      if message.type ~= "choose" then return shell.close() end
      onPick(message.id)
    end)
end

local function startClosed(action)
  shell.leaveFocus()
  shell.close()
  action()
end

-- A new task in a worktree of folder, opened as the dev layout. Also callable from the console.
function feature.startTask(folder, editor)
  local path = makeWorktree(folder)
  if path then start(path, editor, true) end
end

-- editor is the app the editor key opens, from ~/.config/omv/apps.
function feature.open(editor)
  showList("devlayout", "Dev layout for…", devlayout.rows(agentsCard.projects(), shell.HOME), function(folder)
    if not isRepo(folder) then return startClosed(function() start(folder, editor) end) end
    showList("devlayout-choice", folder:match("([^/]+)/*$") .. "…", devlayout.choices(true), function(choice)
      startClosed(function()
        if choice == "open" then return start(folder, editor) end
        feature.startTask(folder, editor)
      end)
    end)
  end)
end

local TMUX = "/opt/homebrew/bin/tmux"

-- Output goes through a file: the tmux server new-session starts would otherwise inherit
-- hs.execute's pipe and keep it open, so hs.execute would never return.
local function tmux(arguments)
  local quoted = {}
  for _, argument in ipairs(arguments) do quoted[#quoted + 1] = devlayout.quote(argument) end
  local log = os.tmpname()
  local _, ok = hs.execute(TMUX .. " " .. table.concat(quoted, " ") .. " > " .. devlayout.quote(log) .. " 2>&1 < /dev/null")
  local output = shell.readText(log) or ""
  os.remove(log)
  return output, ok
end

-- A Ghostty window attached to the grid's session, alone on the dev workspace.
local function attach(session)
  clearDevWorkspace()
  local before = listWindows()
  launch({ { TOOLS.ghosttyWindow, { agentgrid.attachCommand(session, TMUX) } } })
  waitFor(function(after) return devlayout.newWindows(before, after) end,
    function(ids) return #ids >= 1 end,
    function(ids) place(ids, devlayout.arrange) end, 0)
end

-- Also callable from the console: feature.startGrid("/path/to/repo", 2).
function feature.startGrid(folder, count)
  if not hs.fs.attributes(TMUX) then return shell.alert("The agent grid needs tmux: brew install tmux", 3) end
  local paths = {}
  for index = 1, count do
    local path = makeWorktree(folder, index)
    if not path then return end
    paths[#paths + 1] = path
  end
  local session = agentgrid.sessionName(folder)
  for _, command in ipairs(agentgrid.startCommands(session, paths, TOOLS.claudeIn)) do
    local output, ok = tmux(command)
    if not ok then return shell.alert("tmux: " .. (output or ""):gsub("%s+$", ""), 3) end
  end
  attach(session)
end

local function runningGrids()
  if not hs.fs.attributes(TMUX) then return {} end
  return agentgrid.running(hs.execute(TMUX .. " list-sessions -F '#{session_name}' 2>/dev/null"))
end

-- Reattaches a running grid on the dev workspace. Also callable from the console.
function feature.reattach(folder)
  attach(agentgrid.sessionName(folder))
end

local function runningGrid(folder)
  local session = agentgrid.sessionName(folder)
  local project = folder:match("([^/]+)/*$")
  showList("devlayout-grid", project .. "…", agentgrid.runningChoices(), function(choice)
    if choice == "reattach" then return startClosed(function() attach(session) end) end
    local confirm = agentgrid.confirmEnd(project)
    showList("devlayout-grid", confirm.prompt, confirm.rows, function(confirmed)
      shell.close()
      if confirmed ~= "end.confirmed" then return end
      tmux({ "kill-session", "-t", session })
      shell.alert("Ended " .. project .. "'s agents; the worktrees stay", 2)
    end)
  end)
end

function feature.openGrid()
  local running = runningGrids()
  local rows = agentgrid.projectRows(devlayout.rows(agentsCard.projects(), shell.HOME), running)
  showList("devlayout", "Agent grid for…", rows, function(folder)
    if running[agentgrid.sessionName(folder)] then return runningGrid(folder) end
    if not isRepo(folder) then
      shell.close()
      return shell.alert("The agent grid needs a git repository", 2)
    end
    showList("devlayout-grid", "How many agents?", devlayout.gridSizes(), function(size)
      startClosed(function() feature.startGrid(folder, tonumber(size)) end)
    end)
  end)
end

return feature
