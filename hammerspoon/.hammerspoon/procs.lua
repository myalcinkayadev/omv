-- The hungry process card: your processes by CPU or memory, read from ps, or your listening
-- ports, from lsof, each with the folder it runs in, also from lsof, and the card that asks
-- before quitting one.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local procs = {}

local MAX_ROWS = 20
-- Never offered: quitting loginwindow logs you out, launchd is every process's parent.
local KEPT = { loginwindow = true, launchd = true }

-- Processes from `ps -U <you> -o pid=,pcpu=,rss=,comm=`, as { pid, cpu, memory in bytes,
-- name }. selfPid is Hammerspoon's, left out with the processes in KEPT.
function procs.parse(output, selfPid)
  local list = {}
  for line in tostring(output or ""):gmatch("[^\n]+") do
    local pid, cpu, rss, command = line:match("^%s*(%d+)%s+([%d.]+)%s+(%d+)%s+(.+)$")
    if pid then
      local name = command:sub(1, 1) == "/" and command:match("([^/]+)$") or command
      if tonumber(pid) ~= selfPid and not KEPT[name] then
        list[#list + 1] = { pid = tonumber(pid), cpu = tonumber(cpu), memory = tonumber(rss) * 1024, name = name }
      end
    end
  end
  return list
end

-- The busiest first, by "cpu" or "memory", at most 20.
function procs.sorted(list, by)
  local copy = {}
  for index, process in ipairs(list) do copy[index] = process end
  table.sort(copy, function(a, b) return a[by] > b[by] end)
  local top = {}
  for index = 1, math.min(#copy, MAX_ROWS) do top[index] = copy[index] end
  return top
end

local MB, GB = 1024 * 1024, 1024 * 1024 * 1024

function procs.size(bytes)
  if bytes >= GB then return string.format("%.1f GB", bytes / GB) end
  return string.format("%d MB", math.floor(bytes / MB + 0.5))
end

-- Each process's working folder from `lsof -a -d cwd -Fpn -p <pids>`, shown from home as
-- ~/...; a process running in / has none worth showing.
function procs.folders(output, home)
  local found, pid = {}, nil
  for line in tostring(output or ""):gmatch("[^\n]+") do
    local kind, value = line:sub(1, 1), line:sub(2)
    if kind == "p" then pid = tonumber(value) end
    if kind == "n" and pid and value ~= "/" then
      found[pid] = value:sub(1, #home) == home and ("~" .. value:sub(#home + 1)) or value
    end
  end
  return found
end

-- Card rows: the name with its folder, and the sort's measure first in the hint.
function procs.rows(list, folders, by)
  local rows = {}
  for _, process in ipairs(list) do
    local cpu, memory = string.format("%.1f%%", process.cpu), procs.size(process.memory)
    local folder = folders[process.pid]
    rows[#rows + 1] = { id = tostring(process.pid), icon = "󰍛",
      label = process.name .. (folder and ("  " .. folder) or ""),
      hint = by == "memory" and (memory .. " · " .. cpu) or (cpu .. " · " .. memory) }
  end
  return rows
end

local SORTS = { cpu = "memory", memory = "ports", ports = "cpu" }

-- Tab's next view: CPU, then memory, then listening ports, then CPU again.
function procs.nextSort(by)
  return SORTS[by] or "cpu"
end

-- Listening TCP ports from `lsof -nP -iTCP -sTCP:LISTEN -Fpcn`, as { pid, port, name },
-- lowest port first. A process listening on IPv4 and IPv6 is listed once per port.
function procs.ports(output)
  local list, seen, pid, name = {}, {}, nil, nil
  for line in tostring(output or ""):gmatch("[^\n]+") do
    local kind, value = line:sub(1, 1), line:sub(2)
    if kind == "p" then pid, name = tonumber(value), nil end
    if kind == "c" then name = value end
    local port = kind == "n" and tonumber(value:match(":(%d+)$"))
    if port and pid and not seen[pid .. ":" .. port] then
      seen[pid .. ":" .. port] = true
      list[#list + 1] = { pid = pid, port = port, name = name or tostring(pid) }
    end
  end
  table.sort(list, function(a, b) return a.port < b.port end)
  return list
end

-- Card rows for ports: the port, then the process's name from ps, which lsof cuts short,
-- and its folder. The id names the port too, since one process can listen on several.
function procs.portRows(ports, processesByPid, folders)
  local rows = {}
  for _, entry in ipairs(ports) do
    local process = processesByPid[entry.pid]
    local folder = folders[entry.pid]
    rows[#rows + 1] = { id = entry.pid .. ":" .. entry.port, icon = "󰒍",
      label = ":" .. entry.port .. "  " .. (process and process.name or entry.name) .. (folder and ("  " .. folder) or ""),
      hint = process and (string.format("%.1f%%", process.cpu) .. " · " .. procs.size(process.memory)) or nil }
  end
  return rows
end

-- The card that asks before quitting, Cancel first. After a quit the process ignored,
-- it offers Force quit instead.
function procs.confirm(process, quitFailed)
  local action = quitFailed and { id = "force", icon = "󰅚", label = "Force quit" }
    or { id = "quit", icon = "󰅙", label = "Quit" }
  return {
    prompt = (quitFailed and "Still running: " or "Quit ") .. process.name .. "?",
    rows = { { id = "cancel", icon = "󰜺", label = "Cancel" }, action },
    selected = 1,
  }
end

return procs
