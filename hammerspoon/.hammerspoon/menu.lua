-- The Option+Escape system menu, as data. init.lua shows each screen with card.lua and
-- runs the picked action. Has no Hammerspoon dependency, so the Lua tests can run it.

local menu = {}

local SCREENS = {
  system = {
    prompt = "System…",
    rows = {
      { id = "lock", icon = "󰌾", label = "Lock" },
      { id = "screensaver", icon = "󱄄", label = "Screensaver" },
      { id = "sleep", icon = "󰒲", label = "Sleep" },
      { id = "logout", icon = "󰍃", label = "Log out" },
      { id = "restart", icon = "󰜉", label = "Restart" },
      { id = "shutdown", icon = "󰐥", label = "Shut down" },
      { id = "sound", icon = "󰕾", label = "Sound", submenu = true },
      { id = "reload", icon = "󰑐", label = "Reload", submenu = true },
    },
  },
  reload = {
    prompt = "Reload…",
    rows = {
      { id = "reload.aerospace", icon = "󰑐", label = "AeroSpace" },
      { id = "reload.sketchybar", icon = "󰑐", label = "SketchyBar" },
      { id = "reload.hammerspoon", icon = "󰑐", label = "Hammerspoon" },
      { id = "reload.all", icon = "󰑐", label = "Everything" },
    },
  },
}

-- These close every app, so one stray Enter must not run them.
local CONFIRMED = { logout = "Log out", restart = "Restart", shutdown = "Shut down" }
local CONFIRMED_ICONS = { logout = "󰍃", restart = "󰜉", shutdown = "󰐥" }

function menu.screen(id)
  return SCREENS[id]
end

-- Whether a picked id opens another screen, either fixed or built when it opens.
function menu.opens(id)
  return SCREENS[id] ~= nil or id == "sound"
end

local HEADPHONE_NAMES = { "airpods", "headphone", "headset", "beats", "buds" }

-- Headphones by name first, since AirPods and a Bluetooth speaker share a transport.
local function soundIcon(device)
  local name = device.name:lower()
  for _, word in ipairs(HEADPHONE_NAMES) do
    if name:find(word, 1, true) then return "󰋋" end
  end
  local transport = device.transport or ""
  if transport == "HDMI" or transport == "DisplayPort" or transport == "Thunderbolt" then return "󰍹" end
  if transport == "AirPlay" then return "󰄘" end
  if transport:find("Bluetooth", 1, true) then return "󰋋" end
  return "󰓃"
end

-- devices = { { uid, name, transport, current } }, as init.lua reads them from hs.audiodevice.
-- Virtual devices, such as the ones Zoom and Teams add, are left out unless in use.
function menu.sound(devices)
  local rows, selected = {}, 1
  for _, device in ipairs(devices) do
    if device.transport ~= "Virtual" or device.current then
      rows[#rows + 1] = {
        id = "sound." .. device.uid,
        icon = soundIcon(device),
        label = device.name,
        hint = device.current and "current" or nil,
      }
      if device.current then selected = #rows end
    end
  end
  -- Wider than the other menus, so a name like "MacBook Pro Speakers" fits beside "current".
  return { prompt = "Sound…", rows = rows, selected = selected, hint = "No output devices", width = 420 }
end

function menu.needsConfirm(id)
  return CONFIRMED[id] ~= nil
end

function menu.confirm(id)
  return {
    prompt = CONFIRMED[id] .. "?",
    selected = 1,
    rows = {
      { id = "cancel", icon = "󰅖", label = "Cancel" },
      { id = "confirmed." .. id, icon = CONFIRMED_ICONS[id], label = CONFIRMED[id] },
    },
  }
end

return menu
