-- Permissions (Option+Escape, then Permissions): each permission omv needs, granted or not,
-- and Enter opens its pane in System Settings. Opens on its own once, the first time omv loads.

local shell = require("shell")
local card = require("card")
local permissions = require("permissions")

local feature = {}

local SEEN = shell.STATE_DIR .. "/permissions-shown"
local DND = shell.HOME .. "/Library/DoNotDisturb/DB"
local WIDTH = 560

-- What Hammerspoon can read itself. Full Disk Access shows as being able to list a folder
-- macOS protects.
local function localStates()
  local readable = pcall(hs.fs.dir, DND) and hs.fs.attributes(DND) ~= nil
  return {
    accessibility = hs.accessibilityState(false),
    screen = hs.screenRecordingState(false),
    location = hs.location.authorizationStatus() == "authorized",
    disk = readable,
  }
end

local function show(states)
  local screen = { prompt = "Permissions…", rows = permissions.rows(states) }
  shell.show("permissions", shell.centered(WIDTH, shell.menuHeight(screen)), card.html(screen), function(message)
    if message.type == "back" then return require("features.menu").toggle() end
    if message.type ~= "choose" then return shell.close() end
    local url = permissions.paneUrl(message.id)
    if not url then return end
    shell.close()
    shell.open({ url })()
  end)
end

-- AeroSpace can list windows only with Accessibility, so its answer is the check.
function feature.open()
  local states = localStates()
  hs.task.new(shell.AEROSPACE, function(code)
    states.aerospace = code == 0
    show(states)
  end, { "list-windows", "--all" }):start()
end

if permissions.shouldOpen(shell.readText(SEEN)) then
  hs.fs.mkdir(shell.STATE_DIR)
  local file = io.open(SEEN, "w")
  if file then file:write("shown\n"); file:close() end
  -- After the rest of omv has started, so the card isn't the first thing to load.
  feature.timer = hs.timer.doAfter(3, feature.open)
end

return feature
