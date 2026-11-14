-- Behavior of the Option+Space palette: windows, apps and omv's commands in one list.
-- Run through palette_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local palette = require("palette")

check.that("should name an app by its bundle's name", palette.appName("Safari.app") == "Safari")
check.that("should skip a file that isn't an app", palette.appName("README.txt") == nil)
check.that("should skip a hidden app", palette.appName(".Hidden.app") == nil)

local apps = palette.appRows({
  { name = "Zed", path = "/Applications/Zed.app" },
  { name = "calculator", path = "/System/Applications/Calculator.app" },
  { name = "Zed", path = "/Users/me/Applications/Zed.app" },
})
check.that("should list apps by name, whatever the case", apps[1].label == "calculator" and apps[2].label == "Zed")
check.that("should list an app found twice once", #apps == 2)
check.that("should open an app by its path", apps[1].id == "app:/System/Applications/Calculator.app")
check.that("should group apps under Apps", apps[1].group == "Apps")

local launchers = {
  { label = "Option+Space", description = "Go to any window", group = "Cards", run = function() end, runs = true },
  { label = "Option+Shift+W", description = "Wi-Fi", group = "Cards", run = function() end, runs = true },
  { label = "Option+`", description = "Drop-down terminal", group = "Apps", runs = false },
}
local commands = palette.commandRows(launchers, "Option+Space")
check.that("should list omv's commands by what they do", commands[1].label == "Wi-Fi")
check.that("should show a command's key beside it", commands[1].hint == "Option+Shift+W")
check.that("should run a command by its place in the key list", commands[1].id == "command:2")
check.that("should leave out the palette's own key", #commands == 1)
check.that("should leave out keys omv can't run itself", commands[2] == nil)
check.that("should group commands under Commands", commands[1].group == "Commands")

local windows = palette.windowRows("12|Ghostty|1|~/omv\n34|Zed|2|\n")
check.that("should list windows from AeroSpace", #windows == 2)
check.that("should focus a window by its id", windows[1].id == "window:12")
check.that("should group windows under Windows", windows[1].group == "Windows")

local all = palette.rows("12|Ghostty|1|~/omv\n", { { name = "Zed", path = "/Applications/Zed.app" } }, launchers, "Option+Space")
check.that("should list windows, then apps, then commands",
  all[1].group == "Windows" and all[2].group == "Apps" and all[3].group == "Commands")

check.that("should read a window to focus from a row", select(2, palette.parse("window:12")) == "12")
check.that("should read an app to open from a row", palette.parse("app:/Applications/Zed.app") == "app")
check.that("should read a command to run from a row", select(2, palette.parse("command:2")) == 2)
check.that("should read nothing from an unknown row", palette.parse("nope") == nil)


local card = require("card")
check.that("should read a calculator row's result", select(2, palette.parse("calc:70")) == "70")
check.that("should read a calculator row as calc", palette.parse("calc:70") == "calc")
check.that("should keep a decimal result as typed", select(2, palette.parse("calc:0.3333333333")) == "0.3333333333")
check.that("should mark a card that asks for the calculator", card.html({ prompt = "x", rows = {}, calc = true }):find("data-calc", 1, true) ~= nil)
check.that("should add the calculator to a card that asks for it", card.html({ prompt = "x", rows = {}, calc = true }):find("function omvCalc", 1, true) ~= nil)
check.that("should leave the calculator out of other cards", card.html({ prompt = "x", rows = {} }):find("function omvCalc", 1, true) == nil)
check.that("should read a file row's path", select(2, palette.parse("file:/a b/c.md")) == "/a b/c.md")
check.that("should read a file row as file", palette.parse("file:/a b/c.md") == "file")
check.that("should let a card ask for files when it allows them", card.html({ prompt = "x", rows = {}, files = true }):find("<body[^>]* data%-files") ~= nil)
check.that("should keep other cards from asking for files", card.html({ prompt = "x", rows = {} }):find("<body[^>]* data%-files") == nil)
local fileRow = { id = "file:/x/a<b&\"c.md", icon = "f", label = 'a<b&"c.md', hint = "~/x", group = "Files" }
check.that("should hand the page rows for the text they were found for", card.filesCall("rea", { fileRow }):find('omvFiles("rea",', 1, true) == 1)
check.that("should escape a file name in the rows it hands over", card.filesCall("rea", { fileRow }):find("a&lt;b&amp;&quot;c.md", 1, true) ~= nil)
check.that("should hand over no raw markup from a file name", card.filesCall("rea", { fileRow }):find("a<b", 1, true) == nil)

check.finish()
