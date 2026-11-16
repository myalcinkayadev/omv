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

-- The search for devices to pair keeps going while the card is open, as phones and
-- computers do, in rounds of SEARCH_SECONDS: blueutil reports a round's finds only when it
-- ends, and they're listed then. It stops after SEARCH_ROUNDS, 2 minutes in all.
-- search is nil before any search, else { searching, round, found }. Events: start,
-- round (one ended, with blueutil's list), stop, and paired (a found device was paired,
-- so it leaves the list).
bluetooth.SEARCH_SECONDS = 10
bluetooth.SEARCH_ROUNDS = 12

local function withFound(found, more)
  local known, merged = {}, {}
  for _, device in ipairs(found) do
    known[device.address] = true
    merged[#merged + 1] = device
  end
  for _, device in ipairs(more) do
    if not known[device.address] then merged[#merged + 1] = device end
  end
  return merged
end

local function without(found, address)
  local kept = {}
  for _, device in ipairs(found) do
    if device.address ~= address then kept[#kept + 1] = device end
  end
  return kept
end

function bluetooth.searchStep(search, event)
  if event.type == "start" then
    return { searching = true, round = 1, found = {} }
  end
  if not search then return nil end
  if event.type == "stop" then return { searching = false, found = search.found } end
  if event.type == "paired" then
    return { searching = search.searching, round = search.round, found = without(search.found, event.address) }
  end
  if not search.searching or event.type ~= "round" then return search end
  local found = withFound(search.found, bluetooth.found(event.list, event.paired))
  if search.round >= bluetooth.SEARCH_ROUNDS then return { searching = false, found = found } end
  return { searching = true, round = search.round + 1, found = found }
end

-- The 1-based place of the row with this id among the rows that can be picked, so a
-- redraw keeps the selection; 1 when gone. Notes aren't counted: the card skips them.
function bluetooth.indexOf(rows, id)
  local index = 0
  for _, row in ipairs(rows) do
    if not row.note then
      index = index + 1
      if row.id == id then return index end
    end
  end
  return 1
end

local MINE, NEARBY = "My devices", "Nearby"

local PROGRESS = { pairing = "pairing…", connecting = "connecting…", disconnecting = "disconnecting…" }

local function deviceRow(device, state)
  local busy = (state.busy or {})[device.address]
  local hint = PROGRESS[busy]
    or ((state.connectFailed or {})[device.address] and "couldn't connect")
    or (device.connected and "connected" or "")
  return { id = "device:" .. device.address, icon = device.connected and "󰂱" or "󰂯", label = device.name, hint = hint, group = MINE }
end

-- A found device's row; a failed pairing says so, and a second one points to Settings,
-- since a device that wants a PIN typed only pairs there.
local function foundRows(device, state, rows)
  local failures = (state.pairFailures or {})[device.address] or 0
  local busy = (state.busy or {})[device.address]
  local row = { id = "pair:" .. device.address, icon = "󰂰", label = device.name, hint = "Enter pairs", group = NEARBY }
  if busy then
    row.hint = PROGRESS[busy]
  elseif failures > 0 then
    row.label, row.hint = "Couldn't pair " .. device.name, "Enter retries"
  end
  rows[#rows + 1] = row
  if failures > 1 and not busy then
    rows[#rows + 1] = { id = "settings.pair", icon = "󰒓", label = "A device that asks for a PIN pairs in Bluetooth Settings", group = NEARBY }
  end
end

local function searchRows(state, rows)
  local search = state.search
  if not search then
    rows[#rows + 1] = { id = "search", icon = "󰂰", label = "Pair a new device…", group = NEARBY }
    return
  end
  if search.searching then
    rows[#rows + 1] = { id = "searching", icon = "󰑐", label = "Searching…", hint = "Enter stops", group = NEARBY }
    rows[#rows + 1] = { id = "pairing-mode", icon = "󰋼", label = "Put the device in pairing mode", note = true, group = NEARBY }
  end
  for _, device in ipairs(search.found) do foundRows(device, state, rows) end
  if search.searching then return end
  if #search.found == 0 then
    rows[#rows + 1] = { id = "none", icon = "󰂲", label = "No devices found", note = true, group = NEARBY }
    rows[#rows + 1] = { id = "search", icon = "󰂰", label = "Search again", group = NEARBY }
    rows[#rows + 1] = { id = "settings.le", icon = "󰒓", label = "Keyboards and mice often need Bluetooth Settings", group = NEARBY }
    return
  end
  rows[#rows + 1] = { id = "search", icon = "󰂰", label = "Search again", group = NEARBY }
end

-- Card rows: the power switch, each paired device, the search, then Bluetooth Settings.
-- Without blueutil, or without Bluetooth access for Hammerspoon, one row says what's needed.
-- state.busy maps an address to pairing, connecting or disconnecting while that runs;
-- state.connectFailed and state.pairFailures remember what failed while the card is open.
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
  for _, device in ipairs(state.devices or {}) do rows[#rows + 1] = deviceRow(device, state) end
  searchRows(state, rows)
  rows[#rows + 1] = settings
  return rows
end

return bluetooth
