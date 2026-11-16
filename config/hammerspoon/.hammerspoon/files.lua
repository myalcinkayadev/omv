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

-- Nerd Font glyphs by kind of file, picked from the extension.
files.ICONS = { file = "󰈔", code = "󰈮", document = "󰈙", image = "󰈟", pdf = "󰈦", archive = "󰗄" }
local KINDS = {
  code = { "lua", "js", "ts", "py", "sh", "go", "rs", "rb", "swift", "c", "h", "css", "html", "json", "toml", "yaml", "yml" },
  document = { "md", "txt", "rtf", "doc", "docx", "pages" },
  image = { "png", "jpg", "jpeg", "gif", "svg", "webp", "heic" },
  pdf = { "pdf" },
  archive = { "zip", "tar", "gz", "dmg" },
}
local KIND_OF = {}
for kind, extensions in pairs(KINDS) do
  for _, extension in ipairs(extensions) do KIND_OF[extension] = kind end
end

function files.icon(name)
  local extension = tostring(name):match("%.([^.]+)$")
  return files.ICONS[extension and KIND_OF[extension:lower()] or "file"]
end

local function characters(text)
  return select(2, text:gsub("[^\128-\191]", ""))
end

-- The typed words, lowercased, with ", \ and * dropped so a word can't end the name
-- pattern or widen it.
local function words(text)
  local found = {}
  for word in tostring(text or ""):gsub('["\\*]', ""):lower():gmatch("%S+") do found[#found + 1] = word end
  return found
end

-- mdfind's arguments for the typed text, or nil when there's too little to search for: each
-- word is its own "name contains" condition, as the palette's own filter treats words. The
-- text goes in as an argument, never through a shell.
function files.arguments(text, home)
  local typed, letters, names = words(text), 0, {}
  for _, word in ipairs(typed) do
    letters = letters + characters(word)
    names[#names + 1] = '(kMDItemFSName == "*' .. word .. '*"cd)'
  end
  if letters < files.MIN_LENGTH then return nil end
  local since = "$time.today(-" .. files.DAYS .. ")"
  return { "-onlyin", home, table.concat(names, " && ") .. " && ((kMDItemLastUsedDate >= " .. since
    .. ") || (kMDItemFSContentChangeDate >= " .. since .. "))" }
end

-- How well a name matches the first typed word, as Spotlight ranks: 1 when it starts with
-- it, 2 when a word inside it does (after - _ . or a space), 3 when it only contains it.
local function closeness(name, word)
  if not word then return 3 end
  local lower = name:lower()
  if lower:sub(1, #word) == word then return 1 end
  local at = 1
  while true do
    local start = lower:find(word, at, true)
    if not start then return 3 end
    if lower:sub(start - 1, start - 1):match("[%-_%.%s]") then return 2 end
    at = start + 1
  end
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

-- mdfind's answer, one path per line, as palette rows: noise left out, the closest names to
-- the typed text first, then the newest, cut to LIMIT only after sorting. modified(path) gives
-- a file's change time, or nil when it can't be read; text and modified may be left out.
function files.rows(output, home, text, modified)
  local first, found = words(text)[1], {}
  for path in tostring(output or ""):gmatch("[^\n]+") do
    if not skipped(path) then
      local name = path:match("([^/]+)$") or path
      found[#found + 1] = { path = path, name = name, close = closeness(name, first),
        changed = modified and modified(path) or 0 }
    end
  end
  table.sort(found, function(a, b)
    if a.close ~= b.close then return a.close < b.close end
    if a.changed ~= b.changed then return a.changed > b.changed end
    return a.path < b.path
  end)
  local rows = {}
  for index = 1, math.min(#found, files.LIMIT) do
    local file = found[index]
    rows[index] = { id = "file:" .. file.path, icon = files.icon(file.name), label = file.name,
      hint = folderHint(file.path, home), group = "Files" }
  end
  return rows
end

return files
