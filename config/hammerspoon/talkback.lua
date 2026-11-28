-- Talk-back: when an agent finishes, the start of its last message is spoken in your
-- headphones, with a pill showing it. claude-waiting.sh keeps the message beside the session's
-- state while the flag is on; features/talkback.lua watches for a finish and speaks.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local talkback = {}

talkback.MAX_WORDS = 20

-- Drops a UTF-8 character cut short at the end, as the hook's 600-byte cut can leave.
local function wholeCharacters(text)
  for back = 1, math.min(3, #text) do
    local byte = text:byte(#text - back + 1)
    if byte < 0x80 then return text end
    if byte >= 0xC0 then
      local length = byte >= 0xF0 and 4 or byte >= 0xE0 and 3 or 2
      if back < length then return text:sub(1, #text - back) end
      return text
    end
  end
  return text
end

-- The message as it reads aloud: no code, links as their text, paths as their file name, and
-- no markdown marks.
local function plain(text)
  text = text:gsub("```.-```", " "):gsub("```.*$", " ")
  text = text:gsub("%[([^%]]+)%]%([^%)]*%)", "%1")
  text = text:gsub("[%w%._~%-:]*/[%w%._~%-/]*", function(path)
    return path:match("([^/]+)/*$") or ""
  end)
  -- A heading names the reply, not what was done, and reads as part of the sentence after it.
  text = ("\n" .. text):gsub("\n%s*#+[^\n]*", "\n")
  text = text:gsub("\n%s*[%-%*]%s+", "\n"):gsub("^%s*[%-%*]%s+", "")
  text = text:gsub("[`|]", ""):gsub("%*%*", ""):gsub("__", "")
  return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function words(text)
  local list = {}
  for word in text:gmatch("%S+") do list[#list + 1] = word end
  return list
end

-- The line spoken for text, an agent's last message: its whole sentences up to maxWords, or
-- the first one cut at maxWords with "…" when that alone is longer; nil when nothing is left.
function talkback.line(text, maxWords)
  maxWords = maxWords or talkback.MAX_WORDS
  if type(text) ~= "string" then return nil end
  text = plain(wholeCharacters(text))
  if text == "" then return nil end
  local sentences = {}
  for sentence in (text:gsub("([%.!?]+)%s+", "%1\n") .. "\n"):gmatch("([^\n]+)\n") do sentences[#sentences + 1] = sentence end
  local first = words(sentences[1])
  if #first > maxWords then return table.concat(first, " ", 1, maxWords) .. "…" end
  local kept, count = {}, 0
  for _, sentence in ipairs(sentences) do
    local length = #words(sentence)
    if count + length > maxWords then break end
    kept[#kept + 1], count = sentence, count + length
  end
  return table.concat(kept, " ")
end

-- The sessions in after that turned done since before, as claudewait.newlyAsking does for asks.
function talkback.newlyDone(before, after)
  local wasDone = {}
  for _, session in ipairs(before or {}) do
    if session.state == "done" then wasDone[session.id] = true end
  end
  local done = {}
  for _, session in ipairs(after or {}) do
    if session.state == "done" and not wasDone[session.id] then done[#done + 1] = session end
  end
  return done
end

-- Whether a finish is spoken: c { flag, quiet (meeting mode holds notices), headphones,
-- recording (you're dictating), tty, viewedTty }. Never to the room, never over your own
-- voice, and not for the terminal you're looking at.
function talkback.due(c)
  return c.flag == true and not c.quiet and c.headphones == true and not c.recording and c.tty ~= c.viewedTty
end

-- Letters only Turkish uses among the languages a Mac reads, so the line gets a Turkish voice.
local TURKISH = { "ğ", "Ğ", "ı", "İ", "ş", "Ş" }

-- The language of the voice for text: "tr" for Turkish, nil for the system's own.
function talkback.voice(text)
  for _, letter in ipairs(TURKISH) do
    if tostring(text or ""):find(letter, 1, true) then return "tr" end
  end
  return nil
end

return talkback
