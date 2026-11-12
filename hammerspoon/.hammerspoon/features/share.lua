-- Share (Option+Shift+Q): sends the files selected in Finder with AirDrop, else a file or
-- image copied to the clipboard; see share.sh. The first time, macOS asks to let
-- Hammerspoon read Finder's selection.

local shell = require("shell")

local feature = {}

local SHARE = hs.configdir .. "/share.sh"

function feature.share()
  shell.close()
  -- macOS reports a cancelled AirDrop as shared, so success isn't announced: the AirDrop
  -- window shows whether it sent. Only a reason it couldn't open is.
  hs.task.new(SHARE, function(code, _, errors)
    if code == 0 then return end
    local reason = errors:gsub("%s+$", "")
    if reason ~= "" then shell.alert(reason, 2) end
  end):start()
end

return feature
