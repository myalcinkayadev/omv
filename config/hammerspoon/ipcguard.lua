-- A guard around hs.ipc's print. hs.ipc sends console output to each hs command connected
-- (the bar's click scripts, omv's own calls); one that quit mid-print, as a timed-out
-- `hs -t 2` does, makes the send raise before hs.ipc unmarks it as printing. Every print after
-- then sees it still printing, warns through the logger, which prints, and recurses until the
-- stack overflows: half a second to many seconds with every card frozen. The guard clears the
-- marks when a send fails, so the next print starts clean. The line is already in the
-- console by then, so nothing is lost.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local ipcguard = {}

-- print wrapped: ipcPrint is hs.ipc's print, ipc the hs.ipc module.
function ipcguard.wrap(ipc, ipcPrint)
  return function(...)
    local ok = pcall(ipcPrint, ...)
    if ok then return end
    for instance in pairs(ipc.insidePrintInstances) do ipc.insidePrintInstances[instance] = nil end
  end
end

return ipcguard
