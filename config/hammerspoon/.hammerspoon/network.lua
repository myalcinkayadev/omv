-- The Wi-Fi and Ethernet cards, in the status-card layout of panel.lua. init.lua reads the
-- interfaces and passes plain tables in; this turns them into the card's HTML.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local panel = require("panel")

local network = {}

local DASH = "—"
local WEAKEST, STRONGEST = -90, -30

network.WIDTH = 420
network.HEIGHT = 324

local WIFI_SETTINGS = { id = "wifi.settings", icon = "󰒓", label = "Settings" }
local NETWORK_SETTINGS = { id = "network.settings", icon = "󰒓", label = "Settings" }

-- A speed in Mb/s as the card shows it, in Gb/s from 1000.
function network.rateLabel(mbps)
  if mbps < 1000 then return string.format("%d Mb/s", mbps) end
  return string.format("%.1f Gb/s", mbps / 1000)
end

local function mbps(text)
  local value = tonumber(text)
  return value and math.floor(value + 0.5) or nil
end

-- A chunk of networkQuality's live output, run in a terminal: the latest "Downlink: X Mbps,
-- … - Uplink: Y Mbps, …" line in it, as whole Mb/s. Upload is nil until its phase starts.
-- nil when the chunk holds no reading.
function network.parseProgress(chunk)
  local plain = tostring(chunk or ""):gsub("\27%[[%d;?]*%a", "")
  local latest = nil
  for down, up in plain:gmatch("Downlink:%s*([%d.]+)%s*Mbps.-Uplink:%s*([%d.]+)%s*Mbps") do
    latest = { down = mbps(down), up = (tonumber(up) or 0) > 0 and mbps(up) or nil }
  end
  return latest
end

-- The summary networkQuality prints at the end; nil until it has.
function network.parseSummary(text)
  local plain = tostring(text or "")
  local down = plain:match("Downlink capacity:%s*([%d.]+)%s*Mbps")
  local up = plain:match("Uplink capacity:%s*([%d.]+)%s*Mbps")
  if not down or not up then return nil end
  return { down = mbps(down), up = mbps(up) }
end

-- The speed test's grid row and button. speed is nil before a test, { running = true } with
-- any live down and up during one, and { down, up } after.
local function speedRow(speed)
  local function shown(value)
    if value then return network.rateLabel(value) end
    return (speed and speed.running) and "…" or "—"
  end
  return { "Download", shown(speed and speed.down) }, { "Upload", shown(speed and speed.up) }
end

local function speedButton(speed)
  local running = speed and speed.running
  return { id = "network.speedtest", icon = "󰓅", label = running and "Testing…" or "Speed test" }
end

local function orDash(value)
  if not value or value == "" then return DASH end
  return tostring(value)
end

-- macOS reports 0 dBm when there is no reading, so 0 counts as none.
function network.signalPercent(rssi)
  if not rssi or rssi == 0 then return 0 end
  local share = (rssi - WEAKEST) / (STRONGEST - WEAKEST)
  return math.floor(math.max(0, math.min(1, share)) * 100 + 0.5)
end

-- macOS names the 2.4 GHz band "2GHz".
local BAND_NAMES = { ["2GHz"] = "2.4GHz" }

local function hasName(info)
  return info.ssid ~= nil and info.ssid ~= ""
end

-- Without Location, macOS hides the network's name but not the address, so an address
-- also counts as connected; the name then shows as a dash.
local function isConnected(info)
  return info.power and (hasName(info) or (info.ip ~= nil and info.ip ~= "")) or false
end

local function wifiStatus(info)
  if not info.power then return "OFF" end
  if not isConnected(info) then return "NOT CONNECTED" end
  return hasName(info) and info.ssid:upper() or DASH
end

-- info = { power, ssid, rssi, ip, router, channel, band }; speed as for speedRow.
function network.wifiModel(info, speed)
  local connected = isConnected(info)
  local percent = connected and network.signalPercent(info.rssi) or 0
  local signal = connected and info.rssi and info.rssi ~= 0 and (info.rssi .. " dBm") or nil
  local band = info.band and (BAND_NAMES[info.band] or info.band)
  local channel = connected and info.channel and (info.channel .. (band and (" (" .. band .. ")") or "")) or nil
  local download, upload = speedRow(speed)
  local power = info.power and { id = "wifi.power", icon = "󰖪", label = "Turn off" }
    or { id = "wifi.power", icon = "󰖩", label = "Turn on" }
  return {
    icon = info.power and "󰖩" or "󰖪",
    title = "Wi-Fi",
    sub = wifiStatus(info),
    big = connected and (percent .. "%") or DASH,
    percent = percent,
    grid = {
      { "IP address", orDash(connected and info.ip) }, { "Signal", orDash(signal) },
      { "Router", orDash(connected and info.router) }, { "Channel", orDash(channel) },
      download, upload,
    },
    buttons = { power, speedButton(speed), WIFI_SETTINGS },
  }
end

function network.speedLabel(mbps)
  if not mbps then return DASH end
  if mbps < 1000 then return mbps .. " Mb/s" end
  local gigabits = mbps / 1000
  return (gigabits == math.floor(gigabits) and string.format("%d", gigabits) or tostring(gigabits)) .. " Gb/s"
end

-- info = { port, ip, router, mbps, duplex }; speed as for speedRow.
function network.ethernetModel(info, speed)
  local download, upload = speedRow(speed)
  return {
    icon = "󰈀",
    title = "Ethernet",
    sub = "CONNECTED",
    big = network.speedLabel(info.mbps),
    percent = 100,
    grid = {
      { "IP address", orDash(info.ip) }, { "Port", orDash(info.port) },
      { "Router", orDash(info.router) }, { "Duplex", orDash(info.duplex) },
      download, upload,
    },
    buttons = { speedButton(speed), NETWORK_SETTINGS },
  }
end

network.html = panel.html
network.update = panel.update

-- Reads `ifconfig <port>`: whether the link is up, its speed and duplex.
function network.parseMedia(text)
  local media = text:match("media:[^\n]*") or ""
  local speed = media:match("%((%d+)[Bb]ase")
  local duplex = media:match("<(%a+)%-duplex>")
  return {
    active = text:match("status:%s*active") ~= nil,
    mbps = speed and tonumber(speed) or nil,
    duplex = duplex,
  }
end

-- Reads `route -n get default`: the router and the interface the traffic leaves by.
function network.parseRoute(text)
  return { gateway = text:match("gateway:%s*(%S+)"), interface = text:match("interface:%s*(%S+)") }
end

local NOT_WIRED = { ["Wi-Fi"] = true, ["Bluetooth PAN"] = true, ["Thunderbolt Bridge"] = true }

-- Reads `networksetup -listallhardwareports`: the devices that can take a cable.
function network.wiredPorts(text)
  local ports = {}
  for name, device in text:gmatch("Hardware Port: ([^\n]+)\nDevice: (%S+)") do
    if not NOT_WIRED[name] then ports[#ports + 1] = device end
  end
  return ports
end

return network
