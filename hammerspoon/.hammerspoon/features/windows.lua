-- The palette (Option+Space): open windows on any workspace, installed apps, and every omv
-- command the key list can run, in one list filtered as you type. With the file-search flag
-- on, files matching what's typed follow, found by mdfind in the background.

local shell = require("shell")
local card = require("card")
local palette = require("palette")
local windows = require("windows")
local keys = require("features.keys")
local flags = require("flags")
local files = require("files")

local feature = {}

local OWN_KEY = "Option+Space"
-- Long enough for the palette to close, so a command that opens a card isn't closed with it.
local RUN_DELAY = 0.15
local MDFIND = "/usr/bin/mdfind"

-- Read once at load: a change to ~/.config/omv/flags takes a reload.
local fileSearch = flags.read(shell.readText(flags.PATH))["file-search"]
local search = nil

-- Stops the search still running, so typing fast leaves one mdfind at most.
local function stopSearch()
  if search and search:isRunning() then search:terminate() end
  search = nil
end

-- The page drops an answer for text that's no longer typed; a closed palette gets none.
local function findFiles(text)
  stopSearch()
  local arguments = files.arguments(text, shell.HOME)
  if not arguments then return end
  local task
  task = hs.task.new(MDFIND, function(code, output)
    if search == task then search = nil end
    if code ~= 0 or not shell.isOpen("windows") then return end
    shell.view():evaluateJavaScript(card.filesCall(text, files.rows(output, shell.HOME)))
  end, arguments)
  search = task
  task:start()
end

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
  if message.type == "files" then return findFiles(message.id) end
  stopSearch()
  if message.type ~= "choose" then return shell.close() end
  local kind, value = palette.parse(message.id)
  if kind == "window" then
    -- Leave focus to AeroSpace, rather than handing it back to the app open before.
    shell.leaveFocus()
    shell.close()
    return shell.run(shell.AEROSPACE, { "focus", "--window-id", value })()
  end
  if kind == "calc" then
    hs.pasteboard.setContents(value)
    shell.close()
    return shell.alert("Copied " .. value, 1)
  end
  if kind == "file" then
    shell.close()
    return shell.open({ value })()
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
      card.html({ prompt = "Windows, apps, commands…", rows = rows, compact = true, calc = true, files = fileSearch }), onPaletteMessage)
  end, { "list-windows", "--all", "--format", windows.FORMAT }):start()
end

return feature
