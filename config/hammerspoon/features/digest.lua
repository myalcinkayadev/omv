-- The away digest: once you unlock the screen after at least 5 minutes away, or the minutes
-- set in ~/.config/omv/away-digest, and something changed meanwhile, the agents' inbox opens.
-- Sessions that ended and the pull requests you opened go under its While away section,
-- which stays until each row is cleared; the sessions that wait come from their live state,
-- as at any other time.

local shell = require("shell")
local digest = require("digest")
local waiting = require("features.waiting")

local feature = {}

local GH = "/opt/homebrew/bin/gh"
-- How long gh gets before the inbox opens without pull requests.
local GH_SECONDS = 5

-- When the screen locked, and the sessions then; nil while you're here.
local lockedAt = nil
local before = nil

-- The pull requests you opened since the lock, as gh's decoded JSON, when gh answers in time.
local function pullRequests(since, done)
  if not hs.fs.attributes(GH) then return done({}) end
  local finished = false
  local task = hs.task.new(GH, function(code, output)
    if finished then return end
    finished = true
    local ok, found = pcall(hs.json.decode, output)
    done((code == 0 and ok and found) or {})
  end, { "search", "prs", "--author=@me", "--created=" .. digest.createdSince(since), "--json", "number,title,url,repository" })
  if not task:start() then return done({}) end
  hs.timer.doAfter(GH_SECONDS, function()
    if finished then return end
    finished = true
    task:terminate()
    done({})
  end)
end

local function away()
  if lockedAt then return end
  lockedAt = os.time()
  before = waiting.liveSessions()
end

local function back()
  local since, sessionsThen = lockedAt, before
  lockedAt, before = nil, nil
  local now = os.time()
  -- Read each time, so a change to the file needs no reload.
  local minAway = digest.minAway(shell.readText(digest.PATH))
  if not since or now - since < minAway then return end
  pullRequests(since, function(pulls)
    local after = waiting.liveSessions()
    local awayRows = digest.awayRows(sessionsThen, after, since, now, pulls)
    -- A pull request opened during the break counts as a change too.
    if not digest.shows(since, now, digest.inbox(digest.changed(sessionsThen, after, since), awayRows), minAway) then return end
    waiting.away = awayRows
    waiting.showInbox()
  end)
end

-- Kept on the feature, so it isn't garbage-collected.
feature.watcher = hs.caffeinate.watcher.new(function(event)
  local watcher = hs.caffeinate.watcher
  if event == watcher.screensDidLock or event == watcher.systemWillSleep then return away() end
  if event == watcher.screensDidUnlock then return back() end
end):start()

return feature
