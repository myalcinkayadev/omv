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

-- Mutes device; its level is saved only when it's muted by volume and nothing is saved yet,
-- so the first device's level isn't overwritten by a second one muted while muted.
local function muteDevice(device)
  local canMute = device:setInputMuted(true) == true
  local decision = micmute.muting({ canMute = canMute, volume = device:inputVolume() or 0 })
  if decision.mute then return end
  if not readSaved() then save({ uid = device:uid(), volume = decision.saved }) end
  device:setInputVolume(decision.volume)
end

-- Unmutes every muted input, and gives the one muted by volume its level back, whichever
-- is the default now. An input at 0 with nothing saved for it is left alone.
local function unmuteAll()
  local devices = {}
  for _, device in ipairs(hs.audiodevice.allInputDevices()) do
    devices[#devices + 1] = { uid = device:uid(), muted = device:inputMuted(), volume = device:inputVolume() or 0 }
  end
  local saved = readSaved()
  -- The default input muted by volume without a saved level still comes back, at 50%.
  local default = hs.audiodevice.defaultInputDevice()
  if not saved and default and default:inputMuted() == nil and (default:inputVolume() or 0) == 0 then
    saved = { uid = default:uid(), volume = 0 }
  end
  for _, step in ipairs(micmute.unmutingAll(devices, saved)) do
    local device = hs.audiodevice.findDeviceByUID(step.uid)
    if device and step.mute == false then device:setInputMuted(false) end
    if device and step.volume then device:setInputVolume(step.volume) end
  end
  os.remove(STATE_FILE)
end

local function onDeviceChange(event)
  if event ~= "dIn " or not muted then return end
  local device = hs.audiodevice.defaultInputDevice()
  if device then muteDevice(device) end
end

local function setMuted(value)
  muted = value
  if muted then audiowatch.watch("mic", onDeviceChange) else audiowatch.unwatch("mic") end
  drawBar()
end

function feature.toggle()
  local device = hs.audiodevice.defaultInputDevice()
  if not device then return shell.alert("No microphone", 1.2) end
  if muted then
    unmuteAll()
    setMuted(false)
    return shell.alert("Mic on", 1)
  end
  muteDevice(device)
  setMuted(true)
  shell.alert("Mic muted", 1)
end

-- After a reload the device may still be muted, so the bar shows it again.
local function readState()
  local device = hs.audiodevice.defaultInputDevice()
  if not device then return setMuted(false) end
  local saved = readSaved()
  local mine = saved and saved.uid == device:uid() and saved or nil
  setMuted(micmute.isMuted({ muted = device:inputMuted(), volume = device:inputVolume() or 0 }, mine))
end

readState()

return feature
