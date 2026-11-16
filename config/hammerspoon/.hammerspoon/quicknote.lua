-- Quick note: what was typed, with the time, at the end of today's Obsidian daily note.
-- One line becomes a timed bullet, several lines a timed block, and a note that starts with
-- "# Title" becomes its own page in Inbox, linked from the daily note.
-- It also lists the notes in both folders for the editor to open.
-- init.lua reads and writes the files. Has no Hammerspoon dependency, so the Lua tests can run it.

local quicknote = {}

-- Obsidian's daily notes plugin keeps them here, named like 2026-11-08.md.
local DAILY_FOLDER = "00 - Daily"
local PAGE_FOLDER = "Inbox"
-- Characters a filename cannot hold, or that break an Obsidian [[link]].
local UNSAFE = '[/\\:%*%?"<>|#%^%[%]]'

function quicknote.path(vault, time)
  return vault .. "/" .. DAILY_FOLDER .. "/" .. os.date("%Y-%m-%d", time) .. ".md"
end

-- "- 09:05 call Ali", or nil when there is nothing to note.
function quicknote.line(text, time)
  local flat = text:gsub("%s+", " "):match("^ ?(.-) ?$")
  if flat == "" then return nil end
  return "- " .. os.date("%H:%M", time) .. " " .. flat
end

-- "- 09:05 call Ali" for one line, "### 09:05" above the lines for several, nil when blank.
function quicknote.entry(text, time)
  local body = text:gsub("%s+$", "")
  if body:match("^%s*$") then return nil end
  if not body:find("\n") then return quicknote.line(body, time) end
  return "### " .. os.date("%H:%M", time) .. "\n" .. body
end

-- The page's name when the first line is "# Title", without what a filename cannot hold.
function quicknote.title(text)
  local heading = text:match("^# ([^\n]+)")
  if not heading then return nil end
  local name = heading:gsub(UNSAFE, ""):gsub("%s+", " "):match("^ ?(.-) ?$")
  if name == "" then return nil end
  return name
end

-- Inbox/Title.md, or Title 2.md and on when exists says the name is taken.
function quicknote.pagePath(vault, title, exists)
  local folder = vault .. "/" .. PAGE_FOLDER .. "/"
  local path = folder .. title .. ".md"
  local number = 2
  while exists(path) do
    path = folder .. title .. " " .. number .. ".md"
    number = number + 1
  end
  return path
end

-- "- 09:05 [[Title]]", pointing at the page saved at path.
function quicknote.link(path, time)
  return "- " .. os.date("%H:%M", time) .. " [[" .. path:match("([^/]+)%.md$") .. "]]"
end

-- "today · 15:12", "yesterday" or "Nov 6": when a note last changed, as the list shows it.
local function when(modified, now)
  local day = os.date("%Y-%m-%d", modified)
  if day == os.date("%Y-%m-%d", now) then return "today · " .. os.date("%H:%M", modified) end
  local before = os.date("*t", now)
  before.day, before.hour = before.day - 1, 12
  if day == os.date("%Y-%m-%d", os.time(before)) then return "yesterday" end
  return os.date("%b ", modified) .. tonumber(os.date("%d", modified))
end

-- The note list: today's daily note first, then the rest newest first, at most MAX_ROWS.
-- files = { { path, folder = "Daily" | "Inbox", modified } }; rows are what card.html shows.
local MAX_ROWS = 200

function quicknote.rows(files, now)
  local todayName = os.date("%Y-%m-%d", now)
  local notes = {}
  for _, file in ipairs(files) do
    local name = file.path:match("([^/]+)%.md$")
    if name then
      notes[#notes + 1] = { file = file, name = name, today = file.folder == "Daily" and name == todayName }
    end
  end
  table.sort(notes, function(a, b)
    if a.today ~= b.today then return a.today end
    return a.file.modified > b.file.modified
  end)
  local rows = {}
  for index = 1, math.min(#notes, MAX_ROWS) do
    local note = notes[index]
    rows[index] = { id = note.file.path, label = note.name,
      hint = when(note.file.modified, now) .. "  " .. note.file.folder }
  end
  return rows
end

-- A note opened for editing is saved only if nothing else changed it since, such as Obsidian.
function quicknote.canSave(openedModified, currentModified)
  return openedModified == currentModified
end

-- The note's new content. A block gets a blank line on each side, so it reads as its own section.
-- A missing note starts as a plain file, without the template:
-- Obsidian applies templates only to notes it creates itself.
function quicknote.appended(existing, entry)
  local block = entry:find("\n") ~= nil
  local tail = block and "\n\n" or "\n"
  if not existing or existing == "" then return entry .. tail end
  if existing:sub(-1) ~= "\n" then existing = existing .. "\n" end
  if block and existing:sub(-2) ~= "\n\n" then existing = existing .. "\n" end
  return existing .. entry .. tail
end

return quicknote
