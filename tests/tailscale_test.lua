-- Behavior of the Tailscale card: reading `tailscale status --json` and the card's rows.
-- Run through tailscale_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local tailscale = require("tailscale")

local answer = {
  BackendState = "Running",
  Self = { HostName = "mac", TailscaleIPs = { "100.64.0.1", "fd7a::1" }, Online = true },
  Peer = {
    a = { HostName = "zeta", DNSName = "zeta.tail.ts.net.", TailscaleIPs = { "100.64.0.9" }, Online = true, OS = "linux" },
    b = { HostName = "alpha", TailscaleIPs = { "100.64.0.2" }, Online = false, OS = "iOS" },
    c = { HostName = "beta", TailscaleIPs = { "100.64.0.3" }, Online = true, OS = "windows" },
  },
}
local status = tailscale.parseStatus(answer)

check.that("should read that Tailscale is connected", status.connected == true)
check.that("should read that Tailscale is stopped", tailscale.parseStatus({ BackendState = "Stopped" }).connected == false)
check.that("should read this Mac's Tailscale address", status.ip == "100.64.0.1")
check.that("should list every other device", #status.peers == 3)
check.that("should list online devices first, by name", status.peers[1].name == "beta" and status.peers[2].name == "zeta")
check.that("should list offline devices last", status.peers[3].name == "alpha" and status.peers[3].online == false)
check.that("should read a device's IPv4 address", status.peers[1].ip == "100.64.0.3")
check.that("should give nothing for an answer that isn't Tailscale's", tailscale.parseStatus(nil) == nil)
check.that("should list no devices when there are none", #tailscale.parseStatus({ BackendState = "Running" }).peers == 0)
check.that("should say login is needed", tailscale.parseStatus({ BackendState = "NeedsLogin" }).state == "NeedsLogin")

local function ids(screen)
  local result = {}
  for _, row in ipairs(screen.rows) do result[#result + 1] = row.id end
  return table.concat(result, ",")
end
local screen = tailscale.screen(status)
check.that("should offer to disconnect while connected", screen.rows[1].id == "disconnect")
check.that("should offer to connect while stopped", tailscale.screen(tailscale.parseStatus({ BackendState = "Stopped" })).rows[1].id == "connect")
check.that("should list the devices after the switch, to copy their address",
  ids(screen) == "disconnect,copy:100.64.0.3,copy:100.64.0.9,copy:100.64.0.2")
check.that("should show a device's address beside it", screen.rows[2].hint == "100.64.0.3")
check.that("should mark an offline device", screen.rows[4].label == "alpha (offline)")
check.that("should list no devices while stopped", #tailscale.screen(tailscale.parseStatus({ BackendState = "Stopped" })).rows == 1)
check.that("should read the address to copy from a row", tailscale.copied("copy:100.64.0.3") == "100.64.0.3")
check.that("should read no address from another row", tailscale.copied("connect") == nil)

check.finish()
