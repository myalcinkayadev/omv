-- Claude Code sessions waiting for you: reading what claude-waiting.sh saved, listing them
-- with the one waiting longest first, and the AppleScript that focuses one's Ghostty
-- terminal. Ghostty runs every window in one process, so the terminal is found by its tty,
-- not by the app.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local claudewait = {}

claudewait.STATE_DIR = os.getenv("HOME") .. "/.local/state/omv/claude-waiting"

-- One saved line: PID, tty ("-" outside a terminal), folder and since, split by tabs.
function claudewait.parse(text)
  local pid, tty, folder, since = text:match("^(%d+)\t([^\t]*)\t([^\t]*)\t(%d+)")
  if not pid then return nil end
  return { pid = tonumber(pid), tty = tty, folder = folder, since = tonumber(since) }
end

-- Card rows for the live sessions, the one waiting longest first: the folder, how long it
-- has waited, and its terminal as the row's id.
function claudewait.rows(sessions, alive, now)
  local live = {}
  for _, session in ipairs(sessions) do
    if alive(session.pid) then live[#live + 1] = session end
  end
  table.sort(live, function(a, b) return a.since < b.since end)
  local rows = {}
  for _, session in ipairs(live) do
    local minutes = math.floor((now - session.since) / 60)
    rows[#rows + 1] = { id = session.tty, label = session.folder, hint = minutes < 1 and "now" or minutes .. " min" }
  end
  return rows
end

-- Only a plain device path reaches AppleScript, so a saved line can't add commands.
function claudewait.focusScript(tty)
  if not tty:match("^/dev/ttys%d+$") then return nil end
  return 'tell application "Ghostty" to focus (first terminal whose tty is "' .. tty .. '")'
end

return claudewait
