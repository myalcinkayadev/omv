-- Wi-Fi and Ethernet cards (click the bar icons, Option+Shift+W / E). Either runs macOS's
-- own speed test, networkQuality, which talks to Apple's test servers for about 15 seconds;
-- the card shows its readings as they come in.

local shell = require("shell")
local network = require("network")

local feature = {}

local WIFI_SETTINGS = "x-apple.systempreferences:com.apple.wifi-settings-extension"
local NETWORK_SETTINGS = "x-apple.systempreferences:com.apple.Network-Settings.extension"
-- Joining a network takes a moment after Wi-Fi turns on, so the card redraws again then.
local WIFI_JOIN_SECONDS = 4
local NETWORK_QUALITY = "/usr/bin/networkQuality"
-- networkQuality prints its live readings only to a terminal; script gives it one.
local SCRIPT = "/usr/bin/script"
-- The card redraws at most this often while a test runs.
local LIVE_SECONDS = 0.5

-- The last speed test: nil before one, { running = true } with live readings during it,
-- { down, up } after.
local speed = nil

local function ipv4(interface)
  for _, address in ipairs(hs.network.addresses(interface) or {}) do
    if address:match("^%d+%.%d+%.%d+%.%d+$") then return address end
  end
  return nil
end

-- route, networksetup and ifconfig run in the background: networksetup takes long enough to
-- freeze the cards, and refreshCards runs on each change of the signal.

local function routeFor(interface, done)
  local scope = interface and ("-ifscope " .. interface .. " ") or ""
  shell.execute("/sbin/route -n get " .. scope .. "default 2>/dev/null", function(output)
    done(network.parseRoute(output))
  end)
end

-- Hands done the Wi-Fi's state. The network name needs Location for Hammerspoon; without it
-- ssid is nil.
local function wifiInfo(done)
  local details = hs.wifi.interfaceDetails() or {}
  local interface = details.interface or "en0"
  local channel = details.wlanChannel or {}
  routeFor(interface, function(route)
    done({
      power = details.power == true,
      ssid = details.ssid,
      rssi = details.rssi,
      ip = ipv4(interface),
      router = route.gateway,
      channel = channel.number,
      band = channel.band,
    })
  end)
end

-- The Mac's wired ports, read once: networksetup is slow, and they change only with hardware.
local wiredPorts = nil

local function readWiredPorts(done)
  if wiredPorts then return done(wiredPorts) end
  shell.execute("/usr/sbin/networksetup -listallhardwareports", function(output)
    wiredPorts = network.wiredPorts(output)
    done(wiredPorts)
  end)
end

-- Hands done the first port of ports, from index on, that is active with an address,
-- preferring the one the default route leaves by.
local function activePort(ports, default, done, chosen, index)
  index = index or 1
  local port = ports[index]
  if not port then return done(chosen) end
  shell.execute("/sbin/ifconfig " .. port .. " 2>/dev/null", function(output)
    local media = network.parseMedia(output)
    local ip = ipv4(port)
    if media.active and ip and (not chosen or port == default) then
      chosen = { port = port, ip = ip, mbps = media.mbps, duplex = media.duplex }
    end
    activePort(ports, default, done, chosen, index + 1)
  end)
end

-- Hands done the wired port with an address, or nil without one.
local function ethernetInfo(done)
  routeFor(nil, function(route)
    readWiredPorts(function(ports)
      activePort(ports, route.interface, function(chosen)
        if not chosen then return done(nil) end
        routeFor(chosen.port, function(portRoute)
          chosen.router = portRoute.gateway
          done(chosen)
        end)
      end)
    end)
  end)
end

local onNetworkMessage

local function showWifi()
  wifiInfo(function(info)
    shell.show("wifi", shell.anchored(network.WIDTH, network.HEIGHT, "wifi"), network.html(network.wifiModel(info, speed)), onNetworkMessage,
      { onClose = function() feature.signalWatcher:stop() end })
    feature.signalWatcher:start()
  end)
end

local function showEthernet(info)
  shell.show("ethernet", shell.anchored(network.WIDTH, network.HEIGHT, "ethernet"), network.html(network.ethernetModel(info, speed)), onNetworkMessage)
end

local function redrawWifi()
  if shell.isOpen("wifi") then showWifi() end
  hs.task.new(shell.SKETCHYBAR, nil, { "--update" }):start()
end

local refreshCards

-- Runs in the background; the open card shows "Testing…", then the result.
local function speedTest()
  if speed and speed.running then return end
  local previous = speed
  speed = { running = true }
  refreshCards()
  local output, drawnAt = {}, 0
  local function streamed(_, chunk)
    output[#output + 1] = chunk
    local live = network.parseProgress(chunk)
    if live and hs.timer.secondsSinceEpoch() - drawnAt >= LIVE_SECONDS then
      speed = { running = true, down = live.down, up = live.up }
      drawnAt = hs.timer.secondsSinceEpoch()
      refreshCards()
    end
    return true
  end
  local function finished(_, rest)
    speed = network.parseSummary(table.concat(output) .. (rest or ""))
    if not speed then
      speed = previous
      shell.alert("Speed test failed", 1.5)
    end
    refreshCards()
  end
  -- Kept on the feature, so the running task isn't garbage-collected.
  feature.speedTask = hs.task.new(SCRIPT, finished, streamed, { "-q", "/dev/null", NETWORK_QUALITY })
  feature.speedTask:start()
end

onNetworkMessage = function(message)
  if message.type ~= "choose" then return shell.close() end
  if message.id == "network.speedtest" then return speedTest() end
  if message.id == "wifi.power" then
    hs.wifi.setPower(not ((hs.wifi.interfaceDetails() or {}).power == true))
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
  ethernetInfo(function(info)
    if not info then return shell.alert("No cable connected", 1.5) end
    showEthernet(info)
  end)
end

-- Wi-Fi and the cable are watched, not polled: a change redraws the bar's icons at once,
-- and the open card updates in place, keeping its selected button. The signal's strength
-- changes often, so it's watched only while the Wi-Fi card is open. Bursts wait 0.2s.
local networkChanged = hs.timer.delayed.new(0.2, function()
  hs.task.new(shell.SKETCHYBAR, nil, { "--trigger", "omv_network_change" }):start()
  refreshCards()
end)

-- The open card in place, keeping its selected button.
refreshCards = function()
  if shell.isOpen("wifi") then
    wifiInfo(function(info)
      if shell.isOpen("wifi") then shell.view():evaluateJavaScript(network.update(network.wifiModel(info, speed))) end
    end)
  end
  if shell.isOpen("ethernet") then
    ethernetInfo(function(info)
      if not shell.isOpen("ethernet") then return end
      if not info then
        shell.close()
        return shell.alert("Cable disconnected", 1.5)
      end
      shell.view():evaluateJavaScript(network.update(network.ethernetModel(info, speed)))
    end)
  end
end

local function changed() networkChanged:start() end

-- Kept on the feature, so they aren't garbage-collected.
feature.wifiWatcher = hs.wifi.watcher.new(changed):watchingFor({ "powerChange", "SSIDChange", "linkChange" }):start()
feature.signalWatcher = hs.wifi.watcher.new(function()
  if shell.isOpen("wifi") then changed() end
end):watchingFor({ "linkQualityChange" })
feature.cableWatcher = hs.network.configuration.open()
feature.cableWatcher:setCallback(changed)
feature.cableWatcher:monitorKeys({ "State:/Network/Interface/en[0-9]+/Link", "State:/Network/Global/IPv4" }, true)
feature.cableWatcher:start()

return feature
