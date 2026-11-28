-- Right Command's commands, beside its words for agents: "open <anything>" runs a palette row,
-- an app, an open window or one of omv's commands, as Enter in the palette would; "go to
-- <workspace>" and "move this to <workspace>" switch, or move the focused window, by number or
-- name; "close" and "quit" end something, so they wait for Enter after release. Names are
-- matched by soundmatch, so "open said" opens Zed. features/dictation.lua runs the key and the
-- pill, and does what target says.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local soundmatch = require("soundmatch")
local voiceagents = require("voiceagents")

local voicecommands = {}

voicecommands.HINT = 'Say "open …", "go to …", "move this to …", "close …" or "quit …"'
-- "Which one?" lists at most this many.
local CHOICES = 5

local NUMBERS = { one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9,
  won = 1, to = 2, too = 2, ["for"] = 4 }

local function plain(word)
  return soundmatch.normal(word)
end

local function wordsOf(text)
  local words = {}
  for word in tostring(text or ""):gmatch("%S+") do words[#words + 1] = word end
  return words
end

-- Drops the first words when they're the wanted ones, in any case and punctuation.
local function drop(words, wanted)
  for index, word in ipairs(wanted) do
    if plain(words[index]) ~= word then return nil end
  end
  local rest = {}
  for index = #wanted + 1, #words do rest[#rest + 1] = words[index] end
  return rest
end

-- What was said: { verb = open, go, move, close or quit, words = the rest }; nil otherwise.
function voicecommands.parse(text)
  local words = wordsOf(text)
  local forms = {
    { "open", { "open" } },
    { "go", { "go", "to" } }, { "go", { "switch", "to" } }, { "go", { "go" } },
    { "move", { "move", "this", "to" } }, { "move", { "move", "it", "to" } }, { "move", { "move", "to" } },
    { "close", { "close" } }, { "quit", { "quit" } },
  }
  for _, form in ipairs(forms) do
    local rest = drop(words, form[2])
    if rest then return { verb = form[1], words = rest } end
  end
  return nil
end

-- A workspace by its number, said or written, or by its name.
local function workspaceFor(words, list)
  local said = table.concat(words, " ")
  local number = NUMBERS[plain(words[1])] or tonumber(plain(said))
  if number then
    for _, workspace in ipairs(list or {}) do
      if tonumber(workspace.number) == number then return workspace end
    end
  end
  local named = {}
  for _, workspace in ipairs(list or {}) do
    if workspace.name then named[#named + 1] = { label = workspace.name, workspace = workspace } end
  end
  local ranked, verdict = soundmatch.rank(said, named)
  return verdict == "strong" and ranked[1].workspace or nil
end

-- The rows "open" can run: windows, apps and omv's commands.
local function openable(items)
  local list = {}
  for _, item in ipairs(items or {}) do
    if tostring(item.id):match("^window:") or tostring(item.id):match("^app:") or tostring(item.id):match("^command:") then
      list[#list + 1] = item
    end
  end
  return list
end

-- The best of ranked, all those sharing the best score, at most CHOICES.
local function tiedBest(ranked)
  local list = {}
  for _, item in ipairs(ranked) do
    if item.score ~= ranked[1].score or #list >= CHOICES then break end
    list[#list + 1] = item
  end
  return list
end

-- Of a tie, the one item that's an open window or a running app, if only one is; nil otherwise.
local function theRunning(tied, running)
  local isRunning = {}
  for _, name in ipairs(running or {}) do isRunning[name] = true end
  local found = nil
  for _, item in ipairs(tied) do
    if tostring(item.id):match("^window:") or (tostring(item.id):match("^app:") and isRunning[item.label]) then
      if found then return nil end
      found = item
    end
  end
  return found
end

local function open(words, context)
  local said = table.concat(words, " ")
  local ranked, verdict = soundmatch.rank(said, openable(context.items))
  if verdict == "strong" then return { kind = "run", item = ranked[1] } end
  if verdict == "tied" then
    local tied = tiedBest(ranked)
    -- A tie that only one running app or open window is in goes to it: "open z" is the Zed
    -- you have open, not zoom.us.
    local running = theRunning(tied, context.running)
    if running then return { kind = "run", item = running } end
    return { kind = "choose", candidates = tied }
  end
  return { kind = "none", hint = "Nothing sounds like " .. said }
end

local function quit(words, context)
  local apps = {}
  for _, name in ipairs(context.running or {}) do apps[#apps + 1] = { label = name } end
  local said = table.concat(words, " ")
  local ranked, verdict = soundmatch.rank(said, apps)
  if verdict ~= "strong" then return { kind = "none", hint = "No running app sounds like " .. said } end
  return { kind = "confirm", action = "quit", name = ranked[1].label }
end

local function close(words, context)
  local said = table.concat(words, " ")
  if said == "" or plain(said) == "this" or plain(said) == "it" then
    if not context.focused then return { kind = "none", hint = "No window to close" } end
    return { kind = "confirm", action = "close", id = context.focused.id, name = context.focused.label }
  end
  local windows = {}
  for _, item in ipairs(context.items or {}) do
    local id = tostring(item.id):match("^window:(.+)$")
    if id then windows[#windows + 1] = { label = item.label, id = id } end
  end
  local ranked, verdict = soundmatch.rank(said, windows)
  if verdict ~= "strong" then return { kind = "none", hint = "No window sounds like " .. said } end
  return { kind = "confirm", action = "close", id = ranked[1].id, name = ranked[1].label }
end

-- What release does with text, given context { items (the palette's rows), workspaces
-- ({ number, name }), running (app names), focused ({ id, label }) }: run an item; switch to,
-- or move the focused window to, a workspace; confirm a close or quit; choose among tied
-- candidates; or none, with a hint.
function voicecommands.target(text, context)
  local said = voicecommands.parse(text)
  if not said or #said.words == 0 and said.verb ~= "close" then return { kind = "none", hint = voicecommands.HINT } end
  if said.verb == "open" then return open(said.words, context) end
  if said.verb == "go" or said.verb == "move" then
    local workspace = workspaceFor(said.words, context.workspaces)
    if not workspace then return { kind = "none", hint = "No workspace " .. table.concat(said.words, " ") } end
    return { kind = said.verb == "go" and "workspace" or "move", workspace = workspace }
  end
  if said.verb == "quit" then return quit(said.words, context) end
  return close(said.words, context)
end

local KINDS = { ["window:"] = "window", ["app:"] = "app", ["command:"] = "command" }

local function kindOf(item)
  for prefix, kind in pairs(KINDS) do
    if tostring(item.id):sub(1, #prefix) == prefix then return kind end
  end
  return "item"
end

local function workspaceName(workspace)
  return workspace.number .. (workspace.name and (" · " .. workspace.name) or "")
end

-- The pill's line: where release goes, or the hint.
function voicecommands.resultLine(target)
  if target.kind == "run" then return "→ " .. target.item.label .. " · " .. kindOf(target.item) end
  if target.kind == "workspace" then return "→ workspace " .. workspaceName(target.workspace) end
  if target.kind == "move" then return "→ move this to " .. workspaceName(target.workspace) end
  if target.kind == "confirm" then
    return (target.action == "quit" and "Quit " or "Close ") .. target.name .. " · press Enter after release"
  end
  if target.kind == "choose" then return "Which one? release shows " .. #target.candidates end
  return target.hint
end

local TONES = { paste = "go", run = "go", workspace = "go", move = "go", copy = "warn", confirm = "warn" }

-- What the chip at the pill's right names: the session, the item, or the workspace.
local function chipOf(target)
  if target.row then return target.row.label end
  if target.item then return target.item.label end
  if target.workspace then return "workspace " .. target.workspace.number end
  return target.name
end

voicecommands.BOTH_HINT = 'Say "open …", "go to …", "tell <project> …" or "reply …"'

-- What Right Command's words do: an agent's verb (tell, reply, a number) goes to voiceagents;
-- else, with context, a command's verb to target; else nothing, with a hint naming both. The
-- answer carries source (agent or command), line (the pill's line), chip (its name at the
-- right) and tone (go, warn, or dim for a hint or a choice).
function voicecommands.decide(text, sessions, spoke, context)
  local target
  if voiceagents.parse(text) then
    target = voiceagents.target(text, sessions, spoke)
    target.source, target.line = "agent", voiceagents.resultLine(target)
  elseif context and voicecommands.parse(text) then
    target = voicecommands.target(text, context)
    target.source, target.line = "command", voicecommands.resultLine(target)
  else
    target = { kind = "none", hint = voicecommands.BOTH_HINT, source = "agent", line = voicecommands.BOTH_HINT }
  end
  target.chip, target.tone = chipOf(target), TONES[target.kind] or "dim"
  return target
end

return voicecommands
