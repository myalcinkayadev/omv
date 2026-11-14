-- Feature flags: defaults in flags.lua, overridden by ~/.config/omv/flags. Run through
-- flags_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local flags = require("flags")

local function fileSearch(text) return flags.read(text)["file-search"] end

check.that("should be off when there's no flags file", fileSearch(nil) == false)
check.that("should turn a flag on when its line says on", fileSearch("file-search=on\n") == true)
check.that("should turn a flag off when its line says off", fileSearch("file-search=off") == false)
check.that("should ignore spaces around the name and value", fileSearch("  file-search = on ") == true)
check.that("should ignore a comment line", fileSearch("# file-search=on") == false)
check.that("should ignore a value that isn't on or off", fileSearch("file-search=yes") == false)
check.that("should ignore an unknown flag", flags.read("nope=on")["nope"] == nil)
check.that("should let the last line win", fileSearch("file-search=on\nfile-search=off") == false)
check.that("should keep the defaults unchanged when a file turns a flag on", (function()
  flags.read("file-search=on")
  return flags.DEFAULTS["file-search"] == false
end)())

check.finish()
