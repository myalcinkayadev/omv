-- The Option+Space palette: open windows, installed apps and omv's own commands in one
-- list, filtered as you type. Rows carry what to do as their id: window:<id>, app:<path> or
-- command:<index in the key list>. A typed sum adds calc:<result> on top, a clipboard action
-- clip:<result> above that, browser tabs tab:<window id>:<tab index> rows before the apps, and
-- file search file:<path> rows at the end.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local clipboard = require("clipboard")
local windows = require("windows")
local soundmatch = require("soundmatch")

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

-- Windows first, as the palette opens; snippets next, ahead of the apps and commands, so
-- typing a snippet's name picks it. With withTabs, a place for the browser's tabs follows the
-- snippets: they're read after the palette opens, and fill it when they arrive.
function palette.rows(windowsOutput, apps, launchers, ownKey, snippetRows, withTabs)
  local rows = {}
  local tabPlace = withTabs and { { tabs = true } } or {}
  for _, part in ipairs({ palette.windowRows(windowsOutput), snippetRows or {}, tabPlace, palette.appRows(apps), palette.commandRows(launchers, ownKey) }) do
    for _, row in ipairs(part) do rows[#rows + 1] = row end
  end
  return rows
end

-- What Cmd+Enter ("reveal": show in Finder) and Cmd+C ("copy": copy the path) do with a row:
-- { kind, path } for a file row, nil for any other row or key.
local FILE_ACTIONS = { reveal = true, copy = true }

function palette.action(key, id)
  local kind, path = palette.parse(id)
  if not FILE_ACTIONS[key] or kind ~= "file" then return nil end
  return { kind = key, path = path }
end

-- The prompt names what can be found: files too while file search is on.
function palette.prompt(fileSearch)
  return fileSearch and "Windows, apps, commands, files…" or "Windows, apps, commands…"
end

-- What a row does: "window", id; "app", path; "file", path; "calc" or "clip", the result to
-- copy; "tab", { window, index }; or "command", index. nil for an unknown row.
function palette.parse(id)
  local kind, value = id:match("^(%a+):(.+)$")
  if kind == "tab" then
    local window, index = value:match("^(%d+):(%d+)$")
    if not window then return nil end
    return kind, { window = tonumber(window), index = tonumber(index) }
  end
  if kind == "window" or kind == "app" or kind == "calc" or kind == "file" or kind == "clip" then return kind, value end
  if kind == "command" or kind == "snippet" then return kind, tonumber(value) end
  return nil
end

-- The clipboard's text for the clipboard actions, or nil to leave it out of the page: while
-- clipboard history is paused, for a copy a password manager marked as concealed, or past
-- 100 KB, which no action needs.
palette.CLIP_LIMIT = 100 * 1024

function palette.clipText(text, types, paused)
  if paused or type(text) ~= "string" or #text > palette.CLIP_LIMIT or clipboard.isConcealed(types) then return nil end
  return text
end

-- The rows a typed text finds only by how it sounds or one letter off, such as Zed for "said",
-- which the page shows marked "sounds like"; none under 3 letters. A row that holds the text
-- is found by the page itself.
palette.SOUND_LETTERS = 3

function palette.soundIds(rows, text)
  local ids = {}
  if #soundmatch.normal(text) < palette.SOUND_LETTERS then return ids end
  for _, row in ipairs(rows or {}) do
    local score = row.id and row.label and soundmatch.score(text, row.label) or 0
    if score == soundmatch.SOUND or score == soundmatch.SPELLING then ids[#ids + 1] = row.id end
  end
  return ids
end

return palette
