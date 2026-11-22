-- Display profiles: ~/.config/omv/displays names a few settings for each setup, such as tabs and
-- tight gaps on the laptop alone, and tiles and roomy gaps at the desk. omv picks the first
-- profile whose displays are plugged in, and applies what it sets; leaving a profile puts back
-- what it changed. This reads the file, picks the profile, and works out what changes.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit; omv doctor runs it
-- as a script to check the file: luajit displays.lua check <file>.

local displays = {}

local HOME = os.getenv("HOME") or ""

-- The profiles file: ~/.config/omv/profiles, or the displays file it was called before, while
-- only that one exists. exists says whether a path is there.
function displays.pathFor(exists)
  local profiles, old = HOME .. "/.config/omv/profiles", HOME .. "/.config/omv/displays"
  if exists(profiles) or not exists(old) then return profiles end
  return old
end

displays.PATH = displays.pathFor(function(path)
  local file = io.open(path, "r")
  if file then file:close() end
  return file ~= nil
end)

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

-- A screen word in one spelling, as the workspaces file writes it: main, screen N, laptop, or
-- a display's name as written; secondary is screen 2.
local function screenWord(value)
  local lower = value:lower()
  if lower == "main" or lower == "laptop" then return lower end
  if lower == "secondary" then return "screen 2" end
  local nth = lower:match("^screen%s+(%d)$")
  if nth then return "screen " .. nth end
  return value
end

-- workspace.N = screen (or default), then tiles or tabs, then the apps that live there.
local function workspaceSetting(profile, workspace, value)
  local number = tonumber(workspace)
  if number < 1 or number > 9 then return "a workspace is a number from 1 to 9" end
  local items = list(value)
  local entry, start = { apps = {} }, 2
  if items[1] and items[1]:lower() ~= "default" then entry.screen = screenWord(items[1]) end
  if items[2] and (items[2]:lower() == "tiles" or items[2]:lower() == "tabs") then
    entry.layout, start = items[2]:lower(), 3
  end
  profile.appsOn = profile.appsOn or {}
  for index = start, #items do
    local app = items[index]
    local already = profile.appsOn[app:lower()]
    if already then return app .. " is already on workspace " .. already end
    profile.appsOn[app:lower()] = tostring(number)
    entry.apps[#entry.apps + 1] = app
  end
  profile.settings.workspaces = profile.settings.workspaces or {}
  profile.settings.workspaces[tostring(number)] = entry
  return nil
end

-- gaps.SCREEN, gaps.SCREEN.inner or gaps.SCREEN.outer: one screen's gaps. raw keeps the
-- screen's name as written.
local function screenGapsSetting(profile, raw, value)
  local screen, kind = raw:match("^[Gg][Aa][Pp][Ss]%.(.+)%.([Ii][Nn][Nn][Ee][Rr])$")
  if not screen then screen, kind = raw:match("^[Gg][Aa][Pp][Ss]%.(.+)%.([Oo][Uu][Tt][Ee][Rr])$") end
  if not screen then screen = raw:match("^[Gg][Aa][Pp][Ss]%.(.+)$") end
  local number = value:match("^%d+$") and tonumber(value)
  if not number then return raw .. " must be a whole number" end
  screen = screenWord(screen)
  profile.settings.screenGaps = profile.settings.screenGaps or {}
  local gaps = profile.settings.screenGaps[screen] or {}
  if not kind or kind:lower() == "inner" then gaps.inner = number end
  if not kind or kind:lower() == "outer" then gaps.outer = number end
  profile.settings.screenGaps[screen] = gaps
  return nil
end

-- Fills profile from one name = value line; gives a problem, or nil. raw is the name as
-- written, for a display's name inside it.
local function setting(profile, name, value, gapsGiven, raw)
  if name == "when" and value:lower() == "any" then
    profile.any = true
    return nil
  end
  local workspace = name:match("^workspace%.(%d+)$")
  if workspace then return workspaceSetting(profile, workspace, value) end
  local open = name:match("^open%.(%d+)$")
  if open then
    if tonumber(open) < 1 or tonumber(open) > 9 then return "a workspace is a number from 1 to 9" end
    profile.settings.open = profile.settings.open or {}
    profile.settings.open[tostring(tonumber(open))] = value
    return nil
  end
  if name:match("^gaps%..+") and name ~= "gaps.inner" and name ~= "gaps.outer" then
    return screenGapsSetting(profile, raw or name, value)
  end
  if name == "when" then
    -- built-in only is what when said before laptop named the built-in screen.
    profile.when = value:lower() == "built-in only" and { "laptop" } or list(value)
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

-- The file's text, or nil when there's none: { profiles = { { name, when, count,
-- settings } }, problems = { "line 3: …" } }. A bad line is skipped and named in problems; so is
-- a section with a bad or repeated name, with its lines.
function displays.parse(text)
  local profiles, problems = {}, {}
  local current, gaps = nil, nil
  -- Each name's line, by its lowercase form, so Laptop and laptop are one name.
  local named = {}
  -- The line of the profile with when = any; there can be one.
  local anyLine = nil
  local function close()
    if not current or current.skipped then return end
    -- gaps.inner and gaps.outer win over gaps, wherever they are in the section.
    current.settings.gapsInner = current.settings.gapsInner or gaps.inner
    current.settings.gapsOuter = current.settings.gapsOuter or gaps.outer
    current.appsOn = nil
    if not current.any and (not current.when or #current.when == 0) then problems[#problems + 1] = "profile " .. current.name .. " has no when line" end
    profiles[#profiles + 1] = current
  end
  local number = 0
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    number = number + 1
    local plain = trim((line:gsub("#.*$", "")))
    if plain:sub(1, 1) == "[" then
      close()
      local section = trim(plain:match("^%[([^%[%]]*)%]$") or "")
      current, gaps = { name = section, settings = {} }, {}
      local problem
      -- A # starts a comment, so a name with one has lost its ] by now.
      if section == "" then problem = "a profile's name can't have [, ] or #"
      elseif named[section:lower()] then problem = "a profile named " .. section .. " is already on line " .. named[section:lower()]
      else named[section:lower()] = number end
      if problem then
        problems[#problems + 1] = "line " .. number .. ": " .. problem
        current.skipped = true
      end
    elseif plain ~= "" then
      local name, value = plain:match("^([%w%-%.][%w%-%. ]-)%s*=%s*(.-)$")
      local problem
      if not name or value == "" then problem = "expected name = value"
      elseif not current then problem = name .. " is outside a [profile]"
      elseif name:lower() == "when" and value:lower() == "any" and anyLine then
        problem = "only one profile can be when = any; the first is on line " .. anyLine
      else
        problem = setting(current, name:lower(), value, gaps, name)
        if not problem and name:lower() == "when" and value:lower() == "any" then anyLine = number end
      end
      if problem then problems[#problems + 1] = "line " .. number .. ": " .. problem end
    end
  end
  close()
  return { profiles = profiles, problems = problems }
end

-- Whether a screen is the one a part of when names: laptop is the built-in screen; anything
-- else is part of a display's name, in any case.
local function fits(item, screen)
  if item:lower() == "laptop" then return screen.builtin == true end
  return tostring(screen.name or ""):lower():find(item:lower(), 1, true) ~= nil
end

-- Whether each part of when from index on can have a screen of its own among those not used.
local function assign(items, screens, index, used)
  if index > #items then return true end
  for position, screen in ipairs(screens) do
    if not used[position] and fits(items[index], screen) then
      used[position] = true
      if assign(items, screens, index + 1, used) then return true end
      used[position] = nil
    end
  end
  return false
end

-- A profile is for exactly the screens its when names, each part a screen of its own: laptop,
-- DELL is the laptop open beside a DELL, and nothing else plugged in.
local function matches(profile, screens)
  if profile.count and #screens ~= profile.count then return false end
  local items = profile.when or {}
  if #items == 0 or #items ~= #screens then return false end
  return assign(items, screens, 1, {})
end

-- The first profile whose displays are plugged in, in file order; else the when = any one;
-- nil when there's neither. screens is { { name, builtin } } for each display.
function displays.pick(profiles, screens)
  local fallback = nil
  for _, profile in ipairs(profiles or {}) do
    if profile.any then fallback = fallback or profile
    elseif matches(profile, screens) then return profile end
  end
  return fallback
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

-- Whether two profiles' settings are the same, so an edit to the profile in use is noticed;
-- workspaces and screens' gaps are compared all the way down.
function displays.sameSettings(a, b)
  a, b = a or {}, b or {}
  for key, value in pairs(a) do
    local other = b[key]
    if type(value) == "table" and type(other) == "table" then
      if not displays.sameSettings(value, other) then return false end
    elseif other ~= value then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

-- omv's own gaps, used for the screens a profile doesn't name.
local DEFAULT_GAP = 10

-- A display's name as a pattern inside a TOML basic string: regex characters escaped, then
-- the backslashes doubled.
local function monitorName(name)
  return (tostring(name):gsub('"', ""):gsub("[%^%$%(%)%.%[%]%*%+%-%?%{%}%|\\]", "\\%0"):gsub("\\", "\\\\"))
end

-- AeroSpace's monitor pattern for a screen word, for the screens plugged in; nil for a
-- screen N that isn't plugged in. screen N is the Nth screen from the left that isn't main.
local function monitorPattern(screen, screens)
  if screen == "main" then return "main" end
  if screen == "laptop" then return "built-in" end
  local nth = tonumber(screen:match("^screen (%d)$") or "")
  if not nth then return monitorName(screen) end
  local others = {}
  for _, candidate in ipairs(screens or {}) do
    if not candidate.main then others[#others + 1] = candidate end
  end
  table.sort(others, function(a, b) return (a.x or 0) < (b.x or 0) end)
  return others[nth - 1] and monitorName(others[nth - 1].name) or nil
end

-- A gap's TOML value: per-screen entries first, then the value for every other screen.
local function perScreen(entries, fallback)
  if #entries == 0 then return tostring(fallback) end
  local parts = {}
  for _, entry in ipairs(entries) do parts[#parts + 1] = '{ monitor."' .. entry.pattern .. '" = ' .. entry.value .. " }" end
  parts[#parts + 1] = tostring(fallback)
  return "[" .. table.concat(parts, ", ") .. "]"
end

-- The [gaps] table AeroSpace builds in after the user's own settings, or nil when the profile
-- sets no gaps: its gaps for every screen, and screens' own (screenGaps) for the screens
-- plugged in. The built-in screen keeps the notch's top gap; other displays clear the bar.
function displays.aerospaceGaps(settings, screens)
  local inner, outer = settings.gapsInner, settings.gapsOuter
  local names = {}
  for screen in pairs(settings.screenGaps or {}) do names[#names + 1] = screen end
  table.sort(names)
  local innerEntries, outerEntries = {}, {}
  for _, screen in ipairs(names) do
    local gaps, pattern = settings.screenGaps[screen], monitorPattern(screen, screens)
    if pattern and gaps.inner then innerEntries[#innerEntries + 1] = { pattern = pattern, value = gaps.inner } end
    if pattern and gaps.outer then outerEntries[#outerEntries + 1] = { pattern = pattern, value = gaps.outer } end
  end
  if not inner and not outer and #innerEntries == 0 and #outerEntries == 0 then return nil end
  local lines = { "[gaps]" }
  if inner or #innerEntries > 0 then
    local value = perScreen(innerEntries, inner or DEFAULT_GAP)
    lines[#lines + 1] = "inner.horizontal = " .. value
    lines[#lines + 1] = "inner.vertical = " .. value
  end
  if outer or #outerEntries > 0 then
    local value = perScreen(outerEntries, outer or DEFAULT_GAP)
    lines[#lines + 1] = "outer.left = " .. value
    lines[#lines + 1] = "outer.right = " .. value
    lines[#lines + 1] = "outer.bottom = " .. value
    local top = { { pattern = "built-in", value = NOTCH_TOP } }
    for _, entry in ipairs(outerEntries) do
      if entry.pattern ~= "built-in" then top[#top + 1] = { pattern = entry.pattern, value = BAR_HEIGHT + entry.value } end
    end
    lines[#lines + 1] = "outer.top = " .. perScreen(top, BAR_HEIGHT + (outer or DEFAULT_GAP))
  end
  return table.concat(lines, "\n") .. "\n"
end

local function sortedWorkspaces(workspaces)
  local numbers = {}
  for workspace in pairs(workspaces or {}) do numbers[#numbers + 1] = workspace end
  table.sort(numbers, function(a, b) return tonumber(a) < tonumber(b) end)
  return numbers
end

-- Each workspace's layout when moving from settings before to after: a workspace's own, else
-- the profile's; tiles for one the old profile laid out and the new one doesn't. numbers are
-- the workspaces there are.
function displays.layoutPlan(before, after, numbers)
  before, after = before or {}, after or {}
  local plan = {}
  for _, workspace in ipairs(numbers or {}) do
    local own = after.workspaces and after.workspaces[workspace]
    local old = before.workspaces and before.workspaces[workspace]
    local layout = (own and own.layout) or after.layout
    if layout then plan[workspace] = layout
    elseif (old and old.layout) or before.layout then plan[workspace] = "tiles" end
  end
  return plan
end

-- The AeroSpace rules that send each app in the profile's workspaces there when it opens a
-- window, in workspace order; "" without apps. The profile layer puts them before omv's own.
function displays.appRules(settings)
  local blocks = {}
  for _, workspace in ipairs(sortedWorkspaces(settings.workspaces)) do
    for _, app in ipairs(settings.workspaces[workspace].apps or {}) do
      local pattern = app:gsub("'", ""):gsub("[%^%$%(%)%.%[%]%*%+%?%{%}%|\\]", "\\%0")
      blocks[#blocks + 1] = "[[on-window-detected]]\nif.app-name-regex-substring = '(?i)^" .. pattern .. "$'\n"
        .. "run = 'move-node-to-workspace " .. workspace .. "'\n"
    end
  end
  return table.concat(blocks, "\n")
end

-- The open windows of the profile's apps that aren't on their workspace, from aerospace
-- list-windows lines of "<id>|<app>|<workspace>": { { id, to } }. An app with windows on more
-- than one workspace is left where it is.
function displays.appMoves(settings, text)
  local target = {}
  for _, workspace in ipairs(sortedWorkspaces(settings.workspaces)) do
    for _, app in ipairs(settings.workspaces[workspace].apps or {}) do target[app:lower()] = workspace end
  end
  local windows, places = {}, {}
  for id, app, workspace in tostring(text or ""):gmatch("(%d+)|([^|\n]*)|(%S+)") do
    local key = app:lower()
    if target[key] then
      windows[key] = windows[key] or {}
      windows[key][#windows[key] + 1] = id
      places[key] = places[key] or {}
      places[key][workspace] = true
    end
  end
  local moves = {}
  for app, ids in pairs(windows) do
    local count, only = 0, nil
    for workspace in pairs(places[app]) do count, only = count + 1, workspace end
    if count == 1 and only ~= target[app] then
      for _, id in ipairs(ids) do moves[#moves + 1] = { id = id, to = target[app] } end
    end
  end
  return moves
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

-- A profile's settings in a few words, for the card and the notice: tabs · gaps 4 · font 15.
function displays.summary(profile)
  local settings, parts = profile.settings, {}
  if settings.layout then parts[#parts + 1] = settings.layout end
  if settings.gapsOuter or settings.gapsInner then parts[#parts + 1] = "gaps " .. (settings.gapsOuter or settings.gapsInner) end
  if settings.quiet == "on" then parts[#parts + 1] = "quiet" end
  if settings.theme then parts[#parts + 1] = settings.theme end
  if settings.font then parts[#parts + 1] = "font " .. settings.font end
  return table.concat(parts, " · ")
end

-- Whether profiles has name, in any case.
local function taken(profiles, name)
  for _, profile in ipairs(profiles or {}) do
    if profile.name:lower() == name:lower() then return true end
  end
  return false
end

-- The card's rows: each profile, the one in use marked, and Follow the displays; then saving
-- the displays as a profile and opening the file, which are all it has without profiles.
-- state is { active, picked, deleted }: the profile in use, whether it was picked by hand,
-- and one just deleted, { name, index }, offered back in its place.
function displays.rows(profiles, state, screens)
  local rows = {}
  for _, profile in ipairs(profiles or {}) do
    local hint = profile.name == state.active and ("in use" .. (state.picked and " · picked" or "")) or displays.summary(profile)
    if hint == "" then hint = "nothing set" end
    rows[#rows + 1] = { id = "profile:" .. profile.name, icon = "󰍹", label = profile.name, hint = hint }
  end
  -- A deleted profile is offered back only while its name is free.
  if state.deleted and not taken(profiles, state.deleted.name) then
    table.insert(rows, math.min(state.deleted.index, #rows + 1),
      { id = "undo", icon = "󰕌", label = "Bring back " .. state.deleted.name, hint = "deleted just now" })
  end
  local any = #(profiles or {}) > 0
  if any then rows[#rows + 1] = { id = "follow", icon = "󰑐", label = "Follow the displays", hint = "automatic" } end
  local found = displays.pick(profiles, screens)
  rows[#rows + 1] = { id = "save", icon = "󰐕", label = "Save these displays as a profile",
    hint = found and ("already: " .. found.name) or "then edit it here" }
  rows[#rows + 1] = { id = "file", icon = "󰷈", label = "Open the profiles file", hint = any and "applies on save" or "with examples" }
  return rows
end

-- The profile editor: Left and Right step each setting; keep is nil, a setting not set.
local GAP_STEPS = { 0, 2, 4, 6, 8, 10, 12, 16, 20, 24 }
local FONT_STEPS = { 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 }
local WORDS = { layout = { "tiles", "tabs" }, bar = { "shown", "hidden" }, quiet = { "on", "off" } }
-- Each editor row's setting field; gaps sets both.
local FIELDS = { layout = "layout", ["gaps.inner"] = "gapsInner", ["gaps.outer"] = "gapsOuter", font = "font",
  theme = "theme", bar = "bar", quiet = "quiet" }

local function copy(settings)
  local copied = {}
  for key, value in pairs(settings or {}) do copied[key] = value end
  return copied
end

-- Words wrap around through keep; value nil is keep.
local function stepWord(words, value, direction)
  local position = 0
  for index, word in ipairs(words) do
    if word == value then position = index end
  end
  return words[(position + direction) % (#words + 1)]
end

-- Numbers stop at keep and at the largest; one off the list goes to the nearest that way.
local function stepNumber(steps, value, direction)
  if direction > 0 then
    if value == nil then return steps[1] end
    for _, number in ipairs(steps) do
      if number > value then return number end
    end
    return value
  end
  if value == nil then return nil end
  for index = #steps, 1, -1 do
    if steps[index] < value then return steps[index] end
  end
  return nil
end

-- settings with the row id stepped one way: 1 for Right, -1 for Left. themes are the names
-- the theme row goes through. All gaps sets both: from the larger going right, the smaller left.
function displays.step(settings, id, direction, themes)
  local stepped = copy(settings)
  if id == "gaps" then
    local inner, outer = stepped.gapsInner, stepped.gapsOuter
    local from = inner
    if inner ~= outer and direction > 0 then from = (inner and outer) and math.max(inner, outer) or inner or outer
    elseif inner ~= outer then from = (inner and outer) and math.min(inner, outer) or nil end
    local value = stepNumber(GAP_STEPS, from, direction)
    stepped.gapsInner, stepped.gapsOuter = value, value
    return stepped
  end
  local field = FIELDS[id]
  if not field then return stepped end
  local value = stepped[field]
  if WORDS[id] then stepped[field] = stepWord(WORDS[id], value, direction)
  elseif id == "theme" then stepped[field] = stepWord(themes or {}, value, direction)
  elseif id == "font" then stepped[field] = stepNumber(FONT_STEPS, value, direction)
  else stepped[field] = stepNumber(GAP_STEPS, value, direction) end
  return stepped
end

local function shown(value)
  return "‹  " .. (value == nil and "keep" or tostring(value)) .. "  ›"
end

-- The three gap rows, for every screen or for one: inner and outer as they're set, nil for keep.
function displays.gapRows(inner, outer)
  local all = inner == outer and inner or ((inner or "keep") .. " · " .. (outer or "keep"))
  return {
    { id = "gaps", icon = "󰘖", label = "All gaps", hint = shown(all) },
    { id = "gaps.inner", icon = "󰤼", label = "Gaps between windows", hint = shown(inner) },
    { id = "gaps.outer", icon = "󰢡", label = "Gaps at the screen edges", hint = shown(outer) },
  }
end

local function gapsSummary(inner, outer)
  if inner == nil and outer == nil then return "omv's gaps" end
  if inner == outer then return "gaps " .. inner end
  return "gaps " .. (inner or "keep") .. " · " .. (outer or "keep")
end

-- A workspace's line in the file: its screen or default, its layout, its apps; nil when the
-- profile leaves the workspace alone.
function displays.workspaceLine(entry)
  if not entry then return nil end
  local apps = entry.apps or {}
  if not entry.screen and not entry.layout and #apps == 0 then return nil end
  local items = { entry.screen or "default" }
  if entry.layout then items[#items + 1] = entry.layout end
  for _, app in ipairs(apps) do items[#items + 1] = app end
  return table.concat(items, ", ")
end

-- Whether two screen names are one display: the same, or one part of the other, in any case.
local function sameScreen(a, b)
  a, b = a:lower(), b:lower()
  return a == b or a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

-- The key screen's gaps are under in screenGaps: its own name, or a shorter or longer name for
-- the same display; screen itself when it has none yet.
function displays.gapsKey(settings, screen)
  if (settings.screenGaps or {})[screen] then return screen end
  local keys = {}
  for key in pairs(settings.screenGaps or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    if screen ~= "laptop" and key ~= "laptop" and sameScreen(key, screen) then return key end
  end
  return screen
end

-- The screens a profile's editor lists: those in its when, then any other it gives gaps to.
local function profileScreens(settings)
  local found = {}
  local function add(screen)
    if not screen or screen == "" or screen:lower() == "any" then return end
    for _, listed in ipairs(found) do
      if listed:lower() == screen:lower() or (screen ~= "laptop" and listed ~= "laptop" and sameScreen(listed, screen)) then return end
    end
    found[#found + 1] = screen
  end
  for _, item in ipairs(list(tostring(settings.when or ""))) do add(item) end
  local extra = {}
  for screen in pairs(settings.screenGaps or {}) do extra[#extra + 1] = screen end
  table.sort(extra)
  for _, screen in ipairs(extra) do add(screen) end
  return found
end
displays.profileScreens = profileScreens

-- The editor's rows for profile name's settings: its name and when it's used, with status
-- saying whether it is now; then each workspace in numbers; then all screens and each one;
-- then what applies everywhere. Name, When, workspaces and screens open a card on Enter.
function displays.editRows(settings, name, status, numbers)
  settings = settings or {}
  local rows = {
    { id = "name", icon = "󰑕", label = "Name", hint = tostring(name or "") .. "  ›" },
    { id = "when", icon = "󰍹", label = "When", hint = tostring(settings.when or "") .. (status and (" · " .. status) or "") .. "  ›" },
  }
  for _, workspace in ipairs(numbers or {}) do
    local entry = (settings.workspaces or {})[workspace]
    local parts = { entry and entry.screen or "default" }
    if entry and entry.layout then parts[#parts + 1] = entry.layout end
    if entry and entry.apps and #entry.apps > 0 then parts[#parts + 1] = table.concat(entry.apps, ", ") end
    rows[#rows + 1] = { id = "workspace:" .. workspace, group = "Workspaces", icon = "󰕰", label = workspace,
      hint = table.concat(parts, " · ") .. "  ›" }
  end
  rows[#rows + 1] = { id = "screen:all", group = "Screens", icon = "󰍹", label = "All screens",
    hint = gapsSummary(settings.gapsInner, settings.gapsOuter) .. "  ›" }
  for _, screen in ipairs(profileScreens(settings)) do
    local gaps = (settings.screenGaps or {})[displays.gapsKey(settings, screen)] or {}
    rows[#rows + 1] = { id = "screen:" .. screen, group = "Screens", icon = "󰍹", label = screen, hint = gapsSummary(gaps.inner, gaps.outer) .. "  ›" }
  end
  local everywhere = {
    { id = "layout", icon = "󰕰", label = "Layout", hint = shown(settings.layout) },
    { id = "theme", icon = "󰏘", label = "Theme", hint = shown(settings.theme) },
    { id = "font", icon = "󰛖", label = "Terminal font size", hint = shown(settings.font) .. "   new windows" },
    { id = "bar", icon = "󰍜", label = "Bar", hint = shown(settings.bar) },
    { id = "quiet", icon = "󰂛", label = "Do Not Disturb", hint = shown(settings.quiet) },
  }
  for _, row in ipairs(everywhere) do
    row.group = "Everywhere"
    rows[#rows + 1] = row
  end
  return rows
end

-- A workspace's card: its screen, its layout, its apps, and the app to open when it's empty.
function displays.workspaceRows(entry, open, workspace)
  entry = entry or { apps = {} }
  local rows = {
    { id = "screen", icon = "󰍹", label = "Screen", hint = "‹  " .. (entry.screen or "default") .. "  ›" },
    { id = "layout", icon = "󰕰", label = "Layout", hint = shown(entry.layout) },
  }
  for _, app in ipairs(entry.apps or {}) do
    rows[#rows + 1] = { id = "app:" .. app, group = "Apps", icon = "󰀻", label = app, hint = "⌫ remove" }
  end
  rows[#rows + 1] = { id = "add", group = "Apps", icon = "󰐕", label = "Add an app…", hint = "from the apps open now" }
  rows[#rows + 1] = { id = "open", group = "Apps", icon = "󰐊", label = "Open when empty", hint = "‹  " .. (open or "off") .. "  ›" }
  return rows
end

-- A workspace's screen after or before current: default (nil), main, then the profile's screens.
function displays.stepWorkspaceScreen(current, direction, screens)
  local steps = { "default", "main" }
  for _, screen in ipairs(screens or {}) do
    if screen:lower() ~= "main" then steps[#steps + 1] = screen end
  end
  local position = 1
  for index, step in ipairs(steps) do
    if step == (current or "default") then position = index end
  end
  local next = steps[(position - 1 + direction) % #steps + 1]
  return next ~= "default" and next or nil
end

-- The app to open when the workspace is empty, after or before current: off (nil), then its apps.
function displays.stepOpen(current, direction, apps)
  return stepWord(apps or {}, current, direction)
end

-- The apps open now to add to workspace, each with where the profile puts it, if anywhere;
-- those already on it are left out; then typing a name. running is { { name, workspace } }.
function displays.appChoices(running, settings, workspace)
  local placed = {}
  for _, number in ipairs(sortedWorkspaces(settings.workspaces)) do
    for _, app in ipairs(settings.workspaces[number].apps or {}) do placed[app:lower()] = number end
  end
  local rows, seen = {}, {}
  for _, app in ipairs(running or {}) do
    local key = app.name:lower()
    if not seen[key] and placed[key] ~= workspace then
      seen[key] = true
      rows[#rows + 1] = { id = "app:" .. app.name, icon = "󰀻", label = app.name,
        hint = placed[key] and ("on workspace " .. placed[key]) or "open now" }
    end
  end
  rows[#rows + 1] = { id = "type", icon = "󰌌", label = "Type an app's name…", hint = "for one that isn't open" }
  return rows
end

local function copyWorkspaces(workspaces)
  local copied = {}
  for number, entry in pairs(workspaces or {}) do
    local apps = {}
    for _, app in ipairs(entry.apps or {}) do apps[#apps + 1] = app end
    copied[number] = { screen = entry.screen, layout = entry.layout, apps = apps }
  end
  return copied
end

-- The app to open on workspace when it's just been switched to with count windows on it:
-- the profile's open app for it when it's empty; nil otherwise.
function displays.openOnEmpty(settings, workspace, count)
  if count ~= 0 or not settings or not settings.open then return nil end
  return settings.open[workspace]
end

-- A copy of settings whose workspaces, apps, open apps and screens' gaps can be changed
-- without changing settings.
function displays.copySettings(settings)
  local copied = copy(settings)
  copied.workspaces = copyWorkspaces(settings.workspaces)
  copied.open = copy(settings.open)
  copied.screenGaps = {}
  for screen, gaps in pairs(settings.screenGaps or {}) do copied.screenGaps[screen] = copy(gaps) end
  return copied
end

-- settings with app on workspace, taken off any other; with workspace nil, only taken off.
function displays.placeApp(settings, app, workspace)
  local placed = copy(settings)
  placed.workspaces = copyWorkspaces(settings.workspaces)
  for _, entry in pairs(placed.workspaces) do
    for index = #entry.apps, 1, -1 do
      if entry.apps[index]:lower() == app:lower() then table.remove(entry.apps, index) end
    end
  end
  if workspace then
    placed.workspaces[workspace] = placed.workspaces[workspace] or { apps = {} }
    table.insert(placed.workspaces[workspace].apps, app)
  end
  return placed
end

local function splitLines(text)
  local lines = {}
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  if lines[#lines] == "" then lines[#lines] = nil end
  return lines
end

-- The first and last line of profile name's section: it ends before the next section, a
-- commented one included, so an example section after it is never taken as its own.
local function sectionBounds(lines, name)
  local first
  for index, line in ipairs(lines) do
    local plain = trim((line:gsub("#.*$", "")))
    local header = plain:match("^%[(.*)%]$")
    if first then
      if header or line:match("^%s*#%s*%[.*%]") then return first, index - 1 end
    elseif header and trim(header) == name then
      first = index
    end
  end
  return first, first and #lines or nil
end

local function keyPattern(key)
  return "^%s*" .. key:gsub("%p", "%%%0") .. "%s*="
end

-- The line with value in place of its own, keeping how it's aligned and its comment.
local function replaced(line, value)
  local head, rest = line:match("^(%s*[%w%.%-]+%s*=%s*)(.-)$")
  local comment = rest:match("(%s+#.*)$") or ""
  return head .. value .. comment
end

-- lines with key set to value in the section from first to last, or its line removed for nil;
-- gives the section's new last line.
local function setLine(lines, first, last, key, value)
  local pattern = keyPattern(key)
  for index = first + 1, last do
    if lines[index]:match(pattern) then
      if value == nil then
        table.remove(lines, index)
        return last - 1
      end
      lines[index] = replaced(lines[index], tostring(value))
      return last
    end
  end
  if value == nil then return last end
  for index = first + 1, last do
    local commented = lines[index]:match("^%s*#%s*(.*)$")
    if commented and commented:match(pattern) then
      lines[index] = replaced(commented, tostring(value))
      return last
    end
  end
  local after = last
  while after > first and trim(lines[after]) == "" do after = after - 1 end
  table.insert(lines, after + 1, key .. " = " .. tostring(value))
  return last + 1
end

-- The file's text with profile name's section changed from settings before to after: only the
-- lines of settings that changed. Equal gaps are one gaps line; different ones, gaps.inner and
-- gaps.outer.
function displays.writeSettings(text, name, before, after)
  local lines = splitLines(text)
  local first, last = sectionBounds(lines, name)
  if not first then return text end
  before, after = before or {}, after or {}
  for _, key in ipairs({ "when", "layout", "font", "theme", "bar", "quiet" }) do
    if before[key] ~= after[key] then last = setLine(lines, first, last, key, after[key]) end
  end
  local function keys(a, b)
    local found, seen = {}, {}
    for key in pairs(a or {}) do if not seen[key] then seen[key] = true; found[#found + 1] = key end end
    for key in pairs(b or {}) do if not seen[key] then seen[key] = true; found[#found + 1] = key end end
    table.sort(found)
    return found
  end
  for _, workspace in ipairs(keys(before.workspaces, after.workspaces)) do
    local old = displays.workspaceLine((before.workspaces or {})[workspace])
    local new = displays.workspaceLine((after.workspaces or {})[workspace])
    if old ~= new then last = setLine(lines, first, last, "workspace." .. workspace, new) end
  end
  for _, workspace in ipairs(keys(before.open, after.open)) do
    local old, new = (before.open or {})[workspace], (after.open or {})[workspace]
    if old ~= new then last = setLine(lines, first, last, "open." .. workspace, new) end
  end
  for _, screen in ipairs(keys(before.screenGaps, after.screenGaps)) do
    local old, new = (before.screenGaps or {})[screen] or {}, (after.screenGaps or {})[screen] or {}
    if old.inner ~= new.inner or old.outer ~= new.outer then
      local equal = new.inner ~= nil and new.inner == new.outer
      last = setLine(lines, first, last, "gaps." .. screen, equal and new.inner or nil)
      last = setLine(lines, first, last, "gaps." .. screen .. ".inner", (not equal) and new.inner or nil)
      last = setLine(lines, first, last, "gaps." .. screen .. ".outer", (not equal) and new.outer or nil)
    end
  end
  if before.gapsInner ~= after.gapsInner or before.gapsOuter ~= after.gapsOuter then
    local inner, outer = after.gapsInner, after.gapsOuter
    local equal = inner == outer
    last = setLine(lines, first, last, "gaps", equal and inner or nil)
    last = setLine(lines, first, last, "gaps.inner", (not equal) and inner or nil)
    setLine(lines, first, last, "gaps.outer", (not equal) and outer or nil)
  end
  return table.concat(lines, "\n") .. "\n"
end

-- The file's text without profile name, and the lines taken out: its section, and the comment
-- saving it wrote just above, so the sections around it keep one blank line between them.
function displays.removeProfile(text, name)
  local lines = splitLines(text)
  local first, last = sectionBounds(lines, name)
  if not first then return text end
  while last > first and trim(lines[last]) == "" do last = last - 1 end
  if first > 1 and lines[first - 1]:match("^# Saved .* Rename it to anything%.$") then first = first - 1 end
  while last < #lines and trim(lines[last + 1]) == "" do last = last + 1 end
  local removed = {}
  for _ = first, last do removed[#removed + 1] = table.remove(lines, first) end
  while #removed > 0 and trim(removed[#removed]) == "" do removed[#removed] = nil end
  return table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""), table.concat(removed, "\n") .. "\n"
end

-- Bringing back a deleted profile: the file as it was when it hasn't changed since the delete,
-- or the deleted block added at the end when it has.
function displays.restoreProfile(current, afterDelete, before, block)
  if current == afterDelete then return before end
  return tostring(current or ""):gsub("\n*$", "") .. "\n\n" .. block
end

-- The file's text with profile old named new, its comment after the name kept.
function displays.renameProfile(text, old, new)
  local lines = splitLines(text)
  local first = sectionBounds(lines, old)
  if not first then return text end
  lines[first] = lines[first]:gsub("^(%s*)%[[^%]]*%]", function(space) return space .. "[" .. new .. "]" end, 1)
  return table.concat(lines, "\n") .. "\n"
end

-- The name typed for profile current: trimmed, or current when empty; nil and a problem for
-- one the file can't hold or another profile has.
function displays.checkName(typed, profiles, current)
  local name = trim(tostring(typed or ""))
  if name == "" then return current end
  if name:find("[%[%]#]") then return nil, "a profile's name can't have [, ] or #" end
  for _, profile in ipairs(profiles or {}) do
    if profile.name ~= current and profile.name:lower() == name:lower() then return nil, name .. " is taken" end
  end
  return name
end

-- When a profile is used: { items }, the screens it's for, laptop or parts of display names.
function displays.parseWhen(text)
  text = trim(tostring(text or ""))
  if text:lower() == "built-in only" then return { items = { "laptop" } } end
  return { items = list(text) }
end

function displays.whenText(when)
  return table.concat(when.items, ", ")
end

local function whenIndex(when, item)
  for index, existing in ipairs(when.items) do
    if existing:lower() == item:lower() then return index end
  end
  return nil
end

local function copyWhen(when)
  local items = {}
  for _, item in ipairs(when.items) do items[#items + 1] = item end
  return { items = items }
end

-- when with item, laptop or a display's name, ticked or unticked.
function displays.toggleWhen(when, item)
  local toggled = copyWhen(when)
  -- Any screens stands alone: ticking it unticks the screens, and ticking a screen unticks it.
  if item:lower() == "any" then
    toggled.items = whenIndex(toggled, "any") and {} or { "any" }
    return toggled
  end
  local anyAt = whenIndex(toggled, "any")
  if anyAt then table.remove(toggled.items, anyAt) end
  local index = whenIndex(toggled, item)
  if index then table.remove(toggled.items, index) else toggled.items[#toggled.items + 1] = item end
  return toggled
end

-- when with a typed part of a display's name added, ticked.
function displays.addWhen(when, typed)
  local added = copyWhen(when)
  local item = trim(tostring(typed or ""))
  if item == "" or whenIndex(added, item) then return added end
  added.items[#added.items + 1] = item
  return added
end

-- The when line's text, or nil and a problem when nothing is ticked.
function displays.doneWhen(when)
  if #when.items == 0 then return nil, "pick at least one display" end
  return displays.whenText(when)
end

local TICKED, UNTICKED = "󰄵", "󰄱"

-- The When picker's rows: the laptop screen, each display seen but the built-in one, parts
-- typed that omv hasn't seen, ticked when in when; then typing a part, and Done.
function displays.whenRows(when, seen)
  local rows = { { id = "display:laptop", icon = whenIndex(when, "laptop") and TICKED or UNTICKED, label = "Laptop screen", hint = "built-in" } }
  rows[#rows + 1] = { id = "display:any", icon = whenIndex(when, "any") and TICKED or UNTICKED, label = "Any screens",
    hint = "when nothing else matches" }
  local known = { laptop = true, any = true }
  for _, entry in ipairs(seen or {}) do
    if not entry.builtin then
      known[entry.name:lower()] = true
      rows[#rows + 1] = { id = "display:" .. entry.name, icon = whenIndex(when, entry.name) and TICKED or UNTICKED,
        label = entry.name, hint = entry.now and "plugged in" or ("last seen " .. tostring(entry.last)) }
    end
  end
  for _, item in ipairs(when.items) do
    if not known[item:lower()] then rows[#rows + 1] = { id = "display:" .. item, icon = TICKED, label = item, hint = "typed" } end
  end
  local done, problem = displays.doneWhen(when)
  rows[#rows + 1] = { id = "type", icon = "󰌌", label = "Type part of a name…", hint = "for a display not seen yet" }
  rows[#rows + 1] = { id = "done", icon = "󰄬", label = "Done", hint = done or problem }
  return rows
end

-- Whether profile name is used with screens: the first profile in the file to match wins.
function displays.matchStatus(name, profiles, screens)
  local winner = displays.pick(profiles, screens)
  for _, profile in ipairs(profiles or {}) do
    if profile.name == name and profile.any then
      return (winner and winner.name == name) and "used now, as nothing else matches" or "when nothing else matches"
    end
  end
  if winner and winner.name == name then return "matches now" end
  for _, profile in ipairs(profiles or {}) do
    if profile.name == name and matches(profile, screens) then
      return "matches now, but " .. winner.name .. " comes first"
    end
  end
  return "not plugged in"
end

-- Each check is logged, so a check that didn't happen shows: the load's line without one after.
displays.LOG_LINES = 200

-- A log line: when, why the check ran (load, displays, wake, saved or card), and what it did.
function displays.logLine(time, reason, result)
  local line = os.date("%Y-%m-%d %H:%M:%S", time) .. "  " .. reason
  if not result then return line end
  return line .. string.rep(" ", math.max(1, 10 - #reason)) .. result
end

-- The log text with line added, keeping the last LOG_LINES lines.
function displays.appendLog(text, line)
  local lines = {}
  for kept in tostring(text or ""):gmatch("[^\n]+") do lines[#lines + 1] = kept end
  lines[#lines + 1] = line
  local first = math.max(1, #lines - displays.LOG_LINES + 1)
  return table.concat(lines, "\n", first) .. "\n"
end

-- Every display omv has seen, so a profile can name one that isn't plugged in now. One line
-- each: the date last seen, 1 when built in, 1 when plugged in now, and the name.
displays.SEEN_PATH = (os.getenv("HOME") or "") .. "/.local/state/omv/displays-seen"

-- seen is { { name, last, builtin, now } }; screens are the displays plugged in on date.
function displays.recordSeen(seen, screens, date)
  local recorded, byName = {}, {}
  for _, entry in ipairs(seen or {}) do
    recorded[#recorded + 1] = { name = entry.name, last = entry.last, builtin = entry.builtin, now = false }
    byName[entry.name] = recorded[#recorded]
  end
  for _, screen in ipairs(screens or {}) do
    local name = tostring(screen.name or "")
    local entry = byName[name]
    if not entry then
      entry = { name = name }
      recorded[#recorded + 1] = entry
      byName[name] = entry
    end
    entry.last, entry.builtin, entry.now = date, screen.builtin == true, true
  end
  return recorded
end

function displays.formatSeen(seen)
  local lines = {}
  for _, entry in ipairs(seen or {}) do
    lines[#lines + 1] = table.concat({ entry.last, entry.builtin and "1" or "0", entry.now and "1" or "0", entry.name }, "\t")
  end
  return #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
end

function displays.parseSeen(text)
  local seen = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local last, builtin, now, name = line:match("^([^\t]*)\t([01])\t([01])\t(.+)$")
    if name then seen[#seen + 1] = { name = name, last = last, builtin = builtin == "1", now = now == "1" } end
  end
  return seen
end

-- The names to write a when line with: those plugged in now, then those seen before.
function displays.nameLines(seen)
  local now, before = {}, {}
  for _, entry in ipairs(seen or {}) do
    if entry.now then
      now[#now + 1] = (string.format("  %-26s%s", entry.name, entry.builtin and "(built-in)" or "")):gsub("%s+$", "")
    else
      before[#before + 1] = string.format("  %-26slast seen %s", entry.name, entry.last)
    end
  end
  if #now == 0 and #before == 0 then return { "No display seen yet: plug one in once while Hammerspoon runs." } end
  local lines = { "Plugged in now:" }
  for _, line in ipairs(now) do lines[#lines + 1] = line end
  if #before > 0 then
    lines[#lines + 1] = "Seen before:"
    for _, line in ipairs(before) do lines[#lines + 1] = line end
  end
  return lines
end

local STARTER_HEAD = [[
# Profiles: where workspaces and apps go, and how things look, for each set of screens.
# One [section] per profile; the first whose `when` matches the screens plugged in is used,
# else the one with when = any.
# Leaving a profile puts back what it changed. Save, and omv applies it.
#
]]

local STARTER_BODY = [[
#
# Settings; leave one out to keep omv's own:
#   when     exactly the screens plugged in, comma between: laptop for the
#            laptop's own, and part of a display's name for the others;
#            or any, for when nothing else matches
#   workspace.N  its screen (or default), then tiles or tabs, then its apps:
#            workspace.2 = DELL, tabs, Helium, Arc
#   open.N   the app to open when you go to workspace N and it's empty
#   layout   tiles | tabs, for the workspaces without their own
#   gaps     pixels; gaps.inner and gaps.outer set one kind;
#            gaps.DELL, gaps.laptop.outer and so on set one screen's
#   quiet    on | off            Do Not Disturb while it's used
#   theme    a name from `omv theme`
#   font     Ghostty's font size
#   bar      shown | hidden
#   on-enter, on-leave           a shell command
#
# Remove the # in front of a section's lines to use it. Name a profile anything.

# [desk]
# when        = laptop, DELL U2723QE   # the laptop open beside a DELL, nothing else
# workspace.1 = DELL, tiles, Zed
# workspace.2 = DELL, tabs, Helium
# gaps.DELL   = 10

# [presenting]
# when   = laptop, projector
# layout = tiles
# quiet  = on                   # Do Not Disturb while it's in use

# [laptop]
# when   = laptop
# layout = tabs
# gaps   = 4
]]

-- The file written when there's none: what each setting does, the displays omv knows, and
-- examples left as comments, so it changes nothing until one is used.
function displays.starter(seen)
  local names = {}
  for _, line in ipairs(displays.nameLines(seen)) do names[#names + 1] = "# " .. line end
  return STARTER_HEAD .. table.concat(names, "\n") .. "\n" .. STARTER_BODY
end

-- text with a profile added for exactly the screens plugged in, and the profile's name: the first
-- word of the first display that isn't built in, or laptop, numbered when profiles has it.
-- Its settings are left as comments, so it matches but changes nothing until edited.
function displays.addProfile(text, screens, profiles, date)
  local outside = {}
  for _, screen in ipairs(screens or {}) do
    if not screen.builtin then outside[#outside + 1] = tostring(screen.name) end
  end
  local base = #outside > 0 and (outside[1]:match("^[^%s%(%)%[%]#,]+") or "display"):lower() or "laptop"
  local name, number = base, 2
  while taken(profiles, name) do
    name = base .. " " .. number
    number = number + 1
  end
  local plugged = {}
  for _, screen in ipairs(screens or {}) do
    if screen.builtin then plugged[1] = "laptop" end
  end
  for _, display in ipairs(outside) do plugged[#plugged + 1] = display end
  local lines = {
    "# Saved " .. date .. " for: " .. table.concat(plugged, ", ") .. ". Rename it to anything.",
    "[" .. name .. "]",
    "when = " .. table.concat(plugged, ", "),
    "# layout = tiles",
    "# gaps   = 10",
    "# font   = 15",
  }
  text = tostring(text or "")
  if text ~= "" then text = text:gsub("\n*$", "") .. "\n\n" end
  return text .. table.concat(lines, "\n") .. "\n", name
end

local function readFile(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

-- Run as a script by omv displays: prints the displays omv has seen.
if arg and arg[0] and arg[0]:match("displays%.lua$") and arg[1] == "names" then
  print(table.concat(displays.nameLines(displays.parseSeen(readFile(arg[2] or displays.SEEN_PATH))), "\n"))
  os.exit(0)
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
