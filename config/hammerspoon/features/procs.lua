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

local sortBy = "cpu"
local shown = {}
local showList, showConfirm

local function alive(pid)
  return os.execute("/bin/kill -0 " .. pid .. " 2>/dev/null") == true
end

-- ps and lsof run in the background: lsof can take a second or more, which would freeze the
-- cards while it reads.

local function readFolders(pids, done)
  if #pids == 0 then return done({}) end
  shell.execute("/usr/sbin/lsof -a -d cwd -Fpn -p " .. table.concat(pids, ",") .. " 2>/dev/null", function(output)
    done(procs.folders(output, shell.HOME))
  end)
end

local function readProcesses(done)
  shell.execute("/bin/ps -U \"$(/usr/bin/id -u)\" -o pid=,pcpu=,rss=,comm=", function(output)
    done(procs.parse(output, hs.processInfo.processID))
  end)
end

-- Hands done the busiest processes, as card rows, and each process by its row's id.
local function readBusiest(done)
  readProcesses(function(processes)
    local list = procs.sorted(processes, sortBy)
    local pids, byId = {}, {}
    for index, process in ipairs(list) do
      pids[index] = process.pid
      byId[tostring(process.pid)] = process
    end
    readFolders(pids, function(folders) done(procs.rows(list, folders, sortBy), byId) end)
  end)
end

-- Hands done your listening TCP ports, as card rows, and each process by its row's id. lsof
-- lists only your own processes without sudo, and Hammerspoon's own ports are never offered.
local function readPorts(done)
  readProcesses(function(processes)
    local byPid = {}
    for _, process in ipairs(processes) do byPid[process.pid] = process end
    shell.execute("/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpcn 2>/dev/null", function(output)
      local ports, pids, byId = {}, {}, {}
      for _, entry in ipairs(procs.ports(output)) do
        if entry.pid ~= hs.processInfo.processID then
          ports[#ports + 1] = entry
          pids[#pids + 1] = entry.pid
          byId[entry.pid .. ":" .. entry.port] = byPid[entry.pid] or { pid = entry.pid, name = entry.name }
        end
      end
      readFolders(pids, function(folders) done(procs.portRows(ports, byPid, folders), byId) end)
    end)
  end)
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

-- Counts the lists asked for, so only the last one asked is drawn when Tab is pressed quickly.
local asked = 0

local function drawList(rows)
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

showList = function()
  asked = asked + 1
  local this = asked
  local read = sortBy == "ports" and readPorts or readBusiest
  read(function(rows, byId)
    if this ~= asked then return end
    shown = byId
    drawList(rows)
  end)
end

function feature.toggle()
  if shell.isOpen("procs", "procs-confirm") then return shell.close() end
  sortBy = "cpu"
  showList()
end

return feature
