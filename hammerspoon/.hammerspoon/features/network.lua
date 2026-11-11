-- Wi-Fi and Ethernet cards (click the bar icons, Option+Shift+W / E).

local shell = require("shell")
local network = require("network")

local feature = {}

local WIFI_SETTINGS = "x-apple.systempreferences:com.apple.wifi-settings-extension"
local NETWORK_SETTINGS = "x-apple.systempreferences:com.apple.Network-Settings.extension"
-- Joining a network takes a moment after Wi-Fi turns on, so the card redraws again then.
local WIFI_JOIN_SECONDS = 4

local function ipv4(interface)
  for _, address in ipairs(hs.network.addresses(interface) or {}) do
    if address:match("^%d+%.%d+%.%d+%.%d+$") then return address end
  end
  return nil
end

local function routeFor(interface)
  local scope = interface and ("-ifscope " .. interface .. " ") or ""
  return network.parseRoute(hs.execute("/sbin/route -n get " .. scope .. "default 2>/dev/null"))
end

-- The network name needs Location for Hammerspoon; without it ssid is nil.
local function wifiInfo()
  local details = hs.wifi.interfaceDetails() or {}
  local interface = details.interface or "en0"
  local channel = details.wlanChannel or {}
  return {
    power = details.power == true,
    ssid = details.ssid,
    rssi = details.rssi,
    ip = ipv4(interface),
    router = routeFor(interface).gateway,
    channel = channel.number,
    band = channel.band,
  }
end

-- The wired port with an address, preferring the one the default route leaves by.
local function ethernetInfo()
  local default = routeFor(nil).interface
  local chosen = nil
  for _, port in ipairs(network.wiredPorts(hs.execute("/usr/sbin/networksetup -listallhardwareports"))) do
    local media = network.parseMedia(hs.execute("/sbin/ifconfig " .. port .. " 2>/dev/null"))
    local ip = ipv4(port)
    if media.active and ip and (not chosen or port == default) then
      chosen = { port = port, ip = ip, mbps = media.mbps, duplex = media.duplex }
    end
  end
  if chosen then chosen.router = routeFor(chosen.port).gateway end
  return chosen
end

local onNetworkMessage

local function showWifi()
  shell.show("wifi", shell.anchored(network.WIDTH, network.HEIGHT), network.html(network.wifiModel(wifiInfo())), onNetworkMessage)
end

local function showEthernet(info)
  shell.show("ethernet", shell.anchored(network.WIDTH, network.HEIGHT), network.html(network.ethernetModel(info)), onNetworkMessage)
end

local function redrawWifi()
  if shell.isOpen("wifi") then showWifi() end
  hs.task.new(shell.SKETCHYBAR, nil, { "--update" }):start()
end

onNetworkMessage = function(message)
  if message.type ~= "choose" then return shell.close() end
  if message.id == "wifi.power" then
    hs.wifi.setPower(not wifiInfo().power)
    redrawWifi()
    hs.timer.doAfter(WIFI_JOIN_SECONDS, redrawWifi)
    return
  end
  local url = message.id == "wifi.settings" and WIFI_SETTINGS or NETWORK_SETTINGS
  shell.close()
  shell.open({ url })()
end

function feature.toggleWifi()
  if shell.isOpen("wifi") then return shell.close() end
  showWifi()
end

function feature.toggleEthernet()
  if shell.isOpen("ethernet") then return shell.close() end
  local info = ethernetInfo()
  if not info then return shell.alert("No cable connected", 1.5) end
  showEthernet(info)
end

return feature
