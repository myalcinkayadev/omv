-- Meeting mode: while a meeting runs, Do Not Disturb is on, the music is paused, agents'
-- notices wait, and the apps on the chat and music workspaces are hidden, so a shared
-- screen shows none of them. It starts when you join a meeting, or when one with a call
-- link starts, and ends when the meeting does. Leaving undoes only what entering changed:
-- a Focus you had on, or an app you had hidden, stays as it was.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local meeting = {}

-- The workspaces whose apps are hidden: chat, and music.
meeting.HIDDEN_WORKSPACES = { "5", "6" }
meeting.PLAYERS = { "Music", "Spotify" }
-- A meeting that started longer ago than this doesn't start meeting mode on its own: it was
-- probably left, or Hammerspoon reloaded during it.
meeting.LATE = 5 * 60

-- A meeting's key, so one that was left or ended isn't started again.
function meeting.key(event)
  return tostring(event.start) .. "\t" .. tostring(event.title)
end

-- The meeting that should start meeting mode now, or nil: one with a call link that started
-- within the last 5 minutes and hasn't ended, that hasn't been handled.
function meeting.due(events, now, handled)
  for _, event in ipairs(events or {}) do
    if not event.allDay and event.link and event.start <= now and now < event.finish
      and now - event.start <= meeting.LATE and not (handled or {})[meeting.key(event)] then
      return event
    end
  end
  return nil
end

-- The meeting going on now that you joined: the one whose call link it was, else the first
-- one running with a link. nil when none runs, so a join outside a meeting changes nothing.
function meeting.joined(events, now, link)
  local running = nil
  for _, event in ipairs(events or {}) do
    if not event.allDay and event.link and event.start - 5 * 60 <= now and now < event.finish then
      if event.link == link then return event end
      running = running or event
    end
  end
  return running
end

-- `aerospace list-windows --format %{app-bundle-id}`: the apps, once each, in order.
function meeting.apps(output)
  local seen, apps = {}, {}
  for bundle in tostring(output or ""):gmatch("[^\n]+") do
    bundle = bundle:match("^%s*(.-)%s*$")
    if bundle ~= "" and not seen[bundle] then
      seen[bundle] = true
      apps[#apps + 1] = bundle
    end
  end
  return apps
end

-- What entering changes, from what is so now: observed = { focusOn, playing = { "Music" },
-- shown = { bundle ids not hidden } }. The record keeps what to undo.
function meeting.enter(observed)
  return {
    focus = not observed.focusOn,
    paused = observed.playing or {},
    hidden = observed.shown or {},
  }
end

-- What leaving does, from the record and what is so now: observed = { focusOn,
-- paused = { players paused now } }. A Focus switched off already, or a player you started
-- again or quit, is left alone.
function meeting.leave(record, observed)
  local stillPaused = {}
  for _, player in ipairs(observed.paused or {}) do stillPaused[player] = true end
  local resume = {}
  for _, player in ipairs(record.paused or {}) do
    if stillPaused[player] then resume[#resume + 1] = player end
  end
  return {
    focus = record.focus and observed.focusOn == true,
    resume = resume,
    unhide = record.hidden or {},
  }
end

return meeting
