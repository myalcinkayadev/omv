-- The away digest: once you unlock the screen after at least 5 minutes away, a card lists what
-- your agents did meanwhile: sessions that ask for approval, finished, started working or
-- ended, and the pull requests you opened. Enter goes to a session's terminal or opens a
-- pull request. Nothing shows when nothing changed.

local shell = require("shell")
local card = require("card")
local digest = require("digest")
local apps = require("apps")
local waiting = require("features.waiting")

local feature = {}

local GH = "/opt/homebrew/bin/gh"
-- How long gh gets before the card shows without pull requests.
local GH_SECONDS = 5

-- When the screen locked, and the sessions then; nil while you're here.
local lockedAt = nil
local before = nil

local function onDigestMessage(rows)
  return function(message)
    if message.type ~= "choose" then return shell.close() end
    for _, row in ipairs(rows) do
      if row.id == message.id then
        if row.url then
          shell.leaveFocus()
          shell.close()
          return shell.open({ "-a", apps.read(shell.readText(apps.PATH)).browser, row.url })()
        end
        if row.tty then
          shell.leaveFocus()
          shell.close()
          return waiting.focusRow({ id = row.tty, pid = row.pid, label = row.label })
        end
      end
    end
    shell.close()
  end
end

local function show(rows, since, now)
  if not digest.shows(since, now, rows) then return end
  shell.show("digest", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows, #rows)),
    card.html({ prompt = digest.prompt(since, now), rows = rows, compact = true }), onDigestMessage(rows))
end

-- Adds the pull requests you opened since the lock, when gh answers in time.
local function withPullRequests(rows, since, done)
  if not hs.fs.attributes(GH) then return done(rows) end
  local finished = false
  local task = hs.task.new(GH, function(code, output)
    if finished then return end
    finished = true
    local ok, found = pcall(hs.json.decode, output)
    for _, row in ipairs(code == 0 and ok and digest.prRows(found) or {}) do rows[#rows + 1] = row end
    done(rows)
  end, { "search", "prs", "--author=@me", "--created=" .. digest.createdSince(since), "--json", "number,title,url,repository" })
  if not task:start() then return done(rows) end
  hs.timer.doAfter(GH_SECONDS, function()
    if finished then return end
    finished = true
    task:terminate()
    done(rows)
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
  if not since or now - since < digest.MIN_AWAY then return end
  withPullRequests(digest.rows(sessionsThen, waiting.liveSessions(), since, now), since, function(rows)
    show(rows, since, os.time())
  end)
end

-- Kept on the feature, so it isn't garbage-collected.
feature.watcher = hs.caffeinate.watcher.new(function(event)
  local watcher = hs.caffeinate.watcher
  if event == watcher.screensDidLock or event == watcher.systemWillSleep then return away() end
  if event == watcher.screensDidUnlock then return back() end
end):start()

return feature
