-- Editing ~/.config/omv/workspaces' sections in place: only the lines asked for change, and
-- comments stay. Run through inifile_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local inifile = require("inifile")

local TEXT = [[
# mine
[workspace 1]
on   = DELL, main     # the desk
# apps = Zed

[workspace 2]
apps = Helium
]]

check.that("should replace a value and keep its comment",
  check.contains(inifile.set(TEXT, "workspace 1", "on", "LG, main"), "on   = LG, main     # the desk\n"))
check.that("should remove the # from a key saved as a comment", check.contains(inifile.set(TEXT, "workspace 1", "apps", "Zed, Arc"), "\napps = Zed, Arc\n"))
check.that("should add a key the section lacks after its last line",
  check.contains(inifile.set(TEXT, "workspace 2", "layout", "tabs"), "[workspace 2]\napps = Helium\nlayout = tabs\n"))
check.that("should remove a key's line for nil", not check.contains(inifile.set(TEXT, "workspace 2", "apps", nil), "Helium"))
check.that("should leave another section alone", check.contains(inifile.set(TEXT, "workspace 2", "on", "main"), "[workspace 1]\non   = DELL, main     # the desk\n"))
check.that("should add a missing section at the end, after a blank line",
  check.contains(inifile.set(TEXT, "screen laptop", "gaps", 4), "apps = Helium\n\n[screen laptop]\ngaps = 4\n"))
check.that("should leave the text alone when removing a key from a missing section", inifile.set(TEXT, "screen x", "gaps", nil) == TEXT)
check.that("should match a section's name in any spacing", check.contains(inifile.set("[ workspace  2 ]\n", "workspace 2", "on", "main"), "on = main"))
local without, block = inifile.removeSection(TEXT, "workspace 1")
check.that("should remove a section", not check.contains(without, "[workspace 1]") and check.contains(without, "[workspace 2]"))
check.that("should give back the removed lines", check.contains(block, "[workspace 1]\non   = DELL, main"))
check.that("should keep one blank line between the sections around a removed one", without == "# mine\n[workspace 2]\napps = Helium\n")
check.that("should find a section with nothing under its header empty",
  inifile.isEmpty("[screen DELL]\n\n[workspace 1]\non = main\n", "screen DELL") and not inifile.isEmpty("[screen DELL]\n# mine\n", "screen DELL")
  and not inifile.isEmpty("", "screen DELL"))
check.that("should say whether a section exists", inifile.hasSection(TEXT, "workspace 2") and not inifile.hasSection(TEXT, "workspace 3"))

check.finish()
