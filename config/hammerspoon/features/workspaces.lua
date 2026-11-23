-- Workspaces: ~/.config/omv/workspaces, applied. As displays come and go, each workspace goes
-- to the first of its screens plugged in, each screen gets its gaps, and workspaces get their
-- layouts; saving the file rebuilds AeroSpace's keys and app rules, moves the windows of apps
-- whose workspace changed, and moves windows off a workspace that was removed.
-- screen 2 and on only mean a monitor once the screens are known, so the pins and gaps are
-- worked out here and written for the aerospace.toml build, which reloads AeroSpace.
-- The Workspaces card, in the system menu, edits the file: workspaces and screens.
-- Option+W is the window card: keep the focused app on its workspace, or move it.

local shell = require("shell")
local card = require("card")
local workspaces = require("workspaces")
local cards = require("workspacecards")

local feature = {}

-- The pins and gaps for the screens plugged in, read by install/aerospace_merge.lua.
local SCREENS = shell.STATE_DIR .. "/aerospace-screens.toml"
-- The layouts last set, so a display change sets only those that changed, kept across reloads.
local LAYOUTS = shell.STATE_DIR .. "/workspace-layouts"
-- There while a workspace has an app to open when it's empty; AeroSpace's workspace change
-- tells Hammerspoon only then.
local OPEN_WHEN_EMPTY = shell.STATE_DIR .. "/open-when-empty"
-- Displays often connect in steps; the screens are worked out once they've settled.
local SETTLE_SECONDS = 1.5
-- An editor, or the card's keys, can save a few times in a row; the file is read once they stop.
local SAVED_SECONDS = 1.0
-- How long a removed workspace is offered back once the card closes.
local UNDO_SECONDS = 60
local FOOTER_HEIGHT = 24
-- Lines the Workspaces card shows before it scrolls: its workspaces and screens.
local MAIN_VISIBLE = 20
local INPUT_HEIGHT = 28 + 46 + 44 + 4
local MAIN_FOOTER = { { key = "Enter", text = "open ›" }, { key = "⌫", text = "remove" }, { key = "Esc", text = "close" } }
local WORKSPACE_FOOTER = { { key = "Left/Right", text = "change" }, { key = "Enter", text = "add" }, { key = "⌫", text = "remove" },
  { key = "Esc", text = "back" } }
local SCREEN_FOOTER = { { key = "Left/Right", text = "change" }, { key = "Esc", text = "back" } }

local function readList()
  return workspaces.parse(shell.readText(workspaces.PATH))
end

local function writeFile(path, text)
  if not text then return os.remove(path) end
  local file = io.open(path, "w")
  if not file then return end
  file:write(text)
  file:close()
end

-- Writes the workspaces file; the save watcher applies it.
local function save(text)
  os.execute("/bin/mkdir -p '" .. shell.HOME .. "/.config/omv'")
  writeFile(workspaces.PATH, text)
end

-- { name, builtin, main, x } for each screen. main is the screen macOS puts the menu bar on,
-- as AeroSpace's main; x orders them left to right, as AeroSpace numbers them.
function feature.screens()
  local primary = hs.screen.primaryScreen()
  local found = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local name = screen:name() or ""
    found[#found + 1] = { name = name, builtin = name:find("Built%-in") ~= nil, main = screen == primary, x = screen:fullFrame().x }
  end
  return found
end

-- Every display seen, the ones plugged in now marked, so the cards can name one that isn't.
function feature.seen()
  return workspaces.parseSeen(shell.readText(workspaces.SEEN_PATH))
end

local function recordSeen()
  local seen = workspaces.recordSeen(feature.seen(), feature.screens(), os.date("%Y-%m-%d"))
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
  writeFile(workspaces.SEEN_PATH, workspaces.formatSeen(seen))
end

-- Runs aerospace with arguments in the background and calls done, when given, with what it
-- printed. Never waited on: Hammerspoon runs on one thread, and a card can't scroll or take a
-- key while it waits, as it would for AeroSpace busy reloading.
local function aerospace(arguments, done)
  hs.task.new(shell.AEROSPACE, function(_, output)
    if done then done(output or "") end
  end, arguments):start()
end

-- Moves each of moves, { id, to }, one after the other, then calls done.
local function moveWindows(moves, done, index)
  index = index or 1
  local move = moves[index]
  if not move then
    if done then done() end
    return
  end
  aerospace({ "move-node-to-workspace", "--window-id", move.id, move.to }, function() moveWindows(moves, done, index + 1) end)
end

-- Moves each window on a workspace that isn't listed to the lowest one left, then calls done,
-- so the bar, redrawn after, no longer finds the old workspace.
local function moveStrays(list, done)
  aerospace({ "list-windows", "--all", "--format", "%{window-id} %{workspace}" }, function(output)
    moveWindows(workspaces.strayWindows(output, list), done)
  end)
end

-- AeroSpace's built config, whose rules say where an app goes once no workspace keeps it.
local BUILT = shell.HOME .. "/.config/aerospace/aerospace.toml"

-- Moves the open windows of apps taken off their workspace, from before to after, to where
-- AeroSpace's rules send them now, such as omv's own WhatsApp on 5.
local function moveForgotten(before, after)
  aerospace({ "list-windows", "--all", "--format", "%{window-id}|%{app-bundle-id}|%{app-name}|%{workspace}" }, function(output)
    moveWindows(workspaces.forgottenMoves(before, after, output, workspaces.ruleHomes(shell.readText(BUILT))))
  end)
end

-- Moves the open windows of the apps in only to their workspaces.
local function moveApps(list, only)
  if next(only) == nil then return end
  aerospace({ "list-windows", "--all", "--format", "%{window-id}|%{app-bundle-id}|%{app-name}|%{workspace}" }, function(output)
    moveWindows(workspaces.appMoves(list, output, only))
  end)
end

local function readLayouts()
  local plan = {}
  for workspace, layout in (shell.readText(LAYOUTS) or ""):gmatch("(%d)%s*=%s*(%a+)") do plan[workspace] = layout end
  return plan
end

-- Sets the layouts that changed since they were last set.
local function setLayouts(list, screens)
  local plan = workspaces.layoutPlan(list, screens)
  for workspace, layout in pairs(workspaces.layoutChanges(readLayouts(), plan)) do
    hs.task.new(shell.AEROSPACE, nil, workspaces.layoutArgs(workspace, layout)):start()
  end
  local lines = {}
  for _, workspace in ipairs(workspaces.numbers(list)) do
    if plan[workspace] then lines[#lines + 1] = workspace .. " = " .. plan[workspace] end
  end
  writeFile(LAYOUTS, #lines > 0 and (table.concat(lines, "\n") .. "\n") or nil)
end

local function hasOpen(list)
  for _, entry in pairs(list.workspaces) do
    if entry.open then return true end
  end
  return false
end

-- Writes the pins and gaps for the screens plugged in, and rebuilds AeroSpace's config when
-- they changed; then moves windows off removed workspaces, sets layouts and calls done.
function feature.check(done)
  if type(done) ~= "function" then done = nil end
  local list, screens = readList(), feature.screens()
  local gaps = workspaces.gapsToml(list, screens)
  local text = workspaces.assignmentToml(workspaces.resolve(list, screens), list) .. (gaps and ("\n" .. gaps) or "")
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
  writeFile(OPEN_WHEN_EMPTY, hasOpen(list) and "on\n" or nil)
  local function after()
    setLayouts(list, screens)
    moveStrays(list, done)
  end
  if text == shell.readText(SCREENS) then return after() end
  writeFile(SCREENS, text)
  require("features.aerospacebuild").request(after)
end

-- Sets each workspace's text on the bar: its name as the bar line formats it, or its number.
local function redrawTexts(list)
  local arguments = {}
  for _, workspace in ipairs(workspaces.numbers(list)) do
    arguments[#arguments + 1] = "--set"
    arguments[#arguments + 1] = "space." .. workspace
    arguments[#arguments + 1] = "icon=" .. workspaces.barText(list, workspace)
  end
  hs.task.new(shell.SKETCHYBAR, nil, arguments):start()
end

-- The list as last applied, so a save moves only the apps whose workspace changed.
local applied = readList()

-- Applies a saved file: AeroSpace's keys and app rules, then the screens, the windows of apps
-- whose workspace changed, and the bar, last, once no window is left on a removed workspace.
local function applySaved()
  local list = readList()
  if #list.problems > 0 then return shell.alert("~/.config/omv/workspaces " .. list.problems[1], 5) end
  local before = applied
  local moved = workspaces.movedApps(before, list)
  -- The bar redraws every item on every screen, so only when workspaces came or went.
  local barChanged = table.concat(workspaces.numbers(applied), " ") ~= table.concat(workspaces.numbers(list), " ")
  local textsChanged = table.concat(workspaces.textLines(applied), "\n") ~= table.concat(workspaces.textLines(list), "\n")
  applied = list
  require("devlayout").WORKSPACE = workspaces.devWorkspace(list)
  require("features.aerospacebuild").request(function()
    feature.check(function()
      moveApps(list, moved)
      moveForgotten(before, list)
      if barChanged then hs.task.new(shell.SKETCHYBAR, nil, { "--reload" }):start()
      elseif textsChanged then redrawTexts(list) end
    end)
  end)
end

-- Opens a workspace's app when it was just switched to and is empty.
function feature.workspaceChanged(workspace)
  workspace = tostring(workspace):gsub("[^%w]", "")
  aerospace({ "list-windows", "--workspace", workspace, "--count" }, function(output)
    local app = workspaces.openOnEmpty(readList(), workspace, tonumber(output:match("%d+")))
    if app then hs.task.new("/usr/bin/open", nil, { workspaces.isBundleId(app) and "-b" or "-a", app }):start() end
  end)
end

local function indexOf(rows, id)
  for index, row in ipairs(rows) do
    if row.id == id then return index end
  end
  return 1
end

-- visible is how many lines show before the card scrolls; the Workspaces card shows more, so
-- its screens fit.
local function listFrame(rows, footer, visible)
  return shell.centered(shell.LIST_WIDTH, shell.listHeight(cards.lineCount(rows), visible) + (footer and FOOTER_HEIGHT or 0))
end

-- Each bundle id in list's apps by its app's name, for apps installed, so the cards show names.
local function appNames(list)
  local names = {}
  for _, entry in pairs(list.workspaces) do
    for _, app in ipairs(entry.apps or {}) do
      if workspaces.isBundleId(app) then names[app] = hs.application.nameForBundleID(app) end
    end
    if entry.open and workspaces.isBundleId(entry.open) then names[entry.open] = hs.application.nameForBundleID(entry.open) end
  end
  return names
end

-- Calls done with the apps open now, each with the workspace its first window is on.
local function runningApps(done)
  aerospace({ "list-windows", "--all", "--format", "%{app-bundle-id}|%{app-name}|%{workspace}" }, function(output)
    local found, seen = {}, {}
    for bundle, name, workspace in output:gmatch("([^|\n]*)|([^|\n]+)|(%S+)") do
      local app = workspaces.appName(name)
      if not seen[app] then
        seen[app] = true
        found[#found + 1] = { name = app, bundle = bundle, workspace = workspace }
      end
    end
    table.sort(found, function(a, b) return a.name:lower() < b.name:lower() end)
    done(found)
  end)
end

-- The list, or nil when the file has a problem: then a card can't edit it, and the notice
-- names the line.
local function editable()
  local list = readList()
  if #list.problems == 0 then return list end
  shell.alert("~/.config/omv/workspaces " .. list.problems[1] .. ": fix it to edit", 5)
  return nil
end

-- The change offered back: a workspace removed, or the workspaces reset. { number, label,
-- before, after, block, at }: the file before and after, the lines taken out and when; number
-- is nil for a reset.
local removed = nil

-- Undoes the change offered back: the file as it was when it hasn't changed since, else a
-- removed workspace's lines added at the end. Gives the workspace's number.
local function bringBack()
  local was = removed
  removed = nil
  if not was then return nil end
  local current = shell.readText(workspaces.PATH)
  if current == was.after then save(was.before)
  elseif was.number then save(tostring(current or ""):gsub("\n*$", "") .. "\n\n" .. was.block)
  else shell.alert("The file changed since; your workspaces are in the lines you can undo in an editor", 3) end
  return was.number
end

local showWorkspace

-- Asks for an app's name, for one that isn't open; Enter puts it on the workspace.
local function showTypeApp(workspace)
  shell.show("workspaces", shell.centered(shell.LIST_WIDTH, INPUT_HEIGHT),
    card.html({ prompt = "An app's name, for workspace " .. workspace .. "…", rows = {}, input = true,
      hint = "as macOS names it, such as Visual Studio Code · Esc goes back" }), function(message)
      local typed = message.type == "submit" and (message.id or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
      local list = typed ~= "" and editable()
      if list then save(workspaces.keepApp(shell.readText(workspaces.PATH), list, typed, workspace)) end
      showWorkspace(workspace)
    end, { onEscape = function() showWorkspace(workspace) end })
end

local showAppChoices

-- Asks for workspace's name, its current one typed in; Enter saves it, an empty one removes
-- it. A name the file can't keep says why and stays to be fixed.
local function showName(workspace, typed)
  local list = editable()
  if not list or not list.workspaces[workspace] then return end
  shell.show("workspaces", shell.centered(shell.LIST_WIDTH, INPUT_HEIGHT),
    card.html({ prompt = "A name for workspace " .. workspace .. "…", rows = {}, input = true,
      query = typed or list.workspaces[workspace].name,
      hint = "up to 16 characters, emoji too · empty for none · Esc goes back" }), function(message)
      if message.type ~= "submit" then return showWorkspace(workspace, 1) end
      local text, problem = workspaces.setName(shell.readText(workspaces.PATH), list, workspace, message.id or "")
      if not text then
        shell.alert(problem, 3)
        return showName(workspace, message.id)
      end
      save(text)
      showWorkspace(workspace, 1)
    end, { onEscape = function() showWorkspace(workspace, 1) end })
end

-- The apps open now, to put one on workspace; it comes off any other.
local function showAddApp(workspace)
  runningApps(function(running) showAppChoices(workspace, running) end)
end

-- The apps open now as rows, to put one on workspace.
function showAppChoices(workspace, running)
  local rows = cards.appChoices(running, readList(), workspace)
  shell.show("workspaces", listFrame(rows), card.html({ prompt = "Put an app on workspace " .. workspace .. "…", rows = rows,
    compact = true }), function(message)
    if message.type ~= "choose" then return showWorkspace(workspace) end
    if message.id == "type" then return showTypeApp(workspace) end
    local app = (message.id or ""):match("^app:(.+)$")
    local list = app and editable()
    if list then save(workspaces.keepApp(shell.readText(workspaces.PATH), list, app, workspace)) end
    showWorkspace(workspace)
  end, { onEscape = function() showWorkspace(workspace) end })
end

-- workspace's screens, as written, without main.
local function ownScreens(list, workspace)
  local on = {}
  for _, word in ipairs(list.workspaces[workspace].on) do
    if word ~= "main" then on[#on + 1] = word end
  end
  return on
end

-- on with the first screen it doesn't have yet added at the end.
local function withAnother(on)
  local taken = {}
  for _, word in ipairs(on) do taken[word:lower()] = true end
  for _, choice in ipairs(cards.screenChoices(#feature.screens(), feature.seen())) do
    if not taken[choice:lower()] then
      on[#on + 1] = choice
      return on
    end
  end
  return on
end

-- Left/Right on a workspace's row: a screen, its layout or the app to open; gives whether
-- the row was one of those.
local function stepWorkspace(list, workspace, row, direction)
  local entry, text = list.workspaces[workspace], shell.readText(workspaces.PATH)
  local on = ownScreens(list, workspace)
  local position = tonumber((row or ""):match("^on:(%d+)$") or "")
  if position and on[position] then
    on[position] = cards.stepChoice(on[position], direction, cards.screenChoices(#feature.screens(), feature.seen()))
    save(workspaces.setOn(text, list, workspace, on))
  elseif row == "layout" then
    save(workspaces.setWorkspace(text, list, workspace, "layout", cards.stepChoice(entry.layout, direction, { "tiles", "tabs" }, true)))
  elseif row == "open" then
    save(workspaces.setWorkspace(text, list, workspace, "open", cards.stepChoice(entry.open, direction, entry.apps or {}, true)))
  else
    return false
  end
  return true
end

-- Backspace on a workspace's row: a screen, or an app, which stops opening there too; gives
-- whether the row was one of those.
local function clearWorkspace(list, workspace, id)
  local entry, text = list.workspaces[workspace], shell.readText(workspaces.PATH)
  if id == "name" then
    save(workspaces.setName(text, list, workspace, ""))
    return true
  end
  local position = tonumber(id:match("^on:(%d+)$") or "")
  local app = id:match("^app:(.+)$")
  if position then
    local on = ownScreens(list, workspace)
    table.remove(on, position)
    save(workspaces.setOn(text, list, workspace, on))
    return true
  end
  if not app then return false end
  text = workspaces.forgetApp(text, list, app)
  if entry.open == app then text = workspaces.setWorkspace(text, workspaces.parse(text), workspace, "open", nil) end
  save(text)
  return true
end

-- A workspace's card: its screens in order, its layout, its apps and the app to open when
-- it's empty. Each change is saved at once, and applies once the keys stop.
function showWorkspace(workspace, selected)
  local list = editable()
  if not list then return end
  if not list.workspaces[workspace] then return feature.open() end
  local rows = cards.workspaceRows(list.workspaces[workspace], appNames(list))
  local back = function() feature.open("workspace:" .. workspace) end
  shell.show("workspaces", listFrame(rows, true), card.html({ prompt = "Workspace " .. workspaces.title(list, workspace) .. "…", rows = rows,
    compact = true, step = true, clearable = true, footer = WORKSPACE_FOOTER, selected = selected }), function(message)
    local id = message.id or ""
    if message.type == "step" then
      local direction, row = id:match("^(%-?1):(.+)$")
      if row == "name" then return direction == "1" and showName(workspace) or nil end
      if not stepWorkspace(list, workspace, row, tonumber(direction)) then return end
      return showWorkspace(workspace, indexOf(rows, row))
    end
    if message.type == "clear" then
      if not clearWorkspace(list, workspace, id) then return end
      return showWorkspace(workspace, math.max(1, indexOf(rows, id) - 1))
    end
    if message.type == "choose" and id == "on:add" then
      local on = withAnother(ownScreens(list, workspace))
      save(workspaces.setOn(shell.readText(workspaces.PATH), list, workspace, on))
      return showWorkspace(workspace, #on)
    end
    if message.type == "choose" and id == "add" then return showAddApp(workspace) end
    if message.type == "choose" and id == "name" then return showName(workspace) end
    back()
  end, { onEscape = back })
end

-- A screen's card: its gaps and layout, under the section for that display.
local function showScreen(word, selected)
  local list = editable()
  if not list then return end
  local key = cards.screenKey(list, word)
  local values = list.screens[key] or {}
  local rows = cards.screenRows(values)
  local back = function() feature.open("screen:" .. word) end
  shell.show("workspaces", listFrame(rows, true), card.html({ prompt = word .. "…", rows = rows, compact = true, step = true,
    footer = SCREEN_FOOTER, selected = selected }), function(message)
    if message.type ~= "step" then return back() end
    local direction, row = (message.id or ""):match("^(%-?1):(.+)$")
    local stepped = cards.step(values, row, tonumber(direction))
    local text = shell.readText(workspaces.PATH)
    if row == "layout" then save(workspaces.setScreenLayout(text, key, stepped.layout))
    else save(workspaces.setScreenGaps(text, key, stepped.inner, stepped.outer)) end
    showScreen(word, indexOf(rows, row))
  end, { onEscape = back })
end

-- The Workspaces card's rows, with Bring back after a workspace was removed or all were reset.
local function mainRows(list)
  local rows = cards.mainRows(list, feature.screens(), feature.seen(), appNames(list))
  if removed then
    table.insert(rows, indexOf(rows, "add"), { id = "undo", group = "Workspaces", icon = "󰕌",
      label = removed.label, hint = "just now" })
  end
  return rows
end

-- Backspace on the Workspaces card: removes a workspace, offered back.
local function clearMain(list, rows, id)
  local workspace = id:match("^workspace:(%d)$")
  if workspace then
    local before = shell.readText(workspaces.PATH)
    local after, block = workspaces.removeWorkspace(before, list, workspace)
    if not after then return shell.alert("Keep at least one workspace", 2) end
    save(after)
    removed = { number = workspace, label = "Bring back workspace " .. workspace, before = before, after = after, block = block,
      at = os.time() }
    local following = rows[indexOf(rows, id) + 1]
    return feature.open(following and following.id or nil)
  end
end

-- Enter on the Workspaces card: opens a workspace's or a screen's card, adds a workspace,
-- resets them all, or brings one back.
local function chooseMain(list, id)
  if id == "undo" then
    local number = bringBack()
    return feature.open(number and ("workspace:" .. number) or nil)
  end
  if id == "reset" then
    local before = shell.readText(workspaces.PATH)
    local after, block = workspaces.resetWorkspaces(before)
    save(after)
    removed = { label = "Bring back your workspaces", before = before, after = after, block = block, at = os.time() }
    return feature.open("undo")
  end
  if id == "add" then
    local text, number = workspaces.addWorkspace(shell.readText(workspaces.PATH), list, "main")
    if not text then return end
    save(text)
    return showWorkspace(number)
  end
  local workspace = id:match("^workspace:(%d)$")
  if workspace then return showWorkspace(workspace) end
  local screen = id:match("^screen:(.+)$")
  if screen then return showScreen(screen) end
  shell.close()
end

-- The Workspaces card: workspaces and screens, each opening its own card; Add for the
-- next workspace, and Backspace on one removes it, with Bring back. selected is a row's id.
function feature.open(selected)
  if type(selected) ~= "string" then selected = nil end
  local list = editable()
  if not list then return end
  if removed and (os.time() - removed.at > UNDO_SECONDS or (removed.number and list.workspaces[removed.number])) then removed = nil end
  local rows = mainRows(list)
  shell.show("workspaces", listFrame(rows, true, MAIN_VISIBLE), card.html({ prompt = "Workspaces…", rows = rows, compact = true, clearable = true,
    step = true, footer = MAIN_FOOTER, selected = selected and indexOf(rows, selected) or nil }), function(message)
    if message.type == "clear" then return clearMain(list, rows, message.id or "") end
    if message.type == "step" then
      -- Left and Right change the Bar row; on the others they open or close, as without steps.
      local direction, row = (message.id or ""):match("^(%-?1):(.+)$")
      if row == "bar" then
        save(workspaces.setBar(shell.readText(workspaces.PATH), cards.stepBar(list.bar, tonumber(direction))))
        return feature.open("bar")
      end
      if direction == "1" and row then return chooseMain(list, row) end
      return shell.close()
    end
    if message.type ~= "choose" then return shell.close() end
    chooseMain(list, message.id or "")
  end)
end

-- Calls done with the focused window, its id, app and workspace, or nil.
local function focusedWindow(done)
  aerospace({ "list-windows", "--focused", "--format", "%{window-id}|%{app-bundle-id}|%{app-name}|%{workspace}" }, function(output)
    local id, bundle, app, workspace = output:match("^(%d+)|([^|\n]*)|([^|\n]+)|(%S+)")
    done(id and { id = id, bundle = bundle ~= "" and bundle or nil, app = workspaces.appName(app), workspace = workspace } or nil)
  end)
end

local function lowestFree(list)
  for number = 1, 9 do
    if not list.workspaces[tostring(number)] then return tostring(number) end
  end
  return nil
end

-- Puts window's app on workspace from now on and moves the window there.
local function keepOn(window, list, workspace)
  save(workspaces.keepApp(shell.readText(workspaces.PATH), list, window.bundle or window.app, workspace, window.app))
  if workspace ~= window.workspace then moveWindows({ { id = window.id, to = workspace } }) end
end

-- A new workspace on the screen window's workspace is on, with window's app on it.
local function moveToNew(window, list)
  local screen = list.workspaces[window.workspace] and workspaces.landsOn(list, window.workspace, feature.screens()) or "main"
  local text, number = workspaces.addWorkspace(shell.readText(workspaces.PATH), list, screen)
  if not text then return end
  save(text)
  keepOn(window, workspaces.parse(text), number)
end

-- Move to workspace…: each workspace, then a new one; the window goes there and its app with it.
local function showMove(window)
  local list = editable()
  if not list then return end
  local rows = cards.moveRows(list, window.workspace, feature.screens(), appNames(list))
  shell.show("workspaces", listFrame(rows), card.html({ prompt = "Move " .. window.app .. " to…", rows = rows, compact = true }),
    function(message)
      shell.close()
      if message.type ~= "choose" then return end
      local workspace = (message.id or ""):match("^workspace:(%d)$")
      if workspace then return keepOn(window, list, workspace) end
      if message.id == "new" then moveToNew(window, list) end
    end)
end

local opensHere

-- Moves window to where AeroSpace's rules send its app, such as omv's WhatsApp on 5, whether
-- or not a workspace kept it; it stays where it is without a rule.
local function sendHome(window)
  aerospace({ "list-windows", "--all", "--format", "%{window-id}|%{app-bundle-id}" }, function(output)
    local bundle = ("\n" .. output):match("\n" .. window.id .. "|([^\n]+)")
    local to = bundle and workspaces.ruleHomes(shell.readText(BUILT))[bundle]
    local list = readList()
    if not to or not list.workspaces[to] then return shell.alert(window.app .. " opens on the workspace you're on from now on", 2.5) end
    if to ~= window.workspace then moveWindows({ { id = window.id, to = to } }) end
    shell.alert(window.app .. " goes on workspace " .. to .. ", as your aerospace.toml says", 2.5)
  end)
end

-- Whether entry, a workspace, opens window's app when it's empty, by name or bundle id.
function opensHere(entry, window)
  local open = entry.open and entry.open:lower()
  return open ~= nil and (open == window.app:lower() or open == (window.bundle or ""):lower())
end

-- Enter on the window card's row id.
local function chooseWindow(window, list, id)
  local entry, text = list.workspaces[window.workspace], shell.readText(workspaces.PATH)
  if id == "move" then return showMove(window) end
  shell.close()
  if id == "keep" and entry then
    keepOn(window, list, window.workspace)
    return shell.alert(window.app .. " opens on workspace " .. window.workspace .. " from now on", 2.5)
  end
  if id == "new" then return moveToNew(window, list) end
  if id == "open" and entry then
    local app = window.bundle or window.app
    return save(workspaces.setWorkspace(text, list, window.workspace, "open", not opensHere(entry, window) and app or nil))
  end
  if id == "forget" then
    save(workspaces.forgetApp(text, list, window.app, window.bundle))
    sendHome(window)
  end
end

local showWindow

-- The window card (Option+W): keep the focused app on its workspace, move it, open it when
-- the workspace is empty, or forget its place.
function feature.window()
  focusedWindow(showWindow)
end

-- The window card for window, the focused one.
function showWindow(window)
  if not window then return shell.alert("No window is focused", 2) end
  local list = editable()
  if not list then return end
  local entry = list.workspaces[window.workspace]
  local rows = cards.windowRows({ app = window.app, workspace = window.workspace,
    kept = workspaces.homeOf(list, window.app, window.bundle) == window.workspace, open = entry ~= nil and opensHere(entry, window),
    next = lowestFree(list), nextScreen = entry and workspaces.landsOn(list, window.workspace, feature.screens()) or "main" })
  shell.show("workspaces", listFrame(rows), card.html({ prompt = window.app .. " on workspace " .. window.workspace .. "…", rows = rows,
    compact = true }), function(message)
    if message.type ~= "choose" then return shell.close() end
    chooseWindow(window, list, message.id)
  end)
end

-- An installed app's bundle id from its name, as in ~/.config/omv/apps, or nil.
local function bundleIdOf(name)
  local running = hs.application.get(name)
  if running and running:bundleID() then return running:bundleID() end
  for _, folder in ipairs({ "/Applications/", shell.HOME .. "/Applications/", "/System/Applications/" }) do
    local info = hs.application.infoForBundlePath(folder .. name .. ".app")
    if info and info.CFBundleIdentifier then return info.CFBundleIdentifier end
  end
  return nil
end

-- The workspace the file keeps app on, by its name or bundle id, or "" for the one you're on.
function feature.homeOf(app)
  return workspaces.homeOf(readList(), app, bundleIdOf(app)) or ""
end

local settled = hs.timer.delayed.new(SETTLE_SECONDS, function()
  recordSeen()
  feature.check()
end)
local saved = hs.timer.delayed.new(SAVED_SECONDS, applySaved)

-- Kept on the feature, so they aren't garbage-collected.
feature.screenWatcher = hs.screen.watcher.new(function() settled:start() end):start()
-- The folder, not the file: an editor often saves by replacing the file, and it may not exist yet.
feature.file = hs.pathwatcher.new(shell.HOME .. "/.config/omv", function(paths)
  for _, path in ipairs(paths) do
    if path:match("/workspaces$") then return saved:start() end
  end
end):start()
settled:start()

return feature
