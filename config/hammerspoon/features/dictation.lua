-- Dictation: hold Right Option alone to talk, release to type it at the cursor, or release
-- with Shift to only copy it; tap it twice to talk hands-free, once more to type, and it types
-- by itself after 30 s of silence. A pill at the bottom of the screen shows what's heard and
-- where it goes; Esc cancels. Heard on the Mac by dictate.sh; dictation.lua holds the rules. Off
-- unless turned on with omv flags dictation on. The Dictation card, in the System menu, sets
-- the language and the sounds in ~/.config/omv/dictation.

local shell = require("shell")
local card = require("card")
local dictation = require("dictation")
local dictationPill = require("dictationpill")
local ownmic = require("ownmic")
local talkback = require("talkback")
local voiceagents = require("voiceagents")

local feature = {}

local HELPER = hs.configdir .. "/dictate.sh"
-- 20 times a second, for the key's timers and the countdown; the pill is redrawn only when its
-- text changes, and the wave moves in dictate.swift's window, drawn on the GPU.
local TICK_SECONDS = 0.05
-- Where the words would go is asked of macOS every this many ticks, 4 times a second.
local FOCUS_TICKS = 5
local ticks = 0
local START_SOUND, END_SOUND = "Tink", "Pop"

local keys = dictation.keys()
-- Right Command, for agents: the same rules, but the recording starts only once it's held
-- alone, so a Cmd shortcut never opens the mic, and it never locks hands-free.
local commandKeys = dictation.keys()
local COMMAND_OPTIONS = { late = true, lock = false }
-- What voice to agents needs from the agents' features, given by init.lua when it's on:
-- { rows, deliver(tty, text), spoke() }. Without it Right Command does nothing.
local agents = nil
-- Called on a press of either key, so talk-back stops before you speak.
local onPress = nil
-- Talk-back, when it's on, for the card's voice and output rows: features/talkback.lua.
local talkBack = nil
-- The helper's locale lists, read once at load, which also builds the helper.
local lists = { transcriber = {}, dictation = {} }
-- The recording now: { task, locale, started, ready, partial, percent, shown, locked, finishing,
-- review, auto, app, appIcon, secure, startApp, left, waveSent, inputClosed, chimed, rules,
-- languages, nextLocale, before, handover }. before is what was heard before a language switch;
-- handover is set while the helper of the language left behind finishes its words.
local current = nil
-- The last dictations, newest first, each { text, app, at }, kept in dictation.HISTORY_PATH so
-- they outlive a reload.
feature.recent = dictation.parseHistory(shell.readText(dictation.HISTORY_PATH))
-- Whether macOS's Reduce Motion is on, read at load.
local reduceMotion = false

local function settings()
  return shell.readText(dictation.PATH)
end

local function locale()
  return dictation.language(settings(), hs.host.locale.preferredLanguages())
end


local function play(name)
  if not dictation.sounds(settings()) then return end
  local sound = hs.sound.getByName(name)
  if sound then sound:volume(0.4):play() end
end

-- Puts text where you were typing, as dictation.pasteSteps says, one step after another.
local function runSteps(steps, index)
  index = index or 1
  local step = steps[index]
  if not step then return end
  if step.kind == "write" then hs.pasteboard.writeAllData(dictation.pasteboardData(step))
  elseif step.kind == "paste" then hs.eventtap.keyStroke({ "cmd" }, "v", 0)
  elseif step.kind == "wait" then return hs.timer.doAfter(step.seconds, function() runSteps(steps, index + 1) end)
  elseif step.kind == "restore" then shell.restoreClipboard(step.saved)
  elseif step.kind == "clear" then hs.pasteboard.clearContents()
  elseif step.kind == "notice" then shell.alert(step.text, 2) end
  runSteps(steps, index + 1)
end

-- App icons by bundle id, read once each, since the pill asks every tick.
local icons = {}

local function iconOf(bundle)
  if not bundle then return nil end
  if icons[bundle] == nil then icons[bundle] = hs.image.imageFromAppBundle(bundle) or false end
  return icons[bundle] or nil
end

-- The app you're typing in now: its name and icon, and whether its field is a password one.
local function focus()
  local app = hs.application.frontmostApplication()
  return { app = app and app:name() or "", appIcon = iconOf(app and app:bundleID()),
    secure = hs.eventtap.isSecureInputEnabled(), hasWindow = hs.accessibilityState() and hs.window.focusedWindow() ~= nil }
end

-- Types or copies text as dictation.delivery decides from info and where you are now, and
-- says which in the pill; gives the app it went to.
local function deliver(value, info, dropped)
  local now = focus()
  info.secure, info.hasWindow, info.app = now.secure, now.hasWindow, now.app
  local delivery = dictation.delivery(info, value, dropped)
  runSteps(dictation.pasteSteps(value, shell.saveClipboard(), delivery.kind))
  dictationPill.confirm(delivery)
  return now.app
end

local ticker = nil

local function stopTicker()
  if ticker then ticker:stop() end
  ticker = nil
end

-- Writes a line to the helper, until its input is closed: writing to a helper that has ended
-- would kill Hammerspoon, which is why the helper reads on until then.
local function send(recording, word)
  if recording and recording.task and not recording.inputClosed and recording.task:isRunning() then
    recording.task:setInput(word .. "\n")
  end
end

-- After the helper's last line: nothing more is written to it, and closing its input lets it end.
local function closeInput(recording)
  if recording.inputClosed then return end
  recording.inputClosed = true
  if recording.task then recording.task:closeInput() end
end

-- Draws the pill, and tells the helper where its wave goes, or to hide it, when that changed.
local function drawPill(recording)
  local _, strip = dictationPill.draw(recording)
  local tokens = shell.themeTokens()
  local command = strip and dictation.waveCommand(strip, recording,
    { fg = tokens.fg, accent = tokens.accent, warning = dictationPill.WARNING }, reduceMotion) or "hide"
  if command == recording.waveSent then return end
  recording.waveSent = command
  send(recording, command)
end

-- Adds entry to the kept dictations and saves them, readable by you only: they're what you said.
local function keep(entry)
  feature.recent = dictation.remember(feature.recent, entry)
  local existing = io.open(dictation.HISTORY_PATH, "r")
  if existing then existing:close()
  else
    -- Made empty first with only your access, so it's never readable by others, even briefly.
    os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "' && umask 077 && : >> '" .. dictation.HISTORY_PATH .. "'")
  end
  local file = io.open(dictation.HISTORY_PATH, "w")
  if not file then return end
  file:write(dictation.historyText(feature.recent))
  file:close()
end

-- Sends prompt to row: into its prompt, unsent, when it's done; copied when it's busy.
local function sendToAgent(row, prompt, why)
  keep({ text = prompt, app = "→ " .. row.label, at = os.time() })
  if row.state ~= "done" then
    hs.pasteboard.setContents(prompt)
    return dictationPill.confirm({ kind = "copy", message = "Copied: " .. row.label .. " is " .. ((why or row.state) == "asks" and "asking" or "working") })
  end
  dictationPill.confirm({ kind = "type", message = "In " .. row.label .. "'s prompt", hint = "Enter sends" })
  agents.deliver(row.id, prompt)
end

-- After a release that named no session: { heard, prompt, rows, timer }, while the pill waits
-- for a digit to pick one; Esc, another key or the time running out copies the words.
local choosing = nil
local CHOOSE_SECONDS = 5

local function endChoosing(copy)
  local was = choosing
  choosing = nil
  if not was then return end
  if was.timer then was.timer:stop() end
  if not copy then return end
  hs.pasteboard.setContents(was.prompt)
  dictationPill.confirm({ kind = "copy", message = "Copied: " .. was.prompt })
end

local function choose(heard, prompt, rows)
  endChoosing(false)
  choosing = { heard = heard, prompt = prompt, rows = rows }
  choosing.timer = hs.timer.doAfter(CHOOSE_SECONDS, function() endChoosing(true) end)
  dictationPill.choosing(choosing)
end

-- A digit while the pill asks which one: sends the words to that session, or says there's none.
local function picked(number)
  local row = choosing.rows[number]
  if not row then
    choosing.note = "No session " .. number .. ": which one?"
    return dictationPill.choosing(choosing)
  end
  local prompt = choosing.prompt
  endChoosing(false)
  sendToAgent(row, prompt)
end

-- Where an agent's words go on release: into a done session's prompt, unsent; copied for a
-- busy one; when none was named, the pill asks which one, by number.
local function finishedForAgent(recording, final)
  local text = dictation.join(recording.before, final)
  local spoke = agents.spoke and agents.spoke()
  local target = voiceagents.target(text, agents.rows(), spoke)
  if dictation.outcome(text).kind == "notice" then return dictationPill.hide() end
  if target.kind ~= "none" then return sendToAgent(target.row, target.prompt, target.why) end
  local rows = voiceagents.numbered(agents.rows(), spoke)
  local prompt = voiceagents.leftover(text, rows)
  if #rows == 0 or not prompt then
    dictationPill.hide()
    return shell.alert(target.hint, 2)
  end
  choose(text, prompt, rows)
end

local function finished(recording, final)
  if current ~= recording then return end
  current = nil
  closeInput(recording)
  if recording.agent then return finishedForAgent(recording, final) end
  local text, dropped = dictation.join(recording.before, final), 0
  if dictation.cleanupOn(settings()) then text, dropped = dictation.clean(text) end
  text = dictation.replace(text, recording.rules)
  local outcome = dictation.outcome(text)
  if outcome.kind == "notice" then
    dictationPill.hide()
    return shell.alert(outcome.text, 1.2)
  end
  local info = { review = recording.review, auto = recording.auto, startApp = recording.startApp }
  local app = deliver(outcome.text, info, dropped)
  keep({ text = outcome.text, app = dictation.historyApp(info, app), at = os.time() })
end

local function showProblem(recording, problem)
  recording.problem = dictation.notice(problem, recording.locale)
  closeInput(recording)
  drawPill(recording)
  hs.timer.doAfter(2.5, function()
    if current == recording then current = nil end
    dictationPill.hide()
  end)
end

local startHelper

-- The helper of the language left behind has said everything it heard: it's kept, and the
-- next language's helper starts, unless the dictation ended meanwhile.
local function handedOver(recording, final)
  closeInput(recording)
  recording.handover = false
  recording.before = dictation.join(recording.before, final)
  recording.partial = dictation.replace(recording.before, recording.rules)
  if recording.finishing then return finished(recording, "") end
  recording.locale = recording.nextLocale
  recording.nextLocale = dictation.nextLanguage(recording.languageList, recording.locale)
  recording.nextName = recording.nextLocale and dictation.plainLanguage(dictation.languageName(lists, recording.nextLocale))
  startHelper(recording)
end

local function chime(recording)
  if not dictation.chimeDue(recording) then return end
  recording.chimed = true
  play(START_SOUND)
end

-- Reads the helper's lines as they come; a chunk may end mid-line, kept until the rest comes.
local function onOutput(recording, chunk)
  recording.buffer = (recording.buffer or "") .. (chunk or "")
  for line in recording.buffer:gmatch("([^\n]*)\n") do
    local message = dictation.parse(line)
    if message and message.kind == "partial" then
      recording.partial = dictation.replace(dictation.join(recording.before, message.text), recording.rules)
      if recording.agent then recording.agentTarget = voiceagents.target(recording.partial, recording.agentRows, recording.spoke) end
    elseif message and message.kind == "level" then
      local level = dictation.levelOf(message.level)
      if dictation.isVoice(level) then dictation.press(keys, "voice", hs.timer.secondsSinceEpoch()) end
    elseif message and message.kind == "progress" then recording.percent = message.percent
    elseif message and message.kind == "problem" then return showProblem(recording, message.problem)
    elseif message and message.kind == "final" and recording.handover then
      recording.buffer = ""
      return handedOver(recording, message.text)
    elseif message and message.kind == "final" then return finished(recording, message.text)
    elseif line == "ready\t" or line == "ready" then
      recording.ready = true
      chime(recording)
    end
  end
  recording.buffer = recording.buffer:match("([^\n]*)$")
end

local function cancel()
  stopTicker()
  local recording = current
  current = nil
  if recording and recording.handover and recording.task then recording.task:terminate() end
  send(recording, "cancel")
  if recording then closeInput(recording) end
  dictationPill.hide()
end

-- Each tick: the key's timers, where the words would go now, the countdown, and the pill.
local function tick()
  local now = hs.timer.secondsSinceEpoch()
  if keys.phase ~= "idle" then
    local action = dictation.press(keys, "tick", now)
    if action then feature.act(action) end
  end
  if commandKeys.phase ~= "idle" then
    local action = dictation.press(commandKeys, "tick", now, COMMAND_OPTIONS)
    if action then feature.act(action) end
  end
  local recording = current
  -- Right Command held, before its recording starts, still needs the ticks.
  if not recording and commandKeys.phase == "pressed" then return end
  if not recording then return stopTicker() end
  if not recording.shown or recording.problem then return end
  if dictation.finishOverdue(recording, now) then
    if recording.task then recording.task:terminate() end
    return finished(recording, recording.partial or "")
  end
  ticks = ticks + 1
  if not recording.finishing then
    if ticks % FOCUS_TICKS == 0 then
      local here = focus()
      recording.app, recording.appIcon, recording.secure = here.app, here.appIcon, here.secure
    end
    recording.left = dictation.remaining(keys, now)
  end
  drawPill(recording)
end

-- Starts the helper for recording's language; a helper only acts while it's recording's own,
-- so one left behind by a language switch never hides or ends the dictation.
startHelper = function(recording)
  -- Right Command listens with the engine that takes hint words, the project names.
  local engine = dictation.engine(recording.locale, lists, recording.agent)
  if not engine then
    recording.shown = true
    return showProblem(recording, "language")
  end
  recording.ready, recording.waveSent, recording.buffer, recording.inputClosed = false, nil, "", false
  -- A download shows only when this helper, not the dictation, has waited a while.
  recording.percent, recording.helperStarted = nil, hs.timer.secondsSinceEpoch()
  -- Which helper is recording's own, by a token: naming the task in its own callbacks would
  -- hold it forever.
  local own = {}
  recording.own = own
  recording.task = hs.task.new(HELPER, function()
    -- A cancelled helper can end after the next one started, which still listens.
    if not (current and current.task and current.own ~= own) then ownmic.set("dictation", false) end
    if recording.own ~= own then return end
    recording.task = nil
    if current ~= recording then return end
    if recording.handover then return handedOver(recording, "") end
    local next = dictation.onHelperExit(recording)
    if next == "finish" then return finished(recording, recording.partial or "") end
    if next == "hide" then
      current = nil
      dictationPill.hide()
    end
  end, function(_, out)
    if recording.own == own then onOutput(recording, out) end
    return true
  end, { "listen", recording.locale, engine, table.concat(recording.words, "|") })
  -- Before the helper opens the mic, so the in-use dot never takes it for another app's.
  ownmic.set("dictation", true)
  recording.task:start()
end

-- The words the helper listens for: yours, and for an agent the sessions' folder names, each
-- part of omv-web too, so the project's name is heard as written.
local function wordsFor(rows)
  local list, seen = {}, {}
  local function add(word)
    if seen[word:lower()] then return end
    seen[word:lower()], list[#list + 1] = true, word
  end
  for _, word in ipairs(dictation.words(settings())) do add(word) end
  for _, row in ipairs(rows or {}) do
    for part in tostring(row.label):gmatch("[^%-_.%s]+") do add(part) end
  end
  return list
end

-- forAgent: Right Command's recording, whose words go to an agent as they were heard: no
-- replacements, no filler cleanup, one language.
local function record(forAgent)
  if current then cancel() end
  stopTicker()
  local text = settings()
  local languageList = forAgent and {} or dictation.languages(text)
  local recording = { locale = locale(), started = hs.timer.secondsSinceEpoch(), rules = forAgent and {} or dictation.replacements(text),
    languageList = languageList, languages = #languageList >= 2 or nil, agent = forAgent or nil }
  if forAgent then
    recording.agentRows, recording.spoke = agents.rows(), agents.spoke and agents.spoke()
    recording.numbered = voiceagents.numbered(recording.agentRows, recording.spoke)
    recording.agentTarget = voiceagents.target("", recording.agentRows, recording.spoke)
  end
  recording.words = wordsFor(recording.agentRows)
  recording.nextLocale = dictation.nextLanguage(languageList, recording.locale)
  recording.nextName = recording.nextLocale and dictation.plainLanguage(dictation.languageName(lists, recording.nextLocale))
  current = recording
  startHelper(recording)
  if current == recording and not recording.problem then ticker = hs.timer.doEvery(TICK_SECONDS, tick) end
end

-- Tab: the words so far are kept, and listening goes on in the next language once the helper
-- of this one has said what it heard, so two never share the mic.
local function switch()
  local recording = current
  if not recording or recording.handover or recording.finishing or not recording.nextLocale then return end
  recording.handover = true
  recording.ready = false
  send(recording, "stop")
end

local function show(locked)
  if not current then return end
  local here = focus()
  current.shown, current.locked = true, locked
  current.app, current.appIcon, current.secure = here.app, here.appIcon, here.secure
  -- A locked one that types by itself only types into the app it started in.
  if locked then current.startApp = here.app end
  chime(current)
  drawPill(current)
end

-- Ends the recording; how says what then happens to the words: review only copies them,
-- auto is a locked one that ended by itself.
local function finish(how)
  local recording = current
  if not recording then return end
  if not recording.shown then return cancel() end
  recording.finishing, recording.stopped, recording.left = true, hs.timer.secondsSinceEpoch(), nil
  recording.review, recording.auto = how == "review", how == "auto"
  play(END_SOUND)
  drawPill(recording)
  -- In a handover the helper has been told to stop already; its words end the dictation.
  if not recording.handover then send(recording, "stop") end
end

local ACTIONS = {
  record = function() record(false) end, show = function() show(false) end,
  start = function()
    if not agents then return end
    record(true)
    show(false)
  end, lock = function() show(true) end, cancel = cancel,
  finish = function() finish() end, review = function() finish("review") end, timeout = function() finish("auto") end,
  switch = switch,
}

function feature.act(action)
  if ACTIONS[action] then ACTIONS[action]() end
end

local ESCAPE, TAB = 53, 48

local MOUSE_DOWNS = { [hs.eventtap.event.types.leftMouseDown] = true, [hs.eventtap.event.types.rightMouseDown] = true }

-- Right Command's events: while it's held, any other key or a click cancels it and goes
-- through, so Cmd+C, Cmd+Tab and Cmd+click work as always; Esc cancels and is swallowed
-- once it listens.
local function onCommandKey(kind, name, code)
  if MOUSE_DOWNS[kind] then name = "other" end
  if kind == hs.eventtap.event.types.keyDown then name = code == ESCAPE and "escape" or "other" end
  if not name or name == "shift" then return false end
  if commandKeys.phase == "idle" and name ~= "command-down" then return false end
  if name == "command-down" then
    if keys.phase ~= "idle" or current then return false end
    if onPress then onPress() end
    if not ticker then ticker = hs.timer.doEvery(TICK_SECONDS, tick) end
  end
  local action, swallow = dictation.press(commandKeys, name, hs.timer.secondsSinceEpoch(), COMMAND_OPTIONS)
  if action then hs.timer.doAfter(0, function() feature.act(action) end) end
  return swallow
end

-- The digits 1 to 9 by key code, for picking a session after a release named none.
local DIGITS = { [18] = 1, [19] = 2, [20] = 3, [21] = 4, [23] = 5, [22] = 6, [26] = 7, [28] = 8, [25] = 9 }

-- While the pill asks which one: a digit picks, Esc copies, both swallowed; any other key or a
-- click copies and goes through, so typing carries on.
local function onChoosingKey(event, kind)
  if kind == hs.eventtap.event.types.keyDown then
    local code, flags = event:getKeyCode(), event:getFlags()
    local plain = not (flags.cmd or flags.ctrl or flags.alt)
    if plain and DIGITS[code] then
      hs.timer.doAfter(0, function() if choosing then picked(DIGITS[code]) end end)
      return true
    end
    if code == ESCAPE then
      hs.timer.doAfter(0, function() endChoosing(true) end)
      return true
    end
  end
  hs.timer.doAfter(0, function() endChoosing(true) end)
  return false
end

local function onKey(event)
  local kind = event:getType()
  if choosing and kind ~= hs.eventtap.event.types.flagsChanged then return onChoosingKey(event, kind) end
  local name
  if kind == hs.eventtap.event.types.flagsChanged then
    local flags = event:getFlags()
    name = dictation.eventFor(event:getKeyCode(), flags.alt == true, flags.shift == true, flags.cmd == true)
    -- Talking again while the pill asks which one: the words waiting are copied first.
    if choosing and (name == "option-down" or name == "command-down") then endChoosing(true) end
  end
  -- Talk-back stops at Right Command even without voice to agents.
  if name == "command-down" and not agents and onPress then onPress() end
  if agents and (commandKeys.phase ~= "idle" or name == "command-down") then
    return onCommandKey(kind, name, kind == hs.eventtap.event.types.keyDown and event:getKeyCode() or nil)
  end
  if name == "command-down" or name == "command-up" or MOUSE_DOWNS[kind] then return false end
  if kind == hs.eventtap.event.types.keyDown then
    local code = event:getKeyCode()
    name = code == ESCAPE and "escape" or "other"
    -- Tab is the language switch only while the pill listens and there's a language to go to;
    -- before that, Right Option+Tab cancels like any other key.
    if code == TAB and (keys.phase == "listening" or keys.phase == "locked") and current and current.nextLocale then
      name = "tab"
    end
  end
  if not name then return false end
  if keys.phase == "idle" and name ~= "option-down" then return false end
  if name == "option-down" and keys.phase == "idle" and onPress then onPress() end
  local action, swallow = dictation.press(keys, name, hs.timer.secondsSinceEpoch())
  if action then hs.timer.doAfter(0, function() feature.act(action) end) end
  return swallow
end

feature.keys = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown,
  hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown }, onKey):start()

-- Turns on voice to agents (Right Command), with what it needs from the agents' features:
-- { rows(), deliver(tty, text), spoke() }.
function feature.agents(api)
  agents = api
end

-- Whether a dictation or an agent recording runs now, for talk-back.
function feature.recording()
  return current ~= nil or keys.phase ~= "idle" or commandKeys.phase ~= "idle"
end

-- fn runs on every press of Right Option or Right Command, before anything is heard.
function feature.onPress(fn)
  onPress = fn
end

-- Shows talk-back's voice and output on the card; api is features/talkback.lua.
function feature.withTalkBack(api)
  talkBack = api
end

-- Builds the helper and reads which languages the Mac can hear, without waiting on it.
shell.execute("'" .. HELPER .. "' locales", function(output)
  lists = dictation.parseLocales(output)
end)

shell.execute("/usr/bin/defaults read com.apple.universalaccess reduceMotion", function(output)
  reduceMotion = tostring(output or ""):match("^%s*1") ~= nil
end)

-- Pastes a kept dictation again, the last one unless index says, for one that went nowhere.
function feature.pasteLast(index)
  local entry = feature.recent[type(index) == "number" and index or 1]
  if not entry then return shell.alert("Nothing dictated yet", 1.2) end
  deliver(entry.text, {})
end

-- The Dictation card: the language, the sounds, the key and what it needs.
local function languageName(id)
  return dictation.languageName(lists, id)
end

local function allLocales()
  local seen, all = {}, {}
  for _, list in ipairs({ lists.transcriber, lists.dictation }) do
    for _, id in ipairs(list) do
      if not seen[id] then seen[id] = true; all[#all + 1] = id end
    end
  end
  table.sort(all, function(a, b) return languageName(a) < languageName(b) end)
  return all
end

local function save(text)
  os.execute("/bin/mkdir -p '" .. shell.HOME .. "/.config/omv'")
  local file = io.open(dictation.PATH, "w")
  if not file then return shell.alert("Couldn't write ~/.config/omv/dictation", 2) end
  file:write(text)
  file:close()
end

-- Gets a language's model now, so the first hold doesn't wait for it.
local function install(language)
  local engine = dictation.engine(language, lists)
  if not engine then return shell.alert(dictation.notice("language", language), 2) end
  shell.alert("Getting " .. languageName(language) .. " for dictation…", 2)
  hs.task.new(HELPER, function(code)
    shell.alert(code == 0 and (languageName(language) .. " is ready for dictation") or ("Couldn't get " .. languageName(language)), 2)
  end, { "install", language, engine }):start()
end

local showLanguages

-- A language's name without its region, as the card lists it.
local function plainName(id)
  return dictation.plainLanguage(languageName(id))
end

local function rows()
  local start = locale()
  local tab = dictation.tabLanguage(settings(), start)
  return dictation.cardRows({
    language = plainName(start), tabLanguage = tab and plainName(tab),
    languageMissing = not dictation.isInstalled(lists, start) or (tab ~= nil and not dictation.isInstalled(lists, tab)),
    sounds = dictation.sounds(settings()), kept = #feature.recent,
    words = dictation.words(settings()), cleanup = dictation.cleanupOn(settings()),
    replacements = dictation.replacements(settings()), microphone = lists.microphone,
    talkBackVoice = talkBack and talkback.voiceName(talkback.voiceSetting(settings())),
    talkBackMissing = talkBack and talkback.voiceSetting(settings()) ~= "apple" and not talkBack.installed(),
    talkBackOutput = talkBack and talkback.outputSetting(settings()),
  })
end

local showCard, showHistory

local ROWS = dictation.CARD_ROWS

-- The next talk-back voice: plays the sample in it at once, or gets Kokoro first when it isn't
-- on the Mac yet, which plays the sample once it is.
local function nextTalkBackVoice()
  local voice = talkback.nextVoice(talkback.voiceSetting(settings()))
  save(dictation.setting(settings(), "talk-back voice", voice))
  if voice ~= "apple" and not talkBack.installed() then
    talkBack.install(function() if shell.isOpen("dictation") then showCard(ROWS.talkBackVoice) end end)
  else
    talkBack.preview(voice)
  end
  return showCard(ROWS.talkBackVoice)
end

local function toggleTalkBackOutput()
  local anywhere = talkback.outputSetting(settings()) == "anywhere"
  save(dictation.setting(settings(), "talk-back output", anywhere and "headphones" or "anywhere"))
  return showCard(ROWS.talkBackOutput)
end

-- Toggles key, sounds or cleanup, in ~/.config/omv/dictation, and shows the card again on its row.
local function toggle(key, on, row)
  save(dictation.setting(settings(), key, on and "off" or "on"))
  return showCard(row)
end

-- Opens ~/.config/omv/dictation for your words, with a words line to fill in when it has none.
local function editWords()
  if #dictation.words(settings()) == 0 and not (settings() or ""):match("words%s*=") then
    save(dictation.setting(settings(), "words", "omv"))
  end
  shell.open({ "-t", dictation.PATH })()
end

-- Opens ~/.config/omv/dictation for its replacements, with one to copy when it has none.
local function editReplacements()
  if #dictation.replacements(settings()) == 0 then
    save((settings() or "") .. ((settings() or ""):match("[^\n]$") and "\n" or "") .. "replace = slash voice > /voice\n")
  end
  shell.open({ "-t", dictation.PATH })()
end

local showLanguageScreen

-- The groups a card's rows are in, for its height: each has a title line.
local function groupCount(shown)
  local seen, count = {}, 0
  for _, row in ipairs(shown) do
    if row.group and not seen[row.group] then seen[row.group], count = true, count + 1 end
  end
  return count
end

function showCard(selected)
  local shown = rows()
  shell.show("dictation", shell.centered(shell.LIST_WIDTH, 28 + 46 + #shown * 30 + groupCount(shown) * 26 + 44), card.html({
    prompt = "Dictation…", rows = shown, compact = true, step = true, selected = selected,
    footer = { { key = "Right Option", text = "hold, or tap twice" }, { key = "Left/Right", text = "change" },
      { key = "Enter", text = "open ›" }, { key = "Esc", text = "close" } },
  }), function(message)
    local id = message.id or ""
    if message.type == "step" then
      if id:match(":sounds$") then return toggle("sounds", dictation.sounds(settings()), ROWS.sounds) end
      if id:match(":cleanup$") then return toggle("cleanup", dictation.cleanupOn(settings()), ROWS.cleanup) end
      if id:match(":talkBackVoice$") then return nextTalkBackVoice() end
      if id:match(":talkBackOutput$") then return toggleTalkBackOutput() end
      if id == "1:languages" then return showLanguageScreen(1) end
      return
    end
    if message.type ~= "choose" then return shell.close() end
    if id == "languages" then return showLanguageScreen(1) end
    if id == "sounds" then return toggle("sounds", dictation.sounds(settings()), ROWS.sounds) end
    if id == "cleanup" then return toggle("cleanup", dictation.cleanupOn(settings()), ROWS.cleanup) end
    if id == "talkBackVoice" then return nextTalkBackVoice() end
    if id == "talkBackOutput" then return toggleTalkBackOutput() end
    if id == "dictations" then return feature.recent[1] and showHistory() or nil end
    if id == "permissions" and lists.microphone == "granted" then return end
    shell.close()
    if id == "words" then return editWords() end
    if id == "replacements" then return editReplacements() end
    if id == "permissions" then return require("features.permissions").open() end
  end)
end

-- Reads what the Mac has now, the models and the microphone access, then shows the card.
function feature.open(selected)
  if type(selected) ~= "number" then selected = nil end
  shell.execute("'" .. HELPER .. "' locales", function(output)
    lists = dictation.parseLocales(output)
    showCard(selected)
  end)
end

-- The kept dictations, newest first; picking one pastes it again.
function showHistory()
  local shown = dictation.historyRows(feature.recent, os.time())
  shell.show("dictation", shell.centered(shell.LIST_WIDTH, 28 + 46 + #shown * 30 + 4), card.html({
    prompt = "Dictations…", rows = shown, compact = true,
  }), function(message)
    if message.type ~= "choose" then return showCard(6) end
    local index = tonumber((message.id or ""):match("^dictation:(%d+)$"))
    shell.close()
    if index then feature.pasteLast(index) end
  end, { onEscape = function() showCard(6) end })
end

-- Every language the Mac can hear, macOS's first; picking one writes it and gets it.
-- Saves start as the language dictation starts in and tab as the one Tab moves to; without a
-- language line before, start stays macOS's, unwritten.
local function saveLanguages(start, tab, ownStart)
  local text = dictation.withLanguages(settings(), start, tab)
  if not ownStart then text = dictation.setting(text, "language", nil) end
  save(text)
end

-- Whether the file picks the language, rather than macOS.
local function ownStart()
  return dictation.language(settings(), { "" }) ~= ""
end

-- The locales to pick from for which, start or tab: macOS's language first for start, None
-- first for tab. Picking one whose model isn't on the Mac gets it.
function showLanguages(which)
  local start = locale()
  local tab = dictation.tabLanguage(settings(), start)
  local shown = which == "tab" and { { id = "none", icon = "󰅖", label = "None", hint = "Tab doesn't switch" } }
    or { { id = "macos", icon = "󰀵", label = "macOS's language", hint = languageName(hs.host.locale.preferredLanguages()[1] or "en-US") } }
  for _, id in ipairs(allLocales()) do shown[#shown + 1] = { id = "locale:" .. id, icon = "󰗊", label = languageName(id), hint = id } end
  local row = which == "tab" and 2 or 1
  shell.show("dictation", shell.centered(shell.LIST_WIDTH, 28 + 46 + shell.LIST_VISIBLE_ROWS * 30 + 4), card.html({
    prompt = which == "tab" and "Tab switches to…" or "Starts in…", rows = shown, compact = true,
  }), function(message)
    if message.type ~= "choose" then return showLanguageScreen(row) end
    local id = (message.id or ""):match("^locale:(.+)$")
    if which == "tab" then
      saveLanguages(start, id, ownStart())
    else
      local newStart = id or hs.host.locale.preferredLanguages()[1] or "en-US"
      saveLanguages(newStart, tab, id ~= nil)
    end
    showLanguageScreen(row)
    if id and not dictation.isInstalled(lists, id) then install(id) end
  end, { onEscape = function() showLanguageScreen(row) end })
end

-- The Languages screen: the language dictation starts in and the one Tab moves to. Enter on
-- either picks another, or gets its model when it isn't on the Mac.
showLanguageScreen = function(selected)
  local start = locale()
  local tab = dictation.tabLanguage(settings(), start)
  local startInstalled = dictation.isInstalled(lists, start)
  local tabInstalled = tab ~= nil and dictation.isInstalled(lists, tab)
  local shown = dictation.languageRows({ startName = plainName(start), ownStart = ownStart(), startInstalled = startInstalled,
    tabName = tab and plainName(tab), tabInstalled = tabInstalled })
  shell.show("dictation", shell.centered(shell.LIST_WIDTH, 28 + 46 + #shown * 30 + 44), card.html({
    prompt = "Languages…", rows = shown, compact = true, selected = selected,
    footer = { { key = "Enter", text = "pick ›" }, { key = "Esc", text = "back" } },
  }), function(message)
    if message.type ~= "choose" then return showCard(ROWS.languages) end
    if message.id == "start" and not startInstalled then
      shell.close()
      return install(start)
    end
    if message.id == "tab" and tab and not tabInstalled then
      shell.close()
      return install(tab)
    end
    showLanguages(message.id == "tab" and "tab" or "start")
  end, { onEscape = function() showCard(ROWS.languages) end })
end

return feature
