-- What every feature shares: the one floating card, where cards go on screen, the paths of
-- the tools they run, and small helpers. Features require it; init.lua only wires them up.

local shell = {}

shell.HOME = os.getenv("HOME")
shell.LAUNCH = hs.configdir .. "/launch.sh"
shell.GHOSTTY_WINDOW = shell.HOME .. "/.config/ghostty/new-window.sh"
shell.AEROSPACE = "/opt/homebrew/bin/aerospace"
shell.SKETCHYBAR = "/opt/homebrew/bin/sketchybar"
shell.STATE_DIR = shell.HOME .. "/.local/state/omv"
shell.BLACK, shell.WHITE = "0xff000000", "0xffffffff"
shell.MENU_WIDTH = 320
-- The compact lists: windows, pull requests, meetings, projects and waiting sessions.
shell.LIST_WIDTH = 720
shell.LIST_VISIBLE_ROWS = 14

shell.ALERT_STYLE = {
  fillColor = { white = 0, alpha = 1 },
  strokeColor = { white = 0.55, alpha = 1 },
  strokeWidth = 2,
  radius = 0,
  textColor = { white = 1, alpha = 1 },
  textFont = "JetBrainsMono Nerd Font Mono",
  textSize = 15,
}

-- The screen a card or alert opens on: the one the pointer is on. The bar is on every
-- screen, and a click on it doesn't move focus, so the focused screen could be the other
-- one. For a key it is the same screen, since AeroSpace moves the pointer along when focus
-- changes screen.
function shell.screen()
  return hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
end

function shell.alert(text, seconds)
  hs.alert.show(text, shell.ALERT_STYLE, shell.screen(), seconds)
end

function shell.run(command, arguments)
  return function()
    hs.task.new(command, nil, arguments or {}):start()
  end
end

function shell.open(arguments)
  return shell.run("/usr/bin/open", arguments)
end

function shell.readText(path, bytes)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read(bytes or "*a")
  file:close()
  return text
end

-- One floating card at a time, shared by every feature.
-- A single webview is made once and only hidden between uses: a new one costs about
-- 110ms to start WebKit, while showing new HTML in this one costs about 6ms.
-- Escape is a hotkey while a card is open, so it closes the card even if typing never reached it.
-- Nothing here uses hs.window: it needs Accessibility, which Hammerspoon is not given,
-- and without it those calls stall.
local panel = nil
local closeOnEscape = nil
local view = nil

function shell.close()
  if not panel then return end
  -- Cleared first, because hiding fires the focus-loss callback, which calls this.
  local previous, onClose = panel.previous, panel.onClose
  panel = nil
  if onClose then onClose() end
  view:hide()
  closeOnEscape:disable()
  if previous then previous:activate() end
end

-- Whether the card named name is the one showing. With several names, any of them.
function shell.isOpen(...)
  if not panel then return false end
  for _, name in ipairs({ ... }) do
    if panel.name == name then return true end
  end
  return false
end

-- Closing then leaves focus where the card's action put it, rather than handing it back
-- to the app open before.
function shell.leaveFocus()
  if panel then panel.previous = nil end
end

-- A card that waits on something, like the microphone prompt, stays open when focus moves away.
function shell.keepOnBlur(keep)
  if panel then panel.keepOnBlur = keep end
end

function shell.view()
  return view
end

-- Right-aligned just below the 36pt bar, under the status items.
function shell.anchored(width, height)
  local screen = shell.screen():fullFrame()
  return hs.geometry.rect(screen.x + screen.w - width - 10, screen.y + 40, width, height)
end

function shell.centered(width, height)
  local screen = shell.screen():frame()
  return hs.geometry.rect(screen.x + (screen.w - width) / 2, screen.y + (screen.h - height) / 3, width, height)
end

function shell.menuHeight(screen)
  -- An empty screen still has room for its "No matches" line.
  return 28 + 46 + math.max(1, #screen.rows) * 44 + 4
end

-- A compact list's height, showing at most visible rows.
function shell.listHeight(rows, visible)
  return 28 + 46 + math.min(rows, visible or shell.LIST_VISIBLE_ROWS) * 30 + 8
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
    elseif panel.hadFocus and not panel.keepOnBlur then
      panel.previous = nil
      shell.close()
    end
  end)
end

-- options.onEscape replaces closing on Escape, and options.keepOnBlur keeps the card open
-- when focus moves away. The Pomodoro cards use both: a break shouldn't vanish on Cmd+Tab.
-- options.onClose runs when the card closes or another card takes its place.
function shell.show(name, frame, html, onMessage, options)
  options = options or {}
  if panel then
    if panel.name ~= name and panel.onClose then panel.onClose() end
    panel.name, panel.onMessage, panel.onClose = name, onMessage, options.onClose
    panel.onEscape, panel.keepOnBlur = options.onEscape, options.keepOnBlur
    view:frame(frame):html(html)
    return
  end
  panel = { name = name, onMessage = onMessage, previous = hs.application.frontmostApplication(),
    onEscape = options.onEscape, keepOnBlur = options.keepOnBlur, onClose = options.onClose }
  view:frame(frame):html(html):show()
  -- Typing needs Hammerspoon active. Its console would come forward with it, so close it.
  hs.closeConsole()
  hs.focus()
  view:bringToFront(true)
  closeOnEscape:enable()
end

makeView()
closeOnEscape = hs.hotkey.new({}, "escape", function()
  if panel and panel.onEscape then return panel.onEscape() end
  shell.close()
end)

return shell
