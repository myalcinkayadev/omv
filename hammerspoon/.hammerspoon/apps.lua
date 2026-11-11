-- Which browser and editor omv opens, from ~/.config/omv/apps, one "key = value" a line:
--   browser = Google Chrome
--   editor = Cursor
-- Without the file, or for a key left out, Helium and Zed. Names are app names, as in /Applications.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local apps = {}

apps.PATH = os.getenv("HOME") .. "/.config/omv/apps"

local DEFAULTS = { browser = "Helium", editor = "Zed" }

function apps.read(text)
  local chosen = { browser = DEFAULTS.browser, editor = DEFAULTS.editor }
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local key, value = line:match("^%s*(%a+)%s*=%s*(.-)%s*$")
    if key and DEFAULTS[key] and value ~= "" then chosen[key] = value end
  end
  return chosen
end

return apps
