-- Behavior of display profiles: reading ~/.config/omv/displays, picking a profile for the
-- displays plugged in, and what applying one changes. Run through displays_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local displays = require("displays")

local FILE = [[
# Profiles, first match wins.

[desk]
when = laptop, DELL U2723QE
count = 2
layout = tiles
gaps = 10
gaps.inner = 8
quiet = off
theme = tokyo-night
font = 15
bar = shown
on-enter = ~/bin/desk-on.sh
on-leave = ~/bin/desk-off.sh

[laptop]
when = built-in only
layout = tabs
gaps = 4
theme = keep
]]

-- Parsing.
local read = displays.parse(FILE)
check.that("should read each section as a profile", #read.profiles == 2 and read.profiles[1].name == "desk")
check.that("should keep the profiles in file order", read.profiles[2].name == "laptop")
check.that("should ignore comments and blank lines", #read.problems == 0)
check.that("should read when as a list split by commas",
  read.profiles[1].when[1] == "laptop" and read.profiles[1].when[2] == "DELL U2723QE")
check.that("should read count as a number", read.profiles[1].count == 2)
check.that("should read built-in only as the laptop screen", read.profiles[2].when[1] == "laptop" and #read.profiles[2].when == 1)
check.that("should read gaps as both inner and outer", read.profiles[2].settings.gapsInner == 4 and read.profiles[2].settings.gapsOuter == 4)
check.that("should let gaps.inner override gaps", read.profiles[1].settings.gapsInner == 8 and read.profiles[1].settings.gapsOuter == 10)
check.that("should let gaps.outer override gaps",
  displays.parse("[a]\nwhen = x\ngaps.outer = 3\ngaps = 9\n").profiles[1].settings.gapsOuter == 3)
check.that("should read the commands to run", read.profiles[1].settings.onEnter == "~/bin/desk-on.sh" and read.profiles[1].settings.onLeave == "~/bin/desk-off.sh")
check.that("should leave a keep setting out", read.profiles[2].settings.theme == nil)

local broken = displays.parse("[a]\nwhen = x\nthis is not a setting\nlayout = grid\ncolour = red\n")
check.that("should report a line it can't read, with its number", broken.problems[1] == "line 3: expected name = value")
check.that("should report an invalid value", broken.problems[2] == "line 4: layout must be tiles, tabs or keep")
check.that("should report an unknown setting by name", broken.problems[3] == "line 5: unknown setting colour")
check.that("should report a setting outside any profile",
  displays.parse("layout = tiles\n").problems[1] == "line 1: layout is outside a [profile]")
check.that("should report a profile without when", displays.parse("[a]\nlayout = tiles\n").problems[1] == "profile a has no when line")
check.that("should report a gap that isn't a whole number", displays.parse("[a]\nwhen = x\ngaps = -2\n").problems[1] == "line 3: gaps must be a whole number")
check.that("should read no profiles without a file", #displays.parse(nil).profiles == 0)

-- Matching.
local builtIn = { name = "Built-in Retina Display", builtin = true }
local dell = { name = "DELL U2723QE", builtin = false }
check.that("should pick the first profile that matches, in file order",
  displays.pick(displays.parse("[one]\nwhen = laptop, dell\n[two]\nwhen = laptop, dell\n").profiles, { builtIn, dell }).name == "one")
check.that("should match when by part of a display's name, ignoring case",
  displays.pick(displays.parse("[d]\nwhen = u2723\n").profiles, { dell }).name == "d")
check.that("should match laptop when the built-in screen is alone", displays.pick(read.profiles, { builtIn }).name == "laptop")
check.that("should not match built-in only with another display plugged in",
  displays.pick(displays.parse("[l]\nwhen = built-in only\n").profiles, { builtIn, dell }) == nil)
check.that("should not match when a screen in when isn't plugged in", displays.pick(read.profiles, { dell }) == nil)
check.that("should match when exactly the screens in when are plugged in", displays.pick(read.profiles, { builtIn, dell }).name == "desk")
check.that("should not match when another screen is plugged in too",
  displays.pick(displays.parse("[d]\nwhen = DELL\n").profiles, { builtIn, dell }) == nil)
local secondDell = { name = "DELL P2422H", builtin = false }
check.that("should match two screens of one make to two names in when",
  displays.pick(displays.parse("[two]\nwhen = DELL, DELL\n").profiles, { dell, secondDell }).name == "two"
  and displays.pick(displays.parse("[two]\nwhen = DELL, DELL\n").profiles, { dell, builtIn }) == nil)
check.that("should pick nothing when no profile matches", displays.pick(read.profiles, { { name = "LG HDR 4K" }, builtIn }) == nil)

-- Applying.
local desk, laptop = read.profiles[1], read.profiles[2]
local changes = displays.changes(nil, desk)
check.that("should list only the settings a profile changes", changes.layout == "tiles" and changes.font == 15 and changes.quiet == "off")
check.that("should leave a keep setting out of the changes", displays.changes(nil, laptop).theme == nil)
local switching = displays.changes(desk, laptop)
check.that("should undo the old profile's settings that the new one doesn't set", switching.font == "default" and switching.bar == "default")
check.that("should apply the new profile's settings over the old ones", switching.layout == "tabs" and switching.gapsOuter == 4)
check.that("should run the old profile's leave command", switching.onLeave == "~/bin/desk-off.sh")
check.that("should not run the old profile's enter command again", switching.onEnter == nil)
check.that("should undo everything when no profile matches any more", displays.changes(desk, nil).layout == "default")

local toml = displays.aerospaceGaps({ gapsInner = 8, gapsOuter = 12 })
check.that("should set AeroSpace's inner gaps", toml:find("inner.horizontal = 8", 1, true) ~= nil and toml:find("inner.vertical = 8", 1, true) ~= nil)
check.that("should set AeroSpace's outer gaps on three sides", toml:find("outer.left = 12", 1, true) ~= nil and toml:find("outer.bottom = 12", 1, true) ~= nil)
check.that("should keep the notch's top gap on the built-in screen and clear the bar elsewhere",
  toml:find('outer.top = [{ monitor."built-in" = 14 }, 48]', 1, true) ~= nil)
check.that("should write no gaps for a profile that sets none", displays.aerospaceGaps({}) == nil)

-- Noticing an edit to the profile in use.
check.that("should see a profile as unchanged when its settings are the same",
  displays.sameSettings({ layout = "tabs", gapsInner = 4 }, { gapsInner = 4, layout = "tabs" }))
check.that("should see a profile as changed when a setting's value changed", not displays.sameSettings({ gapsInner = 4 }, { gapsInner = 6 }))
check.that("should see a profile as changed when a setting was added", not displays.sameSettings({ layout = "tabs" }, { layout = "tabs", font = 15 }))
check.that("should see a profile as changed when a setting was removed", not displays.sameSettings({ layout = "tabs", font = 15 }, { layout = "tabs" }))
check.that("should see no settings as the same as no settings", displays.sameSettings(nil, {}))

-- Choosing by hand.
local state = displays.choose({}, laptop, { builtIn, dell })
check.that("should hold a profile picked by hand", displays.current(state, read.profiles, { builtIn, dell }).name == "laptop")
check.that("should drop the hand-picked profile once the displays change",
  displays.current(state, read.profiles, { builtIn }).name == "laptop" and displays.current(state, read.profiles, { builtIn }).picked ~= true)
check.that("should follow the displays when follow is picked", displays.current(displays.choose(state, nil, { builtIn, dell }), read.profiles, { builtIn, dell }).name == "desk")

-- The card's rows.
local function hints(rows)
  local found = {}
  for _, row in ipairs(rows) do found[row.id] = row.hint end
  return found
end
local function ids(rows)
  local found = {}
  for _, row in ipairs(rows) do found[#found + 1] = row.id end
  return table.concat(found, " ")
end
local emptyRows = displays.rows({}, {}, { builtIn, dell })
check.that("should give only the save and file rows when there are no profiles", ids(emptyRows) == "save file")
check.that("should hint with examples on the file row when there are no profiles", hints(emptyRows).file == "with examples")
check.that("should hint editing here on the save row when no profile matches the displays", hints(emptyRows).save == "then edit it here")
local cardProfiles = displays.parse("[laptop]\nwhen = built-in only\nlayout = tabs\ngaps = 4\n\n[dell]\nwhen = laptop, DELL\n").profiles
local cardRows = displays.rows(cardProfiles, { active = "dell" }, { builtIn, dell })
check.that("should hint already on the save row when a profile matches the displays", hints(cardRows).save == "already: dell")
check.that("should list the profiles in file order before follow, save and file",
  ids(cardRows) == "profile:laptop profile:dell follow save file")
check.that("should hint in use on the profile in use", hints(cardRows)["profile:dell"] == "in use")
check.that("should hint in use and picked on a profile picked by hand",
  hints(displays.rows(cardProfiles, { active = "dell", picked = true }, { builtIn, dell }))["profile:dell"] == "in use · picked")
check.that("should hint its settings on a profile not in use", hints(cardRows)["profile:laptop"] == "tabs · gaps 4")
check.that("should hint applies on save on the file row when there are profiles", hints(cardRows).file == "applies on save")

-- The log of each check.
local loggedAt = os.time({ year = 2026, month = 11, day = 22, hour = 11, min = 50, sec = 3 })
check.that("should format a check's line as date, time, reason and result",
  displays.logLine(loggedAt, "saved", "applied laptop") == "2026-11-22 11:50:03  saved     applied laptop")
check.that("should format the load's line without a result", displays.logLine(loggedAt, "load") == "2026-11-22 11:50:03  load")
check.that("should add the line at the end of the log", displays.appendLog("one\ntwo\n", "three") == "one\ntwo\nthree\n")
check.that("should start the log with the line when there's none", displays.appendLog(nil, "one") == "one\n")
local fullLog = {}
for index = 1, 200 do fullLog[index] = "line " .. index end
local trimmed = displays.appendLog(table.concat(fullLog, "\n") .. "\n", "line 201")
local trimmedCount = select(2, trimmed:gsub("\n", ""))
check.that("should keep only the last 200 lines when the log is full",
  trimmedCount == 200 and trimmed:sub(1, 7) == "line 2\n" and trimmed:sub(-9) == "line 201\n")

-- AeroSpace's layout command.
local layoutArgs = table.concat(displays.layoutArgs("3", "tabs"), " ")
check.that("should lay out a whole workspace from its root as tabs", layoutArgs == "layout --workspace 3 --root accordion")
check.that("should lay out a whole workspace from its root as tiles", table.concat(displays.layoutArgs("3", "tiles"), " ") == "layout --workspace 3 --root tiles")

-- Profile names.
check.that("should read a profile named with a space", displays.parse("[Home desk]\nwhen = x\n").profiles[1].name == "Home desk")
check.that("should read a profile named with Turkish letters", displays.parse("[Ev masası]\nwhen = x\n").profiles[1].name == "Ev masası")
check.that("should trim the spaces around a profile's name", displays.parse("[ Home desk ]\nwhen = x\n").profiles[1].name == "Home desk")
check.that("should report the line when a profile's name has a ]",
  displays.parse("[a]b]\nwhen = x\n").problems[1] == "line 1: a profile's name can't have [, ] or #")
check.that("should report the line when a profile's name has a #",
  displays.parse("[a#b]\nwhen = x\n").problems[1] == "line 1: a profile's name can't have [, ] or #")
check.that("should report a second profile with the same name, ignoring case",
  displays.parse("[Laptop]\nwhen = x\n\n[laptop]\nwhen = y\n").problems[1] == "line 4: a profile named laptop is already on line 1")

-- Displays seen.
local seen = displays.recordSeen({}, { dell, builtIn }, "2026-11-20")
check.that("should record a display seen for the first time, with the date",
  seen[1].name == "DELL U2723QE" and seen[1].last == "2026-11-20" and seen[1].now == true)
local again = displays.recordSeen(seen, { dell }, "2026-11-22")
local dellEntries = 0
for _, entry in ipairs(again) do if entry.name == dell.name then dellEntries = dellEntries + 1 end end
check.that("should keep one entry for a display seen again", dellEntries == 1)
check.that("should move a display's date when it's seen again", again[1].last == "2026-11-22")
check.that("should mark a display that isn't plugged in any more as not now", again[2].name == builtIn.name and again[2].now == false)
check.that("should read back the seen list it writes",
  displays.parseSeen(displays.formatSeen(again))[2].last == "2026-11-20" and displays.parseSeen(displays.formatSeen(again))[2].builtin == true)
local namesNow = table.concat(displays.nameLines(seen), "\n")
check.that("should leave out seen before when every display is plugged in", not check.contains(namesNow, "Seen before"))
local namesLater = table.concat(displays.nameLines(again), "\n")
check.that("should list a display that isn't plugged in under seen before, with its date",
  check.contains(namesLater, "Seen before:\n  Built-in Retina Display") and check.contains(namesLater, "last seen 2026-11-20"))
check.that("should mark the built-in display", check.contains(namesNow, "(built-in)"))
check.that("should say to plug a display in when none was seen", check.contains(table.concat(displays.nameLines({}), "\n"), "plug"))

-- The starter file.
local starter = displays.starter(seen)
check.that("should give no profiles in the starter file", #displays.parse(starter).profiles == 0)
check.that("should give no problems in the starter file", #displays.parse(starter).problems == 0)
check.that("should name each plugged-in display in the starter file", check.contains(starter, "#   DELL U2723QE"))
check.that("should still be a valid starter file when no display was seen",
  #displays.parse(displays.starter({})).problems == 0 and check.contains(displays.starter({}), "plug"))

-- Saving the displays as a profile.
local added, name = displays.addProfile("", { builtIn, dell }, {}, "2026-11-22")
local addedRead = displays.parse(added)
check.that("should add a profile whose when is exactly the screens plugged in",
  table.concat(addedRead.profiles[1].when, ", ") == "laptop, DELL U2723QE")
check.that("should name the profile after the external display", name == "dell")
check.that("should add a profile that matches the displays", displays.pick(addedRead.profiles, { builtIn, dell }).name == "dell")
check.that("should put a comment naming the displays above the profile",
  check.contains(added, "# Saved 2026-11-22 for: laptop, DELL U2723QE. Rename it to anything.\n[dell]"))
local laptopOnly = displays.parse((displays.addProfile("", { builtIn }, {}, "2026-11-22")))
check.that("should name a profile for the built-in display alone laptop", laptopOnly.profiles[1].name == "laptop")
check.that("should use laptop for the built-in display alone", table.concat(laptopOnly.profiles[1].when, ", ") == "laptop")
local _, taken = displays.addProfile("", { builtIn, dell }, displays.parse("[Dell]\nwhen = x\n").profiles, "2026-11-22")
check.that("should number the name when it's taken", taken == "dell 2")
local _, lg = displays.addProfile("", { { name = "LG HDR 4K (2)", builtin = false } }, {}, "2026-11-22")
check.that("should name a profile with the display's first word in lowercase", lg == "lg")
local kept = displays.parse((displays.addProfile("[laptop]\nwhen = built-in only\ngaps = 4", { builtIn, dell }, {}, "2026-11-22")))
check.that("should keep the profiles already in the file", kept.profiles[1].name == "laptop" and kept.profiles[1].settings.gapsInner == 4)
check.that("should start the added profile on its own line when the file has no last newline",
  #kept.problems == 0 and kept.profiles[2].name == "dell")

-- The profile editor: stepping a value.
local THEMES = { "nord", "tokyo-night" }
local function stepped(settings, id, direction) return displays.step(settings, id, direction, THEMES) end
local layoutRun, layoutSettings = {}, {}
for index = 1, 4 do
  layoutSettings = stepped(layoutSettings, "layout", 1)
  layoutRun[index] = tostring(layoutSettings.layout)
end
check.that("should step the layout through tiles and tabs, then back to keep", table.concat(layoutRun, " ") == "tiles tabs nil tiles")
check.that("should step the gaps between windows to the next value", stepped({ gapsInner = 4 }, "gaps.inner", 1).gapsInner == 6)
check.that("should stop the gaps at the largest value", stepped({ gapsInner = 24 }, "gaps.inner", 1).gapsInner == 24)
check.that("should stop the gaps at keep when stepped left", stepped({}, "gaps.inner", -1).gapsInner == nil)
check.that("should step a gap the list doesn't have to the nearest one that way",
  stepped({ gapsInner = 5 }, "gaps.inner", 1).gapsInner == 6 and stepped({ gapsInner = 5 }, "gaps.inner", -1).gapsInner == 4)
check.that("should step the theme through the themes given, after keep",
  stepped({}, "theme", 1).theme == "nord" and stepped({ theme = "nord" }, "theme", 1).theme == "tokyo-night")
local apartRight = stepped({ gapsInner = 8, gapsOuter = 12 }, "gaps", 1)
check.that("should set all gaps to the step after the larger when stepped right", apartRight.gapsInner == 16 and apartRight.gapsOuter == 16)
local apartLeft = stepped({ gapsInner = 8, gapsOuter = 12 }, "gaps", -1)
check.that("should set all gaps to the step before the smaller when stepped left", apartLeft.gapsInner == 6 and apartLeft.gapsOuter == 6)
local edges = stepped({ gapsInner = 8, gapsOuter = 8 }, "gaps.outer", 1)
check.that("should change the gaps at the edges and keep the gaps between windows", edges.gapsOuter == 10 and edges.gapsInner == 8)
local given = { gapsInner = 4 }
stepped(given, "gaps.inner", 1)
check.that("should leave the settings it was given unchanged", given.gapsInner == 4)

-- The profile editor: its rows.
local function editHints(settings)
  local found = {}
  for _, row in ipairs(displays.editRows(settings)) do found[row.id] = row.hint end
  return found
end
local function gapHints(inner, outer)
  local found = {}
  for _, row in ipairs(displays.gapRows(inner, outer)) do found[row.id] = row.hint end
  return found
end
local editHint = editHints({ layout = "tabs", gapsInner = 4, gapsOuter = 4 })
check.that("should show each setting's value", check.contains(editHint.layout, "tabs") and check.contains(gapHints(4, 4).gaps, "4"))
check.that("should show keep for a setting the profile doesn't set", check.contains(editHint.theme, "keep"))
check.that("should show both values on all gaps when they differ", check.contains(gapHints(8, 12).gaps, "8 · 12"))
check.that("should say the font shows in new terminal windows", check.contains(editHint.font, "new windows"))

-- The profile editor: writing the file.
local EDITED = [[
# [desk]
# when   = DELL U2723QE
# layout = tiles

# Saved 2026-11-22 for: DELL U2723QE. Rename it to anything.
[dell]
when   = DELL U2723QE
layout = tiles          # desk default
# gaps   = 10
# font   = 15

[laptop]
when   = built-in only
layout = tabs
gaps   = 4
]]
local function written(before, after) return displays.writeSettings(EDITED, "dell", before, after) end
local dellBefore = displays.parse(EDITED).profiles[1].settings
local function withChange(change)
  local after = {}
  for key, value in pairs(dellBefore) do after[key] = value end
  for key, value in pairs(change) do after[key] = value end
  return after
end
check.that("should replace a setting's value and keep its comment",
  check.contains(written(dellBefore, withChange({ layout = "tabs" })), "layout = tabs          # desk default"))
check.that("should remove the # from a setting saved as a comment",
  check.contains(written(dellBefore, withChange({ font = 16 })), "\nfont   = 16\n"))
check.that("should add a setting the section lacks after its last line",
  check.contains(written(dellBefore, withChange({ theme = "nord" })), "# font   = 15\ntheme = nord\n\n[laptop]"))
local noLayout = withChange({})
noLayout.layout = nil
check.that("should remove a setting's line when it's set to keep", not check.contains(written(dellBefore, noLayout), "layout = tiles          # desk default"))
check.that("should leave another section's same setting alone",
  check.contains(written(dellBefore, withChange({ gapsInner = 6, gapsOuter = 6 })), "[laptop]\nwhen   = built-in only\nlayout = tabs\ngaps   = 4\n"))
check.that("should leave the commented example sections alone",
  check.contains(written(dellBefore, withChange({ layout = "tabs" })), "# [desk]\n# when   = DELL U2723QE\n# layout = tiles\n"))
local equalGaps = written(dellBefore, withChange({ gapsInner = 12, gapsOuter = 12 }))
check.that("should write one gaps line when the gaps are equal",
  check.contains(equalGaps, "gaps   = 12") and not check.contains(equalGaps, "gaps.inner"))
local apartGaps = displays.writeSettings("[a]\nwhen = x\ngaps = 10\n", "a", { gapsInner = 10, gapsOuter = 10 }, { gapsInner = 8, gapsOuter = 12 })
check.that("should write gaps.inner and gaps.outer and remove the gaps line when they differ",
  apartGaps == "[a]\nwhen = x\ngaps.inner = 8\ngaps.outer = 12\n")
check.that("should write only gaps.outer when the gaps between windows are keep",
  displays.writeSettings("[a]\nwhen = x\n", "a", {}, { gapsOuter = 12 }) == "[a]\nwhen = x\ngaps.outer = 12\n")
local readBack = displays.parse(written(dellBefore, withChange({ layout = "tabs", gapsInner = 8, gapsOuter = 12, theme = "nord", font = 16 })))
local dellBack = readBack.profiles[1].settings
check.that("should give a file that reads back as the edited profile",
  #readBack.problems == 0 and dellBack.layout == "tabs" and dellBack.gapsInner == 8 and dellBack.gapsOuter == 12
  and dellBack.theme == "nord" and dellBack.font == 16)

-- Deleting a profile.
local MANY = [[
# [desk]
# when   = DELL U2723QE

[laptop]
when = built-in only
gaps = 4

# Saved 2026-11-22 for: the built-in display. Rename it to anything.
[laptop 2]
when = built-in only
# layout = tiles

[dell]
when = DELL
]]
local deleted = displays.removeProfile(MANY, "laptop 2")
check.that("should remove the deleted profile's section", not check.contains(deleted, "[laptop 2]") and #displays.parse(deleted).profiles == 2)
check.that("should remove the saved comment right above the deleted profile", not check.contains(deleted, "# Saved 2026-11-22"))
check.that("should leave the other sections and the commented examples alone",
  check.contains(deleted, "# [desk]\n# when   = DELL U2723QE\n") and check.contains(deleted, "[laptop]\nwhen = built-in only\ngaps = 4\n")
  and check.contains(deleted, "[dell]\nwhen = DELL\n"))
check.that("should leave one blank line between the sections around a deleted profile", check.contains(deleted, "gaps = 4\n\n[dell]"))
check.that("should leave the text unchanged when no profile has the name", displays.removeProfile(MANY, "nowhere") == MANY)
local bareRows = displays.rows(displays.parse("[bare]\nwhen = x\n").profiles, {}, { builtIn })
check.that("should hint nothing set on a profile that sets nothing", bareRows[1].hint == "nothing set")

-- Renaming a profile.
local NAMED = "[laptop]\nwhen = built-in only\n\n[dell]   # the desk\nwhen = DELL\n"
check.that("should change the section's name line when a profile is renamed",
  displays.renameProfile(NAMED, "dell", "Home desk"):find("[Home desk]", 1, true) ~= nil
  and displays.parse(displays.renameProfile(NAMED, "dell", "Home desk")).profiles[2].name == "Home desk")
check.that("should keep the comment after a renamed profile's name line", check.contains(displays.renameProfile(NAMED, "dell", "Home desk"), "[Home desk]   # the desk"))
check.that("should leave the other sections alone when a profile is renamed", check.contains(displays.renameProfile(NAMED, "dell", "Home desk"), "[laptop]\nwhen = built-in only\n"))
check.that("should leave the text unchanged when no profile has the old name", displays.renameProfile(NAMED, "nowhere", "x") == NAMED)
local namedProfiles = displays.parse(NAMED).profiles
check.that("should take a typed name without the spaces around it", displays.checkName("  Home desk ", namedProfiles, "dell") == "Home desk")
check.that("should keep the current name when the typed name is empty", displays.checkName("   ", namedProfiles, "dell") == "dell")
check.that("should refuse a name with [, ] or #", select(2, displays.checkName("a#b", namedProfiles, "dell")) == "a profile's name can't have [, ] or #")
check.that("should refuse a name another profile has, ignoring case", select(2, displays.checkName("Laptop", namedProfiles, "dell")) == "Laptop is taken")
check.that("should take the profile's own name in another case", displays.checkName("Dell", namedProfiles, "dell") == "Dell")
local nameRow = displays.editRows({}, "dell")[1]
check.that("should put the name first in the editor, hinting it", nameRow.id == "name" and nameRow.hint == "dell  ›")

-- Choosing when a profile is used.
local function when(text) return displays.parseWhen(text) end
check.that("should add a display to when when it's ticked", table.concat(displays.toggleWhen(when("DELL U2723QE"), "LG").items, ", ") == "DELL U2723QE, LG")
check.that("should remove a display from when when it's unticked", table.concat(displays.toggleWhen(when("DELL U2723QE, LG"), "lg").items, ", ") == "DELL U2723QE")
check.that("should add the laptop screen and keep the displays when it's ticked",
  table.concat(displays.toggleWhen(when("DELL U2723QE"), "laptop").items, ", ") == "DELL U2723QE, laptop")
check.that("should read built-in only in the picker as the laptop screen", when("built-in only").items[1] == "laptop")
local seenList = { { name = "DELL U2723QE", now = true, last = "2026-11-22" }, { name = "Epson EB-W49", now = false, last = "2026-11-18" },
  { name = "Built-in Retina Display", builtin = true, now = true, last = "2026-11-22" } }
local pickRows = displays.whenRows(when("DELL U2723QE, projector"), seenList)
local function pickRow(id)
  for _, row in ipairs(pickRows) do if row.id == id then return row end end
end
check.that("should tick the displays in when, and hint plugged in or the date last seen",
  pickRow("display:DELL U2723QE").icon ~= pickRow("display:Epson EB-W49").icon and pickRow("display:DELL U2723QE").hint == "plugged in"
  and pickRow("display:Epson EB-W49").hint == "last seen 2026-11-18" and pickRow("display:Built-in Retina Display") == nil)
check.that("should offer the laptop screen as a tick of its own, unticked when it isn't in when",
  pickRow("display:laptop").label == "Laptop screen" and pickRow("display:laptop").icon == pickRow("display:Epson EB-W49").icon)
check.that("should list a typed part omv hasn't seen, ticked and hinted typed",
  pickRow("display:projector").hint == "typed" and pickRow("display:projector").icon == pickRow("display:DELL U2723QE").icon)
check.that("should add a typed part, ticked", displays.addWhen(when("DELL U2723QE"), "  projector ").items[2] == "projector")
check.that("should say to pick one when done with nothing ticked", select(2, displays.doneWhen(when(""))) == "pick at least one display")
check.that("should replace the when line when when changed",
  check.contains(displays.writeSettings("[a]\nwhen = x\nlayout = tabs\n", "a", { when = "x" }, { when = "DELL U2723QE, LG" }), "[a]\nwhen = DELL U2723QE, LG\nlayout = tabs\n"))
local whenEditRows = displays.editRows({ when = "DELL U2723QE" }, "dell", "matches now")
check.that("should hint the when and its status on the When row", whenEditRows[2].id == "when" and whenEditRows[2].hint == "DELL U2723QE · matches now  ›")
check.that("should leave count out of the editor", not check.contains(table.concat((function() local ids = {} for _, row in ipairs(whenEditRows) do ids[#ids + 1] = row.id end return ids end)(), " "), "count"))

-- Whether a profile is used with the displays plugged in.
local matchProfiles = displays.parse("[laptop]\nwhen = built-in only\n\n[dell]\nwhen = laptop, DELL\n\n[desk]\nwhen = laptop, DELL\n").profiles
check.that("should say matches now for the first profile to match", displays.matchStatus("dell", matchProfiles, { builtIn, dell }) == "matches now")
check.that("should name the profile that comes first when another matches earlier",
  displays.matchStatus("desk", matchProfiles, { builtIn, dell }) == "matches now, but dell comes first")
check.that("should say not plugged in for a profile that doesn't match", displays.matchStatus("laptop", matchProfiles, { builtIn, dell }) == "not plugged in")

-- Bringing back a deleted profile.
local afterDelete, removedBlock = displays.removeProfile(MANY, "laptop 2")
check.that("should put a deleted profile back where it was when the file hasn't changed",
  displays.restoreProfile(afterDelete, afterDelete, MANY, removedBlock) == MANY)
local changedSince = afterDelete .. "\n[new]\nwhen = x\n"
local restoredAtEnd = displays.restoreProfile(changedSince, afterDelete, MANY, removedBlock)
check.that("should add a deleted profile at the end when the file changed since",
  check.contains(restoredAtEnd, "[new]\nwhen = x\n\n# Saved 2026-11-22 for: the built-in display. Rename it to anything.\n[laptop 2]") and #displays.parse(restoredAtEnd).problems == 0)
local undoRows = displays.rows(displays.parse(afterDelete).profiles, { deleted = { name = "laptop 2", index = 2 } }, { builtIn })
check.that("should show Bring back in place of a deleted profile", undoRows[2].id == "undo" and undoRows[2].label == "Bring back laptop 2")
local againRows = displays.rows(displays.parse(afterDelete .. "\n[laptop 2]\nwhen = laptop\n").profiles, { deleted = { name = "laptop 2", index = 2 } }, { builtIn })
local offered = false
for _, row in ipairs(againRows) do if row.id == "undo" then offered = true end end
check.that("should leave out Bring back when a profile has the deleted name again", not offered)

-- Profiles: workspaces, apps, screens' gaps and the fallback.
local PROFILE = [[
[desk]
when        = laptop, DELL, LG
workspace.1 = DELL, tiles, Zed
workspace.2 = DELL, tabs, Helium, Arc
workspace.4 = default, Slack
open.2      = Helium
gaps.DELL   = 10
gaps.laptop.outer = 4
theme       = tokyo-night

[everywhere]
when        = any
workspace.1 = default, Zed
]]
local desk = displays.parse(PROFILE).profiles[1]
check.that("should read no problems in a profile with workspaces", #displays.parse(PROFILE).problems == 0)
check.that("should read a workspace's screen, layout and apps",
  desk.settings.workspaces["2"].screen == "DELL" and desk.settings.workspaces["2"].layout == "tabs"
  and table.concat(desk.settings.workspaces["2"].apps, ",") == "Helium,Arc")
check.that("should read a workspace without a layout", desk.settings.workspaces["1"].layout == "tiles" and desk.settings.workspaces["4"].layout == nil)
check.that("should read default as no screen of the profile's own", desk.settings.workspaces["4"].screen == nil and desk.settings.workspaces["4"].apps[1] == "Slack")
check.that("should read the app to open when a workspace is empty", desk.settings.open["2"] == "Helium")
check.that("should read a screen's gaps, both kinds", desk.settings.screenGaps["DELL"].inner == 10 and desk.settings.screenGaps["DELL"].outer == 10)
check.that("should read one kind of a screen's gaps", desk.settings.screenGaps["laptop"].outer == 4 and desk.settings.screenGaps["laptop"].inner == nil)
check.that("should keep gaps.inner meaning every screen", displays.parse("[a]\nwhen = x\ngaps.inner = 6\n").profiles[1].settings.gapsInner == 6)
check.that("should report a workspace outside 1 to 9",
  displays.parse("[a]\nwhen = x\nworkspace.12 = main\n").problems[1] == "line 3: a workspace is a number from 1 to 9")
check.that("should report an app placed on two workspaces in one profile",
  displays.parse("[a]\nwhen = x\nworkspace.1 = main, Zed\nworkspace.2 = main, Zed\n").problems[1] == "line 4: Zed is already on workspace 1")
check.that("should report a screen's gaps that aren't a whole number",
  displays.parse("[a]\nwhen = x\ngaps.DELL = wide\n").problems[1] == "line 3: gaps.DELL must be a whole number")

local fallbackProfiles = displays.parse(PROFILE).profiles
check.that("should mark when = any as the fallback", fallbackProfiles[2].any == true)
check.that("should pick the fallback when no other profile matches", displays.pick(fallbackProfiles, { builtIn }).name == "everywhere")
check.that("should pick a matching profile over the fallback, even after it in the file",
  displays.pick(displays.parse("[e]\nwhen = any\n\n[l]\nwhen = laptop\n").profiles, { builtIn }).name == "l")
check.that("should report a second when = any with the first one's line",
  displays.parse("[a]\nwhen = any\n\n[b]\nwhen = any\n").problems[1] == "line 5: only one profile can be when = any; the first is on line 2")

check.that("should see nested settings as the same when they are",
  displays.sameSettings({ workspaces = { ["1"] = { screen = "DELL", apps = { "Zed" } } } }, { workspaces = { ["1"] = { screen = "DELL", apps = { "Zed" } } } }))
check.that("should see a changed app inside a workspace as a change",
  not displays.sameSettings({ workspaces = { ["1"] = { apps = { "Zed" } } } }, { workspaces = { ["1"] = { apps = { "Arc" } } } }))

check.that("should read the profiles file when it exists",
  displays.pathFor(function(path) return path:match("/profiles$") ~= nil end):match("/profiles$") ~= nil)
check.that("should read the old displays file when only it exists",
  displays.pathFor(function(path) return path:match("/displays$") ~= nil end):match("/displays$") ~= nil)
check.that("should use the profiles file when neither exists", displays.pathFor(function() return false end):match("/profiles$") ~= nil)

-- Applying a profile: layouts per workspace, app rules, moving open windows, gaps per screen.
local plan = displays.layoutPlan({}, { layout = "tiles", workspaces = { ["2"] = { layout = "tabs", apps = {} } } }, { "1", "2", "3" })
check.that("should give each workspace the profile's layout", plan["1"] == "tiles" and plan["3"] == "tiles")
check.that("should give a workspace its own layout over the profile's", plan["2"] == "tabs")
local back = displays.layoutPlan({ workspaces = { ["2"] = { layout = "tabs", apps = {} } } }, {}, { "1", "2" })
check.that("should put tiles back on a workspace the old profile laid out", back["2"] == "tiles" and back["1"] == nil)

local rules = displays.appRules({ workspaces = { ["1"] = { apps = { "Zed" } }, ["2"] = { apps = { "Helium", "Visual Studio Code" } } } })
check.that("should write one rule per app, in workspace order",
  rules == "[[on-window-detected]]\nif.app-name-regex-substring = '(?i)^Zed$'\nrun = 'move-node-to-workspace 1'\n\n"
    .. "[[on-window-detected]]\nif.app-name-regex-substring = '(?i)^Helium$'\nrun = 'move-node-to-workspace 2'\n\n"
    .. "[[on-window-detected]]\nif.app-name-regex-substring = '(?i)^Visual Studio Code$'\nrun = 'move-node-to-workspace 2'\n")
check.that("should write no rules for a profile without apps", displays.appRules({}) == "")

local WINDOWS = "11|Zed|3\n12|Helium|2\n13|Ghostty|1\n14|Ghostty|4\n15|Arc|5\n"
local moves = displays.appMoves({ workspaces = { ["1"] = { apps = { "zed", "Ghostty" } }, ["2"] = { apps = { "Helium", "Arc" } } } }, WINDOWS)
local function moved(id) for _, move in ipairs(moves) do if move.id == id then return move.to end end end
check.that("should move an open window of a listed app to its workspace", moved("11") == "1" and moved("15") == "2")
check.that("should leave a window already on its workspace", moved("12") == nil)
check.that("should leave an app whose windows are on several workspaces", moved("13") == nil and moved("14") == nil)

local laptopScreen = { name = "Built-in Retina Display", builtin = true, main = false, x = -1512 }
local dellScreen = { name = "DELL U2723QE", main = true, x = 0 }
local lgScreen = { name = "LG HDR 4K", main = false, x = 2560 }
local perScreen = displays.aerospaceGaps({ screenGaps = { DELL = { inner = 12, outer = 12 }, laptop = { outer = 4 } } }, { laptopScreen, dellScreen })
check.that("should give a screen its own gaps between windows, the rest omv's",
  check.contains(perScreen, 'inner.horizontal = [{ monitor."DELL" = 12 }, 10]'))
check.that("should give each screen its own edge gaps, the rest omv's",
  check.contains(perScreen, 'outer.left = [{ monitor."DELL" = 12 }, { monitor."built-in" = 4 }, 10]'))
check.that("should keep the notch's top gap on the laptop screen and clear the bar on the others",
  check.contains(perScreen, 'outer.top = [{ monitor."built-in" = 14 }, { monitor."DELL" = 48 }, 46]'))
local nth = displays.aerospaceGaps({ gapsInner = 6, screenGaps = { ["screen 2"] = { inner = 2 } } }, { laptopScreen, dellScreen, lgScreen })
check.that("should find screen 2 by its name, the leftmost screen that isn't the main one",
  check.contains(nth, 'inner.horizontal = [{ monitor."Built\\\\-in Retina Display" = 2 }, 6]'))
check.that("should leave out a screen's gaps when that screen isn't plugged in",
  not check.contains(displays.aerospaceGaps({ screenGaps = { ["screen 3"] = { inner = 2 } }, gapsInner = 6 }, { dellScreen }), "monitor"))

-- The grouped editor: workspaces, screens, and settings for everywhere.
check.that("should write a workspace's line: screen, layout, apps", displays.workspaceLine({ screen = "DELL", layout = "tabs", apps = { "Helium", "Arc" } }) == "DELL, tabs, Helium, Arc")
check.that("should write default for a workspace without a screen of its own", displays.workspaceLine({ apps = { "Slack" } }) == "default, Slack")
check.that("should write no line for a workspace the profile leaves alone", displays.workspaceLine({ apps = {} }) == nil and displays.workspaceLine(nil) == nil)

local WS_FILE = "[desk]\nwhen = laptop, DELL\nworkspace.2 = DELL, Helium\n"
local wsBefore = displays.parse(WS_FILE).profiles[1].settings
local function wsWritten(change)
  local after = {}
  for key, value in pairs(wsBefore) do after[key] = value end
  for key, value in pairs(change) do after[key] = value end
  return displays.writeSettings(WS_FILE, "desk", wsBefore, after)
end
check.that("should change a workspace's line", check.contains(wsWritten({ workspaces = { ["2"] = { screen = "DELL", layout = "tabs", apps = { "Helium" } } } }), "workspace.2 = DELL, tabs, Helium\n"))
check.that("should add a workspace's line",
  check.contains(wsWritten({ workspaces = { ["2"] = { screen = "DELL", apps = { "Helium" } }, ["4"] = { apps = { "Slack" } } } }), "workspace.4 = default, Slack\n"))
check.that("should remove a workspace's line when the profile leaves it alone", not check.contains(wsWritten({ workspaces = {} }), "workspace.2"))
check.that("should add and remove the app opened when a workspace is empty",
  check.contains(wsWritten({ open = { ["2"] = "Helium" } }), "open.2 = Helium\n")
  and not check.contains(displays.writeSettings("[a]\nwhen = x\nopen.2 = Helium\n", "a", { open = { ["2"] = "Helium" } }, { open = {} }), "open.2"))
check.that("should write one line for a screen's equal gaps", check.contains(wsWritten({ screenGaps = { DELL = { inner = 8, outer = 8 } } }), "gaps.DELL = 8\n"))
local apartScreen = wsWritten({ screenGaps = { DELL = { inner = 8, outer = 12 } } })
check.that("should write each kind of a screen's gaps when they differ",
  check.contains(apartScreen, "gaps.DELL.inner = 8\n") and check.contains(apartScreen, "gaps.DELL.outer = 12\n") and not check.contains(apartScreen, "gaps.DELL = "))
local backRead = displays.parse(wsWritten({ workspaces = { ["1"] = { screen = "laptop", apps = { "Zed" } } }, open = { ["1"] = "Zed" }, screenGaps = { DELL = { inner = 8, outer = 12 } } }))
check.that("should give a file that reads back as the edited workspaces, apps and gaps",
  #backRead.problems == 0 and backRead.profiles[1].settings.workspaces["1"].screen == "laptop"
  and backRead.profiles[1].settings.open["1"] == "Zed" and backRead.profiles[1].settings.screenGaps["DELL"].outer == 12)

local grouped = displays.editRows({ when = "laptop, DELL", workspaces = { ["2"] = { screen = "DELL", layout = "tabs", apps = { "Helium", "Arc" } } },
  screenGaps = { DELL = { inner = 10, outer = 10 } }, theme = "nord" }, "desk", "matches now", { "1", "2" })
local function groupedRow(id) for _, row in ipairs(grouped) do if row.id == id then return row end end end
check.that("should list each workspace under Workspaces", groupedRow("workspace:1").group == "Workspaces" and groupedRow("workspace:2").group == "Workspaces")
check.that("should sum up a workspace's screen, layout and apps", groupedRow("workspace:2").hint == "DELL · tabs · Helium, Arc  ›")
check.that("should mark a workspace the profile leaves alone default", groupedRow("workspace:1").hint == "default  ›")
check.that("should list all screens and each screen in when under Screens",
  groupedRow("screen:all").group == "Screens" and groupedRow("screen:laptop").group == "Screens" and groupedRow("screen:DELL").hint == "gaps 10  ›")
check.that("should mark a screen without gaps of its own", groupedRow("screen:laptop").hint == "omv's gaps  ›")
check.that("should put the layout, theme and the rest under Everywhere", groupedRow("theme").group == "Everywhere" and groupedRow("layout").group == "Everywhere")

local wsRows = displays.workspaceRows({ screen = "DELL", layout = "tabs", apps = { "Helium", "Arc" } }, "Helium", "2")
local function wsRow(id) for _, row in ipairs(wsRows) do if row.id == id then return row end end end
check.that("should show a workspace's screen and layout", check.contains(wsRow("screen").hint, "DELL") and check.contains(wsRow("layout").hint, "tabs"))
check.that("should list a workspace's apps, each removable", wsRow("app:Helium").group == "Apps" and check.contains(wsRow("app:Arc").hint, "remove"))
check.that("should offer to add an app and to open one when empty", wsRow("add") ~= nil and check.contains(wsRow("open").hint, "Helium"))
check.that("should step a workspace's screen through default, the screens and laptop",
  displays.stepWorkspaceScreen(nil, 1, { "laptop", "DELL" }) == "main" and displays.stepWorkspaceScreen("main", -1, { "laptop", "DELL" }) == nil
  and displays.stepWorkspaceScreen("main", 1, { "laptop", "DELL" }) == "laptop" and displays.stepWorkspaceScreen("laptop", 1, { "laptop", "DELL" }) == "DELL")
check.that("should step the app opened when empty through keep and the workspace's apps",
  displays.stepOpen(nil, 1, { "Helium", "Arc" }) == "Helium" and displays.stepOpen("Arc", 1, { "Helium", "Arc" }) == nil)

local choices = displays.appChoices({ { name = "Zed", workspace = "1" }, { name = "Safari", workspace = "3" }, { name = "Helium", workspace = "2" } },
  { workspaces = { ["1"] = { apps = { "Zed" } }, ["2"] = { apps = { "Helium" } } } }, "2")
local function choice(id) for _, row in ipairs(choices) do if row.id == id then return row end end end
check.that("should offer the apps open now, with where the profile puts them", choice("app:Zed").hint == "on workspace 1" and choice("app:Safari").hint == "open now")
check.that("should leave out an app already on this workspace", choice("app:Helium") == nil)
check.that("should end with typing an app's name", choices[#choices].id == "type")
local movedApp = displays.placeApp({ workspaces = { ["1"] = { apps = { "Zed" } } } }, "zed", "2")
check.that("should take an app off its old workspace when it's added to another",
  #movedApp.workspaces["1"].apps == 0 and movedApp.workspaces["2"].apps[1] == "zed")

-- The fallback in the editor and the When picker.
local withAny = displays.parse("[l]\nwhen = laptop\n\n[e]\nwhen = any\n").profiles
check.that("should say a fallback is used when nothing else matches", displays.matchStatus("e", withAny, { builtIn, dell }) == "used now, as nothing else matches")
check.that("should say a fallback waits while another profile matches", displays.matchStatus("e", withAny, { builtIn }) == "when nothing else matches")
local anyTicked = displays.toggleWhen(when("laptop, DELL"), "any")
check.that("should untick every screen when Any screens is ticked", table.concat(anyTicked.items, ",") == "any")
check.that("should untick Any screens when a screen is ticked", table.concat(displays.toggleWhen(anyTicked, "laptop").items, ",") == "laptop")
check.that("should write when = any for Any screens", displays.doneWhen(anyTicked) == "any")
local anyRows = displays.whenRows(when("any"), {})
local anyRow
for _, row in ipairs(anyRows) do if row.id == "display:any" then anyRow = row end end
check.that("should offer Any screens, ticked when when is any", anyRow and anyRow.label == "Any screens" and anyRow.icon == "󰄵")

-- Open when empty.
local opening = { open = { ["2"] = "Helium" } }
check.that("should open the workspace's app when it's empty", displays.openOnEmpty(opening, "2", 0) == "Helium")
check.that("should open nothing when the workspace has windows", displays.openOnEmpty(opening, "2", 1) == nil)
check.that("should open nothing on a workspace without an app to open", displays.openOnEmpty(opening, "3", 0) == nil and displays.openOnEmpty(nil, "2", 0) == nil)

-- A screen's gaps found under a shorter or longer name for the same display.
local named = displays.editRows({ when = "laptop, DELL U2723QE", screenGaps = { DELL = { inner = 10, outer = 10 } } }, "desk", nil, {})
local screenIds = {}
for _, row in ipairs(named) do if row.group == "Screens" then screenIds[#screenIds + 1] = row.id .. "=" .. row.hint end end
check.that("should show a screen's gaps on its when row when one name holds the other, without a second row",
  table.concat(screenIds, ";") == "screen:all=omv's gaps  ›;screen:laptop=omv's gaps  ›;screen:DELL U2723QE=gaps 10  ›")
check.that("should find the gaps key for a screen whose gaps are under a shorter name",
  displays.gapsKey({ screenGaps = { DELL = { inner = 1 } } }, "DELL U2723QE") == "DELL"
  and displays.gapsKey({ screenGaps = {} }, "DELL U2723QE") == "DELL U2723QE")

check.finish()
