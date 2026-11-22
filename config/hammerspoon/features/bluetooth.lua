-- Bluetooth card (Option+Shift+Y, or a click on the bar's Bluetooth icon): turns Bluetooth
-- on or off, and connects or disconnects paired devices, connected ones first. It reads and
-- changes Bluetooth through blueutil (brew install blueutil); without it, the card says so.
-- The first time, macOS asks to let Hammerspoon use Bluetooth.
-- It also draws the bar's Bluetooth icon: only Hammerspoon has Bluetooth access, so the bar
-- can't read it itself.

local shell = require("shell")
local card = require("card")
local bluetooth = require("bluetooth")

local feature = {}

local BLUEUTIL = "/opt/homebrew/bin/blueutil"
local WIDTH = 420
local VISIBLE_ROWS = 14

-- Hands done blueutil's output. In the background: blueutil hangs while Bluetooth is slow.
local function blueutil(arguments, done)
  shell.execute(BLUEUTIL .. " " .. arguments .. " 2>/dev/null", function(output)
    if done then done(output) end
  end)
end

-- What the card shows while it's open: the search, a device's progress (busy), what failed,
-- and the row last chosen, which every redraw keeps selected. Cleared when the card closes.
local function freshSession()
  return { search = nil, busy = {}, connectFailed = {}, pairFailures = {}, selected = nil }
end
local session = freshSession()

local function paired(done)
  blueutil("--paired --format json", function(output)
    local ok, list = pcall(hs.json.decode, output)
    done(bluetooth.devices(ok and list or nil))
  end)
end

-- Hands done the power as readPower reads it: nil without blueutil or Bluetooth access.
local function readPower(done)
  if not hs.fs.attributes(BLUEUTIL) then return done(nil) end
  blueutil("--power", function(output) done(bluetooth.readPower(output)) end)
end

local function state(done)
  if not hs.fs.attributes(BLUEUTIL) then return done({ installed = false }) end
  readPower(function(power)
    if power == nil then return done({ installed = true, denied = true }) end
    local function withDevices(devices)
      done({ installed = true, power = power, devices = devices, search = session.search,
        busy = session.busy, connectFailed = session.connectFailed, pairFailures = session.pairFailures })
    end
    if not power then return withDevices({}) end
    paired(withDevices)
  end)
end

-- The bar's icon as last set, so an unchanged one isn't sent again.
local iconShown = nil

local function redrawIcon()
  readPower(function(power)
    local properties = bluetooth.barProperties(power)
    local key = table.concat(properties, "\n")
    if key == iconShown then return end
    iconShown = key
    local arguments = { "--set", "bluetooth" }
    for _, property in ipairs(properties) do arguments[#arguments + 1] = property end
    hs.task.new(shell.SKETCHYBAR, nil, arguments):start()
  end)
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
local searchTask = nil
local generation = 0

local function stopSearch()
  generation = generation + 1
  if searchTask and searchTask:isRunning() then searchTask:terminate() end
  searchTask = nil
end

local function searchRound()
  local mine = generation
  searchTask = hs.task.new(BLUEUTIL, function(_, output)
    if mine ~= generation then return end
    local ok, list = pcall(hs.json.decode, output or "")
    paired(function(devices)
      if mine ~= generation then return end
      session.search = bluetooth.searchStep(session.search, { type = "round", list = ok and list or nil, paired = devices })
      if session.search.searching then
        searchRound()
      else
        stopSearch()
      end
      redraw()
    end)
  end, { "--inquiry", tostring(bluetooth.SEARCH_SECONDS), "--format", "json" })
  searchTask:start()
end

local function startSearch()
  stopSearch()
  session.search = bluetooth.searchStep(nil, { type = "start" })
  session.pairFailures = {}
  redraw()
  searchRound()
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
    return blueutil("--power " .. (id == "power.on" and "1" or "0"), function()
      redrawIcon()
      redraw()
    end)
  end
  local address = id:match("^device:(.+)$")
  state(function(current)
    for _, device in ipairs(current.devices or {}) do
      if device.address == address then return toggleDevice(device) end
    end
  end)
end

local function onClose()
  stopSearch()
  session = freshSession()
end

-- Each section's header takes a row's height too.
local function linesOf(rows)
  local lines, previous = #rows, nil
  for _, row in ipairs(rows) do
    if row.group and row.group ~= previous then lines = lines + 1 end
    previous = row.group
  end
  return lines
end

show = function()
  state(function(current)
    local rows = bluetooth.rows(current)
    local screen = { prompt = "Bluetooth…", rows = rows, compact = true, selected = bluetooth.indexOf(rows, session.selected) }
    local height = shell.listHeight(linesOf(rows), VISIBLE_ROWS)
    shell.show("bluetooth", shell.anchored(WIDTH, height, "bluetooth"), card.html(screen), onMessage, { onClose = onClose })
  end)
end

function feature.toggle()
  if shell.isOpen("bluetooth") then return shell.close() end
  show()
end

-- A restarted bar has lost the icon, so it is sent again.
function feature.redrawBar()
  iconShown = nil
  redrawIcon()
end

-- Bluetooth can be turned on or off elsewhere, so the icon is read again each minute and
-- on wake. Kept on the feature, so they aren't garbage-collected.
local ICON_SECONDS = 60
feature.iconTimer = hs.timer.doEvery(ICON_SECONDS, redrawIcon)
feature.wakeWatcher = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then redrawIcon() end
end):start()
redrawIcon()

return feature
