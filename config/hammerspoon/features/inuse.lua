-- Camera and mic in-use dots: a green camera in the bar while any camera is in use, an
-- orange mic while any audio input runs. Driven by macOS's own device events, with no timer
-- and no helper: each camera and input device says when its use changes, and the bar is
-- sent only a dot that changed. The mic omv itself opens, for the Sound card's meter or
-- dictation, doesn't light the dot. Off unless turned on with omv flags in-use on.

local shell = require("shell")
local inuse = require("inuse")
local ownmic = require("ownmic")
local audiowatch = require("features.audiowatch")

-- The watched cameras and input devices are kept here, so they aren't garbage-collected.
local feature = { cameras = {}, inputs = {} }

-- How long the mic stays ignored after omv's own use ends: the meter's helper is stopped
-- with pkill and lets the mic go a moment later, which would otherwise flash the dot.
local SETTLE_SECONDS = 1.5

-- What the bar shows, { camera, mic }; nil until it's first drawn.
local shown = nil
local settling = false

-- Each device's answer; one that can't answer gives false, so the list has no holes.
local function readings(devices, isInUse)
  local found = {}
  for index, device in ipairs(devices) do found[index] = isInUse(device) == true end
  return found
end

local function cameraInUse(camera) return camera:isInUse() end
local function inputInUse(device) return device:inUse() end

local function draw(previous)
  local now = inuse.state(readings(feature.cameras, cameraInUse), readings(feature.inputs, inputInUse), ownmic.any() or settling)
  local arguments = inuse.barArguments(previous, now)
  shown = now
  if arguments then hs.task.new(shell.SKETCHYBAR, nil, arguments):start() end
end

local function refresh() draw(shown) end

feature.settle = hs.timer.delayed.new(SETTLE_SECONDS, function()
  settling = false
  refresh()
end)

-- The callbacks name no camera or device, so none of them keeps one alive.
local function watchCameras()
  for _, camera in ipairs(feature.cameras) do camera:stopPropertyWatcher() end
  feature.cameras = hs.camera.allCameras()
  for _, camera in ipairs(feature.cameras) do camera:setPropertyWatcherCallback(refresh):startPropertyWatcher() end
end

-- "gone" is the event for a change in whether the device is in use.
local function onInputEvent(_, event)
  if event == "gone" then refresh() end
end

local function watchInputs()
  for _, device in ipairs(feature.inputs) do device:watcherStop() end
  feature.inputs = hs.audiodevice.allInputDevices()
  for _, device in ipairs(feature.inputs) do device:watcherCallback(onInputEvent):watcherStart() end
end

-- "dev#" is the event for a device added or removed.
local function onAudioEvent(event)
  if event ~= "dev#" then return end
  watchInputs()
  refresh()
end

local function onCameraAddedOrRemoved()
  watchCameras()
  refresh()
end

local function onOwnMicChange()
  if ownmic.any() then
    settling = false
    feature.settle:stop()
    return refresh()
  end
  settling = true
  feature.settle:start()
end

-- SketchyBar starts its items hidden, so a restart draws both dots again.
function feature.redrawBar() draw(nil) end

ownmic.onChange = onOwnMicChange
watchCameras()
hs.camera.setWatcherCallback(onCameraAddedOrRemoved)
hs.camera.startWatcher()
watchInputs()
audiowatch.watch("inuse", onAudioEvent)
feature.redrawBar()

return feature
