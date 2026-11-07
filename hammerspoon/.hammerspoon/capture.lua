-- The Option+Shift+S capture menu: its rows, and the command each row runs.
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
      { id = "color", icon = "󰈊", label = "Pick a color" },
    },
  }
end

-- Matches the name macOS gives its own screenshots.
function capture.fileName(time)
  return os.date("Screenshot %Y-%m-%d at %H.%M.%S.png", time)
end

-- Returns the program and arguments for a row, or nil for an unknown one.
function capture.command(id, home, script, time)
  if id == "region.clipboard" then return SCREENCAPTURE, { "-i", "-c" } end
  if id == "region.file" then return SCREENCAPTURE, { "-i", home .. "/Desktop/" .. capture.fileName(time) } end
  if id == "window.clipboard" then return SCREENCAPTURE, { "-i", "-W", "-c" } end
  if id == "screen.clipboard" then return SCREENCAPTURE, { "-c" } end
  if id == "text" or id == "color" then return script, { id } end
  return nil
end

return capture
