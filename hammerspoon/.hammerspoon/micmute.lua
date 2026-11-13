-- Mic mute (Option+M): how to mute and unmute the default input, whether it counts as muted
-- after a reload, and the bar item. A device that can mute is muted; one that can't is set
-- to volume 0, and the level it had is saved to restore on unmute.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local micmute = {}

-- The level an input gets back when the one it had wasn't saved, so unmuting never leaves it at 0.
micmute.RESTORE_VOLUME = 50

-- device = { canMute, volume }
function micmute.muting(device)
  if device.canMute then return { mute = true } end
  return { volume = 0, saved = device.volume }
end

-- saved is the level muting by volume kept, or nil.
function micmute.unmuting(device, saved)
  if device.canMute then return { mute = false } end
  return { volume = (saved and saved > 0) and saved or micmute.RESTORE_VOLUME }
end

-- device = { muted, volume }, where muted is nil for a device that can't mute. A device at 0
-- with a saved level was muted by volume before a reload.
function micmute.isMuted(device, savedState)
  if device.muted then return true end
  return savedState ~= nil and device.volume == 0
end

-- The saved state is one line: the device's uid, then the level to restore.
function micmute.encode(state)
  return state.uid .. "\t" .. state.volume .. "\n"
end

function micmute.decode(text)
  local uid, volume = tostring(text or ""):match("^([^\t\n]+)\t([%d.]+)")
  if not uid then return nil end
  return { uid = uid, volume = tonumber(volume) }
end

function micmute.barProperties(muted)
  return { muted and "drawing=on" or "drawing=off" }
end

return micmute
