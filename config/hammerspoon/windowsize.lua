-- Window sizing: Ctrl+Option+Left and Right put the focused window in a half of the screen,
-- then a third, then two-thirds as the key is pressed again; Up almost full; Down centred at
-- two-thirds; C centred at its own size. Always inside the gaps AeroSpace keeps, so a sized
-- window lines up with the tiled ones. A tiled window is floated first.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local windowsize = {}

-- AeroSpace's outer gaps, as omv builds them: 10 around; on top, 14 on the built-in screen,
-- where macOS already keeps windows clear of the notch, and the bar's 36 plus the gap on others.
local GAP, NOTCH_TOP, BAR_HEIGHT = 10, 14, 36
-- How soon the same key again steps to the next size.
windowsize.STEP_SECONDS = 1.5
local FRACTIONS = { 1 / 2, 1 / 3, 2 / 3 }

-- The outer gaps of a screen: its [screen] section in ~/.config/omv/workspaces, or nil.
function windowsize.outer(section, builtin)
  local side = (section and section.outer) or GAP
  return { top = builtin and NOTCH_TOP or (BAR_HEIGHT + side), left = side, right = side, bottom = side }
end

-- The part of a screen's visible frame windows go in.
function windowsize.area(frame, outer)
  return { x = frame.x + outer.left, y = frame.y + outer.top,
    w = frame.w - outer.left - outer.right, h = frame.h - outer.top - outer.bottom }
end

-- Where action puts a window: left or right (step 1 a half, 2 a third, 3 two-thirds), up,
-- down or center, in area; current is the window's frame now.
function windowsize.place(action, area, current, step)
  if action == "left" or action == "right" then
    local w = area.w * FRACTIONS[step or 1]
    local x = action == "left" and area.x or (area.x + area.w - w)
    return { x = x, y = area.y, w = w, h = area.h }
  end
  if action == "up" then return { x = area.x, y = area.y, w = area.w, h = area.h } end
  local w, h = area.w * 2 / 3, area.h * 2 / 3
  if action == "center" then w, h = math.min(current.w, area.w), math.min(current.h, area.h) end
  return { x = area.x + (area.w - w) / 2, y = area.y + (area.h - h) / 2, w = w, h = h }
end

-- The step for action pressed at time: the next one when it's the same key again soon, else
-- the first; and the memory for the next press.
function windowsize.nextStep(memory, action, time)
  local again = memory.action == action and memory.at and time - memory.at <= windowsize.STEP_SECONDS
  local step = again and (memory.step % #FRACTIONS + 1) or 1
  return step, { action = action, at = time, step = step }
end

-- Whether a window with AeroSpace's layout, such as h_tiles or floating, is floated first.
function windowsize.needsFloat(layout)
  return layout ~= "floating"
end

return windowsize
