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

-- What unmuting does across every input, as { { uid, mute = false } | { uid, volume } }, and
-- whether to keep the saved level: each muted input is unmuted, since one muted while
-- switching mics would otherwise stay silent with nothing in the bar; the input muted by
-- volume gets its saved level back; and the default input, at 0 with no level saved for it,
-- gets 50%. A saved level whose mic isn't connected is kept for when it's back.
-- devices = { { uid, muted, volume } }, saved = { uid, volume } or nil, defaultUid = string or nil.
function micmute.unmutingAll(devices, saved, defaultUid)
  local steps, found = {}, false
  for _, device in ipairs(devices) do
    local isSaved = saved ~= nil and saved.uid == device.uid
    found = found or isSaved
    if device.muted then
      steps[#steps + 1] = { uid = device.uid, mute = false }
    elseif isSaved then
      steps[#steps + 1] = { uid = device.uid, volume = micmute.unmuting({ canMute = false }, saved.volume).volume }
    elseif device.uid == defaultUid and device.muted == nil and device.volume == 0 then
      steps[#steps + 1] = { uid = device.uid, volume = micmute.RESTORE_VOLUME }
    end
  end
  return steps, saved ~= nil and not found
end

-- When a mic whose level was kept comes back: the step that restores it, or nil; and whether
-- to drop the saved level. A mic back at another level than 0 was changed since, so its
-- level stays and the saved one goes.
function micmute.restoreSaved(devices, saved)
  if not saved then return nil, false end
  for _, device in ipairs(devices) do
    if device.uid == saved.uid then
      if device.volume == 0 then return { uid = device.uid, volume = micmute.unmuting({ canMute = false }, saved.volume).volume }, true end
      return nil, true
    end
  end
  return nil, false
end

-- Whether muting took: the device reads muted, or its volume is 0. A mic that can do
-- neither stays live, so it must not be shown as muted.
function micmute.worked(device)
  return device.muted == true or device.volume == 0
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
