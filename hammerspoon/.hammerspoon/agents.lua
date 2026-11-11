-- The Agents card opened from the bar's robot: Claude Code's plan, and its session and
-- weekly usage with the time until each resets. >_ continues the last Claude Code
-- session, + starts a new one in a project picked from a list. Under them, a row per live
-- Claude Code session with its state, to go to its terminal.
-- Left and Right move between the two buttons, Down and Up move through the sessions and
-- back, Enter or a click presses one, Escape closes.
-- features/agents.lua reads the usage file, ~/.claude.json and the session files, and passes them in.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = require("card")

local agents = {}

local DASH = "—"
local DAY, HOUR, MINUTE = 86400, 3600, 60

agents.WIDTH = 400
agents.HEIGHT = 218

-- The session list: its rule and gap above, then one row per session, at most six shown.
local SESSIONS_CHROME = 25
local SESSION_ROW = 30
local SESSIONS_SHOWN = 6

-- The background section has a title line above its rows.
local SECTION_TITLE = 22

local function sectionHeight(count, titled)
  if count <= 0 then return 0 end
  return SESSIONS_CHROME + (titled and SECTION_TITLE or 0) + math.min(count, SESSIONS_SHOWN) * SESSION_ROW
end

-- The card's height with sessionCount live sessions and backgroundCount background ones;
-- the same as before with neither.
function agents.height(sessionCount, backgroundCount)
  return agents.HEIGHT + sectionHeight(sessionCount) + sectionHeight(backgroundCount or 0, true)
end

-- A session row's id names its terminal, so it can't be taken for a button's.
local SESSION_ID = "session:"

function agents.sessionTty(id)
  return id:match("^" .. SESSION_ID .. "(.+)$")
end

-- A background session's row is named by its id in Claude Code's agent view.
local BACKGROUND_ID = "background:"

function agents.backgroundId(id)
  return id:match("^" .. BACKGROUND_ID .. "(.+)$")
end

-- Agent view's states as omv names them; any other, such as failed, shows as it is.
local BACKGROUND_STATES = { blocked = "asks", working = "working", done = "done" }
local BACKGROUND_RANK = { asks = 1, working = 2, done = 3 }

-- Rows for the background sessions in a decoded `claude agents --json` list: asking first,
-- then working, done and the rest, newest first in each. Interactive sessions are left
-- out, since the hooks already list them.
function agents.background(list)
  if type(list) ~= "table" then return {} end
  local rows = {}
  for _, session in ipairs(list) do
    if type(session) == "table" and session.kind == "background" and session.id then
      local folder = tostring(session.cwd or ""):match("([^/]+)/*$") or "?"
      local state = BACKGROUND_STATES[session.state] or tostring(session.state or "unknown")
      rows[#rows + 1] = { id = session.id, label = session.name or folder, state = state, cwd = session.cwd,
        hint = folder .. " · " .. state, started = tonumber(session.startedAt) or 0 }
    end
  end
  table.sort(rows, function(a, b)
    local rankA, rankB = BACKGROUND_RANK[a.state] or 4, BACKGROUND_RANK[b.state] or 4
    if rankA ~= rankB then return rankA < rankB end
    return a.started > b.started
  end)
  return rows
end

-- What claude needs to open a background session in a terminal. Only a plain id, as
-- agent view gives them, ever reaches the shell.
function agents.attachArguments(id)
  if not tostring(id or ""):match("^[%w%-]+$") then return nil end
  return "attach " .. id
end

local PLANS = { claude_pro = "Pro", claude_max = "Max" }

local function window(used, resets, now)
  if resets <= now then return { percent = 0 } end
  return { percent = math.floor(used + 0.5), left = resets - now }
end

-- Reads ~/.local/state/omv/claude-usage: "<5h %> <5h reset> <7d %> <7d reset>".
-- A window past its reset counts as 0%, since the file only updates while Claude Code runs.
function agents.parseUsage(text, now)
  local values = {}
  for number in tostring(text or ""):gmatch("%S+") do values[#values + 1] = tonumber(number) end
  if #values < 4 then return nil end
  for index = 1, 4 do
    if not values[index] then return nil end
  end
  return { five = window(values[1], values[2], now), seven = window(values[3], values[4], now) }
end

function agents.left(seconds)
  if not seconds then return DASH end
  if seconds >= DAY then
    return string.format("%dd %dh", math.floor(seconds / DAY), math.floor(seconds % DAY / HOUR))
  end
  return string.format("%dh %02dm", math.floor(seconds / HOUR), math.floor(seconds % HOUR / MINUTE))
end

-- organizationType from ~/.claude.json, such as "claude_pro".
function agents.plan(organizationType)
  return PLANS[organizationType]
end

-- The folder a Claude Code session ran in, from its .jsonl file: the first "cwd" found.
function agents.sessionCwd(text)
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local cwd = line:match('"cwd"%s*:%s*"([^"]+)"')
    if cwd then return cwd end
  end
  return nil
end

-- The sessions whose folder still exists, newest first. exists(folder) checks the disk.
local function living(sessions, exists)
  local kept = {}
  for _, session in ipairs(sessions) do
    if exists(session.cwd) then kept[#kept + 1] = session end
  end
  table.sort(kept, function(a, b) return a.modified > b.modified end)
  return kept
end

-- sessions = { { cwd, modified } }. Gives each folder that still exists once, the most
-- recent first, so a deleted project never opens a window that closes at once.
function agents.projects(sessions, exists)
  local latest = {}
  for _, session in ipairs(living(sessions, exists)) do
    if not latest[session.cwd] then latest[session.cwd] = session.modified end
  end
  local folders = {}
  for folder in pairs(latest) do folders[#folders + 1] = folder end
  table.sort(folders, function(a, b) return latest[a] > latest[b] end)
  return folders
end

-- The session >_ continues: the newest one whose folder still exists.
function agents.latest(sessions, exists)
  return living(sessions, exists)[1]
end

local function folderName(path)
  return path:match("([^/]+)/*$") or path
end

local function age(seconds)
  if seconds < HOUR then return math.max(0, math.floor(seconds / MINUTE)) .. "m ago" end
  if seconds < DAY then return math.floor(seconds / HOUR) .. "h ago" end
  return math.floor(seconds / DAY) .. "d ago"
end

-- Rows for the resume list: each session whose folder still exists, newest first, named by
-- its title when Claude Code gave it one, else by its folder. sessions = { { id, cwd, modified, title } }.
function agents.resumeRows(sessions, exists, now)
  local rows = {}
  for _, session in ipairs(living(sessions, exists)) do
    rows[#rows + 1] = { id = session.id, icon = "󰋚", label = session.title or folderName(session.cwd),
      hint = folderName(session.cwd) .. " · " .. age(now - session.modified) }
  end
  return rows
end

-- Reads the JSON string that starts at position start, just after its opening quote, and
-- gives its text with \" and \\ undone, or nil when it never closes.
local function jsonString(text, start)
  local parts, index = {}, start
  while index <= #text do
    local character = text:sub(index, index)
    if character == '"' then return table.concat(parts) end
    if character == "\\" then
      local escaped = text:sub(index + 1, index + 1)
      parts[#parts + 1] = (escaped == "n" or escaped == "t") and " " or escaped
      index = index + 2
    else
      parts[#parts + 1] = character
      index = index + 1
    end
  end
  return nil
end

-- The title Claude Code gave a session, from its file: the last "aiTitle" in it, since a
-- later one replaces an earlier one. nil when it has none.
function agents.sessionTitle(text)
  local title, from = nil, 1
  text = tostring(text or "")
  while true do
    local _, finish = text:find('"aiTitle"%s*:%s*"', from)
    if not finish then return title end
    title = jsonString(text, finish + 1) or title
    from = finish + 1
  end
end

-- What claude needs to resume a session. Only a plain id, letters, digits and dashes as
-- Claude Code names its files, ever reaches the shell.
function agents.resumeArguments(id)
  if not tostring(id or ""):match("^[%w%-]+$") then return nil end
  return "--resume " .. id
end

-- Rows for card.html: each project by its folder name, with its path from home.
function agents.projectRows(folders, home)
  local rows = {}
  for _, folder in ipairs(folders) do
    local short = folder:sub(1, #home) == home and ("~" .. folder:sub(#home + 1)) or folder
    rows[#rows + 1] = { id = folder, icon = "󰉋", label = folderName(folder), hint = short }
  end
  return rows
end

function agents.shellQuote(text)
  return "'" .. text:gsub("'", [['\'']]) .. "'"
end

local STYLE = [[
  body { padding: 22px 24px; display: block; }
  .head { display: flex; align-items: center; gap: 16px; padding-bottom: 16px; border-bottom: 1px solid #2a2a2a; }
  .head .icon { font-size: 28px; width: 30px; text-align: center; }
  .head .title { font-size: 18px; }
  .head .sub { color: #7a7a7a; letter-spacing: 2px; font-size: 13px; margin-top: 4px; }
  .actions { margin-left: auto; display: flex; gap: 8px; }
  .btn { width: 40px; height: 36px; display: flex; align-items: center; justify-content: center;
    background: #1a1a1a; color: #bdbdbd; font-size: 16px; cursor: default; }
  .btn.selected { background: #333; color: #fff; }
  .agent { display: flex; align-items: center; gap: 12px; margin: 18px 0 14px; }
  .agent .logo { height: 20px; width: auto; }
  .agent .logo.glyph { color: #d97757; font-size: 20px; line-height: 20px; text-align: center; }
  .agent .name { font-size: 16px; flex: 1; }
  .agent .plan { color: #7a7a7a; font-size: 13px; }
  .limit { display: grid; grid-template-columns: 90px 1fr 70px; align-items: center; gap: 14px; height: 30px; font-size: 14px; }
  .limit .bar { height: 4px; background: #2a2a2a; border-radius: 2px; }
  .limit .fill { display: block; height: 4px; background: #fff; border-radius: 2px; }
  .limit .left { color: #7a7a7a; text-align: right; white-space: nowrap; }
  .live { margin-top: 14px; border-top: 1px solid #2a2a2a; padding-top: 10px; max-height: 180px;
    overflow-y: auto; scrollbar-width: none; }
  .live::-webkit-scrollbar { display: none; }
  .live.titled { max-height: 202px; }
  .live .heading { height: 22px; line-height: 22px; padding: 0 10px; color: #7a7a7a; font-size: 12px; letter-spacing: 1px; }
  .session { display: flex; align-items: center; height: 30px; padding: 0 10px; border-radius: 4px;
    font-size: 14px; cursor: default; }
  .session .name { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .session .hint { color: #7a7a7a; padding-left: 12px; white-space: nowrap; }
  .session.asks .hint { color: #fff; }
  .session.selected { background: #fff; color: #000; }
  .session.selected .hint { color: #3a3a3a; }
]]

local SCRIPT = [[
  const buttons = Array.from(document.querySelectorAll(".btn"));
  const sessions = Array.from(document.querySelectorAll(".session"));
  const send = (type, id) => window.webkit.messageHandlers.omv.postMessage({ type, id: id || "" });
  // A button is selected while row is -1; Down moves into the sessions, Up back out.
  let button = 0;
  let row = -1;
  const draw = () => {
    buttons.forEach((element, index) => element.classList.toggle("selected", row < 0 && index === button));
    sessions.forEach((element, index) => element.classList.toggle("selected", index === row));
    if (row >= 0) sessions[row].scrollIntoView({ block: "nearest" });
  };
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") return send("close");
    if (event.key === "Enter") return send("choose", (row < 0 ? buttons[button] : sessions[row]).dataset.id);
    if (event.key === "ArrowRight" && row < 0) button = (button + 1) % buttons.length;
    else if (event.key === "ArrowLeft" && row < 0) button = (button - 1 + buttons.length) % buttons.length;
    else if (event.key === "ArrowDown" && sessions.length) row = Math.min(row + 1, sessions.length - 1);
    else if (event.key === "ArrowUp" && row >= 0) row = row - 1;
    else return;
    event.preventDefault();
    draw();
  });
  buttons.concat(sessions).forEach((element) => element.addEventListener("click", () => send("choose", element.dataset.id)));
  draw();
]]

local function limit(name, usage)
  usage = usage or { percent = 0 }
  return "<div class=limit><span>" .. name .. "</span>"
    .. '<span class=bar><i class=fill style="width: ' .. usage.percent .. '%"></i></span>'
    .. "<span class=left>" .. agents.left(usage.left) .. "</span></div>"
end

-- A row per live session, as claudewait.rows gives them: { id = tty, label, hint, state }.
-- prefix marks where the rows come from; heading titles the section.
local function sessionList(sessions, prefix, heading)
  if not sessions or #sessions == 0 then return "" end
  local rows = {}
  for _, session in ipairs(sessions) do
    rows[#rows + 1] = '<div class="session ' .. card.escape(session.state or "") .. '" data-id="'
      .. card.escape(prefix .. session.id) .. '"><span class=name>' .. card.escape(session.label)
      .. "</span><span class=hint>" .. card.escape(session.hint or "") .. "</span></div>"
  end
  if not heading then return "<div class=live>" .. table.concat(rows) .. "</div>" end
  return '<div class="live titled"><div class=heading>' .. card.escape(heading) .. "</div>" .. table.concat(rows) .. "</div>"
end

-- model = { plan, usage = agents.parseUsage(...), logo = a data: URL of the Claude logo,
--   sessions = the live sessions' rows, background = agents.background(...) }
function agents.html(model)
  local usage = model.usage or {}
  local logo = model.logo and ('<img class=logo src="' .. card.escape(model.logo) .. '">') or "<span class='logo glyph'>✳</span>"
  return "<!doctype html><meta charset=utf-8><style>" .. card.STYLE .. STYLE .. "</style><body>"
    .. "<div class=head><div class=icon>󰚩</div><div><div class=title>Agents</div><div class=sub>SUBSCRIPTIONS</div></div>"
    .. '<div class=actions><div class=btn data-id="agents.new">+</div><div class=btn data-id="agents.continue">&gt;_</div><div class=btn data-id="agents.resume">󰋚</div></div></div>'
    .. "<div class=agent>" .. logo .. "<span class=name>Claude Code</span>"
    .. "<span class=plan>" .. card.escape(model.plan or "") .. "</span></div>"
    .. limit("Session", usage.five) .. limit("Weekly", usage.seven)
    .. sessionList(model.sessions, SESSION_ID)
    .. sessionList(model.background, BACKGROUND_ID, "BACKGROUND")
    .. "<script>" .. SCRIPT .. "</script></body>"
end

return agents
