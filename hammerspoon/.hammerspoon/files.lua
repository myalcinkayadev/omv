-- Which files the palette finds while the file-search flag is on: names containing what's
-- typed, among files opened or modified in the last 30 days under home. Opened alone isn't
-- enough: macOS records "last opened" only for files opened through Finder or apps, so a
-- file edited in a terminal would never count.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local files = {}

files.MIN_LENGTH = 3
files.LIMIT = 20
files.DAYS = 30

-- Folders whose files are noise in a launcher: app data, packages and git's own files.
local SKIPPED = { "/Library/", "/node_modules/", "/.git/" }

local function characters(text)
  return select(2, text:gsub("[^\128-\191]", ""))
end

-- mdfind's arguments for the typed text, or nil when there's too little to search for. The
-- text goes in as an argument, never through a shell; ", \ and * are dropped so it can't end
-- the name pattern or widen it.
function files.arguments(text, home)
  local name = tostring(text or ""):gsub('["\\*]', "")
  if characters(name) < files.MIN_LENGTH then return nil end
  local since = "$time.today(-" .. files.DAYS .. ")"
  return { "-onlyin", home, '(kMDItemFSName == "*' .. name .. '*"cd) && ((kMDItemLastUsedDate >= ' .. since
    .. ") || (kMDItemFSContentChangeDate >= " .. since .. "))" }
end

local function skipped(path)
  for _, folder in ipairs(SKIPPED) do
    if path:find(folder, 1, true) then return true end
  end
  return false
end

local function folderHint(path, home)
  local folder = path:match("^(.*)/[^/]*$") or path
  if folder == home then return "~" end
  if folder:sub(1, #home + 1) == home .. "/" then return "~" .. folder:sub(#home + 1) end
  return folder
end

-- mdfind's answer, one path per line, as palette rows: at most LIMIT, noise left out.
function files.rows(output, home)
  local rows = {}
  for path in tostring(output or ""):gmatch("[^\n]+") do
    if #rows >= files.LIMIT then break end
    if not skipped(path) then
      rows[#rows + 1] = { id = "file:" .. path, icon = "󰈔", label = path:match("([^/]+)$") or path,
        hint = folderHint(path, home), group = "Files" }
    end
  end
  return rows
end

return files
