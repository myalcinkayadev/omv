-- Night light: macOS's Night Shift, read and switched with the nightlight CLI, since macOS
-- has no public API for it. Has no Hammerspoon dependency, so the Lua tests can run it.

local nightshift = {}

-- `nightlight status` prints "on until sunrise" or "off until sunset"; anything else is off.
function nightshift.isOn(status)
  return (status or ""):match("^%s*on%f[%W]") ~= nil
end

-- The nightlight argument that switches from status to the other state.
function nightshift.switch(status)
  return nightshift.isOn(status) and "off" or "on"
end

return nightshift
