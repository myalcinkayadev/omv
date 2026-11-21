-- The away digest: what your agents did while the screen was locked, shown once you unlock
-- it. Each session's saved state says when it entered that state, so the sessions as they
-- were at the lock, and as they are now, are all it takes: nothing more is recorded.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local digest = {}

-- Shorter breaks show nothing.
digest.MIN_AWAY = 5 * 60

local ORDER = { asks = 1, done = 2, working = 3, ended = 4, pr = 5 }

local function ago(seconds)
  local minutes = math.floor(seconds / 60)
  if minutes < 1 then return "just now" end
  if minutes < 60 then return minutes .. " min ago" end
  return math.floor(minutes / 60) .. " h ago"
end

local function prefix(session)
  return (session.agent and session.agent ~= "claude") and (session.agent .. " · ") or ""
end

-- before: the live sessions at the lock; after: the live sessions now. Sessions are
-- claudewait.parse's, with their id. Rows for what changed since lockedAt: asking first,
-- then finished, working and ended, the earliest change first in each.
function digest.rows(before, after, lockedAt, now)
  local found, present = {}, {}
  for _, session in ipairs(after or {}) do
    present[session.id] = true
    if session.since >= lockedAt then
      local state = ORDER[session.state] and session.state or "done"
      local words = state == "asks" and "needs your approval"
        or state == "working" and ("started working " .. ago(now - session.since))
        or ("finished " .. ago(now - session.since))
      found[#found + 1] = { id = "session:" .. session.id, tty = session.tty, pid = session.pid, label = session.folder,
        hint = prefix(session) .. words, state = state, at = session.since }
    end
  end
  for _, session in ipairs(before or {}) do
    if not present[session.id] then
      found[#found + 1] = { id = "ended:" .. session.id, label = session.folder, hint = prefix(session) .. "ended",
        state = "ended", at = lockedAt }
    end
  end
  table.sort(found, function(a, b)
    if ORDER[a.state] ~= ORDER[b.state] then return ORDER[a.state] < ORDER[b.state] end
    if a.at ~= b.at then return a.at < b.at end
    return a.id < b.id
  end)
  return found
end

-- Rows for the pull requests you opened while away, from gh's JSON already decoded.
function digest.prRows(found)
  local rows = {}
  for _, pull in ipairs(found or {}) do
    if type(pull.url) == "string" and pull.url:match("^https://") then
      local repository = pull.repository and pull.repository.nameWithOwner or "?"
      rows[#rows + 1] = { id = "pr:" .. pull.url, url = pull.url, label = pull.title or "",
        hint = repository .. "#" .. tostring(pull.number) .. " · pull request opened", state = "pr" }
    end
  end
  return rows
end

-- gh's --created filter for pull requests opened since a time, in UTC.
function digest.createdSince(time)
  return ">=" .. os.date("!%Y-%m-%dT%H:%M:%SZ", time)
end

-- Whether the digest shows: only after a long enough break, and only with something in it.
function digest.shows(lockedAt, now, rows)
  return lockedAt ~= nil and now - lockedAt >= digest.MIN_AWAY and #rows > 0
end

-- The card's prompt, with how long you were away.
function digest.prompt(lockedAt, now)
  local minutes = math.floor((now - lockedAt) / 60)
  local away = minutes < 60 and (minutes .. " min") or (math.floor(minutes / 60) .. " h " .. (minutes % 60) .. " min")
  return "While you were away, " .. away .. "…"
end

return digest
