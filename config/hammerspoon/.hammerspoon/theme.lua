-- Themes: Omarchy's colors.toml read into the few colours omv uses, and what each part
-- needs from them. The cards keep their grays, each recolored to sit as far between the
-- theme's background and foreground as it sat between black and white, so Vantablack, the
-- default, looks exactly as before. features/theme.lua writes the files and applies them.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local theme = {}

-- Omarchy's Vantablack, built in, so omv looks the same with no theme ever chosen.
local VANTABLACK = {
  accent = "#8d8d8d", muted = "#7a7a7a", background = "#000000", lighter_background = "#1a1a1a",
  foreground = "#ffffff", bright_foreground = "#ffffff",
  red = "#a4a4a4", yellow = "#cecece", green = "#b6b6b6", cyan = "#b0b0b0", blue = "#8d8d8d", magenta = "#9b9b9b",
  bright_red = "#a4a4a4", bright_yellow = "#cecece", bright_green = "#b6b6b6", bright_cyan = "#b0b0b0",
  bright_blue = "#8d8d8d", bright_magenta = "#9b9b9b",
}

-- The terminal's 16 colours, from 0 (black) to 15 (bright white).
local PALETTE = {
  "lighter_background", "red", "green", "yellow", "blue", "magenta", "cyan", "foreground",
  "muted", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_foreground",
}

-- The cards' border gray and hint gray, which take the theme's accent and muted colours.
local BORDER, HINT = "8d8d8d", "7a7a7a"

-- colors.toml's `key = "#rrggbb"` lines; anything else is skipped.
function theme.parse(text)
  local colors = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local key, value = line:match('^%s*([%w_]+)%s*=%s*"([^"]*)"')
    if key then colors[key] = value end
  end
  return colors
end

-- The colours omv uses, each from the theme, else from Vantablack.
function theme.tokens(colors)
  local function color(key)
    local value = colors and colors[key]
    return (type(value) == "string" and value:match("^#%x%x%x%x%x%x$")) and value:lower() or nil
  end
  local function pick(key, fallback)
    return color(key) or fallback or VANTABLACK[key]
  end
  local palette = {}
  for index, key in ipairs(PALETTE) do palette[index] = pick("color" .. (index - 1), pick(key)) end
  return {
    bg = pick("background"),
    fg = pick("bright_foreground", pick("foreground")),
    accent = pick("accent"),
    muted = pick("muted", color("color8")),
    palette = palette,
  }
end

local function channels(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

-- The colour t of the way from a to b, where 0 is a and 1 is b.
function theme.mix(a, b, t)
  local ar, ag, ab = channels(a)
  local br, bg, bb = channels(b)
  local function at(x, y) return math.floor(x + (y - x) * t + 0.5) end
  return string.format("#%02x%02x%02x", at(ar, br), at(ag, bg), at(ab, bb))
end

local function recolored(hex, tokens)
  hex = hex:lower()
  if hex == BORDER then return tokens.accent:sub(2) end
  if hex == HINT then return tokens.muted:sub(2) end
  local r, g, b = hex:sub(1, 2), hex:sub(3, 4), hex:sub(5, 6)
  if r ~= g or g ~= b then return hex end
  return theme.mix(tokens.bg, tokens.fg, tonumber(r, 16) / 255):sub(2)
end

local function recolorCss(css, tokens)
  css = css:gsub("#(%x%x%x%x%x%x)", function(hex)
    local new = recolored(hex, tokens)
    return new == hex:lower() and ("#" .. hex) or ("#" .. new)
  end)
  return (css:gsub("#(%x%x%x)%f[^%x]", function(short)
    local hex = short:gsub("%x", "%0%0")
    local new = recolored(hex, tokens)
    return new == hex:lower() and ("#" .. short) or ("#" .. new)
  end))
end

-- A card's page in the theme's colours. Only its <style> blocks change, so text such as
-- "PR #111" never does.
function theme.recolor(html, tokens)
  return (html:gsub("(<style>)(.-)(</style>)", function(open, css, close)
    return open .. recolorCss(css, tokens) .. close
  end))
end

local function sketchybar(hex)
  return "0xff" .. hex:sub(2)
end

-- Sourced by the bar's config and plugins, which fall back to Vantablack without it.
function theme.sketchybarColors(tokens)
  return table.concat({
    "WHITE=" .. sketchybar(tokens.fg),
    "MUTED=" .. sketchybar(tokens.muted),
    "BLACK=" .. sketchybar(tokens.bg),
    "GRAY=" .. sketchybar(theme.mix(tokens.bg, tokens.fg, 0x3a / 255)),
    "",
  }, "\n")
end

-- Read by Ghostty's config through config-file, after its own theme line.
function theme.ghosttyConfig(tokens)
  local lines = {
    "background = " .. tokens.bg,
    "foreground = " .. tokens.fg,
    "cursor-color = " .. tokens.fg,
    "selection-background = " .. theme.mix(tokens.bg, tokens.fg, 0x2a / 255),
    "selection-foreground = " .. tokens.fg,
  }
  for index, color in ipairs(tokens.palette) do lines[#lines + 1] = "palette = " .. (index - 1) .. "=" .. color end
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

-- borders' arguments for the focused window's outline.
function theme.bordersArguments(tokens)
  return { "active_color=" .. sketchybar(tokens.accent) }
end

function theme.plainName(name)
  return type(name) == "string" and name:match("^[%w%-]+$") ~= nil
end

local function title(name)
  return (name:gsub("%-", " "):gsub("(%a)([%w]*)", function(first, rest) return first:upper() .. rest end))
end

-- The picker's rows: Vantablack, the themes synced from Omarchy, then a row to get them.
-- Also gives the current theme's row, to select.
function theme.rows(names, current)
  current = current or "vantablack"
  local rows = { { id = "theme:vantablack", icon = "󰏘", label = "Vantablack", hint = "built in" } }
  for _, name in ipairs(names) do
    if name ~= "vantablack" then rows[#rows + 1] = { id = "theme:" .. name, icon = "󰏘", label = title(name) } end
  end
  rows[#rows + 1] = { id = "sync", icon = "󰇚", label = "Get Omarchy's themes", hint = "from GitHub" }
  local selected = 1
  for index, row in ipairs(rows) do
    if row.id == "theme:" .. current then
      selected = index
      row.hint = "current"
    end
  end
  return rows, selected
end

return theme
