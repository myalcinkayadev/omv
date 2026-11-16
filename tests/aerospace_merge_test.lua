-- The aerospace.toml merge: omv's defaults with the user's keys applied. Run through
-- aerospace_merge_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local merge = dofile(arg[1] .. "/install/aerospace_merge.lua")

local HEADER = "# Built by omv from its defaults and ~/.config/omv/aerospace.toml. Edit that file, then run omv reload."

local DEFAULTS = table.concat({
  "config-version = 2",
  "after-startup-command = [",
  "  'omv-a',",
  "  'omv-b',",
  "]",
  "",
  "# Gaps between windows",
  "[gaps]",
  "inner.horizontal = 10",
  "inner.vertical = 10",
  "",
  "[mode.main.binding]",
  "alt-h = 'focus left'",
  "",
  "# Workspace 2",
  "[[on-window-detected]]",
  "if.app-id = 'x'",
  "run = 'move-node-to-workspace 2'",
  "",
}, "\n")

local function built(user) return (merge.build(DEFAULTS, user)) end

-- The lines of the table that starts at header, up to the next header.
local function section(text, header)
  local from = text:find("\n" .. header .. "\n", 1, true)
  if not from then return "" end
  local rest = text:sub(from + #header + 2)
  local stop = rest:find("\n%[") or #rest + 1
  return rest:sub(1, stop)
end

check.that("should start the built file with the header when it builds",
  built(nil):sub(1, #HEADER + 1) == HEADER .. "\n")

check.that("should keep omv's file when there's no user file", built(nil) == HEADER .. "\n" .. DEFAULTS)

check.that("should keep omv's file when the user file is empty", built("") == HEADER .. "\n" .. DEFAULTS)

check.that("should replace a key inside a table when the user sets it", (function()
  local gaps = section(built("[gaps]\ninner.horizontal = 4\n"), "[gaps]")
  return check.contains(gaps, "inner.horizontal = 4") and not check.contains(gaps, "inner.horizontal = 10")
end)())

check.that("should keep the table's other keys when the user replaces one",
  check.contains(section(built("[gaps]\ninner.horizontal = 4\n"), "[gaps]"), "inner.vertical = 10"))

check.that("should replace a multi-line value whole when the user sets it", (function()
  local text = built("after-startup-command = ['mine']\n")
  return check.contains(text, "after-startup-command = ['mine']") and not check.contains(text, "omv-a")
    and not check.contains(text, "omv-b")
end)())

check.that("should take a user value that spans lines when it replaces omv's", (function()
  local text = built("after-startup-command = [\n  'one',\n  'two',\n]\n")
  return check.contains(text, "after-startup-command = [\n  'one',\n  'two',\n]") and not check.contains(text, "omv-a")
end)())

check.that("should add a key omv doesn't have to its table when the user sets it",
  check.contains(section(built("[mode.main.binding]\nalt-z = 'close'\n"), "[mode.main.binding]"), "alt-z = 'close'"))

check.that("should add a table omv doesn't have when the user writes one",
  check.contains(section(built("[key-mapping]\npreset = 'qwerty'\n"), "[key-mapping]"), "preset = 'qwerty'"))

check.that("should add a top-level key omv doesn't have before the first table", (function()
  local text = built("start-at-login = true\n")
  local key, table = text:find("start-at-login = true", 1, true), text:find("[gaps]", 1, true)
  return key ~= nil and key < table
end)())

check.that("should append the user's window rules after omv's when the user adds one", (function()
  local text = built("[[on-window-detected]]\nif.app-id = 'mine'\nrun = 'layout floating'\n")
  local omvRule, userRule = text:find("if.app-id = 'x'", 1, true), text:find("if.app-id = 'mine'", 1, true)
  return omvRule ~= nil and userRule ~= nil and omvRule < userRule
end)())

check.that("should keep omv's comments when it merges", check.contains(built("[gaps]\ninner.horizontal = 4\n"), "# Workspace 2"))

check.that("should ignore brackets and hashes inside quotes when it reads a value", (function()
  local text = built("after-startup-command = ['a ] # b']\n")
  return check.contains(text, "after-startup-command = ['a ] # b']") and not check.contains(text, "omv-a")
end)())

check.that("should merge a table the user names twice", (function()
  local gaps = section(built("[gaps]\ninner.horizontal = 4\n[mode.main.binding]\nalt-z = 'close'\n[gaps]\ninner.vertical = 6\n"), "[gaps]")
  return check.contains(gaps, "inner.horizontal = 4") and check.contains(gaps, "inner.vertical = 6")
end)())

check.that("should name the line it can't read when a table header isn't closed", (function()
  local text, problem = merge.build(DEFAULTS, "[gaps]\ninner.horizontal = 4\n[mode.main\n")
  return text == nil and problem ~= nil and problem:sub(1, 7) == "line 3:"
end)())

check.that("should name the line it can't read when a line has no value", (function()
  local text, problem = merge.build(DEFAULTS, "alt-z\n")
  return text == nil and problem ~= nil and problem:sub(1, 7) == "line 1:"
end)())

check.that("should name the line where a value is left open", (function()
  local text, problem = merge.build(DEFAULTS, "x = 1\nafter-startup-command = [\n  'a',\n")
  return text == nil and problem ~= nil and problem:sub(1, 7) == "line 2:"
end)())

check.finish()
