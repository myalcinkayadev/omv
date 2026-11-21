-- Feature flags: defaults in flags.lua, overridden by ~/.config/omv/flags. Run through
-- flags_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local flags = require("flags")

local function fileSearch(text) return flags.read(text)["file-search"] end

check.that("should be off when there's no flags file", fileSearch(nil) == false)
check.that("should turn a flag on when its line says on", fileSearch("file-search=on\n") == true)
check.that("should turn a flag off when its line says off", fileSearch("file-search=off") == false)
check.that("should ignore spaces around the name and value", fileSearch("  file-search = on ") == true)
check.that("should ignore a comment line", fileSearch("# file-search=on") == false)
check.that("should ignore a value that isn't on or off", fileSearch("file-search=yes") == false)
check.that("should ignore an unknown flag", flags.read("nope=on")["nope"] == nil)
check.that("should let the last line win", fileSearch("file-search=on\nfile-search=off") == false)
check.that("should keep the defaults unchanged when a file turns a flag on", (function()
  flags.read("file-search=on")
  return flags.DEFAULTS["file-search"] == false
end)())

-- Every feature has a flag, on unless turned off; file search alone starts off.
local FEATURES = {
  "weather", "battery", "bluetooth", "network", "sound", "calendar", "disk", "tailscale", "focus", "display-profiles",
  "clipboard", "snippets", "calculator", "clipboard-actions", "translate", "capture", "reminders", "daily-note", "airdrop",
  "copy-url", "keep-awake", "night-light", "mic-mute", "volume-popups", "processes", "lyrics",
  "now-playing", "claude", "send-to-agent", "away-digest", "github-prs", "github-ci", "dev-layout", "drop-down-terminal", "long-command-notices",
}
local defaults = flags.read(nil)
for _, name in ipairs(FEATURES) do
  check.that("should have " .. name .. " on by default", defaults[name] == true)
end
check.that("should have meeting mode off by default", flags.read(nil)["meeting-mode"] == false)
check.that("should have a flag for every feature, file search and meeting mode, and nothing else", (function()
  local count = 0
  for _ in pairs(flags.DEFAULTS) do count = count + 1 end
  return count == #FEATURES + 2
end)())
check.that("should turn a feature off when its line says off", flags.read("weather=off").weather == false)
check.that("should leave the other features on when one is turned off", flags.read("weather=off").battery == true)

check.finish()
