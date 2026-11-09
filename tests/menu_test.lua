-- Behavior of the card renderer and the system menu. Run through menu_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local card = require("card")
local menu = require("menu")

local function labels(screen)
  local result = {}
  for _, row in ipairs(screen.rows) do result[#result + 1] = row.label end
  return table.concat(result, ",")
end

local sample = card.html({
  prompt = "Pick…",
  rows = {
    { id = "one", icon = "A", label = "First" },
    { id = "two", icon = "B", label = "Second", submenu = true },
    { id = "three", label = "<b>Bold</b> & co" },
  },
})

local _, rowCount = sample:gsub("class=\"row", "")
check.that("should render one row per item", rowCount == 3)
check.that("should show each row's icon and label", check.contains(sample, ">A<") and check.contains(sample, ">First<"))
check.that("should mark items that open a submenu with ›", check.contains(sample, "data-submenu"))
check.that("should escape HTML in labels", check.contains(sample, "&lt;b&gt;Bold&lt;/b&gt; &amp; co"))
check.that("should show the menu title in the search prompt", check.contains(sample, "data-prompt=\"Pick…\""))
check.that("should give each row its item id", check.contains(sample, "data-id=\"two\""))
check.that("should select the row it is told to select",
  check.contains(card.html({ prompt = "x", rows = { { id = "a", label = "a" }, { id = "b", label = "b" } }, selected = 2 }), "data-selected=\"2\""))

check.that("should lay rows out in columns when asked",
  check.contains(card.html({ prompt = "x", rows = { { id = "a", label = "a" } }, columns = 2 }), "column-count: 2"))
local grouped = card.html({ prompt = "x", rows = {
  { id = "a", label = "a", group = "Windows" }, { id = "b", label = "b", group = "Windows" }, { id = "c", label = "c", group = "Apps" } } })
local _, headerCount = grouped:gsub("class=group", "")
check.that("should render one header per group", headerCount == 2)
check.that("should render headers in row order", grouped:find(">Windows<", 1, true) < grouped:find(">Apps<", 1, true))
check.that("should keep a group's header together with its first row",
  check.contains(grouped, '<div class=lead><div class=group data-name="Windows">Windows</div><div class="row" data-id="a"'))
check.that("should not render a header for rows without a group", not check.contains(sample, "class=group"))
check.that("should let a row's group match a search", check.contains(grouped, 'data-group="Windows"'))
check.that("should keep a single column by default", not check.contains(sample, "column-count"))
check.that("should list the system items in order",
  labels(menu.screen("system")) == "Lock,Screensaver,Sleep,Log out,Restart,Shut down,Sound,Reload")
check.that("should list Sound without ›, since it opens its own card", not menu.screen("system").rows[7].submenu)
check.that("should open Reload as a submenu", menu.screen("system").rows[8].submenu == true)
check.that("should list the tools under Reload",
  labels(menu.screen("reload")) == "AeroSpace,SketchyBar,Hammerspoon,Everything")

check.that("should ask before logging out", menu.needsConfirm("logout"))
check.that("should ask before restarting", menu.needsConfirm("restart"))
check.that("should ask before shutting down", menu.needsConfirm("shutdown"))
check.that("should not ask before locking", not menu.needsConfirm("lock"))

local confirm = menu.confirm("restart")
check.that("should title the confirmation with the action", confirm.prompt == "Restart?")
check.that("should list Cancel first on a confirmation", confirm.rows[1].id == "cancel")
check.that("should select Cancel first on a confirmation", confirm.selected == 1)
check.that("should offer the confirmed action second", confirm.rows[2].id == "confirmed.restart")

check.that("should return nothing for an unknown screen", menu.screen("nope") == nil)
check.that("should treat Reload as a screen to open", menu.opens("reload"))
check.that("should not treat Sound as a screen to open", not menu.opens("sound"))
check.that("should not treat an action as a screen", not menu.opens("lock"))

check.that("should keep other menu screens at the standard width", menu.screen("system").width == nil)

check.finish()
