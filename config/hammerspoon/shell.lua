-- What every feature shares: the one floating card, where cards go on screen, the paths of
-- the tools they run, and small helpers. Features require it; init.lua only wires them up.

local placement = require("placement")
local theme = require("theme")
local paste = require("paste")

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

-- Runs a script with osascript in the background and hands its output to done, or nil
-- when it failed or took longer than seconds. Asking an app over Apple Events waits for its
-- answer, and an app stuck in a dialog never answers: on Hammerspoon's main thread, as
-- hs.osascript runs, that froze every card and key until the app was dealt with.
function shell.osascript(source, language, seconds, done)
  local timer = nil
  local task = hs.task.new("/usr/bin/osascript", function(code, output)
    if timer then timer:stop() end
    done(code == 0 and output or nil)
  end, { "-l", language, "-e", source })
  if not task:start() then return done(nil) end
  timer = hs.timer.doAfter(seconds, function()
    if task:isRunning() then task:terminate() end
  end)
end

-- The tasks shell.execute started that haven't finished, kept so none is garbage-collected
-- while it runs.
local running = {}

-- Runs command with /bin/sh in the background and hands done its output and whether it
-- succeeded, as hs.execute returns them. hs.execute waits on Hammerspoon's only thread, which
-- freezes every card and key until the command finishes.
function shell.execute(command, done)
  local task
  task = hs.task.new("/bin/sh", function(code, output)
    running[task] = nil
    if done then done(output or "", code == 0) end
  end, { "-c", command })
  running[task] = true
  if task:start() then return end
  running[task] = nil
  if done then done("", false) end
end

-- How many commands shell.execute started are still running.
function shell.runningCount()
  local count = 0
  for _ in pairs(running) do count = count + 1 end
  return count
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
-- Nothing here uses hs.window except through shell.typingIn: it needs Accessibility, which
-- Hammerspoon may not be given, and without it those calls stall.
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

-- The window you're typing in, read before a card opens so a pick can be pasted back into it;
-- nil without Accessibility, which hs.window needs.
function shell.typingIn()
  if not paste.canLook(hs.accessibilityState()) then return nil end
  local window = hs.window.focusedWindow()
  return window and window:id()
end

-- After a pick put text on the clipboard and closed the card: Cmd+V once the window typing
-- was in (from shell.typingIn) has focus again, waiting up to 0.6 seconds; otherwise the
-- notice says it was only copied.
local PASTE_WAIT = 0.6

function shell.pasteBack(typingIn, notice)
  if typingIn == nil then return shell.alert(notice, 1.2) end
  local deadline = hs.timer.secondsSinceEpoch() + PASTE_WAIT
  local function back()
    return shell.typingIn() == typingIn
  end
  hs.timer.waitUntil(function()
    return back() or hs.timer.secondsSinceEpoch() >= deadline
  end, function()
    if paste.way(hs.accessibilityState(), typingIn, shell.typingIn()) == "paste" then
      return hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    end
    shell.alert(notice, 1.2)
  end, 0.05)
end

-- Each copy of the clipboard's contents, so a copy made for omv can be undone.
function shell.saveClipboard()
  return hs.pasteboard.readAllData()
end

function shell.restoreClipboard(saved)
  if saved and next(saved) then return hs.pasteboard.writeAllData(saved) end
  hs.pasteboard.clearContents()
end

-- Copies the selection with Cmd+C and hands its text to done, nil when nothing was copied.
-- The clipboard is put back as it was.
local COPY_WAIT_SECONDS = 0.5

function shell.copySelection(done)
  local saved, before = shell.saveClipboard(), hs.pasteboard.changeCount()
  local deadline = hs.timer.secondsSinceEpoch() + COPY_WAIT_SECONDS
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  hs.timer.waitUntil(function()
    return hs.pasteboard.changeCount() ~= before or hs.timer.secondsSinceEpoch() >= deadline
  end, function()
    local copied = hs.pasteboard.changeCount() ~= before and hs.pasteboard.getContents() or nil
    shell.restoreClipboard(saved)
    done(copied)
  end, 0.05)
end

-- The name of the card showing, or "" when none is.
function shell.openName()
  return panel and panel.name or ""
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

-- Just below the bar, under item, the SketchyBar item the card opens from; at the screen's
-- right edge when the item isn't drawn there. Reading its place takes about 10ms; a bar that
-- stopped answering gets a second, so it can't hold every card and key. perl's alarm
-- outlives exec.
function shell.anchored(width, height, item)
  local query = nil
  if item then
    local ok, decoded = pcall(hs.json.decode, hs.execute("/usr/bin/perl -e 'alarm 1; exec @ARGV' " .. shell.SKETCHYBAR .. " --query " .. item .. " 2>/dev/null") or "")
    query = ok and decoded or nil
  end
  local frame = placement.under(query, width, height, shell.screen():fullFrame())
  return hs.geometry.rect(frame.x, frame.y, frame.w, frame.h)
end

function shell.centered(width, height)
  local frame = placement.centered(width, height, shell.screen():frame())
  return hs.geometry.rect(frame.x, frame.y, frame.w, frame.h)
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
-- The theme's colours for the cards, set by features/theme.lua; Vantablack until then.
local themeTokens = nil
local themeWatchers = {}

function shell.setTheme(tokens)
  themeTokens = tokens
  for _, watcher in ipairs(themeWatchers) do watcher() end
end

-- The chosen theme's colours, Vantablack's until one is chosen.
function shell.themeTokens()
  return themeTokens or theme.tokens(nil)
end

-- Windows other than the card redraw in a newly chosen theme through this.
function shell.onThemeChange(watcher)
  themeWatchers[#themeWatchers + 1] = watcher
end

-- A page in the chosen theme's colours, for windows other than the card too.
function shell.themed(html)
  if not themeTokens then return html end
  return theme.recolor(html, themeTokens)
end

function shell.show(name, frame, html, onMessage, options)
  options = options or {}
  html = shell.themed(html)
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
