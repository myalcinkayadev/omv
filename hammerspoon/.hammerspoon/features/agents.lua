-- Agents card (click the robot in the bar). >_ continues the last Claude Code session,
-- in its folder; + lists the recent Claude Code projects, to start a new session in one.
-- Both open a Ghostty window on workspace 1. Below them, every live session with its state;
-- picking one goes to its terminal. Then Claude Code's background sessions, from its agent
-- view; picking one opens it with claude attach in a Ghostty window.

local shell = require("shell")
local card = require("card")
local agents = require("agents")
local waiting = require("features.waiting")

local feature = {}

local HOME = shell.HOME
local CLAUDE_IN = hs.configdir .. "/claude-in.sh"
local CLAUDE_USAGE = HOME .. "/.local/state/omv/claude-usage"
local CLAUDE_CONFIG = HOME .. "/.claude.json"
local CLAUDE_LOGO = HOME .. "/.config/sketchybar/icons/claude.png"
-- Where Claude Code's installer puts it. Without it, the card has no background section.
local CLAUDE = HOME .. "/.local/bin/claude"
-- Enough recent sessions to fill the project list, without reading every one.
local RECENT_SESSIONS = 60
-- A session's folder is near the start of its file, so only that much is read.
local SESSION_HEAD_BYTES = 65536
-- Claude Code writes a session's title again as it goes, so its end holds the latest one.
-- Session files reach hundreds of megabytes together, too much to search while the card opens.
local SESSION_TAIL_BYTES = 131072
local RESUME_VISIBLE_ROWS = 10
local PROJECTS_VISIBLE_ROWS = 10
local claudeLogo = nil

-- Only organizationType is read from ~/.claude.json, for the plan's name.
local function claudePlan()
  local ok, config = pcall(hs.json.read, CLAUDE_CONFIG)
  local account = ok and type(config) == "table" and config.oauthAccount or nil
  return agents.plan(account and account.organizationType)
end

local function logoUrl()
  if claudeLogo == nil then
    local image = hs.image.imageFromPath(CLAUDE_LOGO)
    claudeLogo = image and image:encodeAsURLString() or false
  end
  return claudeLogo or nil
end

-- The recent Claude Code sessions, newest first, as { id, path, cwd, modified }. The id is
-- the file's name, which claude --resume takes.
local function recentSessions()
  local listing = hs.execute("/bin/ls -t " .. HOME .. "/.claude/projects/*/*.jsonl 2>/dev/null | /usr/bin/head -n " .. RECENT_SESSIONS)
  local sessions = {}
  for path in listing:gmatch("[^\n]+") do
    local cwd = agents.sessionCwd(shell.readText(path, SESSION_HEAD_BYTES))
    if cwd then
      sessions[#sessions + 1] = { id = path:match("([^/]+)%.jsonl$"), path = path, cwd = cwd,
        modified = hs.fs.attributes(path, "modification") or 0 }
    end
  end
  return sessions
end

local function readTail(path, bytes)
  local file = io.open(path, "r")
  if not file then return nil end
  if not file:seek("end", -bytes) then file:seek("set") end
  local text = file:read("*a")
  file:close()
  return text
end

-- Claude Code's background sessions, from `claude agents --json`, which answers in about 0.1s.
local function backgroundSessions()
  if not hs.fs.attributes(CLAUDE) then return {} end
  local output = hs.execute(agents.shellQuote(CLAUDE) .. " agents --json 2>/dev/null")
  local ok, list = pcall(hs.json.decode, output or "")
  return agents.background(ok and list or nil)
end

local function folderExists(path)
  return hs.fs.attributes(path, "mode") == "directory"
end

local function startClaude(folder, arguments)
  local command = CLAUDE_IN .. " " .. agents.shellQuote(folder) .. (arguments and (" " .. arguments) or "")
  shell.run(shell.LAUNCH, { "1", shell.GHOSTTY_WINDOW, command })()
end

local onAgentsMessage
-- The rows the card shows, kept so a pick can be matched back to its row.
local sessionRows = {}
local backgroundRows = {}

local function showAgents()
  sessionRows = waiting.rows()
  backgroundRows = backgroundSessions()
  local model = { plan = claudePlan(), usage = agents.parseUsage(shell.readText(CLAUDE_USAGE), os.time()),
    logo = logoUrl(), sessions = sessionRows, background = backgroundRows }
  shell.show("agents", shell.anchored(agents.WIDTH, agents.height(#sessionRows, #backgroundRows), "claude_usage"),
    agents.html(model), onAgentsMessage)
end

local function focusSession(tty)
  -- Leave focus to the terminal, rather than handing it back to the app open before.
  shell.leaveFocus()
  shell.close()
  for _, row in ipairs(sessionRows) do
    if row.id == tty then return waiting.focusRow(row) end
  end
end

local function onProjectMessage(message)
  if message.type == "back" then return showAgents() end
  if message.type ~= "choose" then return shell.close() end
  -- Leave focus to the new window, rather than handing it back to the app open before.
  shell.leaveFocus()
  shell.close()
  startClaude(message.id)
end

local function showProjects()
  local rows = agents.projectRows(agents.projects(recentSessions(), folderExists), HOME)
  local screen = { prompt = "New Claude session in…", rows = rows, compact = true, hint = "No Claude Code projects yet" }
  local height = shell.listHeight(math.max(1, #rows), PROJECTS_VISIBLE_ROWS)
  shell.show("agents-projects", shell.centered(shell.LIST_WIDTH, height), card.html(screen), onProjectMessage)
end

-- Opens a background session in a new Ghostty window, in its folder, with claude attach.
-- Claude's background service runs only while a client is connected, and claude rm needs it.
local function serviceRunning()
  return (hs.execute(agents.shellQuote(CLAUDE) .. " daemon status 2>/dev/null") or ""):find("pid:") ~= nil
end

-- Stops and removes the session, then stops the service when it was started for this,
-- leaving any other background session running.
local function runRemoval(id, startedService)
  for _, command in ipairs(agents.removeCommands(id)) do
    hs.execute(agents.shellQuote(CLAUDE) .. " " .. command .. " 2>&1")
  end
  if startedService then hs.execute(agents.shellQuote(CLAUDE) .. " daemon stop --any --keep-workers 2>&1") end
  showAgents()
end

local function removeBackground(id)
  if not agents.removeCommands(id) then return shell.close() end
  if serviceRunning() then return runRemoval(id, false) end
  shell.alert("Removing…", 1.5)
  -- Kept on the feature, so it isn't garbage-collected while it runs.
  feature.service = hs.task.new(CLAUDE, nil, { "daemon", "run" })
  feature.service:start()
  -- The service takes a moment before it answers.
  hs.timer.doAfter(2, function() runRemoval(id, true) end)
end

-- x on a background row asks first, with Cancel selected.
local function confirmBackgroundRemoval(id)
  for _, row in ipairs(backgroundRows) do
    if row.id == id then
      local screen = agents.confirmRemove(row)
      return shell.show("agents-remove", shell.anchored(agents.WIDTH, shell.menuHeight(screen), "claude_usage"), card.html(screen), function(message)
        if message.type == "choose" and message.id == "remove" then return removeBackground(id) end
        if message.type == "close" then return shell.close() end
        showAgents()
      end)
    end
  end
end

local function attachBackground(id)
  local arguments = agents.attachArguments(id)
  for _, row in ipairs(backgroundRows) do
    if row.id == id and arguments then
      shell.leaveFocus()
      shell.close()
      return startClaude(row.cwd or HOME, arguments)
    end
  end
  shell.close()
end

-- Sessions picked from the resume list, by id, kept to find the chosen one's folder.
local resumable = {}

local function onResumeMessage(message)
  if message.type == "back" then return showAgents() end
  if message.type ~= "choose" then return shell.close() end
  local session, arguments = resumable[message.id], agents.resumeArguments(message.id)
  if not (session and arguments) then return shell.close() end
  -- Leave focus to the new window, rather than handing it back to the app open before.
  shell.leaveFocus()
  shell.close()
  startClaude(session.cwd, arguments)
end

local function showResume()
  local sessions = recentSessions()
  resumable = {}
  for _, session in ipairs(sessions) do
    session.title = agents.sessionTitle(readTail(session.path, SESSION_TAIL_BYTES))
    resumable[session.id] = session
  end
  local rows = agents.resumeRows(sessions, folderExists, os.time())
  local screen = { prompt = "Resume a Claude session…", rows = rows, compact = true, hint = "No Claude Code sessions yet" }
  local height = shell.listHeight(math.max(1, #rows), RESUME_VISIBLE_ROWS)
  shell.show("agents-resume", shell.centered(shell.LIST_WIDTH, height), card.html(screen), onResumeMessage)
end

onAgentsMessage = function(message)
  if message.type == "remove" then
    local id = agents.backgroundId(message.id)
    if id then return confirmBackgroundRemoval(id) end
    return
  end
  if message.type ~= "choose" then return shell.close() end
  if message.id == "agents.new" then return showProjects() end
  if message.id == "agents.resume" then return showResume() end
  local tty = agents.sessionTty(message.id)
  if tty then return focusSession(tty) end
  local backgroundId = agents.backgroundId(message.id)
  if backgroundId then return attachBackground(backgroundId) end
  local latest = agents.latest(recentSessions(), folderExists)
  if not latest then return shell.alert("No Claude Code sessions yet", 1.5) end
  shell.leaveFocus()
  shell.close()
  startClaude(latest.cwd, "--continue")
end

function feature.toggle()
  if shell.isOpen("agents", "agents-projects", "agents-resume", "agents-remove") then return shell.close() end
  showAgents()
end

-- When the 5-hour limit is at 90% or more, a reminder at its reset says it's free again.
-- The planned reset is saved, so a reload doesn't plan the same notice twice.
local RESET_NOTICE = HOME .. "/.local/state/omv/claude-reset-notice"

local function planResetNotice()
  local now = os.time()
  local notice = agents.resetNotice(agents.parseUsage(shell.readText(CLAUDE_USAGE), now), now,
    tonumber(shell.readText(RESET_NOTICE)))
  if not notice then return end
  local file = io.open(RESET_NOTICE, "w")
  if not file then return end
  file:write(notice.at, "\n")
  file:close()
  require("features.reminders").add(notice.at - now, notice.text)
end

-- Kept on the feature, so it isn't garbage-collected.
feature.usageWatcher = hs.pathwatcher.new(CLAUDE_USAGE, planResetNotice):start()
planResetNotice()

return feature
