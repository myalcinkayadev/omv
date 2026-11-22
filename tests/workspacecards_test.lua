-- The Workspaces card and the cards it opens, the window card, and stepping their values.
-- Run through workspacecards_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local workspaces = require("workspaces")
local cards = require("workspacecards")

local FILE = [[
dev = 7
[workspace 1]
on   = DELL
apps = Ghostty

[workspace 2]
on     = DELL
apps   = Zed, Helium
layout = tabs

[workspace 7]

[screen laptop]
gaps   = 4
layout = tabs

]]
local list = workspaces.parse(FILE)
local laptop = { name = "Built-in Retina Display", builtin = true, main = false, x = -1512 }
local dell = { name = "DELL U2723QE", main = true, x = 0 }
local seen = { { name = "DELL U2723QE", now = true }, { name = "Built-in Retina Display", builtin = true, now = true }, { name = "LG HDR 4K", now = false } }

local function find(rows, id) for _, row in ipairs(rows) do if row.id == id then return row end end end

-- The Workspaces card.
local main = cards.mainRows(list, { laptop, dell }, seen)
check.that("should list each workspace with where it is, its apps and layout",
  find(main, "workspace:2").hint == "on DELL · Zed, Helium · tabs  ›" and find(main, "workspace:2").group == "Workspaces")
check.that("should mark the dev workspace", find(main, "workspace:7").hint == "on main · dev layout  ›")
check.that("should offer the next workspace, with what comes after", find(main, "add").label == "Add workspace 3" and find(main, "add").hint == "then pick what goes there")
check.that("should list each screen once, with its gaps and layout, under Screens",
  find(main, "screen:laptop").hint == "no workspace here · gaps 4 · tabs  ›" and find(main, "screen:DELL U2723QE").hint == "omv's gaps  ›" and find(main, "screen:LG HDR 4K").group == "Screens")
local nine = workspaces.parse("[workspace 1]\n[workspace 2]\n[workspace 3]\n[workspace 4]\n[workspace 5]\n[workspace 6]\n[workspace 7]\n[workspace 8]\n[workspace 9]\n")
check.that("should leave out Add when all nine exist", find(cards.mainRows(nine, { dell }, {}), "add") == nil)

-- A workspace's card.
local four = workspaces.parse("[workspace 4]\non = LG, screen 2\napps = Slack\nopen = Slack\n")
local rows = cards.workspaceRows(four.workspaces["4"], "LG")
check.that("should list a workspace's screens in order, first then the rest", find(rows, "on:1").label == "First" and find(rows, "on:1").hint == "‹  LG  ›"
  and find(rows, "on:2").label == "Then" and find(rows, "on:2").hint == "‹  screen 2  ›")
check.that("should end the screens with main, always last", find(rows, "on:main").hint == "main, always last")
check.that("should offer another screen to fall back to", find(rows, "on:add") ~= nil)
check.that("should show the layout as the screen's when the workspace sets none", find(rows, "layout").hint == "‹  the screen's  ›")
check.that("should list the apps, each removable, and the app to open", find(rows, "app:Slack").hint == "⌫ remove" and find(rows, "open").hint == "‹  Slack  ›")
local choices = { "laptop", "screen 2", "screen 3", "DELL U2723QE", "LG HDR 4K" }
check.that("should step a screen through the choices", cards.stepChoice("laptop", 1, choices) == "screen 2" and cards.stepChoice("laptop", -1, choices) == "LG HDR 4K")
check.that("should step a part of a name that isn't a choice to the first", cards.stepChoice("LG", 1, choices) == "laptop")
check.that("should step the app to open through off and the apps",
  cards.stepChoice(nil, 1, { "Slack" }, true) == "Slack" and cards.stepChoice("Slack", 1, { "Slack" }, true) == nil)
check.that("should step the layout through the screen's, tiles and tabs",
  cards.stepChoice(nil, 1, { "tiles", "tabs" }, true) == "tiles" and cards.stepChoice("tabs", 1, { "tiles", "tabs" }, true) == nil)

-- A screen's card.
local screenRows = cards.screenRows({ inner = 8, outer = 12, layout = "tabs" })
check.that("should show a screen's gaps, both when they differ", find(screenRows, "gaps").hint == "‹  8 · 12  ›" and find(screenRows, "gaps.inner").hint == "‹  8  ›")
check.that("should show a screen's layout", find(screenRows, "layout").hint == "‹  tabs  ›")
local stepped = cards.step({ inner = 8, outer = 12 }, "gaps", 1)
check.that("should set both gaps to the step after the larger", stepped.inner == 16 and stepped.outer == 16)
check.that("should step one kind of gaps", cards.step({ inner = 4 }, "gaps.inner", 1).inner == 6 and cards.step({}, "gaps.inner", -1).inner == nil)
check.that("should step a screen's layout through omv's, tiles and tabs", cards.step({}, "layout", 1).layout == "tiles" and cards.step({ layout = "tabs" }, "layout", 1).layout == nil)

-- The window card.
local window = cards.windowRows({ app = "Zed", workspace = "2", kept = false, open = false, next = "3", nextScreen = "DELL" })
check.that("should offer keeping the app on its workspace", find(window, "keep").label == "Keep Zed on workspace 2")
check.that("should offer moving it to a new workspace on its screen", find(window, "new").hint == "3, on DELL")
check.that("should offer opening it when its workspace is empty, and forgetting its place",
  find(window, "open").label == "Open Zed when 2 is empty" and find(window, "forget") ~= nil)
local kept = cards.windowRows({ app = "Zed", workspace = "2", kept = true, open = true })
check.that("should mark an app kept, and leave out a new workspace when there's no room",
  find(kept, "keep").label == "Kept on workspace 2" and find(kept, "new") == nil and find(kept, "open").hint == "on")
local moveRows = cards.moveRows(list, "2", { laptop, dell })
check.that("should list where to move, each with where it is and its apps, here marked",
  find(moveRows, "workspace:1").hint == "on DELL · Ghostty" and find(moveRows, "workspace:2").hint == "on DELL · Zed, Helium  ·  here now")
check.that("should end the move list with a new workspace", moveRows[#moveRows].id == "new" and moveRows[#moveRows].label == "New workspace 3")

-- What goes on a workspace.
local choicesRows = cards.appChoices({ { name = "Zed", workspace = "2" }, { name = "Spotify", workspace = "3" }, { name = "Ghostty", workspace = "1" } }, list, "1")
check.that("should offer the apps open now, with where each lives", find(choicesRows, "app:Zed").hint == "on 2" and find(choicesRows, "app:Spotify").hint == "open, no place yet")
check.that("should leave out an app already on the workspace, and end with typing a name",
  find(choicesRows, "app:Ghostty") == nil and choicesRows[#choicesRows].id == "type")

local p2723 = { name = "DELL P2723D", main = false, x = 2560 }
local three = cards.mainRows(workspaces.parse("[workspace 1]\n[workspace 4]\non = laptop\n"), { laptop, dell, p2723 },
  { { name = "Built-in Retina Display", builtin = true, now = true }, { name = "DELL P2723D", now = true } })
check.that("should mark a screen plugged in that no workspace lands on", find(three, "screen:DELL P2723D").hint == "no workspace here · omv's gaps  ›")
check.that("should leave a screen a workspace lands on unmarked", find(three, "screen:laptop").hint == "omv's gaps  ›")
check.that("should leave a screen that isn't plugged in unmarked", find(main, "screen:LG HDR 4K").hint == "omv's gaps  ›")

-- Bundle ids and resetting.
check.that("should offer resetting the workspaces to omv's", find(main, "reset").label == "Reset to omv's workspaces" and find(main, "reset").group == "Workspaces")
local ids = workspaces.parse("[workspace 5]\napps = net.whatsapp.WhatsApp, Slack\n")
local names = { ["net.whatsapp.WhatsApp"] = "WhatsApp" }
check.that("should show a bundle id by its app's name in the workspace's hint",
  find(cards.mainRows(ids, { dell }, {}, names), "workspace:5").hint == "on main · WhatsApp, Slack · dev layout  ›")
check.that("should show a bundle id as it is when its app isn't installed",
  find(cards.mainRows(ids, { dell }, {}), "workspace:5").hint == "on main · net.whatsapp.WhatsApp, Slack · dev layout  ›")
local idRows = cards.workspaceRows(ids.workspaces["5"], names)
check.that("should label an app row by its name and keep the entry in its id",
  find(idRows, "app:net.whatsapp.WhatsApp").label == "WhatsApp" and find(idRows, "app:Slack").label == "Slack")
local byBundle = cards.appChoices({ { name = "WhatsApp", bundle = "net.whatsapp.WhatsApp", workspace = "8" }, { name = "Zed", bundle = "dev.zed.Zed", workspace = "2" } },
  workspaces.parse(nil), "1")
check.that("should offer an app open now by its bundle id, with the workspace that keeps it",
  find(byBundle, "app:net.whatsapp.WhatsApp").label == "WhatsApp" and find(byBundle, "app:net.whatsapp.WhatsApp").hint == "on 5")
check.that("should show where omv keeps an app by its bundle id", find(byBundle, "app:dev.zed.Zed").hint == "on 2")

check.that("should count a group's header as a line", cards.lineCount({ { group = "A" }, { group = "A" }, { group = "B" }, {} }) == 6)
check.that("should step through the laptop, a screen past those plugged in, and the displays seen",
  table.concat(cards.screenChoices(2, seen), ",") == "laptop,screen 2,screen 3,DELL U2723QE,LG HDR 4K")

check.finish()
