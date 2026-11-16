-- Feature flags: features that stay off unless turned on. The defaults are here, in the repo;
-- ~/.config/omv/flags turns them on or off on this Mac, one "name=on" or "name=off" per line,
-- with # for comments. Lines that aren't one of those, or name an unknown flag, are ignored.
-- Read when Hammerspoon loads, so a change takes a reload.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local flags = {}

flags.PATH = (os.getenv("HOME") or "") .. "/.config/omv/flags"

flags.DEFAULTS = {
  -- The palette also lists recent files matching what's typed (mdfind).
  ["file-search"] = false,
}

-- text is the flags file's contents, or nil when there's none.
function flags.read(text)
  local found = {}
  for name, value in pairs(flags.DEFAULTS) do found[name] = value end
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local name, value = line:match("^%s*([%w%-]+)%s*=%s*(%a+)%s*$")
    if name and found[name] ~= nil and (value == "on" or value == "off") then found[name] = value == "on" end
  end
  return found
end

return flags
