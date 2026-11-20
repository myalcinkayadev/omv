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
local rates = require("rates")

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

-- A file's change time, for ranking the newest first; nil when it can't be read.
local function modified(path)
  return hs.fs.attributes(path, "modification")
end

-- Currency rates, asked for by the page once per opening, when a currency conversion is
-- typed. Saved ones under 4 hours old go at once; otherwise Frankfurter is asked, and the
-- saved ones, if any, still go when it fails, their date shown beside the result.
local RATES_PATH = rates.path(shell.HOME)

local function sendRates(saved)
  if saved and shell.isOpen("windows") then
    shell.view():evaluateJavaScript("omvSetRates(" .. hs.json.encode(saved) .. ")")
  end
end

local function giveRates()
  local ok, saved = pcall(hs.json.read, RATES_PATH)
  saved = ok and saved or nil
  if not rates.stale(saved, os.time()) then return sendRates(saved) end
  hs.http.asyncGet(rates.URL, nil, function(status, body)
    local readable, answer = pcall(hs.json.decode, status == 200 and body or "")
    local kept = rates.after(saved, readable and answer or nil, os.time())
    if kept ~= saved then
      os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
      hs.json.write(kept, RATES_PATH, false, true)
    end
    sendRates(kept)
  end)
end

local function answer(text, rows)
  if shell.isOpen("windows") then shell.view():evaluateJavaScript(card.filesCall(text, rows)) end
end

-- Every request gets an answer, empty when there's nothing to search for or mdfind fails,
-- since the page holds "No matches" until it has one. A search stopped for newer text
-- isn't answered: the newer one will be. The page drops an answer for text no longer typed.
local function findFiles(text)
  stopSearch()
  local arguments = files.arguments(text, shell.HOME)
  if not arguments then return answer(text, {}) end
  local task
  task = hs.task.new(MDFIND, function(code, output)
    if search ~= task then return end
    search = nil
    answer(text, code == 0 and files.rows(output, shell.HOME, text, modified) or {})
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
  if message.type == "rates" then return giveRates() end
  if message.type == "reveal" or message.type == "copy" then
    local action = palette.action(message.type, message.id)
    if not action then return end
    shell.close()
    if action.kind == "reveal" then return shell.open({ "-R", action.path })() end
    hs.pasteboard.setContents(action.path)
    return shell.alert("Copied path", 1)
  end
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
      card.html({ prompt = palette.prompt(fileSearch), rows = rows, compact = true, calc = true, files = fileSearch }), onPaletteMessage,
      -- Closed any way, by Escape, Option+Space or losing focus, a running mdfind stops too.
      { onClose = stopSearch })
  end, { "list-windows", "--all", "--format", windows.FORMAT }):start()
end

return feature
