-- Quick reminders (Option+Shift+M) and Pomodoro breaks. The bar shows the soonest reminder;
-- clicking it lists them. A reminder that comes due stays as a white pill until you click
-- it and dismiss or snooze it. They are saved to a file, so they survive a reload of this config.
-- Pomodoros are reminders too: one coming due opens "Time for a break.", and nothing after it
-- starts on its own: the break, the next pomo and stopping are all picked on a card.

local shell = require("shell")
local card = require("card")
local reminders = require("reminders")
local pomo = require("pomo")

local feature = {}

local REMINDERS_FILE = shell.STATE_DIR .. "/reminders"
local POMO_FILE = shell.STATE_DIR .. "/pomo"
local SNOOZE = { ["due.snooze5"] = 5 * 60, ["due.snooze15"] = 15 * 60 }
local REMINDER_WIDTH = 480
local BLACK, WHITE = shell.BLACK, shell.WHITE

local reminderList = {}
local reminderTimer = nil
-- Set below, with the Pomodoro cards, which add and remove reminders themselves.
local onPomoReminder

local function saveReminders()
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
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
  hs.task.new(shell.SKETCHYBAR, nil, arguments):start()
end

local function announce(reminder, title)
  hs.notify.new({ title = title, informativeText = reminder.text, withdrawAfter = 0 }):send()
  shell.alert("󰔛 " .. reminder.text, 4)
end

-- A plain reminder that comes due notifies and stays, as due, until you deal with it.
-- Pomodoro reminders open their cards instead, and leave the list.
local function fireReminder(reminder)
  if reminder.kind then
    onPomoReminder(reminder)
    return nil
  end
  announce(reminder, "Reminder")
  return reminders.fire(reminder)
end

-- The first waiting reminder, after any due ones, or nil.
local function soonestWaiting()
  for _, reminder in ipairs(reminderList) do
    if not reminders.isDue(reminder) then return reminder end
  end
end

local function tickReminders()
  local now = os.time()
  local kept, changed = {}, false
  for _, reminder in ipairs(reminderList) do
    if reminder.due <= now and not reminders.isDue(reminder) then
      kept[#kept + 1] = fireReminder(reminder)
      changed = true
    else
      kept[#kept + 1] = reminder
    end
  end
  if changed then
    reminderList = reminders.sorted(kept)
    saveReminders()
  end
  -- Due reminders win the bar: a white pill with the oldest one's text, until it is dealt with.
  local dueLabel = reminders.dueLabel(reminderList)
  if dueLabel then
    setReminderBar({ "drawing=on", "icon=󰔛", "label=" .. dueLabel, "background.drawing=on",
      "icon.color=" .. BLACK, "label.color=" .. BLACK })
  end
  local soonest = soonestWaiting()
  if not soonest then
    if not dueLabel then setReminderBar({ "drawing=off", "background.drawing=off" }) end
    reminderTimer:stop()
    return
  end
  if dueLabel then return end
  -- A pomo's last 30 seconds turn the item into a white pill, a quiet heads-up.
  local warning = pomo.warning(soonest, now)
  local text = warning and BLACK or WHITE
  setReminderBar({ "drawing=on", "icon=" .. reminders.icon(reminderList), "background.drawing=" .. (warning and "on" or "off"),
    "icon.color=" .. text, "label.color=" .. text, "label=" .. reminders.label(reminderList, now) })
end

reminderTimer = hs.timer.new(1, tickReminders)

local function startReminders()
  tickReminders()
  if not reminderTimer:running() then reminderTimer:start() end
end

local function removeReminder(target)
  for index, reminder in ipairs(reminderList) do
    if reminder == target then return table.remove(reminderList, index) end
  end
end

-- "c" in the reminder box cancels the soonest waiting reminder, and says which one.
local function cancelSoonestReminder()
  shell.close()
  local soonest = removeReminder(soonestWaiting())
  if not soonest then return shell.alert("No reminders", 1.5) end
  saveReminders()
  startReminders()
  shell.alert("Cancelled: " .. soonest.text, 1.5)
end

local function onReminderInput(message)
  if message.type == "close" then return shell.close() end
  if message.type ~= "submit" then return end
  local seconds, text, kind = reminders.parse(message.id, os.time())
  if kind == "cancel" then return cancelSoonestReminder() end
  if not seconds then
    shell.alert("Start with a time, like 25m or 14:30", 1.5)
    return
  end
  -- A typed break goes straight to its countdown card.
  if kind == "break" then return onPomoReminder({ kind = "start-break", seconds = seconds }) end
  reminderList[#reminderList + 1] = { due = os.time() + seconds, text = text, kind = kind }
  reminderList = reminders.sorted(reminderList)
  saveReminders()
  shell.close()
  startReminders()
end

function feature.new()
  if shell.isOpen("reminder") then return shell.close() end
  local screen = { prompt = "Remind me…", rows = {}, input = true, hint = "25m · 14:30 call · pomo · b break · c cancel" }
  shell.show("reminder", shell.centered(REMINDER_WIDTH, 28 + 46 + 44 + 4), card.html(screen), onReminderInput)
end

local function onReminderList(message)
  if message.type ~= "choose" then return shell.close() end
  table.remove(reminderList, tonumber(message.id))
  saveReminders()
  shell.close()
  startReminders()
end

-- The due card's picks: Dismiss drops the reminder, a snooze brings it back later.
local function onDueMessage(reminder)
  return function(message)
    if message.type ~= "choose" then return shell.close() end
    removeReminder(reminder)
    local seconds = SNOOZE[message.id]
    if seconds then reminderList[#reminderList + 1] = reminders.snooze(reminder, os.time(), seconds) end
    reminderList = reminders.sorted(reminderList)
    saveReminders()
    shell.close()
    startReminders()
  end
end

local function showDue(reminder)
  shell.show("due", shell.screen():fullFrame(), card.big(reminders.dueScreen(reminder)), onDueMessage(reminder))
end

function feature.toggle()
  if shell.isOpen("reminders", "due") then return shell.close() end
  -- A due reminder opens its card first, the one waiting longest.
  local due = reminders.dueList(reminderList)[1]
  if due then return showDue(due) end
  -- During a break, the bar item reopens its countdown.
  local soonest = soonestWaiting()
  if soonest and soonest.kind == "break" then return onPomoReminder({ kind = "show-break" }) end
  if not soonest then return feature.new() end
  local now, rows = os.time(), {}
  for index, reminder in ipairs(reminderList) do
    rows[#rows + 1] = { id = tostring(index), icon = "󰔛", label = reminder.text, hint = reminders.left(reminder.due - now) }
  end
  local screen = { prompt = "Cancel a reminder…", rows = rows }
  shell.show("reminders", shell.centered(REMINDER_WIDTH, shell.menuHeight(screen)), card.html(screen), onReminderList)
end

-- Pomodoro break cards.

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
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
  local file = io.open(POMO_FILE, "w")
  if not file then return end
  file:write(pomo.encode(pomo.finished(readPomoRecord(), todayKey())))
  file:close()
end

-- A break keeps its length, so its countdown is drawn right when it is reopened.
local function addReminder(seconds, text, kind)
  local length = kind == "break" and seconds or nil
  reminderList[#reminderList + 1] = { due = os.time() + seconds, text = text, kind = kind, length = length }
  reminderList = reminders.sorted(reminderList)
  saveReminders()
  startReminders()
end

-- A plain reminder from another feature, such as the notice when Claude's limit resets.
function feature.add(seconds, text)
  addReminder(seconds, text, nil)
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
  shell.show("pomo", hs.screen.mainScreen():fullFrame(), card.big(screen), onPomoMessage, {
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
  shell.close()
  if id == "pomo.postpone" then addReminder(pomo.POSTPONE_SECONDS, pomo.task(task), "postponed") end
  if id == "pomo.next" then addReminder(pomo.POMO_SECONDS, pomo.task(task), "pomo") end
end

onPomoReminder = function(reminder)
  if reminder.kind == "start-break" then
    pomoStep = { step = "break", task = pomoStep and pomoStep.task }
    return startBreak(reminder.seconds)
  end
  if reminder.kind == "show-break" then
    local current = soonestWaiting()
    pomoStep = { step = "break", task = pomoStep and pomoStep.task, ends = current.due, seconds = pomo.breakLength(current, pomoCount()) }
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

-- A restarted bar has lost the item, so the next tick sends it again whatever its shape.
function feature.redrawBar()
  reminderShape = nil
  tickReminders()
end

-- Redraw even with none saved, so a reload clears an item left over from before.
reminderList = loadReminders()
-- A reminder missed while Hammerspoon wasn't running is announced once, now.
for _, reminder in ipairs(reminderList) do
  if reminder.missed then announce(reminder, "Missed reminder") end
end
if #reminderList > 0 then startReminders() else tickReminders() end

return feature
