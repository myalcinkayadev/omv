-- Mic mute (Option+M, or a click on the bar's red mic): mutes the default input from any app.
-- micmute.lua decides how: a device that can mute is muted, one that can't is set to volume
-- 0 and its level saved in ~/.local/state/omv/mic. While muted, a new default input, such as
-- AirPods connecting, is muted too. The state is read back on load, so a reload keeps the bar right.

local shell = require("shell")
local micmute = require("micmute")
local audiowatch = require("features.audiowatch")

local feature = {}

local STATE_FILE = shell.STATE_DIR .. "/mic"
local muted = false

local function drawBar()
  local arguments = { "--set", "mic_muted" }
  for _, property in ipairs(micmute.barProperties(muted)) do arguments[#arguments + 1] = property end
  hs.task.new(shell.SKETCHYBAR, nil, arguments):start()
end

local function readSaved()
  return micmute.decode(shell.readText(STATE_FILE))
end

local function save(state)
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
  local file = io.open(STATE_FILE, "w")
  if not file then return end
  file:write(micmute.encode(state))
  file:close()
end

local function reading(device)
  return { uid = device:uid(), muted = device:inputMuted(), volume = device:inputVolume() }
end

local function inputs()
  local devices = {}
  for _, device in ipairs(hs.audiodevice.allInputDevices()) do
    local found = reading(device)
    found.volume = found.volume or 0
    devices[#devices + 1] = found
  end
  return devices
end

local function apply(step)
  local device = hs.audiodevice.findDeviceByUID(step.uid)
  if not device then return end
  if step.mute == false then device:setInputMuted(false) end
  if step.volume then device:setInputVolume(step.volume) end
end

-- Mutes device, and says whether it took. Its level is saved only when it's muted by volume
-- and nothing is saved yet, so the first device's level isn't overwritten.
local function muteDevice(device)
  local canMute = device:setInputMuted(true) == true
  local decision = micmute.muting({ canMute = canMute, volume = device:inputVolume() or 0 })
  if not decision.mute then
    if not readSaved() then save({ uid = device:uid(), volume = decision.saved }) end
    device:setInputVolume(decision.volume)
  end
  return micmute.worked(reading(device))
end

-- Unmutes every muted input, gives the one muted by volume its level back, and the default
-- input 50% when it was muted by volume without a level saved. A level whose mic isn't
-- connected is kept, and restored when it's back.
local function unmuteAll()
  local default = hs.audiodevice.defaultInputDevice()
  local steps, keep = micmute.unmutingAll(inputs(), readSaved(), default and default:uid())
  for _, step in ipairs(steps) do apply(step) end
  if not keep then os.remove(STATE_FILE) end
end

local function restoreReturning()
  local step, drop = micmute.restoreSaved(inputs(), readSaved())
  if step then apply(step) end
  if drop then os.remove(STATE_FILE) end
end

local function setMuted(value)
  muted = value
  drawBar()
end

-- A mic that can neither mute nor go to 0 stays live, so the bar says so rather than lie.
local function cantMute(device)
  unmuteAll()
  setMuted(false)
  shell.alert("Can't mute " .. device:name() .. ": the mic is on", 2)
end

local function onDeviceChange(event)
  if not muted then return restoreReturning() end
  if event ~= "dIn " then return end
  local device = hs.audiodevice.defaultInputDevice()
  if device and not muteDevice(device) then cantMute(device) end
end

function feature.toggle()
  if muted then
    unmuteAll()
    setMuted(false)
    return shell.alert("Mic on", 1)
  end
  local device = hs.audiodevice.defaultInputDevice()
  if not device then return shell.alert("No microphone", 1.2) end
  if not muteDevice(device) then return cantMute(device) end
  setMuted(true)
  shell.alert("Mic muted", 1)
end

-- SketchyBar starts its items hidden, so a restart while muted draws the red mic again.
feature.redrawBar = drawBar

-- After a reload the device may still be muted, so the bar shows it again; a mic whose
-- level was kept gets it back if it's connected now.
local function readState()
  local device = hs.audiodevice.defaultInputDevice()
  local saved = readSaved()
  local mine = device and saved and saved.uid == device:uid() and saved or nil
  setMuted(device ~= nil and micmute.isMuted({ muted = device:inputMuted(), volume = device:inputVolume() or 0 }, mine))
  if not muted then restoreReturning() end
end

audiowatch.watch("mic", onDeviceChange)
readState()

return feature
