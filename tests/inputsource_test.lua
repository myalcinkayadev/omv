-- Behavior of the input source item: its short tag, which source a click goes to, and when
-- the bar shows it. Run through inputsource_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local inputsource = require("inputsource")

local TURKISH = "com.apple.keylayout.Turkish-QWERTY-PC"
local US = "com.apple.keylayout.US"
local ABC = "com.apple.keylayout.ABC"
local GERMAN = "com.apple.keylayout.German"
local KOTOERI = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"

check.that("should label a known source id with a short tag when it is Turkish QWERTY PC", inputsource.tag(TURKISH) == "TR")
check.that("should label a known source id with a short tag when it is US", inputsource.tag(US) == "US")
check.that("should label a known source id with a short tag when it is ABC", inputsource.tag(ABC) == "US")
check.that("should label a known source id with its country when its name starts otherwise", inputsource.tag(GERMAN) == "DE")
check.that("should fall back to the first two letters of the last id component when the id is unknown",
  inputsource.tag("com.apple.keylayout.Polish") == "PO")
check.that("should fall back to the last component of an input method's id when it is unknown", inputsource.tag(KOTOERI) == "JA")
check.that("should skip digits and dashes when the last id component starts with them",
  inputsource.tag("com.apple.keylayout.2-SetKorean") == "SE")
check.that("should give no tag when the id is nil", inputsource.tag(nil) == nil)
check.that("should give no tag when the id is empty", inputsource.tag("") == nil)
check.that("should give no tag when the id has no letters", inputsource.tag("com.apple.keylayout.123") == nil)

check.that("should pick the next source after the current one when there are several",
  inputsource.nextSource({ US, TURKISH, GERMAN }, TURKISH) == GERMAN)
check.that("should wrap to the first source after the last when the current one is last",
  inputsource.nextSource({ US, TURKISH, GERMAN }, GERMAN) == US)
check.that("should pick the first source when the current one is not in the list",
  inputsource.nextSource({ US, TURKISH }, KOTOERI) == US)
check.that("should pick the first source when there is no current one", inputsource.nextSource({ US, TURKISH }, nil) == US)
check.that("should pick no source when only one is enabled", inputsource.nextSource({ US }, US) == nil)
check.that("should pick no source when none is enabled", inputsource.nextSource({}, US) == nil)

local function drawn(properties) return table.concat(properties, " ") end

check.that("should show the current source's tag when several are enabled",
  drawn(inputsource.barProperties({ US, TURKISH }, TURKISH)) == "drawing=on label=TR")
check.that("should hide the item when only one source is enabled", drawn(inputsource.barProperties({ US }, US)) == "drawing=off")
check.that("should hide the item when no source is enabled", drawn(inputsource.barProperties({}, nil)) == "drawing=off")
check.that("should hide the item when the current source has no tag",
  drawn(inputsource.barProperties({ US, TURKISH }, nil)) == "drawing=off")

check.finish()
