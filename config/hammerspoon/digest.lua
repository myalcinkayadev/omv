-- The agents' inbox: one screen for the sessions that wait for you and for what happened while
-- the screen was locked. Needs you and Done come from the sessions' live state, so they're
-- always current; While away holds what the live state can't show any more, sessions that
-- ended and pull requests you opened, until each row is cleared. A break is read from each
-- session's saved state, which says when it entered that state: nothing more is recorded.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local digest = {}

-- Shorter breaks open nothing on unlock, unless ~/.config/omv/away-digest says otherwise.
digest.MIN_AWAY = 5 * 60
digest.PATH = (os.getenv("HOME") or "") .. "/.config/omv/away-digest"

-- The break, in seconds, from the file's "minutes = N" line: N whole minutes, 0 for every
-- break. The last such line wins; no file, or a value that isn't a whole number, gives 5 minutes.
function digest.minAway(text)
  local found = nil
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local value = line:match("^%s*minutes%s*=%s*(%S+)%s*$")
    if value then found = value end
  end
  local minutes = found and found:match("^%d+$") and tonumber(found)
  return minutes and minutes * 60 or digest.MIN_AWAY
end

digest.NEEDS_YOU = "Needs you"
digest.DONE = "Done"

local function ago(seconds)
  local minutes = math.floor(seconds / 60)
  if minutes < 1 then return "just now" end
  if minutes < 60 then return minutes .. " min ago" end
  return math.floor(minutes / 60) .. " h ago"
end

local function prefix(session)
  return (session.agent and session.agent ~= "claude") and (session.agent .. " · ") or ""
end

local function span(seconds)
  local minutes = math.floor(seconds / 60)
  if minutes < 60 then return minutes .. " min" end
  return math.floor(minutes / 60) .. " h " .. (minutes % 60) .. " min"
end

-- sessions are claudewait.parse's, with their id, and only live ones. Rows for those that wait:
-- asking first, then done, the one waiting longest first in each. Working ones are left out.
function digest.liveRows(sessions, now)
  local waiting = {}
  for _, session in ipairs(sessions or {}) do
    if session.state == "asks" or session.state == "done" then waiting[#waiting + 1] = session end
  end
  table.sort(waiting, function(a, b)
    if a.state ~= b.state then return a.state == "asks" end
    return a.since < b.since
  end)
  local rows = {}
  for _, session in ipairs(waiting) do
    local asking = session.state == "asks"
    rows[#rows + 1] = {
      id = "session:" .. session.id, tty = session.tty, pid = session.pid, label = session.folder,
      hint = prefix(session) .. (asking and "approve · asked " or "finished ") .. ago(now - session.since),
      icon = asking and "●" or "✓", tone = asking and "ask" or "ok",
      group = asking and digest.NEEDS_YOU or digest.DONE, state = session.state, live = true,
    }
  end
  return rows
end

-- What the live state can't show after a break from lockedAt to back: sessions in before that
-- are gone from after, and the pull requests you opened, from gh's JSON already decoded.
function digest.awayRows(before, after, lockedAt, back, pulls)
  local group = "While away · " .. span(back - lockedAt)
  local present, rows = {}, {}
  for _, session in ipairs(after or {}) do present[session.id] = true end
  for _, session in ipairs(before or {}) do
    if not present[session.id] then
      rows[#rows + 1] = { id = "ended:" .. session.id, label = session.folder, hint = prefix(session) .. "ended",
        icon = "–", tone = "muted", group = group, state = "ended" }
    end
  end
  for _, pull in ipairs(pulls or {}) do
    if type(pull.url) == "string" and pull.url:match("^https://") then
      local repository = pull.repository and pull.repository.nameWithOwner or "?"
      rows[#rows + 1] = { id = "pr:" .. pull.url, url = pull.url, label = pull.title or "",
        hint = repository .. "#" .. tostring(pull.number) .. " · PR opened", icon = "↗", tone = "muted", group = group, state = "pr" }
    end
  end
  return rows
end

-- gh's --created filter for pull requests opened since a time, in UTC.
function digest.createdSince(time)
  return ">=" .. os.date("!%Y-%m-%dT%H:%M:%SZ", time)
end

-- The screen's rows: the live ones, then While away.
function digest.inbox(live, away)
  local rows = {}
  for _, row in ipairs(live or {}) do rows[#rows + 1] = row end
  for _, row in ipairs(away or {}) do rows[#rows + 1] = row end
  return rows
end

local COUNTED = { { "asks", "asks" }, { "done", "done" }, { "ended", "ended" }, { "pr", "PR", "PRs" } }

-- The count line under the title, and the status at its right: how many need you.
function digest.summary(rows)
  local counts = {}
  for _, row in ipairs(rows) do counts[row.state] = (counts[row.state] or 0) + 1 end
  local parts = {}
  for _, kind in ipairs(COUNTED) do
    local count = counts[kind[1]]
    if count then parts[#parts + 1] = count .. " " .. ((count > 1 and kind[3]) or kind[2]) end
  end
  local asking = counts.asks
  return {
    counts = table.concat(parts, " · "),
    status = asking and (asking .. (asking == 1 and " needs you" or " need you")) or "nothing needs you",
    tone = asking and "ask" or "ok",
  }
end

-- What the pill and Option+Shift+A do: "jump" straight to the one session waiting when nothing
-- is left from a break, "card" to open the screen, nil when there's nothing at all.
function digest.action(live, away)
  if #live == 1 and #away == 0 then return "jump" end
  if #live + #away > 0 then return "card" end
  return nil
end

-- What changed between the lock and now, to decide whether unlocking opens the screen: each
-- session that entered a state since lockedAt, and each that ended.
function digest.changed(before, after, lockedAt)
  local present, changes = {}, {}
  for _, session in ipairs(after or {}) do
    present[session.id] = true
    if session.since >= lockedAt then changes[#changes + 1] = { id = session.id, state = session.state } end
  end
  for _, session in ipairs(before or {}) do
    if not present[session.id] then changes[#changes + 1] = { id = session.id, state = "ended" } end
  end
  return changes
end

-- Whether unlocking opens the screen: only after a break of at least minAway seconds (5 minutes
-- when nil) in which something changed.
function digest.shows(lockedAt, now, changes, minAway)
  return lockedAt ~= nil and now - lockedAt >= (minAway or digest.MIN_AWAY) and #changes > 0
end

-- The rows without the While away row id; a live row stays, since the live state brings it back.
function digest.clear(rows, id)
  local kept = {}
  for _, row in ipairs(rows) do
    if row.id ~= id or row.live then kept[#kept + 1] = row end
  end
  return kept
end

return digest
