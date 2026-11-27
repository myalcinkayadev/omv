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
-- in seconds. Gives the action, record, show, lock, finish, review, timeout (a locked one
-- ending by itself) or cancel, or nil; and
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
    return "timeout", false
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

-- An app's name as the pill's chip shows it: cut at 18 characters, so the meter keeps room.
local NAME_CHARACTERS = 18

local function shortName(name)
  name = tostring(name or "")
  local starts = {}
  for position in name:gmatch("()[^\128-\191]") do starts[#starts + 1] = position end
  if #starts <= NAME_CHARACTERS then return name end
  return name:sub(1, starts[NAME_CHARACTERS] - 1) .. "…"
end

-- The pill's header, from recording { started, stopped, locked, finishing, left, secure, app }:
-- { icon = mic, lock or spinner; live, whether the mic is on; status; timer; warning, whether
-- the timer is an orange countdown; target = { kind = app or password, name } }.
function dictation.header(recording, now)
  local icon, status = "mic", "Listening"
  if recording.finishing then icon, status = "spinner", "Finishing"
  elseif recording.locked then icon, status = "lock", "Locked" end
  local warning = recording.left ~= nil and not recording.finishing
  local timer = warning and clock(recording.left) or clock((recording.stopped or now) - recording.started)
  local target = recording.secure and { kind = "password", name = "password field" } or { kind = "app", name = shortName(recording.app) }
  return { icon = icon, live = not recording.finishing, status = status, timer = timer, warning = warning, target = target }
end

-- What the pill shows besides its wave and live dot, as one string: the pill is rebuilt only
-- when it changes, and between, only the wave and the dot move, which costs a third as much.
function dictation.frameKey(recording, now)
  local header = dictation.header(recording, now)
  return table.concat({ header.icon, header.status, header.timer, tostring(header.warning), header.target.kind, header.target.name,
    tostring(recording.locked), tostring(recording.finishing), tostring(recording.ready), tostring(recording.percent),
    tostring(recording.problem), recording.partial or "" }, "\0")
end

-- One line from the helper, "kind<tab>value": { kind, text | percent | level | problem },
-- or nil for a line it doesn't know.
function dictation.parse(line)
  local kind, value = tostring(line or ""):match("^(%a+)\t(.*)$")
  if kind == "partial" or kind == "final" then return { kind = kind, text = value } end
  if kind == "progress" then return { kind = kind, percent = tonumber(value) } end
  if kind == "level" then return { kind = kind, level = tonumber(value) } end
  if kind == "bands" then
    local low, mid, high = value:match("^(%S+) (%S+) (%S+)$")
    return { kind = kind, bands = { low = tonumber(low), mid = tonumber(mid), high = tonumber(high) } }
  end
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
local ATTACK, RELEASE = 0.6, 0.25
-- A level this loud or louder is speech, which keeps a locked one going.
local VOICE = 0.3

function dictation.isVoice(level)
  return level >= VOICE
end

function dictation.levelOf(db)
  return math.max(0, math.min(1, (db - FLOOR_DB) / (CEILING_DB - FLOOR_DB)))
end

-- The shown level moved towards target: at once going up, slowly coming down, so it doesn't flicker.
function dictation.smooth(shown, target)
  local rate = target > shown and ATTACK or RELEASE
  return shown + (target - shown) * rate
end

-- The meter fills the header from after the timer to 10 pt before the app chip: { x, w } for
-- a chip chipWidth wide.
dictation.PILL_WIDTH = 560
local METER_X, EDGE, GAP = 190, 18, 10

function dictation.meterLayout(chipWidth)
  return { x = METER_X, w = math.max(0, dictation.PILL_WIDTH - EDGE - chipWidth - GAP - METER_X) }
end

-- The meter is three sine curves layered, as Siri's is, each following one band of your voice:
-- the bright one the vowels (mid), the next the hum under them (low), the faint one hiss like
-- s, sh and t (high). A band sets its curve's height and how fast it travels; silence leaves
-- a ripple so the mic still looks alive. Each curve: its band, cycles across the strip, its
-- speed, brightness and stroke.
local CURVES = { { band = "mid", cycles = 1.6, speed = 1, alpha = 1, stroke = 2 }, { band = "low", cycles = 2.3, speed = -1.4, alpha = 0.5, stroke = 1.5 },
  { band = "high", cycles = 3.2, speed = 1.9, alpha = 0.25, stroke = 1.2 } }
local RIPPLE, RISE, FINISHING_HEIGHT, CENTER_Y, STEP = 1.5, 9.5, 2.5, 25, 4
-- How far the hump moves from the middle, as a part of the strip, for pure hum or pure hiss.
local SWAY = 0.3

-- A curve's height in points for recording { bands, finishing, left } and its band: low while
-- finishing, a ripple during the countdown, else the ripple plus the band.
function dictation.waveAmplitude(recording, band)
  if recording.finishing then return FINISHING_HEIGHT end
  if recording.left then return RIPPLE end
  return RIPPLE + RISE * ((recording.bands or {})[band] or 0)
end

-- The curves' phases after seconds at bands: each faster as its band is louder; still with
-- Reduce Motion.
function dictation.wavePhase(phases, bands, seconds, still)
  local moved = {}
  for index, curve in ipairs(CURVES) do
    local phase = phases and phases[index] or 0
    moved[index] = still and phase or (phase + seconds * (1.5 + 6 * ((bands or {})[curve.band] or 0)))
  end
  return moved
end

-- Where the hump sits, as a part of the strip: right of the middle for hiss, left for hum.
local function humpAt(bands)
  local low, mid, high = bands.low or 0, bands.mid or 0, bands.high or 0
  local total = low + mid + high
  if total <= 0 then return 0.5 end
  return 0.5 + SWAY * (high - low) / total
end

-- How much of its height a curve has at x: 0 at both ends, 1 at its hump.
function dictation.taperAt(curve, x)
  if curve.width <= 0 then return 0 end
  local part = (x - curve.from) / curve.width
  local hump = curve.hump
  local shaped = part <= hump and (part / hump * 0.5) or (0.5 + (part - hump) / (1 - hump) * 0.5)
  return math.sin(math.pi * shaped) ^ 2
end

-- The wave's curves in layout { x, w } for recording { bands, phases, left, finishing }: each
-- { points, alpha, stroke, warning, dim, from, width, hump }. During the countdown it's orange
-- and shrinks to the left, a tenth each second; while finishing it's dim.
function dictation.wave(recording, layout)
  local width = layout.w * (recording.left and math.max(0, recording.left) / dictation.COUNTDOWN_SECONDS or 1)
  local hump = humpAt(recording.bands or {})
  local curves = {}
  for index, curve in ipairs(CURVES) do
    local shaped = { from = layout.x, width = width, hump = hump, alpha = curve.alpha, stroke = curve.stroke,
      warning = recording.left ~= nil and not recording.finishing, dim = recording.finishing == true, points = {} }
    local height, phase = dictation.waveAmplitude(recording, curve.band), (recording.phases or {})[index] or 0
    local steps = math.max(1, math.floor(width / STEP))
    for step = 0, steps do
      local x = layout.x + width * step / steps
      local y = CENTER_Y + height * dictation.taperAt(shaped, x) * math.sin(2 * math.pi * curve.cycles * (x - layout.x) / math.max(1, layout.w) + phase * curve.speed)
      shaped.points[#shaped.points + 1] = { x = x, y = y }
    end
    curves[index] = shaped
  end
  return curves
end

-- Each band's loudness above the room, scaled by its own recent peak, so the wave shows how
-- your voice changes however loud you speak and however loud your mic is. The room's level is
-- learned as it goes: it falls at once to anything quieter and creeps up, doubling every 8 s,
-- so a pause sets it again. Only sound twice the room's counts; the peak never goes under ten
-- times the room's, so a quiet room isn't blown up. The peak halves every 1.5 s, and a steady
-- voice reaches 0.8, leaving the top for a new peak.
local QUIETEST, MARGIN, PEAK_OVER_ROOM, HEADROOM, HALF_LIFE, ROOM_DOUBLING = 10 ^ (-90 / 20), 2, 10, 1.25, 1.5, 8

function dictation.newGain()
  return { peaks = {}, rooms = {} }
end

-- The bands { low, mid, high } in dB as 0 to 1, seconds after the last; updates state.
function dictation.gain(state, bands, seconds)
  local values = {}
  for _, band in ipairs({ "low", "mid", "high" }) do
    local heard = math.max(QUIETEST, 10 ^ ((bands[band] or -100) / 20))
    local room = math.min(heard, (state.rooms[band] or heard) * 2 ^ (seconds / ROOM_DOUBLING))
    state.rooms[band] = room
    local amplitude = math.max(0, heard - MARGIN * room)
    local peak = math.max(PEAK_OVER_ROOM * room, (state.peaks[band] or 0) * 0.5 ^ (seconds / HALF_LIFE))
    values[band] = math.min(1, math.sqrt(amplitude / peak) / HEADROOM)
    state.peaks[band] = math.max(peak, amplitude)
  end
  return values
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
