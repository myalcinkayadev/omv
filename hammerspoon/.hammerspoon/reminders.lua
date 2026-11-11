-- Quick reminders: reading "25m check deploy", the bar label, and the saved file.
-- init.lua runs the timers. Has no Hammerspoon dependency, so the Lua tests can run it.

local reminders = {}

local UNIT_SECONDS = { h = 3600, m = 60, s = 1 }

-- Words that stand for a time and a kind: "pomo" is a 25-minute focus block, "break" the
-- 5 minutes after it. Text after the word names the task, as in "pomo write tests".
-- A kind tells init.lua to open the Pomodoro cards instead of the usual pill.
local PRESETS = {
  pomo = { seconds = 25 * 60, text = "Pomodoro", kind = "pomo" },
  ["break"] = { seconds = 5 * 60, text = "Break", kind = "break" },
  b = { seconds = 5 * 60, text = "Break", kind = "break" },
}

-- Seconds from now until the next hour:minute, today or else tomorrow, or nil for a time
-- that doesn't exist, such as 25:00.
local function untilClock(hour, minute, now)
  hour, minute = tonumber(hour), tonumber(minute)
  if hour > 23 or minute > 59 then return nil end
  local target = os.date("*t", now)
  target.hour, target.min, target.sec = hour, minute, 0
  local at = os.time(target)
  if at <= now then
    target.day = target.day + 1
    at = os.time(target)
  end
  return at - now
end

-- Returns seconds, text and kind (nil for a plain reminder) for "1h30m stand up", "14:30
-- call" or "pomo", or nil when it doesn't start with a time or a preset. A clock time
-- already past today means tomorrow; now is the current time, for clock times.
-- Short forms: "r 25m ..." is a reminder, "b" a break, and "c" alone returns nil, nil, "cancel".
function reminders.parse(input, now)
  if input:match("^%s*[cC]%s*$") then return nil, nil, "cancel" end
  local rest = input:match("^%s*[rR]%s+(.+)$")
  if rest then input = rest end
  local hour, minute, after = input:match("^%s*(%d%d?):(%d%d)%s+(.-)%s*$")
  if not hour then hour, minute = input:match("^%s*(%d%d?):(%d%d)%s*$") end
  if hour then
    local seconds = untilClock(hour, minute, now)
    if not seconds then return nil end
    return seconds, (after and after ~= "") and after or "Reminder"
  end
  local word, after = input:match("^%s*(%a+)%s+(.-)%s*$")
  if not word then word, after = input:match("^%s*(%a+)%s*$"), "" end
  local preset = word and PRESETS[word:lower()]
  if preset then return preset.seconds, after ~= "" and after or preset.text, preset.kind end
  local duration, rest = input:match("^%s*([%dhms]+)%s*(.-)%s*$")
  if not duration or not duration:match("^%d") then return nil end
  if rest ~= "" and not input:match("^%s*[%dhms]+%s") then return nil end
  local seconds = 0
  local consumed = duration:gsub("(%d+)([hms])", function(amount, unit)
    seconds = seconds + tonumber(amount) * UNIT_SECONDS[unit]
    return ""
  end)
  if consumed ~= "" or seconds <= 0 then return nil end
  return seconds, rest ~= "" and rest or "Reminder"
end

-- 24:13 under an hour, 2:05 (hours and minutes) from an hour up.
function reminders.left(seconds)
  seconds = math.max(0, math.floor(seconds))
  if seconds >= 3600 then
    return string.format("%d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
  end
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- A reminder that came due stays until it is dismissed or snoozed: "due" when it fired
-- on time, "late" when its time passed while Hammerspoon wasn't running.
local DUE_KINDS = { due = true, late = true }

function reminders.isDue(reminder)
  return DUE_KINDS[reminder.kind] == true
end

local function waitingOnly(list)
  local waiting = {}
  for _, reminder in ipairs(list) do
    if not reminders.isDue(reminder) then waiting[#waiting + 1] = reminder end
  end
  return waiting
end

-- A plain reminder whose time came: it now waits for you instead of for its time.
function reminders.fire(reminder)
  return { due = reminder.due, text = reminder.text, kind = "due" }
end

-- The same reminder, due again seconds from now.
function reminders.snooze(reminder, now, seconds)
  return { due = now + seconds, text = reminder.text }
end

function reminders.sorted(list)
  local copy = {}
  for index, reminder in ipairs(list) do copy[index] = reminder end
  table.sort(copy, function(a, b) return a.due < b.due end)
  return copy
end

-- The soonest reminder's time left, then +N for the others. The text stays out: the
-- right side of the bar is full, and a longer label would run under the notch.
function reminders.label(list, now)
  list = waitingOnly(list)
  if #list == 0 then return "" end
  local label = reminders.left(reminders.sorted(list)[1].due - now)
  if #list > 1 then label = label .. " +" .. (#list - 1) end
  return label
end

-- The bar's icon for the soonest reminder: a coffee cup during a break, a target while a
-- pomo runs, and a timer for anything else, so the three never look alike.
local ICONS = { ["break"] = "󰅶", pomo = "󰣉", postponed = "󰣉" }
local TIMER = "󰔛"

function reminders.icon(list)
  local soonest = reminders.sorted(waitingOnly(list))[1]
  return soonest and ICONS[soonest.kind] or TIMER
end

-- 10 fits beside the notch even when the Claude item shows its wider reset times.
local SHORT_CHARACTERS = 10

-- A due reminder's text in the bar, cut so it can't reach the notch either.
-- Counts UTF-8 characters, so a cut never splits a Turkish letter.
function reminders.short(text)
  local characters = {}
  for character in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do characters[#characters + 1] = character end
  if #characters <= SHORT_CHARACTERS then return text end
  -- Spaces before the cut are dropped, so it reads "Pomodoro…", not "Pomodoro …".
  return (table.concat(characters, "", 1, SHORT_CHARACTERS - 1):gsub("%s+$", "")) .. "…"
end

-- Due reminders, the one waiting longest first.
function reminders.dueList(list)
  local due = {}
  for _, reminder in ipairs(reminders.sorted(list)) do
    if reminders.isDue(reminder) then due[#due + 1] = reminder end
  end
  return due
end

-- The bar's pill while reminders are due: the oldest one's text, cut to fit, then +N.
function reminders.dueLabel(list)
  local due = reminders.dueList(list)
  if #due == 0 then return nil end
  local label = reminders.short(due[1].text)
  if #due > 1 then label = label .. " +" .. (#due - 1) end
  return label
end

-- The large card a due reminder opens, from a click on its pill. Dismiss is picked first.
function reminders.dueScreen(reminder)
  local when = (reminder.kind == "late" and "LATE · WAS " or "DUE ") .. os.date("%H:%M", reminder.due)
  return {
    kicker = "REMINDER · " .. when,
    title = reminder.text,
    rows = {
      { id = "due.dismiss", icon = "󰄬", label = "Dismiss", hint = "↵" },
      { id = "due.snooze5", icon = "󰔛", label = "Snooze 5 minutes", key = "s", hint = "s" },
      { id = "due.snooze15", icon = "󰔛", label = "Snooze 15 minutes", key = "l", hint = "l" },
    },
    selected = 1,
  }
end

-- One reminder per line: due time, the text, then the kind when it has one, and after the
-- kind a break's length in seconds, split by tabs.
function reminders.encode(list)
  local lines = {}
  for _, reminder in ipairs(reminders.sorted(list)) do
    local line = reminder.due .. "\t" .. reminder.text:gsub("[\t\n]", " ")
    if reminder.kind then line = line .. "\t" .. reminder.kind end
    if reminder.kind and reminder.length then line = line .. "\t" .. reminder.length end
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n")
end

-- A plain reminder whose time passed while Hammerspoon wasn't running comes back late,
-- marked missed so it is announced once. Pomodoros and breaks already past are dropped,
-- since their moment is gone.
function reminders.decode(text, now)
  local list = {}
  for due, rest in text:gmatch("(%d+)\t([^\n]*)") do
    local message, kind, length = rest:match("^([^\t]*)\t(%a+)\t(%d+)$")
    if not message then message, kind = rest:match("^([^\t]*)\t(%a+)$") end
    local reminder = { due = tonumber(due), text = message or rest, kind = kind, length = length and tonumber(length) }
    if reminder.due > now or reminders.isDue(reminder) then
      list[#list + 1] = reminder
    elseif not kind then
      reminder.kind, reminder.missed = "late", true
      list[#list + 1] = reminder
    end
  end
  return reminders.sorted(list)
end

return reminders
