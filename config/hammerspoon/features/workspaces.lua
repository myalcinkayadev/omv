-- Workspaces: puts each workspace from ~/.config/omv/workspaces on its screen for the screens
-- plugged in, or on the screen the display profile in use gives it, as displays come and go,
-- and moves windows off a workspace that was removed.
-- screen 2, screen 3 and screen 4 only mean a monitor once the screens are known, so the pins
-- are worked out here and written for the aerospace.toml build, which reloads AeroSpace.
-- The Workspaces card, in the system menu, adds and removes workspaces and sets their screens.

local shell = require("shell")
local card = require("card")
local workspaces = require("workspaces")

local feature = {}

-- The pins for the screens plugged in, read by install/aerospace_merge.lua.
local SCREENS = shell.STATE_DIR .. "/aerospace-screens.toml"
-- Displays often connect in steps; the pins are worked out once they've settled.
local SETTLE_SECONDS = 1.5
-- The card's changes are applied once the keys have stopped for this long.
local APPLY_SECONDS = 1.0
-- How long a removed workspace is offered back once the card closes.
local UNDO_SECONDS = 60
local FOOTER = { { key = "Left/Right", text = "screen" }, { key = "⌫", text = "remove" }, { key = "Esc", text = "close" } }
local FOOTER_HEIGHT = 24

local function list()
  return workspaces.parse(shell.readText(workspaces.PATH))
end

-- The display profile in use's workspaces, which can move some to other screens.
local PROFILE_STATE = shell.STATE_DIR .. "/display-profile.json"

local function profileWorkspaces()
  -- hs.json.read logs an error for a file that isn't there, so that's checked first.
  if not hs.fs.attributes(PROFILE_STATE) then return nil end
  local ok, saved = pcall(hs.json.read, PROFILE_STATE)
  return ok and type(saved) == "table" and type(saved.settings) == "table" and saved.settings.workspaces or nil
end

-- { name, builtin, main, x } for each screen. main is the screen macOS puts the menu bar on,
-- as AeroSpace's main; x orders them left to right, as AeroSpace numbers them.
local function screens()
  local primary = hs.screen.primaryScreen()
  local found = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    local name = screen:name() or ""
    found[#found + 1] = { name = name, builtin = name:find("Built%-in") ~= nil, main = screen == primary, x = screen:fullFrame().x }
  end
  return found
end

-- Moves each window on a workspace that isn't listed to the lowest one left, one after the
-- other, so the bar, redrawn after, no longer finds the old workspace; then calls done.
local function moveStrays(done)
  local output = hs.execute(shell.AEROSPACE .. " list-windows --all --format '%{window-id} %{workspace}'") or ""
  for _, move in ipairs(workspaces.strayWindows(output, list())) do
    hs.execute(shell.AEROSPACE .. " move-node-to-workspace --window-id " .. move.id .. " " .. move.to)
  end
  if done then done() end
end

-- Writes the pins for the screens plugged in, and rebuilds AeroSpace's config when they changed;
-- then moves windows off removed workspaces and calls done.
function feature.check(done)
  if type(done) ~= "function" then done = nil end
  local current = workspaces.overlay(list(), profileWorkspaces())
  local text = workspaces.assignmentToml(workspaces.resolve(current, screens()), current)
  if text == shell.readText(SCREENS) then return moveStrays(done) end
  os.execute("/bin/mkdir -p '" .. shell.STATE_DIR .. "'")
  local file = io.open(SCREENS, "w")
  if not file then return end
  file:write(text)
  file:close()
  require("features.aerospacebuild").request(function() moveStrays(done) end)
end

local pending = hs.timer.delayed.new(SETTLE_SECONDS, feature.check)

-- Rebuilds AeroSpace's keys and pins and the bar's items from the file, then the pins for
-- the screens plugged in, which moves windows off a removed workspace.
local apply = hs.timer.delayed.new(APPLY_SECONDS, function()
  require("devlayout").WORKSPACE = workspaces.devWorkspace(list())
  require("features.aerospacebuild").request(function()
    -- The bar is redrawn last, once no window is left on a removed workspace.
    feature.check(function() hs.task.new(shell.SKETCHYBAR, nil, { "--reload" }):start() end)
  end)
end)

local function save(changed)
  os.execute("/bin/mkdir -p '" .. shell.HOME .. "/.config/omv'")
  local file = io.open(workspaces.PATH, "w")
  if not file then return end
  file:write(workspaces.format(changed))
  file:close()
  apply:start()
end

-- The workspace removed last, offered back: { number, screen, at }.
local removed = nil

local function indexOf(rows, id)
  for index, row in ipairs(rows) do
    if row.id == id then return index end
  end
  return 1
end

-- The card: each workspace with its screen, Left/Right to change it, Backspace to remove one
-- (with Bring back), and Add for the next. selected is the row to select when it opens again.
function feature.open(selected)
  if type(selected) ~= "number" then selected = nil end
  local current = list()
  if #current.problems > 0 then return shell.alert("~/.config/omv/workspaces " .. current.problems[1], 5) end
  if removed and (os.time() - removed.at > UNDO_SECONDS or current.screens[removed.number]) then removed = nil end
  local rows = workspaces.rows(current, removed and removed.number)
  shell.show("workspaces", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows) + FOOTER_HEIGHT),
    card.html({ prompt = "Workspaces…", rows = rows, compact = true, step = true, clearable = true, footer = FOOTER,
      selected = selected }), function(message)
      local id = message.id or ""
      if message.type == "step" then
        local direction, workspace = id:match("^(%-?1):workspace:(%d)$")
        if not workspace then return end
        current.screens[workspace] = workspaces.stepScreen(current.screens[workspace], tonumber(direction), #hs.screen.allScreens())
        save(current)
        return feature.open(indexOf(rows, "workspace:" .. workspace))
      end
      if message.type == "clear" then
        local workspace = id:match("^workspace:(%d)$")
        if not workspace then return end
        local without = workspaces.remove(current, workspace)
        if not without then return shell.alert("Keep at least one workspace", 2) end
        removed = { number = workspace, screen = current.screens[workspace], at = os.time() }
        save(without)
        return feature.open(indexOf(rows, id))
      end
      if message.type == "choose" and id == "undo" and removed then
        current.screens[removed.number] = removed.screen
        local number = removed.number
        removed = nil
        save(current)
        return feature.open(indexOf(workspaces.rows(current), "workspace:" .. number))
      end
      if message.type == "choose" and id == "add" then
        local added = workspaces.add(current)
        if not added then return end
        save(added)
        return feature.open(#workspaces.rows(added) - (workspaces.add(added) and 1 or 0))
      end
      shell.close()
    end)
end

-- Kept on the feature, so they aren't garbage-collected.
feature.screens = hs.screen.watcher.new(function() pending:start() end):start()
pending:start()

return feature
