-- Voice to agents (Right Command): "tell <project> …" puts the rest into that Claude
-- session's prompt, "reply …" into the prompt of the one that finished last. Only a session
-- that's done takes it, as with Option+P: one that works would be interrupted, and one that
-- asks would take the words as its answer, so for those the words are only copied. Enter is
-- never pressed. features/dictation.lua runs the key and the pill.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local sendto = require("sendto")

local voiceagents = {}

-- Up to this many spoken words name the project, such as "omv web" for omv-web.
local NAME_WORDS = 3
-- A name this long or longer may be heard one letter off, such as "dashbord".
local NEAR_LENGTH = 5

voiceagents.HINT = 'Say "tell <project> …" or "reply …"'

local function normal(text)
  return tostring(text or ""):lower():gsub("[^%w]", "")
end

-- What was said: the verb, tell or reply, and the words after it; nil for anything else.
function voiceagents.parse(text)
  local words = {}
  for word in tostring(text or ""):gmatch("%S+") do words[#words + 1] = word end
  local verb = normal(words[1])
  if verb ~= "tell" and verb ~= "reply" then return nil end
  table.remove(words, 1)
  if verb == "reply" and normal(words[1]) == "to" then table.remove(words, 1) end
  return { verb = verb, words = words }
end

-- Whether a and b are at most one letter added, dropped or changed apart.
local function oneEdit(a, b)
  if math.abs(#a - #b) > 1 then return false end
  local i, j, edits = 1, 1, 0
  while i <= #a and j <= #b do
    if a:sub(i, i) == b:sub(j, j) then
      i, j = i + 1, j + 1
    else
      edits = edits + 1
      if edits > 1 then return false end
      if #a > #b then i = i + 1
      elseif #b > #a then j = j + 1
      else i, j = i + 1, j + 1 end
    end
  end
  return edits + (#a - i + 1) + (#b - j + 1) <= 1
end

-- How well heard matches a folder's name: 2 the same, 1 one letter off, 0 not at all.
local function score(heard, name)
  if heard == "" then return 0 end
  if heard == name then return 2 end
  if #name >= NEAR_LENGTH and oneEdit(heard, name) then return 1 end
  return 0
end

-- The session the first words name, and the words left as the prompt; else nil and why:
-- tied (with the names, for the hint), unknown, or empty when nothing follows the name.
-- The first one to three words are tried as the name, spaces and letters spelled out
-- counting as nothing; the same name beats one letter off, then the longer name wins.
function voiceagents.match(words, rows)
  local best, bestScore, bestCount, tied = nil, 0, 0, {}
  for count = 1, math.min(NAME_WORDS, #words) do
    local heard = normal(table.concat(words, "", 1, count))
    for _, row in ipairs(rows or {}) do
      local value = score(heard, normal(row.label))
      if value > 0 and (value > bestScore or (value == bestScore and count > bestCount)) then
        best, bestScore, bestCount, tied = row, value, count, { row }
      elseif value > 0 and value == bestScore and count == bestCount and row ~= best and row.id ~= best.id then
        tied[#tied + 1] = row
      end
    end
  end
  if not best then return nil, "unknown" end
  if #tied > 1 then
    local names = {}
    for _, row in ipairs(tied) do names[#names + 1] = row.label end
    return nil, "tied", names
  end
  local prompt = table.concat(words, " ", bestCount + 1)
  if prompt:match("^%s*$") then return nil, "empty" end
  return best, prompt
end

-- The session a reply goes to: preferTty's, the one that spoke last, while it's done; else
-- the done one that finished last, which claudewait.rows lists last among the done.
function voiceagents.lastDone(rows, preferTty)
  local last = nil
  for _, row in ipairs(rows or {}) do
    if row.state == "done" then
      if preferTty and row.id == preferTty then return row end
      last = row
    end
  end
  return last
end

local REASONS = {
  unknown = "No agent by that name: " .. voiceagents.HINT,
  empty = "Say what to tell it after its name",
}

-- What release does with text: { kind = paste, row, prompt } for a done session; { kind =
-- copy, row, prompt, why = working or asks } for a busy one; { kind = none, hint } otherwise.
function voiceagents.target(text, rows, preferTty)
  local said = voiceagents.parse(text)
  if not said then return { kind = "none", hint = voiceagents.HINT } end
  local row, prompt, names
  if said.verb == "reply" then
    row, prompt = voiceagents.lastDone(rows, preferTty), table.concat(said.words, " ")
    if not row then return { kind = "none", hint = "No agent is waiting for a reply" } end
  else
    row, prompt, names = voiceagents.match(said.words, rows)
    if not row then
      local hint = prompt == "tied" and ("Which one: " .. table.concat(names, ", ") .. "?") or REASONS[prompt]
      return { kind = "none", hint = hint }
    end
  end
  prompt = sendto.clean(prompt)
  if not prompt then return { kind = "none", hint = REASONS.empty } end
  if row.state == "done" then return { kind = "paste", row = row, prompt = prompt } end
  return { kind = "copy", row = row, prompt = prompt, why = row.state }
end

-- The pill's line under the words: where they go and the session's state, or the hint.
function voiceagents.resultLine(target)
  if target.kind == "none" then return target.hint end
  local line = "→ " .. target.row.label .. " · " .. (target.row.hint or target.row.state)
  if target.kind == "copy" then line = line .. " · release copies it" end
  return line
end

return voiceagents
