-- Capture menu (Option+Shift+S): screenshots, text from the screen, and a color picker.

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
}

local function runCapture(id)
  local program, arguments = capture.command(id, shell.HOME, CAPTURE, os.time())
  if not program then return end
  hs.task.new(program, function(code, output, errors)
    -- A cancelled selection exits non-zero with nothing to say, so it stays quiet.
    local message = code == 0 and (CAPTURE_DONE[id] or ("Copied " .. output:gsub("%s+$", ""))) or errors:gsub("%s+$", "")
    if message ~= "" then shell.alert(message, 1.2) end
  end, arguments):start()
end

local function onCaptureMessage(message)
  shell.close()
  if message.type ~= "choose" then return end
  -- Wait for the card to disappear, so it never ends up in the picture.
  hs.timer.doAfter(0.2, function() runCapture(message.id) end)
end

function feature.toggle()
  if shell.isOpen("capture") then return shell.close() end
  local screen = capture.screen()
  shell.show("capture", shell.centered(shell.MENU_WIDTH, shell.menuHeight(screen)), card.html(screen), onCaptureMessage)
end

return feature
