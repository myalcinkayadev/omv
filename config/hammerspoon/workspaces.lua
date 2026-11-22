-- Workspaces: ~/.config/omv/workspaces says which workspaces exist, 1 to 9; the screens each
-- prefers, in order, so it lands right whatever is plugged in; the apps that live on it, its
-- layout and the app to open when it's empty; and each screen's gaps and layout. omv builds
-- AeroSpace's keys, pins, gaps and app rules from
-- it, and the bar draws one item per workspace.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit; the aerospace.toml
-- build loads it, and omv doctor runs it as a script:
--   luajit workspaces.lua check <file>      each problem in the file; fails when there's one
--   luajit workspaces.lua names <seen file>  the displays seen, for omv displays

local inifile = require("inifile")

local workspaces = {}

workspaces.PATH = (os.getenv("HOME") or "") .. "/.config/omv/workspaces"

-- Today's workspaces: 1 to 3 and the dev workspace 7 on the main screen, 4 to 6 on the next.
local DEFAULT_ON = { { "main" }, { "main" }, { "main" }, { "screen 2", "main" }, { "screen 2", "main" }, { "screen 2", "main" }, { "main" } }
local DEFAULT_DEV = "7"
local FORCE_TABLE = "workspace-to-monitor-force-assignment"
-- The built-in screen's top gap: macOS already keeps windows clear of the notch there. The bar
-- on other displays is this tall, so the outer gap goes below it. omv's gaps otherwise.
local NOTCH_TOP, BAR_HEIGHT, DEFAULT_GAP = 14, 36, 10
local LAYOUTS = { tiles = true, tabs = true }
-- omv's apps on today's workspaces, by bundle id, so they match whatever language macOS names
-- them in: the terminal, the editor, the browser; notes and planning; messages; music.
local DEFAULT_APPS = {
  { "com.mitchellh.ghostty" }, { "dev.zed.Zed" }, { "net.imput.helium" }, { "md.obsidian", "notion.id", "com.linear" },
  { "com.apple.Notes", "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "com.hnc.Discord" }, { "com.apple.Music", "com.spotify.client" }, {},
}

-- The left-to-right mark AeroSpace puts in front of some apps' names, such as WhatsApp's.
local LRM = "\226\128\142"

-- An app's name without that mark, as it's saved.
function workspaces.appName(app)
  return (tostring(app):gsub("^" .. LRM, ""))
end

-- An app's name to compare by: without the mark, lowercase.
local function appKey(app)
  return workspaces.appName(app):lower()
end

-- Whether an apps entry is a bundle id, such as com.apple.Notes, rather than an app's name.
local function isBundleId(app)
  return app:find("%.") ~= nil and not app:find("%s")
end
workspaces.isBundleId = isBundleId

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function items(text)
  local found = {}
  for item in tostring(text or ""):gmatch("[^,]+") do
    item = trim(item)
    if item ~= "" then found[#found + 1] = item end
  end
  return found
end

-- A screen word in one spelling: main, screen N, laptop, or a display's name as written.
-- secondary, AeroSpace's word for the other screen when there are two, is screen 2.
local function screenWord(value)
  local lower = value:lower()
  if lower == "main" or lower == "laptop" then return lower end
  if lower == "secondary" then return "screen 2" end
  local number = lower:match("^screen%s+(%d)$")
  if number then return "screen " .. number end
  return value
end
workspaces.screenWord = screenWord

-- A list of screens in order, main added last when it isn't there.
local function onList(text)
  local chain, hasMain = {}, false
  for _, item in ipairs(items(text)) do
    local word = screenWord(item)
    if word == "main" then hasMain = true end
    chain[#chain + 1] = word
  end
  if not hasMain then chain[#chain + 1] = "main" end
  return chain
end

local function defaultWorkspaces()
  local found = {}
  for number, on in ipairs(DEFAULT_ON) do
    local chain = {}
    for _, word in ipairs(on) do chain[#chain + 1] = word end
    local apps = {}
    for _, app in ipairs(DEFAULT_APPS[number]) do apps[#apps + 1] = app end
    found[tostring(number)] = { on = chain, apps = apps }
  end
  return found
end

local function wholeNumber(value)
  return value:match("^%d+$") and tonumber(value) or nil
end

-- Fills workspace from one key = value line; gives a problem, or nil.
local function workspaceSetting(workspace, key, value, appsOn, number)
  if key == "on" then workspace.on = onList(value)
  elseif key == "apps" then
    workspace.apps = {}
    for _, app in ipairs(items(value)) do
      if appsOn[appKey(app)] then return app .. " is already on workspace " .. appsOn[appKey(app)] end
      appsOn[appKey(app)] = number
      workspace.apps[#workspace.apps + 1] = app
    end
  elseif key == "layout" then
    if not LAYOUTS[value:lower()] then return "layout is tiles or tabs" end
    workspace.layout = value:lower()
  elseif key == "open" then workspace.open = value
  else return "unknown setting " .. key end
  return nil
end

-- Fills screen from one key = value line; gives a problem, or nil.
local function screenSetting(screen, key, value)
  if key == "layout" then
    if not LAYOUTS[value:lower()] then return "layout is tiles or tabs" end
    screen.layout = value:lower()
    return nil
  end
  if key ~= "gaps" and key ~= "gaps.inner" and key ~= "gaps.outer" then return "unknown setting " .. key end
  local number = wholeNumber(value)
  if not number then return key .. " is a whole number" end
  if key ~= "gaps.outer" then screen.inner = number end
  if key ~= "gaps.inner" then screen.outer = number end
  return nil
end

-- The file's text, or nil without one: { workspaces = { ["2"] = { on, apps, layout, open } },
-- screens = { [name] = { inner, outer, layout } }, dev, problems }. Without [workspace]
-- sections, or with a problem, today's workspaces stand, so the desktop always has some.
function workspaces.parse(text)
  local list = { workspaces = {}, screens = {}, problems = {} }
  if text == nil then
    list.workspaces, list.dev = defaultWorkspaces(), DEFAULT_DEV
    return list
  end
  local seen, appsOn, number = {}, {}, 0
  local current = nil
  local function problem(line, reason) list.problems[#list.problems + 1] = "line " .. line .. ": " .. reason end
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    number = number + 1
    local plain = trim((line:gsub("#.*$", "")))
    local header = plain:match("^%[(.*)%]$")
    if header then
      header = trim(header):gsub("%s+", " ")
      local kind, name = header:match("^(%a+) (.+)$")
      kind = kind and kind:lower()
      current = nil
      local key = kind and (kind .. " " .. name:lower())
      if kind == "workspace" then
        local workspace = tonumber(name)
        if not workspace or workspace < 1 or workspace > 9 or not name:match("^%d$") then
          problem(number, "a workspace is a number from 1 to 9")
        elseif seen[key] then problem(number, "workspace " .. name .. " is already on line " .. seen[key])
        else
          seen[key] = number
          current = { kind = "workspace", name = name, value = { on = { "main" }, apps = {} } }
          list.workspaces[name] = current.value
        end
      elseif kind == "screen" then
        if seen[key] then problem(number, "screen " .. name .. " is already on line " .. seen[key])
        else
          seen[key] = number
          current = { kind = "screen", value = {} }
          list.screens[screenWord(name)] = current.value
        end
      else
        problem(number, "unknown section " .. header .. "; it's [workspace N] or [screen NAME]")
      end
    elseif plain ~= "" then
      local key, value = plain:match("^([^=]-)%s*=%s*(.-)$")
      key = key and trim(key):lower()
      if not key or key == "" or (value == "" and key ~= "apps") then problem(number, "expected name = value")
      elseif not current and key == "dev" then list.dev = value
      elseif not current and key:match("^%d$") then
        problem(number, key .. " = " .. value .. " is the old form; write [workspace " .. key .. "] then on = " .. value)
      elseif not current then problem(number, key .. " is outside a section")
      elseif current.kind == "workspace" then
        local reason = workspaceSetting(current.value, key, value, appsOn, current.name)
        if reason then problem(number, reason) end
      elseif current.kind == "screen" then
        local reason = screenSetting(current.value, key, value)
        if reason then problem(number, reason) end
      end
    end
  end
  if #list.problems > 0 or next(list.workspaces) == nil then list.workspaces = defaultWorkspaces() end
  list.dev = list.dev or DEFAULT_DEV
  return list
end

-- The workspaces, as strings, in number order.
function workspaces.numbers(list)
  local numbers = {}
  for workspace in pairs(list.workspaces) do numbers[#numbers + 1] = workspace end
  table.sort(numbers, function(a, b) return tonumber(a) < tonumber(b) end)
  return numbers
end

-- The dev layout's workspace: dev when it's one of them, otherwise the last.
function workspaces.devWorkspace(list)
  if list.dev and list.workspaces[list.dev] then return list.dev end
  local numbers = workspaces.numbers(list)
  return numbers[#numbers]
end

-- A display's name as AeroSpace's case-insensitive pattern in a TOML literal string: regex
-- characters escaped, single quotes left out.
local function namePattern(name)
  return (name:gsub("'", ""):gsub("[%^%$%(%)%.%[%]%*%+%?%{%}%|\\]", "\\%0"))
end

local function patternList(patterns)
  patterns[#patterns + 1] = "'main'"
  return #patterns == 1 and "'main'" or "[" .. table.concat(patterns, ", ") .. "]"
end

-- The TOML value pinning a workspace to its screens before omv knows the screens plugged in:
-- screen 2 is AeroSpace's secondary; screen 3 and up wait for workspaces.resolve.
function workspaces.staticPattern(on)
  local patterns = {}
  for _, word in ipairs(on) do
    if word == "screen 2" then patterns[#patterns + 1] = "'secondary'"
    elseif word == "laptop" then patterns[#patterns + 1] = "'built-in'"
    elseif word ~= "main" and not word:match("^screen %d$") then patterns[#patterns + 1] = "'" .. namePattern(word) .. "'" end
  end
  return patternList(patterns)
end

local KEYS = {
  { "alt-%d", "workspace %d" },
  { "alt-shift-%d", "move-node-to-workspace %d" },
  { "alt-keypad%d", "workspace %d" },
  { "alt-shift-keypad%d", "move-node-to-workspace %d" },
}

local function isWorkspaceKey(line)
  return line:match("^%s*alt%-%d%s*=") or line:match("^%s*alt%-shift%-%d%s*=")
    or line:match("^%s*alt%-keypad%d%s*=") or line:match("^%s*alt%-shift%-keypad%d%s*=")
end

-- Option+Enter's binding, which opens a Ghostty window, going to the workspace list keeps
-- Ghostty on, or staying on the current one when none does.
local function ghosttyKey(line, list)
  local home = workspaces.homeOf(list, "Ghostty", "com.mitchellh.ghostty")
  if home then return (line:gsub("'workspace %w+'", "'workspace " .. home .. "'", 1)) end
  return (line:gsub("'workspace %w+',%s*", "", 1))
end

-- omv's default aerospace.toml with its workspaces replaced by list's: the workspaces kept
-- alive, their pins, and their keys. Everything else is left as it is.
function workspaces.rewriteDefaults(text, list)
  local numbers = workspaces.numbers(list)
  local quoted, pins, keys = {}, {}, {}
  for _, workspace in ipairs(numbers) do
    quoted[#quoted + 1] = "'" .. workspace .. "'"
    pins[#pins + 1] = workspace .. " = " .. workspaces.staticPattern(list.workspaces[workspace].on)
  end
  for _, key in ipairs(KEYS) do
    for _, workspace in ipairs(numbers) do
      keys[#keys + 1] = string.format(key[1], workspace) .. " = '" .. string.format(key[2], workspace) .. "'"
    end
  end
  local out, inPins, keysWritten = {}, false, false
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    local header = line:match("^%s*%[([^%[%]]+)%]%s*$")
    if header then inPins = trim(header) == FORCE_TABLE end
    if line:match("^%s*persistent%-workspaces%s*=") then
      out[#out + 1] = "persistent-workspaces = [" .. table.concat(quoted, ", ") .. "]"
    elseif header and inPins then
      out[#out + 1] = line
      for _, pin in ipairs(pins) do out[#out + 1] = pin end
    elseif inPins and (line:match("^%s*%d+%s*=") or line:match("^%s*#")) then
      -- omv's own pins and their comments, replaced above.
    elseif line:match("^%s*alt%-enter%s*=") then
      out[#out + 1] = ghosttyKey(line, list)
    elseif isWorkspaceKey(line) then
      if not keysWritten then
        for _, key in ipairs(keys) do out[#out + 1] = key end
        keysWritten = true
      end
    else
      out[#out + 1] = line
    end
  end
  if out[#out] == "" then out[#out] = nil end
  return table.concat(out, "\n") .. "\n"
end

-- screens ({ name, builtin, main, x } each) left to right, and the ones that aren't main.
local function arranged(screens)
  local byX = {}
  for _, screen in ipairs(screens or {}) do byX[#byX + 1] = screen end
  table.sort(byX, function(a, b) return (a.x or 0) < (b.x or 0) end)
  local others = {}
  for position, screen in ipairs(byX) do
    if not screen.main then others[#others + 1] = { screen = screen, position = position } end
  end
  return byX, others
end

-- The screen a word names among screens, or nil: main, laptop, screen N, or part of a name.
local function screenFor(word, screens, others)
  local nth = tonumber(word:match("^screen (%d)$") or "")
  if nth then return others[nth - 1] and others[nth - 1].screen or nil end
  for _, screen in ipairs(screens) do
    if word == "main" and screen.main then return screen end
    if word == "laptop" and screen.builtin then return screen end
    if word ~= "main" and word ~= "laptop" and tostring(screen.name or ""):lower():find(word:lower(), 1, true) then return screen end
  end
  return nil
end

-- Each workspace's pin as a TOML value for the screens plugged in. screen N becomes
-- AeroSpace's position of that screen among all screens; one that isn't plugged in is left out.
function workspaces.resolve(list, screens)
  local _, others = arranged(screens)
  local resolved = {}
  for workspace, entry in pairs(list.workspaces) do
    local patterns = {}
    for _, word in ipairs(entry.on) do
      local nth = tonumber(word:match("^screen (%d)$") or "")
      if nth then
        if others[nth - 1] then patterns[#patterns + 1] = tostring(others[nth - 1].position) end
      elseif word == "laptop" then patterns[#patterns + 1] = "'built-in'"
      elseif word ~= "main" then patterns[#patterns + 1] = "'" .. namePattern(word) .. "'" end
    end
    resolved[workspace] = patternList(patterns)
  end
  return resolved
end

-- AeroSpace's pin table for resolved pins, in number order.
function workspaces.assignmentToml(resolved, list)
  local lines = { "[" .. FORCE_TABLE .. "]" }
  for _, workspace in ipairs(workspaces.numbers(list)) do
    if resolved[workspace] then lines[#lines + 1] = workspace .. " = " .. resolved[workspace] end
  end
  return table.concat(lines, "\n") .. "\n"
end

-- The screen among screens plugged in that a word names, or nil.
function workspaces.screenOf(word, screens)
  local _, others = arranged(screens)
  return screenFor(word, screens or {}, others)
end

-- The screen workspace is on with screens plugged in: the first of its screens there, as the
-- word it was written with, and the screen itself.
function workspaces.landsOn(list, workspace, screens)
  local _, others = arranged(screens)
  for _, word in ipairs(list.workspaces[workspace].on) do
    local screen = screenFor(word, screens or {}, others)
    if screen then return word, screen end
  end
  return "main", nil
end

-- The [screen] section that describes screen, or nil: by its name, main, laptop or screen N.
local function sectionFor(list, screen, screens)
  if not screen then return nil end
  local _, others = arranged(screens)
  local names = {}
  for name in pairs(list.screens) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    if screenFor(name, screens, others) == screen then return list.screens[name] end
  end
  return nil
end

-- Each workspace's layout for the screens plugged in: its own, else its screen's; workspaces
-- with neither are left as they are.
function workspaces.layoutPlan(list, screens)
  local plan = {}
  for workspace, entry in pairs(list.workspaces) do
    local _, screen = workspaces.landsOn(list, workspace, screens)
    local section = sectionFor(list, screen, screens)
    plan[workspace] = entry.layout or (section and section.layout) or nil
  end
  return plan
end

-- A display's name as a pattern inside a TOML basic string: regex characters escaped, then the
-- backslashes doubled.
local function monitorName(name)
  return (tostring(name):gsub('"', ""):gsub("[%^%$%(%)%.%[%]%*%+%-%?%{%}%|\\]", "\\%0"):gsub("\\", "\\\\"))
end

local function monitorPattern(name, screens)
  if name == "main" then return "main" end
  if name == "laptop" then return "built-in" end
  if name:match("^screen %d$") then
    local _, others = arranged(screens)
    local screen = screenFor(name, screens or {}, others)
    return screen and monitorName(screen.name) or nil
  end
  return monitorName(name)
end

local function perScreen(entries, fallback)
  if #entries == 0 then return tostring(fallback) end
  local parts = {}
  for _, entry in ipairs(entries) do parts[#parts + 1] = '{ monitor."' .. entry.pattern .. '" = ' .. entry.value .. " }" end
  parts[#parts + 1] = tostring(fallback)
  return "[" .. table.concat(parts, ", ") .. "]"
end

-- The [gaps] table for the screens' own gaps, or nil when none sets any. The built-in screen
-- keeps the notch's top gap; other displays clear the bar.
function workspaces.gapsToml(list, screens)
  local names = {}
  for name in pairs(list.screens) do names[#names + 1] = name end
  table.sort(names)
  local inner, outer = {}, {}
  for _, name in ipairs(names) do
    local section, pattern = list.screens[name], monitorPattern(name, screens)
    if pattern and section.inner then inner[#inner + 1] = { pattern = pattern, value = section.inner } end
    if pattern and section.outer then outer[#outer + 1] = { pattern = pattern, value = section.outer } end
  end
  if #inner == 0 and #outer == 0 then return nil end
  local lines = { "[gaps]" }
  if #inner > 0 then
    lines[#lines + 1] = "inner.horizontal = " .. perScreen(inner, DEFAULT_GAP)
    lines[#lines + 1] = "inner.vertical = " .. perScreen(inner, DEFAULT_GAP)
  end
  if #outer > 0 then
    local value = perScreen(outer, DEFAULT_GAP)
    lines[#lines + 1] = "outer.left = " .. value
    lines[#lines + 1] = "outer.right = " .. value
    lines[#lines + 1] = "outer.bottom = " .. value
    local top = { { pattern = "built-in", value = NOTCH_TOP } }
    for _, entry in ipairs(outer) do
      if entry.pattern ~= "built-in" then top[#top + 1] = { pattern = entry.pattern, value = BAR_HEIGHT + entry.value } end
    end
    lines[#lines + 1] = "outer.top = " .. perScreen(top, BAR_HEIGHT + DEFAULT_GAP)
  end
  return table.concat(lines, "\n") .. "\n"
end




-- The AeroSpace rules that send each workspace's apps there when they open a window, in
-- workspace order; "" without apps. The build puts them before omv's own.
function workspaces.appRules(list)
  local blocks = {}
  for _, workspace in ipairs(workspaces.numbers(list)) do
    for _, app in ipairs(list.workspaces[workspace].apps or {}) do
      -- AeroSpace puts a left-to-right mark before some names, such as WhatsApp's.
      local match = isBundleId(app) and ("if.app-id = '" .. app:gsub("'", "") .. "'")
        or ("if.app-name-regex-substring = '(?i)^" .. LRM .. "?" .. namePattern(app) .. "$'")
      blocks[#blocks + 1] = "[[on-window-detected]]\n" .. match .. "\nrun = 'move-node-to-workspace " .. workspace .. "'\n"
    end
  end
  return table.concat(blocks, "\n")
end

-- The workspace each app lives on, by its lowercase name.
local function homes(list)
  local found = {}
  for workspace, entry in pairs(list.workspaces) do
    for _, app in ipairs(entry.apps or {}) do found[appKey(app)] = workspace end
  end
  return found
end
workspaces.homes = homes

-- The workspace list keeps an app on, found by its name or its bundle id, either nil; nil when
-- none keeps it.
function workspaces.homeOf(list, name, bundle)
  local found = homes(list)
  return (bundle and found[appKey(bundle)]) or (name and found[appKey(name)]) or nil
end

-- The open windows of apps that aren't on their workspace, from aerospace list-windows lines
-- of "<id>|<bundle id>|<app>|<workspace>": { { id, to } }, of only the apps in only (lowercase names) when
-- given. An app on several workspaces is left alone.
function workspaces.appMoves(list, text, only)
  local target = homes(list)
  local windows, places = {}, {}
  for id, bundle, app, workspace in tostring(text or ""):gmatch("(%d+)|([^|\n]*)|([^|\n]*)|(%S+)") do
    -- An app is kept by its bundle id or its name; the key is whichever the file has.
    local key = target[appKey(bundle)] and appKey(bundle) or appKey(app)
    if target[key] and (not only or only[key]) then
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

-- The apps, by lowercase name, whose workspace differs between two lists, so a save moves
-- only their windows.
function workspaces.movedApps(before, after)
  local old, new, moved = homes(before), homes(after), {}
  for app, workspace in pairs(new) do
    if old[app] ~= workspace then moved[app] = true end
  end
  for app in pairs(old) do
    if not new[app] then moved[app] = true end
  end
  return moved
end

-- Where the rules in a built aerospace.toml send each app when it opens a window, by bundle
-- id: { [id] = workspace }. AeroSpace takes the first rule that matches, so the first wins.
function workspaces.ruleHomes(text)
  local found = {}
  -- Each block runs to the next [, which starts the next table; a run list is left out.
  for block in tostring(text or ""):gmatch("%[%[on%-window%-detected%]%]([^%[]*)") do
    local id = block:match("if%.app%-id%s*=%s*'([^']+)'")
    local workspace = block:match("run%s*=%s*'move%-node%-to%-workspace%s+(%w+)'")
    if id and workspace and not found[id] then found[id] = workspace end
  end
  return found
end

-- The windows of apps taken off their workspace from before to after, each to where the
-- rules send its app now: { { id, to } }. windows are aerospace list-windows lines of
-- "<id>|<bundle id>|<app>|<workspace>"; an app without a rule, or whose rule names a
-- workspace that doesn't exist, stays where it is.
function workspaces.forgottenMoves(before, after, windows, ruled)
  local kept = homes(after)
  local forgotten = {}
  for app in pairs(homes(before)) do
    if not kept[app] then forgotten[app] = true end
  end
  local moves = {}
  for id, bundle, app, workspace in tostring(windows or ""):gmatch("(%d+)|([^|\n]*)|([^|\n]*)|(%S+)") do
    local to = (forgotten[appKey(app)] or forgotten[appKey(bundle)]) and ruled[bundle]
    if to and to ~= workspace and after.workspaces[to] then moves[#moves + 1] = { id = id, to = to } end
  end
  return moves
end

-- The layouts to set moving from one layout plan to another: each that changed, and tiles,
-- AeroSpace's own, for one no longer set. A plan is { [workspace] = "tiles" or "tabs" }.
function workspaces.layoutChanges(before, after)
  local changes = {}
  for workspace, layout in pairs(after or {}) do
    if (before or {})[workspace] ~= layout then changes[workspace] = layout end
  end
  for workspace in pairs(before or {}) do
    if (after or {})[workspace] == nil then changes[workspace] = "tiles" end
  end
  return changes
end

-- The aerospace arguments that set a workspace's layout: tabs is AeroSpace's accordion. The
-- whole workspace changes, from its root; aerospace refuses --workspace without --root.
function workspaces.layoutArgs(workspace, layout)
  return { "layout", "--workspace", workspace, "--root", layout == "tabs" and "accordion" or "tiles" }
end

-- The app to open on workspace just switched to with count windows on it, when it's empty.
function workspaces.openOnEmpty(list, workspace, count)
  local entry = list.workspaces[tostring(workspace)]
  if count ~= 0 or not entry then return nil end
  return entry.open
end

-- Windows on a workspace that isn't listed, from aerospace list-windows lines of
-- "<window id> <workspace>": { { id, to } }, each to the lowest workspace left.
function workspaces.strayWindows(text, list)
  local lowest = workspaces.numbers(list)[1]
  local moves = {}
  for id, workspace in tostring(text or ""):gmatch("(%d+)%s+(%S+)") do
    if not list.workspaces[workspace] then moves[#moves + 1] = { id = id, to = lowest } end
  end
  return moves
end

-- Editing. Each change keeps the file's comments and other lines.

local function onText(on)
  local words = {}
  for _, word in ipairs(on) do
    if word ~= "main" then words[#words + 1] = word end
  end
  return #words > 0 and table.concat(words, ", ") or "main"
end

-- text with today's workspaces written out when it has no [workspace] section, so a change to
-- one keeps the others.
local function materialize(text, list)
  text = tostring(text or "")
  for _, workspace in ipairs(workspaces.numbers(list)) do
    if inifile.hasSection(text, "workspace " .. workspace) then return text end
  end
  for _, workspace in ipairs(workspaces.numbers(list)) do
    text = inifile.set(text, "workspace " .. workspace, "on", onText(list.workspaces[workspace].on))
    local apps = list.workspaces[workspace].apps or {}
    if #apps > 0 then text = inifile.set(text, "workspace " .. workspace, "apps", table.concat(apps, ", ")) end
  end
  return text
end

local function appsText(apps)
  return #apps > 0 and table.concat(apps, ", ") or nil
end

-- text without app on any workspace.
-- Whether an apps entry is app, by its name or its bundle id, other.
local function sameApp(existing, app, other)
  return appKey(existing) == appKey(app) or (other ~= nil and appKey(existing) == appKey(other))
end

local function withoutApp(text, list, app, other)
  for _, workspace in ipairs(workspaces.numbers(list)) do
    local kept, removed = {}, false
    for _, existing in ipairs(list.workspaces[workspace].apps or {}) do
      if sameApp(existing, app, other) then removed = true else kept[#kept + 1] = existing end
    end
    if removed then text = inifile.set(text, "workspace " .. workspace, "apps", appsText(kept)) end
  end
  return text
end

-- text with app, a name or a bundle id, living on workspace, taken off any other. other is the
-- same app the other way, its name or bundle id, so an entry written either way goes.
function workspaces.keepApp(text, list, app, workspace, other)
  app = workspaces.appName(app)
  text = withoutApp(materialize(text, list), list, app, other)
  local apps = {}
  for _, existing in ipairs((list.workspaces[workspace] or { apps = {} }).apps or {}) do
    if not sameApp(existing, app, other) then apps[#apps + 1] = existing end
  end
  apps[#apps + 1] = app
  return inifile.set(text, "workspace " .. workspace, "apps", appsText(apps))
end

-- text with app living nowhere in particular; other is its name or bundle id the other way.
function workspaces.forgetApp(text, list, app, other)
  return withoutApp(materialize(text, list), list, app, other)
end

-- text with its workspaces back to today's, omv's apps on them, and the lines taken out; its
-- screens, dev line and comments stay.
function workspaces.resetWorkspaces(text)
  text = tostring(text or "")
  local names, removed = {}, {}
  for name in text:gmatch("%[%s*[Ww][Oo][Rr][Kk][Ss][Pp][Aa][Cc][Ee]%s+([^%]]-)%s*%]") do names[#names + 1] = name end
  for _, name in ipairs(names) do
    local block
    text, block = inifile.removeSection(text, "workspace " .. name)
    removed[#removed + 1] = block
  end
  return materialize(text, workspaces.parse(nil)), table.concat(removed)
end

-- text with the lowest free workspace added on screen, then main, and its number; nil when all
-- nine exist.
function workspaces.addWorkspace(text, list, screen)
  for workspace = 1, 9 do
    if not list.workspaces[tostring(workspace)] then
      local number = tostring(workspace)
      return inifile.set(materialize(text, list), "workspace " .. number, "on", onText({ screen or "main" })), number
    end
  end
  return nil
end

-- text without workspace, and the lines taken out; nil when it's the last one.
function workspaces.removeWorkspace(text, list, workspace)
  if #workspaces.numbers(list) <= 1 then return nil end
  return inifile.removeSection(materialize(text, list), "workspace " .. workspace)
end

-- text with workspace's screens set, in order; main isn't written, since it's always last.
function workspaces.setOn(text, list, workspace, on)
  return inifile.set(materialize(text, list), "workspace " .. workspace, "on", onText(on))
end

-- text with one of workspace's settings, layout or open, set, or removed for nil.
function workspaces.setWorkspace(text, list, workspace, key, value)
  return inifile.set(materialize(text, list), "workspace " .. workspace, key, value)
end

-- text with screen's gaps set: one gaps line when they're equal, each kind otherwise.
function workspaces.setScreenGaps(text, screen, inner, outer)
  local section = "screen " .. screen
  local equal = inner ~= nil and inner == outer
  text = inifile.set(text, section, "gaps", equal and inner or nil)
  text = inifile.set(text, section, "gaps.inner", (not equal) and inner or nil)
  return inifile.set(text, section, "gaps.outer", (not equal) and outer or nil)
end

-- text with screen's layout set, or removed for nil.
function workspaces.setScreenLayout(text, screen, layout)
  return inifile.set(text, "screen " .. screen, "layout", layout)
end

-- Every display omv has seen, so a workspace or a screen can name one that isn't plugged in now.
-- One line each: the date last seen, 1 when built in, 1 when plugged in now, and the name.
workspaces.SEEN_PATH = (os.getenv("HOME") or "") .. "/.local/state/omv/displays-seen"

function workspaces.recordSeen(seen, screens, date)
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

function workspaces.formatSeen(seen)
  local lines = {}
  for _, entry in ipairs(seen or {}) do
    lines[#lines + 1] = table.concat({ entry.last, entry.builtin and "1" or "0", entry.now and "1" or "0", entry.name }, "\t")
  end
  return #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
end

function workspaces.parseSeen(text)
  local seen = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local last, builtin, now, name = line:match("^([^\t]*)\t([01])\t([01])\t(.+)$")
    if name then seen[#seen + 1] = { name = name, last = last, builtin = builtin == "1", now = now == "1" } end
  end
  return seen
end

-- The names to write a when or on line with: those plugged in now, then those seen before.
function workspaces.nameLines(seen)
  local now, before = {}, {}
  for _, entry in ipairs(seen or {}) do
    if entry.now then
      now[#now + 1] = (string.format("  %-26s%s", entry.name, entry.builtin and "(built-in, laptop)" or "")):gsub("%s+$", "")
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

local function readFile(path)
  local file = path and io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

if arg and arg[0] and arg[0]:match("workspaces%.lua$") and arg[1] == "check" then
  local list = workspaces.parse(readFile(arg[2] or workspaces.PATH))
  for _, problem in ipairs(list.problems) do print(problem) end
  os.exit(#list.problems == 0 and 0 or 1)
end
if arg and arg[0] and arg[0]:match("workspaces%.lua$") and arg[1] == "names" then
  for _, line in ipairs(workspaces.nameLines(workspaces.parseSeen(readFile(arg[2])))) do print(line) end
end

return workspaces
