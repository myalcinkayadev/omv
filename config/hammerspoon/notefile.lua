-- Writing a note without ever leaving it half-written, and finding the vault it goes in.
-- The file system comes in as a table, { open, rename, remove, mkdir }, so the Lua tests
-- can run it with luajit and no disk.

local notefile = {}

-- Written beside the note, so the rename stays on one disk and is all or nothing. Obsidian
-- only reads .md files, so it never shows the temporary one.
local TEMPORARY = ".omv-tmp"

-- The folder is made only when the file can't be opened, since a draft is written on every edit.
local function openMakingFolder(fs, path)
  local file = fs.open(path, "w")
  if file then return file end
  fs.mkdir(path:match("^(.*)/"))
  return fs.open(path, "w")
end

local function writeAll(fs, path, content)
  local file = openMakingFolder(fs, path)
  if not file then return false end
  local written = file:write(content)
  local closed = file:close()
  return written ~= nil and closed ~= nil
end

-- Writes content to path through a temporary file, then renames it over the note. On any
-- failure the note keeps its old content, the temporary file is removed, and it returns false.
function notefile.write(path, content, fs)
  local temporary = path .. TEMPORARY
  if not writeAll(fs, temporary, content) or not fs.rename(temporary, path) then
    fs.remove(temporary)
    return false
  end
  return true
end

-- The vault from ~/.config/omv/vault, its first line, where ~ means the home folder.
-- Without the file, or with nothing in it, the vault is ~/Documents/vault/work.
function notefile.vault(configText, home)
  local firstLine = tostring(configText or ""):match("^[^\n]*")
  local path = firstLine:match("^%s*(.-)%s*$")
  if path == "" then return home .. "/Documents/vault/work" end
  return (path:gsub("^~", home, 1))
end

return notefile
