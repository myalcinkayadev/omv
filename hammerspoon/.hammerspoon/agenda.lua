-- Today's Calendar.app events: reading agenda.sh's output, the rows under the calendar
-- card, and the next-meeting item in the bar. init.lua runs agenda.sh and the timers.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local agenda = {}

-- The bar shows a meeting from an hour before it starts, and turns it into a white pill
-- from 5 minutes before until 5 minutes after.
agenda.LOOKAHEAD = 60 * 60
agenda.SOON = 5 * 60
-- The card lists at most this many, then "+N more".
agenda.LISTED = 5

local function before(a, b)
  if a.allDay ~= b.allDay then return a.allDay end
  if a.start ~= b.start then return a.start < b.start end
  return a.title < b.title
end

-- agenda.sh prints one event per line, start, end, all-day and title split by tabs, or
-- the single word "denied" when Calendar access was refused.
function agenda.decode(text)
  if text:match("^denied") then return { denied = true, events = {} } end
  local events = {}
  for start, finish, allDay, title in text:gmatch("(%d+)\t(%d+)\t([01])\t([^\n]*)") do
    events[#events + 1] = {
      start = tonumber(start),
      finish = tonumber(finish),
      allDay = allDay == "1",
      title = title ~= "" and title or "Event",
    }
  end
  table.sort(events, before)
  return { denied = false, events = events }
end

-- Rows for the calendar card: { time, title, past, current }, plus how many were left out.
-- When there are too many, events already over go first, since they matter least.
function agenda.rows(day, now)
  local events = {}
  for index, event in ipairs(day.events) do events[index] = event end
  while #events > agenda.LISTED do
    local dropped = false
    for index, event in ipairs(events) do
      if not event.allDay and event.finish <= now then
        table.remove(events, index)
        dropped = true
        break
      end
    end
    if not dropped then break end
  end
  local rows = {}
  for index = 1, math.min(#events, agenda.LISTED) do
    local event = events[index]
    rows[index] = {
      time = event.allDay and "all day" or os.date("%H:%M", event.start),
      title = event.title,
      past = not event.allDay and event.finish <= now,
      current = not event.allDay and event.start <= now and now < event.finish,
    }
  end
  return rows, #day.events - #rows
end

-- The next meeting for the bar, as { label, soon }, or nil while none is close.
-- The label is only the start time: with a title, the right side of the bar ran under
-- the notch next to a reminder. The title is in the calendar card, a click away.
-- All-day events are left out: they have no time to be late for.
function agenda.bar(events, now)
  for _, event in ipairs(events) do
    if not event.allDay and event.start + agenda.SOON > now and event.start - now <= agenda.LOOKAHEAD then
      return {
        label = os.date("%H:%M", event.start),
        soon = event.start - now <= agenda.SOON,
      }
    end
  end
  return nil
end

return agenda
