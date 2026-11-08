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

-- Returns seconds, text and kind (nil for a plain reminder) for "1h30m stand up" or
-- "pomo", or nil when it doesn't start with a time or a preset. Short forms: "r 25m ..."
-- is a reminder, "b" a break, and "c" alone returns nil, nil, "cancel".
function reminders.parse(input)
  if input:match("^%s*[cC]%s*$") then return nil, nil, "cancel" end
  local rest = input:match("^%s*[rR]%s+(.+)$")
  if rest then input = rest end
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

function reminders.sorted(list)
  local copy = {}
  for index, reminder in ipairs(list) do copy[index] = reminder end
  table.sort(copy, function(a, b) return a.due < b.due end)
  return copy
end

-- The soonest reminder's time left, then +N for the others. The text stays out: the
-- right side of the bar is full, and a longer label would run under the notch.
function reminders.label(list, now)
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
  local soonest = reminders.sorted(list)[1]
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

-- One reminder per line: due time, the text, then the kind when it has one, split by tabs.
function reminders.encode(list)
  local lines = {}
  for _, reminder in ipairs(reminders.sorted(list)) do
    local line = reminder.due .. "\t" .. reminder.text:gsub("[\t\n]", " ")
    if reminder.kind then line = line .. "\t" .. reminder.kind end
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n")
end

-- Reminders already past are dropped, since their moment is gone.
function reminders.decode(text, now)
  local list = {}
  for due, rest in text:gmatch("(%d+)\t([^\n]*)") do
    local message, kind = rest:match("^([^\t]*)\t(%a+)$")
    if tonumber(due) > now then list[#list + 1] = { due = tonumber(due), text = message or rest, kind = kind } end
  end
  return reminders.sorted(list)
end

return reminders
