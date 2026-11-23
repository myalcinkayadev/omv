-- Window sizing: Ctrl+Option+arrows put the focused window in a half, a third, almost full or
-- the centre, inside the screen's gaps. Run through windowsize_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local windowsize = require("windowsize")
local workspaces = require("workspaces")

local function same(rect, x, y, w, h)
  return math.abs(rect.x - x) < 0.01 and math.abs(rect.y - y) < 0.01 and math.abs(rect.w - w) < 0.01 and math.abs(rect.h - h) < 0.01
end

-- An external screen at 0,0, 1000 wide and 800 tall, with omv's gaps: 10, and 46 on top.
local external = windowsize.area({ x = 0, y = 0, w = 1000, h = 800 }, windowsize.outer(nil, false))
check.that("should keep the bar's 46 at the top of an external screen", same(external, 10, 46, 980, 744))
local builtin = windowsize.area({ x = 0, y = 32, w = 1000, h = 800 }, windowsize.outer(nil, true))
check.that("should keep 14 at the top of the built-in screen", same(builtin, 10, 46, 980, 776))
check.that("should use a screen's own outer gaps", same(windowsize.area({ x = 0, y = 0, w = 1000, h = 800 }, windowsize.outer({ outer = 4 }, false)), 4, 40, 992, 756))

local function place(action, step, current)
  return windowsize.place(action, external, current or { x = 100, y = 100, w = 400, h = 300 }, step or 1)
end
check.that("should put Left in the left half", same(place("left"), 10, 46, 490, 744))
check.that("should put Right in the right half", same(place("right"), 500, 46, 490, 744))
check.that("should put Left's second step in the left third", same(place("left", 2), 10, 46, 980 / 3, 744))
check.that("should put Left's third step in the left two-thirds", same(place("left", 3), 10, 46, 980 * 2 / 3, 744))
check.that("should make Up the whole area", same(place("up"), 10, 46, 980, 744))
check.that("should centre Down at two-thirds", same(place("down"), 10 + 980 / 6, 46 + 744 / 6, 980 * 2 / 3, 744 * 2 / 3))
check.that("should centre C at the window's size", same(place("center"), 10 + 290, 46 + 222, 400, 300))
check.that("should shrink C to fit a window bigger than the area", same(place("center", 1, { x = 0, y = 0, w = 2000, h = 900 }), 10, 46, 980, 744))

-- Stepping.
local memory = {}
local steps = {}
for _, press in ipairs({ { "left", 0 }, { "left", 1 }, { "left", 2 }, { "left", 3 } }) do
  local step
  step, memory = windowsize.nextStep(memory, press[1], press[2])
  steps[#steps + 1] = step
end
check.that("should step a half, a third, two-thirds, then a half again on quick presses", table.concat(steps, " ") == "1 2 3 1")
check.that("should start again at a half after a pause", (windowsize.nextStep({ action = "left", at = 0, step = 2 }, "left", 2)) == 1)
check.that("should start again at a half after another key", (windowsize.nextStep({ action = "right", at = 0, step = 2 }, "left", 0.5)) == 1)

-- Floating first.
check.that("should float a tiled window first", windowsize.needsFloat("h_tiles") and windowsize.needsFloat("v_accordion"))
check.that("should leave a floating window as it is", not windowsize.needsFloat("floating"))

check.finish()
