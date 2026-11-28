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

local function finished(recording, final)
  if current ~= recording then return end
  current = nil
  closeInput(recording)
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
  recording.nextName = recording.nextLocale and dictation.languageName(lists, recording.nextLocale)
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
  local recording = current
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
  local engine = dictation.engine(recording.locale, lists)
  if not engine then
    recording.shown = true
    return showProblem(recording, "language")
  end
  recording.ready, recording.waveSent, recording.buffer, recording.inputClosed = false, nil, "", false
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
  end, { "listen", recording.locale, engine, table.concat(dictation.words(settings()), "|") })
  -- Before the helper opens the mic, so the in-use dot never takes it for another app's.
  ownmic.set("dictation", true)
  recording.task:start()
end

local function record()
  if current then cancel() end
  stopTicker()
  local text = settings()
  local languageList = dictation.languages(text)
  local recording = { locale = locale(), started = hs.timer.secondsSinceEpoch(), rules = dictation.replacements(text),
    languageList = languageList, languages = #languageList >= 2 or nil }
  recording.nextLocale = dictation.nextLanguage(languageList, recording.locale)
  recording.nextName = recording.nextLocale and dictation.languageName(lists, recording.nextLocale)
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
  record = record, show = function() show(false) end, lock = function() show(true) end, cancel = cancel,
  finish = function() finish() end, review = function() finish("review") end, timeout = function() finish("auto") end,
  switch = switch,
}

function feature.act(action)
  if ACTIONS[action] then ACTIONS[action]() end
end

local ESCAPE, TAB = 53, 48

local function onKey(event)
  local kind = event:getType()
  local name
  if kind == hs.eventtap.event.types.flagsChanged then
    local flags = event:getFlags()
    name = dictation.eventFor(event:getKeyCode(), flags.alt == true, flags.shift == true)
  elseif kind == hs.eventtap.event.types.keyDown then
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
  local action, swallow = dictation.press(keys, name, hs.timer.secondsSinceEpoch())
  if action then hs.timer.doAfter(0, function() feature.act(action) end) end
  return swallow
end

feature.keys = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown }, onKey):start()

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

local function rows()
  local language = locale()
  return dictation.cardRows({
    -- With no macOS language given, an empty one means the file has no language line.
    ownLanguage = dictation.language(settings(), { "" }) ~= "",
    language = languageName(language), sounds = dictation.sounds(settings()), kept = #feature.recent,
    words = dictation.words(settings()), cleanup = dictation.cleanupOn(settings()),
    microphone = lists.microphone, installed = dictation.isInstalled(lists, language),
  })
end

local showCard, showHistory

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
  shell.open({ "-t", dictation.PATH })
end

function showCard(selected)
  local shown = rows()
  shell.show("dictation", shell.centered(shell.LIST_WIDTH, 28 + 46 + #shown * 30 + 2 * 26 + 44), card.html({
    prompt = "Dictation…", rows = shown, compact = true, step = true, selected = selected,
    footer = { { key = "Left/Right", text = "change" }, { key = "Enter", text = "open ›" }, { key = "Esc", text = "close" } },
  }), function(message)
    local id = message.id or ""
    if message.type == "step" then
      if id:match(":sounds$") then return toggle("sounds", dictation.sounds(settings()), 4) end
      if id:match(":cleanup$") then return toggle("cleanup", dictation.cleanupOn(settings()), 3) end
      if id == "1:language" then return showLanguages() end
      return
    end
    if message.type ~= "choose" then return shell.close() end
    if id == "language" then return showLanguages() end
    if id == "sounds" then return toggle("sounds", dictation.sounds(settings()), 4) end
    if id == "cleanup" then return toggle("cleanup", dictation.cleanupOn(settings()), 3) end
    if id == "dictations" then return feature.recent[1] and showHistory() or nil end
    if id == "key" then return end
    if id == "permissions" and lists.microphone == "granted" then return end
    if id == "install" and dictation.isInstalled(lists, locale()) then return end
    shell.close()
    if id == "words" then return editWords() end
    if id == "permissions" then return require("features.permissions").open() end
    if id == "install" then return install(locale()) end
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
function showLanguages()
  local shown = { { id = "macos", icon = "󰀵", label = "macOS's language", hint = languageName(hs.host.locale.preferredLanguages()[1] or "en-US") } }
  for _, id in ipairs(allLocales()) do shown[#shown + 1] = { id = "locale:" .. id, icon = "󰗊", label = languageName(id), hint = id } end
  shell.show("dictation", shell.centered(shell.LIST_WIDTH, 28 + 46 + shell.LIST_VISIBLE_ROWS * 30 + 4), card.html({
    prompt = "Dictation language…", rows = shown, compact = true,
  }), function(message)
    if message.type ~= "choose" then return showCard(1) end
    local id = (message.id or ""):match("^locale:(.+)$")
    save(dictation.setting(settings(), "language", id))
    showCard(1)
    if not dictation.isInstalled(lists, id or locale()) then install(id or locale()) end
  end, { onEscape = function() showCard(1) end })
end

return feature
