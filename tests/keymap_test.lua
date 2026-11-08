-- Behavior of the cheat sheet's config parser. Run through keymap_test.sh with luajit.

package.path = arg[1] .. "/hammerspoon/.hammerspoon/?.lua;" .. package.path
local keymap = dofile(arg[1] .. "/hammerspoon/.hammerspoon/keymap.lua")

local failed = 0

local function check(name, passed)
  print((passed and "ok   - " or "FAIL - ") .. name)
  if not passed then failed = failed + 1 end
end

local single = keymap.parse("[mode.main.binding]\nalt-h = 'focus left'\n")
check("should list a key and its command when a binding is a single string",
  #single == 1 and single[1].key == "alt-h" and single[1].command == "focus left")

local list = keymap.parse("[mode.main.binding]\nalt-enter = ['workspace 1', 'exec-and-forget x']\n")
check("should join commands when a binding is a list",
  #list == 1 and list[1].command == "workspace 1, exec-and-forget x")

local modes = keymap.parse("[mode.main.binding]\nalt-h = 'a'\n[mode.resize.binding]\nh = 'b'\n")
check("should group bindings by mode when the file has several modes",
  modes[1].mode == "main" and modes[2].mode == "resize")

local noise = keymap.parse([==[
# alt-x = 'commented'
start-at-login = true
[gaps]
inner.horizontal = 10
[mode.main.binding]
# alt-y = 'commented'
alt-h = 'focus left'
[[on-window-detected]]
run = 'layout floating'
]==])
check("should ignore comments and non-binding lines", #noise == 1 and noise[1].key == "alt-h")

check("should return an empty list when the file is missing", #keymap.read("/nonexistent/aerospace.toml") == 0)

local notified = keymap.parse("[mode.resize.binding]\nesc = ['mode main', 'exec-and-forget /opt/homebrew/bin/sketchybar --trigger x']\n")
check("should hide bar notifications when a binding also tells the bar", notified[1].command == "mode main")

check("should show a readable label when a key has modifiers", keymap.label("alt-shift-h") == "Option+Shift+H")

check("should label tab as Tab when building the cheat sheet", keymap.label("alt-tab") == "Option+Tab")

check("should describe a known command in words", keymap.describe("focus left") == "Focus the window left")
check("should describe a numbered workspace command", keymap.describe("move-node-to-workspace 4") == "Send the window to workspace 4")
check("should describe the accordion toggle in words", keymap.describe("layout accordion tiles") == "Toggle tabbed or tiled")
check("should keep the command when it has no description", keymap.describe("flatten-workspace-tree") == "flatten-workspace-tree")

local sheet = keymap.html(keymap.parse("[mode.main.binding]\nalt-h = 'focus left'\n"), { { label = "Option+/", description = "Show this list" } })
check("should title the key list Keybindings", sheet:find('data-prompt="Keybindings…"', 1, true) ~= nil)
check("should show a binding's description in its row", sheet:find(">Focus the window left<", 1, true) ~= nil)
check("should show a binding's key in its row", sheet:find(">Option+H<", 1, true) ~= nil)
check("should show the key list in two columns", sheet:find("column-count: 2", 1, true) ~= nil)
check("should count one row per binding and launcher", #keymap.rows(keymap.parse("[mode.main.binding]\nalt-h = 'focus left'\n"), { { label = "x", description = "y" } }) == 2)
check("should list launcher keys as rows", sheet:find(">Show this list<", 1, true) ~= nil)

os.exit(failed == 0 and 0 or 1)
