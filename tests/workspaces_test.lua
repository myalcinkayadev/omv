-- Workspaces: which exist, the default screen of each, and what omv builds from them. Run
-- through workspaces_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local workspaces = require("workspaces")

local function numbersOf(list) return table.concat(workspaces.numbers(list), " ") end

-- Reading the file.
local defaults = workspaces.parse(nil)
check.that("should give today's seven workspaces without a file", numbersOf(defaults) == "1 2 3 4 5 6 7")
check.that("should put 4 to 6 on screen 2 without a file", defaults.screens["4"] == "screen 2" and defaults.screens["1"] == "main")
check.that("should use 7 for the dev layout without a file", workspaces.devWorkspace(defaults) == "7")

local FILE = "# mine\n1 = main\n2 = DELL\n3 = screen 3\n5 = laptop\n8 = secondary\ndev = 2\n"
local read = workspaces.parse(FILE)
check.that("should read the workspaces in number order", numbersOf(read) == "1 2 3 5 8")
check.that("should read each workspace's screen", read.screens["2"] == "DELL" and read.screens["5"] == "laptop")
check.that("should read secondary as screen 2", read.screens["8"] == "screen 2")
check.that("should read the dev workspace", workspaces.devWorkspace(read) == "2")
check.that("should use the last workspace for the dev layout when dev isn't one",
  workspaces.devWorkspace(workspaces.parse("1 = main\n4 = main\ndev = 7\n")) == "4")
check.that("should report a workspace outside 1 to 9 with its line",
  workspaces.parse("1 = main\n10 = main\n").problems[1] == "line 2: a workspace is a number from 1 to 9")
check.that("should report a workspace listed twice with both lines",
  workspaces.parse("1 = main\n1 = DELL\n").problems[1] == "line 2: workspace 1 is already on line 1")
check.that("should report a line it can't read", workspaces.parse("1 = main\nhello\n").problems[1] == "line 2: expected 1 = main")
check.that("should report an unknown setting", workspaces.parse("1 = main\ncolour = red\n").problems[1] == "line 2: unknown setting colour")
check.that("should report a file with no workspace", workspaces.parse("# none\n").problems[1] == "keep at least one workspace")
check.that("should keep today's workspaces when the file has a problem",
  numbersOf(workspaces.parse("1 = main\n10 = main\n")) == "1 2 3 4 5 6 7")

-- What omv builds before AeroSpace knows the screens.
check.that("should pin main to the main monitor", workspaces.staticPattern("main") == "'main'")
check.that("should pin screen 2 to AeroSpace's secondary, then main", workspaces.staticPattern("screen 2") == "['secondary', 'main']")
check.that("should pin screen 3 to main until the screens are known", workspaces.staticPattern("screen 3") == "'main'")
check.that("should pin laptop to the built-in screen, then main", workspaces.staticPattern("laptop") == "['built-in', 'main']")
check.that("should pin a display's name as an escaped pattern, then main", workspaces.staticPattern("LG (2)") == "['LG \\(2\\)', 'main']")

local AEROSPACE = table.concat({
  "persistent-workspaces = ['1', '2', '3', '4', '5', '6', '7']",
  "",
  "[workspace-to-monitor-force-assignment]",
  "1 = 'main'",
  "# The dev workspace.",
  "7 = 'main'",
  "",
  "[mode.main.binding]",
  "alt-h = 'focus left'",
  "# Workspace keys",
  "alt-1 = 'workspace 1'",
  "alt-7 = 'workspace 7'",
  "alt-shift-1 = 'move-node-to-workspace 1'",
  "alt-keypad1 = 'workspace 1'",
  "alt-shift-keypad1 = 'move-node-to-workspace 1'",
  "alt-tab = 'workspace-back-and-forth'",
  "",
}, "\n")
local built = workspaces.rewriteDefaults(AEROSPACE, workspaces.parse("1 = main\n2 = screen 2\n5 = DELL\n"))
check.that("should keep only the listed workspaces alive", check.contains(built, "persistent-workspaces = ['1', '2', '5']"))
check.that("should pin each listed workspace", check.contains(built, "[workspace-to-monitor-force-assignment]\n1 = 'main'\n2 = ['secondary', 'main']\n5 = ['DELL', 'main']\n"))
check.that("should drop the old pins", not check.contains(built, "7 = 'main'") and not check.contains(built, "The dev workspace"))
check.that("should bind the four keys of each listed workspace",
  check.contains(built, "alt-5 = 'workspace 5'") and check.contains(built, "alt-shift-5 = 'move-node-to-workspace 5'")
  and check.contains(built, "alt-keypad5 = 'workspace 5'") and check.contains(built, "alt-shift-keypad5 = 'move-node-to-workspace 5'"))
check.that("should free the keys of a workspace that isn't listed", not check.contains(built, "alt-7 ="))
check.that("should leave omv's other keys alone", check.contains(built, "alt-h = 'focus left'") and check.contains(built, "alt-tab = 'workspace-back-and-forth'"))

-- What omv writes once it knows the screens: screen N is the Nth screen from the left that
-- isn't the main one, as AeroSpace's position number among all screens.
local laptop = { name = "Built-in Retina Display", builtin = true, main = false, x = -1512 }
local dellMain = { name = "DELL U2723QE", main = true, x = 0 }
local lg = { name = "LG HDR 4K", main = false, x = 2560 }
local benq = { name = "BenQ", main = false, x = 5120 }
local four = workspaces.parse("1 = main\n2 = screen 2\n3 = screen 3\n4 = screen 4\n5 = laptop\n")
local resolved = workspaces.resolve(four, { lg, dellMain, benq, laptop })
check.that("should send main to the main monitor", resolved["1"] == "'main'")
check.that("should send screen 2 to the leftmost other screen, by position", resolved["2"] == "[1, 'main']")
check.that("should fall back from screen 3 to screen 2, then main", resolved["3"] == "[3, 1, 'main']")
check.that("should fall back from screen 4 through 3 and 2", resolved["4"] == "[4, 3, 1, 'main']")
check.that("should send laptop to the built-in screen", resolved["5"] == "['built-in', 'main']")
local alone = workspaces.resolve(four, { dellMain })
check.that("should send every screen N to main with one screen", alone["2"] == "'main'" and alone["4"] == "'main'")
local two = workspaces.resolve(four, { dellMain, lg })
check.that("should skip screens that aren't plugged in", two["3"] == "[2, 'main']")
check.that("should write the resolved pins as AeroSpace's table",
  workspaces.assignmentToml(two, four) == "[workspace-to-monitor-force-assignment]\n1 = 'main'\n2 = [2, 'main']\n3 = [2, 'main']\n4 = [2, 'main']\n5 = ['built-in', 'main']\n")

-- Windows left on a workspace that was removed.
local moves = workspaces.strayWindows("11 1\n12 7\n13 8\n14 3\n", workspaces.parse("1 = main\n3 = main\n"))
check.that("should move windows off removed workspaces to the lowest one left",
  #moves == 2 and moves[1].id == "12" and moves[1].to == "1" and moves[2].id == "13")
check.that("should leave windows on listed workspaces where they are", #workspaces.strayWindows("11 1\n14 3\n", workspaces.parse("1 = main\n3 = main\n")) == 0)

-- The Workspaces card.
local cardList = workspaces.parse("1 = main\n2 = screen 2\n4 = DELL\ndev = 4\n")
local written = workspaces.format(cardList)
check.that("should write a file that reads back as the same workspaces",
  numbersOf(workspaces.parse(written)) == "1 2 4" and workspaces.parse(written).screens["4"] == "DELL"
  and workspaces.devWorkspace(workspaces.parse(written)) == "4" and #workspaces.parse(written).problems == 0)
check.that("should step a screen to the next one", workspaces.stepScreen("main", 1, 3) == "screen 2" and workspaces.stepScreen("screen 3", 1, 3) == "laptop")
check.that("should step up to as many screens as are plugged in, five here",
  workspaces.stepScreen("screen 4", 1, 5) == "screen 5" and workspaces.stepScreen("screen 5", 1, 5) == "laptop")
check.that("should still offer screen 2 with one screen plugged in", workspaces.stepScreen("main", 1, 1) == "screen 2")
check.that("should wrap a screen from laptop back to main", workspaces.stepScreen("laptop", 1, 2) == "main" and workspaces.stepScreen("main", -1, 2) == "laptop")
check.that("should step a display's name, or a screen beyond those plugged in, to main",
  workspaces.stepScreen("DELL", 1, 2) == "main" and workspaces.stepScreen("screen 4", 1, 2) == "main")
local added = workspaces.add(cardList)
check.that("should add the lowest workspace missing, on main", numbersOf(added) == "1 2 3 4" and added.screens["3"] == "main")
local nine = workspaces.parse("1=main\n2=main\n3=main\n4=main\n5=main\n6=main\n7=main\n8=main\n9=main\n")
check.that("should add nothing when all nine exist", workspaces.add(nine) == nil)
check.that("should remove a workspace", numbersOf(workspaces.remove(cardList, "2")) == "1 4")
check.that("should keep the last workspace", workspaces.remove(workspaces.parse("1 = main\n"), "1") == nil)
check.that("should leave the list it was given unchanged", numbersOf(cardList) == "1 2 4")
local cardRows = workspaces.rows(cardList, "3")
local function rowIds(rows) local ids = {} for _, row in ipairs(rows) do ids[#ids + 1] = row.id end return table.concat(ids, " ") end
check.that("should list each workspace, Bring back for one just removed, then Add", rowIds(cardRows) == "workspace:1 workspace:2 undo workspace:4 add")
check.that("should hint each workspace's screen, and mark the dev workspace",
  check.contains(cardRows[2].hint, "screen 2") and check.contains(cardRows[4].hint, "dev layout"))
check.that("should name the key of the workspace Add makes", cardRows[5].label == "Add workspace 3" and cardRows[5].hint == "Option+3")
check.that("should leave out Add when all nine exist", not check.contains(rowIds(workspaces.rows(nine)), "add"))

check.finish()
