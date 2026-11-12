-- Battery card (click the battery icon, Option+Shift+B).

local shell = require("shell")
local battery = require("battery")

local feature = {}

local BATTERY_SETTINGS = "x-apple.systempreferences:com.apple.Battery-Settings.extension"

local function onBatteryMessage(message)
  shell.close()
  if message.type == "choose" then shell.open({ BATTERY_SETTINGS })() end
end

-- The card's model now, or nil on a Mac without a battery.
local function model()
  local status = battery.parseBatt(hs.execute("/usr/bin/pmset -g batt"))
  if not status then return nil end
  return battery.model(status, battery.parseSmartBattery(hs.execute("/usr/sbin/ioreg -rn AppleSmartBattery")))
end

local function showBattery()
  local current = model()
  if not current then return shell.alert("This Mac has no battery", 1.5) end
  shell.show("battery", shell.anchored(battery.WIDTH, battery.HEIGHT, "battery"), battery.html(current), onBatteryMessage)
end

function feature.toggle()
  if shell.isOpen("battery") then return shell.close() end
  showBattery()
end

-- The battery is watched, not polled: a change redraws the bar's icon at once, and the open
-- card updates in place. macOS reports several changes at a time, so they wait 0.2s.
local batteryChanged = hs.timer.delayed.new(0.2, function()
  hs.task.new(shell.SKETCHYBAR, nil, { "--trigger", "omv_battery_change" }):start()
  local current = shell.isOpen("battery") and model()
  if current then shell.view():evaluateJavaScript(battery.update(current)) end
end)

-- Kept on the feature, so it isn't garbage-collected.
feature.watcher = hs.battery.watcher.new(function() batteryChanged:start() end):start()

return feature
