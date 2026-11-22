-- The rows of the Workspaces card and the cards it opens, a workspace's and a screen's, and of
-- the window card (Option+W), with how Left and Right step their values.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local workspaces = require("workspaces")

local cards = {}

local GAP_STEPS = { 0, 2, 4, 6, 8, 10, 12, 16, 20, 24 }
local LAYOUTS = { "tiles", "tabs" }

local function shown(value, none)
  return "‹  " .. (value == nil and (none or "keep") or tostring(value)) .. "  ›"
end

local function copy(values)
  local copied = {}
  for key, value in pairs(values or {}) do copied[key] = value end
  return copied
end

-- Words wrap around through nil, which comes first.
local function stepWord(words, value, direction)
  local position = 0
  for index, word in ipairs(words) do
    if word == value then position = index end
  end
  return words[(position + direction) % (#words + 1)]
end

-- Numbers stop at nil and at the largest; one off the list goes to the nearest that way.
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

-- current after or before among choices. With allowNil, nil (off, the screen's, keep) comes
-- first; without it, they wrap and one that isn't among them steps to the first or the last.
function cards.stepChoice(current, direction, choices, allowNil)
  if allowNil then return stepWord(choices, current, direction) end
  local position = 0
  for index, choice in ipairs(choices) do
    if choice == current then position = index end
  end
  if position == 0 then return direction > 0 and choices[1] or choices[#choices] end
  return choices[(position - 1 + direction) % #choices + 1]
end

-- A screen's values with id stepped: gaps (both kinds, from the larger going right and the
-- smaller left), gaps.inner, gaps.outer or layout.
function cards.step(values, id, direction)
  local stepped = copy(values)
  if id == "gaps" then
    local inner, outer = stepped.inner, stepped.outer
    local from = inner
    if inner ~= outer and direction > 0 then from = (inner and outer) and math.max(inner, outer) or inner or outer
    elseif inner ~= outer then from = (inner and outer) and math.min(inner, outer) or nil end
    local value = stepNumber(GAP_STEPS, from, direction)
    stepped.inner, stepped.outer = value, value
  elseif id == "gaps.inner" then stepped.inner = stepNumber(GAP_STEPS, stepped.inner, direction)
  elseif id == "gaps.outer" then stepped.outer = stepNumber(GAP_STEPS, stepped.outer, direction)
  elseif id == "layout" then stepped.layout = stepWord(LAYOUTS, stepped.layout, direction) end
  return stepped
end

local function gapsSummary(section)
  if not section or (section.inner == nil and section.outer == nil) then return "omv's gaps" end
  if section.inner == section.outer then return "gaps " .. section.inner end
  return "gaps " .. (section.inner or "omv's") .. " · " .. (section.outer or "omv's")
end

-- The [screen] section name a screen's word is under: its own, or a shorter or longer name for
-- the same display, such as DELL for DELL U2723QE; the word itself when there's none yet.
function cards.screenKey(list, word)
  if list.screens[word] then return word end
  local names = {}
  for name in pairs(list.screens) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local a, b = name:lower(), word:lower()
    if a ~= "laptop" and b ~= "laptop" and (a:find(b, 1, true) or b:find(a, 1, true)) then return name end
  end
  return word
end

-- An apps list as shown: each bundle id by its app's name from names, when installed.
local function appList(apps, names)
  local shown = {}
  for _, app in ipairs(apps or {}) do shown[#shown + 1] = (names or {})[app] or app end
  return table.concat(shown, ", ")
end

-- The Workspaces card: each workspace, where it is now, its apps and layout; Add and Reset;
-- each screen omv has seen or the file names, with its gaps and layout. names gives installed
-- apps' names by bundle id.
function cards.mainRows(list, screens, seen, names)
  local rows, dev = {}, workspaces.devWorkspace(list)
  for _, number in ipairs(workspaces.numbers(list)) do
    local entry = list.workspaces[number]
    local parts = { "on " .. workspaces.landsOn(list, number, screens) }
    if entry.apps and #entry.apps > 0 then parts[#parts + 1] = appList(entry.apps, names) end
    if entry.layout then parts[#parts + 1] = entry.layout end
    if number == dev then parts[#parts + 1] = "dev layout" end
    rows[#rows + 1] = { id = "workspace:" .. number, group = "Workspaces", icon = "󰕰", label = number, hint = table.concat(parts, " · ") .. "  ›" }
  end
  for number = 1, 9 do
    if not list.workspaces[tostring(number)] then
      rows[#rows + 1] = { id = "add", group = "Workspaces", icon = "󰐕", label = "Add workspace " .. number, hint = "then pick what goes there" }
      break
    end
  end
  rows[#rows + 1] = { id = "reset", group = "Workspaces", icon = "󰑓", label = "Reset to omv's workspaces", hint = "1 to 7 with omv's apps" }
  local listed = {}
  local function addScreen(word)
    for _, existing in ipairs(listed) do
      if cards.screenKey({ screens = { [existing] = true } }, word) == existing then return end
    end
    listed[#listed + 1] = word
  end
  for _, entry in ipairs(seen or {}) do addScreen(entry.builtin and "laptop" or entry.name) end
  local named = {}
  for name in pairs(list.screens) do named[#named + 1] = name end
  table.sort(named)
  for _, name in ipairs(named) do addScreen(name) end
  -- The screens a workspace lands on now; one plugged in that none does still shows a
  -- workspace AeroSpace keeps for it, so it's marked.
  local used = {}
  for _, number in ipairs(workspaces.numbers(list)) do
    local _, screen = workspaces.landsOn(list, number, screens)
    if screen then used[screen] = true end
  end
  for _, word in ipairs(listed) do
    local section = list.screens[cards.screenKey(list, word)]
    local hint = gapsSummary(section) .. ((section and section.layout) and (" · " .. section.layout) or "")
    local plugged = workspaces.screenOf(word, screens)
    if plugged and not used[plugged] then hint = "no workspace here · " .. hint end
    rows[#rows + 1] = { id = "screen:" .. word, group = "Screens", icon = "󰍹", label = word, hint = hint .. "  ›" }
  end
  return rows
end

-- A workspace's card: its screens in order, main always last; its layout; its apps and the
-- app to open when it's empty.
function cards.workspaceRows(entry, names)
  local rows, index = {}, 0
  for _, word in ipairs(entry.on or {}) do
    if word ~= "main" then
      index = index + 1
      rows[#rows + 1] = { id = "on:" .. index, group = "On", icon = "󰍹", label = index == 1 and "First" or "Then", hint = shown(word) }
    end
  end
  rows[#rows + 1] = { id = "on:add", group = "On", icon = "󰐕", label = index == 0 and "Pick a screen" or "Then try another",
    hint = "before main" }
  rows[#rows + 1] = { id = "on:main", group = "On", icon = "󰍹", label = "Then", hint = "main, always last" }
  rows[#rows + 1] = { id = "layout", group = "Workspace", icon = "󰕰", label = "Layout", hint = shown(entry.layout, "the screen's") }
  for _, app in ipairs(entry.apps or {}) do
    rows[#rows + 1] = { id = "app:" .. app, group = "Apps", icon = "󰀻", label = (names or {})[app] or app, hint = "⌫ remove" }
  end
  rows[#rows + 1] = { id = "add", group = "Apps", icon = "󰐕", label = "Add an app…", hint = "from the apps open now" }
  rows[#rows + 1] = { id = "open", group = "Apps", icon = "󰐊", label = "Open when empty", hint = shown(entry.open and ((names or {})[entry.open] or entry.open) or nil, "off") }
  return rows
end

-- A screen's card: its gaps, both kinds or each, and its layout.
function cards.screenRows(values)
  values = values or {}
  local inner, outer = values.inner, values.outer
  local all = inner == outer and inner or ((inner or "keep") .. " · " .. (outer or "keep"))
  return {
    { id = "gaps", icon = "󰘖", label = "All gaps", hint = shown(all) },
    { id = "gaps.inner", icon = "󰤼", label = "Gaps between windows", hint = shown(inner) },
    { id = "gaps.outer", icon = "󰢡", label = "Gaps at the screen edges", hint = shown(outer) },
    { id = "layout", icon = "󰕰", label = "Layout", hint = shown(values.layout) },
  }
end

-- The window card: info is { app, workspace, kept, open, next, nextScreen }, next being the
-- workspace a new one would be, nil when all nine exist.
function cards.windowRows(info)
  local rows = {}
  if info.kept then
    rows[#rows + 1] = { id = "keep", icon = "󰄬", label = "Kept on workspace " .. info.workspace, hint = "every time it opens" }
  else
    rows[#rows + 1] = { id = "keep", icon = "󰐃", label = "Keep " .. info.app .. " on workspace " .. info.workspace, hint = "every time it opens" }
  end
  rows[#rows + 1] = { id = "move", icon = "󰕰", label = "Move to workspace…", hint = "and keep it there  ›" }
  if info.next then
    rows[#rows + 1] = { id = "new", icon = "󰐕", label = "Move to a new workspace", hint = info.next .. ", on " .. (info.nextScreen or "main") }
  end
  rows[#rows + 1] = { id = "open", icon = "󰐊", label = "Open " .. info.app .. " when " .. info.workspace .. " is empty", hint = info.open and "on" or "off" }
  rows[#rows + 1] = { id = "forget", icon = "󰆴", label = "Forget " .. info.app .. "'s place", hint = "opens where you are" }
  return rows
end

-- Move to workspace…: each workspace with where it is and its apps, the one the window is on
-- marked; then a new workspace when there's room.
function cards.moveRows(list, current, screens, names)
  local rows = {}
  for _, number in ipairs(workspaces.numbers(list)) do
    local entry = list.workspaces[number]
    local hint = "on " .. workspaces.landsOn(list, number, screens)
    if entry.apps and #entry.apps > 0 then hint = hint .. " · " .. appList(entry.apps, names) end
    if number == current then hint = hint .. "  ·  here now" end
    rows[#rows + 1] = { id = "workspace:" .. number, icon = "󰕰", label = number, hint = hint }
  end
  for number = 1, 9 do
    if not list.workspaces[tostring(number)] then
      local screen = list.workspaces[current] and workspaces.landsOn(list, current, screens) or "main"
      rows[#rows + 1] = { id = "new", icon = "󰐕", label = "New workspace " .. number, hint = "on " .. screen .. ", Option+" .. number }
      break
    end
  end
  return rows
end

-- The apps open now to put on workspace, each with where it lives, if anywhere; those already
-- there are left out; then typing a name. running is { { name, bundle, workspace } }; a row's
-- id carries the bundle id when there is one, so the file keeps the app whatever its name.
function cards.appChoices(running, list, workspace)
  local rows, seen = {}, {}
  for _, app in ipairs(running or {}) do
    local home = workspaces.homeOf(list, app.name, app.bundle)
    local entry = (app.bundle and app.bundle ~= "") and app.bundle or app.name
    if not seen[entry] and home ~= workspace then
      seen[entry] = true
      rows[#rows + 1] = { id = "app:" .. entry, icon = "󰀻", label = app.name, hint = home and ("on " .. home) or "open, no place yet" }
    end
  end
  rows[#rows + 1] = { id = "type", icon = "󰌌", label = "Type an app's name…", hint = "for one that isn't open" }
  return rows
end

-- How many lines a card's rows take: one each, and one per group header.
function cards.lineCount(rows)
  local lines, last = #rows, nil
  for _, row in ipairs(rows) do
    if row.group and row.group ~= last then lines = lines + 1 end
    last = row.group
  end
  return lines
end

-- The screens a workspace's row steps through: the laptop, screen 2 up to one past those
-- plugged in, and each display seen that isn't built in.
function cards.screenChoices(count, seen)
  local choices = { "laptop" }
  for number = 2, math.min(9, math.max(2, count + 1)) do choices[#choices + 1] = "screen " .. number end
  for _, entry in ipairs(seen or {}) do
    if not entry.builtin then choices[#choices + 1] = entry.name end
  end
  return choices
end

return cards
