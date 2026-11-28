-- Voice to agents (Right Command): "tell <project> …" puts the rest into that Claude
-- session's prompt, "reply …" into the prompt of the one that finished last, and "one …"
-- into the prompt of the session numbered 1 in the pill, since numbers are heard far more
-- reliably than project names. Only a session
-- that's done takes it, as with Option+P: one that works would be interrupted, and one that
-- asks would take the words as its answer, so for those the words are only copied. Enter is
-- never pressed. features/dictation.lua runs the key and the pill.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local sendto = require("sendto")
local soundmatch = require("soundmatch")

local voiceagents = {}

-- Up to this many spoken words name the project, such as "omv web" for omv-web; spelled out,
-- a letter a word, up to SPELLED_WORDS, so "oh em vee test" reaches omv-test.
local NAME_WORDS, SPELLED_WORDS = 3, 6

voiceagents.HINT = 'Say "tell <project> …" or "reply …"'

local function normal(text)
  return tostring(text or ""):lower():gsub("[^%w]", "")
end

-- A session's number as said: a digit, a word, or a word heard for one at the start.
local NUMBERS = { one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9,
  won = 1, to = 2, too = 2, ["for"] = 4 }

local function numberOf(word)
  local said = normal(word)
  local digit = tonumber(said)
  if digit and digit >= 1 and digit <= 9 and #said == 1 then return digit end
  return NUMBERS[said]
end

-- A leading number, "one", "number one" or "1", and the words after it; nil without one.
local function leadingNumber(words)
  local at = normal(words[1]) == "number" and 2 or 1
  local index = numberOf(words[at])
  if not index then return nil end
  local rest = {}
  for position = at + 1, #words do rest[#rest + 1] = words[position] end
  return index, rest
end

-- What was said: tell or reply and the words after it; number with its index, for a session
-- picked by its number in the pill; nil for anything else.
function voiceagents.parse(text)
  local words = {}
  for word in tostring(text or ""):gmatch("%S+") do words[#words + 1] = word end
  local verb = normal(words[1])
  local after = {}
  for position = verb == "tell" and 2 or 1, #words do after[#after + 1] = words[position] end
  local index, rest = leadingNumber(after)
  if index then return { verb = "number", index = index, words = rest } end
  if verb ~= "tell" and verb ~= "reply" then return nil end
  table.remove(words, 1)
  if verb == "reply" and normal(words[1]) == "to" then table.remove(words, 1) end
  return { verb = verb, words = words }
end

-- The letters' names as said, so "oh em vee" is heard as omv; "double you" is W.
local LETTERS = { ay = "a", bee = "b", see = "c", dee = "d", ee = "e", eff = "f", gee = "g", aitch = "h", jay = "j",
  kay = "k", el = "l", em = "m", en = "n", oh = "o", pee = "p", cue = "q", are = "r", ess = "s", tee = "t", you = "u",
  vee = "v", ex = "x", why = "y", zee = "z", zed = "z" }

-- The first count words joined as a name, with each letter's name read as its letter.
local function asLetters(words, count)
  local out, index = {}, 1
  while index <= count do
    local word = normal(words[index])
    if word == "double" and normal(words[index + 1]) == "you" and index + 1 <= count then
      out[#out + 1], index = "w", index + 2
    else
      out[#out + 1], index = LETTERS[word] or word, index + 1
    end
  end
  return table.concat(out)
end

-- How well heard matches a folder's name: 2 the same, 1 one letter off, 0 not at all. A short
-- name may be one letter off only when it was heard as an acronym, such as LMV for omv: the
-- dictation model writes spelled-out letters that way, while a short word one letter off, such
-- as omb, is more likely another word.
local function score(heard, name, acronym)
  if heard == "" then return 0 end
  if heard == name then return 2 end
  if (#name >= soundmatch.NEAR_LENGTH or acronym) and soundmatch.oneEdit(heard, name) then return 1 end
  return 0
end

-- Whether the first count words were heard as capitals, such as LMV.
local function capitals(words, count)
  for index = 1, count do
    if not tostring(words[index]):match("^%u%u+%p*$") then return false end
  end
  return true
end

-- The session the first words name, and the words left as the prompt; else nil and why:
-- tied (with the names, for the hint), unknown, or empty when nothing follows the name.
-- The first one to three words are tried as the name, spaces and letters spelled out
-- counting as nothing; the same name beats one letter off, then the longer name wins.
function voiceagents.match(words, rows)
  local best, bestScore, bestCount, tied = nil, 0, 0, {}
  for count = 1, math.min(SPELLED_WORDS, #words) do
    local heard = count <= NAME_WORDS and normal(table.concat(words, "", 1, count)) or ""
    local spelled = asLetters(words, count)
    for _, row in ipairs(rows or {}) do
      local name = normal(row.label)
      local value = math.max(score(heard, name, capitals(words, count)), score(spelled, name))
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

-- The sessions in the order the pill numbers them, each with .number, 1 to 9: the one a
-- reply goes to first, then the other done ones, newest first, then those asking, then those
-- working, which only take a copy.
function voiceagents.numbered(rows, preferTty)
  local first = voiceagents.lastDone(rows, preferTty)
  local list = { first }
  local done, asks, working = {}, {}, {}
  for _, row in ipairs(rows or {}) do
    if row ~= first then
      local group = row.state == "done" and done or row.state == "asks" and asks or working
      group[#group + 1] = row
    end
  end
  for position = #done, 1, -1 do list[#list + 1] = done[position] end
  for _, group in ipairs({ asks, working }) do
    for _, row in ipairs(group) do list[#list + 1] = row end
  end
  local numbered = {}
  for _, row in ipairs(list) do
    if #numbered >= 9 then break end
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    copy.number = #numbered + 1
    numbered[#numbered + 1] = copy
  end
  return numbered
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
  if said.verb == "number" then
    row, prompt = voiceagents.numbered(rows, preferTty)[said.index], table.concat(said.words, " ")
    if not row then return { kind = "none", hint = "No session " .. said.index } end
  elseif said.verb == "reply" then
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

local function distance(a, b)
  local previous = {}
  for j = 0, #b do previous[j] = j end
  for i = 1, #a do
    local current = { [0] = i }
    for j = 1, #b do
      local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
      current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
    end
    previous = current
  end
  return previous[#b]
end

-- The words to send when nothing matched and a number is picked after release: all of text
-- without a verb; after "reply"; after "tell" and the words nearest a folder's name.
function voiceagents.leftover(text, rows)
  local words = {}
  for word in tostring(text or ""):gmatch("%S+") do words[#words + 1] = word end
  local verb = normal(words[1])
  local skip = 0
  if verb == "reply" then skip = 1 end
  if verb == "tell" then
    local best, count = math.huge, 1
    for take = 1, math.min(NAME_WORDS, #words - 1) do
      local heard = normal(table.concat(words, "", 2, 1 + take))
      for _, row in ipairs(rows or {}) do
        local away = distance(heard, normal(row.label))
        if away < best then best, count = away, take end
      end
    end
    skip = 1 + count
  end
  return sendto.clean(table.concat(words, " ", skip + 1))
end

-- The pill's numbered rows, at most six: { number, label, state, chosen }, chosen for the
-- session on chosenTty, where the words said so far go.
local SHOWN = 6

function voiceagents.listLines(numbered, chosenTty)
  local lines = {}
  for position = 1, math.min(SHOWN, #numbered) do
    local row = numbered[position]
    lines[#lines + 1] = { number = row.number, label = row.label, state = row.hint or row.state,
      working = row.state ~= "done", chosen = chosenTty ~= nil and row.id == chosenTty }
  end
  return lines
end

-- The pill's line under the words: where they go and the session's state, or the hint.
function voiceagents.resultLine(target)
  if target.kind == "none" then return target.hint end
  local line = "→ " .. target.row.label .. " · " .. (target.row.hint or target.row.state)
  if target.kind == "copy" then line = line .. " · release copies it" end
  return line
end

return voiceagents
