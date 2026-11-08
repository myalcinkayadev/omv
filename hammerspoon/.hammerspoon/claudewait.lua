-- Claude Code sessions waiting for you: reading what claude-waiting.sh saved, picking the
-- one waiting longest, and the AppleScript that focuses its Ghostty terminal. Ghostty runs
-- every window in one process, so the terminal is found by its tty, not by the app.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local claudewait = {}

claudewait.STATE_DIR = os.getenv("HOME") .. "/.local/state/omv/claude-waiting"

-- One saved line: PID, tty ("-" outside a terminal), folder and since, split by tabs.
function claudewait.parse(text)
  local pid, tty, folder, since = text:match("^(%d+)\t([^\t]*)\t([^\t]*)\t(%d+)")
  if not pid then return nil end
  return { pid = tonumber(pid), tty = tty, folder = folder, since = tonumber(since) }
end

function claudewait.oldest(sessions, alive)
  local found = nil
  for _, session in ipairs(sessions) do
    if alive(session.pid) and (not found or session.since < found.since) then found = session end
  end
  return found
end

-- Only a plain device path reaches AppleScript, so a saved line can't add commands.
function claudewait.focusScript(tty)
  if not tty:match("^/dev/ttys%d+$") then return nil end
  return 'tell application "Ghostty" to focus (first terminal whose tty is "' .. tty .. '")'
end

return claudewait
