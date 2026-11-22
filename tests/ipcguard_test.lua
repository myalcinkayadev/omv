-- The guard around hs.ipc's print. Run through ipcguard_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local ipcguard = require("ipcguard")

-- An hs.ipc whose print sends to a dead hs command: it marks the instance, then raises.
local function deadIpc()
  local ipc = { insidePrintInstances = {} }
  local printed = {}
  local function ipcPrint(text)
    printed[#printed + 1] = text
    ipc.insidePrintInstances.dead = (ipc.insidePrintInstances.dead or 0) + 1
    error("ipc port is no longer valid (early)")
  end
  return ipc, ipcPrint, printed
end

local ipc, ipcPrint, printed = deadIpc()
local guarded = ipcguard.wrap(ipc, ipcPrint)
check.that("should not raise when an hs command quit mid-print", pcall(guarded, "hello"))
check.that("should clear the marks a failed send left", next(ipc.insidePrintInstances) == nil)
guarded("again")
check.that("should still print each line", printed[1] == "hello" and printed[2] == "again")
local fine = { insidePrintInstances = {} }
local seen = nil
ipcguard.wrap(fine, function(...) seen = select("#", ...) end)("a", "b")
check.that("should pass every argument through when nothing fails", seen == 2)

check.finish()
