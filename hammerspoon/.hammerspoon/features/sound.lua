-- Sound card (click the volume icon, Option+Shift+V, or Sound in the system menu).
-- While it is open, meter.sh runs a helper that writes the mic's level to a file. The card
-- reads it ten times a second, and touches an .alive file the helper watches, so the
-- helper stops by itself if this config is reloaded or stops reading.

local shell = require("shell")
local sound = require("sound")

local feature = {}

local METER = hs.configdir .. "/meter.sh"
local METER_FILE = shell.HOME .. "/.cache/omv/meter-level"
local METER_ALIVE = METER_FILE .. ".alive"
local METER_SECONDS = 0.1
-- How long to wait for the helper's first answer before letting a click elsewhere close
-- the card again, in case the helper never starts.
local METER_ANSWER_SECONDS = 10
local meterTimer = nil
local meterAnswerTimer = nil
-- Bumped by every start and stop, so a start still waiting on an earlier stop gives up.
local meterGeneration = 0
-- Whether the helper has answered since it started: a level, "denied" or "none". Until
-- then the card may be under macOS's microphone prompt, so losing focus must not close it.
local meterAnswered = false

local function touchMeterAlive()
  local file = io.open(METER_ALIVE, "w")
  if file then file:close() end
end

local function meterHasAnswered()
  if meterAnswered then return end
  meterAnswered = true
  if meterAnswerTimer then meterAnswerTimer:stop() end
  meterAnswerTimer = nil
  if shell.isOpen("sound") then shell.keepOnBlur(false) end
end

local function readMeter()
  touchMeterAlive()
  local file = io.open(METER_FILE, "r")
  if not file then return end
  local line = file:read("*l")
  file:close()
  if not line then return end
  meterHasAnswered()
  local level = tonumber(line)
  if level and shell.isOpen("sound") then shell.view():evaluateJavaScript("omvLevel(" .. level .. ")") end
end

local function stopMeterTimers()
  if meterTimer then meterTimer:stop() end
  if meterAnswerTimer then meterAnswerTimer:stop() end
  meterTimer, meterAnswerTimer = nil, nil
end

local function stopMeter()
  meterGeneration = meterGeneration + 1
  stopMeterTimers()
  os.remove(METER_ALIVE)
  hs.task.new(METER, nil, { "stop" }):start()
end

local function launchMeter(generation)
  os.execute("/bin/mkdir -p '" .. shell.HOME .. "/.cache/omv'")
  os.remove(METER_FILE)
  touchMeterAlive()
  hs.task.new(METER, function(code)
    -- The helper couldn't be built or started: it will never answer.
    if code ~= 0 and generation == meterGeneration then meterHasAnswered() end
  end, { "start", METER_FILE }):start()
  meterTimer = hs.timer.doEvery(METER_SECONDS, readMeter)
  meterAnswerTimer = hs.timer.doAfter(METER_ANSWER_SECONDS, meterHasAnswered)
end

-- Stops any helper first and starts the new one once it has gone, so the two never
-- overlap. The helper listens to the input that was default when it started, so picking
-- a new input starts it again this way too.
local function startMeter()
  meterGeneration = meterGeneration + 1
  local generation = meterGeneration
  stopMeterTimers()
  meterAnswered = false
  hs.task.new(METER, function()
    if generation == meterGeneration and shell.isOpen("sound") then launchMeter(generation) end
  end, { "stop" }):start()
end

local function deviceList(devices, current)
  local currentUid = current and current:uid()
  local result = {}
  for _, device in ipairs(devices) do
    result[#result + 1] = { uid = device:uid(), name = device:name(), transport = device:transportType(), current = device:uid() == currentUid }
  end
  return result
end

-- A device that takes no volume reports nil, which the card shows as a dash.
local function soundState()
  local output, input = hs.audiodevice.defaultOutputDevice(), hs.audiodevice.defaultInputDevice()
  return {
    outputs = deviceList(hs.audiodevice.allOutputDevices(), output),
    inputs = deviceList(hs.audiodevice.allInputDevices(), input),
    outputVolume = output and output:outputVolume() or false,
    inputVolume = input and input:inputVolume() or false,
    muted = output and output:outputMuted() or false,
  }
end

local function redrawVolumeBar()
  local output = hs.audiodevice.defaultOutputDevice()
  local level = output and output:outputVolume()
  hs.task.new(shell.SKETCHYBAR, nil, { "--trigger", "volume_change", "INFO=" .. (level and math.floor(level + 0.5) or "") }):start()
end

local onSoundMessage

local function showSound()
  local state = soundState()
  shell.show("sound", shell.anchored(sound.WIDTH, sound.height(state)), sound.html(state), onSoundMessage,
    { keepOnBlur = not meterAnswered, onClose = stopMeter })
end

onSoundMessage = function(message)
  if message.type == "close" then return shell.close() end
  local output, input = hs.audiodevice.defaultOutputDevice(), hs.audiodevice.defaultInputDevice()
  local level = tonumber(message.id)
  -- The page already shows a new volume, so only the bar is redrawn.
  if message.type == "volume" and output and level then
    output:setOutputVolume(level)
    return redrawVolumeBar()
  end
  if message.type == "inputVolume" and input and level then
    input:setInputVolume(level)
    return
  end
  if message.type == "mute" and output then output:setOutputMuted(not output:outputMuted()) end
  local device = (message.type == "output" or message.type == "input") and hs.audiodevice.findDeviceByUID(message.id)
  if device and message.type == "output" then device:setDefaultOutputDevice() end
  if device and message.type == "input" then
    device:setDefaultInputDevice()
    startMeter()
  end
  showSound()
  redrawVolumeBar()
end

-- The meter starts first, so the card opens knowing the helper hasn't answered yet.
function feature.open()
  startMeter()
  showSound()
end

function feature.toggle()
  if shell.isOpen("sound") then return shell.close() end
  feature.open()
end

-- A helper left running by an earlier load of this config.
hs.task.new(METER, nil, { "stop" }):start()

return feature
