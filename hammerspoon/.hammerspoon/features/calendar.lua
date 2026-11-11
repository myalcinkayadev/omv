-- Calendar (click the clock), today's events, the bar's next meeting, and joining a meeting.
-- Today's events come from agenda.sh. They are read every 5 minutes, on wake and when the
-- calendar opens; the bar's next-meeting item is redrawn from them every 30 seconds.

local shell = require("shell")
local card = require("card")
local calendar = require("calendar")
local agenda = require("agenda")

local feature = {}

local AGENDA = hs.configdir .. "/agenda.sh"
local CALENDAR_WIDTH = 360
local AGENDA_REFRESH_SECONDS = 300
local MEETING_REDRAW_SECONDS = 30

local shown = nil
local agendaDay = nil
local agendaText = nil
local agendaTask = nil
local meetingShown = nil

local function today()
  local now = os.date("*t")
  return { year = now.year, month = now.month, day = now.day }
end

local onCalendarMessage

local function showCalendar()
  local now = os.time()
  local frame = shell.anchored(CALENDAR_WIDTH, calendar.height(agendaDay, now), "clock")
  local model = calendar.month(shown.year, shown.month, today())
  shell.show("calendar", frame, calendar.html(model, today(), agendaDay, now), onCalendarMessage)
end

local function drawMeeting()
  local meeting = agendaDay and agenda.bar(agendaDay.events, os.time())
  local properties
  if not meeting then
    properties = { "drawing=off" }
  elseif meeting.soon then
    properties = { "drawing=on", "label=" .. meeting.label, "background.drawing=on", "icon.color=" .. shell.BLACK, "label.color=" .. shell.BLACK }
  else
    properties = { "drawing=on", "label=" .. meeting.label, "background.drawing=off", "icon.color=" .. shell.WHITE, "label.color=" .. shell.WHITE }
  end
  -- Only a change reaches SketchyBar, since most redraws find the same meeting.
  local key = table.concat(properties, "\n")
  if key == meetingShown then return end
  meetingShown = key
  properties[#properties + 1] = "--trigger"
  properties[#properties + 1] = "bar_fit"
  hs.task.new(shell.SKETCHYBAR, nil, { "--set", "meeting", table.unpack(properties) }):start()
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
  if shell.isOpen("calendar") then showCalendar() end
end

onCalendarMessage = function(message)
  if message.type == "close" then return shell.close() end
  if message.type == "today" then shown = today() end
  if message.type == "shift" then
    shown.year, shown.month = calendar.shift(shown.year, shown.month, tonumber(message.id))
  end
  showCalendar()
end

function feature.toggle()
  if shell.isOpen("calendar") then return shell.close() end
  shown = today()
  showCalendar()
  readAgenda(redrawOpenCalendar)
end

-- Join a meeting (Option+Shift+C, or a click on the meeting in the bar): one meeting with a
-- call link opens it, several list them, and none opens the calendar card instead.
function feature.join()
  if shell.isOpen("join") then return shell.close() end
  local meetings = agendaDay and agenda.joinable(agendaDay.events, os.time()) or {}
  if #meetings == 0 then return feature.toggle() end
  if #meetings == 1 then return shell.open({ meetings[1].link })() end
  local rows = agenda.joinRows(meetings)
  shell.show("join", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows, #rows)),
    card.html({ prompt = "Join…", rows = rows, compact = true }), function(message)
      if message.type ~= "choose" then return shell.close() end
      -- Leave focus to the call app, rather than handing it back to the app open before.
      shell.leaveFocus()
      shell.close()
      shell.open({ message.id })()
    end)
end

-- A restarted bar has lost the item, so the meeting is sent again even if unchanged.
function feature.redrawBar()
  meetingShown = nil
  drawMeeting()
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

return feature
