-- Behavior of placing a card under the bar item it opens from. Run through placement_test.sh
-- with luajit. Queries are tables, as hs.json.decode gives `sketchybar --query <item>`.

local check = dofile(arg[1] .. "/tests/check.lua")
local placement = require("placement")

-- A 2560pt main display, and a 1512pt one placed to its left, as SketchyBar reports them.
local MAIN = { x = 0, y = 0, w = 2560, h = 1440 }
local LEFT = { x = -1512, y = 458, w = 1512, h = 982 }

local function item(rects, drawing)
  local bounding = {}
  for name, rect in pairs(rects) do bounding[name] = { origin = { rect[1], rect[2] }, size = { rect[3], 36 } } end
  return { geometry = { drawing = drawing or "on" }, bounding_rects = bounding }
end

local claude = item({ ["display-1"] = { 2123, 0, 91 }, ["display-2"] = { -437, 458, 91 } })

local frame = placement.under(claude, 400, 218, MAIN)
check.that("should open the card under its bar item, aligned to the item's left edge", frame.x == 2123)
check.that("should open the card just below the bar", frame.y == 40)
check.that("should keep the card's size", frame.w == 400 and frame.h == 218)
check.that("should use the item's position on the screen the card opens on", placement.under(claude, 400, 218, LEFT).x == -437)
check.that("should open just below the bar on a lower screen", placement.under(claude, 400, 218, LEFT).y == 458 + 40)

local nearRight = item({ ["display-1"] = { 2500, 0, 40 } })
check.that("should keep the card inside the screen's right edge", placement.under(nearRight, 400, 218, MAIN).x == 2560 - 400 - 10)
local nearLeft = item({ ["display-1"] = { 2, 0, 40 } })
check.that("should keep the card inside the screen's left edge", placement.under(nearLeft, 400, 218, MAIN).x == 10)

local hidden = item({ ["display-1"] = { -9999, -9999, 1 } }, "off")
check.that("should fall back to the right edge when the item isn't drawn", placement.under(hidden, 400, 218, MAIN).x == 2560 - 400 - 10)
check.that("should fall back to the right edge without a query", placement.under(nil, 400, 218, MAIN).x == 2560 - 400 - 10)

-- Cards taller than the screen shrink to fit; their rows scroll.
local TALL = 2000
check.that("should keep a card's height when it fits under the bar", placement.under(claude, 400, 218, LEFT).h == 218)
check.that("should shrink a card to the room under the bar when it is taller",
  placement.under(claude, 400, TALL, LEFT).h == 982 - 36 - 4 - 10)

local centered = placement.centered(420, 300, LEFT)
check.that("should center a card horizontally when it opens centered", centered.x == -1512 + (1512 - 420) / 2)
check.that("should open a centered card a third of the way down when it fits", centered.y == 458 + (982 - 300) / 3)
check.that("should keep a centered card's size when it fits", centered.w == 420 and centered.h == 300)
check.that("should shrink a centered card to the screen less its margins when it is taller",
  placement.centered(420, TALL, LEFT).h == 982 - 2 * 10)
check.that("should keep a shrunk centered card inside the screen's top edge", placement.centered(420, TALL, LEFT).y == 458 + 10)

check.finish()
