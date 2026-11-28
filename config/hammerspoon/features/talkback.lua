-- Talk-back: when a Claude session finishes, the start of its last message is spoken, with a
-- pill showing it as it's spoken. Only into headphones unless ~/.config/omv/dictation says
-- talk-back output = anywhere; never during a meeting or while you dictate, and not for the
-- terminal you're looking at. A press of Right Option or Right Command stops it, so you can
-- answer at once. Off unless turned on with omv flags talk-back on; claude-waiting.sh keeps the
-- message only while the flag is on.
-- The voice is Apple's own, or Kokoro once installed (talk-back voice = kokoro-woman or
-- kokoro-man), run by speak.sh and kept loaded while in use. Kokoro doesn't speak Turkish, and
-- any line it can't speak in time is spoken by Apple's voice instead, so none is lost.

local shell = require("shell")
local talkback = require("talkback")
local claudewait = require("claudewait")
local dictation = require("dictation")
local sound = require("sound")
local quiet = require("quiet")
local dictationPill = require("dictationpill")
local waiting = require("features.waiting")

local feature = {}

-- reply goes to the session spoken last for this long after.
local SPOKE_SECONDS = 120
-- The pill stays this long after the voice ends, to finish reading it.
local LINGER_SECONDS = 1.5
local SPEAK = hs.configdir .. "/speak.sh"
local INSTALL = hs.configdir .. "/voice-install.sh"
local READY = shell.HOME .. "/.local/share/omv/voice/ready"
-- How long Kokoro gets for a line before Apple's voice speaks it: the first one also loads it.
local KOKORO_SECONDS = 8
-- Kokoro is stopped after this long unused, giving back its memory.
local IDLE_SECONDS = 600

-- Finishes waiting their turn, each { tty, project, line }; the one speaking now.
local queue, speaking = {}, nil
local spokeTty, spokeAt = nil, 0
-- Kept on the feature, so the voices, the sound and the timers aren't garbage-collected.
feature.voice, feature.sound, feature.linger, feature.idle = nil, nil, nil, nil
-- Whether you're dictating, from features/dictation.lua through init.lua.
local recording = function() return false end
-- Kokoro's helper while it runs: { task, own, buffer, pending }; pending are the lines asked
-- for, oldest first, each { done, timer }.
local helper = nil
local installing = false

local function settings()
  return shell.readText(dictation.PATH)
end

function feature.installed()
  return hs.fs.attributes(READY) ~= nil
end

local function headphones()
  local device = hs.audiodevice.defaultOutputDevice()
  return device ~= nil and sound.isHeadphones({ name = device:name(), transport = device:transportType() })
end

-- A Turkish voice for Turkish text, when the Mac has one; the system's own otherwise.
local function appleVoiceFor(line)
  if talkback.voice(line) ~= "tr" then return nil end
  for _, voice in ipairs(hs.speech.availableVoices()) do
    if voice:find("tr-TR", 1, true) then return voice end
  end
  return nil
end

local speakNext

local function ended(item)
  if speaking ~= item then return end
  if item.preview then
    speaking = nil
    return speakNext()
  end
  feature.linger = hs.timer.doAfter(LINGER_SECONDS, function()
    if speaking ~= item then return end
    speaking = nil
    dictationPill.hide()
    speakNext()
  end)
end

local function speakWithApple(item)
  local voice = appleVoiceFor(item.line)
  -- hs.speech.new takes no nil: without a voice it's called with none, for the system's own.
  feature.voice = voice and hs.speech.new(voice) or hs.speech.new()
  if not feature.voice then return ended(item) end
  feature.voice:setCallback(function(_, kind)
    if kind == "didFinish" then ended(item) end
  end)
  feature.voice:speak(item.line)
end

local function stopHelper()
  if not helper then return end
  local was = helper
  helper = nil
  for _, request in ipairs(was.pending) do
    if request.timer then request.timer:stop() end
    request.done(nil)
  end
  if was.task:isRunning() then
    was.task:setInput("quit\n")
    was.task:closeInput()
  end
end

-- The helper's lines: an audio path or a problem answers the oldest line asked for.
local function onHelperOutput(chunk)
  helper.buffer = helper.buffer .. (chunk or "")
  for line in helper.buffer:gmatch("([^\n]*)\n") do
    local kind, value = line:match("^(%a+)\t(.*)$")
    if kind == "audio" or kind == "problem" then
      local request = table.remove(helper.pending, 1)
      if request then
        if request.timer then request.timer:stop() end
        request.done(kind == "audio" and value or nil)
      end
    end
  end
  helper.buffer = helper.buffer:match("([^\n]*)$")
end

local function startHelper()
  -- Which helper is the current one, by a token: naming the task in its own callbacks would
  -- hold it forever.
  local own = {}
  helper = { own = own, buffer = "", pending = {} }
  local task = hs.task.new(SPEAK, function()
    if helper and helper.own == own then stopHelper() end
  end, function(_, out)
    if helper and helper.own == own then onHelperOutput(out) end
    return true
  end, { "serve" })
  helper.task = task
  if not task:start() then helper = nil end
end

-- Asks Kokoro for line in voice; done gets the wav's path, or nil when it can't in time.
local function speakWithKokoro(voice, line, done)
  if not helper then startHelper() end
  if not helper then return done(nil) end
  local request = { done = done }
  request.timer = hs.timer.doAfter(KOKORO_SECONDS, function()
    for index, waitingRequest in ipairs(helper and helper.pending or {}) do
      if waitingRequest == request then
        -- Kept as answered, so its late audio is dropped in order.
        helper.pending[index] = { done = function() end }
        return done(nil)
      end
    end
  end)
  helper.pending[#helper.pending + 1] = request
  helper.task:setInput("say\t" .. voice .. "\t" .. line:gsub("[\t\n\r]", " ") .. "\n")
  if feature.idle then feature.idle:stop() end
  feature.idle = hs.timer.doAfter(IDLE_SECONDS, stopHelper)
end

local function play(item, path)
  feature.sound = path and hs.sound.getByFile(path)
  if not feature.sound then return false end
  feature.sound:setCallback(function() ended(item) end)
  feature.sound:play()
  return true
end

local function speakItem(item, engine)
  speaking = item
  if not item.preview then dictationPill.speaking(item) end
  if engine.engine ~= "kokoro" then return speakWithApple(item) end
  speakWithKokoro(engine.voice, item.line, function(path)
    if speaking ~= item then return end
    if not play(item, path) then speakWithApple(item) end
  end)
end

speakNext = function()
  if speaking or #queue == 0 then return end
  local item = table.remove(queue, 1)
  spokeTty, spokeAt = item.tty, os.time()
  speakItem(item, talkback.engineFor(talkback.voiceSetting(settings()), item.line, feature.installed()))
end

local function silence()
  speaking = nil
  if feature.linger then feature.linger:stop() end
  if feature.voice then feature.voice:stop() end
  if feature.sound then feature.sound:stop() end
end

-- Stops speaking and forgets the finishes waiting, as you press a key to talk.
function feature.stop()
  queue = {}
  if not speaking then return end
  local wasPreview = speaking.preview
  silence()
  if not wasPreview then dictationPill.hide() end
end

-- Plays the sample line in setting's voice, cutting off the one before; for the card.
function feature.preview(setting)
  local engine = talkback.previewFor(setting, feature.installed())
  if speaking then silence() end
  if not engine then return end
  speakItem({ line = engine.line, preview = true }, engine)
end

-- Installs Kokoro in the background, about 1.5 GB; afterwards done runs, and the sample line
-- plays in the chosen voice.
function feature.install(done)
  if installing then return end
  installing = true
  shell.alert("Getting Kokoro for talk-back… (~1.5 GB)", 3)
  hs.task.new(INSTALL, function(code)
    installing = false
    if code ~= 0 then return shell.alert("Couldn't get Kokoro: try omv voice install in a terminal", 3) end
    shell.alert("Kokoro is ready for talk-back", 2)
    feature.preview(talkback.voiceSetting(settings()))
    if done then done() end
  end, { "install" }):start()
end

function feature.isInstalling()
  return installing
end

-- The tty of the session spoken last, for a while after, for "reply".
function feature.spoke()
  if spokeTty and os.time() - spokeAt <= SPOKE_SECONDS then return spokeTty end
  return nil
end

-- isRecording() tells whether a dictation runs now.
function feature.whileRecording(isRecording)
  recording = isRecording
end

local function onChange(before, after)
  local output = talkback.outputSetting(settings())
  for _, session in ipairs(talkback.newlyDone(before, after)) do
    local due = talkback.due({ flag = true, quiet = quiet.active, headphones = headphones(), output = output,
      recording = recording(), tty = session.tty, viewedTty = waiting.viewedTty() })
    local line = due and talkback.line(shell.readText(claudewait.STATE_DIR .. "/.last-" .. session.id))
    if line then queue[#queue + 1] = { tty = session.tty, project = session.folder, line = line } end
  end
  speakNext()
end

waiting.onChange(onChange)

return feature
