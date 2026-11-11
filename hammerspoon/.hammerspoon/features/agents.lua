-- Agents card (click the robot in the bar). >_ continues the last Claude Code session,
-- in its folder; + lists the recent Claude Code projects, to start a new session in one.
-- Both open a Ghostty window on workspace 1. Below them, every live session with its state;
-- picking one goes to its terminal.

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
-- Enough recent sessions to fill the project list, without reading every one.
local RECENT_SESSIONS = 60
-- A session's folder is near the start of its file, so only that much is read.
local SESSION_HEAD_BYTES = 65536
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

-- The recent Claude Code sessions, newest first, as { cwd, modified }.
local function recentSessions()
  local listing = hs.execute("/bin/ls -t " .. HOME .. "/.claude/projects/*/*.jsonl 2>/dev/null | /usr/bin/head -n " .. RECENT_SESSIONS)
  local sessions = {}
  for path in listing:gmatch("[^\n]+") do
    local cwd = agents.sessionCwd(shell.readText(path, SESSION_HEAD_BYTES))
    if cwd then sessions[#sessions + 1] = { cwd = cwd, modified = hs.fs.attributes(path, "modification") or 0 } end
  end
  return sessions
end

local function startClaude(folder, arguments)
  local command = CLAUDE_IN .. " " .. agents.shellQuote(folder) .. (arguments and (" " .. arguments) or "")
  shell.run(shell.LAUNCH, { "1", shell.GHOSTTY_WINDOW, command })()
end

local onAgentsMessage
-- The session rows the card shows, kept so a pick can be matched back to its row.
local sessionRows = {}

local function showAgents()
  sessionRows = waiting.rows()
  local model = { plan = claudePlan(), usage = agents.parseUsage(shell.readText(CLAUDE_USAGE), os.time()),
    logo = logoUrl(), sessions = sessionRows }
  shell.show("agents", shell.anchored(agents.WIDTH, agents.height(#sessionRows)), agents.html(model), onAgentsMessage)
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
  local rows = agents.projectRows(agents.projects(recentSessions()), HOME)
  local screen = { prompt = "New Claude session in…", rows = rows, compact = true, hint = "No Claude Code projects yet" }
  local height = shell.listHeight(math.max(1, #rows), PROJECTS_VISIBLE_ROWS)
  shell.show("agents-projects", shell.centered(shell.LIST_WIDTH, height), card.html(screen), onProjectMessage)
end

onAgentsMessage = function(message)
  if message.type ~= "choose" then return shell.close() end
  if message.id == "agents.new" then return showProjects() end
  local tty = agents.sessionTty(message.id)
  if tty then return focusSession(tty) end
  local latest = recentSessions()[1]
  if not latest then return shell.alert("No Claude Code sessions yet", 1.5) end
  shell.leaveFocus()
  shell.close()
  startClaude(latest.cwd, "--continue")
end

function feature.toggle()
  if shell.isOpen("agents", "agents-projects") then return shell.close() end
  showAgents()
end

return feature
