-- Behavior of night light: reading `nightlight status`, and which way a switch goes.
-- Run through nightshift_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local nightshift = require("nightshift")

check.that("should read that Night Shift is on", nightshift.isOn("on until sunrise\n"))
check.that("should read that Night Shift is off", not nightshift.isOn("off until sunset\n"))
check.that("should read an unknown answer as off", not nightshift.isOn("error: unsupported\n"))
check.that("should read no answer as off", not nightshift.isOn(nil))
check.that("should switch off when on", nightshift.switch("on until sunrise") == "off")
check.that("should switch on when off", nightshift.switch("off until sunset") == "on")

check.finish()
