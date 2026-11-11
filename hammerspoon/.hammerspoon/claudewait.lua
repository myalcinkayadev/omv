-- Claude Code sessions: reading what claude-waiting.sh saved, listing them with the ones
-- waiting for you first, and the AppleScript that focuses one's terminal in
-- Ghostty, iTerm2 or Terminal. Each runs every window in one process, so the terminal is
-- found by its tty, not by the app.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local claudewait = {}

claudewait.STATE_DIR = os.getenv("HOME") .. "/.local/state/omv/claude-sessions"

-- asks: waits for your approval or answer. done: finished, waits for your next prompt.
-- working: busy, needs nothing from you. Listed in this order.
local RANK = { asks = 1, done = 2, working = 3 }

-- One saved line: PID, tty ("-" outside a terminal), folder, since and state, split by
-- tabs. A line saved before states existed has no state, and was saved when Claude waited.
function claudewait.parse(text)
  local pid, tty, folder, since, rest = text:match("^(%d+)\t([^\t]*)\t([^\t]*)\t(%d+)(.*)")
  if not pid then return nil end
  local state = rest:match("^\t(%a+)")
  return { pid = tonumber(pid), tty = tty, folder = folder, since = tonumber(since), state = RANK[state] and state or "done" }
end

-- Card rows for the live sessions: asking first, then done, then working, and in each the
-- one in its state longest first. Each row has the folder, the state and how long it has
-- been in it, whether it waits for you, and its terminal as the row's id.
function claudewait.rows(sessions, alive, now)
  local live = {}
  for _, session in ipairs(sessions) do
    if alive(session.pid) then live[#live + 1] = session end
  end
  local function rank(session) return RANK[session.state] or RANK.done end
  table.sort(live, function(a, b)
    if rank(a) ~= rank(b) then return rank(a) < rank(b) end
    return a.since < b.since
  end)
  local rows = {}
  for _, session in ipairs(live) do
    local state = session.state or "done"
    local minutes = math.floor((now - session.since) / 60)
    rows[#rows + 1] = { id = session.tty, label = session.folder, state = state, waiting = state ~= "working",
      hint = state .. " · " .. (minutes < 1 and "now" or minutes .. " min") }
  end
  return rows
end

-- Each script focuses the terminal on TTY, and fails or returns false when the app has none.
local FOCUS_SCRIPTS = {
  { bundle = "com.mitchellh.ghostty", script = 'tell application "Ghostty" to focus (first terminal whose tty is "TTY")' },
  { bundle = "com.googlecode.iterm2", script = [[
tell application "iTerm2"
  repeat with aWindow in windows
    repeat with aTab in tabs of aWindow
      repeat with aSession in sessions of aTab
        if tty of aSession is "TTY" then
          select aWindow
          select aTab
          select aSession
          activate
          return true
        end if
      end repeat
    end repeat
  end repeat
  return false
end tell]] },
  { bundle = "com.apple.Terminal", script = [[
tell application "Terminal"
  repeat with aWindow in windows
    repeat with aTab in tabs of aWindow
      if tty of aTab is "TTY" then
        set selected of aTab to true
        set index of aWindow to 1
        activate
        return true
      end if
    end repeat
  end repeat
  return false
end tell]] },
}

-- The scripts to try, Ghostty first. Only a plain device path reaches AppleScript, so a
-- saved line can't add commands.
function claudewait.focusScripts(tty)
  if not tty:match("^/dev/ttys%d+$") then return {} end
  local scripts = {}
  for _, entry in ipairs(FOCUS_SCRIPTS) do
    scripts[#scripts + 1] = { bundle = entry.bundle, script = (entry.script:gsub("TTY", tty)) }
  end
  return scripts
end

-- Focuses the terminal on tty in the first running app that has it. Apps that aren't
-- running are skipped, since telling one to look would launch it.
-- running(bundle) says whether an app runs; run(script) says whether the script found the tty.
function claudewait.focus(tty, running, run)
  for _, entry in ipairs(claudewait.focusScripts(tty)) do
    if running(entry.bundle) and run(entry.script) then return true end
  end
  return false
end

return claudewait
