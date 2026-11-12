-- The Tailscale card: `tailscale status --json` read into this Mac's state and its devices,
-- and the card's rows: connect or disconnect, then each device, to copy its address.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local tailscale = {}

local function ipv4(addresses)
  for _, address in ipairs(type(addresses) == "table" and addresses or {}) do
    if address:match("^%d+%.%d+%.%d+%.%d+$") then return address end
  end
  return nil
end

-- { state, connected, ip, peers = { { name, ip, online, os } } }, online devices first; nil
-- for an answer that isn't Tailscale's.
function tailscale.parseStatus(data)
  if type(data) ~= "table" or type(data.BackendState) ~= "string" then return nil end
  local peers = {}
  for _, peer in pairs(type(data.Peer) == "table" and data.Peer or {}) do
    peers[#peers + 1] = { name = peer.HostName or "?", ip = ipv4(peer.TailscaleIPs), online = peer.Online == true, os = peer.OS }
  end
  table.sort(peers, function(a, b)
    if a.online ~= b.online then return a.online end
    return a.name:lower() < b.name:lower()
  end)
  return {
    state = data.BackendState,
    connected = data.BackendState == "Running",
    ip = ipv4(type(data.Self) == "table" and data.Self.TailscaleIPs),
    peers = peers,
  }
end

function tailscale.screen(status)
  local rows = {}
  if status.connected then
    rows[1] = { id = "disconnect", icon = "󰖂", label = "Disconnect", hint = status.ip }
    for _, peer in ipairs(status.peers) do
      if peer.ip then
        rows[#rows + 1] = { id = "copy:" .. peer.ip, icon = "󰍹", label = peer.name .. (peer.online and "" or " (offline)"), hint = peer.ip }
      end
    end
  else
    rows[1] = { id = "connect", icon = "󰖂", label = status.state == "NeedsLogin" and "Log in" or "Connect" }
  end
  return { prompt = "Tailscale…", rows = rows }
end

function tailscale.copied(id)
  return id:match("^copy:(.+)$")
end

return tailscale
