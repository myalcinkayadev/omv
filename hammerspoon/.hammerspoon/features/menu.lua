-- System menu (Option+Escape): lock, sleep, restart and reload the tools.

local shell = require("shell")
local card = require("card")
local menu = require("menu")

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

local function screenFor(key)
  local confirmed = key:match("^confirm:(.+)$")
  if confirmed then return menu.confirm(confirmed) end
  return menu.screen(key)
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
  if id == "sound" then return require("features.sound").open() end
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
