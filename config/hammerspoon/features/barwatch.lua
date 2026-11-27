-- The bar watchdog: every few seconds, whether SketchyBar and AeroSpace run; a bar gone for
-- 10 seconds while AeroSpace runs is started again with the bar's own start.sh, and the start
-- goes to ~/.local/state/omv/stalls.log, so a bar that keeps dying shows when. barwatch.lua
-- holds the rules.

local shell = require("shell")
local stalls = require("stalls")
local barwatch = require("barwatch")

local feature = {}

local LOG = shell.STATE_DIR .. "/stalls.log"
local START = shell.HOME .. "/.config/sketchybar/start.sh"
local SEEN = "/usr/bin/pgrep -x sketchybar >/dev/null && echo bar; /usr/bin/pgrep -x AeroSpace >/dev/null && echo aerospace"

local state = barwatch.new()
-- Whether a check's pgrep is still running, so a slow one never piles up behind the next.
local checking = false

-- Started detached, as omv doctor --fix does, since start.sh runs as long as the bar.
local function start(gone)
  shell.execute("/usr/bin/nohup '" .. START .. "' >/dev/null 2>&1 &")
  stalls.append(LOG, barwatch.line(os.date("%Y-%m-%d %H:%M:%S"), gone))
end

local function check()
  if checking then return end
  checking = true
  shell.execute(SEEN, function(output)
    checking = false
    local action, gone = barwatch.check(state, { bar = output:find("bar") ~= nil, aerospace = output:find("aerospace") ~= nil },
      hs.timer.secondsSinceEpoch())
    if action == "start" then start(gone) end
  end)
end

-- Kept on the feature, so it isn't garbage-collected.
feature.timer = hs.timer.doEvery(barwatch.CHECK_SECONDS, check)

return feature
