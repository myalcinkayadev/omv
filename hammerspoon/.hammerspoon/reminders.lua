-- Quick reminders: reading "25m check deploy", the bar label, and the saved file.
-- init.lua runs the timers. Has no Hammerspoon dependency, so the Lua tests can run it.

local reminders = {}

local UNIT_SECONDS = { h = 3600, m = 60, s = 1 }

-- Returns seconds and text for "1h30m stand up", or nil when it doesn't start with a time.
function reminders.parse(input)
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

-- 10 fits beside the notch even when the Claude item shows its wider reset times.
local SHORT_CHARACTERS = 10

-- A due reminder's text in the bar, cut so it can't reach the notch either.
-- Counts UTF-8 characters, so a cut never splits a Turkish letter.
function reminders.short(text)
  local characters = {}
  for character in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do characters[#characters + 1] = character end
  if #characters <= SHORT_CHARACTERS then return text end
  return table.concat(characters, "", 1, SHORT_CHARACTERS - 1) .. "…"
end

-- One reminder per line: due time, a tab, then the text.
function reminders.encode(list)
  local lines = {}
  for _, reminder in ipairs(reminders.sorted(list)) do
    lines[#lines + 1] = reminder.due .. "\t" .. reminder.text:gsub("[\t\n]", " ")
  end
  return table.concat(lines, "\n")
end

-- Reminders already past are dropped, since their moment is gone.
function reminders.decode(text, now)
  local list = {}
  for due, message in text:gmatch("(%d+)\t([^\n]*)") do
    if tonumber(due) > now then list[#list + 1] = { due = tonumber(due), text = message } end
  end
  return reminders.sorted(list)
end

return reminders
