-- Tailscale (a click on the bar's icon): connect or disconnect, and every device with its
-- address, Enter to copy it. The icon shows only once Tailscale is installed, white while
-- connected; its state is read every 30 seconds with Tailscale's own CLI.

local shell = require("shell")
local card = require("card")
local tailscale = require("tailscale")

local feature = {}

local CLIS = { "/opt/homebrew/bin/tailscale", "/Applications/Tailscale.app/Contents/MacOS/Tailscale" }
local CHECK_SECONDS = 30
local WIDTH = 480

local function cli()
  for _, path in ipairs(CLIS) do
    if hs.fs.attributes(path) then return path end
  end
  return nil
end

local function readStatus(done)
  local path = cli()
  if not path then return done(nil) end
  hs.task.new(path, function(_, output)
    local ok, data = pcall(hs.json.decode, output or "")
    done(tailscale.parseStatus(ok and data or nil))
  end, { "status", "--json" }):start()
end

-- Hidden while Tailscale isn't installed; white while connected, the theme's muted colour otherwise.
local function showOnBar(status)
  local arguments = { "--set", "tailscale", "drawing=" .. (status and "on" or "off") }
  if status then arguments[#arguments + 1] = "icon.color=" .. (status.connected and shell.WHITE or ("0xff" .. shell.themeTokens().muted:sub(2))) end
  hs.task.new(shell.SKETCHYBAR, nil, arguments):start()
end

local function refresh()
  readStatus(showOnBar)
end

local function run(arguments)
  hs.task.new(cli(), function() hs.timer.doAfter(1, refresh) end, arguments):start()
end

local function onMessage(message)
  shell.close()
  if message.type ~= "choose" then return end
  local address = tailscale.copied(message.id)
  if address then
    hs.pasteboard.setContents(address)
    return shell.alert("Copied " .. address, 1.2)
  end
  if message.id == "disconnect" then return run({ "down" }) end
  if message.id == "connect" then return run({ "up" }) end
  -- Logging in happens in the Tailscale app.
  shell.open({ "-a", "Tailscale" })()
end

function feature.toggle()
  if shell.isOpen("tailscale") then return shell.close() end
  readStatus(function(status)
    if not status then return shell.alert("Tailscale isn't installed", 1.5) end
    local screen = tailscale.screen(status)
    if status.state == "NeedsLogin" then screen.rows[1].id = "login" end
    shell.show("tailscale", shell.anchored(WIDTH, shell.menuHeight(screen), "tailscale"), card.html(screen), onMessage)
  end)
end

-- Kept on the feature, so it isn't garbage-collected.
feature.timer = hs.timer.doEvery(CHECK_SECONDS, refresh)
refresh()

return feature
