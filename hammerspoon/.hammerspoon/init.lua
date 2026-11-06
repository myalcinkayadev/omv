-- App-launch keys. AeroSpace owns every window key; see README.md for the full map.
-- hs.hotkey needs no Accessibility permission, so none is granted.
require("hs.ipc")

hs.menuIcon(false)
hs.dockIcon(false)
hs.uploadCrashData(false)

local SUPER_SHIFT = { "alt", "shift" }
local LAUNCH = hs.configdir .. "/launch.sh"

local function run(command, arguments)
  return function()
    hs.task.new(command, nil, arguments or {}):start()
  end
end

local function open(arguments)
  return run("/usr/bin/open", arguments)
end

local function openOnWorkspace(workspace, arguments)
  return run(LAUNCH, { workspace, table.unpack(arguments) })
end

hs.hotkey.bind(SUPER_SHIFT, "return", openOnWorkspace("2", { "-na", "Helium", "--args", "--new-window" }))
hs.hotkey.bind(SUPER_SHIFT, "n", openOnWorkspace("3", { "-a", "Zed" }))
hs.hotkey.bind(SUPER_SHIFT, "f", open({ os.getenv("HOME") }))
hs.hotkey.bind(SUPER_SHIFT, "t", openOnWorkspace("1", { "-na", "Ghostty", "--args", "-e", "/opt/homebrew/bin/btop" }))
hs.hotkey.bind(SUPER_SHIFT, "space", run("/opt/homebrew/bin/sketchybar", { "--bar", "hidden=toggle" }))
