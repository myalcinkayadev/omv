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
-- output (the setting), recording (you're dictating), tty, viewedTty }. Only into headphones
-- unless the output setting is anywhere, never over your own voice, and not for the terminal
-- you're looking at.
function talkback.due(c)
  local heard = c.headphones == true or c.output == "anywhere"
  return c.flag == true and not c.quiet and heard and not c.recording and c.tty ~= c.viewedTty
end

-- The settings, in ~/.config/omv/dictation: talk-back voice and talk-back output.
local function settingOf(text, key)
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local name, value = line:gsub("#.*$", ""):match("^%s*([%w%s%-]-)%s*=%s*(.-)%s*$")
    if name == key then return value end
  end
  return nil
end

local VOICES = { "apple", "kokoro-woman", "kokoro-man" }
local KOKORO = { ["kokoro-woman"] = "af_heart", ["kokoro-man"] = "am_michael" }
local NAMES = { apple = "Apple", ["kokoro-woman"] = "Kokoro, woman", ["kokoro-man"] = "Kokoro, man" }

talkback.PREVIEW = "omv finished. Tests pass, and I changed two files."

-- The voice setting: apple, kokoro-woman or kokoro-man; apple when unset or unknown.
function talkback.voiceSetting(text)
  local value = settingOf(text, "talk-back voice")
  return NAMES[value] and value or "apple"
end

-- The output setting: headphones, or anywhere to speak on speakers too.
function talkback.outputSetting(text)
  return settingOf(text, "talk-back output") == "anywhere" and "anywhere" or "headphones"
end

-- The voice after current, for the card.
function talkback.nextVoice(current)
  for index, voice in ipairs(VOICES) do
    if voice == current then return VOICES[index % #VOICES + 1] end
  end
  return VOICES[1]
end

function talkback.voiceName(setting)
  return NAMES[setting] or NAMES.apple
end

-- What speaks line: Kokoro in the chosen voice once it's installed, Apple's own otherwise,
-- and for Turkish, which Kokoro doesn't speak.
function talkback.engineFor(setting, line, installed)
  if not KOKORO[setting] or not installed or talkback.voice(line) == "tr" then return { engine = "apple" } end
  return { engine = "kokoro", voice = KOKORO[setting] }
end

-- What plays as the card's voice changes: the sample line in the new voice; nil for Kokoro
-- before it's installed, which plays once the install is done.
function talkback.previewFor(setting, installed)
  if KOKORO[setting] and not installed then return nil end
  local engine = talkback.engineFor(setting, talkback.PREVIEW, installed)
  engine.line = talkback.PREVIEW
  return engine
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
