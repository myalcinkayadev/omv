-- Camera and mic in-use dots: which dot shows, and what the bar is sent when one changes.
-- Has no Hammerspoon dependency, so the Lua tests can run it.

local inuse = {}

local ITEMS = { camera = "camera_in_use", mic = "mic_in_use" }
local ORDER = { "camera", "mic" }

-- readings holds each device's answer; a device that can't be read answers nil, which
-- counts as not in use, so an error never lights a dot.
local function anyInUse(readings)
  for _, reading in pairs(readings or {}) do
    if reading == true then return true end
  end
  return false
end

-- ownMic is true while omv's own meter or dictation listens: the mic they open isn't
-- another app's, so it doesn't light the dot.
function inuse.state(cameras, inputs, ownMic)
  return { camera = anyInUse(cameras), mic = not ownMic and anyInUse(inputs) }
end

-- The sketchybar arguments that bring the bar from shown to now, or nil when nothing
-- changed. shown is nil when nothing has been drawn yet, such as after the bar restarts.
function inuse.barArguments(shown, now)
  local arguments = {}
  for _, name in ipairs(ORDER) do
    if not shown or shown[name] ~= now[name] then
      arguments[#arguments + 1] = "--set"
      arguments[#arguments + 1] = ITEMS[name]
      arguments[#arguments + 1] = "drawing=" .. (now[name] and "on" or "off")
    end
  end
  if #arguments == 0 then return nil end
  return arguments
end

return inuse
