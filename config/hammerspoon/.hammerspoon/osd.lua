-- The volume and brightness pop-ups: levels in macOS's 16 steps, the pop-up's segments and
-- icon, and m1ddc's answers for an external display's brightness.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local osd = {}

local STEPS = 16
local STEP = 100 / STEPS

osd.ICONS = { muted = "󰝟", low = "󰕿", medium = "󰖀", high = "󰕾", brightness = "󰃠" }

-- How close to a step counts as on it: macOS reports 43.75% as 43.749996.
local ON_STEP = 1e-3

-- level moved one step up or down, snapped to the steps, kept between 0 and 100. A fine
-- step, with Option held, moves 1% from where the level is.
function osd.step(level, direction, fine)
  local current = level or 0
  if fine then return math.max(0, math.min(100, math.floor((current + direction) * 1000 + 0.5) / 1000)) end
  local index = direction > 0 and math.floor(current / STEP + ON_STEP) + 1 or math.ceil(current / STEP - ON_STEP) - 1
  return math.max(0, math.min(100, index * STEP))
end

-- How many of the pop-up's 16 segments a level lights.
function osd.segments(level)
  return math.max(0, math.min(STEPS, math.ceil((level or 0) / STEP - ON_STEP)))
end

function osd.volumeIcon(level, muted)
  if muted or (level or 0) <= 0 then return osd.ICONS.muted end
  if level < 34 then return osd.ICONS.low end
  if level < 67 then return osd.ICONS.medium end
  return osd.ICONS.high
end

-- `m1ddc display list`: "[1] DELL G2724D (UUID)" per display.
function osd.parseDisplays(text)
  local displays = {}
  for index, name in (text or ""):gmatch("%[(%d+)%]%s+(.-)%s+%([^%)]*%)") do
    displays[#displays + 1] = { index = tonumber(index), name = name }
  end
  return displays
end

-- The m1ddc display number for a screen, by name; nil when m1ddc doesn't list it.
function osd.displayFor(displays, name)
  for _, display in ipairs(displays) do
    if display.name == name then return display.index end
  end
  return nil
end

-- `m1ddc get luminance`: a number from 0 to 100, or nil for an error or an impossible value.
function osd.parseLevel(text)
  local level = tonumber((text or ""):match("^%s*(%d+)%s*$"))
  if not level or level > 100 then return nil end
  return level
end

-- Some displays answer DDC reads unreliably, sometimes with junk like 48750, so a level is
-- read several times and the value that comes back most often wins; ties go to the first.
function osd.likelyLevel(readings)
  local counts, best = {}, nil
  for _, level in ipairs(readings) do
    if type(level) == "number" and level >= 0 and level <= 100 then
      counts[level] = (counts[level] or 0) + 1
      if not best or counts[level] > counts[best] then best = level end
    end
  end
  return best
end

local VOLUME_KEYS = { SOUND_UP = 1, SOUND_DOWN = -1, MUTE = 0 }
local BRIGHTNESS_KEYS = { BRIGHTNESS_UP = 1, BRIGHTNESS_DOWN = -1 }

function osd.isVolumeKey(key)
  return VOLUME_KEYS[key] ~= nil
end

function osd.isBrightnessKey(key)
  return BRIGHTNESS_KEYS[key] ~= nil
end

-- 1 for up, -1 for down, 0 for mute.
function osd.direction(key)
  return VOLUME_KEYS[key] or BRIGHTNESS_KEYS[key]
end

return osd
