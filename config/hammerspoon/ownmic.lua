-- omv's own mic users, the Sound card's meter and dictation, say here when they start and
-- stop listening, so the mic in-use dot can tell their use from another app's. Shared by
-- require; onChange, set by the in-use feature, hears each change. Has no Hammerspoon
-- dependency, so the Lua tests can run it.

local ownmic = { onChange = nil }

local listening = {}

function ownmic.set(name, on)
  local value = on and true or nil
  if listening[name] == value then return end
  listening[name] = value
  if ownmic.onChange then ownmic.onChange() end
end

function ownmic.any()
  return next(listening) ~= nil
end

return ownmic
