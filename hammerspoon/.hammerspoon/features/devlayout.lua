-- Dev layout (Option+Space, then Dev layout): pick a recent Claude Code project, and its
-- editor, Claude Code and a shell open side by side on the current workspace. AeroSpace
-- sends Zed and Ghostty to their own workspaces, so the new windows are found and moved.

local shell = require("shell")
local card = require("card")
local devlayout = require("devlayout")
local windows = require("windows")
local agentsCard = require("features.agents")

local feature = {}

local TOOLS = {
  ghosttyWindow = shell.GHOSTTY_WINDOW,
  claudeIn = hs.configdir .. "/claude-in.sh",
  shellIn = hs.configdir .. "/shell-in.sh",
}
-- How long to wait for the three windows, checking twice a second.
local WAIT_SECONDS = 10
local CHECK_SECONDS = 0.5

local function listWindows()
  return hs.execute(shell.AEROSPACE .. " list-windows --all --format '" .. windows.FORMAT .. "'") or ""
end

-- Moves the project's windows to workspace, then goes there; stops waiting after 10 seconds.
local function gather(before, folder, workspace, waited)
  local found = devlayout.windowsToMove(before, listWindows(), folder)
  if not devlayout.ready(found) and waited < WAIT_SECONDS then
    return hs.timer.doAfter(CHECK_SECONDS, function() gather(before, folder, workspace, waited + CHECK_SECONDS) end)
  end
  for _, id in ipairs(found) do
    hs.execute(shell.AEROSPACE .. " move-node-to-workspace --window-id " .. id .. " " .. workspace)
  end
  hs.execute(shell.AEROSPACE .. " workspace " .. workspace)
end

local function start(folder, editor)
  local workspace = (hs.execute(shell.AEROSPACE .. " list-workspaces --focused") or ""):match("%S+")
  if not workspace then return shell.alert("Couldn't read the current workspace", 1.5) end
  local before = listWindows()
  for _, command in ipairs(devlayout.commands(folder, { editor = editor, ghosttyWindow = TOOLS.ghosttyWindow,
    claudeIn = TOOLS.claudeIn, shellIn = TOOLS.shellIn })) do
    hs.task.new(command[1], nil, command[2]):start()
  end
  gather(before, folder, workspace, 0)
end

-- editor is the app the editor key opens, from ~/.config/omv/apps.
function feature.open(editor)
  local rows = devlayout.rows(agentsCard.projects(), shell.HOME)
  local screen = { prompt = "Dev layout for…", rows = rows, compact = true, hint = "No Claude Code projects yet" }
  shell.show("devlayout", shell.centered(shell.LIST_WIDTH, shell.listHeight(math.max(1, #rows))), card.html(screen),
    function(message)
      if message.type ~= "choose" then return shell.close() end
      shell.leaveFocus()
      shell.close()
      start(message.id, editor)
    end)
end

return feature
