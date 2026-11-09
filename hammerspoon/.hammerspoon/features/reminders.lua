-- Quick reminders (Option+Shift+M) and Pomodoro breaks. The bar shows the soonest reminder;
-- clicking it lists them. They are saved to a file, so they survive a reload of this config.
-- Pomodoros are reminders too: one coming due opens "Time for a break.", and nothing after it
-- starts on its own: the break, the next pomo and stopping are all picked on a card.

local shell = require("shell")
local card = require("card")
local reminders = require("reminders")
local pomo = require("pomo")

local feature = {}

local REMINDERS_FILE = shell.STATE_DIR .. "/reminders"
local POMO_FILE = shell.STATE_DIR .. "/pomo"
local REMINDER_FLASH_SECONDS = 10
local REMINDER_WIDTH = 480
local BLACK, WHITE = shell.BLACK, shell.WHITE

local reminderList = {}
local reminderTimer = nil
local flashUntil = nil
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

-- A due reminder notifies, and turns the bar item into a white pill for a moment.
-- Pomodoro reminders open their cards instead.
local function fireReminder(reminder)
  if reminder.kind then return onPomoReminder(reminder) end
  hs.notify.new({ title = "Reminder", informativeText = reminder.text, withdrawAfter = 0 }):send()
  shell.alert("󰔛 " .. reminder.text, 4)
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
  shell.close()
  local soonest = table.remove(reminderList, 1)
  if not soonest then return shell.alert("No reminders", 1.5) end
  saveReminders()
  startReminders()
  shell.alert("Cancelled: " .. soonest.text, 1.5)
end

local function onReminderInput(message)
  if message.type == "close" then return shell.close() end
  if message.type ~= "submit" then return end
  local seconds, text, kind = reminders.parse(message.id)
  if kind == "cancel" then return cancelSoonestReminder() end
  if not seconds then
    shell.alert("Start with a time, like 25m", 1.5)
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
  local screen = { prompt = "Remind me…", rows = {}, input = true, hint = "25m check deploy · pomo · b break · c cancel" }
  shell.show("reminder", shell.centered(REMINDER_WIDTH, 28 + 46 + 44 + 4), card.html(screen), onReminderInput)
end

local function onReminderList(message)
  if message.type ~= "choose" then return shell.close() end
  table.remove(reminderList, tonumber(message.id))
  saveReminders()
  shell.close()
  startReminders()
end

function feature.toggle()
  if shell.isOpen("reminders") then return shell.close() end
  -- During a break, the bar item reopens its countdown.
  if reminderList[1] and reminderList[1].kind == "break" then return onPomoReminder({ kind = "show-break" }) end
  if #reminderList == 0 then return feature.new() end
  local now, rows = os.time(), {}
  for index, reminder in ipairs(reminderList) do
    rows[index] = { id = tostring(index), icon = "󰔛", label = reminder.text, hint = reminders.left(reminder.due - now) }
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

-- A restarted bar has lost the item, so the next tick sends it again whatever its shape.
function feature.redrawBar()
  reminderShape = nil
  tickReminders()
end

-- Redraw even with none saved, so a reload clears an item left over from before.
reminderList = loadReminders()
if #reminderList > 0 then startReminders() else tickReminders() end

return feature
