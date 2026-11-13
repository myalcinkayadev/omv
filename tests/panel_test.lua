-- Behavior of the status-card layout: its bar, grid and buttons or list. Run through
-- panel_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local panel = require("panel")

local function model(overrides)
  local base = { icon = "x", title = "Disk", sub = "STARTUP DISK", big = "212 GB free", percent = 40,
    grid = { { "Used", "273 GB" } }, buttons = { { id = "a", icon = "i", label = "A" } } }
  for key, value in pairs(overrides or {}) do base[key] = value end
  return base
end

local stacked = panel.html(model({ segments = { { share = 55.2, kind = "used" }, { share = 2, kind = "purgeable" } } }))
local first = stacked:find('class="used" style="width: 55.2%"', 1, true)
local second = stacked:find('class="purgeable" style="width: 2%"', 1, true)
check.that("should draw one bar segment per share, in order", first ~= nil and second ~= nil and first < second)
check.that("should draw a single bar when no shares are given", check.contains(panel.html(model()), "width: 40%"))

local swatched = panel.html(model({ grid = { { "Purgeable", "9.7 GB", "purgeable" } } }))
check.that("should mark a grid label with its bar segment's swatch", check.contains(swatched, '<span class="swatch purgeable">Purgeable</span>'))

local items = {
  { id = "clean", icon = "c", label = "Caches and logs", size = "3.80 GB", age = "3h ago" },
  { id = "purge", icon = "p", label = "Build artifacts", size = "3.34 GB" },
}
local listed = panel.html(model({ list = true, section = "CLEAN UP", buttons = items }))
check.that("should lay the choices out as a list when asked", check.contains(listed, 'class="btns list"'))
check.that("should mark the first list item selected when none is", check.contains(listed, 'class="btn item selected" data-id="clean"'))
check.that("should keep the list's size and age apart in the markup",
  check.contains(listed, "<span class=size>3.80 GB</span><span class=age>3h ago</span>"))
check.that("should leave the age empty when an item has none", check.contains(listed, "<span class=size>3.34 GB</span><span class=age></span>"))
check.that("should keep the list layout when the card updates", check.contains(panel.update(model({ list = true, buttons = items })), "3h ago"))
check.that("should move through a list with Up and Down", check.contains(listed, "ArrowDown") and check.contains(listed, "ArrowUp"))

check.finish()
