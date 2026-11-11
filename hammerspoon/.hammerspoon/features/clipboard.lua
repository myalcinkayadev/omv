-- Clipboard history (Option+V): the text you copied in the last day, newest first, kept in
-- memory only, so a reload or restart forgets it. Secrets are skipped; see clipboard.lua.
-- Enter puts a copy back on the clipboard, for you to paste with Cmd+V: pasting for you
-- would need Accessibility, which omv doesn't grant. While paused, the bar says so.

local shell = require("shell")
local card = require("card")
local clipboard = require("clipboard")

local feature = {}

local WIDTH = 720
local VISIBLE_ROWS = 14

local history = clipboard.new()

local function drawBar()
  hs.task.new(shell.SKETCHYBAR, nil, { "--set", "clipboard_paused", "drawing=" .. (history.paused and "on" or "off"),
    "--trigger", "bar_fit" }):start()
end

local function onCopy(text)
  local app = hs.application.frontmostApplication()
  clipboard.add(history, { text = text, types = hs.pasteboard.contentTypes(),
    app = app and app:name(), bundle = app and app:bundleID() }, os.time())
end

local function setPaused(paused)
  history.paused = paused
  drawBar()
  shell.alert(paused and "Clipboard history paused" or "Clipboard history on", 1.2)
end

local function onMessage(message)
  if message.type ~= "choose" then return shell.close() end
  shell.close()
  if message.id == "pause" then return setPaused(true) end
  if message.id == "resume" then return setPaused(false) end
  if message.id == "clear" then
    clipboard.clear(history)
    return shell.alert("Clipboard history cleared", 1.2)
  end
  local item = history.items[tonumber(message.id)]
  if not item then return end
  hs.pasteboard.setContents(item.text)
  shell.alert("Copied · ⌘V to paste", 1.2)
end

function feature.toggle()
  if shell.isOpen("clipboard") then return shell.close() end
  local rows = clipboard.rows(history, os.time())
  local screen = { prompt = "Clipboard…", rows = rows, compact = true }
  shell.show("clipboard", shell.centered(WIDTH, shell.listHeight(#rows, VISIBLE_ROWS)), card.html(screen), onMessage)
end

-- The bar's paused item: a click turns history back on.
function feature.resume()
  if history.paused then setPaused(false) end
end

-- A restarted bar has lost the item's state.
function feature.redrawBar()
  drawBar()
end

-- Kept on the feature, so it isn't garbage-collected.
feature.watcher = hs.pasteboard.watcher.new(onCopy)
drawBar()

return feature
