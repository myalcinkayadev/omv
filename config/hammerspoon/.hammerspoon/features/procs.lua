-- Hungry processes (Option+Shift+P): your busiest processes, by CPU or, after Tab, by
-- memory, then your listening ports, each with the folder it runs in, so a dev server an
-- agent left behind is easy to tell apart. Enter asks, then quits it; if it's still running 3 seconds later, the card
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

local function readFolders(pids)
  if #pids == 0 then return {} end
  return procs.folders(hs.execute("/usr/sbin/lsof -a -d cwd -Fpn -p " .. table.concat(pids, ",") .. " 2>/dev/null"), shell.HOME)
end

local function readProcesses()
  return procs.parse(hs.execute("/bin/ps -U " .. USER_ID .. " -o pid=,pcpu=,rss=,comm="), hs.processInfo.processID)
end

-- The busiest processes, as card rows, each process kept by its row's id.
local function readBusiest()
  local list = procs.sorted(readProcesses(), sortBy)
  local pids, byId = {}, {}
  for index, process in ipairs(list) do
    pids[index] = process.pid
    byId[tostring(process.pid)] = process
  end
  return procs.rows(list, readFolders(pids), sortBy), byId
end

-- Your listening TCP ports, as card rows. lsof lists only your own processes without sudo,
-- and Hammerspoon's own ports are never offered.
local function readPorts()
  local ports, byPid, pids, byId = {}, {}, {}, {}
  for _, process in ipairs(readProcesses()) do byPid[process.pid] = process end
  for _, entry in ipairs(procs.ports(hs.execute("/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpcn 2>/dev/null"))) do
    if entry.pid ~= hs.processInfo.processID then
      ports[#ports + 1] = entry
      pids[#pids + 1] = entry.pid
      byId[entry.pid .. ":" .. entry.port] = byPid[entry.pid] or { pid = entry.pid, name = entry.name }
    end
  end
  return procs.portRows(ports, byPid, readFolders(pids)), byId
end

local PROMPTS = { cpu = "Processes by CPU…", memory = "Processes by memory…", ports = "Listening ports…" }
local EMPTY = { cpu = "No processes", memory = "No processes", ports = "No listening ports" }

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
  local rows
  if sortBy == "ports" then rows, shown = readPorts() else rows, shown = readBusiest() end
  local screen = { prompt = PROMPTS[sortBy], rows = rows, compact = true, tab = true, hint = EMPTY[sortBy] }
  shell.show("procs", shell.centered(WIDTH, shell.listHeight(math.max(1, #screen.rows), VISIBLE_ROWS)), card.html(screen), function(message)
    if message.type == "tab" then
      sortBy = procs.nextSort(sortBy)
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
