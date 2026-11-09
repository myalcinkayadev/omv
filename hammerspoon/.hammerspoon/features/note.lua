-- Quick note (Option+Shift+D): what was typed, with the time, at the end of today's daily note,
-- or its own page in Inbox when it starts with "# Title". Escape with text first asks: a second
-- Escape keeps the draft for next time, Cmd+Backspace throws it away.
-- Cmd+O lists the notes in both folders. One opens in the same editor; Escape goes back a step.

local shell = require("shell")
local card = require("card")
local quicknote = require("quicknote")
local notepad = require("notepad")

local feature = {}

local NOTE_VAULT = shell.HOME .. "/Documents/vault/work"
local NOTE_WIDTH = 640
local NOTE_FOLDERS = { { name = "00 - Daily", label = "Daily" }, { name = "Inbox", label = "Inbox" } }
local NOTE_LIST_ROWS = 10

-- file is the note opened for editing: { path, name, modified, original, text }, nil for a new note.
local note = { draft = "", armed = false, file = nil }

local function exists(path)
  local file = io.open(path, "r")
  if not file then return false end
  file:close()
  return true
end

local function write(path, content)
  os.execute("/bin/mkdir -p '" .. path:match("^(.*)/") .. "'")
  local file = io.open(path, "w")
  if not file then return false end
  file:write(content)
  file:close()
  return true
end

local function modified(path)
  return hs.fs.attributes(path, "modification")
end

-- A page is written first, so the daily note never links to one that failed.
local function save(text)
  local now = os.time()
  local entry = quicknote.entry(text, now)
  local title = quicknote.title(text)
  if title then
    local page = quicknote.pagePath(NOTE_VAULT, title, exists)
    if not write(page, text:gsub("%s+$", "") .. "\n") then return false end
    entry = quicknote.link(page, now)
  end
  local daily = quicknote.path(NOTE_VAULT, now)
  return write(daily, quicknote.appended(shell.readText(daily), entry))
end

local function submit(text)
  if not quicknote.entry(text, os.time()) then return shell.close() end
  shell.close()
  if not save(text) then return shell.alert("Could not write the note", 1.2) end
  note.draft = ""
  shell.alert("Noted", 1.2)
end

-- Keeps the card's top where it is and lets it grow downward.
local function resize(height)
  local view = shell.view()
  local frame = view:frame()
  frame.h = tonumber(height) or frame.h
  view:frame(frame)
end

local function files()
  local found = {}
  for _, folder in ipairs(NOTE_FOLDERS) do
    local dir = NOTE_VAULT .. "/" .. folder.name
    if hs.fs.attributes(dir, "mode") == "directory" then
      for entry in hs.fs.dir(dir) do
        local path = dir .. "/" .. entry
        local changed = entry:sub(1, 1) ~= "." and modified(path)
        if changed then found[#found + 1] = { path = path, folder = folder.label, modified = changed } end
      end
    end
  end
  return found
end

local onMessage, onEscape, onListMessage

local function showNew()
  note.file, note.armed = nil, false
  shell.show("note", shell.centered(NOTE_WIDTH, 28 + 46 + 44 + 4), notepad.html(note.draft), onMessage,
    { onEscape = onEscape })
end

local function showList()
  note.file, note.armed = nil, false
  local screen = { prompt = "Notes…", rows = quicknote.rows(files(), os.time()), hint = "No notes yet" }
  local height = 28 + 46 + math.max(1, math.min(#screen.rows, NOTE_LIST_ROWS)) * 44 + 4
  shell.show("notes", shell.centered(NOTE_WIDTH, height), card.html(screen), onListMessage,
    { onEscape = showNew })
end

local function open(path)
  local text = shell.readText(path)
  if not text then return shell.alert("Could not read the note", 1.2) end
  local name = path:match("([^/]+)%.md$")
  note.file = { path = path, name = name, modified = modified(path), original = text, text = text }
  note.armed = false
  shell.show("note", shell.centered(NOTE_WIDTH, 28 + 46 + 44 + 4), notepad.html(text, name), onMessage,
    { onEscape = onEscape })
end

onListMessage = function(message)
  if message.type == "choose" then return open(message.id) end
  if message.type == "back" then return showNew() end
  shell.close()
end

-- Written only when the file is as it was when opened, so an edit in Obsidian is never overwritten.
local function saveFile(text)
  local file = note.file
  if not quicknote.canSave(file.modified, modified(file.path)) then
    return shell.alert("Changed in Obsidian, not saved", 2)
  end
  if not write(file.path, text) then return shell.alert("Could not write the note", 1.2) end
  note.file = nil
  shell.close()
  shell.alert("Saved", 1.2)
end

onMessage = function(message)
  if message.type == "draft" then
    if note.file then note.file.text = message.id else note.draft = message.id end
    note.armed = false
  elseif message.type == "resize" then
    resize(message.id)
  elseif message.type == "submit" then
    if note.file then saveFile(message.id) else submit(message.id) end
  elseif message.type == "open" then
    showList()
  elseif message.type == "discard" then
    note.draft = ""
    shell.close()
  end
end

-- An opened note goes back to the list, asking first when its changes would be lost.
local function onFileEscape()
  if note.armed or note.file.text == note.file.original then return showList() end
  note.armed = true
  shell.view():evaluateJavaScript("arm()")
end

-- Without text, or on the second press, Escape closes and keeps any draft. Otherwise it asks first.
onEscape = function()
  if note.file then return onFileEscape() end
  local hasText = note.draft:find("%S") ~= nil
  if note.armed or not hasText then
    shell.close()
    if hasText then shell.alert("Draft kept", 1.2) end
    return
  end
  note.armed = true
  shell.view():evaluateJavaScript("arm()")
end

function feature.toggle()
  if shell.isOpen("note", "notes") then return shell.close() end
  showNew()
end

return feature
