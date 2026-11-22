-- One rebuild of AeroSpace's config for many requests. Workspaces, display profiles and the
-- Workspaces card each change a part of aerospace.toml, often within a moment of each other;
-- asking here waits a little, then runs omv reload aerospace once for all of them, and calls
-- each one's follow-up after. A request during a rebuild waits for the next one.

local shell = require("shell")

local feature = {}

local REPO = hs.configdir:gsub("/config/hammerspoon/?$", "")
local OMV = REPO .. "/bin/omv"
-- How long requests are gathered before AeroSpace reloads.
local DEFER_SECONDS = 0.8

local waiting, running = {}, false
local timer

local function rebuild()
  if running then return timer:start() end
  local followUps = waiting
  waiting = {}
  running = true
  -- Hammerspoon's tasks get a bare PATH; omv needs Homebrew's luajit and aerospace.
  hs.task.new(OMV, function()
    running = false
    for _, followUp in ipairs(followUps) do pcall(followUp) end
  end, { "reload", "aerospace" })
    :setEnvironment({ HOME = shell.HOME, PATH = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" }):start()
end

timer = hs.timer.delayed.new(DEFER_SECONDS, rebuild)

-- Asks for a rebuild; done, when given, runs once AeroSpace has the new config.
function feature.request(done)
  if type(done) == "function" then waiting[#waiting + 1] = done end
  timer:start()
end

return feature
