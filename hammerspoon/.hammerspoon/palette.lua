-- The Option+Space palette: open windows, installed apps and omv's own commands in one
-- list, filtered as you type. Rows carry what to do as their id: window:<id>, app:<path> or
-- command:<index in the key list>. A typed sum adds calc:<result> on top.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local windows = require("windows")

local palette = {}

-- Where apps are looked for, in this order.
palette.APP_FOLDERS = { "/Applications", "/Applications/Utilities", "/System/Applications",
  "/System/Applications/Utilities" }

-- "Safari.app" is Safari; anything else, or a hidden app, is nil.
function palette.appName(file)
  if file:sub(1, 1) == "." then return nil end
  return file:match("^(.+)%.app$")
end

-- apps = { { name, path } }, in the order found; an app found twice is listed once.
function palette.appRows(apps)
  local seen, rows = {}, {}
  for _, app in ipairs(apps) do
    if not seen[app.name] then
      seen[app.name] = true
      rows[#rows + 1] = { id = "app:" .. app.path, icon = "󰀻", label = app.name, group = "Apps" }
    end
  end
  table.sort(rows, function(a, b) return a.label:lower() < b.label:lower() end)
  return rows
end

-- The key list's launchers, except the palette's own key and keys another app owns.
function palette.commandRows(launchers, ownKey)
  local rows = {}
  for index, launcher in ipairs(launchers) do
    if launcher.runs and launcher.label ~= ownKey then
      rows[#rows + 1] = { id = "command:" .. index, icon = "󰘳", label = launcher.description, hint = launcher.label,
        keywords = launcher.group, group = "Commands" }
    end
  end
  return rows
end

function palette.windowRows(output)
  local rows = {}
  for _, row in ipairs(windows.rows(output)) do
    rows[#rows + 1] = { id = "window:" .. row.id, icon = "󰖯", label = row.label, hint = row.hint, group = "Windows" }
  end
  return rows
end

function palette.rows(windowsOutput, apps, launchers, ownKey)
  local rows = {}
  for _, part in ipairs({ palette.windowRows(windowsOutput), palette.appRows(apps), palette.commandRows(launchers, ownKey) }) do
    for _, row in ipairs(part) do rows[#rows + 1] = row end
  end
  return rows
end

-- What a row does: "window", id; "app", path; "calc", the result to copy; or "command",
-- index. nil for an unknown row.
function palette.parse(id)
  local kind, value = id:match("^(%a+):(.+)$")
  if kind == "window" or kind == "app" or kind == "calc" then return kind, value end
  if kind == "command" then return kind, tonumber(value) end
  return nil
end

return palette
