-- System menu (Option+Escape): lock, sleep, restart and reload the tools.

local shell = require("shell")
local card = require("card")
local menu = require("menu")
local flags = require("flags")

local feature = {}

local ACTIONS = {
  lock = hs.caffeinate.lockScreen,
  screensaver = hs.caffeinate.startScreensaver,
  sleep = hs.caffeinate.systemSleep,
  ["confirmed.logout"] = hs.caffeinate.logOut,
  ["confirmed.restart"] = hs.caffeinate.restartSystem,
  ["confirmed.shutdown"] = hs.caffeinate.shutdownSystem,
  ["reload.aerospace"] = shell.run(shell.AEROSPACE, { "reload-config" }),
  ["reload.sketchybar"] = shell.run(shell.SKETCHYBAR, { "--reload" }),
  ["reload.hammerspoon"] = hs.reload,
  ["reload.all"] = function()
    shell.run(shell.AEROSPACE, { "reload-config" })()
    shell.run(shell.SKETCHYBAR, { "--reload" })()
    hs.timer.doAfter(0.5, hs.reload)
  end,
}

local menuStack = {}

-- Rows for features turned off with their flags, read once at load like every flag.
local enabled = flags.read(shell.readText(flags.PATH))
local hiddenRows = { focus = not enabled.focus, nightlight = not enabled["night-light"], sound = not enabled.sound }
for id, hidden in pairs(hiddenRows) do
  if not hidden then hiddenRows[id] = nil end
end

local function screenFor(key)
  local confirmed = key:match("^confirm:(.+)$")
  if confirmed then return menu.confirm(confirmed) end
  return menu.screen(key, hiddenRows)
end

local onMenuMessage

local function showMenuTop()
  local screen = screenFor(menuStack[#menuStack])
  shell.show("menu", shell.centered(screen.width or shell.MENU_WIDTH, shell.menuHeight(screen)), card.html(screen), onMenuMessage)
end

local function menuBack()
  table.remove(menuStack)
  if #menuStack == 0 then return shell.close() end
  showMenuTop()
end

local function menuChoose(id)
  if id == "cancel" then return menuBack() end
  -- Required when picked, so loading the menu doesn't load the Sound card ahead of its turn.
  if id == "focus" then return require("features.focus").toggle() end
  if id == "nightlight" then return require("features.nightshift").toggle() end
  if id == "sound" then return require("features.sound").open() end
  if id == "theme" then return require("features.theme").open() end
  -- Loaded with its flag only, since it starts watching the displays when it loads.
  if id == "displays" then
    local profiles = package.loaded["features.displays"]
    if type(profiles) ~= "table" then return shell.alert("Display profiles are off: omv flags display-profiles on", 2.5) end
    return profiles.open()
  end
  if id == "permissions" then return require("features.permissions").open() end
  if menu.opens(id) then
    menuStack[#menuStack + 1] = id
    return showMenuTop()
  end
  if menu.needsConfirm(id) then
    menuStack[#menuStack + 1] = "confirm:" .. id
    return showMenuTop()
  end
  local action = ACTIONS[id]
  shell.close()
  if action then action() end
end

onMenuMessage = function(message)
  if message.type == "close" then return shell.close() end
  if message.type == "back" then return menuBack() end
  if message.type == "choose" then return menuChoose(message.id) end
end

function feature.toggle()
  if shell.isOpen("menu") then return shell.close() end
  menuStack = { "system" }
  showMenuTop()
end

return feature
