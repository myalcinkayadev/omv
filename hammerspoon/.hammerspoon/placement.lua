-- Where a card opens: just under the bar item it opens from, its left edge at the item's,
-- kept inside the screen. Reads the item's place from `sketchybar --query <item>`, whose
-- bounding_rects are in the same global points as Hammerspoon's screens. Without the item
-- drawn on that screen, the card opens at the screen's right edge, as before.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local placement = {}

-- The 36pt bar, and the room left between the card and it or the screen's edge.
local BAR, GAP, MARGIN = 36, 4, 10

local function inside(screen, x, y)
  return x >= screen.x and x < screen.x + screen.w and y >= screen.y and y < screen.y + screen.h
end

-- The item's left edge on this screen, or nil when it isn't drawn there.
local function itemLeft(query, screen)
  if type(query) ~= "table" or type(query.bounding_rects) ~= "table" then return nil end
  if query.geometry and query.geometry.drawing == "off" then return nil end
  for _, rect in pairs(query.bounding_rects) do
    local origin = type(rect) == "table" and rect.origin
    if origin and inside(screen, origin[1], origin[2]) then return origin[1] end
  end
  return nil
end

-- The card's frame on screen, { x, y, w, h }, under the item in query.
function placement.under(query, width, height, screen)
  local right = screen.x + screen.w - width - MARGIN
  local x = itemLeft(query, screen) or right
  return { x = math.max(screen.x + MARGIN, math.min(x, right)), y = screen.y + BAR + GAP, w = width, h = height }
end

return placement
