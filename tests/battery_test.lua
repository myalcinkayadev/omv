-- Behavior of the Battery card. Run through battery_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local battery = require("battery")

local DASH = "—"

local DISCHARGING = [[
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=23461987)	78%; discharging; 6:05 remaining present: true
]]
local CHARGING = [[
Now drawing from 'AC Power'
 -InternalBattery-0 (id=23461987)	41%; charging; 1:12 remaining present: true
]]
local CHARGED = [[
Now drawing from 'AC Power'
 -InternalBattery-0 (id=23461987)	100%; charged; 0:00 remaining present: true
]]
local NOT_CHARGING = [[
Now drawing from 'AC Power'
 -InternalBattery-0 (id=23461987)	80%; AC attached; not charging present: true
]]
local NO_ESTIMATE = [[
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=23461987)	78%; discharging; (no estimate) present: true
]]
local SMART_BATTERY = [[
      "Amperage" = 18446744073709551232
      "AppleRawCurrentCapacity" = 3773
      "CycleCount" = 188
      "AppleRawMaxCapacity" = 5092
      "Voltage" = 12131
]]

local status = battery.parseBatt(DISCHARGING)
check.that("should read the charge when discharging", status.percent == 78)
check.that("should read discharging as draining", status.state == "DRAINING")
check.that("should read the time left in minutes", status.minutes == 365)
check.that("should read charging as charging", battery.parseBatt(CHARGING).state == "CHARGING")
check.that("should read charged as charged", battery.parseBatt(CHARGED).state == "CHARGED")
check.that("should read AC attached but not charging as charged", battery.parseBatt(NOT_CHARGING).state == "CHARGED")
check.that("should read no estimate as no time", battery.parseBatt(NO_ESTIMATE).minutes == nil)
check.that("should give nothing when the Mac has no battery", battery.parseBatt("Now drawing from 'AC Power'\n") == nil)

local health = battery.parseSmartBattery(SMART_BATTERY)
check.that("should read the charge cycles", health.cycles == 188)
check.that("should give the battery size in Wh from capacity and voltage", health.wattHours == 62)
check.that("should read a negative current written as a large unsigned number", math.abs(health.watts + 4.66) < 0.01)
check.that("should read a positive current as charging power",
  math.abs(battery.parseSmartBattery('"Amperage" = 2000\n"Voltage" = 12500\n').watts - 25) < 0.05)
check.that("should give nothing for missing values", battery.parseSmartBattery("").cycles == nil)


local page = battery.html(battery.model(status, health))
local visible = check.visible(page)
check.that("should show the charge as the big number", check.contains(visible, "78%"))
check.that("should fill the bar to the charge", check.contains(page, "width: 78%"))
check.that("should show draining as the status line", check.contains(visible, "DRAINING"))
check.that("should show the battery size", check.contains(visible, "62Wh"))
check.that("should show the charge cycles", check.contains(visible, "188"))
check.that("should show the time left in hours and minutes", check.contains(visible, "6h 05m"))
check.that("should label the time as time left when draining", check.contains(visible, "Time left"))
check.that("should label the power as discharging when draining", check.contains(visible, "Discharging"))
check.that("should show the power in watts", check.contains(visible, "4.7W"))
check.that("should offer Battery settings", check.contains(visible, "Battery settings"))
check.that("should give the settings button its id", check.contains(page, 'data-id="battery.settings"'))
check.that("should offer no power profile", not check.contains(visible, "POWER PROFILE"))

local charging = check.visible(battery.html(battery.model(battery.parseBatt(CHARGING), health)))
check.that("should label the time as time to full when charging", check.contains(charging, "Time to full"))
check.that("should label the power as charging when charging", check.contains(charging, "Charging"))

local bare = check.visible(battery.html(battery.model(battery.parseBatt(NO_ESTIMATE), {})))
check.that("should show dashes for missing values", select(2, bare:gsub(DASH, "")) >= 4)

check.that("should update the open Battery card in place", check.contains(battery.update(battery.model(status, health)), "omvUpdate("))

check.finish()
