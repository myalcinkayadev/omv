-- Send to agent (Option+P): the selection, else the clipboard's text, or a screenshot of a
-- region, pasted into the prompt of an agent that finished and waits for you. The card lists
-- only those sessions; the paste never presses Enter, so you read it and send it yourself.
-- The clipboard is put back afterwards.

local shell = require("shell")
local card = require("card")
local sendto = require("sendto")
local waiting = require("features.waiting")

local feature = {}

local SCREENCAPTURE = "/usr/sbin/screencapture"
-- The terminal needs a moment in front before Cmd+V reaches it, and the paste a moment
-- before the clipboard is put back.
local PASTE_DELAY = 0.15
local RESTORE_DELAY = 0.5
-- Long enough for the card to disappear, so it never ends up in the screenshot.
local CARD_GONE_DELAY = 0.2

-- The session on tty as it is now, if it is still done: it may have started again since the
-- card opened.
local function doneSession(tty)
  for _, row in ipairs(waiting.rows()) do
    if row.id == tty and row.state == "done" then return row end
  end
  return nil
end

local function pasteInto(row, text)
  waiting.focusRow(row, function(focused)
    if not focused or not hs.accessibilityState() then
      hs.pasteboard.setContents(text)
      return shell.alert("Copied: paste it into " .. row.label .. " with Cmd+V", 2)
    end
    local saved = shell.saveClipboard()
    hs.pasteboard.setContents(text)
    hs.timer.doAfter(PASTE_DELAY, function()
      hs.eventtap.keyStroke({ "cmd" }, "v", 0)
      hs.timer.doAfter(RESTORE_DELAY, function() shell.restoreClipboard(saved) end)
    end)
  end)
end

local function deliver(tty, text)
  local row = doneSession(tty)
  if not row then return shell.alert("That agent is no longer waiting for a prompt", 1.5) end
  pasteInto(row, text)
end

local function removeOldShots()
  local ok, files, folder = pcall(hs.fs.dir, sendto.SHOT_DIR)
  local now = os.time()
  for name in (ok and files) and files or function() end, folder do
    local path = sendto.SHOT_DIR .. "/" .. name
    local modified = hs.fs.attributes(path, "modification")
    if modified and sendto.isOldShot(name, modified, now) then os.remove(path) end
  end
end

local function sendShot(tty)
  hs.fs.mkdir(shell.STATE_DIR)
  hs.fs.mkdir(sendto.SHOT_DIR)
  removeOldShots()
  local path = sendto.shotPath(os.time())
  hs.task.new(SCREENCAPTURE, function(code)
    -- A cancelled selection exits non-zero and saves nothing, so it stays quiet.
    if code ~= 0 or not hs.fs.attributes(path) then return end
    deliver(tty, path)
  end, { "-i", path }):start()
end

local function showCard(text, source)
  local rows = sendto.rows(waiting.rows(), text, source)
  if #rows == 0 then return shell.alert("No agent is waiting for a prompt", 1.5) end
  shell.show("sendto", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows)),
    card.html({ prompt = "Send to agent…", rows = rows, compact = true }), function(message)
      if message.type ~= "choose" then return shell.close() end
      local kind, tty = sendto.parseId(message.id)
      -- Leave focus to the agent's terminal, rather than handing it back to the app open before.
      shell.leaveFocus()
      shell.close()
      if kind == "text" then return deliver(tty, text) end
      if kind == "shot" then hs.timer.doAfter(CARD_GONE_DELAY, function() sendShot(tty) end) end
    end)
end

function feature.toggle()
  if shell.isOpen("sendto") then return shell.close() end
  shell.copySelection(function(selected)
    local text = sendto.clean(selected)
    if text then return showCard(text, "Selection") end
    text = sendto.clean(hs.pasteboard.getContents())
    if text then return showCard(text, "Clipboard") end
    showCard(nil, nil)
  end)
end

return feature
