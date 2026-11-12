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

local function rowById(rows, id)
  for _, row in ipairs(rows) do if row.id == id then return row end end
end

local rows = disk.rows({ installed = true, space = status,
  previews = { clean = { size = "12.70 GB" }, purge = { measuring = true } } })
check.that("should show free, total and purgeable space first",
  rows[1].label == "182 GB free of 494 GB" and rows[1].hint == "9.4 GB purgeable")
check.that("should show the clean preview's size beside its row", rowById(rows, "clean").hint == "12.70 GB")
check.that("should show measuring… while a preview runs", rowById(rows, "purge").hint == "measuring…")
check.that("should offer to explore disk usage", rowById(rows, "analyze") ~= nil)
check.that("should offer old installers", rowById(rows, "installer") ~= nil)
check.that("should leave out purgeable space before Mole answers",
  disk.rows({ installed = true, space = space, previews = {} })[1].hint == nil)

local hints = disk.hints({ installed = true, space = status,
  previews = { clean = { size = "12.70 GB" }, purge = { measuring = true } } })
check.that("should give the clean preview's size as its hint", hints.clean == "12.70 GB")
check.that("should give measuring… as the hint of a running preview", hints.purge == "measuring…")
check.that("should give purgeable space as the space row's hint", hints.space == "9.4 GB purgeable")
check.that("should clear the hint of a preview with no size yet", disk.hints({ space = space, previews = {} }).clean == false)

local missing = disk.rows({ installed = false, space = space, previews = {} })
check.that("should offer to install Mole when it's missing", missing[2].id == "install" and #missing == 2)

local commands = { clean = "mo clean", purge = "mo purge", analyze = "mo analyze", installer = "mo installer" }
for id, expected in pairs(commands) do
  check.that("should run " .. expected .. " for the " .. id .. " row", disk.command(id) == "/opt/homebrew/bin/" .. expected)
end
local unattended = false
for id in pairs(commands) do unattended = unattended or check.contains(disk.command(id), "--yes") end
check.that("should never run a row's command unattended", not unattended)
check.that("should run brew install mole for the install row", disk.command("install") == "/opt/homebrew/bin/brew install mole")
check.that("should run nothing for the space row", disk.command("space") == nil)

check.that("should re-measure the clean preview after Clean caches is chosen", disk.invalidates("clean") == "clean")
check.that("should re-measure the purge preview after Purge is chosen", disk.invalidates("purge") == "purge")
check.that("should keep the previews after Explore disk usage is chosen", disk.invalidates("analyze") == nil)
check.that("should keep the previews after Remove old installers is chosen", disk.invalidates("installer") == nil)

check.finish()
