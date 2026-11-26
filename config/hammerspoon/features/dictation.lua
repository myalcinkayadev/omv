-- Dictation: hold Right Option alone to talk, release to type it at the cursor; tap it twice
-- to talk hands-free, once more to type. A pill at the bottom of the screen shows what's
-- heard; Esc cancels. Heard on the Mac by dictate.sh; dictation.lua holds the rules. Off
-- unless turned on with omv flags dictation on. The Dictation card, in the System menu, sets
-- the language and the sounds in ~/.config/omv/dictation.

local shell = require("shell")
local card = require("card")
local dictation = require("dictation")
local dictationPill = require("dictationpill")

local feature = {}

local HELPER = hs.configdir .. "/dictate.sh"
local TICK_SECONDS = 0.05
local START_SOUND, END_SOUND = "Tink", "Pop"

local keys = dictation.keys()
-- The helper's locale lists, read once at load, which also builds the helper.
local lists = { transcriber = {}, dictation = {} }
-- The recording now: { task, locale, started, ready, partial, history, shownLevel, percent, shown, locked, finishing }.
local current = nil
feature.recent = {}

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

local function typeText(value)
  local hasWindow = hs.accessibilityState() and hs.window.focusedWindow() ~= nil
  runSteps(dictation.pasteSteps(value, shell.saveClipboard(), hs.eventtap.isSecureInputEnabled(), hasWindow))
end

local ticker = nil

local function stopTicker()
  if ticker then ticker:stop() end
  ticker = nil
end

local function finished(recording, final)
  if current ~= recording then return end
  current = nil
  dictationPill.hide()
  local outcome = dictation.outcome(final)
  if outcome.kind == "notice" then return shell.alert(outcome.text, 1.2) end
  feature.recent = dictation.remember(feature.recent, outcome.text)
  typeText(outcome.text)
end

local function showProblem(recording, problem)
  recording.problem = dictation.notice(problem, recording.locale)
  dictationPill.draw(recording)
  hs.timer.doAfter(2.5, function()
    if current == recording then current = nil end
    dictationPill.hide()
  end)
end

-- Reads the helper's lines as they come; a chunk may end mid-line, kept until the rest comes.
local function onOutput(recording, chunk)
  recording.buffer = (recording.buffer or "") .. (chunk or "")
  for line in recording.buffer:gmatch("([^\n]*)\n") do
    local message = dictation.parse(line)
    if message and message.kind == "partial" then recording.partial = message.text
    elseif message and message.kind == "level" then
      recording.shownLevel = dictation.smooth(recording.shownLevel or 0, dictation.levelOf(message.level))
      recording.history = dictation.pushLevel(recording.history or {}, recording.shownLevel)
    elseif message and message.kind == "progress" then recording.percent = message.percent
    elseif message and message.kind == "problem" then return showProblem(recording, message.problem)
    elseif message and message.kind == "final" then return finished(recording, message.text)
    elseif line == "ready\t" or line == "ready" then recording.ready = true end
  end
  recording.buffer = recording.buffer:match("([^\n]*)$")
  if recording.shown and not recording.finishing then dictationPill.draw(recording) end
end

local function send(recording, word)
  if recording and recording.task and recording.task:isRunning() then recording.task:setInput(word .. "\n") end
end

local function cancel()
  stopTicker()
  local recording = current
  current = nil
  send(recording, "cancel")
  if recording and recording.task then recording.task:closeInput() end
  dictationPill.hide()
end

local function record()
  if current then cancel() end
  local language = locale()
  local engine = dictation.engine(language, lists)
  local recording = { locale = language, started = hs.timer.secondsSinceEpoch(), history = {} }
  current = recording
  if not engine then
    recording.shown = true
    return showProblem(recording, "language")
  end
  recording.task = hs.task.new(HELPER, function()
    recording.task = nil
    if current == recording and not recording.finishing and not recording.problem then
      current = nil
      dictationPill.hide()
    end
  end, function(_, out)
    onOutput(recording, out)
    return true
  end, { "listen", language, engine })
  recording.task:start()
  ticker = hs.timer.doEvery(TICK_SECONDS, function()
    local action = dictation.press(keys, "tick", hs.timer.secondsSinceEpoch())
    if action then feature.act(action) end
    if current and current.shown and current.locked then dictationPill.draw(current) end
    if keys.phase == "idle" then stopTicker() end
  end)
end

local function show(locked)
  if not current then return end
  current.shown, current.locked = true, locked
  play(START_SOUND)
  dictationPill.draw(current)
end

local function finish()
  stopTicker()
  local recording = current
  if not recording then return end
  if not recording.shown then return cancel() end
  recording.finishing = true
  play(END_SOUND)
  dictationPill.draw(recording)
  send(recording, "stop")
end

local ACTIONS = { record = record, show = function() show(false) end, lock = function() show(true) end, finish = finish, cancel = cancel }

function feature.act(action)
  if ACTIONS[action] then ACTIONS[action]() end
end

local ESCAPE = 53

local function onKey(event)
  local kind = event:getType()
  local name
  if kind == hs.eventtap.event.types.flagsChanged then
    name = dictation.eventFor(event:getKeyCode(), event:getFlags().alt == true)
  elseif kind == hs.eventtap.event.types.keyDown then
    name = event:getKeyCode() == ESCAPE and "escape" or "other"
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

-- Pastes the last dictation again, for one that went nowhere.
function feature.pasteLast()
  if not feature.recent[1] then return shell.alert("Nothing dictated yet", 1.2) end
  typeText(feature.recent[1])
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
    language = languageName(language), sounds = dictation.sounds(settings()), hasRecent = feature.recent[1] ~= nil,
    microphone = lists.microphone, installed = dictation.isInstalled(lists, language),
  })
end

local function showCard(selected)
  local shown = rows()
  shell.show("dictation", shell.centered(shell.LIST_WIDTH, 28 + 46 + #shown * 30 + 2 * 26 + 44), card.html({
    prompt = "Dictation…", rows = shown, compact = true, step = true, selected = selected,
    footer = { { key = "Left/Right", text = "change" }, { key = "Enter", text = "open ›" }, { key = "Esc", text = "close" } },
  }), function(message)
    local id = message.id or ""
    if message.type == "step" then
      if id:match(":sounds$") then
        save(dictation.setting(settings(), "sounds", dictation.sounds(settings()) and "off" or "on"))
        return showCard(2)
      end
      if id == "1:language" then return showLanguages() end
      return
    end
    if message.type ~= "choose" then return shell.close() end
    if id == "language" then return showLanguages() end
    if id == "sounds" then
      save(dictation.setting(settings(), "sounds", dictation.sounds(settings()) and "off" or "on"))
      return showCard(2)
    end
    if id == "key" then return end
    if id == "permissions" and lists.microphone == "granted" then return end
    if id == "install" and dictation.isInstalled(lists, locale()) then return end
    shell.close()
    if id == "last" then return feature.pasteLast() end
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
