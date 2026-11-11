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

local function partLabel(part)
  local numpad = part:match("^keypad(%d)$")
  return MODIFIER_LABELS[part] or KEY_LABELS[part] or (numpad and "Num " .. numpad) or part:upper()
end

function keymap.label(key)
  local parts = {}
  for part in key:gmatch("[^-]+") do parts[#parts + 1] = partLabel(part) end
  return table.concat(parts, "+")
end

-- Several keys for one command: "Option+1 / Num 1" when they share their modifiers,
-- each written in full otherwise, "Option+Shift+Z / Ctrl+Z".
local function modifiersAndKey(key)
  return key:match("^(.-)%-?([^-]+)$")
end

function keymap.keysLabel(keys)
  local modifiers = modifiersAndKey(keys[1])
  local finals = {}
  for _, key in ipairs(keys) do
    local theseModifiers, final = modifiersAndKey(key)
    if theseModifiers ~= modifiers then
      local labels = {}
      for index, each in ipairs(keys) do labels[index] = keymap.label(each) end
      return table.concat(labels, " / ")
    end
    finals[#finals + 1] = partLabel(final)
  end
  local prefix = modifiers ~= "" and (keymap.label(modifiers) .. "+") or ""
  return prefix .. table.concat(finals, " / ")
end

-- Plain descriptions for AeroSpace commands, short enough to fit a column. The group
-- header gives the rest of the meaning. A command missing here shows as itself, so a new
-- binding still appears, just less readably.
local DESCRIPTIONS = {
  { "^focus (%a+)$", "Focus %1" },
  { "^move (%a+)$", "Move %1" },
  { "^workspace%-back%-and%-forth$", "Previous workspace" },
  { "^workspace (%w+)$", "Go to %1" },
  { "^move%-node%-to%-workspace (%w+)$", "Send window to %1" },
  { "^focus%-monitor (%a+)$", "Focus %1 monitor" },
  { "^move%-node%-to%-monitor (%a+)$", "Send window to %1 monitor" },
  { "^fullscreen$", "Fullscreen" },
  { "^layout floating tiling$", "Floating or tiled" },
  { "^layout tiles horizontal vertical$", "Split direction" },
  { "^layout accordion tiles$", "Tabbed or tiled" },
  { "^balance%-sizes$", "Even sizes" },
  { "^mode resize$", "Enter resize mode" },
  { "^mode main$", "Leave resize mode" },
  { "^resize width %-%d+$", "Narrower" },
  { "^resize width %+%d+$", "Wider" },
  { "^resize height %-%d+$", "Shorter" },
  { "^resize height %+%d+$", "Taller" },
  { "^workspace 1, exec%-and%-forget .*new%-window%.sh$", "New Ghostty window" },
}

-- Words a row is also found by, for what it does: "screenshot" finds "Capture the screen".
-- The first rule whose pattern matches the row's description gives its words. They are
-- searched, never shown. A row no rule matches has none.
local SEARCH_WORDS = {
  { "^Go to %d", "desktop space switch" },
  { "^Send window to %d", "move desktop space" },
  { "^Previous workspace", "back last desktop space" },
  { "monitor$", "display screen" },
  { "^Fullscreen", "maximize zoom" },
  { "^Floating or tiled", "float tile layout" },
  { "^Split direction", "tile horizontal vertical layout" },
  { "^Tabbed or tiled", "accordion tabs layout" },
  { "^Enter resize mode", "size width height" },
  { "^New Ghostty window", "terminal shell" },
  { "^btop", "terminal processes cpu memory" },
  { "^Capture the screen", "screenshot grab ocr text color picker" },
  { "^Copy .+'s current URL", "browser link" },
  { "^Set a reminder", "timer alarm pomodoro" },
  { "^Note in today's daily note", "obsidian write journal" },
  { "^PRs waiting", "github pull request review" },
  { "^Hungry processes", "kill quit cpu memory process activity monitor slow" },
  { "^Claude session waiting", "agent ai" },
  { "^Join the meeting", "zoom meet teams call video calendar" },
  { "^Show or hide the bar", "sketchybar menu bar" },
  { "^Wi%-Fi", "wifi network internet" },
  { "^Ethernet", "network cable internet" },
  { "^Sound", "volume audio speaker microphone mic output input" },
  { "^Weather", "temperature forecast" },
  { "^Battery", "power charge" },
  { "^System menu", "lock sleep restart shut down log out reload" },
  { "^Go to any window", "switch find windows" },
  { "^Clipboard history", "paste copy copied clipboard history" },
  { "^Keep the Mac awake", "caffeinate sleep" },
  { "^Drop%-down terminal", "quake ghostty" },
  { "^Finder at home", "files folder" },
  { "^Open %S", "editor code" },
  { "^New .+ window$", "browser" },
  { "^Show or hide this list", "help keys shortcuts cheat sheet" },
}

local function searchWords(description)
  for _, rule in ipairs(SEARCH_WORDS) do
    if description:find(rule[1]) then return rule[2] end
  end
  return nil
end

-- Groups in the order the list shows them. Launchers name their group in init.lua.
local GROUP_ORDER = { "Windows", "Workspaces", "Monitors", "Layout", "Resize mode", "Apps", "Tools", "Cards", "Other" }

-- A group's mode, when its header already says which mode its keys work in.
local GROUP_MODES = { ["Resize mode"] = "resize" }

-- The first rule whose pattern matches the command picks the binding's group.
local BINDING_GROUPS = {
  { "^focus%-monitor ", "Monitors" },
  { "^move%-node%-to%-monitor ", "Monitors" },
  { "^focus ", "Windows" },
  { "^move ", "Windows" },
  { "^workspace 1, exec%-and%-forget", "Apps" },
  { "^workspace", "Workspaces" },
  { "^move%-node%-to%-workspace ", "Workspaces" },
  { "^fullscreen$", "Layout" },
  { "^layout ", "Layout" },
  { "^balance%-sizes$", "Layout" },
  { "^mode resize$", "Resize mode" },
}

local function bindingGroup(binding)
  if binding.mode == "resize" then return "Resize mode" end
  for _, rule in ipairs(BINDING_GROUPS) do
    if binding.command:find(rule[1]) then return rule[2] end
  end
  return "Other"
end

local function groupRank(group)
  for rank, name in ipairs(GROUP_ORDER) do
    if name == group then return rank end
  end
  return #GROUP_ORDER + 1
end

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

-- One row for every binding that runs the same commands in the same mode, such as Option+1
-- and Option+Num 1. It runs the first one's commands and sits where it was written.
local function bindingRow(binding, index, keys)
  local group = bindingGroup(binding)
  local key = keymap.keysLabel(keys)
  if binding.mode ~= "main" and GROUP_MODES[group] ~= binding.mode then key = key .. " (" .. binding.mode .. ")" end
  local label = keymap.describe(binding.command)
  return { id = "binding:" .. index, label = label, hint = key, group = group, runnable = true, keywords = searchWords(label) }
end

local function mergedBindings(bindings)
  local merged, byCommands = {}, {}
  for index, binding in ipairs(bindings) do
    local same = binding.mode .. "\n" .. table.concat(binding.commands, "\n")
    local entry = byCommands[same]
    if entry then
      entry.keys[#entry.keys + 1] = binding.key
    else
      entry = { binding = binding, index = index, keys = { binding.key } }
      byCommands[same] = entry
      merged[#merged + 1] = entry
    end
  end
  return merged
end

-- Sorted by group, keeping the written order inside each group.
local function sortByGroup(rows)
  for position, row in ipairs(rows) do row.position = position end
  table.sort(rows, function(a, b)
    local rankA, rankB = groupRank(a.group), groupRank(b.group)
    if rankA ~= rankB then return rankA < rankB end
    return a.position < b.position
  end)
  return rows
end

function keymap.rows(bindings, launchers)
  local rows = {}
  for _, entry in ipairs(mergedBindings(bindings)) do rows[#rows + 1] = bindingRow(entry.binding, entry.index, entry.keys) end
  -- A launcher runs only when init.lua gave it something to run.
  for index, launcher in ipairs(launchers) do
    rows[#rows + 1] = { id = "launcher:" .. index, label = launcher.description, hint = launcher.label,
      group = launcher.group or "Other", runnable = launcher.runs == true, keywords = searchWords(launcher.description) }
  end
  return sortByGroup(rows)
end

-- Lines the card draws: every row, plus a header wherever the group changes.
function keymap.lines(rows)
  local count, previous = 0, nil
  for _, row in ipairs(rows) do
    if row.group ~= previous then count = count + 1 end
    previous = row.group
    count = count + 1
  end
  return count
end

-- Card sizes in points: border, padding and prompt above the rows, one compact row,
-- and room left between the card and the screen edges.
local CARD_CHROME = 28 + 46 + 8
local ROW_HEIGHT = 30
local COLUMN_WIDTH = 550
local SCREEN_MARGIN = 40

-- A header is never left alone at the foot of a column, so a column can end up to one
-- line short. Each column keeps one spare line for that.
local SPARE_LINES = 1

-- Enough columns to show every line at once on this screen, at least two, and a card
-- size that stays on screen. Long labels shorten with "…" once the width is capped.
function keymap.layout(lineCount, screen)
  if lineCount == 0 then return { columns = 1, w = COLUMN_WIDTH, h = CARD_CHROME } end
  local linesThatFit = math.floor((screen.h - SCREEN_MARGIN - CARD_CHROME) / ROW_HEIGHT) - SPARE_LINES
  local columns = math.max(2, math.ceil(lineCount / math.max(1, linesThatFit)))
  local linesPerColumn = math.ceil(lineCount / columns) + SPARE_LINES
  return {
    columns = columns,
    w = math.min(columns * COLUMN_WIDTH, screen.w - SCREEN_MARGIN),
    h = math.min(CARD_CHROME + linesPerColumn * ROW_HEIGHT, screen.h - SCREEN_MARGIN),
  }
end

function keymap.html(bindings, launchers, columns)
  return card.html({ prompt = "Keybindings…", rows = keymap.rows(bindings, launchers), compact = true, columns = columns })
end

return keymap
