-- Behavior of the Disk card: reading df, Mole's status and previews, and what each row runs.
-- Run through disk_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local disk = require("disk")

local df = "Filesystem     1024-blocks      Used Available Capacity iused      ifree %iused  Mounted on\n"
  .. "/dev/disk3s1s1   482797652  12344396 177925936     7%  458732 1779259360    0%   /\n"
local space = disk.parseDf(df)
check.that("should read free bytes from df output", space.free == 177925936 * 1024)
check.that("should read total bytes from df output", space.total == 482797652 * 1024)
check.that("should give no space for df output without a disk line", disk.parseDf("Filesystem 1024-blocks\n") == nil)

local status = disk.parseStatus({ disks = {
  { mount = "/Library/Developer/CoreSimulator/Volumes/iOS_23F77", used = 17617674240, total = 18083741696 },
  { mount = "/", used = 302768385864, total = 494384795648, purgeable = 9423282360 },
} })
check.that("should read the startup disk from Mole's status, not a simulator volume", status.total == 494384795648)
check.that("should count free bytes as total less used and purgeable, as df does",
  status.free == 494384795648 - 302768385864 - 9423282360)
check.that("should count free bytes as total less used when Mole reports no purgeable space",
  disk.parseStatus({ disks = { { mount = "/", used = 100, total = 300 } } }).free == 200)
check.that("should read purgeable bytes from Mole's status", status.purgeable == 9423282360)
check.that("should give no space when Mole's status has no startup disk", disk.parseStatus({ disks = {} }) == nil)
check.that("should give no space when Mole's status isn't a table", disk.parseStatus(nil) == nil)

check.that("should show sizes in GB as Finder does", disk.size(182196142080) == "182 GB")
check.that("should show a size under 1 GB in MB", disk.size(36000000) == "36 MB")

local clean = "\27[1;32mDry run complete\27[0m\nPotential space: \27[0;32m12.70GB\27[0m | Items: 1074 | Categories: 6\n"
check.that("should read the size from the clean preview through color codes", disk.previewSize(clean) == "12.70 GB")
check.that("should read the size from the purge preview",
  disk.previewSize("Would free approximately: 24.26GB | Items: 167 | Free: 182.19GB\n") == "24.26 GB")
check.that("should read a preview size given in MB", disk.previewSize("Potential space: 512.4MB | Items: 3\n") == "512.4 MB")
check.that("should give no size when a preview has no summary line", disk.previewSize("➤ Browsers\n  → Chrome cache\n") == nil)

local saved = disk.cacheLine(1000, "12.70 GB")
check.that("should read back a saved preview's time", disk.readCache(saved).at == 1000)
check.that("should read back a saved preview's size", disk.readCache(saved).size == "12.70 GB")
check.that("should give no saved preview for an empty cache file", disk.readCache("") == nil)
check.that("should treat a missing preview as stale", disk.isStale(nil, 1000))
check.that("should treat a preview older than 6 hours as stale", disk.isStale({ at = 0 }, 6 * 3600 + 1))
check.that("should keep a preview from the last 6 hours", not disk.isStale({ at = 0 }, 6 * 3600))

local NOW = 100000
local HOUR = 3600
local function itemById(model, id)
  for _, item in ipairs(model.buttons) do if item.id == id then return item end end
end
local function gridValue(model, label)
  for _, pair in ipairs(model.grid) do if pair[1] == label then return pair[2] end end
end

local fresh = { clean = { size = "12.70 GB", at = NOW - 60 }, purge = { measuring = true } }
local model = disk.model({ installed = true, space = status, previews = fresh }, NOW)
check.that("should show free space as the card's big number", model.big == "182 GB free")
check.that("should fill the bar with used, then purgeable, as shares of the total",
  model.segments[1].kind == "used" and model.segments[2].kind == "purgeable"
  and math.abs(model.segments[1].share - 61.2) < 0.1 and math.abs(model.segments[2].share - 1.9) < 0.1)
check.that("should list used space in the grid", gridValue(model, "Used") == "303 GB")
check.that("should list total space in the grid", gridValue(model, "Total") == "494 GB")
check.that("should list purgeable space in the grid with the bar's swatch",
  gridValue(model, "Purgeable") == "9.4 GB" and model.grid[2][3] == "purgeable")

local early = disk.model({ installed = true, space = space, previews = {} }, NOW)
check.that("should leave purgeable out of the bar before Mole answers", #early.segments == 1)
check.that("should show a dash for purgeable before Mole answers", gridValue(early, "Purgeable") == "—")
check.that("should show a dash as the big number when free space is unknown",
  disk.model({ installed = true, previews = {} }, NOW).big == "—")

check.that("should lay the cleanups out as a list", model.list == true and model.section == "CLEAN UP")
check.that("should list Caches and logs first, so it starts selected", model.buttons[1].id == "clean")
check.that("should list build artifacts, old installers and exploring",
  itemById(model, "purge") and itemById(model, "installer") and itemById(model, "analyze") and #model.buttons == 4)
check.that("should show measuring… in place of a size while a preview runs", itemById(model, "purge").size == "measuring…")

local function cleanItem(at)
  return disk.model({ installed = true, space = status, previews = { clean = { size = "3.80 GB", at = at } } }, NOW).buttons[1]
end
check.that("should show a cleanup's size and its age apart", cleanItem(NOW - 3 * HOUR - 60).size == "3.80 GB"
  and cleanItem(NOW - 3 * HOUR - 60).age == "3h ago")
check.that("should show no age when a size is under an hour old", cleanItem(NOW - 59 * 60).age == nil)
check.that("should show a size's age in days when it's a day old or more", cleanItem(NOW - 50 * HOUR).age == "2d ago")
check.that("should show no size before a preview has run",
  disk.model({ installed = true, space = status, previews = {} }, NOW).buttons[1].size == nil)

local missing = disk.model({ installed = false, space = space, previews = {} }, NOW)
check.that("should offer only Install Mole when Mole is missing", #missing.buttons == 1 and missing.buttons[1].id == "install")
check.that("should keep the space figures when Mole is missing", missing.big == "182 GB free")
check.that("should give the card room for its list", disk.height(model) > disk.height(missing))

check.that("should keep the last purgeable space while Mole's answer is on its way",
  disk.withPurgeable(space, status).purgeable == 9423282360)
check.that("should take df's free space while Mole's answer is on its way",
  disk.withPurgeable(space, status).free == space.free)
check.that("should add no purgeable space before Mole has ever answered", disk.withPurgeable(space, nil).purgeable == nil)
check.that("should give no space without a df reading", disk.withPurgeable(nil, status) == nil)

local commands = { clean = "mo clean", purge = "mo purge", analyze = "mo analyze", installer = "mo installer" }
for id, expected in pairs(commands) do
  check.that("should run " .. expected .. " for the " .. id .. " item", check.contains(disk.command(id), "/opt/homebrew/bin/" .. expected .. ";"))
  check.that("should keep the window open after " .. expected .. " finishes, so its summary can be read",
    check.contains(disk.command(id), "Press Enter to close"))
end
local unattended = false
for id in pairs(commands) do unattended = unattended or check.contains(disk.command(id), "--yes") end
check.that("should never run an item's command unattended", not unattended)
check.that("should run brew install mole for the install item", check.contains(disk.command("install"), "/opt/homebrew/bin/brew install mole;"))
check.that("should keep the window open after brew install mole finishes", check.contains(disk.command("install"), "Press Enter to close"))
check.that("should run nothing for an unknown item", disk.command("space") == nil)

check.that("should re-measure the clean preview after Clean caches is chosen", disk.invalidates("clean") == "clean")
check.that("should re-measure the purge preview after Purge is chosen", disk.invalidates("purge") == "purge")
check.that("should keep the previews after Explore disk usage is chosen", disk.invalidates("analyze") == nil)
check.that("should keep the previews after Remove old installers is chosen", disk.invalidates("installer") == nil)

check.finish()
