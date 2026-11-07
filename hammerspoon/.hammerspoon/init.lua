-- App-launch keys, the system menu, the key list and the calendar. AeroSpace owns every
-- window key; see README.md for the full map.
-- hs.hotkey needs no Accessibility permission, so none is granted.
require("hs.ipc")

local keymap = require("keymap")
local card = require("card")
local menu = require("menu")
local calendar = require("calendar")

hs.menuIcon(false)
hs.dockIcon(false)
hs.uploadCrashData(false)
-- Hotkeys log every enable and disable, which would add lines each time a card opens.
hs.hotkey.setLogLevel("warning")

local SUPER = { "alt" }
local SUPER_SHIFT = { "alt", "shift" }
local AEROSPACE_CONFIG = os.getenv("HOME") .. "/.config/aerospace/aerospace.toml"
local LAUNCH = hs.configdir .. "/launch.sh"
local COPY_URL = hs.configdir .. "/copy-url.sh"
local GHOSTTY_WINDOW = os.getenv("HOME") .. "/.config/ghostty/new-window.sh"
local AEROSPACE = "/opt/homebrew/bin/aerospace"
local SKETCHYBAR = "/opt/homebrew/bin/sketchybar"

local ALERT_STYLE = {
  fillColor = { white = 0, alpha = 1 },
  strokeColor = { white = 0.55, alpha = 1 },
  strokeWidth = 2,
  radius = 0,
  textColor = { white = 1, alpha = 1 },
  textFont = "JetBrainsMono Nerd Font Mono",
  textSize = 15,
}

local function run(command, arguments)
  return function()
    hs.task.new(command, nil, arguments or {}):start()
  end
end

local function open(arguments)
  return run("/usr/bin/open", arguments)
end

local launchers = {}

local function bindKey(modifiers, key, label, description, action)
  hs.hotkey.bind(modifiers, key, action)
  launchers[#launchers + 1] = { label = label, description = description }
end

local function openOnWorkspace(workspace, arguments)
  return run(LAUNCH, { workspace, "/usr/bin/open", table.unpack(arguments) })
end

-- One floating card at a time, shared by the menu, the key list and the calendar.
-- A single webview is made once and only hidden between uses: a new one costs about
-- 110ms to start WebKit, while showing new HTML in this one costs about 6ms.
-- Escape is a hotkey while a card is open, so it closes the card even if typing never reached it.
-- Nothing here uses hs.window: it needs Accessibility, which Hammerspoon is not given,
-- and without it those calls stall.
local panel = nil
local closeOnEscape = nil
local view = nil

local function closePanel()
  if not panel then return end
  -- Cleared first, because hiding fires the focus-loss callback, which calls this.
  local previous = panel.previous
  panel = nil
  view:hide()
  closeOnEscape:disable()
  if previous then previous:activate() end
end

local function centered(width, height)
  local screen = hs.screen.mainScreen():frame()
  return hs.geometry.rect(screen.x + (screen.w - width) / 2, screen.y + (screen.h - height) / 3, width, height)
end

local function makeView()
  local controller = hs.webview.usercontent.new("omv")
  controller:setCallback(function(message)
    if panel then panel.onMessage(message.body) end
  end)
  view = hs.webview.new({ x = 0, y = 0, w = 10, h = 10 }, {}, controller)
  -- Transparent, so a reload shows the black page instead of a white flash.
  view:windowStyle({ "borderless" })
    :level(hs.drawing.windowLevels.modalPanel)
    :allowTextEntry(true)
    :transparent(true)
  -- Clicking anywhere else closes the card, like Omarchy's menu. Only a focus loss after
  -- the card had focus counts, so the handover while it opens never closes it.
  view:windowCallback(function(action, _, focused)
    if action ~= "focusChange" or not panel then return end
    if focused then
      panel.hadFocus = true
    elseif panel.hadFocus then
      panel.previous = nil
      closePanel()
    end
  end)
end

local function showPanel(name, frame, html, onMessage)
  if panel then
    panel.name, panel.onMessage = name, onMessage
    view:frame(frame):html(html)
    return
  end
  panel = { name = name, onMessage = onMessage, previous = hs.application.frontmostApplication() }
  view:frame(frame):html(html):show()
  -- Typing needs Hammerspoon active. Its console would come forward with it, so close it.
  hs.closeConsole()
  hs.focus()
  view:bringToFront(true)
  closeOnEscape:enable()
end

makeView()
closeOnEscape = hs.hotkey.new({}, "escape", closePanel)

-- System menu (Option+Escape)

local MENU_WIDTH = 320

local function menuHeight(screen)
  return 28 + 46 + #screen.rows * 44 + 4
end

local ACTIONS = {
  lock = hs.caffeinate.lockScreen,
  screensaver = hs.caffeinate.startScreensaver,
  sleep = hs.caffeinate.systemSleep,
  ["confirmed.logout"] = hs.caffeinate.logOut,
  ["confirmed.restart"] = hs.caffeinate.restartSystem,
  ["confirmed.shutdown"] = hs.caffeinate.shutdownSystem,
  ["reload.aerospace"] = run(AEROSPACE, { "reload-config" }),
  ["reload.sketchybar"] = run(SKETCHYBAR, { "--reload" }),
  ["reload.hammerspoon"] = hs.reload,
  ["reload.all"] = function()
    run(AEROSPACE, { "reload-config" })()
    run(SKETCHYBAR, { "--reload" })()
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
  showPanel("menu", centered(MENU_WIDTH, menuHeight(screen)), card.html(screen), onMenuMessage)
end

local function menuBack()
  table.remove(menuStack)
  if #menuStack == 0 then return closePanel() end
  showMenuTop()
end

local function menuChoose(id)
  if id == "cancel" then return menuBack() end
  if menu.screen(id) then
    menuStack[#menuStack + 1] = id
    return showMenuTop()
  end
  if menu.needsConfirm(id) then
    menuStack[#menuStack + 1] = "confirm:" .. id
    return showMenuTop()
  end
  local action = ACTIONS[id]
  closePanel()
  if action then action() end
end

onMenuMessage = function(message)
  if message.type == "close" then return closePanel() end
  if message.type == "back" then return menuBack() end
  if message.type == "choose" then return menuChoose(message.id) end
end

local function toggleSystemMenu()
  if panel and panel.name == "menu" then return closePanel() end
  menuStack = { "system" }
  showMenuTop()
end

-- Key list (Option+/)

local function onKeyListMessage(message)
  if message.type == "close" or message.type == "back" or message.type == "choose" then closePanel() end
end

local function toggleKeyList()
  if panel and panel.name == "keys" then return closePanel() end
  local bindings = keymap.read(AEROSPACE_CONFIG)
  local rowsPerColumn = math.ceil(#keymap.rows(bindings, launchers) / 2)
  showPanel("keys", centered(1100, 28 + 46 + rowsPerColumn * 30 + 8), keymap.html(bindings, launchers), onKeyListMessage)
end

-- Calendar (click the clock)

local CALENDAR_WIDTH = 360
local CALENDAR_HEIGHT = 384
local shown = nil

local function today()
  local now = os.date("*t")
  return { year = now.year, month = now.month, day = now.day }
end

local onCalendarMessage

local function showCalendar()
  local screen = hs.screen.mainScreen():fullFrame()
  -- Right-aligned under the clock, just below the 36pt bar.
  local frame = hs.geometry.rect(screen.x + screen.w - CALENDAR_WIDTH - 10, screen.y + 40, CALENDAR_WIDTH, CALENDAR_HEIGHT)
  local model = calendar.month(shown.year, shown.month, today())
  showPanel("calendar", frame, calendar.html(model, today()), onCalendarMessage)
end

onCalendarMessage = function(message)
  if message.type == "close" then return closePanel() end
  if message.type == "today" then shown = today() end
  if message.type == "shift" then
    shown.year, shown.month = calendar.shift(shown.year, shown.month, tonumber(message.id))
  end
  showCalendar()
end

local function toggleCalendar()
  if panel and panel.name == "calendar" then return closePanel() end
  shown = today()
  showCalendar()
end

-- Copy URL (Option+Shift+U)

local function copyUrl()
  hs.task.new(COPY_URL, function(code, _, errors)
    local message = code == 0 and "Copied URL" or (errors:gsub("%s+$", ""))
    hs.alert.show(message, ALERT_STYLE, 1.2)
  end):start()
end

bindKey(SUPER_SHIFT, "return", "Option+Shift+Enter", "New Helium window", openOnWorkspace("3", { "-na", "Helium", "--args", "--new-window" }))
bindKey(SUPER_SHIFT, "n", "Option+Shift+N", "Open Zed", openOnWorkspace("2", { "-a", "Zed" }))
bindKey(SUPER_SHIFT, "f", "Option+Shift+F", "Finder at home", open({ os.getenv("HOME") }))
bindKey(SUPER_SHIFT, "t", "Option+Shift+T", "btop", run(LAUNCH, { "1", GHOSTTY_WINDOW, "/opt/homebrew/bin/btop" }))
bindKey(SUPER_SHIFT, "i", "Option+Shift+I", "Keep the Mac awake, or stop", run(SKETCHYBAR, { "--trigger", "keep_awake_toggle" }))
bindKey(SUPER_SHIFT, "u", "Option+Shift+U", "Copy Helium's current URL", copyUrl)
bindKey(SUPER_SHIFT, "space", "Option+Shift+Space", "Show or hide the bar", run(SKETCHYBAR, { "--bar", "hidden=toggle" }))
bindKey(SUPER, "escape", "Option+Escape", "System menu", toggleSystemMenu)

-- Ghostty owns this key, so it is listed here rather than bound.
launchers[#launchers + 1] = { label = "Option+`", description = "Drop-down terminal" }

-- 44 is the physical "/" key, so this stays the same key on the Turkish layout.
bindKey(SUPER, 44, "Option+/", "Show or hide this list", toggleKeyList)

-- Scripts open the cards with hs -c, for example the bar's clock: hs -c 'omvToggleCalendar()'.
-- Each call waits for the next run-loop turn, because drawing a card inside the hs -c
-- request makes that request call back into itself.
local function later(fn)
  return function() hs.timer.doAfter(0, fn) end
end

omvToggleSystemMenu = later(toggleSystemMenu)
omvToggleKeyList = later(toggleKeyList)
omvToggleCalendar = later(toggleCalendar)
