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
local idle = bluetooth.rows({ installed = true, power = true, devices = devices })
check.that("should offer Pair a new device after the paired devices", idle[#idle - 1].id == "search")
check.that("should offer Bluetooth Settings as the last row", idle[#idle].id == "settings.bluetooth")
check.that("should offer Bluetooth Settings while Bluetooth is off",
  ids(bluetooth.rows({ installed = true, power = false })) == "power.on,settings.bluetooth")
local searching = bluetooth.rows({ installed = true, power = true, devices = devices, searching = true })
check.that("should show Searching while a search runs", searching[#searching - 1].id == "searching")
local results = bluetooth.rows({ installed = true, power = true, devices = devices, found = found })
local jbl
for _, row in ipairs(results) do if row.id == "pair:11-22-33-44-55-66" then jbl = row end end
check.that("should list the devices found, to pair", jbl ~= nil and jbl.label == "JBL Flip 6")
local nothing = bluetooth.rows({ installed = true, power = true, devices = devices, found = {} })
check.that("should say when the search found nothing new", nothing[#nothing - 1].label:find("Nothing new found", 1, true) ~= nil)
check.that("should build the pair command only for a plain address",
  bluetooth.command("pair", "11-22-33-44-55-66") == "--pair 11-22-33-44-55-66" and bluetooth.command("pair", "x y") == nil)
local failed = bluetooth.rows({ installed = true, power = true, devices = devices, failed = "JBL Flip 6" })
check.that("should say to use Bluetooth Settings when pairing fails",
  failed[2].id == "settings.bluetooth" and failed[2].label:find("JBL Flip 6", 1, true) ~= nil)

check.finish()
