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

-- What the card shows while it's open: the search, a device's progress (busy), what failed,
-- and the row last chosen, which every redraw keeps selected. Cleared when the card closes.
local function freshSession()
  return { search = nil, busy = {}, connectFailed = {}, pairFailures = {}, selected = nil }
end
local session = freshSession()

local function paired()
  local ok, list = pcall(hs.json.decode, blueutil("--paired --format json"))
  return bluetooth.devices(ok and list or nil)
end

local function state()
  if not hs.fs.attributes(BLUEUTIL) then return { installed = false } end
  local power = bluetooth.readPower(blueutil("--power"))
  if power == nil then return { installed = true, denied = true } end
  return { installed = true, power = power, devices = power and paired() or {}, search = session.search,
    busy = session.busy, connectFailed = session.connectFailed, pairFailures = session.pairFailures }
end

-- The bar's icon redraws on this event.
local function redrawIcon()
  hs.task.new(shell.SKETCHYBAR, nil, { "--trigger", "bluetooth_change" }):start()
end

local show

local function redraw()
  if shell.isOpen("bluetooth") then show() end
end

-- Pairing and connecting stop after LIMIT_SECONDS, so a device gone out of range never
-- leaves a row saying pairing… for good. done gets whether blueutil succeeded.
local LIMIT_SECONDS = 20
local running = {}

local function runLimited(arguments, done)
  local task, limit
  task = hs.task.new(BLUEUTIL, function(code)
    if limit then limit:stop() end
    running[task] = nil
    done(code == 0)
  end, arguments)
  limit = hs.timer.doAfter(LIMIT_SECONDS, function()
    if task:isRunning() then task:terminate() end
  end)
  running[task] = true
  task:start()
end

-- Connecting can take a few seconds, so it runs in the background, and the device's row
-- says connecting… or disconnecting… meanwhile.
local function toggleDevice(device)
  local action = bluetooth.action(device)
  if not bluetooth.command(action, device.address) or session.busy[device.address] then return end
  local address = device.address
  session.busy[address] = action == "connect" and "connecting" or "disconnecting"
  session.connectFailed[address] = nil
  redraw()
  runLimited({ "--" .. action, address }, function(ok)
    session.busy[address] = nil
    if not ok and action == "connect" then session.connectFailed[address] = true end
    redraw()
  end)
end

-- The search runs blueutil's inquiry once per round. A stopped search's late answer is
-- dropped: each search counts as a new generation.
local searchTask, tickTimer = nil, nil
local generation = 0

local function stopSearch()
  generation = generation + 1
  if searchTask and searchTask:isRunning() then searchTask:terminate() end
  searchTask = nil
  if tickTimer then tickTimer:stop() end
  tickTimer = nil
end

-- Counts the searching row down in place, rather than redrawing the card every second.
local function tick()
  session.search = bluetooth.searchStep(session.search, { type = "tick" })
  if not (session.search and session.search.searching) or not shell.isOpen("bluetooth") then return end
  shell.view():evaluateJavaScript("(function () { const label = document.querySelector('[data-id=\"searching\"] .label');"
    .. " if (label) label.textContent = " .. card.jsString(bluetooth.searchingLabel(session.search)) .. "; })()")
end

local function searchRound()
  local mine = generation
  searchTask = hs.task.new(BLUEUTIL, function(_, output)
    if mine ~= generation then return end
    local ok, list = pcall(hs.json.decode, output or "")
    session.search = bluetooth.searchStep(session.search, { type = "round", list = ok and list or nil, paired = paired() })
    if session.search.searching then
      searchRound()
    else
      stopSearch()
    end
    redraw()
  end, { "--inquiry", tostring(bluetooth.SEARCH_SECONDS), "--format", "json" })
  searchTask:start()
end

local function startSearch()
  stopSearch()
  session.search = bluetooth.searchStep(nil, { type = "start" })
  session.pairFailures = {}
  redraw()
  searchRound()
  tickTimer = hs.timer.doEvery(1, tick)
end

-- Pairs, then connects. The search stops first, since both use the radio. On success the
-- device's row among the paired ones is selected; a device that wants a PIN typed fails
-- here, and after a second failure the card points to Bluetooth Settings.
local function pair(address)
  if not bluetooth.command("pair", address) or session.busy[address] then return end
  stopSearch()
  session.search = bluetooth.searchStep(session.search, { type = "stop" })
  session.busy[address] = "pairing"
  redraw()
  runLimited({ "--pair", address }, function(ok)
    session.busy[address] = nil
    if not ok then
      session.pairFailures[address] = (session.pairFailures[address] or 0) + 1
      return redraw()
    end
    session.search = bluetooth.searchStep(session.search, { type = "paired", address = address })
    session.selected = "device:" .. address
    session.busy[address] = "connecting"
    redraw()
    runLimited({ "--connect", address }, function(connected)
      session.busy[address] = nil
      if not connected then session.connectFailed[address] = true end
      redraw()
    end)
  end)
end

local BLUETOOTH_PRIVACY = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
local BLUETOOTH_SETTINGS = "x-apple.systempreferences:com.apple.BluetoothSettings"
local SETTINGS_LINKS = { settings = BLUETOOTH_PRIVACY, ["settings.bluetooth"] = BLUETOOTH_SETTINGS,
  ["settings.le"] = BLUETOOTH_SETTINGS, ["settings.pair"] = BLUETOOTH_SETTINGS }
-- Rows that only say something.
local NOTES = { ["pairing-mode"] = true, none = true }

local function onMessage(message)
  if message.type ~= "choose" then return shell.close() end
  local id = message.id
  if NOTES[id] then return end
  session.selected = id
  if SETTINGS_LINKS[id] then
    shell.close()
    return shell.open({ SETTINGS_LINKS[id] })()
  end
  if id == "search" then return startSearch() end
  if id == "searching" then
    stopSearch()
    session.search = bluetooth.searchStep(session.search, { type = "stop" })
    return redraw()
  end
  local found = id:match("^pair:(.+)$")
  if found then return pair(found) end
  if id == "power.on" or id == "power.off" then
    stopSearch()
    session = freshSession()
    blueutil("--power " .. (id == "power.on" and "1" or "0"))
    redrawIcon()
    return show()
  end
  local address = id:match("^device:(.+)$")
  for _, device in ipairs(state().devices or {}) do
    if device.address == address then return toggleDevice(device) end
  end
end

local function onClose()
  stopSearch()
  session = freshSession()
end

show = function()
  local rows = bluetooth.rows(state())
  local screen = { prompt = "Bluetooth…", rows = rows, compact = true, selected = bluetooth.indexOf(rows, session.selected) }
  shell.show("bluetooth", shell.anchored(WIDTH, shell.listHeight(#rows, VISIBLE_ROWS), "bluetooth"), card.html(screen), onMessage,
    { onClose = onClose })
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
