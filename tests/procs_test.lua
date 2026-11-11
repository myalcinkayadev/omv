-- Behavior of the hungry process card: reading ps and lsof, ordering, and what can be done.
-- Run through procs_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local procs = require("procs")

local ps = table.concat({
  "65076  85.7  161888 npm exec ccstatusline",
  "  667  10.7  646112 /System/Applications/Music.app/Contents/MacOS/Music",
  "98422   8.0 2682960 claude",
  "  401   0.5   90000 /System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
  "    1   0.1   12000 /sbin/launchd",
  " 5555   3.0  200000 /Applications/Hammerspoon.app/Contents/MacOS/Hammerspoon",
  "  777   0.0    4000 /Applications/Helium.app/Contents/Frameworks/Helium Framework.framework/Helpers/Helium Helper",
}, "\n")
local list = procs.parse(ps, 5555)

check.that("should read PID, CPU, memory and name from ps output",
  list[1].pid == 65076 and list[1].cpu == 85.7 and list[1].memory == 161888 * 1024 and list[1].name == "npm exec ccstatusline")
check.that("should name a process by its file name, not its full path",
  list[2].name == "Music" and list[#list].name == "Helium Helper")

local names = {}
for _, process in ipairs(list) do names[process.name] = true end
check.that("should leave out loginwindow, launchd and Hammerspoon itself",
  not names.loginwindow and not names.launchd and not names.Hammerspoon)

local byCpu = procs.sorted(list, "cpu")
check.that("should sort by CPU, busiest first", byCpu[1].pid == 65076 and byCpu[2].pid == 667)
local byMemory = procs.sorted(list, "memory")
check.that("should sort by memory when asked", byMemory[1].pid == 98422)

check.that("should show memory as MB under 1 GB", procs.size(161888 * 1024) == "158 MB")
check.that("should show memory as GB from 1 GB", procs.size(2682960 * 1024) == "2.6 GB")

local many = {}
for index = 1, 30 do many[index] = string.format("%d 1.0 1000 p%d", index + 100, index) end
check.that("should list at most 20 processes", #procs.sorted(procs.parse(table.concat(many, "\n"), 0), "cpu") == 20)
check.that("should give no rows for empty ps output", #procs.parse("", 0) == 0)

local folders = procs.folders("p667\nfcwd\nn/\np65076\nfcwd\nn/Users/me/workspace/omv\n", "/Users/me")
check.that("should read each process's folder from lsof output", folders[65076] ~= nil)
check.that("should show a folder under home as ~/...", folders[65076] == "~/workspace/omv")
check.that("should leave out a folder that is just /", folders[667] == nil)

local rows = procs.rows(byCpu, folders, "cpu")
check.that("should hint CPU first when sorting by CPU", rows[1].hint == "85.7% · 158 MB")
check.that("should show a process's folder beside its name", rows[1].label == "npm exec ccstatusline  ~/workspace/omv")
check.that("should hint memory first when sorting by memory", procs.rows(byMemory, {}, "memory")[1].hint == "2.6 GB · 8.0%")

local confirm = procs.confirm({ pid = 65076, name = "npm exec ccstatusline" }, false)
check.that("should offer Cancel first, then Quit", confirm.rows[1].id == "cancel" and confirm.rows[2].id == "quit")
local force = procs.confirm({ pid = 65076, name = "npm exec ccstatusline" }, true)
check.that("should offer Force quit after a quit fails", force.rows[2].id == "force")

local card = require("card")
check.that("should let a card ask for Tab", check.contains(card.html({ prompt = "x", rows = {}, tab = true }), "data-tab"))
check.that("should leave Tab alone in other cards", not check.contains(card.html({ prompt = "x", rows = {} }), "data-tab"))

check.finish()
