-- The palette (Option+Space): open windows on any workspace, installed apps, and every omv
-- command the key list can run, in one list filtered as you type.

local shell = require("shell")
local card = require("card")
local palette = require("palette")
local windows = require("windows")
local keys = require("features.keys")

local feature = {}

local OWN_KEY = "Option+Space"
-- Long enough for the palette to close, so a command that opens a card isn't closed with it.
local RUN_DELAY = 0.15

local function installedApps()
  local apps = {}
  for _, folder in ipairs(palette.APP_FOLDERS) do
    local ok, files, state = pcall(hs.fs.dir, folder)
    for file in (ok and files) and files or function() end, state do
      local name = palette.appName(file)
      if name then apps[#apps + 1] = { name = name, path = folder .. "/" .. file } end
    end
  end
  local home = shell.HOME .. "/Applications"
  local ok, files, state = pcall(hs.fs.dir, home)
  for file in (ok and files) and files or function() end, state do
    local name = palette.appName(file)
    if name then apps[#apps + 1] = { name = name, path = home .. "/" .. file } end
  end
  return apps
end

local function onPaletteMessage(message)
  if message.type ~= "choose" then return shell.close() end
  local kind, value = palette.parse(message.id)
  if kind == "window" then
    -- Leave focus to AeroSpace, rather than handing it back to the app open before.
    shell.leaveFocus()
    shell.close()
    return shell.run(shell.AEROSPACE, { "focus", "--window-id", value })()
  end
  if kind == "app" then
    shell.leaveFocus()
    shell.close()
    return shell.open({ value })()
  end
  shell.close()
  local launcher = kind == "command" and keys.launchers[value]
  if launcher and launcher.runs then hs.timer.doAfter(RUN_DELAY, launcher.run) end
end

function feature.toggle()
  if shell.isOpen("windows") then return shell.close() end
  hs.task.new(shell.AEROSPACE, function(code, output)
    local rows = palette.rows(code == 0 and output or "", installedApps(), keys.launchers, OWN_KEY)
    shell.show("windows", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows)),
      card.html({ prompt = "Windows, apps, commands…", rows = rows, compact = true }), onPaletteMessage)
  end, { "list-windows", "--all", "--format", windows.FORMAT }):start()
end

return feature
