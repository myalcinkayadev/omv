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
-- True while starting asks the players and AeroSpace, so the timer doesn't start it twice.
local starting = false
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

-- A player busy or starting takes seconds to answer, so each is asked in the background and
-- given this long.
local PLAYER_SECONDS = 3

-- Hands done the player's state. Only a player that is running is asked, so none is ever
-- launched.
local function playerState(player, done)
  if not hs.application.get(player) then return done(nil) end
  shell.osascript('tell application "' .. player .. '" to return player state as string', "AppleScript", PLAYER_SECONDS, function(state)
    done(state and state:gsub("%s+$", "") or nil)
  end)
end

-- Hands done the players in state, asking one after the other.
local function playersIn(state, done, found, index)
  found, index = found or {}, index or 1
  local player = meeting.PLAYERS[index]
  if not player then return done(found) end
  playerState(player, function(answer)
    if answer == state then found[#found + 1] = player end
    playersIn(state, done, found, index + 1)
  end)
end

local function tellPlayers(players, command)
  for _, player in ipairs(players) do
    shell.osascript('tell application "' .. player .. '" to ' .. command, "AppleScript", PLAYER_SECONDS, function() end)
  end
end

-- Hands done the apps on the chat and music workspaces that aren't hidden.
local function shownApps(done)
  shell.execute(shell.AEROSPACE .. " list-windows --workspace " .. table.concat(meeting.HIDDEN_WORKSPACES, " ")
    .. " --format '%{app-bundle-id}'", function(output)
    local shown = {}
    for _, bundle in ipairs(meeting.apps(output)) do
      local app = hs.application.get(bundle)
      if app and not app:isHidden() then shown[#shown + 1] = bundle end
    end
    done(shown)
  end)
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
  local entered = record
  record = nil
  quiet.active = false
  if endTimer then endTimer:stop() end
  endTimer = nil
  shell.alert("Meeting mode off", 1.2)
  playersIn("paused", function(paused)
    local left = meeting.leave(entered, { focusOn = focusOn(), paused = paused })
    if left.focus then toggleFocus() end
    tellPlayers(left.resume, "play")
    setApps(left.unhide, false)
  end)
end

-- Starts meeting mode until finish, a time in seconds; an event marks its meeting handled.
local function start(finish, event)
  if event then handled[meeting.key(event)] = true end
  if record or starting then return end
  starting = true
  shell.alert("Meeting mode on", 1.2)
  playersIn("playing", function(playing)
    shownApps(function(shown)
      starting = false
      record = meeting.enter({ focusOn = focusOn(), playing = playing, shown = shown })
      quiet.active = true
      if record.focus then toggleFocus() end
      tellPlayers(record.paused, "pause")
      setApps(record.hidden, true)
      endTimer = hs.timer.doAfter(math.max(1, finish - os.time()), feature.stop)
    end)
  end)
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
  if starting then return end
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
