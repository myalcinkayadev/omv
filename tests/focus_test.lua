-- Behavior of Do Not Disturb: reading macOS's Focus files, and the shortcut that switches it.
-- Run through focus_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local focus = require("focus")

local DND = "com.apple.donotdisturb.mode.default"
local on = { data = { { storeAssertionRecords = { { assertionDetails = { assertionDetailsModeIdentifier = DND } } } } } }
local configs = { data = { { modeConfigurations = {
  [DND] = { mode = { name = "Do Not Disturb", modeIdentifier = DND } },
  ["com.apple.focus.work"] = { mode = { name = "Work", modeIdentifier = "com.apple.focus.work" } },
} } } }

check.that("should find the Focus that is on", focus.activeMode(on) == DND)
check.that("should find no Focus when there are no assertions", focus.activeMode({ data = { {} } }) == nil)
check.that("should find no Focus when the assertions are empty",
  focus.activeMode({ data = { { storeAssertionRecords = {} } } }) == nil)
check.that("should find no Focus in a file it can't read", focus.activeMode(nil) == nil)
check.that("should name the Focus that is on", focus.modeName(configs, DND) == "Do Not Disturb")
check.that("should name another Focus by its own name", focus.modeName(configs, "com.apple.focus.work") == "Work")
check.that("should call a Focus it can't name just Focus", focus.modeName(nil, "com.apple.focus.x") == "Focus")
check.that("should find the shortcut among the user's shortcuts",
  focus.hasShortcut("Dyson air\n" .. focus.SHORTCUT .. "\nOther\n"))
check.that("should not find the shortcut when it is missing", not focus.hasShortcut("Dyson air\nOther\n"))
check.that("should not take a longer name for the shortcut", not focus.hasShortcut(focus.SHORTCUT .. " copy\n"))

check.finish()
