-- Night light (Option+Shift+Z, or Option+Escape, then Night light): switches macOS's Night
-- Shift with the nightlight CLI. The bar shows a moon while it's on; Night Shift's own
-- schedule can change it too, so the bar checks again every 5 minutes.

local shell = require("shell")
local nightshift = require("nightshift")

local feature = {}

local NIGHTLIGHT = "/opt/homebrew/bin/nightlight"
local CHECK_SECONDS = 300

local function status(done)
  if not hs.fs.attributes(NIGHTLIGHT) then return done(nil) end
  hs.task.new(NIGHTLIGHT, function(_, output) done(output) end, { "status" }):start()
end

local function showOnBar(output)
  local on = output ~= nil and nightshift.isOn(output)
  hs.task.new(shell.SKETCHYBAR, nil, { "--set", "nightlight", "drawing=" .. (on and "on" or "off") }):start()
end

function feature.toggle()
  shell.close()
  status(function(output)
    if not output then return shell.alert("Night light needs: brew install smudge/smudge/nightlight", 3) end
    local turning = nightshift.switch(output)
    hs.task.new(NIGHTLIGHT, function()
      shell.alert("Night light " .. turning, 1)
      status(showOnBar)
    end, { turning }):start()
  end)
end

-- Kept on the feature, so it isn't garbage-collected.
feature.timer = hs.timer.doEvery(CHECK_SECONDS, function() status(showOnBar) end)
status(showOnBar)

return feature
