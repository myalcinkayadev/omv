-- Builds the cheat sheet from aerospace.toml, so the sheet cannot go stale.
-- Has no Hammerspoon dependency, so tests/keymap_test.sh can run it with luajit.

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
        bindings[#bindings + 1] = { mode = mode, key = key, command = parseCommand(value) }
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

local function escapeHtml(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function row(key, description)
  return "<tr><td class=key>" .. escapeHtml(key) .. "</td><td>" .. escapeHtml(description) .. "</td></tr>"
end

local function section(title, rows)
  return "<section><h2>" .. escapeHtml(title) .. "</h2><table>" .. table.concat(rows) .. "</table></section>"
end

local function rowsForMode(bindings, mode)
  local rows = {}
  for _, binding in ipairs(bindings) do
    if binding.mode == mode then
      rows[#rows + 1] = row(keymap.label(binding.key), binding.command)
    end
  end
  return rows
end

local function launcherRows(launchers)
  local rows = {}
  for _, launcher in ipairs(launchers) do
    rows[#rows + 1] = row(launcher.label, launcher.description)
  end
  return rows
end

local STYLE = [[
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; background: #000; color: #fff; }
  body { font: 14px "JetBrainsMono Nerd Font Mono", monospace; border: 2px solid #8d8d8d; padding: 18px 22px; overflow: hidden; }
  main { columns: 2; column-gap: 28px; }
  section { break-inside: avoid; padding-bottom: 14px; }
  h2 { font-size: 14px; font-weight: normal; color: #7a7a7a; margin: 0 0 6px; }
  table { border-collapse: collapse; width: 100%; }
  td { padding: 1px 10px 1px 0; vertical-align: top; }
  .key { white-space: nowrap; }
]]

function keymap.html(bindings, launchers)
  return "<!doctype html><meta charset=utf-8><style>" .. STYLE .. "</style><main>"
    .. section("Windows and workspaces", rowsForMode(bindings, "main"))
    .. section("Resize mode", rowsForMode(bindings, "resize"))
    .. section("Apps", launcherRows(launchers))
    .. "</main>"
end

return keymap
