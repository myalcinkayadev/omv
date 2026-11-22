-- Dev layout (Option+Space, then Dev layout): pick a recent Claude Code project, then open
-- it or start a new task in a git worktree. Its editor, Claude Code and a shell open side by
-- side on the dev workspace, 7 unless ~/.config/omv/workspaces says otherwise: the editor on the left half, Claude
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
-- The projects Claude Code knows, read without loading the Agents card, so the claude flag
-- keeps its watchers off.
local projects = require("features.claudeprojects").projects
local agentgrid = require("agentgrid")
local workspaces = require("workspaces")

local feature = {}

-- The dev workspace from ~/.config/omv/workspaces, read when omv reloads.
devlayout.WORKSPACE = workspaces.devWorkspace(workspaces.parse(shell.readText(workspaces.PATH)))

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

-- Every call here runs in the background, so the cards and keys stay live while the layout
-- opens. Each step starts when the one before has finished.

-- Runs step(item, next) on each of items in turn, then calls done.
local function inTurn(items, step, done, index)
  index = index or 1
  if not items[index] then return done and done() end
  step(items[index], function() inTurn(items, step, done, index + 1) end)
end

local function aerospaceAll(commands, done)
  inTurn(commands, function(arguments, next)
    hs.task.new(shell.AEROSPACE, function() next() end, arguments):start()
  end, done)
end

local function listWindows(done)
  shell.execute(shell.AEROSPACE .. " list-windows --all --format '" .. windows.FORMAT .. "'", done)
end

local function clearDevWorkspace(done)
  shell.execute(shell.AEROSPACE .. " list-windows --workspace " .. devlayout.WORKSPACE
    .. " --format '" .. windows.FORMAT .. "'", function(output)
    aerospaceAll(devlayout.sendHome(output), done)
  end)
end

local function launch(commands)
  for _, command in ipairs(commands) do hs.task.new(command[1], nil, command[2]):start() end
end

-- Waits until found(listWindows()) says the windows are there, or 10 seconds pass, then
-- hands them to done. The timer is kept on the feature: one nothing refers to can be
-- collected before it fires.
local function waitFor(found, ready, done, waited)
  listWindows(function(output)
    local ids = found(output)
    if not ready(ids) and waited < WAIT_SECONDS then
      feature.waiting = hs.timer.doAfter(CHECK_SECONDS, function() waitFor(found, ready, done, waited + CHECK_SECONDS) end)
      return
    end
    done(ids, output)
  end)
end

-- Moves the windows in order, lays them out, then goes to the dev workspace.
local function place(ordered, layout)
  local workspace = devlayout.WORKSPACE
  local commands = {}
  for _, id in ipairs(ordered) do commands[#commands + 1] = { "move-node-to-workspace", "--window-id", id, workspace } end
  for _, command in ipairs(layout(workspace, ordered)) do commands[#commands + 1] = command end
  commands[#commands + 1] = { "workspace", workspace }
  aerospaceAll(commands)
end

-- newWindow opens the editor in a window of its own, for a task's new folder.
local function start(folder, editor, newWindow)
  clearDevWorkspace(function()
    listWindows(function(before)
      local cli = editor == "Zed" and hs.fs.attributes(ZED_CLI) and ZED_CLI or nil
      launch(devlayout.commands(folder, { editor = editor, editorCli = cli, ghosttyWindow = TOOLS.ghosttyWindow,
        claudeIn = TOOLS.claudeIn, shellIn = TOOLS.shellIn }, newWindow))
      waitFor(function(after) return devlayout.windowsToMove(before, after, folder) end, devlayout.ready, function(ids, after)
        -- Moved in order, so the editor ends up left, then Claude, then the shell.
        place(devlayout.ordered(after, ids), devlayout.arrange)
      end, 0)
    end)
  end)
end

local function isRepo(folder, done)
  shell.execute("/usr/bin/git -C " .. devlayout.quote(folder) .. " rev-parse --git-dir 2>/dev/null", function(_, ok)
    done(ok)
  end)
end

-- Hands done a new branch and folder for a task; nil, with an alert, when git refuses.
local function makeWorktree(folder, index, done)
  local name = devlayout.taskName(os.time(), index)
  local path = devlayout.worktreePath(shell.HOME, folder, name)
  local command = devlayout.worktreeCommand(folder, path, name)
  local quoted = {}
  for _, argument in ipairs(command[2]) do quoted[#quoted + 1] = devlayout.quote(argument) end
  shell.execute(command[1] .. " " .. table.concat(quoted, " ") .. " 2>&1", function(output, ok)
    if ok then return done(path) end
    shell.alert("Couldn't make a worktree: " .. output:gsub("%s+$", ""), 3)
    done(nil)
  end)
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
  makeWorktree(folder, nil, function(path)
    if path then start(path, editor, true) end
  end)
end

-- editor is the app the editor key opens, from ~/.config/omv/apps.
function feature.open(editor)
  projects(function(found)
    showList("devlayout", "Dev layout for…", devlayout.rows(found, shell.HOME), function(folder)
      isRepo(folder, function(repo)
        if not repo then return startClosed(function() start(folder, editor) end) end
        showList("devlayout-choice", folder:match("([^/]+)/*$") .. "…", devlayout.choices(true), function(choice)
          startClosed(function()
            if choice == "open" then return start(folder, editor) end
            feature.startTask(folder, editor)
          end)
        end)
      end)
    end)
  end)
end

local TMUX = "/opt/homebrew/bin/tmux"

-- Output goes through a file: the tmux server new-session starts would otherwise inherit
-- the task's pipe and keep it open, so the task would never be seen to finish.
local function tmux(arguments, done)
  local quoted = {}
  for _, argument in ipairs(arguments) do quoted[#quoted + 1] = devlayout.quote(argument) end
  local log = os.tmpname()
  shell.execute(TMUX .. " " .. table.concat(quoted, " ") .. " > " .. devlayout.quote(log) .. " 2>&1 < /dev/null", function(_, ok)
    local output = shell.readText(log) or ""
    os.remove(log)
    if done then done(output, ok) end
  end)
end

-- A Ghostty window attached to the grid's session, alone on the dev workspace.
local function attach(session)
  clearDevWorkspace(function()
    listWindows(function(before)
      launch({ { TOOLS.ghosttyWindow, { agentgrid.attachCommand(session, TMUX) } } })
      waitFor(function(after) return devlayout.newWindows(before, after) end,
        function(ids) return #ids >= 1 end,
        function(ids) place(ids, devlayout.arrange) end, 0)
    end)
  end)
end

-- Hands done a worktree for each of count agents, or nil when git refuses one.
local function makeWorktrees(folder, count, done, paths)
  paths = paths or {}
  if #paths == count then return done(paths) end
  makeWorktree(folder, #paths + 1, function(path)
    if not path then return done(nil) end
    paths[#paths + 1] = path
    makeWorktrees(folder, count, done, paths)
  end)
end

-- Runs the tmux commands in turn, stopping with an alert at the first that fails.
local function runTmux(commands, done, index)
  index = index or 1
  if not commands[index] then return done() end
  tmux(commands[index], function(output, ok)
    if not ok then return shell.alert("tmux: " .. output:gsub("%s+$", ""), 3) end
    runTmux(commands, done, index + 1)
  end)
end

-- Also callable from the console: feature.startGrid("/path/to/repo", 2).
function feature.startGrid(folder, count)
  if not hs.fs.attributes(TMUX) then return shell.alert("The agent grid needs tmux: brew install tmux", 3) end
  makeWorktrees(folder, count, function(paths)
    if not paths then return end
    local session = agentgrid.sessionName(folder)
    runTmux(agentgrid.startCommands(session, paths, TOOLS.claudeIn), function() attach(session) end)
  end)
end

local function runningGrids(done)
  if not hs.fs.attributes(TMUX) then return done({}) end
  shell.execute(TMUX .. " list-sessions -F '#{session_name}' 2>/dev/null", function(output)
    done(agentgrid.running(output))
  end)
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

local function pickGridSize(folder)
  isRepo(folder, function(repo)
    if not repo then
      shell.close()
      return shell.alert("The agent grid needs a git repository", 2)
    end
    showList("devlayout-grid", "How many agents?", devlayout.gridSizes(), function(size)
      startClosed(function() feature.startGrid(folder, tonumber(size)) end)
    end)
  end)
end

function feature.openGrid()
  runningGrids(function(running)
    projects(function(found)
      local rows = agentgrid.projectRows(devlayout.rows(found, shell.HOME), running)
      showList("devlayout", "Agent grid for…", rows, function(folder)
        if running[agentgrid.sessionName(folder)] then return runningGrid(folder) end
        pickGridSize(folder)
      end)
    end)
  end)
end

return feature
