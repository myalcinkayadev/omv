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
local RIGHT_OPTION, RIGHT_COMMAND = 61, 54
local TRANSIENT, TEXT = "org.nspasteboard.TransientType", "public.utf8-plain-text"

local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A flagsChanged event's key as an event name: Right Option going down or up, up with Shift
-- held, Right Command going down or up, or Shift going down on either side; else nil.
local SHIFTS = { [56] = true, [60] = true }

function dictation.eventFor(keyCode, optionDown, shiftDown, commandDown)
  if SHIFTS[keyCode] then return shiftDown and "shift" or nil end
  if keyCode == RIGHT_COMMAND then return commandDown and "command-down" or "command-up" end
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
-- shift (a Shift tap), voice (speech heard), tab (Tab, when there's a language to move to),
-- other (any other key), escape or tick, at time in seconds. Gives the action, record, show,
-- lock, finish, review, timeout (a locked one ending by itself), switch (to the next language)
-- or cancel, or nil; and whether the event is swallowed, which only Esc and Tab are, and only
-- while the pill listens.
local PHASES = {}

-- options, for Right Command: late, the recording starts only once the key has been held
-- alone, as the action start, so a shortcut never opens the mic; lock = false, no hands-free.
function PHASES.idle(state, event, time, options)
  if event ~= "option-down" then return nil, false end
  moveTo(state, "pressed", { since = time })
  if options.late then return nil, false end
  return "record", false
end

function PHASES.pressed(state, event, time, options)
  local held = time - state.since
  if event == "tick" and held >= dictation.HOLD_SECONDS then
    moveTo(state, "listening")
    return options.late and "start" or "show", false
  end
  -- Nothing was recorded yet: a short press or another key ends it quietly.
  if options.late and event ~= "tick" and event ~= "voice" and event ~= "shift" and held < dictation.HOLD_SECONDS then
    moveTo(state, "idle")
    return nil, false
  end
  if (event == "option-up" or event == "option-up-shift") and held >= dictation.HOLD_SECONDS then
    moveTo(state, "idle")
    return event == "option-up" and "finish" or "review", false
  end
  if (event == "option-up" or event == "option-up-shift") and options.lock == false then
    moveTo(state, "idle")
    return "cancel", false
  end
  if event == "option-up" or event == "option-up-shift" then
    moveTo(state, "tapped", { at = time })
    return nil, false
  end
  if event == "other" or event == "escape" or event == "tab" then
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
  if (event == "tick" and since > dictation.DOUBLE_SECONDS) or event == "other" or event == "escape" or event == "tab" then
    moveTo(state, "idle")
    return "cancel", false
  end
  return nil, false
end

function PHASES.listening(state, event)
  if event == "tab" then return "switch", true end
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

-- Hands-free: Enter types and Shift+Enter copies; Space pauses, and the time paused isn't
-- counted toward the silence and length limits.
dictation.PAUSE_SECONDS = 300

function PHASES.locked(state, event, time)
  if event == "option-up" and state.ignoreUp then
    state.ignoreUp = false
    return nil, false
  end
  if event == "option-down" then
    moveTo(state, "finishing")
    return "finish", false
  end
  if event == "enter" or event == "enter-shift" then
    moveTo(state, "idle")
    return event == "enter" and "finish" or "review", true
  end
  if event == "space" then
    state.phase, state.pausedAt = "paused", time
    return "pause", true
  end
  if event == "tab" then return "switch", true end
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
    return "timeout", false
  end
  return nil, false
end

function PHASES.paused(state, event, time)
  if event == "space" then
    local paused = time - state.pausedAt
    state.phase, state.pausedAt = "locked", nil
    state.since = state.since + paused
    if state.heard then state.heard = state.heard + paused end
    return "resume", true
  end
  if event == "enter" or event == "enter-shift" then
    moveTo(state, "idle")
    return event == "enter" and "finish" or "review", true
  end
  if event == "escape" then
    moveTo(state, "idle")
    return "cancel", true
  end
  if event == "option-down" then
    moveTo(state, "finishing")
    return "finish", false
  end
  if event == "tick" and time - state.pausedAt >= dictation.PAUSE_SECONDS then
    moveTo(state, "idle")
    return "review", false
  end
  return nil, false
end

-- After the tap that finished a locked one: its release.
function PHASES.finishing(state, event)
  if event == "option-up" then moveTo(state, "idle") end
  return nil, false
end

-- Right Command's events run through the same phases as Right Option's.
local AS_OPTION = { ["command-down"] = "option-down", ["command-up"] = "option-up" }

function dictation.press(state, event, time, options)
  return PHASES[state.phase](state, AS_OPTION[event] or event, time, options or {})
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

-- An app's name as the pill's chip shows it: cut at 18 characters, so the meter keeps room.
local NAME_CHARACTERS = 18

local function shortName(name)
  name = tostring(name or "")
  local starts = {}
  for position in name:gmatch("()[^\128-\191]") do starts[#starts + 1] = position end
  if #starts <= NAME_CHARACTERS then return name end
  return name:sub(1, starts[NAME_CHARACTERS] - 1) .. "…"
end

-- Which key a keyDown is, for press: hands-free (locked or paused), Enter, Shift+Enter and
-- Space are its keys; Tab only when there's a language to move to, while the pill listens; Esc
-- always; any other key, other, which cancels while held as it always did.
local ESCAPE_KEY, TAB_KEY, RETURN_KEY, SPACE_KEY = 53, 48, 36, 49

function dictation.keyName(code, shiftDown, phase, hasNextLanguage)
  if code == ESCAPE_KEY then return "escape" end
  local handsFree = phase == "locked" or phase == "paused"
  if handsFree and code == RETURN_KEY then return shiftDown and "enter-shift" or "enter" end
  if handsFree and code == SPACE_KEY then return "space" end
  if code == TAB_KEY and hasNextLanguage and (phase == "listening" or phase == "locked") then return "tab" end
  return "other"
end

-- The pill's hint line: hands-free keys, the paused ones, or holding's; a password field's
-- warning instead of either.
function dictation.hint(recording)
  if recording.secure then return "won't be typed here: it goes to the clipboard" end
  if recording.paused then return "␣ resume · ↩ type · ⇧↩ copy · esc cancels" end
  if recording.locked then
    return "↩ type · ␣ pause · ⇧↩ copy" .. (recording.nextName and (" · ⇥ " .. recording.nextName) or "") .. " · esc cancels"
  end
  return "release types it · Shift+release copies · Esc cancels" .. (recording.nextName and (" · Tab: " .. recording.nextName) or "")
end

-- The pill's header, from recording { started, stopped, locked, finishing, left, secure, app }:
-- { icon = mic, lock or spinner; live, whether the mic is on; status; timer; warning, whether
-- the timer is an orange countdown; target = { kind = app or password, name } }.
-- Until the helper says ready, the mic isn't open yet: the status says Starting and the live
-- dot waits, so nothing said before it is expected to be heard. With languages set, language
-- is the code of the one heard now, such as EN. For an agent (Right Command) the status says
-- Command and the chip names the session the words go to.
function dictation.header(recording, now)
  local icon, status = "mic", "Listening"
  if recording.agent then icon, status = "agent", "Command" end
  if recording.finishing then icon, status = "spinner", "Finishing"
  elseif recording.paused then icon, status = "pause", "Paused"
  elseif not recording.ready then status = "Starting"
  elseif recording.locked then icon, status = "lock", "Locked" end
  local live = not recording.finishing and not recording.paused and recording.ready == true
  local warning = recording.left ~= nil and not recording.finishing
  local timer = warning and clock(recording.left) or clock((recording.stopped or recording.pausedAt or now) - recording.started)
  local target = recording.secure and { kind = "password", name = "password field" } or { kind = "app", name = shortName(recording.app) }
  -- For an agent, the chip names the session the words go to, whatever app is in front.
  if recording.agent then
    local chip = recording.agentTarget and recording.agentTarget.chip
    target = { kind = "agent", name = chip and shortName(chip) or "—" }
  end
  local language = recording.languages and tostring(recording.locale or ""):match("^(%a+)")
  return { icon = icon, live = live, status = status, timer = timer, warning = warning, target = target,
    language = language and language:upper() or nil }
end

-- Whether the start sound plays now: once, when the pill shows and the mic is open, whichever
-- comes last.
function dictation.chimeDue(recording)
  return recording.shown == true and recording.ready == true and not recording.chimed
end

-- What the pill shows, as one string: it's redrawn only when this changes, about once a
-- second for its timer, since each redraw costs Hammerspoon about 9 ms of CPU; the wave moves
-- in dictate.swift's window, not here.
function dictation.frameKey(recording, now)
  local header = dictation.header(recording, now)
  return table.concat({ header.icon, header.status, header.timer, tostring(header.warning), header.target.kind, header.target.name,
    tostring(recording.locked), tostring(recording.paused), tostring(recording.finishing), tostring(recording.ready), tostring(recording.percent),
    tostring(recording.problem), tostring(header.language), recording.partial or "" }, "\0")
end

-- What the helper ending does to recording, the one now: finish with the words heard so far
-- when it ends while finishing without its final line, since the pill would otherwise wait on
-- it forever; hide the pill when it ends while listening; nothing when a problem is shown,
-- which hides itself.
function dictation.onHelperExit(recording)
  if recording.problem then return nil end
  return recording.finishing and "finish" or "hide"
end

-- Whether finishing has taken too long: past FINISH_SECONDS, what was heard is used as it is.
dictation.FINISH_SECONDS = 15

function dictation.finishOverdue(recording, now)
  return recording.finishing == true and recording.stopped ~= nil and now - recording.stopped > dictation.FINISH_SECONDS
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

-- The steps for how, type or copy: typed, the text goes on the clipboard, marked transient
-- so the clipboard history skips it; Cmd+V; a wait, so the app reads it first; then saved
-- back, or the clipboard emptied when it was empty. Copied, it's only written, and kept in
-- the history.
function dictation.pasteSteps(text, saved, how)
  if how == "copy" then return { { kind = "write", text = text, transient = false } } end
  local back = next(saved or {}) and { kind = "restore", saved = saved } or { kind = "clear" }
  return { { kind = "write", text = text, transient = true }, { kind = "paste" }, { kind = "wait", seconds = dictation.RESTORE_SECONDS }, back }
end

local function counted(count, one)
  return count .. " " .. one .. (count == 1 and "" or "s")
end

-- Whether finished words are typed or only copied, and what the pill says, from info
-- { review, secure, hasWindow, auto (a locked one ended by itself), startApp, app }: copied
-- for a review, a password field or no window, and when a locked one ends by itself after
-- you moved to another app; typed into the focused app otherwise.
function dictation.delivery(info, text, dropped)
  local words = select(2, tostring(text or ""):gsub("%S+", ""))
  if info.review then return { kind = "copy", message = "Copied " .. counted(words, "word"), hint = "⌘V pastes" } end
  if info.secure then return { kind = "copy", message = "Not typed into a password field · on the clipboard" } end
  if not info.hasWindow then return { kind = "copy", message = "On the clipboard · ⌘V to paste" } end
  if info.auto and info.startApp and info.app ~= info.startApp then
    return { kind = "copy", message = info.startApp .. " lost focus · on the clipboard" }
  end
  local said = "Typed " .. counted(words, "word") .. ((dropped or 0) > 0 and (" · " .. counted(dropped, "um") .. " dropped") or "")
  return { kind = "type", message = said, hint = "⌘Z undoes" }
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

-- The app a finished dictation is kept with, from info as dictation.delivery takes it and app,
-- the one you're in: a locked one that ended by itself after you moved on is kept with the
-- app it started in, the one it was meant for; any other with the app you're in.
function dictation.historyApp(info, app)
  if info.auto and info.startApp and info.startApp ~= app then return info.startApp end
  return app
end

-- The history file, ~/.local/state/omv/dictations: a line a dictation, newest first,
-- "at<tab>app<tab>text", with tabs, line breaks and backslashes in the text escaped.
dictation.HISTORY_PATH = (os.getenv("HOME") or "") .. "/.local/state/omv/dictations"
local ESCAPES = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n" }
local UNESCAPES = { ["\\"] = "\\", t = "\t", n = "\n" }

function dictation.historyText(list)
  local lines = {}
  for _, entry in ipairs(list or {}) do
    local text = tostring(entry.text or ""):gsub("[\\\t\n]", ESCAPES)
    local app = tostring(entry.app or ""):gsub("[\t\n]", " ")
    lines[#lines + 1] = string.format("%d\t%s\t%s", math.floor(entry.at or 0), app, text)
  end
  return #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
end

-- The kept dictations in the file's text, the last KEEP, skipping lines it can't read.
function dictation.parseHistory(text)
  local list = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local at, app, saved = line:match("^(%d+)\t([^\t]*)\t(.*)$")
    if at and #list < KEEP then
      list[#list + 1] = { at = tonumber(at), app = app, text = (saved:gsub("\\(.)", function(c) return UNESCAPES[c] or c end)) }
    end
  end
  return list
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
-- A key as a pattern that matches it literally, so talk-back voice's hyphen is a hyphen.
local function keyPattern(key)
  return (key:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function lineOf(text, key)
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local value = line:gsub("#.*$", ""):match("^%s*" .. keyPattern(key) .. "%s*=%s*(.-)%s*$")
    if value then return value end
  end
  return nil
end

-- Every value of key, one per line, in the order written.
local function linesOf(text, key)
  local values = {}
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local value = line:gsub("#.*$", ""):match("^%s*" .. keyPattern(key) .. "%s*=%s*(.-)%s*$")
    if value then values[#values + 1] = value end
  end
  return values
end

-- Spoken replacements, from replace = slash voice > /voice lines, one rule a line: { from, to },
-- longest phrase first, so it wins over a shorter one inside it. \n in to is a line break.
function dictation.replacements(text)
  local rules = {}
  for _, value in ipairs(linesOf(text, "replace")) do
    local from, to = value:match("^(.-)%s+>%s+(.*)$")
    from = trim(from)
    if from and from ~= "" then rules[#rules + 1] = { from = from, to = (to:gsub("\\n", "\n")) } end
  end
  table.sort(rules, function(a, b) return #a.from > #b.from end)
  return rules
end

-- Letters, digits and any byte of a multibyte character, so ç and ğ count as letters.
local WORD = "%w\128-\255"

local function lowerAscii(text)
  return (text:gsub("%u", string.lower))
end

-- text with each rule's phrase, as whole words and in any case of its ASCII letters, replaced.
function dictation.replace(text, rules)
  text = tostring(text or "")
  for _, rule in ipairs(rules or {}) do
    local phrase = lowerAscii(rule.from):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    local open = rule.from:match("^[" .. WORD .. "]") and "%f[" .. WORD .. "]" or ""
    local close = rule.from:match("[" .. WORD .. "]$") and "%f[^" .. WORD .. "]" or ""
    local pattern, out, from = open .. phrase .. close, {}, 1
    local lowered = lowerAscii(text)
    while true do
      local first, last = lowered:find(pattern, from)
      if not first then break end
      out[#out + 1] = text:sub(from, first - 1) .. rule.to
      from = last + 1
    end
    out[#out + 1] = text:sub(from)
    text = table.concat(out)
  end
  return text
end

-- The languages Tab moves between, from languages = tr-TR, en-US.
function dictation.languages(text)
  local list = {}
  for locale in (lineOf(text, "languages") or ""):gmatch("[^,]+") do
    locale = trim(locale)
    if locale ~= "" then list[#list + 1] = locale end
  end
  return list
end

-- The language after current in list, wrapping round; the first other one when current isn't
-- in it; nil with fewer than two.
function dictation.nextLanguage(list, current)
  if #list < 2 then return nil end
  for index, locale in ipairs(list) do
    if locale == current then return list[index % #list + 1] end
  end
  for _, locale in ipairs(list) do
    if locale ~= current then return locale end
  end
  return nil
end

-- The words before a switch and after it, as one text.
function dictation.join(before, after)
  before, after = trim(before), trim(after)
  if before == "" then return after end
  if after == "" then return before end
  return before .. " " .. after
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
    if line:gsub("#.*$", ""):match("^%s*" .. keyPattern(key) .. "%s*=") then
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

-- A language's name without its region: English (United States) is English.
function dictation.plainLanguage(name)
  return (tostring(name or ""):gsub("%s*%b()", ""))
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
-- A level this loud or louder is speech, which keeps a locked one going.
local VOICE = 0.3

function dictation.isVoice(level)
  return level >= VOICE
end

function dictation.levelOf(db)
  return math.max(0, math.min(1, (db - FLOOR_DB) / (CEILING_DB - FLOOR_DB)))
end

-- The meter fills the header from after the timer to 10 pt before the app chip: { x, w } for
-- a chip chipWidth wide.
dictation.PILL_WIDTH = 560
local METER_X, EDGE, GAP = 190, 18, 10

function dictation.meterLayout(chipWidth)
  return { x = METER_X, w = math.max(0, dictation.PILL_WIDTH - EDGE - chipWidth - GAP - METER_X) }
end

-- The line that tells dictate.swift, which draws the wave on the GPU in a window of its own,
-- where the strip { x, y, w } is on screen and what the pill shows: listening, locked or
-- finishing, the seconds left of a countdown or -1, colors { fg, accent, warning } as hex,
-- and still, 1 with Reduce Motion.
function dictation.waveCommand(strip, recording, colors, still)
  local state = recording.finishing and "finishing" or (recording.locked and "locked" or "listening")
  local left = (not recording.finishing and recording.left) or -1
  local function hex(value) return (tostring(value or "ffffff"):gsub("^#", "")) end
  return string.format("wave %d %d %d %s %d %s %s %s %d", math.floor(strip.x + 0.5), math.floor(strip.y + 0.5),
    math.floor(strip.w + 0.5), state, left, hex(colors.fg), hex(colors.accent), hex(colors.warning), still and 1 or 0)
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
  return 83 + dictation.LINE_HEIGHT * math.max(1, math.min(dictation.MAX_LINES, count))
end

-- An agent's pill: the same, with a row a session listed by number above the words.
dictation.AGENT_ROW_HEIGHT = 22

function dictation.agentPillHeight(count, rows)
  return dictation.pillHeight(count) + dictation.AGENT_ROW_HEIGHT * rows
end

-- The Dictation card's rows, from info { language (the start language's name), tabLanguage (the
-- name of the one Tab moves to, or nil), languageMissing (either's model isn't on the Mac),
-- words, replacements, cleanup, sounds, kept (dictations kept), microphone (granted, denied or
-- undetermined), and, with talk-back on, talkBackVoice, talkBackMissing and talkBackOutput }.
local MICROPHONE = { granted = "allowed", denied = "not allowed  ›", undetermined = "asked on the first hold" }

local function wordsHint(words)
  if not words or #words == 0 then return "none  ›" end
  local shown = {}
  for index = 1, math.min(3, #words) do shown[index] = words[index] end
  local more = #words > 3 and (" +" .. (#words - 3)) or ""
  return table.concat(shown, ", ") .. more .. "  ›"
end

-- The first replacement, and how many more.
local function rulesHint(rules)
  if not rules or #rules == 0 then return "none  ›" end
  local more = #rules > 1 and (" +" .. (#rules - 1)) or ""
  return rules[1].from .. " → " .. rules[1].to:gsub("\n", "⏎") .. more .. "  ›"
end

local function onOff(value)
  return "‹  " .. (value == false and "off" or "on") .. "  ›"
end

-- Where the card's rows that step or reopen on themselves are.
dictation.CARD_ROWS = { languages = 1, cleanup = 4, sounds = 5, talkBackVoice = 7, talkBackOutput = 8 }

local function languagesHint(info)
  local names = info.language .. (info.tabLanguage and (", " .. info.tabLanguage .. " (Tab)") or "")
  return (info.languageMissing and "get it · " or "") .. names .. "  ›"
end

function dictation.cardRows(info)
  local kept = info.kept or 0
  local rows = {
    { id = "languages", group = "Hearing", icon = "󰗊", label = "Languages", hint = languagesHint(info) },
    { id = "words", group = "Hearing", icon = "󰓹", label = "Your words", hint = wordsHint(info.words) },
    { id = "replacements", group = "Hearing", icon = "󰛔", label = "Replacements", hint = rulesHint(info.replacements) },
    { id = "cleanup", group = "Hearing", icon = "󰃢", label = "Drop ums and uhs", hint = onOff(info.cleanup) },
    { id = "sounds", group = "Feedback", icon = "󰕾", label = "Sounds", hint = onOff(info.sounds) },
    { id = "dictations", group = "Feedback", icon = "󰆒", label = "Dictations", hint = kept > 0 and ("the last " .. kept .. "  ›") or "none yet" },
  }
  if info.talkBackVoice then
    rows[#rows + 1] = { id = "talkBackVoice", group = "Talk-back", icon = "󰗋", label = "Voice",
      hint = (info.talkBackMissing and "get it · " or "") .. "‹  " .. info.talkBackVoice .. "  ›" }
    rows[#rows + 1] = { id = "talkBackOutput", group = "Talk-back", icon = "󰋋", label = "Speaks",
      hint = "‹  " .. (info.talkBackOutput == "anywhere" and "anywhere" or "in headphones") .. "  ›" }
  end
  rows[#rows + 1] = { id = "permissions", group = "Needs", icon = "󰍬", label = "Microphone", hint = MICROPHONE[info.microphone] or MICROPHONE.undetermined }
  return rows
end

-- The Languages screen's rows, from info { startName, ownStart (the file picks it, rather than
-- macOS), startInstalled, tabName (or nil), tabInstalled }: the language dictation starts in,
-- and the one Tab moves to, each with whether its model is on the Mac.
local function modelHint(installed)
  return installed and "on this Mac" or "get it"
end

function dictation.languageRows(info)
  local start = (info.ownStart and "" or "macOS's: ") .. info.startName .. " · " .. modelHint(info.startInstalled) .. "  ›"
  local tab = info.tabName and (info.tabName .. " · " .. modelHint(info.tabInstalled) .. "  ›") or "none  ›"
  return {
    { id = "start", icon = "󰗊", label = "Starts in", hint = start },
    { id = "tab", icon = "󰌌", label = "Tab switches to", hint = tab },
  }
end

-- The language Tab moves to from start: the first in the languages line that isn't start.
function dictation.tabLanguage(text, start)
  for _, locale in ipairs(dictation.languages(text)) do
    if locale ~= start then return locale end
  end
  return nil
end

-- text with start as the language dictation starts in and tab as the one Tab moves to: the
-- languages line is written for a different tab, and removed for none or the same one.
function dictation.withLanguages(text, start, tab)
  text = dictation.setting(text, "language", start)
  if not tab or tab == start then return dictation.setting(text, "languages", nil) end
  return dictation.setting(text, "languages", start .. ", " .. tab)
end

-- Which of macOS's engines hears locale: the transcriber when it knows the language, since
-- it hears quiet speech from the start, keeps the last word and punctuates a long dictation
-- throughout, where dictation lost the start of quiet speech and the last word; dictation, which
-- also takes your words, for the languages only it knows, Turkish among them; nil for neither.
function dictation.engine(locale, lists)
  local language = tostring(locale):match("^(%a+)")
  if hasLanguage(lists.transcriber, language) then return "transcriber" end
  if hasLanguage(lists.dictation, language) then return "dictation" end
  return nil
end

return dictation
