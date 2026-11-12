-- Volume and brightness pop-ups: the volume, mute and brightness keys are caught, so omv's
-- pop-up shows in place of macOS's. With Option held, they move 1% at a time. The brightness keys dim the display under the pointer:
-- the built-in one directly, an external one over DDC with m1ddc. Catching the keys needs
-- Accessibility for Hammerspoon; without it, or for an output macOS can't set the volume
-- of, the keys behave as macOS's own.

local shell = require("shell")
local theme = require("theme")
local osd = require("osd")

local feature = {}

local M1DDC = "/opt/homebrew/bin/m1ddc"
local SHOW_SECONDS = 1.2
local WIDTH, HEIGHT = 320, 60
-- DDC is slow, so a held key changes the pop-up at once and the display once it settles.
local DDC_SETTLE_SECONDS = 0.15

local canvas = nil
local hideTimer = nil
-- The external displays m1ddc can dim, their brightness, and levels still to be written.
local ddc = { displays = {}, levels = {}, pending = {} }
-- On the feature too, to look into from the console.
feature.ddc = ddc

local function color(hex)
  return { hex = hex, alpha = 1 }
end

local function placed()
  local frame = shell.screen():frame()
  return { x = frame.x + (frame.w - WIDTH) / 2, y = frame.y + frame.h - HEIGHT - 120, w = WIDTH, h = HEIGHT }
end

-- A card-styled bar of 16 segments under an icon, in the theme's colours.
local function show(icon, level)
  local tokens = shell.themeTokens()
  local off = theme.mix(tokens.bg, tokens.fg, 0x2a / 255)
  local elements = {
    { type = "rectangle", action = "strokeAndFill", fillColor = color(tokens.bg), strokeColor = color(tokens.accent),
      strokeWidth = 2, frame = { x = 0, y = 0, w = WIDTH, h = HEIGHT } },
    { type = "text", text = hs.styledtext.new(icon, { font = { name = "JetBrainsMono Nerd Font Mono", size = 26 },
      color = color(tokens.fg) }), frame = { x = 18, y = 13, w = 34, h = 34 } },
  }
  local left, gap, count = 64, 3, 16
  local width = (WIDTH - left - 20 - gap * (count - 1)) / count
  local lit = osd.segments(level)
  for index = 1, count do
    elements[#elements + 1] = { type = "rectangle", action = "fill", fillColor = color(index <= lit and tokens.fg or off),
      frame = { x = left + (index - 1) * (width + gap), y = (HEIGHT - 10) / 2, w = width, h = 10 } }
  end
  if not canvas then
    canvas = hs.canvas.new(placed()):level(hs.canvas.windowLevels.overlay):behavior({ "canJoinAllSpaces", "transient" })
  end
  canvas:frame(placed()):replaceElements(elements):show()
  if hideTimer then hideTimer:stop() end
  hideTimer = hs.timer.doAfter(SHOW_SECONDS, function() canvas:hide() end)
end

-- Returns false for an output macOS can't set the volume of, such as some HDMI ones.
local function changeVolume(key, fine)
  local device = hs.audiodevice.defaultOutputDevice()
  local volume = device and device:outputVolume()
  if not volume then return false end
  local direction = osd.direction(key)
  if direction == 0 then
    device:setOutputMuted(not device:outputMuted())
  else
    if device:outputMuted() then device:setOutputMuted(false) end
    device:setOutputVolume(osd.step(volume, direction, fine))
  end
  local muted = device:outputMuted()
  show(osd.volumeIcon(device:outputVolume(), muted), muted and 0 or device:outputVolume())
  return true
end

local writeDdc = hs.timer.delayed.new(DDC_SETTLE_SECONDS, function()
  for index, level in pairs(ddc.pending) do
    hs.task.new(M1DDC, nil, { "display", tostring(index), "set", "luminance", tostring(math.floor(level + 0.5)) }):start()
  end
  ddc.pending = {}
end)

-- Returns false for a display neither macOS nor m1ddc can dim.
local function changeBrightness(key, fine)
  local screen = shell.screen()
  local direction = osd.direction(key)
  local index = osd.displayFor(ddc.displays, screen:name())
  if index then
    local level = osd.step(ddc.levels[index] or 50, direction, fine)
    ddc.levels[index], ddc.pending[index] = level, level
    writeDdc:start()
    show(osd.ICONS.brightness, level)
    return true
  end
  if not (screen:name() or ""):find("Built%-in") then return false end
  local level = osd.step(hs.brightness.get(), direction, fine)
  hs.brightness.set(math.floor(level + 0.5))
  show(osd.ICONS.brightness, level)
  return true
end

-- What m1ddc can dim, read again whenever displays come and go.
local function readDisplays()
  if not hs.fs.attributes(M1DDC) then return end
  hs.task.new(M1DDC, function(_, output)
    ddc.displays = osd.parseDisplays(output)
    for _, display in ipairs(ddc.displays) do
      hs.task.new(M1DDC, function(_, level)
        ddc.levels[display.index] = osd.parseLevel(level)
      end, { "display", tostring(display.index), "get", "luminance" }):start()
    end
  end, { "display", "list" }):start()
end

-- A key's press and release are both swallowed, or both left to macOS.
local swallowed = {}

local function onKey(event)
  local key = event:systemKey()
  local name = key and key.key
  if not name or not (osd.isVolumeKey(name) or osd.isBrightnessKey(name)) then return false end
  if not key.down then
    local handled = swallowed[name]
    if not key["repeat"] then swallowed[name] = nil end
    return handled or false
  end
  local fine = event:getFlags().alt == true
  local handled = osd.isVolumeKey(name) and changeVolume(name, fine) or (osd.isBrightnessKey(name) and changeBrightness(name, fine))
  swallowed[name] = handled or nil
  return handled or false
end

-- Kept on the feature, so they aren't garbage-collected. macOS turns a slow tap off, so it's
-- turned back on when that happens.
feature.keys = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, onKey):start()
feature.keysWatchdog = hs.timer.doEvery(30, function()
  if not feature.keys:isEnabled() then feature.keys:start() end
end)
feature.screens = hs.screen.watcher.new(readDisplays):start()
readDisplays()

return feature
