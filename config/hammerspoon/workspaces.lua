-- Workspaces: ~/.config/omv/workspaces says which workspaces exist, 1 to 9, and the screen
-- each one sits on by default. omv builds AeroSpace's workspace keys and pins from it, and the
-- bar draws one item each. A display profile can move a workspace to another screen.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit; the aerospace.toml
-- build loads it, and the bar and omv doctor run it as a script:
--   luajit workspaces.lua numbers <file>    the workspaces, space-separated
--   luajit workspaces.lua check <file>      each problem in the file; fails when there's one

local workspaces = {}

workspaces.PATH = (os.getenv("HOME") or "") .. "/.config/omv/workspaces"

-- Today's workspaces: 1 to 3 and the dev workspace 7 on the main screen, 4 to 6 on the next.
local DEFAULT_SCREENS = { "main", "main", "main", "screen 2", "screen 2", "screen 2", "main" }
local DEFAULT_DEV = "7"
local FORCE_TABLE = "workspace-to-monitor-force-assignment"

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A screen word in one spelling: main, screen N, laptop, or a display's name as written.
-- secondary, AeroSpace's word for the other screen when there are two, is screen 2.
local function screenWord(value)
  local lower = value:lower()
  if lower == "main" or lower == "laptop" then return lower end
  if lower == "secondary" then return "screen 2" end
  local number = lower:match("^screen%s+(%d)$")
  if number then return "screen " .. number end
  return value
end

local function defaultList(list)
  list.screens = {}
  for number, screen in ipairs(DEFAULT_SCREENS) do list.screens[tostring(number)] = screen end
  list.dev = DEFAULT_DEV
  return list
end

-- The file's text, or nil without one: { screens = { ["1"] = "main", … }, dev, problems }.
-- A file with a problem gives today's workspaces, with the problems named.
function workspaces.parse(text)
  local list = { screens = {}, problems = {} }
  if text == nil then return defaultList(list) end
  local seen, number = {}, 0
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    number = number + 1
    local plain = trim((line:gsub("#.*$", "")))
    if plain ~= "" then
      local key, value = plain:match("^([%w%-]+)%s*=%s*(.-)$")
      local problem
      if not key or value == "" then problem = "expected 1 = main"
      elseif key == "dev" then list.dev = value
      elseif key:match("^%d+$") then
        local workspace = tonumber(key)
        if workspace < 1 or workspace > 9 then problem = "a workspace is a number from 1 to 9"
        elseif seen[tostring(workspace)] then
          problem = "workspace " .. workspace .. " is already on line " .. seen[tostring(workspace)]
        else
          seen[tostring(workspace)] = number
          list.screens[tostring(workspace)] = screenWord(value)
        end
      else problem = "unknown setting " .. key end
      if problem then list.problems[#list.problems + 1] = "line " .. number .. ": " .. problem end
    end
  end
  if #list.problems == 0 and next(list.screens) == nil then list.problems[1] = "keep at least one workspace" end
  if #list.problems > 0 then
    local problems = list.problems
    defaultList(list)
    list.problems = problems
  end
  return list
end

-- The workspaces, as strings, in number order.
function workspaces.numbers(list)
  local numbers = {}
  for workspace in pairs(list.screens) do numbers[#numbers + 1] = workspace end
  table.sort(numbers, function(a, b) return tonumber(a) < tonumber(b) end)
  return numbers
end

-- The dev layout's workspace: dev when it's one of them, otherwise the last.
function workspaces.devWorkspace(list)
  if list.dev and list.screens[list.dev] then return list.dev end
  local numbers = workspaces.numbers(list)
  return numbers[#numbers]
end

-- A display's name as AeroSpace's case-insensitive pattern: regex characters escaped, and
-- single quotes left out, since the pattern goes in a TOML literal string.
local function namePattern(name)
  return (name:gsub("'", ""):gsub("[%^%$%(%)%.%[%]%*%+%?%{%}%|\\]", "\\%0"))
end

-- The TOML value pinning a workspace to screen, before omv knows the screens plugged in.
-- Each falls back to the main screen. screen 3 and up wait for workspaces.resolve.
function workspaces.staticPattern(screen)
  if screen == "main" then return "'main'" end
  if screen == "screen 2" then return "['secondary', 'main']" end
  if screen:match("^screen %d$") then return "'main'" end
  if screen == "laptop" then return "['built-in', 'main']" end
  return "['" .. namePattern(screen) .. "', 'main']"
end

local KEYS = {
  { "alt-%d", "workspace %d" },
  { "alt-shift-%d", "move-node-to-workspace %d" },
  { "alt-keypad%d", "workspace %d" },
  { "alt-shift-keypad%d", "move-node-to-workspace %d" },
}

local function isWorkspaceKey(line)
  return line:match("^%s*alt%-%d%s*=") or line:match("^%s*alt%-shift%-%d%s*=")
    or line:match("^%s*alt%-keypad%d%s*=") or line:match("^%s*alt%-shift%-keypad%d%s*=")
end

-- omv's default aerospace.toml with its workspaces replaced by list's: the workspaces kept
-- alive, their pins, and their keys. Everything else is left as it is.
function workspaces.rewriteDefaults(text, list)
  local numbers = workspaces.numbers(list)
  local quoted, pins, keys = {}, {}, {}
  for _, workspace in ipairs(numbers) do
    quoted[#quoted + 1] = "'" .. workspace .. "'"
    pins[#pins + 1] = workspace .. " = " .. workspaces.staticPattern(list.screens[workspace])
  end
  for _, key in ipairs(KEYS) do
    for _, workspace in ipairs(numbers) do
      keys[#keys + 1] = string.format(key[1], workspace) .. " = '" .. string.format(key[2], workspace) .. "'"
    end
  end
  local out, inPins, keysWritten = {}, false, false
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    local header = line:match("^%s*%[([^%[%]]+)%]%s*$")
    if header then inPins = trim(header) == FORCE_TABLE end
    if line:match("^%s*persistent%-workspaces%s*=") then
      out[#out + 1] = "persistent-workspaces = [" .. table.concat(quoted, ", ") .. "]"
    elseif header and inPins then
      out[#out + 1] = line
      for _, pin in ipairs(pins) do out[#out + 1] = pin end
    elseif inPins and (line:match("^%s*%d+%s*=") or line:match("^%s*#")) then
      -- omv's own pins and their comments, replaced above.
    elseif isWorkspaceKey(line) then
      if not keysWritten then
        for _, key in ipairs(keys) do out[#out + 1] = key end
        keysWritten = true
      end
    else
      out[#out + 1] = line
    end
  end
  if out[#out] == "" then out[#out] = nil end
  return table.concat(out, "\n") .. "\n"
end

-- Each workspace's pin as a TOML value, for the screens plugged in: { name, builtin, main, x }
-- each. screen N is the Nth screen from the left that isn't the main one, written as
-- AeroSpace's position among all screens, then the ones before it, then main.
function workspaces.resolve(list, screens)
  local byX = {}
  for _, screen in ipairs(screens or {}) do byX[#byX + 1] = screen end
  table.sort(byX, function(a, b) return (a.x or 0) < (b.x or 0) end)
  local others = {}
  for position, screen in ipairs(byX) do
    if not screen.main then others[#others + 1] = position end
  end
  local resolved = {}
  for workspace, screen in pairs(list.screens) do
    local nth = tonumber(screen:match("^screen (%d)$") or "")
    if nth then
      local chain = {}
      for index = nth - 1, 1, -1 do
        if others[index] then chain[#chain + 1] = tostring(others[index]) end
      end
      chain[#chain + 1] = "'main'"
      resolved[workspace] = #chain == 1 and "'main'" or "[" .. table.concat(chain, ", ") .. "]"
    else
      resolved[workspace] = workspaces.staticPattern(screen)
    end
  end
  return resolved
end

-- AeroSpace's pin table for resolved pins, in number order.
function workspaces.assignmentToml(resolved, list)
  local lines = { "[" .. FORCE_TABLE .. "]" }
  for _, workspace in ipairs(workspaces.numbers(list)) do
    if resolved[workspace] then lines[#lines + 1] = workspace .. " = " .. resolved[workspace] end
  end
  return table.concat(lines, "\n") .. "\n"
end

-- Windows on a workspace that isn't listed, from aerospace list-windows lines of
-- "<window id> <workspace>": { { id, to } }, each to the lowest workspace left.
function workspaces.strayWindows(text, list)
  local lowest = workspaces.numbers(list)[1]
  local moves = {}
  for id, workspace in tostring(text or ""):gmatch("(%d+)%s+(%S+)") do
    if not list.screens[workspace] then moves[#moves + 1] = { id = id, to = lowest } end
  end
  return moves
end

-- The Workspaces card writes the whole file, in this shape.
local FILE_HEAD = [[
# Workspaces, 1 to 9: remove a line to remove one, add 8 or 9 to add one.
# Screen: main, screen 2, screen 3 and on (the others, left to right, main left out),
# laptop, or part of a display's name. A screen that isn't plugged in falls back down the list.
# Apply with omv reload. The Workspaces card in the system menu writes this file too.
]]

function workspaces.format(list)
  local lines = {}
  for _, workspace in ipairs(workspaces.numbers(list)) do lines[#lines + 1] = workspace .. " = " .. list.screens[workspace] end
  lines[#lines + 1] = "dev = " .. workspaces.devWorkspace(list)
  return FILE_HEAD .. table.concat(lines, "\n") .. "\n"
end

local function copy(list)
  local screens = {}
  for workspace, screen in pairs(list.screens) do screens[workspace] = screen end
  return { screens = screens, dev = list.dev, problems = {} }
end

-- The screen after or before screen in the card: main, screen 2 up to as many screens as are
-- plugged in (count, at least two), then laptop. A display's name, or a screen beyond those
-- plugged in, steps on to main.
function workspaces.stepScreen(screen, direction, count)
  local steps = { "main" }
  for nth = 2, math.max(2, count or 2) do steps[#steps + 1] = "screen " .. nth end
  steps[#steps + 1] = "laptop"
  for index, word in ipairs(steps) do
    if word == screen then return steps[(index - 1 + direction) % #steps + 1] end
  end
  return "main"
end

-- list with the lowest missing workspace added on main; nil when all nine exist.
function workspaces.add(list)
  for workspace = 1, 9 do
    if not list.screens[tostring(workspace)] then
      local added = copy(list)
      added.screens[tostring(workspace)] = "main"
      return added
    end
  end
  return nil
end

-- list without workspace; nil when it's the last one.
function workspaces.remove(list, workspace)
  if #workspaces.numbers(list) <= 1 then return nil end
  local removed = copy(list)
  removed.screens[workspace] = nil
  return removed
end

-- The card's rows: each workspace with its screen; Bring back in the place of one just
-- removed; then Add for the next workspace, when there's room.
function workspaces.rows(list, removed)
  local rows, dev, undone = {}, workspaces.devWorkspace(list), removed == nil
  local numbers = workspaces.numbers(list)
  local function undoRow()
    return { id = "undo", icon = "󰕌", label = "Bring back workspace " .. removed, hint = "removed just now" }
  end
  for _, workspace in ipairs(numbers) do
    if not undone and tonumber(removed) < tonumber(workspace) then
      rows[#rows + 1] = undoRow()
      undone = true
    end
    rows[#rows + 1] = { id = "workspace:" .. workspace, icon = "󰕰", label = "Workspace " .. workspace,
      hint = "‹  " .. list.screens[workspace] .. "  ›" .. (workspace == dev and "   dev layout" or "") }
  end
  if not undone then rows[#rows + 1] = undoRow() end
  local next = workspaces.add(list)
  if next then
    for workspace = 1, 9 do
      if next.screens[tostring(workspace)] and not list.screens[tostring(workspace)] then
        rows[#rows + 1] = { id = "add", icon = "󰐕", label = "Add workspace " .. workspace, hint = "Option+" .. workspace }
      end
    end
  end
  return rows
end

local function readFile(path)
  local file = path and io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

if arg and arg[0] and arg[0]:match("workspaces%.lua$") then
  local list = workspaces.parse(readFile(arg[2] or workspaces.PATH))
  if arg[1] == "numbers" then
    print(table.concat(workspaces.numbers(list), " "))
    os.exit(0)
  elseif arg[1] == "check" then
    for _, problem in ipairs(list.problems) do print(problem) end
    os.exit(#list.problems == 0 and 0 or 1)
  end
end

return workspaces
