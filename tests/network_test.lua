-- Behavior of the Wi-Fi and Ethernet cards. Run through network_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local network = require("network")

local DASH = "—"

check.that("should give 0% when the signal is at -90 dBm", network.signalPercent(-90) == 0)
check.that("should give 0% when the signal is weaker than -90 dBm", network.signalPercent(-97) == 0)
check.that("should give 100% when the signal is at -30 dBm", network.signalPercent(-30) == 100)
check.that("should give 100% when the signal is stronger than -30 dBm", network.signalPercent(-20) == 100)
check.that("should give 50% when the signal is at -60 dBm", network.signalPercent(-60) == 50)
check.that("should give 0% when there is no signal reading", network.signalPercent(nil) == 0)
check.that("should give 0% when the signal reads 0", network.signalPercent(0) == 0)

local connected = network.html(network.wifiModel({
  power = true, ssid = "Home-5G", rssi = -58, ip = "192.168.1.24", router = "192.168.1.1", channel = 36, band = "5GHz",
}))
local visible = check.visible(connected)
check.that("should show the network name uppercased when connected", check.contains(visible, "HOME-5G"))
check.that("should show the signal as a big percentage when connected", check.contains(visible, "53%"))
check.that("should show the signal in dBm when connected", check.contains(visible, "-58 dBm"))
check.that("should show the IP address when connected", check.contains(visible, "192.168.1.24"))
check.that("should show the router when connected", check.contains(visible, "192.168.1.1"))
check.that("should show the channel with its band when connected", check.contains(visible, "36 (5GHz)"))
check.that("should offer to turn Wi-Fi off when it is on", check.contains(visible, "Turn off"))
check.that("should offer Wi-Fi settings on the Wi-Fi card", check.contains(visible, "Wi-Fi settings"))
check.that("should give the settings button its id on the Wi-Fi card", check.contains(connected, 'data-id="wifi.settings"'))
check.that("should give the power button its id on the Wi-Fi card", check.contains(connected, 'data-id="wifi.power"'))

local searching = network.html(network.wifiModel({ power = true }))
check.that("should say not connected when Wi-Fi is on without a network", check.contains(check.visible(searching), "NOT CONNECTED"))
check.that("should show an empty bar when Wi-Fi is on without a network", check.contains(searching, "width: 0%"))
check.that("should show dashes for missing values when Wi-Fi is on without a network",
  select(2, check.visible(searching):gsub(DASH, "")) >= 4)

check.that("should show the 2.4 GHz band by its full name",
  check.contains(check.visible(network.html(network.wifiModel({ power = true, ssid = "x", channel = 6, band = "2GHz" }))), "6 (2.4GHz)"))

local hidden = check.visible(network.html(network.wifiModel({ power = true, rssi = -58, ip = "192.168.1.24", router = "192.168.1.1" })))
check.that("should show the signal when Location is refused while connected", check.contains(hidden, "53%"))
check.that("should show the IP address when Location is refused while connected", check.contains(hidden, "192.168.1.24"))
check.that("should not say not connected when Location is refused while connected", not check.contains(hidden, "NOT CONNECTED"))

local off = check.visible(network.html(network.wifiModel({ power = false })))
check.that("should say off when Wi-Fi power is off", check.contains(off, "OFF"))
check.that("should offer to turn Wi-Fi on when it is off", check.contains(off, "Turn on"))

check.that("should escape HTML when the network name has markup",
  check.contains(network.html(network.wifiModel({ power = true, ssid = "<b>&" })), "&lt;B&gt;&amp;"))

local wired = network.html(network.ethernetModel({ port = "en5", ip = "192.168.1.31", router = "192.168.1.1", mbps = 1000, duplex = "full" }))
local wiredText = check.visible(wired)
check.that("should show the link speed on the Ethernet card", check.contains(wiredText, "1 Gb/s"))
check.that("should show the port on the Ethernet card", check.contains(wiredText, "en5"))
check.that("should show the duplex on the Ethernet card", check.contains(wiredText, "full"))
check.that("should say connected on the Ethernet card", check.contains(wiredText, "CONNECTED"))
check.that("should offer Network settings on the Ethernet card", check.contains(wiredText, "Network settings"))
check.that("should give the settings button its id on the Ethernet card", check.contains(wired, 'data-id="network.settings"'))

check.that("should label 1000 Mb/s as 1 Gb/s", network.speedLabel(1000) == "1 Gb/s")
check.that("should label 2500 Mb/s as 2.5 Gb/s", network.speedLabel(2500) == "2.5 Gb/s")
check.that("should label 10000 Mb/s as 10 Gb/s", network.speedLabel(10000) == "10 Gb/s")
check.that("should label 100 Mb/s in Mb/s", network.speedLabel(100) == "100 Mb/s")
check.that("should label an unknown speed with a dash", network.speedLabel(nil) == DASH)

local active = network.parseMedia([[
en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	ether 00:e0:4c:68:01:02
	inet 192.168.1.31 netmask 0xffffff00 broadcast 192.168.1.255
	media: autoselect (1000baseT <full-duplex>)
	status: active
]])
check.that("should read an active link as active", active.active == true)
check.that("should read 1000baseT as 1000 Mb/s", active.mbps == 1000)
check.that("should read full-duplex as full", active.duplex == "full")
check.that("should read 2500Base-T as 2500 Mb/s",
  network.parseMedia("\tmedia: autoselect (2500Base-T <full-duplex>)\n\tstatus: active\n").mbps == 2500)
check.that("should read half-duplex as half",
  network.parseMedia("\tmedia: autoselect (100baseTX <half-duplex>)\n\tstatus: active\n").duplex == "half")
check.that("should read an unplugged port as not active",
  network.parseMedia("\tmedia: autoselect (none)\n\tstatus: inactive\n").active == false)

local ports = network.wiredPorts([[
Hardware Port: Wi-Fi
Device: en0
Ethernet Address: aa:bb:cc:dd:ee:ff

Hardware Port: Thunderbolt Bridge
Device: bridge0
Ethernet Address: N/A

Hardware Port: Bluetooth PAN
Device: en7
Ethernet Address: aa:bb:cc:dd:ee:00

Hardware Port: USB 10/100/1000 LAN
Device: en5
Ethernet Address: 00:e0:4c:68:01:02
]])
check.that("should list a USB LAN port as wired", #ports == 1 and ports[1] == "en5")
check.that("should list no wired ports when there is only Wi-Fi",
  #network.wiredPorts("Hardware Port: Wi-Fi\nDevice: en0\n") == 0)

local route = network.parseRoute([[
   route to: default
destination: default
       mask: default
    gateway: 192.168.1.1
  interface: en5
      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
]])
check.that("should read the gateway from route", route.gateway == "192.168.1.1")
check.that("should read the interface from route", route.interface == "en5")
check.that("should read nothing when there is no default route", network.parseRoute("route: writing to routing socket: not in table\n").gateway == nil)

-- The open card updates in place: only its changing part is sent, so the selected button stays.
local panel = require("panel")
local card = require("card")
local liveModel = network.wifiModel({ power = true, ssid = "home", rssi = -58, ip = "192.168.1.24" })
check.that("should mark the part of the card that changes", check.contains(network.html(liveModel), "<div class=data>"))
check.that("should render the changing part on its own, as the full card shows it",
  check.contains(network.html(liveModel), panel.data(liveModel)))
local update = network.update(liveModel)
check.that("should update the card from the same changing part", check.contains(update, card.jsString(panel.data(liveModel))))
check.that("should update the buttons' labels too", check.contains(update, card.jsString(panel.buttonsRow(liveModel.buttons))))
check.that("should keep the buttons' section outside the changing part", not check.contains(panel.data(liveModel), "class=btns"))
check.that("should make a JavaScript string that survives quotes and new lines",
  card.jsString('a"b\\c\nd</script>') == '"a\\"b\\\\c\\nd<\\/script>"')

check.finish()
