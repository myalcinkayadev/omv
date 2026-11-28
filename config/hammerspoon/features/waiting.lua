-- The agents' inbox (Option+Shift+A, or a click on the bar's pill): with one session waiting
-- and nothing left from a break, it goes straight to that session's terminal. Otherwise one
-- screen lists Needs you, Done, and While away after a break, with a count line under the
-- title. Working sessions are left out here; the Agents card lists them too.
-- While Ghostty is in front, the session in the terminal you're looking at is marked seen,
-- so it leaves the pill until its state changes. A session that starts asking for approval
-- elsewhere gets a notification.

local shell = require("shell")
local card = require("card")
local claudewait = require("claudewait")
local agentgrid = require("agentgrid")
local quiet = require("quiet")
local digest = require("digest")
local apps = require("apps")
local notices = require("notices")

local feature = {}

local function alive(pid)
  return os.execute("/bin/kill -0 " .. math.floor(pid) .. " 2>/dev/null") == true
end

local function savedSessions()
  local sessions = {}
  -- hs.fs.dir gives an iterator and the folder it reads, and the loop needs both.
  local ok, files, folder = pcall(hs.fs.dir, claudewait.STATE_DIR)
  for name in (ok and files) and files or function() end, folder do
    local session = name:sub(1, 1) ~= "." and claudewait.parse(shell.readText(claudewait.STATE_DIR .. "/" .. name) or "")
    if session then
      session.id = name
      sessions[#sessions + 1] = session
    end
  end
  return sessions
end

local function running(bundle)
  return hs.application.get(bundle) ~= nil
end

-- How long a terminal gets to answer whether it has the session.
local FOCUS_SECONDS = 3

-- A focus script answers false when its terminal hasn't the tty; no answer counts the same.
local function runScript(script, answer)
  shell.osascript(script, "AppleScript", FOCUS_SECONDS, function(output)
    answer(output ~= nil and not output:match("^%s*false%s*$"))
  end)
end

-- The saved sessions whose agent still runs, each with its id.
function feature.liveSessions()
  local live = {}
  for _, session in ipairs(savedSessions()) do
    if alive(session.pid) then live[#live + 1] = session end
  end
  return live
end

-- Every live session's row, asking first, then done, then working.
function feature.rows()
  return claudewait.rows(savedSessions(), alive, os.time())
end

-- Brings forward the app Claude runs in, such as Zed, when no terminal app has its tty, and
-- hands done whether it could. macOS can't pick the window or pane, so the app comes forward
-- as it was. One ps in the background lists every process's parent.
local function activateApp(row, done)
  if not row.pid then return done(false) end
  shell.execute("/bin/ps -axo pid=,ppid=,comm=", function(output)
    local appPid = claudewait.appPid(row.pid, claudewait.parents(output))
    local app = appPid and hs.application.applicationForPID(appPid)
    done(app ~= nil and app:activate())
  end)
end

local TMUX = "/opt/homebrew/bin/tmux"

-- A session in a tmux pane, such as an agent grid's: selects its pane, then brings forward
-- the terminal attached to that tmux session. Only a plain target reaches the shell.
local function focusTmux(row, done)
  if not hs.fs.attributes(TMUX) then return done(false) end
  shell.execute(TMUX .. " list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}' 2>/dev/null", function(panes)
    local target = agentgrid.paneFor(panes, row.id)
    if not target or not target:match("^[%w_%-]+:%d+%.%d+$") then return done(false) end
    shell.execute(TMUX .. " select-window -t " .. target .. " && " .. TMUX .. " select-pane -t " .. target
      .. " && " .. TMUX .. " list-clients -F '#{client_tty} #{session_name}' 2>/dev/null", function(clients)
      local client = agentgrid.clientFor(clients, target)
      if not client then return done(false) end
      claudewait.focus(client, running, runScript, done)
    end)
  end)
end

-- Goes to the session's terminal, its tmux pane, else the app it runs in, or says where it runs.
-- after, when given, hears whether the session's own terminal or pane came forward: the app
-- alone doesn't count, since macOS can't pick its window or pane.
function feature.focusRow(row, after)
  local function finish(focused)
    if after then after(focused) end
  end
  claudewait.focus(row.id, running, runScript, function(focused)
    if focused then return finish(true) end
    focusTmux(row, function(tmuxFocused)
      if tmuxFocused then return finish(true) end
      activateApp(row, function(activated)
        if not activated then shell.alert("Claude runs in " .. row.label .. ", which can't be brought forward", 2) end
        finish(false)
      end)
    end)
  end)
end

-- What the away digest keeps from the last break, the While away rows, until each is cleared.
feature.away = {}

local INBOX_FOOTER = { { key = "Enter", text = "go to it" }, { key = "⌫", text = "clear" }, { key = "Esc", text = "close" } }

local function inboxRows()
  return digest.inbox(digest.liveRows(feature.liveSessions(), os.time()), feature.away)
end

-- The screen is sized to what its page needs once it has loaded; it may still be loading
-- when asked, so it's asked a few times.
local FIT_TRIES = 10

local function fitInbox(tries)
  if not shell.isOpen("claude") or tries <= 0 then return end
  shell.view():evaluateJavaScript("typeof omvContentHeight === 'function' ? omvContentHeight() : 0", function(height)
    if type(height) ~= "number" or height <= 0 then
      return hs.timer.doAfter(0.05, function() fitInbox(tries - 1) end)
    end
    if shell.isOpen("claude") then shell.view():frame(shell.centered(shell.LIST_WIDTH, height)) end
  end)
end

local function openRow(row)
  -- Leave focus to the terminal or the browser, rather than handing it back to the app open before.
  shell.leaveFocus()
  shell.close()
  if row.url then return shell.open({ "-a", apps.read(shell.readText(apps.PATH)).browser, row.url })() end
  if row.tty then return feature.focusRow({ id = row.tty, pid = row.pid, label = row.label }) end
end

local showInbox

local function onInboxMessage(message)
  if message.type == "clear" then
    feature.away = digest.clear(feature.away, message.id)
    return showInbox()
  end
  if message.type ~= "choose" then return shell.close() end
  for _, row in ipairs(inboxRows()) do
    if row.id == message.id then return openRow(row) end
  end
  shell.close()
end

showInbox = function()
  local rows = inboxRows()
  if #rows == 0 then return shell.close() end
  shell.show("claude", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows, #rows) + 100),
    card.html({ prompt = "Agents", sub = digest.summary(rows), rows = rows, footer = INBOX_FOOTER, clearable = true, compact = true }),
    onInboxMessage)
  fitInbox(FIT_TRIES)
end

-- Opens the screen whatever it holds, as unlocking after a break does.
function feature.showInbox()
  showInbox()
end

function feature.focus()
  if shell.isOpen("claude") then return shell.close() end
  local live = digest.liveRows(feature.liveSessions(), os.time())
  local action = digest.action(live, feature.away)
  if not action then return shell.alert("No agent is waiting", 1.2) end
  if action == "jump" then return feature.focusRow({ id = live[1].tty, pid = live[1].pid, label = live[1].label }) end
  showInbox()
end

-- Seen sessions, read while Ghostty is in front, and only then: once its focused window has
-- settled after a switch of window or tab (each tab is a window of its own), and every
-- VIEW_SECONDS for a switch of split, which leaves the window as it was. Each read starts an
-- osascript. A title change alone doesn't change the terminal in view, and Claude Code turns
-- its spinner in the title once a second, so titles aren't watched.
local GHOSTTY = "com.mitchellh.ghostty"
local VIEW_SECONDS = 5
-- Switching windows quickly, one read follows them all.
local VIEW_SETTLE_SECONDS = 0.3
local viewedTty = nil

-- How long Ghostty gets to answer; a busy one is asked again at the next read.
local VIEW_ANSWER_SECONDS = 2
-- Set while Ghostty is being asked, so a slow answer never has a second ask piled on.
local viewing = false

local function markSeen()
  local marked = false
  for _, seen in ipairs(claudewait.seenNow(savedSessions(), viewedTty)) do
    local path = claudewait.STATE_DIR .. "/.seen-" .. seen.id
    if tonumber(shell.readText(path)) ~= seen.since then
      local file = io.open(path, "w")
      if file then
        file:write(seen.since, "\n")
        file:close()
        marked = true
      end
    end
  end
  if marked then hs.task.new(shell.SKETCHYBAR, nil, { "--trigger", "claude_waiting_change" }):start() end
end

-- Asked in the background: Ghostty not answering mustn't freeze Hammerspoon.
local function readViewed()
  if viewing then return end
  viewing = true
  shell.osascript(claudewait.viewedScript(), "AppleScript", VIEW_ANSWER_SECONDS, function(answer)
    viewing = false
    viewedTty = claudewait.viewedTty(answer)
    markSeen()
  end)
end

-- Kept on the feature, so they aren't garbage-collected.
feature.viewTimer = hs.timer.new(VIEW_SECONDS, readViewed)
feature.viewSettled = hs.timer.delayed.new(VIEW_SETTLE_SECONDS, readViewed)
feature.ghosttyWatcher = nil

local function watchGhostty(app)
  readViewed()
  feature.viewTimer:start()
  if feature.ghosttyWatcher then feature.ghosttyWatcher:stop() end
  feature.ghosttyWatcher = app:newWatcher(function() feature.viewSettled:start() end)
  feature.ghosttyWatcher:start({ hs.uielement.watcher.focusedWindowChanged })
end

local function unwatchGhostty()
  viewedTty = nil
  feature.viewTimer:stop()
  feature.viewSettled:stop()
  if feature.ghosttyWatcher then feature.ghosttyWatcher:stop() end
  feature.ghosttyWatcher = nil
end

feature.appWatcher = hs.application.watcher.new(function(_, event, app)
  if event ~= hs.application.watcher.activated then return end
  if app and app:bundleID() == GHOSTTY then return watchGhostty(app) end
  unwatchGhostty()
end):start()

-- A reload while Ghostty is in front gets no activation, so it starts watching here.
local front = hs.application.frontmostApplication()
if front and front:bundleID() == GHOSTTY then watchGhostty(front) end

-- A notification when a session starts asking, unless its terminal is the one in view, or
-- meeting mode holds notices back; the bar's pill still shows it. Clicking it goes to that
-- session. One function serves every notification, since Hammerspoon keeps a function given
-- to hs.notify.new for good; two sessions in one folder read the same, so a click goes to
-- the one that asked last.
local known = savedSessions()
-- Features told of every change in the sessions, with the sessions before and after it.
local listeners = {}

-- fn(before, after) runs whenever a session's state file changes; talk-back uses it.
function feature.onChange(fn)
  listeners[#listeners + 1] = fn
end

-- The tty of the Claude session in the Ghostty terminal you're looking at, or nil.
function feature.viewedTty()
  return viewedTty
end
local ASKING_TITLE = "omv · needs your approval"
local ASKING_TAG = "omv-waiting"
local askingRows = notices.new()

hs.notify.register(ASKING_TAG, function(clicked)
  local row = notices.find(askingRows, notices.key(clicked:title(), clicked:informativeText()))
  if row then feature.focusRow(row) end
end)

feature.stateWatcher = hs.pathwatcher.new(claudewait.STATE_DIR, function()
  local now = savedSessions()
  for _, session in ipairs(quiet.active and {} or claudewait.newlyAsking(known, now, viewedTty)) do
    notices.add(askingRows, notices.key(ASKING_TITLE, session.folder),
      { id = session.tty, pid = session.pid, label = session.folder })
    hs.notify.new(ASKING_TAG, { title = ASKING_TITLE, informativeText = session.folder, withdrawAfter = 0 }):send()
  end
  local before = known
  known = now
  -- A listener's error is logged and never stops the watcher or the asking notices.
  for _, listener in ipairs(listeners) do
    local ok, problem = pcall(listener, before, now)
    if not ok then print("omv: a sessions listener failed: " .. tostring(problem)) end
  end
end):start()

return feature
