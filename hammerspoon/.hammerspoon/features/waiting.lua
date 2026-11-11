-- Waiting Claude (Option+Shift+A, or a click on the bar's pill): focuses the session's
-- terminal, or with several waiting, lists them with the asking ones first, then the one
-- waiting longest. Working sessions are left out here; the Agents card lists them too.

local shell = require("shell")
local card = require("card")
local claudewait = require("claudewait")

local feature = {}

local function alive(pid)
  return os.execute("/bin/kill -0 " .. math.floor(pid) .. " 2>/dev/null") == true
end

local function savedSessions()
  local sessions = {}
  -- hs.fs.dir gives an iterator and the folder it reads, and the loop needs both.
  local ok, files, folder = pcall(hs.fs.dir, claudewait.STATE_DIR)
  for name in (ok and files) and files or function() end, folder do
    local session = name:sub(1, 1) ~= "." and claudewait.parse(shell.readText(claudewait.STATE_DIR .. "/" .. name) or "")
    if session then sessions[#sessions + 1] = session end
  end
  return sessions
end

local function running(bundle)
  return hs.application.get(bundle) ~= nil
end

local function runScript(script)
  local ok, found = hs.osascript.applescript(script)
  return ok and found ~= false
end

-- Every live session's row, asking first, then done, then working.
function feature.rows()
  return claudewait.rows(savedSessions(), alive, os.time())
end

-- Goes to the session's terminal, or says where it runs when that can't be focused.
function feature.focusRow(row)
  if not claudewait.focus(row.id, running, runScript) then
    shell.alert("Claude runs in " .. row.label .. ", outside Ghostty, iTerm2 or Terminal", 2)
  end
end

local function waitingRows()
  local rows = {}
  for _, row in ipairs(feature.rows()) do
    if row.waiting then rows[#rows + 1] = row end
  end
  return rows
end

function feature.focus()
  if shell.isOpen("claude") then return shell.close() end
  local rows = waitingRows()
  if #rows == 0 then return shell.alert("No Claude session is waiting", 1.2) end
  if #rows == 1 then return feature.focusRow(rows[1]) end
  shell.show("claude", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows, #rows)),
    card.html({ prompt = "Waiting…", rows = rows, compact = true }), function(message)
      if message.type ~= "choose" then return shell.close() end
      -- Leave focus to the terminal, rather than handing it back to the app open before.
      shell.leaveFocus()
      shell.close()
      for _, row in ipairs(rows) do
        if row.id == message.id then return feature.focusRow(row) end
      end
    end)
end

return feature
