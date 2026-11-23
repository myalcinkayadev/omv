-- Battery card (click the battery icon, Option+Shift+B).

local shell = require("shell")
local battery = require("battery")

local feature = {}

local BATTERY_SETTINGS = "x-apple.systempreferences:com.apple.Battery-Settings.extension"

local function onBatteryMessage(message)
  shell.close()
  if message.type == "choose" then shell.open({ BATTERY_SETTINGS })() end
end

-- Hands done the card's model now, or nil on a Mac without a battery. pmset and ioreg run in
-- the background, so the cards stay live while they read.
local function model(done)
  shell.execute("/usr/bin/pmset -g batt", function(batt)
    local status = battery.parseBatt(batt)
    if not status then return done(nil) end
    shell.execute("/usr/sbin/ioreg -rn AppleSmartBattery", function(smart)
      done(battery.model(status, battery.parseSmartBattery(smart)))
    end)
  end)
end

local function showBattery()
  model(function(current)
    if not current then return shell.alert("This Mac has no battery", 1.5) end
    shell.show("battery", shell.anchored(battery.WIDTH, battery.HEIGHT, "battery"), battery.html(current), onBatteryMessage)
  end)
end

function feature.toggle()
  if shell.isOpen("battery") then return shell.close() end
  showBattery()
end

-- The battery is watched, not polled: a change redraws the bar's icon at once, and the open
-- card updates in place. macOS reports several changes at a time, so they wait 0.2s.
local batteryChanged = hs.timer.delayed.new(0.2, function()
  hs.task.new(shell.SKETCHYBAR, nil, { "--trigger", "omv_battery_change" }):start()
  if not shell.isOpen("battery") then return end
  model(function(current)
    if current and shell.isOpen("battery") then shell.view():evaluateJavaScript(battery.update(current)) end
  end)
end)

-- Kept on the feature, so it isn't garbage-collected.
feature.watcher = hs.battery.watcher.new(function() batteryChanged:start() end):start()

return feature
