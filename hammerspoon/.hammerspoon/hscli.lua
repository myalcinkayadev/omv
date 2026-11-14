-- Where Hammerspoon installs its hs command, which the bar's clicks, the Bluetooth icon and
-- doctor.sh use to talk to it. Homebrew's folder on Apple Silicon is on PATH there; elsewhere
-- /usr/local is.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local hscli = {}

function hscli.prefix(homebrewExists)
  return homebrewExists and "/opt/homebrew" or "/usr/local"
end

return hscli
