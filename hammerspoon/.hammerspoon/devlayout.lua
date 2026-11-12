-- The dev layout: a project's editor, Claude Code and a shell, on one workspace. AeroSpace
-- sends each app to its own workspace, so the new windows are found and moved afterwards.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local windows = require("windows")
local agents = require("agents")

local devlayout = {}

-- The apps the layout opens, as AeroSpace names them.
local APPS = { Zed = true, Ghostty = true }

-- tools = { editor, ghosttyWindow, claudeIn, shellIn }. Returns { program, arguments } each.
function devlayout.commands(folder, tools)
  local quoted = agents.shellQuote(folder)
  return {
    { "/usr/bin/open", { "-a", tools.editor, folder } },
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

function devlayout.rows(folders, home)
  return agents.projectRows(folders, home)
end

return devlayout
