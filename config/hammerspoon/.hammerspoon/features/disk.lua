-- Disk card (Option+Shift+X, or a click on the bar's low-space item): free space, and what
-- Mole's cleanup previews would free. Each row opens Mole's interactive command in a new
-- Ghostty window, so you pick what goes; the card itself never deletes anything.
-- The previews take up to two minutes, so they run in the background, at most once every
-- 6 hours, and the open card updates when they finish.

local shell = require("shell")
local panel = require("panel")
local disk = require("disk")

local feature = {}

local MO = "/opt/homebrew/bin/mo"
local WIDTH = 420
local PREVIEWS = { clean = { "clean", "--dry-run" }, purge = { "purge", "--dry-run" } }
-- Mole is a bash script that calls Homebrew's tools, which Hammerspoon's own PATH lacks.
local TASK_ENVIRONMENT = { HOME = shell.HOME, PATH = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", LANG = "en_US.UTF-8" }

local space = nil
local previews = {}
local running = {}
-- A preview still running when its cleanup starts measured the disk before it, so its
-- result is dropped rather than saved.
local discarded = {}

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

local function forget(id)
  os.remove(cachePath(id))
  previews[id] = nil
  if running[id] then discarded[id] = true end
end

local function onMessage(message)
  if message.type ~= "choose" then return shell.close() end
  local command = disk.command(message.id)
  if not command then return shell.close() end
  local stale = disk.invalidates(message.id)
  if stale then forget(stale) end
  shell.leaveFocus()
  shell.close()
  shell.run(shell.LAUNCH, { "1", shell.GHOSTTY_WINDOW, command })()
end

local function model()
  return disk.model({ installed = installed(), space = space, previews = previews }, os.time())
end

local function render()
  local current = model()
  shell.show("disk", shell.anchored(WIDTH, disk.height(current), "disk"), panel.html(current), onMessage)
end

-- New space or a finished preview updates the open card in place, keeping its selection.
local function updateIfOpen()
  if shell.isOpen("disk") then shell.view():evaluateJavaScript(panel.update(model())) end
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
  previews[id] = { measuring = true }
  startTask(PREVIEWS[id], function(_, output)
    running[id] = false
    if discarded[id] then
      discarded[id] = false
      previews[id] = nil
      return
    end
    local size = disk.previewSize(output)
    if size then saveCache(id, size) end
    previews[id] = size and { size = size, at = os.time() } or (last and last.size and last) or nil
    updateIfOpen()
  end)
end

local function refreshPreviews()
  for id in pairs(PREVIEWS) do
    local saved = disk.readCache(shell.readText(cachePath(id)))
    if not running[id] then previews[id] = saved and { size = saved.size, at = saved.at } or nil end
    if disk.isStale(saved, os.time()) then measure(id) end
  end
end

-- df answers at once; Mole's status brings purgeable space about a second later. Until it
-- does, the last purgeable space stays, so the bar doesn't change a second after it opens.
local function refreshSpace()
  space = disk.withPurgeable(disk.parseDf(hs.execute("/bin/df -k /")), space)
  startTask({ "status", "--json" }, function(code, output)
    if code ~= 0 then return end
    local ok, decoded = pcall(hs.json.decode, output)
    local status = ok and disk.parseStatus(decoded)
    if not status then return end
    space = status
    updateIfOpen()
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
