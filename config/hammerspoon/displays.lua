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
  local function close()
    if not current or current.skipped then return end
    -- gaps.inner and gaps.outer win over gaps, wherever they are in the section.
    current.settings.gapsInner = current.settings.gapsInner or gaps.inner
    current.settings.gapsOuter = current.settings.gapsOuter or gaps.outer
    if not current.when or #current.when == 0 then problems[#problems + 1] = "profile " .. current.name .. " has no when line" end
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

-- The editor's rows for profile name's settings: its name, when it's used, with status saying
-- whether it is now, then a row per setting. Name and When open a card on Enter, so carry a ›.
function displays.editRows(settings, name, status)
  settings = settings or {}
  local inner, outer = settings.gapsInner, settings.gapsOuter
  local all = inner == outer and inner or ((inner or "keep") .. " · " .. (outer or "keep"))
  return {
    { id = "name", icon = "󰑕", label = "Name", hint = tostring(name or "") .. "  ›" },
    { id = "when", icon = "󰍹", label = "When", hint = tostring(settings.when or "") .. (status and (" · " .. status) or "") .. "  ›" },
    { id = "layout", icon = "󰕰", label = "Layout", hint = shown(settings.layout) },
    { id = "gaps", icon = "󰘖", label = "All gaps", hint = shown(all) },
    { id = "gaps.inner", icon = "󰤼", label = "Gaps between windows", hint = shown(inner) },
    { id = "gaps.outer", icon = "󰢡", label = "Gaps at the screen edges", hint = shown(outer) },
    { id = "font", icon = "󰛖", label = "Terminal font size", hint = shown(settings.font) .. "   new windows" },
    { id = "theme", icon = "󰏘", label = "Theme", hint = shown(settings.theme) },
    { id = "bar", icon = "󰍜", label = "Bar", hint = shown(settings.bar) },
    { id = "quiet", icon = "󰂛", label = "Do Not Disturb", hint = shown(settings.quiet) },
  }
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
  local known = { laptop = true }
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
# Display profiles: settings that follow the displays you plug in.
# One [section] per profile; the first whose `when` matches the screens plugged in is used.
# Leaving a profile puts back what it changed. Save, and omv applies it.
#
]]

local STARTER_BODY = [[
#
# Settings; leave one out to keep omv's own:
#   when     exactly the screens plugged in, comma between: laptop for the
#            laptop's own, and part of a display's name for the others
#   layout   tiles | tabs
#   gaps     pixels; gaps.inner and gaps.outer set one kind
#   quiet    on | off            Do Not Disturb while it's used
#   theme    a name from `omv theme`
#   font     Ghostty's font size
#   bar      shown | hidden
#   on-enter, on-leave           a shell command
#
# Remove the # in front of a section's lines to use it. Name a profile anything.

# [desk]
# when   = laptop, DELL U2723QE  # the laptop open beside a DELL, nothing else
# layout = tiles
# gaps   = 10

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
