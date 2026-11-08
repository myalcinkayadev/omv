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
check.that("should keep a single column by default", not check.contains(sample, "column-count"))
check.that("should list the system items in order",
  labels(menu.screen("system")) == "Lock,Screensaver,Sleep,Log out,Restart,Shut down,Sound,Reload")
check.that("should open Sound as a submenu", menu.screen("system").rows[7].submenu == true)
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
check.that("should treat Sound and Reload as screens to open", menu.opens("sound") and menu.opens("reload"))
check.that("should not treat an action as a screen", not menu.opens("lock"))

local devices = {
  { uid = "BuiltInSpeakerDevice", name = "MacBook Pro Speakers", transport = "Built-in", current = false },
  { uid = "aa-bb", name = "Mehmet's AirPods Pro", transport = "Bluetooth", current = true },
  { uid = "dell", name = "DELL U2723QE", transport = "DisplayPort", current = false },
  { uid = "zoom", name = "ZoomAudioDevice", transport = "Virtual", current = false },
  { uid = "jbl", name = "JBL Flip 6", transport = "Bluetooth", current = false },
}
local sound = menu.sound(devices)
check.that("should title the sound screen", sound.prompt == "Sound…")
check.that("should list the output devices in order, without virtual ones",
  labels(sound) == "MacBook Pro Speakers,Mehmet's AirPods Pro,DELL U2723QE,JBL Flip 6")
check.that("should select the device in use", sound.selected == 2)
check.that("should mark the device in use", sound.rows[2].hint == "current" and sound.rows[1].hint == nil)
check.that("should give each device row its uid", sound.rows[3].id == "sound.dell")
check.that("should show headphones for AirPods", sound.rows[2].icon == "󰋋")
check.that("should show a monitor for a display", sound.rows[3].icon == "󰍹")
check.that("should show a speaker for built-in speakers", sound.rows[1].icon == "󰓃")
check.that("should keep a virtual device while it is in use",
  #menu.sound({ { uid = "z", name = "ZoomAudioDevice", transport = "Virtual", current = true } }).rows == 1)
check.that("should say so when there are no devices",
  check.contains(card.html(menu.sound({})), "No output devices"))

check.finish()
