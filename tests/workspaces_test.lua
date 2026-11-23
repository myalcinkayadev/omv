-- Workspaces: ~/.config/omv/workspaces says which workspaces exist, the screens each prefers,
-- its apps and layout, and each screen's gaps and layout. Run through workspaces_test.sh.

local check = dofile(arg[1] .. "/tests/check.lua")
local workspaces = require("workspaces")

local function numbersOf(list) return table.concat(workspaces.numbers(list), " ") end
local function chain(list, workspace) return table.concat(list.workspaces[workspace].on, ", ") end

-- Without a file.
local defaults = workspaces.parse(nil)
check.that("should give today's seven workspaces without a file", numbersOf(defaults) == "1 2 3 4 5 6 7")
check.that("should put 1 to 3 on main and 4 to 6 on screen 2, then main, without a file",
  chain(defaults, "1") == "main" and chain(defaults, "4") == "screen 2, main")
check.that("should use 7 for the dev layout without a file", workspaces.devWorkspace(defaults) == "7")
local function appsOf(list, workspace) return table.concat(list.workspaces[workspace].apps, ",") end
check.that("should put omv's apps on today's workspaces, by bundle id, without a file",
  appsOf(defaults, "1") == "com.mitchellh.ghostty" and appsOf(defaults, "2") == "dev.zed.Zed" and appsOf(defaults, "3") == "net.imput.helium"
  and appsOf(defaults, "4") == "md.obsidian,notion.id,com.linear"
  and appsOf(defaults, "5") == "com.apple.Notes,com.apple.MobileSMS,net.whatsapp.WhatsApp,com.hnc.Discord"
  and appsOf(defaults, "6") == "com.apple.Music,com.spotify.client" and appsOf(defaults, "7") == "")
check.that("should give a workspace no apps without an apps line, none of omv's",
  appsOf(workspaces.parse("[workspace 5]\n"), "5") == "" and appsOf(workspaces.parse("[workspace 5]\napps =\n"), "5") == "")
check.that("should report a bundle id on two workspaces",
  workspaces.parse("[workspace 1]\napps = com.apple.Notes\n[workspace 2]\napps = com.apple.notes\n").problems[1] == "line 4: com.apple.notes is already on workspace 1")

-- Reading the file.
local FILE = [[
dev = 2
# mine
[workspace 1]
on   = DELL
apps = Ghostty

[workspace 2]
on     = DELL, main
apps   = Zed, Helium
layout = tabs
open   = Zed

[workspace 4]
on = LG, secondary

[screen laptop]
gaps   = 4
layout = tabs

[screen DELL]
gaps.inner = 8
gaps.outer = 12

]]
local read = workspaces.parse(FILE)
check.that("should read no problems in a file with every kind of section", #read.problems == 0)
check.that("should read the workspaces the file has", numbersOf(read) == "1 2 4")
check.that("should read a workspace's screens, with main always last", chain(read, "1") == "DELL, main" and chain(read, "2") == "DELL, main")
check.that("should read secondary as screen 2", chain(read, "4") == "LG, screen 2, main")
check.that("should read a workspace's apps, layout and app to open",
  table.concat(read.workspaces["2"].apps, ",") == "Zed,Helium" and read.workspaces["2"].layout == "tabs" and read.workspaces["2"].open == "Zed")
check.that("should read a screen's gaps for both kinds", read.screens["laptop"].inner == 4 and read.screens["laptop"].outer == 4)
check.that("should read each kind of a screen's gaps", read.screens["DELL"].inner == 8 and read.screens["DELL"].outer == 12)
check.that("should read a screen's layout", read.screens["laptop"].layout == "tabs")
check.that("should read the dev workspace", workspaces.devWorkspace(read) == "2")
check.that("should use the last workspace for the dev layout when dev isn't one",
  workspaces.devWorkspace(workspaces.parse("dev = 7\n[workspace 1]\n[workspace 4]\n")) == "4")
check.that("should give today's workspaces when the file has none, only screens",
  numbersOf(workspaces.parse("[screen laptop]\ngaps = 4\n")) == "1 2 3 4 5 6 7")

local function problem(text) return workspaces.parse(text).problems[1] end
check.that("should report a workspace outside 1 to 9", problem("[workspace 12]\n") == "line 1: a workspace is a number from 1 to 9")
check.that("should report a workspace twice", problem("[workspace 1]\n\n[workspace 1]\n") == "line 3: workspace 1 is already on line 1")
check.that("should report a screen twice, ignoring case", problem("[screen DELL]\n[screen dell]\n") == "line 2: screen dell is already on line 1")
check.that("should report an unknown setting", problem("[workspace 1]\ncolour = red\n") == "line 2: unknown setting colour")
check.that("should report an app on two workspaces", problem("[workspace 1]\napps = Zed\n[workspace 2]\napps = zed\n") == "line 4: zed is already on workspace 1")
check.that("should report a layout that isn't tiles or tabs", problem("[workspace 1]\nlayout = grid\n") == "line 2: layout is tiles or tabs")
check.that("should report gaps that aren't a whole number", problem("[screen DELL]\ngaps = wide\n") == "line 2: gaps is a whole number")
check.that("should say how to write a line of the old form", problem("2 = laptop\n") == "line 1: 2 = laptop is the old form; write [workspace 2] then on = laptop")
check.that("should report a line outside a section", problem("hello = 1\n") == "line 1: hello is outside a section")
check.that("should report an unknown section", problem("[desk]\n") == "line 1: unknown section desk; it's [workspace N] or [screen NAME]")
check.that("should report a setup section, which omv no longer reads", problem("[setup desk]\nwhen = laptop\n") == "line 1: unknown section setup desk; it's [workspace N] or [screen NAME]")
check.that("should keep today's workspaces when the file has a problem", numbersOf(workspaces.parse("[workspace 12]\n")) == "1 2 3 4 5 6 7")

-- Pins before the screens are known, for omv reload.
check.that("should pin main to the main monitor", workspaces.staticPattern({ "main" }) == "'main'")
check.that("should pin screen 2 to AeroSpace's secondary, then main", workspaces.staticPattern({ "screen 2", "main" }) == "['secondary', 'main']")
check.that("should pin laptop and a display's name as patterns, then main",
  workspaces.staticPattern({ "laptop", "LG (2)", "main" }) == "['built-in', 'LG \\(2\\)', 'main']")
check.that("should leave screen 3 to the screens being known", workspaces.staticPattern({ "screen 3", "main" }) == "'main'")

local AEROSPACE = table.concat({
  "persistent-workspaces = ['1', '2', '3', '4', '5', '6', '7']",
  "",
  "[workspace-to-monitor-force-assignment]",
  "1 = 'main'",
  "7 = 'main'",
  "",
  "[mode.main.binding]",
  "alt-h = 'focus left'",
  "alt-1 = 'workspace 1'",
  "alt-7 = 'workspace 7'",
  "alt-shift-1 = 'move-node-to-workspace 1'",
  "alt-keypad1 = 'workspace 1'",
  "alt-shift-keypad1 = 'move-node-to-workspace 1'",
  "alt-tab = 'workspace-back-and-forth'",
  "",
}, "\n")
local built = workspaces.rewriteDefaults(AEROSPACE, workspaces.parse("[workspace 1]\n[workspace 2]\non = screen 2\n[workspace 5]\non = DELL\n"))
check.that("should keep only the listed workspaces alive", check.contains(built, "persistent-workspaces = ['1', '2', '5']"))
check.that("should pin each listed workspace", check.contains(built, "[workspace-to-monitor-force-assignment]\n1 = 'main'\n2 = ['secondary', 'main']\n5 = ['DELL', 'main']\n"))
check.that("should bind the four keys of each listed workspace",
  check.contains(built, "alt-5 = 'workspace 5'") and check.contains(built, "alt-shift-keypad5 = 'move-node-to-workspace 5'"))
check.that("should free the keys of a workspace that isn't listed", not check.contains(built, "alt-7 ="))
check.that("should leave omv's other keys alone", check.contains(built, "alt-h = 'focus left'") and check.contains(built, "alt-tab = 'workspace-back-and-forth'"))

-- Pins once the screens are known: the first plugged in wins.
local laptop = { name = "Built-in Retina Display", builtin = true, main = false, x = -1512 }
local dell = { name = "DELL U2723QE", main = true, x = 0 }
local lg = { name = "LG HDR 4K", main = false, x = 2560 }
local four = workspaces.parse("[workspace 1]\n[workspace 2]\non = screen 2\n[workspace 3]\non = screen 3, screen 2\n[workspace 4]\non = laptop\n[workspace 5]\non = LG, laptop\n")
local resolved = workspaces.resolve(four, { lg, dell, laptop })
check.that("should send main to the main monitor", resolved["1"] == "'main'")
check.that("should send screen 2 to the leftmost other screen, by position", resolved["2"] == "[1, 'main']")
check.that("should fall back from screen 3 to screen 2, then main", resolved["3"] == "[3, 1, 'main']")
check.that("should send laptop to the built-in screen", resolved["4"] == "['built-in', 'main']")
check.that("should keep a name's pattern and the next screen in order", resolved["5"] == "['LG', 'built-in', 'main']")
check.that("should drop screen N that isn't plugged in", workspaces.resolve(four, { dell })["3"] == "'main'")
check.that("should write the resolved pins as AeroSpace's table",
  workspaces.assignmentToml(workspaces.resolve(four, { dell }), four) == "[workspace-to-monitor-force-assignment]\n1 = 'main'\n2 = 'main'\n3 = 'main'\n4 = ['built-in', 'main']\n5 = ['LG', 'built-in', 'main']\n")

-- Where each workspace is now, and its layout.
check.that("should find the screen a workspace is on now", workspaces.landsOn(four, "5", { dell, laptop }) == "laptop" and workspaces.landsOn(four, "5", { dell, lg, laptop }) == "LG")
check.that("should find main when none of its screens is plugged in", workspaces.landsOn(four, "4", { dell }) == "main")
local layoutList = workspaces.parse("[workspace 1]\nlayout = tiles\n[workspace 2]\non = laptop\n[workspace 3]\non = DELL\n[screen laptop]\nlayout = tabs\n[screen DELL]\ngaps = 4\n")
local plan = workspaces.layoutPlan(layoutList, { laptop, dell })
check.that("should give a workspace its own layout", plan["1"] == "tiles")
check.that("should give a workspace its screen's layout", plan["2"] == "tabs")
check.that("should leave a workspace whose screen sets no layout", plan["3"] == nil)

-- Gaps per screen, for AeroSpace.
local gaps = workspaces.gapsToml(read, { laptop, dell })
check.that("should give each screen its gaps between windows, the rest omv's",
  check.contains(gaps, 'inner.horizontal = [{ monitor."DELL" = 8 }, { monitor."built-in" = 4 }, 10]'))
check.that("should keep the notch's top gap and clear the bar on other screens",
  check.contains(gaps, 'outer.top = [{ monitor."built-in" = 14 }, { monitor."DELL" = 48 }, 46]'))
check.that("should write no gaps without screens that set some", workspaces.gapsToml(workspaces.parse(nil), { dell }) == nil)

-- Apps.
check.that("should write a bundle id as an app-id rule and a name as a name rule",
  workspaces.appRules(workspaces.parse("[workspace 5]\napps = com.apple.Notes, Visual Studio Code\n"))
    == "[[on-window-detected]]\nif.app-id = 'com.apple.Notes'\nrun = 'move-node-to-workspace 5'\n\n"
    .. "[[on-window-detected]]\nif.app-name-regex-substring = '(?i)^\226\128\142?Visual Studio Code$'\nrun = 'move-node-to-workspace 5'\n")
check.that("should write no rule for a workspace that isn't listed",
  not workspaces.appRules(workspaces.parse("[workspace 1]\napps = Zed\n")):find("move%-node%-to%-workspace [^1]"))
check.that("should move a window kept by bundle id to its workspace",
  workspaces.appMoves(workspaces.parse("[workspace 5]\napps = net.whatsapp.WhatsApp\n"), "21|net.whatsapp.WhatsApp|\226\128\142WhatsApp|8\n")[1].to == "5")
check.that("should find an app's workspace by its name or its bundle id",
  workspaces.homeOf(workspaces.parse(nil), "Zed", "dev.zed.Zed") == "2" and workspaces.homeOf(workspaces.parse("[workspace 4]\napps = Zed\n"), "zed", nil) == "4"
  and workspaces.homeOf(workspaces.parse("[workspace 4]\n"), "Zed", "dev.zed.Zed") == nil)
check.that("should send Option+Enter to Ghostty's workspace",
  check.contains(workspaces.rewriteDefaults("alt-enter = ['workspace 1', 'exec-and-forget new-window.sh']\n", workspaces.parse("[workspace 4]\napps = com.mitchellh.ghostty\n")),
    "alt-enter = ['workspace 4', 'exec-and-forget new-window.sh']"))
check.that("should keep Option+Enter on the current workspace when Ghostty isn't kept",
  check.contains(workspaces.rewriteDefaults("alt-enter = ['workspace 1', 'exec-and-forget new-window.sh']\n", workspaces.parse("[workspace 4]\n")),
    "alt-enter = ['exec-and-forget new-window.sh']"))
local repoToml = io.open(arg[1] .. "/config/aerospace/.config/aerospace/aerospace.toml"):read("*a")
check.that("should leave no app's workspace in omv's aerospace.toml, only floating and tiling rules",
  not repoToml:find("run = 'move%-node%-to%-workspace") and repoToml:find("run = 'layout floating'") ~= nil)
check.that("should write one rule per app, in workspace order",
  workspaces.appRules(read) == "[[on-window-detected]]\nif.app-name-regex-substring = '(?i)^\226\128\142?Ghostty$'\nrun = 'move-node-to-workspace 1'\n\n"
    .. "[[on-window-detected]]\nif.app-name-regex-substring = '(?i)^\226\128\142?Zed$'\nrun = 'move-node-to-workspace 2'\n\n"
    .. "[[on-window-detected]]\nif.app-name-regex-substring = '(?i)^\226\128\142?Helium$'\nrun = 'move-node-to-workspace 2'\n")
local moves = workspaces.appMoves(read, "11|x.zed|Zed|3\n12|x.helium|Helium|2\n13|x.ghostty|Ghostty|1\n14|x.ghostty|Ghostty|4\n")
local function moved(id) for _, move in ipairs(moves) do if move.id == id then return move.to end end end
check.that("should move an open window of an app to its workspace", moved("11") == "2")
check.that("should leave a window already there, and an app spread over workspaces", moved("12") == nil and moved("13") == nil and moved("14") == nil)
check.that("should move only the apps asked for when given some",
  #workspaces.appMoves(read, "11|x.zed|Zed|3\n15|x.helium|Helium|5\n", { helium = true }) == 1 and workspaces.appMoves(read, "11|x.zed|Zed|3\n15|x.helium|Helium|5\n", { helium = true })[1].id == "15")
check.that("should list the apps whose workspace changed, by lowercase name",
  next(workspaces.movedApps(read, read)) == nil and workspaces.movedApps(workspaces.parse("[workspace 1]\napps = Zed\n"), read).zed == true
  and workspaces.movedApps(workspaces.parse("[workspace 1]\napps = Zed\n"), read).helium == true)
local layoutChanges = workspaces.layoutChanges({ ["1"] = "tabs", ["2"] = "tiles" }, { ["1"] = "tabs", ["3"] = "tabs" })
check.that("should set only the layouts that changed, tiles for one no longer set",
  layoutChanges["1"] == nil and layoutChanges["2"] == "tiles" and layoutChanges["3"] == "tabs")
check.that("should set no layout that was never set", next(workspaces.layoutChanges({}, {})) == nil)
check.that("should open a workspace's app when it's empty", workspaces.openOnEmpty(read, "2", 0) == "Zed" and workspaces.openOnEmpty(read, "2", 1) == nil)
local strays = workspaces.strayWindows("11 1\n12 7\n13 2\n", read)
check.that("should move windows off a workspace that isn't listed to the lowest one left", #strays == 1 and strays[1].id == "12" and strays[1].to == "1")

-- Editing: the file with today's workspaces written out first, so a change to one keeps the rest.
local fromNothing = workspaces.keepApp("", workspaces.parse(nil), "Zed", "2")
local fromNothingRead = workspaces.parse(fromNothing)
check.that("should write today's workspaces into the file before the first change", numbersOf(fromNothingRead) == "1 2 3 4 5 6 7")
check.that("should write omv's apps into the file with today's workspaces", appsOf(fromNothingRead, "5") == "com.apple.Notes,com.apple.MobileSMS,net.whatsapp.WhatsApp,com.hnc.Discord")
check.that("should keep an app on a workspace", appsOf(fromNothingRead, "2") == "dev.zed.Zed,Zed" and #fromNothingRead.problems == 0)
local byId = workspaces.parse(workspaces.keepApp(fromNothing, fromNothingRead, "net.whatsapp.WhatsApp", "8", "WhatsApp"))
check.that("should move an app kept by bundle id off its old workspace", appsOf(byId, "5") == "com.apple.Notes,com.apple.MobileSMS,com.hnc.Discord" and appsOf(byId, "8") == "net.whatsapp.WhatsApp")
local byName = workspaces.parse(workspaces.keepApp(fromNothing, fromNothingRead, "WhatsApp", "3", "net.whatsapp.WhatsApp"))
check.that("should replace an app's bundle id entry when it's kept by name", not appsOf(byName, "5"):find("WhatsApp") and appsOf(byName, "3") == "net.imput.helium,WhatsApp")
check.that("should forget an app by its bundle id or its name",
  not appsOf(workspaces.parse(workspaces.forgetApp(fromNothing, fromNothingRead, "WhatsApp", "net.whatsapp.WhatsApp")), "5"):find("WhatsApp"))
local RESETTABLE = "# mine\ndev = 2\n[workspace 1]\napps = Zed\n[screen laptop]\ngaps = 4\n[workspace 9]\n"
local reset, removedLines = workspaces.resetWorkspaces(RESETTABLE)
local resetRead = workspaces.parse(reset)
check.that("should reset to today's workspaces and omv's apps", numbersOf(resetRead) == "1 2 3 4 5 6 7" and appsOf(resetRead, "1") == "com.mitchellh.ghostty")
check.that("should keep screens, dev and comments on reset",
  check.contains(reset, "# mine\ndev = 2\n") and check.contains(reset, "[screen laptop]\ngaps = 4\n"))
check.that("should give the lines a reset took out", check.contains(removedLines, "[workspace 9]") and check.contains(removedLines, "apps = Zed"))
local moved2 = workspaces.parse(workspaces.keepApp(FILE, read, "zed", "1"))
check.that("should take a kept app off its old workspace", table.concat(moved2.workspaces["2"].apps, ",") == "Helium" and table.concat(moved2.workspaces["1"].apps, ",") == "Ghostty,zed")
check.that("should keep the file's comments and other sections", check.contains(workspaces.keepApp(FILE, read, "zed", "1"), "# mine\n") and check.contains(workspaces.keepApp(FILE, read, "zed", "1"), "[screen DELL]"))
check.that("should forget an app", #workspaces.parse(workspaces.forgetApp(FILE, read, "Helium")).workspaces["2"].apps == 1)
local added, number = workspaces.addWorkspace(FILE, read, "DELL")
check.that("should add the lowest free workspace, on the given screen, then main", number == "3" and chain(workspaces.parse(added), "3") == "DELL, main")
local nine = "[workspace 1]\n[workspace 2]\n[workspace 3]\n[workspace 4]\n[workspace 5]\n[workspace 6]\n[workspace 7]\n[workspace 8]\n[workspace 9]\n"
check.that("should add nothing when all nine exist", workspaces.addWorkspace(nine, workspaces.parse(nine), "main") == nil)
check.that("should remove a workspace", numbersOf(workspaces.parse((workspaces.removeWorkspace(FILE, read, "4")))) == "1 2")
check.that("should keep the last workspace", workspaces.removeWorkspace("[workspace 1]\n", workspaces.parse("[workspace 1]\n"), "1") == nil)
check.that("should set a workspace's screens, without writing main", check.contains(workspaces.setOn(FILE, read, "4", { "LG", "laptop", "main" }), "on = LG, laptop\n"))
check.that("should set and clear a workspace's layout and app to open",
  check.contains(workspaces.setWorkspace(FILE, read, "1", "layout", "tabs"), "layout = tabs")
  and not check.contains(workspaces.setWorkspace(FILE, read, "2", "open", nil), "open"))
check.that("should set a screen's gaps as one line when equal, and remove the kinds",
  check.contains(workspaces.setScreenGaps(FILE, "DELL", 6, 6), "[screen DELL]\ngaps = 6\n") and not check.contains(workspaces.setScreenGaps(FILE, "DELL", 6, 6), "gaps.inner"))
check.that("should set each kind of a screen's gaps when they differ",
  check.contains(workspaces.setScreenGaps(FILE, "laptop", 2, 8), "gaps.inner = 2") and check.contains(workspaces.setScreenGaps(FILE, "laptop", 2, 8), "gaps.outer = 8"))
check.that("should remove a screen's section once its gaps go back to omv's",
  not check.contains(workspaces.setScreenGaps("[workspace 1]\n\n[screen DELL]\ngaps = 4\n", "DELL", nil, nil), "[screen DELL]"))
check.that("should keep a screen's section that still sets its layout",
  check.contains(workspaces.setScreenGaps("[screen DELL]\ngaps = 4\nlayout = tabs\n", "DELL", nil, nil), "[screen DELL]\nlayout = tabs\n"))
check.that("should remove a screen's section once its layout goes back to omv's",
  not check.contains(workspaces.setScreenLayout("[workspace 1]\n[screen laptop]\nlayout = tabs\n", "laptop", nil), "[screen laptop]"))
check.that("should keep a screen's section that has a comment", check.contains(
  workspaces.setScreenGaps("[screen DELL]\n# the desk\ngaps = 4\n", "DELL", nil, nil), "[screen DELL]\n# the desk\n"))

-- Apps taken off a workspace go back where the rules in aerospace.toml send them.
local BUILT = [==[
[[on-window-detected]]
if.app-id = 'net.whatsapp.WhatsApp'
run = 'move-node-to-workspace 5'

[[on-window-detected]]
if.app-id = 'com.apple.finder'
run = 'layout tiling'

[[on-window-detected]]
if.app-id = 'net.whatsapp.WhatsApp'
run = 'move-node-to-workspace 6'
]==]
check.that("should move a kept app whose name AeroSpace marks left to right",
  workspaces.appMoves(workspaces.parse("[workspace 5]\napps = WhatsApp\n"), "21|x.whatsapp|\226\128\142WhatsApp|8\n")[1].to == "5")
local marked = workspaces.parse("[workspace 8]\napps = \226\128\142WhatsApp\n")
check.that("should match an app saved with AeroSpace's left-to-right mark to its windows",
  workspaces.appMoves(marked, "21|x.whatsapp|\226\128\142WhatsApp|5\n")[1].to == "8" and workspaces.homes(marked).whatsapp == "8")
check.that("should save an app's name without the left-to-right mark",
  check.contains(workspaces.keepApp("[workspace 8]\n", workspaces.parse("[workspace 8]\n"), "\226\128\142WhatsApp", "8"), "apps = WhatsApp\n"))
check.that("should forget an app saved with the left-to-right mark", not check.contains(workspaces.forgetApp(
  "[workspace 8]\napps = \226\128\142WhatsApp\n", marked, "WhatsApp"), "WhatsApp"))
local ruled = workspaces.ruleHomes(BUILT)
check.that("should read where each app's first rule sends it", ruled["net.whatsapp.WhatsApp"] == "5")
check.that("should read a rule after another", workspaces.ruleHomes("[[on-window-detected]]\nif.app-id = 'a'\nrun = 'layout floating'\n\n[[on-window-detected]]\nif.app-id = 'b'\nrun = 'move-node-to-workspace 4'\n\n[[on-window-detected]]\nif.app-id = 'c'\nrun = 'move-node-to-workspace 3'\n").c == "3")
check.that("should leave out a rule that doesn't move to a workspace", ruled["com.apple.finder"] == nil)
local kept = workspaces.parse("[workspace 5]\n[workspace 8]\napps = WhatsApp, Zed\n")
local forgot = workspaces.parse("[workspace 5]\n[workspace 8]\napps = Zed\n")
local WINDOWS = "21|net.whatsapp.WhatsApp|\226\128\142WhatsApp|8\n22|dev.zed.Zed|Zed|8\n"
local back = workspaces.forgottenMoves(kept, forgot, WINDOWS, ruled)
check.that("should move a forgotten app's windows where its rule sends them", #back == 1 and back[1].id == "21" and back[1].to == "5")
check.that("should leave a forgotten app without a rule where it is",
  #workspaces.forgottenMoves(kept, forgot, WINDOWS, {}) == 0)
check.that("should leave an app where it is when its rule's workspace doesn't exist",
  #workspaces.forgottenMoves(kept, forgot, WINDOWS, { ["net.whatsapp.WhatsApp"] = "9" }) == 0)

local builtIn = { name = "Built-in Retina Display", builtin = true }
local dell = { name = "DELL U2723QE" }
-- Displays seen.
local recorded = workspaces.recordSeen({}, { dell, builtIn }, "2026-11-20")
local again = workspaces.recordSeen(recorded, { dell }, "2026-11-22")
check.that("should record a display with the date and update it when seen again", again[1].last == "2026-11-22" and #again == 2 and again[2].now == false)
check.that("should read back the seen list it writes", workspaces.parseSeen(workspaces.formatSeen(again))[2].builtin == true)

local names = workspaces.nameLines(again)
check.that("should list the displays plugged in, then those seen before", names[1] == "Plugged in now:" and names[2] == "  DELL U2723QE"
  and names[3] == "Seen before:" and names[4]:match("^  Built%-in Retina Display +last seen 2026%-11%-20$") ~= nil)
check.that("should say no display was seen yet", workspaces.nameLines({})[1]:match("^No display seen yet") ~= nil)

-- A screen's section.
local laptopSection = workspaces.parse("[workspace 1]\n[screen laptop]\ngaps = 4\n")
local laptopScreen = { name = "Built-in Retina Display", builtin = true, main = true, x = 0 }
check.that("should find a screen's section by the word that names it",
  workspaces.sectionOf(laptopSection, laptopScreen, { laptopScreen }).outer == 4)
check.that("should find no section for a screen the file doesn't name",
  workspaces.sectionOf(laptopSection, { name = "DELL", main = false, x = 1 }, { laptopScreen, { name = "DELL", main = false, x = 1 } }) == nil)

-- Names, and the bar's text for each workspace.
local NAMED = "bar = {number}: {name}\n[workspace 1]\nname = Side project\n[workspace 2]\n[workspace 3]\nname = 🚀\n"
local named = workspaces.parse(NAMED)
local function nameProblem(text) return workspaces.parse(text).problems[1] end
check.that("should keep a workspace's name when name is set", workspaces.parse("[workspace 1]\nname = Code\n").workspaces["1"].name == "Code")
check.that("should leave the name unset when a workspace has no name line", named.workspaces["2"].name == nil)
check.that("should report the line when a name is empty", nameProblem("[workspace 1]\nname =\n") == "line 2: expected name = value")
check.that("should report a name longer than 16 characters",
  nameProblem("[workspace 1]\nname = abcdefghijklmnopq\n") == "line 2: a name is 16 characters at most")
check.that("should keep spaces inside a name", named.workspaces["1"].name == "Side project")
check.that("should keep an emoji in a name", named.workspaces["3"].name == "🚀")
check.that("should count an emoji as one character, not its bytes",
  #workspaces.parse("[workspace 1]\nname = 🚀🚀🚀🚀🚀\n").problems == 0)
check.that("should accept a name of exactly 16 characters with emoji",
  #workspaces.parse("[workspace 1]\nname = 🚀bcdefghijklmnop\n").problems == 0)
check.that("should reject a name of 17 characters with emoji",
  nameProblem("[workspace 1]\nname = 🚀bcdefghijklmnopq\n") == "line 2: a name is 16 characters at most")
check.that("should cut a name at #, since # starts a comment", workspaces.parse("[workspace 1]\nname = C# work\n").workspaces["1"].name == "C")

local plain = workspaces.parse("[workspace 1]\nname = Code\n[workspace 2]\n")
check.that("should show {number} {name} by default", workspaces.barText(plain, "1") == "1 Code")
check.that("should show only the number for a workspace without a name", workspaces.barText(plain, "2") == "2")
check.that("should show the format the file gives", workspaces.barText(named, "1") == "1: Side project")
check.that("should show only the number for an unnamed workspace when the format is {name}",
  workspaces.barText(workspaces.parse("bar = {name}\n[workspace 2]\n"), "2") == "2")
check.that("should show only the name when the format is {name}",
  workspaces.barText(workspaces.parse("bar = {name}\n[workspace 3]\nname = 🚀\n"), "3") == "🚀")
check.that("should report the line for an unknown placeholder",
  nameProblem("bar = {number} {foo}\n[workspace 1]\n") == "line 1: bar knows {number} and {name}, not {foo}")
check.that("should report a format with neither placeholder",
  nameProblem("bar = Code\n[workspace 1]\n") == "line 1: bar needs {number} or {name}")
check.that("should report bar inside a workspace section", nameProblem("[workspace 1]\nbar = {name}\n") == "line 2: unknown setting bar")
check.that("should give the bar's text for only the named workspaces",
  table.concat(workspaces.textLines(named), "|") == "1\t1: Side project|3\t3: 🚀")
check.that("should give no bar text without names", #workspaces.textLines(workspaces.parse("[workspace 1]\n")) == 0)
check.that("should give no bar text without a file", #workspaces.textLines(workspaces.parse(nil)) == 0)

-- Writing names and the bar's format.
local NAMEFILE = "dev = 7\n\n[workspace 1]\non = main   # here\n\n[workspace 2]\n"
local renamed = workspaces.setName(NAMEFILE, workspaces.parse(NAMEFILE), "1", "Code")
check.that("should write a name into the workspace's section", workspaces.parse(renamed).workspaces["1"].name == "Code")
check.that("should keep the comments when writing a name", renamed:find("on = main   # here", 1, true) ~= nil)
check.that("should remove the name line when the name is empty",
  not workspaces.setName(renamed, workspaces.parse(renamed), "1", ""):find("name", 1, true))
local tooLong, longProblem = workspaces.setName(NAMEFILE, workspaces.parse(NAMEFILE), "1", "abcdefghijklmnopq")
check.that("should refuse a 17-character name", tooLong == nil and longProblem == "a name is 16 characters at most")
local hashed, hashProblem = workspaces.setName(NAMEFILE, workspaces.parse(NAMEFILE), "1", "C#")
check.that("should refuse a name with #, which would start a comment", hashed == nil and hashProblem == "a name can't have #")
local withBar = workspaces.setBar(NAMEFILE, "{name}")
check.that("should write bar at the top, outside any section", withBar:match("^dev = 7\nbar = {name}\n") ~= nil and workspaces.parse(withBar).bar == "{name}")
local rewritten = workspaces.setBar(withBar, "{number}: {name}")
check.that("should replace an existing bar line", select(2, rewritten:gsub("bar =", "")) == 1 and workspaces.parse(rewritten).bar == "{number}: {name}")
check.that("should remove the bar line for the default", not workspaces.setBar(withBar, nil):find("bar", 1, true))

check.finish()
