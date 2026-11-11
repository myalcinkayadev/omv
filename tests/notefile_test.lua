-- Behavior of writing a note safely and finding the vault. Run through notefile_test.sh
-- with luajit. The file system is a table, so nothing touches the disk.

local check = dofile(arg[1] .. "/tests/check.lua")
local notefile = require("notefile")

local NOTE = "/vault/00 - Daily/2026-11-11.md"

-- A file system kept in a table. failWrite makes every write fail, failRename every rename,
-- and missing lists folders that don't exist until mkdir makes them.
local function fakeFs(options)
  options = options or {}
  local fs = { files = {}, renamed = {}, missing = options.missing or {} }
  local function folder(path) return path:match("^(.*)/") end
  function fs.open(path, _)
    if fs.missing[folder(path)] then return nil end
    local buffer = {}
    return {
      write = function(self, text)
        if options.failWrite then return nil, "disk full" end
        buffer[#buffer + 1] = text
        return self
      end,
      close = function() fs.files[path] = table.concat(buffer); return true end,
    }
  end
  function fs.rename(from, to)
    if options.failRename then return nil, "busy" end
    fs.renamed[#fs.renamed + 1] = { from = from, to = to }
    fs.files[to], fs.files[from] = fs.files[from], nil
    return true
  end
  function fs.remove(path) fs.files[path] = nil; return true end
  function fs.mkdir(path) fs.missing[path] = nil end
  return fs
end

local function fileCount(fs)
  local count = 0
  for _ in pairs(fs.files) do count = count + 1 end
  return count
end

local fs = fakeFs()
check.that("should report success when the note is written", notefile.write(NOTE, "- 09:05 call", fs) == true)
check.that("should leave the new content in the note", fs.files[NOTE] == "- 09:05 call")
check.that("should leave no other file behind", fileCount(fs) == 1)
check.that("should write the note through a temporary file in the same folder",
  fs.renamed[1].from ~= NOTE and fs.renamed[1].from:match("^(.*)/") == NOTE:match("^(.*)/"))

fs = fakeFs({ failWrite = true })
fs.files[NOTE] = "old"
check.that("should report failure when writing the temporary file fails", notefile.write(NOTE, "new", fs) == false)
check.that("should leave the old note unchanged when writing the temporary file fails", fs.files[NOTE] == "old")
check.that("should remove the temporary file when writing it fails", fileCount(fs) == 1)

fs = fakeFs({ failRename = true })
fs.files[NOTE] = "old"
check.that("should report failure when the rename fails", notefile.write(NOTE, "new", fs) == false)
check.that("should leave the old note unchanged when the rename fails", fs.files[NOTE] == "old")
check.that("should remove the temporary file when the rename fails", fileCount(fs) == 1)

fs = fakeFs({ missing = { ["/vault/Inbox"] = true } })
notefile.write("/vault/Inbox/Plan.md", "# Plan", fs)
check.that("should make the folder when it is missing", fs.files["/vault/Inbox/Plan.md"] == "# Plan")

local HOME = "/Users/me"
check.that("should use the vault path from the config file when it is set",
  notefile.vault("/Users/me/notes\n", HOME) == "/Users/me/notes")
check.that("should read ~ in the config file as the home folder", notefile.vault("~/notes", HOME) == "/Users/me/notes")
check.that("should use ~/Documents/vault/work when there is no config file",
  notefile.vault(nil, HOME) == "/Users/me/Documents/vault/work")
check.that("should use ~/Documents/vault/work when the config file is empty",
  notefile.vault("  \n", HOME) == "/Users/me/Documents/vault/work")

check.finish()
