-- The Battery card opened from the bar's battery item, in the status-card layout of
-- panel.lua: the charge, battery size, time left, charge cycles and power, and a button
-- to Battery settings. init.lua runs pmset and ioreg and passes their output in.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local panel = require("panel")

local battery = {}

local DASH = "—"

battery.WIDTH = 420
battery.HEIGHT = 300

-- ioreg prints a negative current as its unsigned 64-bit value, 2^64 - n. That is too
-- big for a Lua number to hold exactly, so the difference is taken on the last digits.
local TWO_TO_64_PREFIX, TWO_TO_64_TAIL = "1844674407", 3709551616

local function signed(digits)
  if not digits then return nil end
  if #digits == 20 and digits:sub(1, 10) == TWO_TO_64_PREFIX then
    return -(TWO_TO_64_TAIL - tonumber(digits:sub(11)))
  end
  return tonumber(digits)
end

local function stateOf(word)
  if word == "discharging" then return "DRAINING" end
  if word == "charging" or word == "finishing charge" then return "CHARGING" end
  return "CHARGED"
end

-- Reads `pmset -g batt`. Gives nil when the Mac has no battery.
function battery.parseBatt(text)
  local line = text:match("InternalBattery[^\n]*")
  if not line then return nil end
  local percent, word = line:match("(%d+)%%;%s*([^;]+);")
  if not percent then return nil end
  local state = stateOf(word)
  local hours, minutes = line:match("(%d+):(%d+) remaining")
  local left = hours and (tonumber(hours) * 60 + tonumber(minutes)) or nil
  if state == "CHARGED" or left == 0 then left = nil end
  return { percent = tonumber(percent), state = state, minutes = left }
end

local function value(text, key)
  return text:match('"' .. key .. '"%s*=%s*(%d+)')
end

-- Reads `ioreg -rn AppleSmartBattery`: cycles, full-charge size in Wh, and power in W
-- (negative while draining).
function battery.parseSmartBattery(text)
  local capacity, voltage = tonumber(value(text, "AppleRawMaxCapacity")), tonumber(value(text, "Voltage"))
  local amperage = signed(value(text, "Amperage"))
  return {
    cycles = tonumber(value(text, "CycleCount")),
    wattHours = capacity and voltage and math.floor(capacity * voltage / 1e6 + 0.5) or nil,
    watts = amperage and voltage and amperage * voltage / 1e6 or nil,
  }
end

local function duration(minutes)
  if not minutes then return DASH end
  return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

local function orDash(text, number)
  return number and text or DASH
end

-- status from parseBatt, health from parseSmartBattery.
function battery.model(status, health)
  local charging = status.state == "CHARGING"
  return {
    icon = charging and "󰂄" or "󰁹",
    title = "Battery",
    sub = status.state,
    big = status.percent .. "%",
    percent = status.percent,
    grid = {
      { "Battery size", orDash((health.wattHours or 0) .. "Wh", health.wattHours) },
      { charging and "Time to full" or "Time left", duration(status.minutes) },
      { "Charge cycles", orDash(tostring(health.cycles), health.cycles) },
      { charging and "Charging" or "Discharging", orDash(string.format("%.1fW", math.abs(health.watts or 0)), health.watts) },
    },
    buttons = { { id = "battery.settings", icon = "󰒓", label = "Battery settings" } },
  }
end

battery.html = panel.html
battery.update = panel.update

return battery
