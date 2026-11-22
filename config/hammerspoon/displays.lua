-- Display profiles: ~/.config/omv/displays names a few settings for each setup, such as tabs and
-- tight gaps on the laptop alone, and tiles and roomy gaps at the desk. omv picks the first
-- profile whose displays are plugged in, and applies what it sets; leaving a profile puts back
-- what it changed. This reads the file, picks the profile, and works out what changes.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit; omv doctor runs it
-- as a script to check the file: luajit displays.lua check <file>.

local displays = {}

displays.PATH = (os.getenv("HOME") or "") .. "/.config/omv/displays"

-- The built-in screen's top gap: macOS already keeps windows clear of the notch there. The bar
-- on other displays is this tall, so the outer gap goes below it.
local NOTCH_TOP, BAR_HEIGHT = 14, 36

local CHOICES = {
  layout = { tiles = true, tabs = true },
  quiet = { on = true, off = true },
  bar = { shown = true, hidden = true },
}
local CHOICE_WORDS = { layout = "tiles, tabs or keep", quiet = "on, off or keep", bar = "shown, hidden or keep" }
-- Settings with a whole number, and the field each fills.
local NUMBERS = { gaps = true, ["gaps.inner"] = "gapsInner", ["gaps.outer"] = "gapsOuter", font = "font", count = true }
local COMMANDS = { ["on-enter"] = "onEnter", ["on-leave"] = "onLeave" }

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function list(text)
  local items = {}
  for item in text:gmatch("[^,]+") do
    item = trim(item)
    if item ~= "" then items[#items + 1] = item end
  end
  return items
end

-- Fills profile from one name = value line; gives a problem, or nil.
local function setting(profile, name, value, gapsGiven)
  if name == "when" then
    if value:lower() == "built-in only" then profile.builtinOnly = true else profile.when = list(value) end
    return nil
  end
  if value == "keep" and name ~= "count" then return nil end
  if CHOICES[name] then
    if not CHOICES[name][value] then return name .. " must be " .. CHOICE_WORDS[name] end
    profile.settings[name] = value
    return nil
  end
  if NUMBERS[name] then
    local number = value:match("^%d+$") and tonumber(value)
    if not number then return name .. " must be a whole number" end
    if name == "count" then profile.count = number
    elseif name == "gaps" then gapsGiven.inner, gapsGiven.outer = number, number
    else profile.settings[NUMBERS[name]] = number end
    return nil
  end
  if name == "theme" then
    if not value:match("^[%w%-]+$") then return "theme must be a theme's name" end
    profile.settings.theme = value
    return nil
  end
  if COMMANDS[name] then
    profile.settings[COMMANDS[name]] = value
    return nil
  end
  return "unknown setting " .. name
end

-- The file's text, or nil when there's none: { profiles = { { name, when, builtinOnly, count,
-- settings } }, problems = { "line 3: …" } }. A bad line is skipped and named in problems.
function displays.parse(text)
  local profiles, problems = {}, {}
  local current, gaps = nil, nil
  local function close()
    if not current then return end
    -- gaps.inner and gaps.outer win over gaps, wherever they are in the section.
    current.settings.gapsInner = current.settings.gapsInner or gaps.inner
    current.settings.gapsOuter = current.settings.gapsOuter or gaps.outer
    if not current.when and not current.builtinOnly then problems[#problems + 1] = "profile " .. current.name .. " has no when line" end
    profiles[#profiles + 1] = current
  end
  local number = 0
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    number = number + 1
    local plain = trim((line:gsub("#.*$", "")))
    local section = plain:match("^%[([%w%-_]+)%]$")
    if section then
      close()
      current, gaps = { name = section, settings = {} }, {}
    elseif plain ~= "" then
      local name, value = plain:match("^([%w%-%.]+)%s*=%s*(.-)$")
      local problem
      if not name or value == "" then problem = "expected name = value"
      elseif not current then problem = name .. " is outside a [profile]"
      else problem = setting(current, name:lower(), value, gaps) end
      if problem then problems[#problems + 1] = "line " .. number .. ": " .. problem end
    end
  end
  close()
  return { profiles = profiles, problems = problems }
end

local function matches(profile, screens)
  if profile.count and #screens ~= profile.count then return false end
  if profile.builtinOnly then return #screens == 1 and screens[1].builtin == true end
  for _, wanted in ipairs(profile.when or {}) do
    for _, screen in ipairs(screens) do
      if tostring(screen.name or ""):lower():find(wanted:lower(), 1, true) then return true end
    end
  end
  return false
end

-- The first profile whose displays are plugged in, in file order; nil when none is.
-- screens is { { name, builtin } } for each display.
function displays.pick(profiles, screens)
  for _, profile in ipairs(profiles or {}) do
    if matches(profile, screens) then return profile end
  end
  return nil
end

local SETTINGS = { "layout", "gapsInner", "gapsOuter", "quiet", "theme", "font", "bar" }

-- What moving from profile before to profile after changes, either nil: each setting after
-- sets, and "default" for one before set that after doesn't, to put omv's own back. Also the
-- command before runs on leaving, and the one after runs on entering.
function displays.changes(before, after)
  local old, new = before and before.settings or {}, after and after.settings or {}
  local changes = {}
  for _, name in ipairs(SETTINGS) do
    if new[name] ~= nil then changes[name] = new[name]
    elseif old[name] ~= nil then changes[name] = "default" end
  end
  changes.onLeave = old.onLeave
  changes.onEnter = new.onEnter
  return changes
end

-- The aerospace arguments that set a workspace's layout: tabs is AeroSpace's accordion. The
-- whole workspace changes, from its root; aerospace refuses --workspace without --root.
function displays.layoutArgs(workspace, layout)
  return { "layout", "--workspace", workspace, "--root", layout == "tabs" and "accordion" or "tiles" }
end

-- Whether two profiles' settings are the same, so an edit to the profile in use is noticed.
function displays.sameSettings(a, b)
  a, b = a or {}, b or {}
  for key, value in pairs(a) do
    if b[key] ~= value then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

-- The [gaps] table AeroSpace builds in after the user's own settings, or nil when the profile
-- sets no gaps. The built-in screen keeps the notch's top gap; other displays clear the bar.
function displays.aerospaceGaps(settings)
  local inner, outer = settings.gapsInner, settings.gapsOuter
  if not inner and not outer then return nil end
  local lines = { "[gaps]" }
  if inner then
    lines[#lines + 1] = "inner.horizontal = " .. inner
    lines[#lines + 1] = "inner.vertical = " .. inner
  end
  if outer then
    lines[#lines + 1] = "outer.left = " .. outer
    lines[#lines + 1] = "outer.right = " .. outer
    lines[#lines + 1] = "outer.bottom = " .. outer
    lines[#lines + 1] = 'outer.top = [{ monitor."built-in" = ' .. NOTCH_TOP .. " }, " .. (BAR_HEIGHT + outer) .. "]"
  end
  return table.concat(lines, "\n") .. "\n"
end

local function screensKey(screens)
  local names = {}
  for _, screen in ipairs(screens or {}) do names[#names + 1] = tostring(screen.name) end
  table.sort(names)
  return table.concat(names, "\n")
end

-- Picks profile by hand for the displays plugged in now, or nil to follow the displays again.
function displays.choose(_, profile, screens)
  if not profile then return {} end
  return { picked = profile.name, screens = screensKey(screens) }
end

-- The profile in use: the one picked by hand while the displays are as they were then, marked
-- picked; otherwise the first that matches.
function displays.current(state, profiles, screens)
  if state and state.picked and state.screens == screensKey(screens) then
    for _, profile in ipairs(profiles or {}) do
      if profile.name == state.picked then
        return { name = profile.name, settings = profile.settings, picked = true }
      end
    end
  end
  return displays.pick(profiles, screens)
end

-- Run as a script by omv doctor: prints each problem in the file, and fails when there's one.
if arg and arg[0] and arg[0]:match("displays%.lua$") and arg[1] == "check" then
  local file = io.open(arg[2] or displays.PATH, "r")
  if not file then os.exit(0) end
  local text = file:read("*a")
  file:close()
  local problems = displays.parse(text).problems
  for _, problem in ipairs(problems) do print(problem) end
  os.exit(#problems == 0 and 0 or 1)
end

return displays
