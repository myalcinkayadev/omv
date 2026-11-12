-- Behavior of the Bluetooth card: reading blueutil, ordering devices, and what Enter does.
-- Run through bluetooth_test.sh with luajit. blueutil's JSON comes as hs.json.decode gives it.

local check = dofile(arg[1] .. "/tests/check.lua")
local bluetooth = require("bluetooth")

local paired = {
  { address = "aa-bb-cc-dd-ee-01", name = "Magic Keyboard", connected = false, paired = true },
  { address = "aa-bb-cc-dd-ee-02", name = "AirPods Pro", connected = true, paired = true },
  { address = "aa-bb-cc-dd-ee-03", name = "", connected = false, paired = true },
}
local devices = bluetooth.devices(paired)
check.that("should read paired devices from blueutil's JSON", #devices == 3 and devices[1].address ~= nil)
check.that("should list connected devices first", devices[1].name == "AirPods Pro")
check.that("should name a device without a name by its address", devices[3].name == "aa-bb-cc-dd-ee-03")
check.that("should read no devices from output that isn't a list", #bluetooth.devices({ error = "x" }) == 0)

check.that("should offer Disconnect for a connected device", bluetooth.action(devices[1]) == "disconnect")
check.that("should offer Connect for a disconnected one", bluetooth.action(devices[2]) == "connect")
check.that("should build the command for a plain address", bluetooth.command("connect", "aa-bb-cc-dd-ee-01") == "--connect aa-bb-cc-dd-ee-01")
check.that("should refuse an address that isn't plain", bluetooth.command("connect", "aa; rm -rf ~") == nil)

local on = bluetooth.rows({ installed = true, power = true, devices = devices })
check.that("should offer to turn Bluetooth off first", on[1].id == "power.off")
check.that("should list each device after the switch", #on == 6 and on[2].id == "device:aa-bb-cc-dd-ee-02")
check.that("should hint a connected device as connected", on[2].hint == "connected")
local off = bluetooth.rows({ installed = true, power = false, devices = devices })
check.that("should show only the power switch and Settings while Bluetooth is off", #off == 2 and off[1].id == "power.on")
local missing = bluetooth.rows({ installed = false })
check.that("should say to install blueutil when it's missing", #missing == 1 and missing[1].label:find("brew install blueutil", 1, true) ~= nil)

-- blueutil aborts when the app running it has no Bluetooth access.
local REFUSED = "Error: Received abort signal, it may be due to absence of access to Bluetooth API, check that current terminal application has access in System Settings > Privacy & Security > Bluetooth"
check.that("should read power 1 as on", bluetooth.readPower("1\n") == true)
check.that("should read power 0 as off", bluetooth.readPower("0\n") == false)
check.that("should read a refusal as no access", bluetooth.readPower(REFUSED) == nil)
local refused = bluetooth.rows({ installed = true, denied = true })
check.that("should say to allow Bluetooth for Hammerspoon when blueutil is refused",
  #refused == 1 and refused[1].label:find("Allow Bluetooth for Hammerspoon", 1, true) ~= nil)

-- Pairing: a 10-second search for devices in range, then Enter pairs one.
local inquiry = {
  { address = "aa-bb-cc-dd-ee-02", name = "AirPods Pro", connected = false },
  { address = "11-22-33-44-55-66", name = "JBL Flip 6", connected = false },
  { address = "11-22-33-44-55-77", name = "", connected = false },
}
local found = bluetooth.found(inquiry, devices)
local function foundNamed(name)
  for _, device in ipairs(found) do if device.name == name then return device end end
end
check.that("should read devices found by the search from blueutil's JSON", #found == 2 and foundNamed("JBL Flip 6") ~= nil)
check.that("should leave out devices that are already paired", found[1].name ~= "AirPods Pro" and found[2].name ~= "AirPods Pro")
check.that("should name a found device without a name by its address", foundNamed("11-22-33-44-55-77") ~= nil)
check.that("should find nothing in output that isn't a list", #bluetooth.found({ error = "x" }, devices) == 0)

local function ids(rows)
  local list = {}
  for _, row in ipairs(rows) do list[#list + 1] = row.id end
  return table.concat(list, ",")
end
local function rowWith(rows, id)
  for _, row in ipairs(rows) do if row.id == id then return row end end
end
local function onWith(extra)
  local state = { installed = true, power = true, devices = devices }
  for key, value in pairs(extra) do state[key] = value end
  return bluetooth.rows(state)
end
local JBL, AIRPODS, KEYBOARD = "11-22-33-44-55-66", "aa-bb-cc-dd-ee-02", "aa-bb-cc-dd-ee-01"

local idle = onWith({})
check.that("should offer Pair a new device after the paired devices", idle[#idle - 1].id == "search")
check.that("should offer Bluetooth Settings as the last row", idle[#idle].id == "settings.bluetooth")
check.that("should offer Bluetooth Settings while Bluetooth is off",
  ids(bluetooth.rows({ installed = true, power = false })) == "power.on,settings.bluetooth")
check.that("should build the pair command only for a plain address",
  bluetooth.command("pair", JBL) == "--pair " .. JBL and bluetooth.command("pair", "x y") == nil)

-- The search: rounds of 10 seconds, at most three, driven here by fake events.
local started = bluetooth.searchStep(nil, { type = "start" })
local searching = onWith({ search = started })
check.that("should show a Searching row while searching", rowWith(searching, "searching").label == "Searching…")
check.that("should hint to put the device in pairing mode while searching", rowWith(searching, "pairing-mode") ~= nil)
check.that("should offer to stop the search on the searching row", rowWith(searching, "searching").hint == "Enter stops")
check.that("should stop the search when asked", bluetooth.searchStep(started, { type = "stop" }).searching == false)
check.that("should mark the pairing-mode hint as a note", rowWith(searching, "pairing-mode").note == true)

local firstRound = bluetooth.searchStep(started, { type = "round", list = inquiry, paired = devices })
check.that("should keep searching after a round that found a device", firstRound.searching and firstRound.round == 2)
check.that("should list devices found while later rounds keep searching", rowWith(onWith({ search = firstRound }), "pair:" .. JBL) ~= nil)
local secondRound = bluetooth.searchStep(firstRound, { type = "round", list = {}, paired = devices })
check.that("should keep a device found in an earlier round", rowWith(onWith({ search = secondRound }), "pair:" .. JBL) ~= nil)
local found = bluetooth.searchStep(firstRound, { type = "paired", address = JBL })
check.that("should drop a device from the found list once it's paired", rowWith(onWith({ search = found }), "pair:" .. JBL) == nil)

local empty = started
empty = bluetooth.searchStep(empty, { type = "round", list = {}, paired = devices })
check.that("should keep searching after a round without finds", empty.searching == true)
for _ = 2, 9 do empty = bluetooth.searchStep(empty, { type = "round", list = {}, paired = devices }) end
check.that("should still search after a minute and a half", empty.searching == true)
for _ = 10, 12 do empty = bluetooth.searchStep(empty, { type = "round", list = {}, paired = devices }) end
check.that("should stop searching after 2 minutes of 10-second rounds", empty.searching == false)
local nothing = onWith({ search = empty })
check.that("should say no devices were found after the last round", rowWith(nothing, "none").label == "No devices found")
check.that("should mark No devices found as a note", rowWith(nothing, "none").note == true)
check.that("should group paired devices under My devices", rowWith(idle, "device:" .. AIRPODS).group == "My devices")
check.that("should group found devices under Nearby", rowWith(onWith({ search = firstRound }), "pair:" .. JBL).group == "Nearby")
check.that("should group the search under Nearby", rowWith(searching, "searching").group == "Nearby")
check.that("should offer Search again when nothing was found", rowWith(nothing, "search").label == "Search again")
check.that("should point keyboards and mice to Bluetooth Settings when nothing was found", rowWith(nothing, "settings.le") ~= nil)

-- Progress and failures, shown on the row they belong to.
check.that("should show pairing… on the row being paired",
  rowWith(onWith({ search = firstRound, busy = { [JBL] = "pairing" } }), "pair:" .. JBL).hint == "pairing…")
check.that("should show connecting… on a device being connected",
  rowWith(onWith({ busy = { [KEYBOARD] = "connecting" } }), "device:" .. KEYBOARD).hint == "connecting…")
check.that("should show disconnecting… on a device being disconnected",
  rowWith(onWith({ busy = { [AIRPODS] = "disconnecting" } }), "device:" .. AIRPODS).hint == "disconnecting…")
check.that("should show connected once a device connects", rowWith(idle, "device:" .. AIRPODS).hint == "connected")
check.that("should show couldn't connect on a device that failed to connect",
  rowWith(onWith({ connectFailed = { [KEYBOARD] = true } }), "device:" .. KEYBOARD).hint == "couldn't connect")
local failedOnce = onWith({ search = firstRound, pairFailures = { [JBL] = 1 } })
check.that("should name the device that couldn't be paired", rowWith(failedOnce, "pair:" .. JBL).label == "Couldn't pair JBL Flip 6")
check.that("should offer a retry after a failed pairing", rowWith(failedOnce, "pair:" .. JBL).hint == "Enter retries")
check.that("should leave out the Settings hint after one failed pairing", rowWith(failedOnce, "settings.pair") == nil)
check.that("should add the Settings row after a second failed pairing",
  rowWith(onWith({ search = firstRound, pairFailures = { [JBL] = 2 } }), "settings.pair") ~= nil)

-- The selection follows a row's id across redraws.
check.that("should keep the selected row across a redraw", bluetooth.indexOf(idle, "search") == #idle - 1)
check.that("should select the first row when the selected one is gone", bluetooth.indexOf(idle, "pair:" .. JBL) == 1)
check.that("should select a newly paired device", bluetooth.indexOf(idle, "device:" .. KEYBOARD) == 3)
check.that("should count only rows that can be picked when finding the selected row",
  bluetooth.indexOf({ { id = "a" }, { id = "tip", note = true }, { id = "b" } }, "b") == 2)

check.finish()
