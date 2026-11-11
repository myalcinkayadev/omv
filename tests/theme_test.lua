-- Behavior of themes: reading Omarchy's colors.toml, recoloring the cards, and the files
-- written for SketchyBar, Ghostty and borders. Run through theme_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local theme = require("theme")

local TOKYO = [[
mode = "dark"

accent = "#7aa2f7"
muted = "#414868"
background = "#1a1b26"
lighter_background = "#24283b"
foreground = "#a9b1d6"
bright_foreground = "#c0caf5"
red = "#f7768e"
]]

local tokyo = theme.tokens(theme.parse(TOKYO))
check.that("should read a theme's colours", tokyo.accent == "#7aa2f7" and tokyo.bg == "#1a1b26" and tokyo.fg == "#c0caf5")
check.that("should fall back to Vantablack for a missing colour", tokyo.palette[7] == theme.tokens(nil).palette[7])
check.that("should read a theme's terminal red", tokyo.palette[2] == "#f7768e")
check.that("should ignore lines it can't read", theme.parse("# comment\nnot a line\naccent = \"#123456\"\n").accent == "#123456")

local vanta = theme.tokens(nil)
local css = '<style>body { background: #000; color: #fff; border: 2px solid #8d8d8d; } .hint { color: #7a7a7a; } .line { background: #2a2a2a; } .logo { color: #d97757; }</style>'
check.that("should keep every colour as it is for Vantablack", theme.recolor(css, vanta) == css)
local recolored = theme.recolor(css, tokyo)
check.that("should use the theme's background for black", recolored:find("background: #1a1b26", 1, true) ~= nil)
check.that("should use the theme's foreground for white", recolored:find("color: #c0caf5", 1, true) ~= nil)
check.that("should use the theme's accent for the cards' border gray", recolored:find("solid #7aa2f7", 1, true) ~= nil)
check.that("should use the theme's muted colour for the hint gray", recolored:find(".hint { color: #414868", 1, true) ~= nil)
check.that("should mix a gray between the theme's background and foreground", theme.mix("#000000", "#ffffff", 42 / 255) == "#2a2a2a")
check.that("should leave a colour that isn't gray alone", recolored:find("#d97757", 1, true) ~= nil)
check.that("should recolor only inside style blocks", theme.recolor("<div>PR #111</div>", tokyo) == "<div>PR #111</div>")

local bar = theme.sketchybarColors(tokyo)
check.that("should write SketchyBar's white as the theme's foreground", bar:find("WHITE=0xffc0caf5", 1, true) ~= nil)
check.that("should write SketchyBar's black as the theme's background", bar:find("BLACK=0xff1a1b26", 1, true) ~= nil)
check.that("should write SketchyBar's muted colour", bar:find("MUTED=0xff414868", 1, true) ~= nil)

local ghostty = theme.ghosttyConfig(tokyo)
check.that("should write Ghostty's background", ghostty:find("background = #1a1b26", 1, true) ~= nil)
check.that("should write Ghostty's 16 colours", select(2, ghostty:gsub("palette = ", "")) == 16)
check.that("should write Ghostty's red", ghostty:find("palette = 1=#f7768e", 1, true) ~= nil)

check.that("should outline the focused window in the theme's accent", theme.bordersArguments(tokyo)[1] == "active_color=0xff7aa2f7")

local rows, selected = theme.rows({ "tokyo-night", "gruvbox" }, "gruvbox")
check.that("should list Vantablack first, then the synced themes", rows[1].id == "theme:vantablack" and #rows == 4)
check.that("should select the current theme", rows[selected].id == "theme:gruvbox")
check.that("should name a theme for people", rows[2].label == "Tokyo Night")
check.that("should offer to get Omarchy's themes last", rows[4].id == "sync")
local _, none = theme.rows({}, nil)
check.that("should keep Vantablack when no theme was ever chosen", none == 1)
check.that("should take only a plain theme name", theme.plainName("tokyo-night") and not theme.plainName("../etc"))

check.finish()
