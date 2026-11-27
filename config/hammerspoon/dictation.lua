-- Dictation: hold Right Option alone to talk, release to type what was heard at the cursor;
-- tap it twice to talk hands-free, and once more to type. Recording starts at the press, so
-- the first word isn't cut off; the pill shows once the key has been held alone a moment, and
-- another key in that moment cancels it, so Right Option still types @, € and the rest.
-- dictate.swift hears it on the Mac; features/dictation.lua runs the key, the pill and the
-- paste. Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local dictation = {}

dictation.PATH = (os.getenv("HOME") or "") .. "/.config/omv/dictation"

-- How long Right Option is held alone before the pill shows; how quickly a second tap locks
-- it; how long a locked one runs before it types by itself; how long the clipboard waits
-- after the paste before it's put back, so the app reads the dictation, not the old contents.
dictation.HOLD_SECONDS, dictation.DOUBLE_SECONDS, dictation.LOCK_SECONDS = 0.3, 0.4, 300
-- A locked one types what it heard after this long without speech, as macOS's dictation
-- does; the pill counts down the last few seconds before either end.
dictation.SILENCE_SECONDS, dictation.COUNTDOWN_SECONDS = 30, 10
dictation.RESTORE_SECONDS = 0.6
local KEEP = 10
local RIGHT_OPTION = 61
local TRANSIENT, TEXT = "org.nspasteboard.TransientType", "public.utf8-plain-text"

local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A flagsChanged event's key as an event name: Right Option going down or up, up with Shift
-- held, or Shift going down on either side; else nil.
local SHIFTS = { [56] = true, [60] = true }

function dictation.eventFor(keyCode, optionDown, shiftDown)
  if SHIFTS[keyCode] then return shiftDown and "shift" or nil end
  if keyCode ~= RIGHT_OPTION then return nil end
  if optionDown then return "option-down" end
  return shiftDown and "option-up-shift" or "option-up"
end

function dictation.keys()
  return { phase = "idle" }
end

local function moveTo(state, phase, fields)
  for key in pairs(state) do state[key] = nil end
  state.phase = phase
  for key, value in pairs(fields or {}) do state[key] = value end
end

-- What one event does: option-down, option-up, option-up-shift (released with Shift held),
-- shift (a Shift tap), voice (speech heard), other (any other key), escape or tick, at time
-- in seconds. Gives the action, record, show, lock, finish, review or cancel, or nil; and
-- whether the event is swallowed, which only Esc is, and only while the pill listens.
local PHASES = {}

function PHASES.idle(state, event, time)
  if event ~= "option-down" then return nil, false end
  moveTo(state, "pressed", { since = time })
  return "record", false
end

function PHASES.pressed(state, event, time)
  local held = time - state.since
  if event == "tick" and held >= dictation.HOLD_SECONDS then
    moveTo(state, "listening")
    return "show", false
  end
  if (event == "option-up" or event == "option-up-shift") and held >= dictation.HOLD_SECONDS then
    moveTo(state, "idle")
    return event == "option-up" and "finish" or "review", false
  end
  if event == "option-up" or event == "option-up-shift" then
    moveTo(state, "tapped", { at = time })
    return nil, false
  end
  if event == "other" or event == "escape" then
    moveTo(state, "idle")
    return "cancel", false
  end
  return nil, false
end

function PHASES.tapped(state, event, time)
  local since = time - state.at
  if event == "option-down" and since <= dictation.DOUBLE_SECONDS then
    moveTo(state, "locked", { since = time, ignoreUp = true })
    return "lock", false
  end
  if event == "option-down" then
    moveTo(state, "pressed", { since = time })
    return "record", false
  end
  if (event == "tick" and since > dictation.DOUBLE_SECONDS) or event == "other" or event == "escape" then
    moveTo(state, "idle")
    return "cancel", false
  end
  return nil, false
end

function PHASES.listening(state, event)
  if event == "option-up" or event == "option-up-shift" then
    moveTo(state, "idle")
    return event == "option-up" and "finish" or "review", false
  end
  if event == "escape" then
    moveTo(state, "idle")
    return "cancel", true
  end
  if event == "other" then
    moveTo(state, "idle")
    return "cancel", false
  end
  return nil, false
end

function PHASES.locked(state, event, time)
  if event == "option-up" and state.ignoreUp then
    state.ignoreUp = false
    return nil, false
  end
  if event == "option-down" then
    moveTo(state, "finishing")
    return "finish", false
  end
  if event == "shift" then
    moveTo(state, "idle")
    return "review", false
  end
  if event == "escape" then
    moveTo(state, "idle")
    return "cancel", true
  end
  if event == "voice" then
    state.heard = time
    return nil, false
  end
  local quiet = time - (state.heard or state.since)
  if event == "tick" and (time - state.since >= dictation.LOCK_SECONDS or quiet >= dictation.SILENCE_SECONDS) then
    moveTo(state, "idle")
    return "finish", false
  end
  return nil, false
end

-- After the tap that finished a locked one: its release.
function PHASES.finishing(state, event)
  if event == "option-up" then moveTo(state, "idle") end
  return nil, false
end

function dictation.press(state, event, time)
  return PHASES[state.phase](state, event, time)
end

-- The whole seconds a locked one has left, when it's in its last 10, before 5 minutes or 30
-- seconds of silence, whichever comes first; nil otherwise.
function dictation.remaining(state, time)
  if state.phase ~= "locked" then return nil end
  local left = math.min(state.since + dictation.LOCK_SECONDS - time, (state.heard or state.since) + dictation.SILENCE_SECONDS - time)
  if left > dictation.COUNTDOWN_SECONDS then return nil end
  return math.max(0, math.ceil(left - 1e-6))
end

local function clock(seconds)
  seconds = math.max(0, math.floor(seconds))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The pill's header, from recording { started, stopped, locked, finishing, left, secure, app }:
-- { icon = mic, lock or spinner; live, whether the mic is on; status; timer; warning, whether
-- the timer is an orange countdown; target = { kind = app or password, name } }.
function dictation.header(recording, now)
  local icon, status = "mic", "Listening…"
  if recording.finishing then icon, status = "spinner", "Finishing…"
  elseif recording.locked then icon, status = "lock", "Locked" end
  local warning = recording.left ~= nil and not recording.finishing
  local timer = warning and (clock(recording.left) .. " left") or clock((recording.stopped or now) - recording.started)
  local target = recording.secure and { kind = "password", name = "password field" } or { kind = "app", name = recording.app or "" }
  return { icon = icon, live = not recording.finishing, status = status, timer = timer, warning = warning, target = target }
end

-- One line from the helper, "kind<tab>value": { kind, text | percent | level | problem },
-- or nil for a line it doesn't know.
function dictation.parse(line)
  local kind, value = tostring(line or ""):match("^(%a+)\t(.*)$")
  if kind == "partial" or kind == "final" then return { kind = kind, text = value } end
  if kind == "progress" then return { kind = kind, percent = tonumber(value) } end
  if kind == "level" then return { kind = kind, level = tonumber(value) } end
  if kind == "problem" then return { kind = kind, problem = value } end
  return nil
end

-- What a finished dictation does: types its text, or says nothing was heard.
function dictation.outcome(final)
  local text = trim(final)
  if text == "" then return { kind = "notice", text = "Didn't catch that" } end
  return { kind = "type", text = text }
end

local NOTICES = {
  ["no-microphone"] = "No microphone access",
  ["no-input"] = "No microphone to listen to",
}

function dictation.notice(problem, locale)
  if problem == "language" then return "This Mac can't take dictation in " .. tostring(locale) end
  return NOTICES[problem] or ("Dictation stopped: " .. tostring(problem))
end

-- The steps that put text where you were typing: on the clipboard, marked transient so the
-- clipboard history skips it; Cmd+V; a wait, so the app reads it first; then saved back, or
-- the clipboard emptied when it was empty. Into a password field, or with no window to
-- type in, it's only copied, kept in the history, and a notice says so.
function dictation.pasteSteps(text, saved, secure, hasWindow)
  if secure or not hasWindow then
    return {
      { kind = "write", text = text, transient = false },
      { kind = "notice", text = secure and "Not typed into a password field · on the clipboard" or "On the clipboard · ⌘V to paste" },
    }
  end
  local back = next(saved or {}) and { kind = "restore", saved = saved } or { kind = "clear" }
  return { { kind = "write", text = text, transient = true }, { kind = "paste" }, { kind = "wait", seconds = dictation.RESTORE_SECONDS }, back }
end

-- The pasteboard data for a write step.
function dictation.pasteboardData(step)
  local data = { [TEXT] = step.text }
  if step.transient then data[TRANSIENT] = "" end
  return data
end

-- The last dictations, newest first, with entry { text, app, at } added unless it's empty.
function dictation.remember(list, entry)
  local kept = {}
  local text = trim(entry and entry.text)
  if text ~= "" then kept[1] = { text = text, app = entry.app, at = entry.at } end
  for _, old in ipairs(list or {}) do
    if #kept >= KEEP then break end
    kept[#kept + 1] = old
  end
  return kept
end

local function ago(seconds)
  if seconds < 60 then return "now" end
  if seconds < 3600 then return math.floor(seconds / 60) .. " min" end
  return math.floor(seconds / 3600) .. " h"
end

-- The Dictations card's rows: each dictation, its app and how long ago, newest first.
function dictation.historyRows(entries, now)
  local rows = {}
  for index, entry in ipairs(entries or {}) do
    rows[#rows + 1] = { id = "dictation:" .. index, icon = "󰍬", label = entry.text,
      hint = (entry.app and entry.app ~= "" and (entry.app .. " · ") or "") .. ago(now - (entry.at or now)) }
  end
  return rows
end

-- A key's value in ~/.config/omv/dictation's "key = value" lines, or nil.
local function valueOf(text, key)
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local value = line:gsub("#.*$", ""):match("^%s*" .. key .. "%s*=%s*(%S+)%s*$")
    if value then return value end
  end
  return nil
end

-- A key's whole value, spaces and commas included, without a comment; nil without the line.
local function lineOf(text, key)
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local value = line:gsub("#.*$", ""):match("^%s*" .. key .. "%s*=%s*(.-)%s*$")
    if value then return value end
  end
  return nil
end

-- Your words, from words = omv, AeroSpace, …: names and terms dictation should hear right.
function dictation.words(text)
  local list = {}
  for word in (lineOf(text, "words") or ""):gmatch("[^,]+") do
    word = trim(word)
    if word ~= "" then list[#list + 1] = word end
  end
  return list
end

-- Whether filler sounds are dropped: on unless the file says cleanup = off.
function dictation.cleanupOn(text)
  return valueOf(text, "cleanup") ~= "off"
end

-- Sounds only, never words, so dropping them never changes what was meant.
local FILLERS = { um = true, umm = true, uh = true, uhh = true, uhm = true, erm = true, hmm = true, mm = true,
  ["ıı"] = true, ["ııı"] = true, ee = true, eee = true, ["ıhm"] = true }

-- text without filler sounds, and how many were dropped; a capital moves to the new first word.
function dictation.clean(text)
  local kept, dropped = {}, 0
  for word in tostring(text or ""):gmatch("%S+") do
    local core = word:gsub("^[%p]+", ""):gsub("[%p]+$", ""):lower()
    if FILLERS[core] then dropped = dropped + 1 else kept[#kept + 1] = word end
  end
  local cleaned = table.concat(kept, " ")
  if dropped > 0 and tostring(text):match("^%s*%u") then cleaned = cleaned:gsub("^%l", string.upper) end
  return cleaned, dropped
end

-- The language to hear: the file's language line, else macOS's first language, else en-US.
function dictation.language(text, appleLanguages)
  return valueOf(text, "language") or (appleLanguages or {})[1] or "en-US"
end

-- Whether the start and end sounds play: on unless the file says sounds = off.
function dictation.sounds(text)
  return valueOf(text, "sounds") ~= "off"
end

-- text with key's line set to value, added at the end when it has none, or removed for nil;
-- the other lines and comments stay.
function dictation.setting(text, key, value)
  local lines, found = {}, false
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line:gsub("#.*$", ""):match("^%s*" .. key .. "%s*=") then
      found = true
      if value then lines[#lines + 1] = key .. " = " .. value end
    else
      lines[#lines + 1] = line
    end
  end
  if lines[#lines] == "" then table.remove(lines) end
  if value and not found then lines[#lines + 1] = key .. " = " .. value end
  if #lines == 0 then return "" end
  return table.concat(lines, "\n") .. "\n"
end

-- What the helper's locales mode says: the languages each engine hears, the models on the
-- Mac, the microphone access, and each language's name in macOS's language, from lines
-- "transcriber<tab>en-US en-GB…", "dictation<tab>…", "installed<tab>…",
-- "microphone<tab>granted" and "name<tab>tr-TR<tab>Turkish (Türkiye)".
function dictation.parseLocales(output)
  local lists = { transcriber = {}, dictation = {}, installed = {}, names = {} }
  for line in tostring(output or ""):gmatch("[^\n]+") do
    local kind, value = line:match("^(%a+)\t(.*)$")
    if kind == "name" then
      local id, name = value:match("^(%S+)\t(.+)$")
      if id then lists.names[id] = name end
    elseif kind == "microphone" then
      lists.microphone = value
    elseif kind and lists[kind] then
      for locale in value:gmatch("%S+") do lists[kind][#lists[kind] + 1] = locale end
    end
  end
  return lists
end

function dictation.languageName(lists, id)
  return lists.names[id] or id
end

local function hasLanguage(list, language)
  for _, locale in ipairs(list) do
    if locale:match("^(%a+)") == language then return true end
  end
  return false
end

-- Whether locale's language has its model on the Mac.
function dictation.isInstalled(lists, locale)
  return hasLanguage(lists.installed or {}, tostring(locale):match("^(%a+)"))
end

-- The meter: a level in dB as 0 to 1, -55 dB (a quiet room) to -15 dB (speaking up), so
-- quiet speech still moves it.
local FLOOR_DB, CEILING_DB = -55, -15
local ATTACK, RELEASE, BARS = 0.6, 0.08, 24

function dictation.levelOf(db)
  return math.max(0, math.min(1, (db - FLOOR_DB) / (CEILING_DB - FLOOR_DB)))
end

-- The shown level moved towards target: at once going up, slowly coming down, so it doesn't flicker.
function dictation.smooth(shown, target)
  local rate = target > shown and ATTACK or RELEASE
  return shown + (target - shown) * rate
end

-- The waveform's levels with level added at the right, the oldest dropped past 24 bars.
function dictation.pushLevel(history, level)
  local kept = {}
  for index = math.max(1, #history - BARS + 2), #history do kept[#kept + 1] = history[index] end
  kept[#kept + 1] = level
  return kept
end

-- The words as lines of at most width characters, broken between words, or inside a word
-- longer than a line.
function dictation.wrap(text, width)
  local lines, line = {}, ""
  local function length(value) return select(2, value:gsub("[^\128-\191]", "")) end
  for word in tostring(text or ""):gmatch("%S+") do
    while length(word) > width do
      if line ~= "" then lines[#lines + 1], line = line, "" end
      local cut = 0
      for position in word:gmatch("()[^\128-\191]") do
        if length(word:sub(1, position - 1)) == width then cut = position - 1; break end
      end
      lines[#lines + 1], word = word:sub(1, cut), word:sub(cut + 1)
    end
    if line == "" then line = word
    elseif length(line) + 1 + length(word) <= width then line = line .. " " .. word
    else lines[#lines + 1], line = line, word end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

function dictation.lastLines(lines, count)
  local kept = {}
  for index = math.max(1, #lines - count + 1), #lines do kept[#kept + 1] = lines[index] end
  return kept
end

-- The pill's height for count lines of words, 1 to 4.
dictation.MAX_LINES, dictation.LINE_HEIGHT = 4, 21

function dictation.pillHeight(count)
  return 75 + dictation.LINE_HEIGHT * math.max(1, math.min(dictation.MAX_LINES, count))
end

-- The Dictation card's rows, from info { ownLanguage, language (its name), words, cleanup,
-- sounds, kept (dictations kept), microphone (granted, denied or undetermined), installed }.
local MICROPHONE = { granted = "allowed", denied = "not allowed  ›", undetermined = "asked on the first hold" }

local function wordsHint(words)
  if not words or #words == 0 then return "none  ›" end
  local shown = {}
  for index = 1, math.min(3, #words) do shown[index] = words[index] end
  local more = #words > 3 and (" +" .. (#words - 3)) or ""
  return table.concat(shown, ", ") .. more .. "  ›"
end

local function onOff(value)
  return "‹  " .. (value == false and "off" or "on") .. "  ›"
end

function dictation.cardRows(info)
  local kept = info.kept or 0
  return {
    { id = "language", group = "Dictation", icon = "󰗊", label = "Language", hint = (info.ownLanguage and "" or "macOS's: ") .. info.language .. "  ›" },
    { id = "words", group = "Dictation", icon = "󰓹", label = "Your words", hint = wordsHint(info.words) },
    { id = "cleanup", group = "Dictation", icon = "󰃢", label = "Drop ums and uhs", hint = onOff(info.cleanup) },
    { id = "sounds", group = "Dictation", icon = "󰕾", label = "Sounds", hint = onOff(info.sounds) },
    { id = "key", group = "Dictation", icon = "󰌌", label = "Key", hint = "hold Right Option, or tap it twice" },
    { id = "dictations", group = "Dictation", icon = "󰆒", label = "Dictations", hint = kept > 0 and ("the last " .. kept .. "  ›") or "none yet" },
    { id = "permissions", group = "Needs", icon = "󰍬", label = "Microphone", hint = MICROPHONE[info.microphone] or MICROPHONE.undetermined },
    { id = "install", group = "Needs", icon = "󰇚", label = info.language .. " model", hint = info.installed and "on this Mac" or "get it  ›" },
  }
end

-- Which of macOS's engines hears locale: dictation, whose words stream in as they're said
-- and which takes your words, when it knows the language; the transcriber otherwise; nil for
-- neither.
function dictation.engine(locale, lists)
  local language = tostring(locale):match("^(%a+)")
  if hasLanguage(lists.dictation, language) then return "dictation" end
  if hasLanguage(lists.transcriber, language) then return "transcriber" end
  return nil
end

return dictation
