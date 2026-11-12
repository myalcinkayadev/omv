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

-- `blueutil --power`: true when on, false when off, nil when blueutil was refused, which
-- happens when the app running it has no Bluetooth access.
function bluetooth.readPower(output)
  local first = tostring(output or ""):match("^%s*(%S)")
  if first == "1" then return true end
  if first == "0" then return false end
  return nil
end

-- Devices from a decoded `blueutil --inquiry --format json`, left out when already paired.
-- The search finds classic Bluetooth only: Bluetooth Low Energy devices pair in Settings.
function bluetooth.found(list, paired)
  local known = {}
  for _, device in ipairs(paired or {}) do known[device.address] = true end
  local found = {}
  for _, device in ipairs(bluetooth.devices(list)) do
    if not known[device.address] then found[#found + 1] = device end
  end
  return found
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
-- or without Bluetooth access for Hammerspoon, one row says what's needed.
function bluetooth.rows(state)
  if not state.installed then
    return { { id = "install", icon = "󰂲", label = "Bluetooth needs blueutil: brew install blueutil" } }
  end
  if state.denied then
    return { { id = "settings", icon = "󰂲", label = "Allow Bluetooth for Hammerspoon in Privacy & Security" } }
  end
  local settings = { id = "settings.bluetooth", icon = "󰒓", label = "Bluetooth Settings" }
  if not state.power then return { { id = "power.on", icon = "󰂯", label = "Turn Bluetooth on" }, settings } end
  local rows = { { id = "power.off", icon = "󰂲", label = "Turn Bluetooth off" } }
  if state.failed then
    rows[#rows + 1] = { id = "settings.bluetooth", icon = "󰂲", label = "Couldn't pair " .. state.failed .. ": try Bluetooth Settings" }
  end
  for _, device in ipairs(state.devices or {}) do
    rows[#rows + 1] = { id = "device:" .. device.address, icon = device.connected and "󰂱" or "󰂯", label = device.name,
      hint = device.connected and "connected" or "" }
  end
  if state.searching then
    rows[#rows + 1] = { id = "searching", icon = "󰑐", label = "Searching…", hint = "10s" }
  elseif state.found and #state.found == 0 then
    rows[#rows + 1] = { id = "search", icon = "󰂰", label = "Nothing new found · search again" }
  elseif state.found then
    for _, device in ipairs(state.found) do
      rows[#rows + 1] = { id = "pair:" .. device.address, icon = "󰂰", label = device.name, hint = "Enter pairs" }
    end
  else
    rows[#rows + 1] = { id = "search", icon = "󰂰", label = "Pair a new device…" }
  end
  rows[#rows + 1] = settings
  return rows
end

return bluetooth
