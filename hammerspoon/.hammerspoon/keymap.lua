-- Builds the cheat sheet from aerospace.toml, so the sheet cannot go stale.
-- Has no Hammerspoon dependency, so tests/keymap_test.sh can run it with luajit.

local card = require("card")

local keymap = {}

local MODIFIER_LABELS = { alt = "Option", shift = "Shift", ctrl = "Ctrl", cmd = "Cmd" }
local KEY_LABELS = { enter = "Enter", esc = "Escape", tab = "Tab", comma = ",", period = "." }

local function parseCommand(value)
  local single = value:match("^'(.*)'$")
  if single then return single end
  local commands = {}
  for command in value:gmatch("'([^']*)'") do
    if not command:find("sketchybar --trigger", 1, true) then
      commands[#commands + 1] = command
    end
  end
  return table.concat(commands, ", ")
end

-- Every command a binding runs, in order, including the bar triggers the description hides.
local function commandList(value)
  local single = value:match("^'(.*)'$")
  if single then return { single } end
  local commands = {}
  for command in value:gmatch("'([^']*)'") do commands[#commands + 1] = command end
  return commands
end

function keymap.parse(text)
  local bindings = {}
  local mode = nil
  for line in text:gmatch("[^\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed:sub(1, 1) == "[" then
      mode = trimmed:match("^%[mode%.([%w_-]+)%.binding%]$")
    elseif mode and trimmed:sub(1, 1) ~= "#" then
      local key, value = trimmed:match("^([%w-]+)%s*=%s*(.+)$")
      if key then
        bindings[#bindings + 1] = { mode = mode, key = key, command = parseCommand(value), commands = commandList(value) }
      end
    end
  end
  return bindings
end

function keymap.read(path)
  local file = io.open(path, "r")
  if not file then return {} end
  local text = file:read("*a")
  file:close()
  return keymap.parse(text)
end

function keymap.label(key)
  local parts = {}
  for part in key:gmatch("[^-]+") do
    parts[#parts + 1] = MODIFIER_LABELS[part] or KEY_LABELS[part] or part:upper()
  end
  return table.concat(parts, "+")
end

-- Plain descriptions for AeroSpace commands. A command missing here shows as itself,
-- so a new binding still appears, just less readably.
local DESCRIPTIONS = {
  { "^focus (%a+)$", "Focus the window %1" },
  { "^move (%a+)$", "Move the window %1" },
  { "^workspace%-back%-and%-forth$", "Go back to the previous workspace" },
  { "^workspace (%w+)$", "Go to workspace %1" },
  { "^move%-node%-to%-workspace (%w+)$", "Send the window to workspace %1" },
  { "^focus%-monitor (%a+)$", "Focus the %1 monitor" },
  { "^move%-node%-to%-monitor (%a+)$", "Send the window to the %1 monitor" },
  { "^fullscreen$", "Toggle fullscreen" },
  { "^layout floating tiling$", "Toggle floating or tiled" },
  { "^layout tiles horizontal vertical$", "Toggle the split direction" },
  { "^layout accordion tiles$", "Toggle tabbed or tiled" },
  { "^balance%-sizes$", "Make window sizes even" },
  { "^mode resize$", "Enter resize mode" },
  { "^mode main$", "Leave resize mode" },
  { "^resize width %-%d+$", "Resize: narrower" },
  { "^resize width %+%d+$", "Resize: wider" },
  { "^resize height %-%d+$", "Resize: shorter" },
  { "^resize height %+%d+$", "Resize: taller" },
  { "^workspace 1, exec%-and%-forget .*new%-window%.sh$", "New Ghostty window" },
}

function keymap.describe(command)
  for _, rule in ipairs(DESCRIPTIONS) do
    local described, matched = command:gsub(rule[1], rule[2])
    if matched > 0 then return described end
  end
  return command
end

-- How to run a binding's commands from the key list: AeroSpace commands through its CLI,
-- and exec-and-forget through the shell, since the CLI doesn't take it. In written order.
function keymap.steps(commands)
  local steps = {}
  for _, command in ipairs(commands) do
    local shell = command:match("^exec%-and%-forget%s+(.+)$")
    if shell then
      steps[#steps + 1] = { program = "/bin/sh", args = { "-c", shell } }
    else
      local args = {}
      for word in command:gmatch("%S+") do args[#args + 1] = word end
      steps[#steps + 1] = { program = "aerospace", args = args }
    end
  end
  return steps
end

local function bindingRows(bindings)
  local rows = {}
  for index, binding in ipairs(bindings) do
    local key = keymap.label(binding.key)
    if binding.mode ~= "main" then key = key .. " (" .. binding.mode .. ")" end
    rows[#rows + 1] = { id = "binding:" .. index, label = keymap.describe(binding.command), hint = key, runnable = true }
  end
  return rows
end

function keymap.rows(bindings, launchers)
  local rows = bindingRows(bindings)
  -- A launcher runs only when init.lua gave it something to run.
  for index, launcher in ipairs(launchers) do
    rows[#rows + 1] = { id = "launcher:" .. index, label = launcher.description, hint = launcher.label, runnable = launcher.runs == true }
  end
  return rows
end

-- Card sizes in points: border, padding and prompt above the rows, one compact row,
-- and room left between the card and the screen edges.
local CARD_CHROME = 28 + 46 + 8
local ROW_HEIGHT = 30
local COLUMN_WIDTH = 550
local SCREEN_MARGIN = 40

-- Enough columns to show every key at once on this screen, at least two, and a card
-- size that stays on screen. Long labels shorten with "…" once the width is capped.
function keymap.layout(rowCount, screen)
  if rowCount == 0 then return { columns = 1, w = COLUMN_WIDTH, h = CARD_CHROME } end
  local rowsThatFit = math.max(1, math.floor((screen.h - SCREEN_MARGIN - CARD_CHROME) / ROW_HEIGHT))
  local columns = math.max(2, math.ceil(rowCount / rowsThatFit))
  local rowsPerColumn = math.ceil(rowCount / columns)
  return {
    columns = columns,
    w = math.min(columns * COLUMN_WIDTH, screen.w - SCREEN_MARGIN),
    h = math.min(CARD_CHROME + rowsPerColumn * ROW_HEIGHT, screen.h - SCREEN_MARGIN),
  }
end

function keymap.html(bindings, launchers, columns)
  return card.html({ prompt = "Keybindings…", rows = keymap.rows(bindings, launchers), compact = true, columns = columns })
end

return keymap
