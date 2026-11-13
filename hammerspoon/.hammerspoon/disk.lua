-- The Disk card: free space from df and Mole's status, and the sizes Mole's cleanup
-- previews found, in panel.lua's layout. Every row that frees space opens Mole's own interactive command, so you
-- choose what goes; nothing is ever deleted from the card itself.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local disk = {}

local MO = "/opt/homebrew/bin/mo"
local BREW = "/opt/homebrew/bin/brew"
-- A preview takes up to two minutes, so one from the last 6 hours is shown as it is.
local STALE_SECONDS = 6 * 3600
local GB, MB = 1000 * 1000 * 1000, 1000 * 1000

local COMMANDS = {
  clean = MO .. " clean",
  purge = MO .. " purge",
  analyze = MO .. " analyze",
  installer = MO .. " installer",
  install = BREW .. " install mole",
}

-- Free and total bytes of / from `df -k /`, or nil.
function disk.parseDf(output)
  local total, available = tostring(output or ""):match("\n%S+%s+(%d+)%s+%d+%s+(%d+)")
  if not total then return nil end
  return { free = tonumber(available) * 1024, total = tonumber(total) * 1024 }
end

-- Free, total and purgeable bytes of the startup disk from `mo status --json`, decoded, or nil.
-- Mole's used leaves purgeable space out, as Finder's free space does, so it's taken off
-- here: free is what can be written now, as df and the bar's item count it.
function disk.parseStatus(status)
  if type(status) ~= "table" or type(status.disks) ~= "table" then return nil end
  for _, entry in ipairs(status.disks) do
    if entry.mount == "/" and entry.total and entry.used then
      return { free = entry.total - entry.used - (entry.purgeable or 0), total = entry.total, purgeable = entry.purgeable }
    end
  end
  return nil
end

-- df's reading with the purgeable space Mole last reported, so the card keeps that line
-- while Mole's new answer is on its way rather than growing a second after it opens.
function disk.withPurgeable(dfSpace, previous)
  if not dfSpace then return nil end
  return { free = dfSpace.free, total = dfSpace.total, purgeable = previous and previous.purgeable }
end

-- Sizes in decimal units, as Finder and Mole show them.
function disk.size(bytes)
  if bytes >= 10 * GB then return string.format("%d GB", math.floor(bytes / GB + 0.5)) end
  if bytes >= GB then return string.format("%.1f GB", bytes / GB) end
  return string.format("%d MB", math.floor(bytes / MB + 0.5))
end

-- The space a `mo clean --dry-run` or `mo purge --dry-run` would free, as "12.70 GB", or nil
-- when the run printed no summary, as when it failed or was cut short.
function disk.previewSize(output)
  local text = tostring(output or ""):gsub("\27%[[%d;]*m", "")
  local amount, unit = text:match("Potential space:%s*([%d.]+)%s*([KMGT]B)")
  if not amount then amount, unit = text:match("Would free approximately:%s*([%d.]+)%s*([KMGT]B)") end
  if not amount then return nil end
  return amount .. " " .. unit
end

-- A saved preview is one line: the time it was measured, then its size.
function disk.cacheLine(at, size)
  return string.format("%d %s\n", at, size)
end

function disk.readCache(text)
  local at, size = tostring(text or ""):match("^(%d+) ([^\n]+)")
  if not at then return nil end
  return { at = tonumber(at), size = size }
end

function disk.isStale(saved, now)
  return saved == nil or now - saved.at > STALE_SECONDS
end

local HOUR, DAY = 3600, 24 * 3600

-- How long ago a preview was measured: nil under an hour, since the size is still fresh.
local function age(at, now)
  if not at or now - at < HOUR then return nil end
  if now - at < DAY then return math.floor((now - at) / HOUR) .. "h ago" end
  return math.floor((now - at) / DAY) .. "d ago"
end

local DASH = "—"
-- The card's height: its head, bar, grid and section title, then one line per choice.
local FRAME_HEIGHT, LINE_HEIGHT = 240, 40

-- A cleanup's size and age, from its preview: measuring… while one runs.
local function sized(item, preview, now)
  if preview and preview.measuring then
    item.size = "measuring…"
  elseif preview then
    item.size, item.age = preview.size, age(preview.at, now)
  end
  return item
end

local function cleanups(previews, now)
  return {
    sized({ id = "clean", icon = "󰃢", label = "Caches and logs" }, previews.clean, now),
    sized({ id = "purge", icon = "󰆴", label = "Build artifacts" }, previews.purge, now),
    { id = "installer", icon = "󰏔", label = "Old installers" },
    { id = "analyze", icon = "󰙅", label = "Explore disk usage" },
  }
end

-- Used, then purgeable, as shares of the total. Purgeable is macOS's to free, so it's
-- neither free nor part of what the cleanups would free.
local function segments(space)
  if not space then return {} end
  local purgeable = space.purgeable or 0
  local used = space.total - space.free - purgeable
  local shares = { { share = used / space.total * 100, kind = "used" } }
  if space.purgeable then shares[2] = { share = purgeable / space.total * 100, kind = "purgeable" } end
  return shares
end

local function grid(space)
  if not space then return { { "Used", DASH }, { "Purgeable", DASH, "purgeable" }, { "Total", DASH } } end
  return {
    { "Used", disk.size(space.total - space.free - (space.purgeable or 0)) },
    { "Purgeable", space.purgeable and disk.size(space.purgeable) or DASH, "purgeable" },
    { "Total", disk.size(space.total) },
  }
end

-- The card, in panel.lua's layout, from { installed, space, previews = { clean, purge } }:
-- each preview is { size, at } or { measuring = true }, and now dates their ages.
function disk.model(state, now)
  local space = state.space
  local buttons = state.installed and cleanups(state.previews or {}, now)
    or { { id = "install", icon = "󰏗", label = "Install Mole to clean up", size = "brew install mole" } }
  return {
    icon = "󰋊", title = "Disk", sub = "STARTUP DISK",
    big = space and (disk.size(space.free) .. " free") or DASH,
    segments = segments(space), grid = grid(space),
    section = "CLEAN UP", list = true, buttons = buttons,
  }
end

function disk.height(model)
  return FRAME_HEIGHT + #model.buttons * LINE_HEIGHT
end

-- The preview a row's command makes out of date, so it's measured again next time: only
-- the cleanups change what Mole would free.
local INVALIDATES = { clean = "clean", purge = "purge" }

function disk.invalidates(id)
  return INVALIDATES[id]
end

-- The command a row runs in a new Ghostty window, or nil for a row that runs nothing.
function disk.command(id)
  return COMMANDS[id]
end

return disk
