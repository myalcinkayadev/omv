-- Waiting Claude (Option+Shift+A, or a click on the bar's pill): focuses the session's
-- terminal, or with several waiting, lists them with the asking ones first, then the one
-- waiting longest. Working sessions are left out here; the Agents card lists them too.
-- While Ghostty is in front, the session in the terminal you're looking at is marked seen,
-- so it leaves the pill until its state changes. A session that starts asking for approval
-- elsewhere gets a notification.

local shell = require("shell")
local card = require("card")
local claudewait = require("claudewait")

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

local function runScript(script)
  local ok, found = hs.osascript.applescript(script)
  return ok and found ~= false
end

-- Every live session's row, asking first, then done, then working.
function feature.rows()
  return claudewait.rows(savedSessions(), alive, os.time())
end

-- A process's parent PID and program path, as ps reports them.
local function parentOf(pid)
  local output = hs.execute("/bin/ps -o ppid=,comm= -p " .. math.floor(pid))
  local parentPid, program = output:match("^%s*(%d+)%s+(.-)%s*$")
  return tonumber(parentPid), program
end

-- Brings forward the app Claude runs in, such as Zed, when no terminal app has its tty.
-- macOS can't pick the window or pane, so the app comes forward as it was.
local function activateApp(row)
  local appPid = row.pid and claudewait.appPid(row.pid, parentOf)
  local app = appPid and hs.application.applicationForPID(appPid)
  return app ~= nil and app:activate()
end

-- Goes to the session's terminal, else the app it runs in, or says where it runs.
function feature.focusRow(row)
  if claudewait.focus(row.id, running, runScript) or activateApp(row) then return end
  shell.alert("Claude runs in " .. row.label .. ", which can't be brought forward", 2)
end

local function waitingRows()
  local rows = {}
  for _, row in ipairs(feature.rows()) do
    if row.waiting then rows[#rows + 1] = row end
  end
  return rows
end

function feature.focus()
  if shell.isOpen("claude") then return shell.close() end
  local rows = waitingRows()
  if #rows == 0 then return shell.alert("No Claude session is waiting", 1.2) end
  if #rows == 1 then return feature.focusRow(rows[1]) end
  shell.show("claude", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows, #rows)),
    card.html({ prompt = "Waiting…", rows = rows, compact = true }), function(message)
      if message.type ~= "choose" then return shell.close() end
      -- Leave focus to the terminal, rather than handing it back to the app open before.
      shell.leaveFocus()
      shell.close()
      for _, row in ipairs(rows) do
        if row.id == message.id then return feature.focusRow(row) end
      end
    end)
end

-- Seen sessions, read every 2 seconds while Ghostty is in front, and only then.
local GHOSTTY = "com.mitchellh.ghostty"
local VIEW_SECONDS = 2
local viewedTty = nil

local function readViewed()
  local ok, tty = hs.osascript.applescript(claudewait.viewedScript())
  viewedTty = ok and type(tty) == "string" and tty or nil
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

-- Kept on the feature, so they aren't garbage-collected.
feature.viewTimer = hs.timer.new(VIEW_SECONDS, readViewed)
feature.appWatcher = hs.application.watcher.new(function(_, event, app)
  if event ~= hs.application.watcher.activated then return end
  if app and app:bundleID() == GHOSTTY then
    readViewed()
    feature.viewTimer:start()
  else
    viewedTty = nil
    feature.viewTimer:stop()
  end
end):start()

-- A notification when a session starts asking, unless its terminal is the one in view.
-- Clicking it goes to that session.
local known = savedSessions()

feature.stateWatcher = hs.pathwatcher.new(claudewait.STATE_DIR, function()
  local now = savedSessions()
  for _, session in ipairs(claudewait.newlyAsking(known, now, viewedTty)) do
    local row = { id = session.tty, pid = session.pid, label = session.folder }
    hs.notify.new(function() feature.focusRow(row) end,
      { title = "omv · needs your approval", informativeText = session.folder, withdrawAfter = 0 }):send()
  end
  known = now
end):start()

return feature
