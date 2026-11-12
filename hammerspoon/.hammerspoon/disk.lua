-- The Disk card: free space from df and Mole's status, and the sizes Mole's cleanup
-- previews found. Every row that frees space opens Mole's own interactive command, so you
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
function disk.parseStatus(status)
  if type(status) ~= "table" or type(status.disks) ~= "table" then return nil end
  for _, entry in ipairs(status.disks) do
    if entry.mount == "/" and entry.total and entry.used then
      return { free = entry.total - entry.used, total = entry.total, purgeable = entry.purgeable }
    end
  end
  return nil
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

local function previewHint(preview)
  if not preview then return nil end
  if preview.measuring then return "measuring…" end
  return preview.size
end

-- Each row's hint, by row id, from the same state disk.rows takes. false means no hint, so
-- an open card can clear one.
function disk.hints(state)
  local previews = state.previews or {}
  local space = state.space
  return {
    space = space and space.purgeable and (disk.size(space.purgeable) .. " purgeable") or false,
    clean = previewHint(previews.clean) or false,
    purge = previewHint(previews.purge) or false,
  }
end

local function spaceRow(space, hint)
  if not space then return { id = "space", icon = "󰋊", label = "Free space unknown" } end
  return { id = "space", icon = "󰋊", label = disk.size(space.free) .. " free of " .. disk.size(space.total), hint = hint or nil }
end

-- Card rows from { installed, space, previews = { clean, purge } }, where each preview is
-- { size } or { measuring = true }.
function disk.rows(state)
  local hints = disk.hints(state)
  local rows = { spaceRow(state.space, hints.space) }
  if not state.installed then
    rows[2] = { id = "install", icon = "󰏗", label = "Install Mole to clean up", hint = "brew install mole" }
    return rows
  end
  rows[#rows + 1] = { id = "clean", icon = "󰃢", label = "Clean caches and logs", hint = hints.clean or nil }
  rows[#rows + 1] = { id = "purge", icon = "󰆴", label = "Purge project build artifacts", hint = hints.purge or nil }
  rows[#rows + 1] = { id = "analyze", icon = "󰙅", label = "Explore disk usage" }
  rows[#rows + 1] = { id = "installer", icon = "󰏔", label = "Remove old installers" }
  return rows
end

-- The command a row runs in a new Ghostty window, or nil for a row that runs nothing.
function disk.command(id)
  return COMMANDS[id]
end

return disk
