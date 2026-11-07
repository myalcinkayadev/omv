-- Behavior of the cheat sheet's config parser. Run through keymap_test.sh with luajit.

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

os.exit(failed == 0 and 0 or 1)
