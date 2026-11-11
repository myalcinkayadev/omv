-- Themes (Option+Escape, then Theme): Vantablack, built in, or one of Omarchy's themes,
-- fetched on request by theme-sync.sh. Picking one recolors the cards at once, writes the
-- bar's and Ghostty's colours to ~/.local/state/omv/theme and reloads the bar, and
-- recolors the focused window's outline. Ghostty picks up its colours in new windows, or
-- with its own config reload (Cmd+Shift+,). The choice is kept across reloads.

local shell = require("shell")
local card = require("card")
local theme = require("theme")

local feature = {}

local THEMES = shell.HOME .. "/.local/share/omv/themes"
local STATE = shell.STATE_DIR .. "/theme"
local CURRENT = STATE .. "/current"
local SYNC = hs.configdir .. "/theme-sync.sh"
local WIDTH = 420
local VISIBLE_ROWS = 12

local function names()
  local found = {}
  local ok, files, folder = pcall(hs.fs.dir, THEMES)
  for name in (ok and files) and files or function() end, folder do
    if theme.plainName(name) and hs.fs.attributes(THEMES .. "/" .. name .. "/colors.toml") then found[#found + 1] = name end
  end
  table.sort(found)
  return found
end

local function current()
  local name = (shell.readText(CURRENT) or ""):match("^%s*([%w%-]+)")
  return name or "vantablack"
end

local function tokensFor(name)
  if name == "vantablack" then return theme.tokens(nil) end
  return theme.tokens(theme.parse(shell.readText(THEMES .. "/" .. name .. "/colors.toml")))
end

local function write(path, text)
  local file = io.open(path, "w")
  if not file then return false end
  file:write(text)
  file:close()
  return true
end

-- borders started by AeroSpace takes new colours when run again; it's never started here.
local function outline(tokens)
  if (hs.execute("/usr/bin/pgrep -x borders") or "") == "" then return end
  hs.task.new("/opt/homebrew/bin/borders", nil, theme.bordersArguments(tokens)):start()
end

local function apply(name)
  local tokens = tokensFor(name)
  os.execute("/bin/mkdir -p '" .. STATE .. "'")
  write(STATE .. "/colors.sh", theme.sketchybarColors(tokens))
  write(STATE .. "/ghostty", theme.ghosttyConfig(tokens))
  write(CURRENT, name .. "\n")
  shell.setTheme(tokens)
  outline(tokens)
  hs.task.new(shell.SKETCHYBAR, nil, { "--reload" }):start()
end

local function sync()
  shell.close()
  shell.alert("Getting Omarchy's themes…", 2)
  hs.task.new(SYNC, function(code, output)
    if code ~= 0 then return shell.alert("Couldn't reach GitHub", 1.5) end
    shell.alert("Got " .. (output:match("%d+") or "0") .. " themes", 1.5)
    feature.open()
  end):start()
end

function feature.open()
  local rows, selected = theme.rows(names(), current())
  local screen = { prompt = "Theme…", rows = rows, selected = selected }
  shell.show("theme", shell.centered(WIDTH, shell.menuHeight(screen)), card.html(screen), function(message)
    if message.type == "back" then return require("features.menu").toggle() end
    if message.type ~= "choose" then return shell.close() end
    if message.id == "sync" then return sync() end
    local name = message.id:match("^theme:([%w%-]+)$")
    if not name then return end
    apply(name)
    -- Reopened, so the card shows itself in the new colours.
    feature.open()
  end)
end

-- The cards and the outline take the chosen theme as soon as this config loads; the bar's
-- and Ghostty's files are already written.
local chosen = current()
if chosen ~= "vantablack" then
  local tokens = tokensFor(chosen)
  shell.setTheme(tokens)
  outline(tokens)
end

return feature
