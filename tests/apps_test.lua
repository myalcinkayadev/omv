-- Behavior of reading which browser and editor omv opens, from ~/.config/omv/apps.
-- Run through apps_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local apps = require("apps")

local chosen = apps.read("# my apps\nbrowser = Google Chrome\neditor=Cursor\n")
check.that("should read the browser", chosen.browser == "Google Chrome")
check.that("should read the editor", chosen.editor == "Cursor")
check.that("should use Helium without a file", apps.read(nil).browser == "Helium")
check.that("should use Zed without a file", apps.read(nil).editor == "Zed")
check.that("should keep the default for a key left out", apps.read("browser=Safari\n").editor == "Zed")
check.that("should ignore an empty value", apps.read("browser=\n").browser == "Helium")
check.that("should ignore unknown keys", apps.read("terminal=iTerm\n").terminal == nil)

check.finish()
