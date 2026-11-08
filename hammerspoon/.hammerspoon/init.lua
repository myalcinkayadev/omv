-- App-launch keys, the system menu, the key list and the calendar. AeroSpace owns every
-- window key; see README.md for the full map.
-- hs.hotkey needs no Accessibility permission, so none is granted.
require("hs.ipc")

local keymap = require("keymap")
local card = require("card")
local menu = require("menu")
local calendar = require("calendar")
local windows = require("windows")
local capture = require("capture")
local reminders = require("reminders")
local pomo = require("pomo")
local agenda = require("agenda")
local network = require("network")
local sound = require("sound")
local weather = require("weather")
local battery = require("battery")

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
local CAPTURE = hs.configdir .. "/capture.sh"
local AGENDA = hs.configdir .. "/agenda.sh"
local METER = hs.configdir .. "/meter.sh"
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

-- Each key keeps its action, so the key list can run it too.
local function bindKey(modifiers, key, label, description, action)
  hs.hotkey.bind(modifiers, key, action)
  launchers[#launchers + 1] = { label = label, description = description, run = action, runs = true }
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
  local previous, onClose = panel.previous, panel.onClose
  panel = nil
  if onClose then onClose() end
  view:hide()
  closeOnEscape:disable()
  if previous then previous:activate() end
end

-- Right-aligned just below the 36pt bar, under the status items.
local function anchored(width, height)
  local screen = hs.screen.mainScreen():fullFrame()
  return hs.geometry.rect(screen.x + screen.w - width - 10, screen.y + 40, width, height)
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
    elseif panel.hadFocus and not panel.keepOnBlur then
      panel.previous = nil
      closePanel()
    end
  end)
end

-- options.onEscape replaces closing on Escape, and options.keepOnBlur keeps the card open
-- when focus moves away. The Pomodoro cards use both: a break shouldn't vanish on Cmd+Tab.
-- options.onClose runs when the card closes or another card takes its place.
local function showPanel(name, frame, html, onMessage, options)
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
  closePanel()
end)

-- System menu (Option+Escape)

local MENU_WIDTH = 320

local function menuHeight(screen)
  -- An empty screen still has room for its "No matches" line.
  return 28 + 46 + math.max(1, #screen.rows) * 44 + 4
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
-- Defined with the Sound card below, which the system menu's Sound row opens.
local openSound

local function showMenuTop()
  local screen = screenFor(menuStack[#menuStack])
  showPanel("menu", centered(screen.width or MENU_WIDTH, menuHeight(screen)), card.html(screen), onMenuMessage)
end

local function menuBack()
  table.remove(menuStack)
  if #menuStack == 0 then return closePanel() end
  showMenuTop()
end

local function menuChoose(id)
  if id == "cancel" then return menuBack() end
  if id == "sound" then return openSound() end
  if menu.opens(id) then
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

-- Enter on a row runs that shortcut. The list closes and focus goes back first, because
-- commands like "focus left" act on whichever window has focus.
local KEY_LIST_DELAY = 0.15
local keyListBindings = {}

local function runSteps(steps, index)
  local step = steps[index]
  if not step then return end
  local program = step.program == "aerospace" and AEROSPACE or step.program
  hs.task.new(program, function() runSteps(steps, index + 1) end, step.args):start()
end

local function runKeyListRow(id)
  local kind, index = id:match("^(%a+):(%d+)$")
  index = tonumber(index)
  if kind == "binding" and keyListBindings[index] then
    local steps = keymap.steps(keyListBindings[index].commands)
    return function() runSteps(steps, 1) end
  end
  local launcher = kind == "launcher" and launchers[index]
  return launcher and launcher.runs and launcher.run or nil
end

local function onKeyListMessage(message)
  if message.type ~= "choose" then return closePanel() end
  local action = runKeyListRow(message.id)
  closePanel()
  if action then hs.timer.doAfter(KEY_LIST_DELAY, action) end
end

local function toggleKeyList()
  if panel and panel.name == "keys" then return closePanel() end
  local bindings = keymap.read(AEROSPACE_CONFIG)
  keyListBindings = bindings
  local rowsPerColumn = math.ceil(#keymap.rows(bindings, launchers) / 2)
  showPanel("keys", centered(1100, 28 + 46 + rowsPerColumn * 30 + 8), keymap.html(bindings, launchers), onKeyListMessage)
end

-- Window summon (Option+Space)

local WINDOWS_WIDTH = 720
local WINDOWS_VISIBLE_ROWS = 14

local function onWindowsMessage(message)
  if message.type ~= "choose" then return closePanel() end
  -- Leave focus to AeroSpace, rather than handing it back to the app open before.
  panel.previous = nil
  closePanel()
  run(AEROSPACE, { "focus", "--window-id", message.id })()
end

local function toggleWindows()
  if panel and panel.name == "windows" then return closePanel() end
  hs.task.new(AEROSPACE, function(code, output)
    if code ~= 0 then return end
    local rows = windows.rows(output)
    local height = 28 + 46 + math.min(#rows, WINDOWS_VISIBLE_ROWS) * 30 + 8
    showPanel("windows", centered(WINDOWS_WIDTH, height), card.html({ prompt = "Windows…", rows = rows, compact = true }), onWindowsMessage)
  end, { "list-windows", "--all", "--format", windows.FORMAT }):start()
end

-- Capture menu (Option+Shift+S)

local CAPTURE_DONE = {
  ["region.clipboard"] = "Copied screenshot",
  ["region.file"] = "Saved to Desktop",
  ["window.clipboard"] = "Copied screenshot",
  ["screen.clipboard"] = "Copied screenshot",
  text = "Copied text",
}

local function runCapture(id)
  local program, arguments = capture.command(id, os.getenv("HOME"), CAPTURE, os.time())
  if not program then return end
  hs.task.new(program, function(code, output, errors)
    -- A cancelled selection exits non-zero with nothing to say, so it stays quiet.
    local message = code == 0 and (CAPTURE_DONE[id] or ("Copied " .. output:gsub("%s+$", ""))) or errors:gsub("%s+$", "")
    if message ~= "" then hs.alert.show(message, ALERT_STYLE, 1.2) end
  end, arguments):start()
end

local function onCaptureMessage(message)
  closePanel()
  if message.type ~= "choose" then return end
  -- Wait for the card to disappear, so it never ends up in the picture.
  hs.timer.doAfter(0.2, function() runCapture(message.id) end)
end

local function toggleCapture()
  if panel and panel.name == "capture" then return closePanel() end
  local screen = capture.screen()
  showPanel("capture", centered(MENU_WIDTH, menuHeight(screen)), card.html(screen), onCaptureMessage)
end

-- Quick reminders (Option+Shift+M). The bar shows the soonest one; clicking it lists them.
-- They are saved to a file, so they survive a reload of this config.

local STATE_DIR = os.getenv("HOME") .. "/.local/state/omv"
local REMINDERS_FILE = STATE_DIR .. "/reminders"
local REMINDER_FLASH_SECONDS = 10
local REMINDER_WIDTH = 480
local BLACK, WHITE = "0xff000000", "0xffffffff"

local reminderList = {}
local reminderTimer = nil
local flashUntil = nil
-- Set below, with the Pomodoro cards, which add and remove reminders themselves.
local onPomoReminder

local function saveReminders()
  os.execute("/bin/mkdir -p '" .. STATE_DIR .. "'")
  local file = io.open(REMINDERS_FILE, "w")
  if not file then return end
  file:write(reminders.encode(reminderList))
  file:close()
end

local function loadReminders()
  local file = io.open(REMINDERS_FILE, "r")
  if not file then return {} end
  local text = file:read("*a")
  file:close()
  return reminders.decode(text, os.time())
end

-- The bar's fit check runs only when the item's width can change: it appears or goes, or
-- its label changes length. The countdown ticking from 24:10 to 24:09 doesn't count.
local reminderShape = nil

local function setReminderBar(properties)
  local arguments = { "--set", "reminder", table.unpack(properties) }
  local drawing, label = "", ""
  for _, property in ipairs(properties) do
    drawing = property:match("^drawing=(.*)") or drawing
    label = property:match("^label=(.*)") or label
  end
  local shape = drawing .. ":" .. utf8.len(label)
  if shape ~= reminderShape then
    reminderShape = shape
    arguments[#arguments + 1] = "--trigger"
    arguments[#arguments + 1] = "bar_fit"
  end
  hs.task.new(SKETCHYBAR, nil, arguments):start()
end

-- A due reminder notifies, and turns the bar item into a white pill for a moment.
-- Pomodoro reminders open their cards instead.
local function fireReminder(reminder)
  if reminder.kind then return onPomoReminder(reminder) end
  hs.notify.new({ title = "Reminder", informativeText = reminder.text, withdrawAfter = 0 }):send()
  hs.alert.show("󰔛 " .. reminder.text, ALERT_STYLE, 4)
  setReminderBar({ "drawing=on", "label=" .. reminders.short(reminder.text), "background.drawing=on", "icon.color=" .. BLACK, "label.color=" .. BLACK })
  flashUntil = os.time() + REMINDER_FLASH_SECONDS
end

local function tickReminders()
  local now = os.time()
  local waiting = {}
  for _, reminder in ipairs(reminderList) do
    if reminder.due <= now then fireReminder(reminder) else waiting[#waiting + 1] = reminder end
  end
  if #waiting ~= #reminderList then
    reminderList = waiting
    saveReminders()
  end
  if flashUntil and now < flashUntil then return end
  flashUntil = nil
  if #reminderList == 0 then
    setReminderBar({ "drawing=off", "background.drawing=off" })
    reminderTimer:stop()
    return
  end
  -- A pomo's last 30 seconds turn the item into a white pill, a quiet heads-up.
  local warning = pomo.warning(reminderList[1], now)
  local text = warning and BLACK or WHITE
  setReminderBar({ "drawing=on", "icon=" .. reminders.icon(reminderList), "background.drawing=" .. (warning and "on" or "off"),
    "icon.color=" .. text, "label.color=" .. text, "label=" .. reminders.label(reminderList, now) })
end

reminderTimer = hs.timer.new(1, tickReminders)

local function startReminders()
  tickReminders()
  if not reminderTimer:running() then reminderTimer:start() end
end

-- "c" in the reminder box cancels the soonest reminder, and says which one.
local function cancelSoonestReminder()
  closePanel()
  local soonest = table.remove(reminderList, 1)
  if not soonest then return hs.alert.show("No reminders", ALERT_STYLE, 1.5) end
  saveReminders()
  startReminders()
  hs.alert.show("Cancelled: " .. soonest.text, ALERT_STYLE, 1.5)
end

local function onReminderInput(message)
  if message.type == "close" then return closePanel() end
  if message.type ~= "submit" then return end
  local seconds, text, kind = reminders.parse(message.id)
  if kind == "cancel" then return cancelSoonestReminder() end
  if not seconds then
    hs.alert.show("Start with a time, like 25m", ALERT_STYLE, 1.5)
    return
  end
  -- A typed break goes straight to its countdown card.
  if kind == "break" then return onPomoReminder({ kind = "start-break", seconds = seconds }) end
  reminderList[#reminderList + 1] = { due = os.time() + seconds, text = text, kind = kind }
  reminderList = reminders.sorted(reminderList)
  saveReminders()
  closePanel()
  startReminders()
end

local function newReminder()
  if panel and panel.name == "reminder" then return closePanel() end
  local screen = { prompt = "Remind me…", rows = {}, input = true, hint = "25m check deploy · pomo · b break · c cancel" }
  showPanel("reminder", centered(REMINDER_WIDTH, 28 + 46 + 44 + 4), card.html(screen), onReminderInput)
end

local function onReminderList(message)
  if message.type ~= "choose" then return closePanel() end
  table.remove(reminderList, tonumber(message.id))
  saveReminders()
  closePanel()
  startReminders()
end

local function toggleReminders()
  if panel and panel.name == "reminders" then return closePanel() end
  -- During a break, the bar item reopens its countdown.
  if reminderList[1] and reminderList[1].kind == "break" then return onPomoReminder({ kind = "show-break" }) end
  if #reminderList == 0 then return newReminder() end
  local now, rows = os.time(), {}
  for index, reminder in ipairs(reminderList) do
    rows[index] = { id = tostring(index), icon = "󰔛", label = reminder.text, hint = reminders.left(reminder.due - now) }
  end
  local screen = { prompt = "Cancel a reminder…", rows = rows }
  showPanel("reminders", centered(REMINDER_WIDTH, menuHeight(screen)), card.html(screen), onReminderList)
end

-- Pomodoro break cards. A pomo coming due opens "Time for a break.", and nothing after it
-- starts on its own: the break, the next pomo and stopping are all picked on a card.

local POMO_FILE = STATE_DIR .. "/pomo"
local pomoStep = nil

local function todayKey()
  return os.date("%Y-%m-%d")
end

local function readPomoRecord()
  local file = io.open(POMO_FILE, "r")
  if not file then return pomo.decode("") end
  local text = file:read("*a")
  file:close()
  return pomo.decode(text)
end

local function pomoCount()
  return pomo.countFor(readPomoRecord(), todayKey())
end

local function countFinishedPomo()
  os.execute("/bin/mkdir -p '" .. STATE_DIR .. "'")
  local file = io.open(POMO_FILE, "w")
  if not file then return end
  file:write(pomo.encode(pomo.finished(readPomoRecord(), todayKey())))
  file:close()
end

local function addReminder(seconds, text, kind)
  reminderList[#reminderList + 1] = { due = os.time() + seconds, text = text, kind = kind }
  reminderList = reminders.sorted(reminderList)
  saveReminders()
  startReminders()
end

local function removeBreaks()
  local kept = {}
  for _, reminder in ipairs(reminderList) do
    if reminder.kind ~= "break" then kept[#kept + 1] = reminder end
  end
  reminderList = kept
  saveReminders()
  startReminders()
end

local onPomoMessage

local function showPomo()
  local count = pomoCount()
  local screen
  if pomoStep.step == "done" then
    screen = pomo.doneScreen({ task = pomoStep.task, count = count, postponed = pomoStep.postponed })
  elseif pomoStep.step == "break" then
    screen = pomo.breakScreen({ ends = pomoStep.ends, seconds = pomoStep.seconds, count = count, tip = count + 1 })
  else
    screen = pomo.overScreen({ task = pomoStep.task, count = count })
  end
  -- Escape skips the break on the first card, ends it early on the second, and stops on the last.
  local escape = { done = "break.skip", ["break"] = "break.end", over = "pomo.stop" }
  showPanel("pomo", hs.screen.mainScreen():fullFrame(), card.big(screen), onPomoMessage, {
    keepOnBlur = true,
    onEscape = function() onPomoMessage({ type = "choose", id = escape[pomoStep.step] }) end,
  })
end

local function startBreak(seconds)
  removeBreaks()
  addReminder(seconds, "Break", "break")
  pomoStep = { step = "break", task = pomoStep and pomoStep.task, ends = os.time() + seconds, seconds = seconds }
  showPomo()
end

onPomoMessage = function(message)
  if message.type ~= "choose" or not pomoStep then return end
  local id, task = message.id, pomoStep.task
  if id == "break.start" then return startBreak(pomo.breakSeconds(pomoCount())) end
  if id == "break.skip" or id == "break.end" then
    removeBreaks()
    pomoStep = { step = "over", task = task }
    return showPomo()
  end
  pomoStep = nil
  closePanel()
  if id == "pomo.postpone" then addReminder(pomo.POSTPONE_SECONDS, pomo.task(task), "postponed") end
  if id == "pomo.next" then addReminder(pomo.POMO_SECONDS, pomo.task(task), "pomo") end
end

onPomoReminder = function(reminder)
  if reminder.kind == "start-break" then
    pomoStep = { step = "break", task = pomoStep and pomoStep.task }
    return startBreak(reminder.seconds)
  end
  if reminder.kind == "show-break" then
    local current = reminderList[1]
    pomoStep = { step = "break", task = pomoStep and pomoStep.task, ends = current.due, seconds = pomo.breakSeconds(pomoCount()) }
    return showPomo()
  end
  if reminder.kind == "break" then
    hs.notify.new({ title = "Break over", informativeText = "Back to work when you're ready.", withdrawAfter = 0 }):send()
    pomoStep = { step = "over", task = pomoStep and pomoStep.task }
    return showPomo()
  end
  -- A pomo counts when its 25 minutes are done, not again after "5 more minutes".
  if reminder.kind == "pomo" then countFinishedPomo() end
  hs.notify.new({ title = "Pomodoro done", informativeText = reminder.text, withdrawAfter = 0 }):send()
  pomoStep = { step = "done", task = reminder.text, postponed = reminder.kind == "postponed" }
  showPomo()
end

-- Redraw even with none saved, so a reload clears an item left over from before.
reminderList = loadReminders()
if #reminderList > 0 then startReminders() else tickReminders() end

-- Calendar (click the clock)

local CALENDAR_WIDTH = 360
local shown = nil
local agendaDay = nil

local function today()
  local now = os.date("*t")
  return { year = now.year, month = now.month, day = now.day }
end

local onCalendarMessage

local function showCalendar()
  local now = os.time()
  local frame = anchored(CALENDAR_WIDTH, calendar.height(agendaDay, now))
  local model = calendar.month(shown.year, shown.month, today())
  showPanel("calendar", frame, calendar.html(model, today(), agendaDay, now), onCalendarMessage)
end

-- Today's events (agenda.sh). They are read every 5 minutes, on wake and when the
-- calendar opens; the bar's next-meeting item is redrawn from them every 30 seconds.

local AGENDA_REFRESH_SECONDS = 300
local MEETING_REDRAW_SECONDS = 30
local agendaText = nil
local agendaTask = nil
local meetingShown = nil

local function drawMeeting()
  local meeting = agendaDay and agenda.bar(agendaDay.events, os.time())
  local properties
  if not meeting then
    properties = { "drawing=off" }
  elseif meeting.soon then
    properties = { "drawing=on", "label=" .. meeting.label, "background.drawing=on", "icon.color=" .. BLACK, "label.color=" .. BLACK }
  else
    properties = { "drawing=on", "label=" .. meeting.label, "background.drawing=off", "icon.color=" .. WHITE, "label.color=" .. WHITE }
  end
  -- Only a change reaches SketchyBar, since most redraws find the same meeting.
  local key = table.concat(properties, "\n")
  if key == meetingShown then return end
  meetingShown = key
  properties[#properties + 1] = "--trigger"
  properties[#properties + 1] = "bar_fit"
  hs.task.new(SKETCHYBAR, nil, { "--set", "meeting", table.unpack(properties) }):start()
end

-- changed runs once the events are read, only if they differ from the ones before.
local function readAgenda(changed)
  if agendaTask and agendaTask:isRunning() then return end
  agendaTask = hs.task.new(AGENDA, function(code, output)
    agendaTask = nil
    if code ~= 0 or output == agendaText then return drawMeeting() end
    agendaText = output
    agendaDay = agenda.decode(output)
    drawMeeting()
    if changed then changed() end
  end)
  agendaTask:start()
end

local function redrawOpenCalendar()
  if panel and panel.name == "calendar" then showCalendar() end
end

-- Globals, so the timers and the watcher are never garbage-collected.
omvAgendaTimers = {
  hs.timer.doEvery(AGENDA_REFRESH_SECONDS, function() readAgenda(redrawOpenCalendar) end),
  hs.timer.doEvery(MEETING_REDRAW_SECONDS, drawMeeting),
}
omvWakeWatcher = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then readAgenda(redrawOpenCalendar) end
end):start()
readAgenda()

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
  readAgenda(redrawOpenCalendar)
end

-- Wi-Fi and Ethernet cards (click the bar icons, Option+Shift+W / E)

local WIFI_SETTINGS = "x-apple.systempreferences:com.apple.wifi-settings-extension"
local NETWORK_SETTINGS = "x-apple.systempreferences:com.apple.Network-Settings.extension"
-- Joining a network takes a moment after Wi-Fi turns on, so the card redraws again then.
local WIFI_JOIN_SECONDS = 4

local function ipv4(interface)
  for _, address in ipairs(hs.network.addresses(interface) or {}) do
    if address:match("^%d+%.%d+%.%d+%.%d+$") then return address end
  end
  return nil
end

local function routeFor(interface)
  local scope = interface and ("-ifscope " .. interface .. " ") or ""
  return network.parseRoute(hs.execute("/sbin/route -n get " .. scope .. "default 2>/dev/null"))
end

-- The network name needs Location for Hammerspoon; without it ssid is nil.
local function wifiInfo()
  local details = hs.wifi.interfaceDetails() or {}
  local interface = details.interface or "en0"
  local channel = details.wlanChannel or {}
  return {
    power = details.power == true,
    ssid = details.ssid,
    rssi = details.rssi,
    ip = ipv4(interface),
    router = routeFor(interface).gateway,
    channel = channel.number,
    band = channel.band,
  }
end

-- The wired port with an address, preferring the one the default route leaves by.
local function ethernetInfo()
  local default = routeFor(nil).interface
  local chosen = nil
  for _, port in ipairs(network.wiredPorts(hs.execute("/usr/sbin/networksetup -listallhardwareports"))) do
    local media = network.parseMedia(hs.execute("/sbin/ifconfig " .. port .. " 2>/dev/null"))
    local ip = ipv4(port)
    if media.active and ip and (not chosen or port == default) then
      chosen = { port = port, ip = ip, mbps = media.mbps, duplex = media.duplex }
    end
  end
  if chosen then chosen.router = routeFor(chosen.port).gateway end
  return chosen
end

local onNetworkMessage
local showWifi

showWifi = function()
  showPanel("wifi", anchored(network.WIDTH, network.HEIGHT), network.html(network.wifiModel(wifiInfo())), onNetworkMessage)
end

local function showEthernet(info)
  showPanel("ethernet", anchored(network.WIDTH, network.HEIGHT), network.html(network.ethernetModel(info)), onNetworkMessage)
end

local function redrawWifi()
  if panel and panel.name == "wifi" then showWifi() end
  hs.task.new(SKETCHYBAR, nil, { "--update" }):start()
end

onNetworkMessage = function(message)
  if message.type ~= "choose" then return closePanel() end
  if message.id == "wifi.power" then
    hs.wifi.setPower(not wifiInfo().power)
    redrawWifi()
    hs.timer.doAfter(WIFI_JOIN_SECONDS, redrawWifi)
    return
  end
  local url = message.id == "wifi.settings" and WIFI_SETTINGS or NETWORK_SETTINGS
  closePanel()
  open({ url })()
end

local function toggleWifi()
  if panel and panel.name == "wifi" then return closePanel() end
  showWifi()
end

local function toggleEthernet()
  if panel and panel.name == "ethernet" then return closePanel() end
  local info = ethernetInfo()
  if not info then return hs.alert.show("No cable connected", ALERT_STYLE, 1.5) end
  showEthernet(info)
end

-- Sound card (click the volume icon, Option+Shift+V, or Sound in the system menu)
-- While it is open, meter.sh runs a helper that writes the mic's level to a file. The card
-- reads it ten times a second, and touches an .alive file the helper watches, so the
-- helper stops by itself if this config is reloaded or stops reading.

local METER_FILE = os.getenv("HOME") .. "/.cache/omv/meter-level"
local METER_ALIVE = METER_FILE .. ".alive"
local METER_SECONDS = 0.1
-- How long to wait for the helper's first answer before letting a click elsewhere close
-- the card again, in case the helper never starts.
local METER_ANSWER_SECONDS = 10
local meterTimer = nil
local meterAnswerTimer = nil
-- Bumped by every start and stop, so a start still waiting on an earlier stop gives up.
local meterGeneration = 0
-- Whether the helper has answered since it started: a level, "denied" or "none". Until
-- then the card may be under macOS's microphone prompt, so losing focus must not close it.
local meterAnswered = false

local function touchMeterAlive()
  local file = io.open(METER_ALIVE, "w")
  if file then file:close() end
end

local function meterHasAnswered()
  if meterAnswered then return end
  meterAnswered = true
  if meterAnswerTimer then meterAnswerTimer:stop() end
  meterAnswerTimer = nil
  if panel and panel.name == "sound" then panel.keepOnBlur = false end
end

local function readMeter()
  touchMeterAlive()
  local file = io.open(METER_FILE, "r")
  if not file then return end
  local line = file:read("*l")
  file:close()
  if not line then return end
  meterHasAnswered()
  local level = tonumber(line)
  if level and panel and panel.name == "sound" then view:evaluateJavaScript("omvLevel(" .. level .. ")") end
end

local function stopMeterTimers()
  if meterTimer then meterTimer:stop() end
  if meterAnswerTimer then meterAnswerTimer:stop() end
  meterTimer, meterAnswerTimer = nil, nil
end

local function stopMeter()
  meterGeneration = meterGeneration + 1
  stopMeterTimers()
  os.remove(METER_ALIVE)
  hs.task.new(METER, nil, { "stop" }):start()
end

local function launchMeter(generation)
  os.execute("/bin/mkdir -p '" .. os.getenv("HOME") .. "/.cache/omv'")
  os.remove(METER_FILE)
  touchMeterAlive()
  hs.task.new(METER, function(code)
    -- The helper couldn't be built or started: it will never answer.
    if code ~= 0 and generation == meterGeneration then meterHasAnswered() end
  end, { "start", METER_FILE }):start()
  meterTimer = hs.timer.doEvery(METER_SECONDS, readMeter)
  meterAnswerTimer = hs.timer.doAfter(METER_ANSWER_SECONDS, meterHasAnswered)
end

-- Stops any helper first and starts the new one once it has gone, so the two never
-- overlap. The helper listens to the input that was default when it started, so picking
-- a new input starts it again this way too.
local function startMeter()
  meterGeneration = meterGeneration + 1
  local generation = meterGeneration
  stopMeterTimers()
  meterAnswered = false
  hs.task.new(METER, function()
    if generation == meterGeneration and panel and panel.name == "sound" then launchMeter(generation) end
  end, { "stop" }):start()
end

local function deviceList(devices, current)
  local currentUid = current and current:uid()
  local result = {}
  for _, device in ipairs(devices) do
    result[#result + 1] = { uid = device:uid(), name = device:name(), transport = device:transportType(), current = device:uid() == currentUid }
  end
  return result
end

-- A device that takes no volume reports nil, which the card shows as a dash.
local function soundState()
  local output, input = hs.audiodevice.defaultOutputDevice(), hs.audiodevice.defaultInputDevice()
  return {
    outputs = deviceList(hs.audiodevice.allOutputDevices(), output),
    inputs = deviceList(hs.audiodevice.allInputDevices(), input),
    outputVolume = output and output:outputVolume() or false,
    inputVolume = input and input:inputVolume() or false,
    muted = output and output:outputMuted() or false,
  }
end

local function redrawVolumeBar()
  local output = hs.audiodevice.defaultOutputDevice()
  local level = output and output:outputVolume()
  hs.task.new(SKETCHYBAR, nil, { "--trigger", "volume_change", "INFO=" .. (level and math.floor(level + 0.5) or "") }):start()
end

local onSoundMessage

local function showSound()
  local state = soundState()
  showPanel("sound", anchored(sound.WIDTH, sound.height(state)), sound.html(state), onSoundMessage,
    { keepOnBlur = not meterAnswered, onClose = stopMeter })
end

onSoundMessage = function(message)
  if message.type == "close" then return closePanel() end
  local output, input = hs.audiodevice.defaultOutputDevice(), hs.audiodevice.defaultInputDevice()
  local level = tonumber(message.id)
  -- The page already shows a new volume, so only the bar is redrawn.
  if message.type == "volume" and output and level then
    output:setOutputVolume(level)
    return redrawVolumeBar()
  end
  if message.type == "inputVolume" and input and level then
    input:setInputVolume(level)
    return
  end
  if message.type == "mute" and output then output:setOutputMuted(not output:outputMuted()) end
  local device = (message.type == "output" or message.type == "input") and hs.audiodevice.findDeviceByUID(message.id)
  if device and message.type == "output" then device:setDefaultOutputDevice() end
  if device and message.type == "input" then
    device:setDefaultInputDevice()
    startMeter()
  end
  showSound()
  redrawVolumeBar()
end

-- The meter starts first, so the card opens knowing the helper hasn't answered yet.
openSound = function()
  startMeter()
  showSound()
end

local function toggleSound()
  if panel and panel.name == "sound" then return closePanel() end
  openSound()
end

-- A helper left running by an earlier load of this config.
hs.task.new(METER, nil, { "stop" }):start()

-- Weather (the bar item, Option+Shift+O). It follows the Mac's location, which macOS asks
-- to share with Hammerspoon the first time. Read every 30 minutes, on wake and when the
-- card opens. The last good reading stays shown when a later one fails.

local WEATHER_REFRESH_SECONDS = 1800
local LOCATION_RETRY_SECONDS = 5
local LOCATION_RETRIES = 6
local weatherReading, weatherCity, weatherProblem = nil, nil, nil
local weatherBarShown = nil

local function drawWeatherBar()
  local properties = { "drawing=off" }
  if weatherReading then
    properties = { "drawing=on", "icon=" .. weatherReading.icon, "label=" .. weather.barLabel(weatherReading) }
  end
  local key = table.concat(properties, "\n")
  if key == weatherBarShown then return end
  weatherBarShown = key
  local arguments = { "--set", "weather" }
  for _, property in ipairs(properties) do arguments[#arguments + 1] = property end
  arguments[#arguments + 1] = "--trigger"
  arguments[#arguments + 1] = "bar_fit"
  hs.task.new(SKETCHYBAR, nil, arguments):start()
end

local function showWeather()
  showPanel("weather", anchored(weather.WIDTH, weather.height(weatherReading)),
    weather.html(weatherReading, weatherCity, weatherProblem), function() closePanel() end)
end

local function weatherChanged()
  drawWeatherBar()
  if panel and panel.name == "weather" then showWeather() end
end

local function fetchWeather(location)
  -- Two decimals is about a kilometre: close enough for weather, and no more exact than needed.
  local url = weather.url(string.format("%.2f", location.latitude), string.format("%.2f", location.longitude))
  hs.http.asyncGet(url, nil, function(status, body)
    local ok, data = pcall(hs.json.decode, body or "")
    local reading = status == 200 and ok and weather.reading(data) or nil
    if reading then
      weatherReading, weatherProblem = reading, nil
    else
      weatherProblem = status == 200 and "Couldn't read the weather" or "No connection"
    end
    weatherChanged()
  end)
  hs.location.geocoder.lookupLocation(location, function(found, places)
    if not found or not places or not places[1] then return end
    weatherCity = places[1].locality or places[1].name
    weatherChanged()
  end)
end

local function locationProblem()
  if not hs.location.servicesEnabled() then return "Turn on Location Services in System Settings" end
  local status = hs.location.authorizationStatus()
  if status == "denied" or status == "restricted" then return "Allow Location for Hammerspoon in System Settings" end
  return nil
end

local function readWeather(tries)
  tries = tries or 0
  local problem = locationProblem()
  if problem then
    weatherProblem = problem
    return weatherChanged()
  end
  hs.location.start()
  local location = hs.location.get()
  -- One fix is enough, so Location Services isn't kept running between readings.
  if location then
    hs.location.stop()
    return fetchWeather(location)
  end
  -- The first fix, or the permission answer, can take a few seconds.
  if tries < LOCATION_RETRIES then
    hs.timer.doAfter(LOCATION_RETRY_SECONDS, function() readWeather(tries + 1) end)
  else
    hs.location.stop()
    weatherProblem = "Couldn't find your location"
    weatherChanged()
  end
end

local function toggleWeather()
  if panel and panel.name == "weather" then return closePanel() end
  showWeather()
  readWeather()
end

-- Globals, so the timer and the watcher are never garbage-collected.
omvWeatherTimer = hs.timer.doEvery(WEATHER_REFRESH_SECONDS, function() readWeather() end)
omvWeatherWakeWatcher = hs.caffeinate.watcher.new(function(event)
  if event == hs.caffeinate.watcher.systemDidWake then readWeather() end
end):start()
readWeather()

-- Battery card (click the battery icon, Option+Shift+B)

local BATTERY_SETTINGS = "x-apple.systempreferences:com.apple.Battery-Settings.extension"

local function onBatteryMessage(message)
  closePanel()
  if message.type == "choose" then open({ BATTERY_SETTINGS })() end
end

local function showBattery()
  local status = battery.parseBatt(hs.execute("/usr/bin/pmset -g batt"))
  if not status then return hs.alert.show("This Mac has no battery", ALERT_STYLE, 1.5) end
  local health = battery.parseSmartBattery(hs.execute("/usr/sbin/ioreg -rn AppleSmartBattery"))
  showPanel("battery", anchored(battery.WIDTH, battery.HEIGHT), battery.html(battery.model(status, health)), onBatteryMessage)
end

local function toggleBattery()
  if panel and panel.name == "battery" then return closePanel() end
  showBattery()
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
bindKey(SUPER_SHIFT, "s", "Option+Shift+S", "Capture the screen", toggleCapture)
bindKey(SUPER_SHIFT, "m", "Option+Shift+M", "Set a reminder", newReminder)
bindKey(SUPER_SHIFT, "space", "Option+Shift+Space", "Show or hide the bar", run(SKETCHYBAR, { "--bar", "hidden=toggle" }))
bindKey(SUPER_SHIFT, "w", "Option+Shift+W", "Wi-Fi card", toggleWifi)
bindKey(SUPER_SHIFT, "e", "Option+Shift+E", "Ethernet card", toggleEthernet)
bindKey(SUPER_SHIFT, "v", "Option+Shift+V", "Sound card", toggleSound)
bindKey(SUPER_SHIFT, "o", "Option+Shift+O", "Weather card", toggleWeather)
bindKey(SUPER_SHIFT, "b", "Option+Shift+B", "Battery card", toggleBattery)
bindKey(SUPER, "escape", "Option+Escape", "System menu", toggleSystemMenu)
bindKey(SUPER, "space", "Option+Space", "Go to any window", toggleWindows)

-- Now playing: Music and Spotify announce every track and play-state change, so the bar
-- redraws only then. Global, so the watchers are never garbage-collected.
omvMediaWatchers = {}
for _, name in ipairs({ "com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged" }) do
  omvMediaWatchers[#omvMediaWatchers + 1] = hs.distributednotifications.new(run(SKETCHYBAR, { "--trigger", "now_playing_change" }), name):start()
end

-- Ghostty owns this key, so it is listed here rather than bound.
launchers[#launchers + 1] = { label = "Option+`", description = "Drop-down terminal" }

-- 44 is the physical "/" key, so this stays the same key on the Turkish layout.
bindKey(SUPER, 44, "Option+/", "Show or hide this list", toggleKeyList)
-- Running it from the list would only open the list again.
launchers[#launchers].runs = false

-- Scripts open the cards with hs -c, for example the bar's clock: hs -c 'omvToggleCalendar()'.
-- Each call waits for the next run-loop turn, because drawing a card inside the hs -c
-- request makes that request call back into itself.
local function later(fn)
  return function() hs.timer.doAfter(0, fn) end
end

omvToggleSystemMenu = later(toggleSystemMenu)
omvToggleSound = later(toggleSound)
omvToggleWifi = later(toggleWifi)
omvToggleEthernet = later(toggleEthernet)
omvToggleWeather = later(toggleWeather)
omvToggleBattery = later(toggleBattery)
omvToggleKeyList = later(toggleKeyList)
omvToggleCalendar = later(toggleCalendar)
omvToggleWindows = later(toggleWindows)
omvToggleCapture = later(toggleCapture)
omvToggleReminders = later(toggleReminders)
omvNewReminder = later(newReminder)
