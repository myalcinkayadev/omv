-- Bluetooth card (Option+Shift+Y, or a click on the bar's Bluetooth icon): turns Bluetooth
-- on or off, and connects or disconnects paired devices, connected ones first. It reads and
-- changes Bluetooth through blueutil (brew install blueutil); without it, the card says so.
-- The first time, macOS asks to let Hammerspoon use Bluetooth.

local shell = require("shell")
local card = require("card")
local bluetooth = require("bluetooth")

local feature = {}

local BLUEUTIL = "/opt/homebrew/bin/blueutil"
local WIDTH = 420
local VISIBLE_ROWS = 10

local function blueutil(arguments)
  return hs.execute(BLUEUTIL .. " " .. arguments .. " 2>/dev/null") or ""
end

local function state()
  if not hs.fs.attributes(BLUEUTIL) then return { installed = false } end
  local power = bluetooth.readPower(blueutil("--power"))
  if power == nil then return { installed = true, denied = true } end
  local devices = {}
  if power then
    local ok, list = pcall(hs.json.decode, blueutil("--paired --format json"))
    devices = bluetooth.devices(ok and list or nil)
  end
  return { installed = true, power = power, devices = devices }
end

-- The bar's icon redraws on this event.
local function redrawIcon()
  hs.task.new(shell.SKETCHYBAR, nil, { "--trigger", "bluetooth_change" }):start()
end

local show

-- Connecting can take a few seconds, so it runs in the background and the card redraws after.
local function toggleDevice(device)
  local command = bluetooth.command(bluetooth.action(device), device.address)
  if not command then return end
  shell.alert((device.connected and "Disconnecting " or "Connecting ") .. device.name, 1.5)
  local arguments = {}
  for word in command:gmatch("%S+") do arguments[#arguments + 1] = word end
  hs.task.new(BLUEUTIL, function()
    if shell.isOpen("bluetooth") then show() end
  end, arguments):start()
end

local BLUETOOTH_PRIVACY = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"

local function onMessage(message)
  if message.type ~= "choose" then return shell.close() end
  if message.id == "settings" then
    shell.close()
    return shell.open({ BLUETOOTH_PRIVACY })()
  end
  if message.id == "power.on" or message.id == "power.off" then
    blueutil("--power " .. (message.id == "power.on" and "1" or "0"))
    redrawIcon()
    return show()
  end
  local address = message.id:match("^device:(.+)$")
  for _, device in ipairs(state().devices or {}) do
    if device.address == address then return toggleDevice(device) end
  end
end

show = function()
  local rows = bluetooth.rows(state())
  local screen = { prompt = "Bluetooth…", rows = rows, compact = true }
  shell.show("bluetooth", shell.anchored(WIDTH, shell.listHeight(#rows, VISIBLE_ROWS), "bluetooth"), card.html(screen), onMessage)
end

-- For the bar's icon: "1" when on, "0" when off, "" when it can't be read. SketchyBar asks
-- through hs -c, since only Hammerspoon has Bluetooth access.
function feature.power()
  if not hs.fs.attributes(BLUEUTIL) then return "" end
  local power = bluetooth.readPower(blueutil("--power"))
  if power == nil then return "" end
  return power and "1" or "0"
end

function feature.toggle()
  if shell.isOpen("bluetooth") then return shell.close() end
  show()
end

return feature
