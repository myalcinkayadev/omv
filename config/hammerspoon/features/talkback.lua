-- Talk-back: when a Claude session finishes, the start of its last message is spoken in your
-- headphones, with a pill showing it as it's spoken. Never to the room, never during a meeting
-- or while you dictate, and not for the terminal you're looking at. A press of Right Option
-- or Right Command stops it, so you can answer at once. Off unless turned on with omv flags
-- talk-back on; claude-waiting.sh keeps the message only while the flag is on.

local shell = require("shell")
local talkback = require("talkback")
local claudewait = require("claudewait")
local sound = require("sound")
local quiet = require("quiet")
local dictationPill = require("dictationpill")
local waiting = require("features.waiting")

local feature = {}

-- reply goes to the session spoken last for this long after.
local SPOKE_SECONDS = 120
-- The pill stays this long after the voice ends, to finish reading it.
local LINGER_SECONDS = 1.5

-- Finishes waiting their turn, each { tty, project, line }; the one speaking now.
local queue, speaking = {}, nil
local spokeTty, spokeAt = nil, 0
-- Kept on the feature, so the voice and the timer aren't garbage-collected while they run.
feature.voice, feature.linger = nil, nil
-- Whether you're dictating, from features/dictation.lua through init.lua.
local recording = function() return false end

local function headphones()
  local device = hs.audiodevice.defaultOutputDevice()
  return device ~= nil and sound.isHeadphones({ name = device:name(), transport = device:transportType() })
end

-- A Turkish voice for Turkish text, when the Mac has one; the system's own otherwise.
local function voiceFor(line)
  if talkback.voice(line) ~= "tr" then return nil end
  for _, voice in ipairs(hs.speech.availableVoices()) do
    if voice:find("tr-TR", 1, true) then return voice end
  end
  return nil
end

local speakNext

local function ended(item)
  if speaking ~= item then return end
  feature.linger = hs.timer.doAfter(LINGER_SECONDS, function()
    if speaking ~= item then return end
    speaking = nil
    dictationPill.hide()
    speakNext()
  end)
end

speakNext = function()
  if speaking or #queue == 0 then return end
  local item = table.remove(queue, 1)
  speaking, spokeTty, spokeAt = item, item.tty, os.time()
  dictationPill.speaking(item)
  local voice = voiceFor(item.line)
  -- hs.speech.new takes no nil: without a voice it's called with none, for the system's own.
  feature.voice = voice and hs.speech.new(voice) or hs.speech.new()
  if not feature.voice then return ended(item) end
  feature.voice:setCallback(function(_, kind)
    if kind == "didFinish" then ended(item) end
  end)
  feature.voice:speak(item.line)
end

-- Stops speaking and forgets the finishes waiting, as you press a key to talk.
function feature.stop()
  queue = {}
  if not speaking then return end
  speaking = nil
  if feature.linger then feature.linger:stop() end
  if feature.voice then feature.voice:stop() end
  dictationPill.hide()
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
  for _, session in ipairs(talkback.newlyDone(before, after)) do
    local due = talkback.due({ flag = true, quiet = quiet.active, headphones = headphones(), recording = recording(),
      tty = session.tty, viewedTty = waiting.viewedTty() })
    local line = due and talkback.line(shell.readText(claudewait.STATE_DIR .. "/.last-" .. session.id))
    if line then queue[#queue + 1] = { tty = session.tty, project = session.folder, line = line } end
  end
  speakNext()
end

waiting.onChange(onChange)

return feature
