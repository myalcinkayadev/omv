-- App-launch keys and the cheat sheet. AeroSpace owns every window key; see README.md for the full map.
-- hs.hotkey needs no Accessibility permission, so none is granted.
require("hs.ipc")

local keymap = require("keymap")

hs.menuIcon(false)
hs.dockIcon(false)
hs.uploadCrashData(false)

local SUPER = { "alt" }
local SUPER_SHIFT = { "alt", "shift" }
local AEROSPACE_CONFIG = os.getenv("HOME") .. "/.config/aerospace/aerospace.toml"
local LAUNCH = hs.configdir .. "/launch.sh"
local GHOSTTY_WINDOW = os.getenv("HOME") .. "/.config/ghostty/new-window.sh"

local function run(command, arguments)
  return function()
    hs.task.new(command, nil, arguments or {}):start()
  end
end

local function open(arguments)
  return run("/usr/bin/open", arguments)
end

local launchers = {}

local function bindKey(modifiers, key, label, description, action)
  hs.hotkey.bind(modifiers, key, action)
  launchers[#launchers + 1] = { label = label, description = description }
end

local function openOnWorkspace(workspace, arguments)
  return run(LAUNCH, { workspace, "/usr/bin/open", table.unpack(arguments) })
end

bindKey(SUPER_SHIFT, "return", "Option+Shift+Enter", "New Helium window", openOnWorkspace("3", { "-na", "Helium", "--args", "--new-window" }))
bindKey(SUPER_SHIFT, "n", "Option+Shift+N", "Open Zed", openOnWorkspace("2", { "-a", "Zed" }))
bindKey(SUPER_SHIFT, "f", "Option+Shift+F", "Finder at home", open({ os.getenv("HOME") }))
bindKey(SUPER_SHIFT, "t", "Option+Shift+T", "btop", run(LAUNCH, { "1", GHOSTTY_WINDOW, "/opt/homebrew/bin/btop" }))
bindKey(SUPER_SHIFT, "space", "Option+Shift+Space", "Show or hide the bar", run("/opt/homebrew/bin/sketchybar", { "--bar", "hidden=toggle" }))

-- Ghostty owns this key, so it is listed here rather than bound.
launchers[#launchers + 1] = { label = "Option+`", description = "Drop-down terminal" }

local SHEET_WIDTH = 1040
local SHEET_HEIGHT = 780
local sheet = nil
local closeOnEscape = nil

local function closeSheet()
  if not sheet then return end
  sheet:delete()
  sheet = nil
  closeOnEscape:disable()
end

local function openSheet()
  local screen = hs.screen.mainScreen():frame()
  local frame = hs.geometry.rect(
    screen.x + (screen.w - SHEET_WIDTH) / 2,
    screen.y + (screen.h - SHEET_HEIGHT) / 2,
    SHEET_WIDTH,
    SHEET_HEIGHT
  )
  sheet = hs.webview.new(frame)
  sheet:windowStyle({ "borderless" })
  sheet:level(hs.drawing.windowLevels.modalPanel)
  sheet:html(keymap.html(keymap.read(AEROSPACE_CONFIG), launchers))
  sheet:show()
  closeOnEscape:enable()
end

closeOnEscape = hs.hotkey.new({}, "escape", closeSheet)

-- 44 is the physical "/" key, so this stays the same key on the Turkish layout.
bindKey(SUPER, 44, "Option+/", "Show or hide this sheet", function()
  if sheet then closeSheet() else openSheet() end
end)
