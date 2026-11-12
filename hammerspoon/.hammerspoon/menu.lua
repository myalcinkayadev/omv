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
      { id = "focus", icon = "󰽥", label = "Do Not Disturb" },
      { id = "sound", icon = "󰕾", label = "Sound" },
      { id = "theme", icon = "󰏘", label = "Theme" },
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

-- Whether a picked id opens another screen of this menu.
function menu.opens(id)
  return SCREENS[id] ~= nil
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
