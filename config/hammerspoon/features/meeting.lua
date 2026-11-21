-- Meeting mode: Do Not Disturb on, the music paused, agents' notices held back and the apps on
-- workspaces 5 and 6 hidden while a meeting runs; everything it changed comes back when the
-- meeting ends. It starts when you join a meeting, or when one with a call link starts, and
-- the key list and the palette can end it or start it by hand.

local shell = require("shell")
local meeting = require("meeting")
local focus = require("focus")
local quiet = require("quiet")

local feature = {}

local DB = shell.HOME .. "/Library/DoNotDisturb/DB"
local SHORTCUTS = "/usr/bin/shortcuts"
local CHECK_SECONDS = 30
-- How long a manual start lasts when no meeting runs.
local MANUAL_SECONDS = 60 * 60

local calendarCard = nil
-- What entering changed, while meeting mode is on.
local record = nil
local endTimer = nil
-- Meetings that started meeting mode, or that you left early, so they don't start it again.
local handled = {}

local function readJson(path)
  local text = shell.readText(path)
  if not text then return nil end
  local ok, data = pcall(hs.json.decode, text)
  return ok and data or nil
end

local function focusOn()
  return focus.activeMode(readJson(DB .. "/Assertions.json")) ~= nil
end

-- Runs the user's "omv Do Not Disturb" shortcut, when there is one; without it the Focus is
-- left alone.
local function toggleFocus()
  hs.task.new(SHORTCUTS, function(_, list)
    if focus.hasShortcut(list) then hs.task.new(SHORTCUTS, nil, { "run", focus.SHORTCUT }):start() end
  end, { "list" }):start()
end

-- Only a player that is running is asked, so none is ever launched.
local function playerState(player)
  if not hs.application.get(player) then return nil end
  local ok, state = hs.osascript.applescript('tell application "' .. player .. '" to return player state as string')
  return ok and state or nil
end

local function playersIn(state)
  local found = {}
  for _, player in ipairs(meeting.PLAYERS) do
    if playerState(player) == state then found[#found + 1] = player end
  end
  return found
end

local function tellPlayers(players, command)
  for _, player in ipairs(players) do
    hs.osascript.applescript('tell application "' .. player .. '" to ' .. command)
  end
end

-- The apps on the chat and music workspaces that aren't hidden.
local function shownApps()
  local output = hs.execute(shell.AEROSPACE .. " list-windows --workspace " .. table.concat(meeting.HIDDEN_WORKSPACES, " ")
    .. " --format '%{app-bundle-id}'")
  local shown = {}
  for _, bundle in ipairs(meeting.apps(output)) do
    local app = hs.application.get(bundle)
    if app and not app:isHidden() then shown[#shown + 1] = bundle end
  end
  return shown
end

local function setApps(bundles, hidden)
  for _, bundle in ipairs(bundles) do
    local app = hs.application.get(bundle)
    if app then
      if hidden then app:hide() else app:unhide() end
    end
  end
end

function feature.isOn()
  return record ~= nil
end

function feature.stop()
  if not record then return end
  local left = meeting.leave(record, { focusOn = focusOn(), paused = playersIn("paused") })
  record = nil
  quiet.active = false
  if endTimer then endTimer:stop() end
  endTimer = nil
  if left.focus then toggleFocus() end
  tellPlayers(left.resume, "play")
  setApps(left.unhide, false)
  shell.alert("Meeting mode off", 1.2)
end

-- Starts meeting mode until finish, a time in seconds; an event marks its meeting handled.
local function start(finish, event)
  if event then handled[meeting.key(event)] = true end
  if record then return end
  record = meeting.enter({ focusOn = focusOn(), playing = playersIn("playing"), shown = shownApps() })
  quiet.active = true
  if record.focus then toggleFocus() end
  tellPlayers(record.paused, "pause")
  setApps(record.hidden, true)
  endTimer = hs.timer.doAfter(math.max(1, finish - os.time()), feature.stop)
  shell.alert("Meeting mode on", 1.2)
end

local function events()
  return calendarCard and calendarCard.events() or {}
end

-- The calendar calls this after it opened a meeting's call link.
function feature.joined(link)
  local event = meeting.joined(events(), os.time(), link)
  if event then start(event.finish, event) end
end

-- From the key list and the palette: ends meeting mode, or starts it until the meeting
-- running now ends, or for an hour.
function feature.toggle()
  if record then return feature.stop() end
  local event = meeting.joined(events(), os.time(), nil)
  start(event and event.finish or os.time() + MANUAL_SECONDS, event)
end

local function check()
  local event = meeting.due(events(), os.time(), handled)
  if event then start(event.finish, event) end
end

function feature.setup(calendar)
  calendarCard = calendar
  -- Kept on the feature, so it isn't garbage-collected.
  feature.timer = hs.timer.doEvery(CHECK_SECONDS, check)
end

return feature
