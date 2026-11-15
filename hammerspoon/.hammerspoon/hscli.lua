-- Where Hammerspoon installs its hs command, which the bar's clicks, the Bluetooth icon and
-- doctor.sh use to talk to it. Homebrew's folder on Apple Silicon is on PATH there; elsewhere
-- /usr/local is.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local hscli = {}

function hscli.prefix(homebrewExists)
  return homebrewExists and "/opt/homebrew" or "/usr/local"
end

-- Whether to install hs, from hs.ipc.cliStatus (true, false or "broken") and whether
-- <prefix>/bin/hs leads to a real file. "broken" also means only the man page link is
-- missing, as when hs was linked by hand, and that hs works; a link that leads nowhere,
-- as after Hammerspoon.app moved, is installed again.
function hscli.needsInstall(status, commandWorks)
  if status == false then return true end
  return status == "broken" and not commandWorks
end

return hscli
