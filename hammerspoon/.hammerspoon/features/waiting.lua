-- Waiting Claude (Option+Shift+A, or a click on the bar's pill): focuses the session's
-- terminal, or with several waiting, lists them with the one waiting longest first.

local shell = require("shell")
local card = require("card")
local claudewait = require("claudewait")

local feature = {}

local function alive(pid)
  return os.execute("/bin/kill -0 " .. math.floor(pid) .. " 2>/dev/null") == true
end

local function waitingSessions()
  local sessions = {}
  -- hs.fs.dir gives an iterator and the folder it reads, and the loop needs both.
  local ok, files, folder = pcall(hs.fs.dir, claudewait.STATE_DIR)
  for name in (ok and files) and files or function() end, folder do
    local session = name:sub(1, 1) ~= "." and claudewait.parse(shell.readText(claudewait.STATE_DIR .. "/" .. name) or "")
    if session then sessions[#sessions + 1] = session end
  end
  return sessions
end

local function focus(row)
  local script = claudewait.focusScript(row.id)
  if not (script and hs.osascript.applescript(script)) then
    shell.alert("Claude waits in " .. row.label .. ", outside Ghostty", 2)
  end
end

function feature.focus()
  if shell.isOpen("claude") then return shell.close() end
  local rows = claudewait.rows(waitingSessions(), alive, os.time())
  if #rows == 0 then return shell.alert("No Claude session is waiting", 1.2) end
  if #rows == 1 then return focus(rows[1]) end
  shell.show("claude", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows, #rows)),
    card.html({ prompt = "Waiting…", rows = rows, compact = true }), function(message)
      if message.type ~= "choose" then return shell.close() end
      -- Leave focus to Ghostty, rather than handing it back to the app open before.
      shell.leaveFocus()
      shell.close()
      for _, row in ipairs(rows) do
        if row.id == message.id then return focus(row) end
      end
    end)
end

return feature
