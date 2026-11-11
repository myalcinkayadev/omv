-- Hungry processes (Option+Shift+P): your busiest processes, by CPU or, after Tab, by
-- memory, each with the folder it runs in, so a dev server an agent left behind is easy to
-- tell apart. Enter asks, then quits it; if it's still running 3 seconds later, the card
-- offers Force quit.

local shell = require("shell")
local card = require("card")
local procs = require("procs")

local feature = {}

local WIDTH = 720
local VISIBLE_ROWS = 14
local QUIT_WAIT_SECONDS = 3
local USER_ID = (hs.execute("/usr/bin/id -u") or ""):match("%d+") or "0"

local sortBy = "cpu"
local shown = {}
local showList, showConfirm

local function alive(pid)
  return os.execute("/bin/kill -0 " .. pid .. " 2>/dev/null") == true
end

local function read()
  local output = hs.execute("/bin/ps -U " .. USER_ID .. " -o pid=,pcpu=,rss=,comm=")
  local list = procs.sorted(procs.parse(output, hs.processInfo.processID), sortBy)
  local pids = {}
  for index, process in ipairs(list) do pids[index] = process.pid end
  local folders = #pids > 0 and procs.folders(hs.execute("/usr/sbin/lsof -a -d cwd -Fpn -p " .. table.concat(pids, ",") .. " 2>/dev/null"), shell.HOME) or {}
  return list, folders
end

local function quit(process)
  shell.close()
  os.execute("/bin/kill -TERM " .. process.pid .. " 2>/dev/null")
  -- A process that saves before it goes gets a moment; one that ignores the request is offered Force quit.
  hs.timer.doAfter(QUIT_WAIT_SECONDS, function()
    if alive(process.pid) then return showConfirm(process, true) end
    shell.alert("Quit " .. process.name, 1.2)
  end)
end

local function forceQuit(process)
  shell.close()
  os.execute("/bin/kill -KILL " .. process.pid .. " 2>/dev/null")
  shell.alert("Force quit " .. process.name, 1.2)
end

showConfirm = function(process, quitFailed)
  local screen = procs.confirm(process, quitFailed)
  shell.show("procs-confirm", shell.centered(shell.MENU_WIDTH + 120, shell.menuHeight(screen)), card.html(screen), function(message)
    if message.type == "back" then return showList() end
    if message.type ~= "choose" then return shell.close() end
    if message.id == "quit" then return quit(process) end
    if message.id == "force" then return forceQuit(process) end
    showList()
  end)
end

showList = function()
  local list, folders = read()
  shown = {}
  for _, process in ipairs(list) do shown[tostring(process.pid)] = process end
  local screen = { prompt = sortBy == "cpu" and "Processes by CPU…" or "Processes by memory…",
    rows = procs.rows(list, folders, sortBy), compact = true, tab = true, hint = "No processes" }
  shell.show("procs", shell.centered(WIDTH, shell.listHeight(math.max(1, #screen.rows), VISIBLE_ROWS)), card.html(screen), function(message)
    if message.type == "tab" then
      sortBy = sortBy == "cpu" and "memory" or "cpu"
      return showList()
    end
    if message.type ~= "choose" then return shell.close() end
    local process = shown[message.id]
    if process then showConfirm(process, false) end
  end)
end

function feature.toggle()
  if shell.isOpen("procs", "procs-confirm") then return shell.close() end
  sortBy = "cpu"
  showList()
end

return feature
