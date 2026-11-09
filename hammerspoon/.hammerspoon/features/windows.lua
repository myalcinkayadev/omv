-- Window summon (Option+Space): any window on any workspace.

local shell = require("shell")
local card = require("card")
local windows = require("windows")

local feature = {}

local function onWindowsMessage(message)
  if message.type ~= "choose" then return shell.close() end
  -- Leave focus to AeroSpace, rather than handing it back to the app open before.
  shell.leaveFocus()
  shell.close()
  shell.run(shell.AEROSPACE, { "focus", "--window-id", message.id })()
end

function feature.toggle()
  if shell.isOpen("windows") then return shell.close() end
  hs.task.new(shell.AEROSPACE, function(code, output)
    if code ~= 0 then return end
    local rows = windows.rows(output)
    shell.show("windows", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows)),
      card.html({ prompt = "Windows…", rows = rows, compact = true }), onWindowsMessage)
  end, { "list-windows", "--all", "--format", windows.FORMAT }):start()
end

return feature
