-- The bar watchdog: every 10 seconds, whether SketchyBar and AeroSpace run, asked of macOS
-- without starting a process; a bar gone for 10 seconds while AeroSpace runs is started again
-- with the bar's own start.sh, and the start goes to ~/.local/state/omv/stalls.log, so a bar
-- that keeps dying shows when. barwatch.lua holds the rules.

local shell = require("shell")
local stalls = require("stalls")
local barwatch = require("barwatch")

local feature = {}

local LOG = shell.STATE_DIR .. "/stalls.log"
local START = shell.HOME .. "/.config/sketchybar/start.sh"
local AEROSPACE = "bobko.aerospace"

local state = barwatch.new()
-- The bar's process, once found: asking macOS about one process costs a twentieth of a
-- millisecond and starts nothing, where pgrep cost several milliseconds a check.
local barPid = nil

-- Whether SketchyBar runs: its known process first, else, only when that's gone, a look
-- through the running apps for its new one.
local function barRunning()
  if barPid then
    local app = hs.application.applicationForPID(barPid)
    if app and app:name() == "sketchybar" then return true end
    barPid = nil
  end
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:name() == "sketchybar" then
      barPid = app:pid()
      return true
    end
  end
  return false
end

-- Started detached, as omv doctor --fix does, since start.sh runs as long as the bar.
local function start(gone)
  shell.execute("/usr/bin/nohup '" .. START .. "' >/dev/null 2>&1 &")
  stalls.append(LOG, barwatch.line(os.date("%Y-%m-%d %H:%M:%S"), gone))
end

local function check()
  local seen = { bar = barRunning() }
  seen.aerospace = seen.bar or #hs.application.applicationsForBundleID(AEROSPACE) > 0
  local action, gone = barwatch.check(state, seen, hs.timer.secondsSinceEpoch())
  if action == "start" then start(gone) end
end

-- Kept on the feature, so it isn't garbage-collected.
feature.timer = hs.timer.doEvery(barwatch.CHECK_SECONDS, check)

return feature
