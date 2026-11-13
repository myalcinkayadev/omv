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

-- The card's frame on screen, { x, y, w, h }, under the item in query. A card taller than
-- the room under the bar shrinks to it; its rows scroll.
function placement.under(query, width, height, screen)
  local right = screen.x + screen.w - width - MARGIN
  local x = itemLeft(query, screen) or right
  local room = screen.h - BAR - GAP - MARGIN
  return { x = math.max(screen.x + MARGIN, math.min(x, right)), y = screen.y + BAR + GAP, w = width, h = math.min(height, room) }
end

-- A card in the middle of the screen, a third of the way down. One taller than the screen
-- shrinks to it, less a margin at the top and bottom.
function placement.centered(width, height, screen)
  local fitted = math.min(height, screen.h - 2 * MARGIN)
  return { x = screen.x + (screen.w - width) / 2, y = screen.y + math.max(MARGIN, (screen.h - fitted) / 3), w = width, h = fitted }
end

return placement
