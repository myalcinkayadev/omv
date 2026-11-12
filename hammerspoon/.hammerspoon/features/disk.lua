-- Disk card (Option+Shift+X, or a click on the bar's low-space item): free space, and what
-- Mole's cleanup previews would free. Each row opens Mole's interactive command in a new
-- Ghostty window, so you pick what goes; the card itself never deletes anything.
-- The previews take up to two minutes, so they run in the background, at most once every
-- 6 hours, and the open card updates when they finish.

local shell = require("shell")
local card = require("card")
local disk = require("disk")

local feature = {}

local MO = "/opt/homebrew/bin/mo"
local WIDTH = 480
local PREVIEWS = { clean = { "clean", "--dry-run" }, purge = { "purge", "--dry-run" } }
-- Mole is a bash script that calls Homebrew's tools, which Hammerspoon's own PATH lacks.
local TASK_ENVIRONMENT = { HOME = shell.HOME, PATH = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", LANG = "en_US.UTF-8" }

local space = nil
local previews = {}
local running = {}

local function cachePath(id)
  return shell.STATE_DIR .. "/disk-" .. id
end

local function saveCache(id, size)
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
  local file = io.open(cachePath(id), "w")
  if not file then return end
  file:write(disk.cacheLine(os.time(), size))
  file:close()
end

local function installed()
  return hs.fs.attributes(MO) ~= nil
end

local function onMessage(message)
  if message.type ~= "choose" then return shell.close() end
  local command = disk.command(message.id)
  if not command then return shell.close() end
  shell.leaveFocus()
  shell.close()
  shell.run(shell.LAUNCH, { "1", shell.GHOSTTY_WINDOW, command })()
end

local function render()
  local rows = disk.rows({ installed = installed(), space = space, previews = previews })
  shell.show("disk", shell.anchored(WIDTH, shell.menuHeight({ rows = rows }), "disk"),
    card.html({ prompt = "Disk…", rows = rows }), onMessage)
end

local function redrawIfOpen()
  if shell.isOpen("disk") then render() end
end

-- A finished preview only changes hints, so the open card keeps its selection and filter.
local function updateHintsIfOpen()
  if not shell.isOpen("disk") then return end
  shell.view():evaluateJavaScript(card.setHints(disk.hints({ space = space, previews = previews })))
end

local function startTask(arguments, onDone)
  local task = hs.task.new(MO, onDone, arguments)
  task:setEnvironment(TASK_ENVIRONMENT)
  task:start()
end

-- Runs one dry-run preview. A run that prints no summary keeps the last size it had.
local function measure(id)
  if running[id] then return end
  running[id] = true
  local last = previews[id]
  previews[id] = { measuring = true, size = last and last.size }
  startTask(PREVIEWS[id], function(_, output)
    running[id] = false
    local size = disk.previewSize(output)
    if size then saveCache(id, size) end
    previews[id] = (size or (last and last.size)) and { size = size or last.size } or nil
    updateHintsIfOpen()
  end)
end

local function refreshPreviews()
  for id in pairs(PREVIEWS) do
    local saved = disk.readCache(shell.readText(cachePath(id)))
    if not running[id] then previews[id] = saved and { size = saved.size } or nil end
    if disk.isStale(saved, os.time()) then measure(id) end
  end
end

-- df answers at once; Mole's status adds purgeable space about a second later. It changes
-- the first row's label too, so the card is drawn again, before you've likely moved.
local function refreshSpace()
  space = disk.parseDf(hs.execute("/bin/df -k /"))
  startTask({ "status", "--json" }, function(code, output)
    if code ~= 0 then return end
    local ok, decoded = pcall(hs.json.decode, output)
    local status = ok and disk.parseStatus(decoded)
    if not status then return end
    space = status
    redrawIfOpen()
  end)
end

function feature.toggle()
  if shell.isOpen("disk") then return shell.close() end
  if not installed() then
    space = disk.parseDf(hs.execute("/bin/df -k /"))
    return render()
  end
  refreshSpace()
  refreshPreviews()
  render()
end

return feature
