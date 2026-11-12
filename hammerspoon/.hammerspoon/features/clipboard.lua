-- Clipboard history (Option+V): the text you copied in the last day, and the last 20
-- images, newest first, kept in memory only, so a reload or restart forgets it. Secrets are skipped; see clipboard.lua.
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

-- A copied picture: its small preview, which also tells one picture from another, its
-- size, and the picture itself, to put back on the clipboard.
local function copiedImage()
  local picture = hs.pasteboard.readImage()
  if not picture then return nil end
  local size = picture:size()
  local preview = picture:copy():setSize({ w = 40, h = 40 }, true):encodeAsURLString(false, "PNG")
  return { fingerprint = preview, preview = preview, width = math.floor(size.w), height = math.floor(size.h), picture = picture }
end

local function onCopy(text)
  local app = hs.application.frontmostApplication()
  local copy = { text = text, types = hs.pasteboard.contentTypes(), app = app and app:name(), bundle = app and app:bundleID() }
  if not text then copy.image = copiedImage() end
  clipboard.add(history, copy, os.time())
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
  if item.image then
    hs.pasteboard.writeObjects(item.image.picture)
  else
    hs.pasteboard.setContents(item.text)
  end
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
