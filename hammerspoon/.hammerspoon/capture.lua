-- The Option+Shift+S capture menu: its rows, and the command each row runs. A recording
-- runs until it is stopped, from the bar or the same key.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local capture = {}

local SCREENCAPTURE = "/usr/sbin/screencapture"

function capture.screen()
  return {
    prompt = "Capture…",
    rows = {
      { id = "region.clipboard", icon = "󰆟", label = "Region to clipboard" },
      { id = "region.file", icon = "󰄀", label = "Region to file", hint = "Desktop" },
      { id = "window.clipboard", icon = "󰖯", label = "Window to clipboard" },
      { id = "screen.clipboard", icon = "󰍹", label = "Screen to clipboard" },
      { id = "text", icon = "󰊄", label = "Text from screen" },
      { id = "qr", icon = "󰐲", label = "QR code from screen" },
      { id = "color", icon = "󰈊", label = "Pick a color" },
      { id = "record.region", icon = "󰻃", label = "Record a region", hint = "Desktop" },
      { id = "record.screen", icon = "󰻃", label = "Record the screen", hint = "Desktop" },
    },
  }
end

-- Matches the name macOS gives its own screenshots.
function capture.fileName(time)
  return os.date("Screenshot %Y-%m-%d at %H.%M.%S.png", time)
end

-- Matches the name macOS gives its own screen recordings.
function capture.recordingName(time)
  return os.date("Screen Recording %Y-%m-%d at %H.%M.%S.mov", time)
end

function capture.isRecording(id)
  return id == "record.region" or id == "record.screen"
end

-- Returns the program and arguments for a row, or nil for an unknown one. display is the
-- screencapture display number to record, the main one when nil.
function capture.command(id, home, script, time, display)
  local recording = home .. "/Desktop/" .. capture.recordingName(time)
  if id == "record.region" then return script, { "record", recording } end
  if id == "record.screen" then
    local arguments = { "-v", "-k" }
    if display then arguments[#arguments + 1] = "-D" .. display end
    arguments[#arguments + 1] = recording
    return SCREENCAPTURE, arguments
  end
  if id == "region.clipboard" then return SCREENCAPTURE, { "-i", "-c" } end
  if id == "region.file" then return SCREENCAPTURE, { "-i", home .. "/Desktop/" .. capture.fileName(time) } end
  if id == "window.clipboard" then return SCREENCAPTURE, { "-i", "-W", "-c" } end
  if id == "screen.clipboard" then return SCREENCAPTURE, { "-c" } end
  if id == "text" or id == "color" or id == "qr" then return script, { id } end
  return nil
end

return capture
