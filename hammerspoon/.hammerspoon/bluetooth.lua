-- The Bluetooth card: paired devices from blueutil, connected first, and what Enter does
-- with each. features/bluetooth.lua runs blueutil.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local bluetooth = {}

-- Devices from a decoded `blueutil --paired --format json`, connected first, then by name.
-- A device without a name goes by its address.
function bluetooth.devices(list)
  local devices = {}
  if type(list) ~= "table" then return devices end
  for _, item in ipairs(list) do
    if type(item) == "table" and type(item.address) == "string" then
      local name = (type(item.name) == "string" and item.name ~= "") and item.name or item.address
      devices[#devices + 1] = { address = item.address, name = name, connected = item.connected == true }
    end
  end
  table.sort(devices, function(a, b)
    if a.connected ~= b.connected then return a.connected end
    return a.name < b.name
  end)
  return devices
end

function bluetooth.action(device)
  return device.connected and "disconnect" or "connect"
end

-- blueutil's arguments to connect or disconnect a device. Only a plain address, as blueutil
-- prints them, ever reaches the shell.
function bluetooth.command(action, address)
  if not tostring(address or ""):match("^[%x%-:]+$") then return nil end
  return "--" .. action .. " " .. address
end

-- Card rows: the power switch, then each device while Bluetooth is on. Without blueutil,
-- one row says how to install it.
function bluetooth.rows(state)
  if not state.installed then
    return { { id = "install", icon = "󰂲", label = "Bluetooth needs blueutil: brew install blueutil" } }
  end
  if not state.power then return { { id = "power.on", icon = "󰂯", label = "Turn Bluetooth on" } } end
  local rows = { { id = "power.off", icon = "󰂲", label = "Turn Bluetooth off" } }
  for _, device in ipairs(state.devices or {}) do
    rows[#rows + 1] = { id = "device:" .. device.address, icon = device.connected and "󰂱" or "󰂯", label = device.name,
      hint = device.connected and "connected" or "" }
  end
  return rows
end

return bluetooth
