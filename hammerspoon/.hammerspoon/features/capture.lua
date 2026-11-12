-- Capture menu (Option+Shift+S): screenshots, text and QR codes from the screen, a color
-- picker, and screen recordings. While a recording runs, the bar shows "rec"; a click on it,
-- or Option+Shift+S again, stops it and saves it to the Desktop.

local shell = require("shell")
local card = require("card")
local capture = require("capture")

local feature = {}

local CAPTURE = hs.configdir .. "/capture.sh"
local CAPTURE_DONE = {
  ["region.clipboard"] = "Copied screenshot",
  ["region.file"] = "Saved to Desktop",
  ["window.clipboard"] = "Copied screenshot",
  ["screen.clipboard"] = "Copied screenshot",
  text = "Copied text",
  ["record.region"] = "Saved recording to Desktop",
  ["record.screen"] = "Saved recording to Desktop",
}

-- The recording's task while it runs.
local recording = nil

local function showRecording(on)
  hs.task.new(shell.SKETCHYBAR, nil, { "--set", "recording", "drawing=" .. (on and "on" or "off") }):start()
end

-- screencapture's display number for the screen under the pointer: 1 is the main one.
local function displayNumber()
  local current = shell.screen()
  for index, screen in ipairs(hs.screen.allScreens()) do
    if screen == current then return index end
  end
  return nil
end

local function runCapture(id)
  local program, arguments = capture.command(id, shell.HOME, CAPTURE, os.time(), displayNumber())
  if not program then return end
  local task = hs.task.new(program, function(code, output, errors)
    if capture.isRecording(id) then
      recording = nil
      showRecording(false)
    end
    -- A cancelled selection exits non-zero with nothing to say, so it stays quiet. An
    -- interrupted recording has been saved.
    local saved = code == 0 or (capture.isRecording(id) and code == 2)
    local message = saved and (CAPTURE_DONE[id] or ("Copied " .. output:gsub("%s+$", ""))) or errors:gsub("%s+$", "")
    if message ~= "" then shell.alert(message, 1.2) end
  end, arguments)
  if not task:start() then return shell.alert("Couldn't start the capture", 1.5) end
  if capture.isRecording(id) then
    recording = task
    showRecording(true)
  end
end

-- Interrupted, screencapture finishes the file before it exits.
function feature.stopRecording()
  if recording then recording:interrupt() end
end

local function onCaptureMessage(message)
  shell.close()
  if message.type ~= "choose" then return end
  -- Wait for the card to disappear, so it never ends up in the picture.
  hs.timer.doAfter(0.2, function() runCapture(message.id) end)
end

function feature.toggle()
  if recording then return feature.stopRecording() end
  if shell.isOpen("capture") then return shell.close() end
  local screen = capture.screen()
  shell.show("capture", shell.centered(shell.MENU_WIDTH, shell.menuHeight(screen)), card.html(screen), onCaptureMessage)
end

return feature
