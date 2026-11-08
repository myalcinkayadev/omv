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
    elseif panel.hadFocus and not panel.keepOnBlur then
      panel.previous = nil
      closePanel()
    end
  end)
end

-- options.onEscape replaces closing on Escape, and options.keepOnBlur keeps the card open
-- when focus moves away. The Pomodoro cards use both: a break shouldn't vanish on Cmd+Tab.
local function showPanel(name, frame, html, onMessage, options)
  options = options or {}
  if panel then
    panel.name, panel.onMessage = name, onMessage
    panel.onEscape, panel.keepOnBlur = options.onEscape, options.keepOnBlur
    view:frame(frame):html(html)
    return
  end
  panel = { name = name, onMessage = onMessage, previous = hs.application.frontmostApplication(),
    onEscape = options.onEscape, keepOnBlur = options.keepOnBlur }
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

-- Output devices change as AirPods connect or a monitor is plugged in, so the Sound
-- screen is read each time it opens.
local function soundScreen()
  local current = hs.audiodevice.defaultOutputDevice()
  local currentUid = current and current:uid()
  local devices = {}
  for _, device in ipairs(hs.audiodevice.allOutputDevices()) do
    devices[#devices + 1] = {
      uid = device:uid(),
      name = device:name(),
      transport = device:transportType(),
      current = device:uid() == currentUid,
    }
  end
  return menu.sound(devices)
end

local function setOutput(uid)
  local device = hs.audiodevice.findDeviceByUID(uid)
  if device and device:setDefaultOutputDevice() then
    hs.alert.show("󰕾 " .. device:name(), ALERT_STYLE, 1.2)
  else
    hs.alert.show("Couldn't switch the sound output", ALERT_STYLE, 1.5)
  end
end

local function screenFor(key)
  if key == "sound" then return soundScreen() end
  local confirmed = key:match("^confirm:(.+)$")
  if confirmed then return menu.confirm(confirmed) end
  return menu.screen(key)
end

local onMenuMessage

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
  if menu.opens(id) then
    menuStack[#menuStack + 1] = id
    return showMenuTop()
  end
  if menu.needsConfirm(id) then
    menuStack[#menuStack + 1] = "confirm:" .. id
    return showMenuTop()
  end
  local action = ACTIONS[id]
  local output = id:match("^sound%.(.+)$")
  if output then action = function() setOutput(output) end end
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

-- Opens straight on Sound, with the system menu under it, so Left goes back to it.
local function toggleSound()
  if panel and panel.name == "menu" and menuStack[#menuStack] == "sound" then return closePanel() end
  menuStack = { "system", "sound" }
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

local function setReminderBar(properties)
  hs.task.new(SKETCHYBAR, nil, { "--set", "reminder", table.unpack(properties) }):start()
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
  setReminderBar({ "drawing=on", "icon=" .. reminders.icon(reminderList), "background.drawing=off", "icon.color=" .. WHITE, "label.color=" .. WHITE,
    "label=" .. reminders.label(reminderList, now) })
end

reminderTimer = hs.timer.new(1, tickReminders)

local function startReminders()
  tickReminders()
  if not reminderTimer:running() then reminderTimer:start() end
end

local function onReminderInput(message)
  if message.type == "close" then return closePanel() end
  if message.type ~= "submit" then return end
  local seconds, text, kind = reminders.parse(message.id)
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
  local screen = { prompt = "Remind me…", rows = {}, input = true, hint = "25m check deploy · 1h30m stand up · pomo" }
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
  if id == "break.start" then return startBreak(pomo.BREAK_SECONDS) end
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
    pomoStep = { step = "break", task = pomoStep and pomoStep.task, ends = current.due, seconds = pomo.BREAK_SECONDS }
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
  local screen = hs.screen.mainScreen():fullFrame()
  -- Right-aligned under the clock, just below the 36pt bar.
  local now = os.time()
  local frame = hs.geometry.rect(screen.x + screen.w - CALENDAR_WIDTH - 10, screen.y + 40, CALENDAR_WIDTH, calendar.height(agendaDay, now))
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

-- Scripts open the cards with hs -c, for example the bar's clock: hs -c 'omvToggleCalendar()'.
-- Each call waits for the next run-loop turn, because drawing a card inside the hs -c
-- request makes that request call back into itself.
local function later(fn)
  return function() hs.timer.doAfter(0, fn) end
end

omvToggleSystemMenu = later(toggleSystemMenu)
omvToggleSound = later(toggleSound)
omvToggleKeyList = later(toggleKeyList)
omvToggleCalendar = later(toggleCalendar)
omvToggleWindows = later(toggleWindows)
omvToggleCapture = later(toggleCapture)
omvToggleReminders = later(toggleReminders)
omvNewReminder = later(newReminder)
