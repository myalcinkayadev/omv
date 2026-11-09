-- Battery card (click the battery icon, Option+Shift+B).

local shell = require("shell")
local battery = require("battery")

local feature = {}

local BATTERY_SETTINGS = "x-apple.systempreferences:com.apple.Battery-Settings.extension"

local function onBatteryMessage(message)
  shell.close()
  if message.type == "choose" then shell.open({ BATTERY_SETTINGS })() end
end

local function showBattery()
  local status = battery.parseBatt(hs.execute("/usr/bin/pmset -g batt"))
  if not status then return shell.alert("This Mac has no battery", 1.5) end
  local health = battery.parseSmartBattery(hs.execute("/usr/sbin/ioreg -rn AppleSmartBattery"))
  shell.show("battery", shell.anchored(battery.WIDTH, battery.HEIGHT), battery.html(battery.model(status, health)), onBatteryMessage)
end

function feature.toggle()
  if shell.isOpen("battery") then return shell.close() end
  showBattery()
end

return feature
