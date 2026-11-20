-- Behavior of pasting for you, after a snippet or a clipboard history item is picked. Run
-- through paste_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local paste = require("paste")

check.that("should paste when focus is back where you were typing", paste.way(true, 7, 7) == "paste")
check.that("should only copy when another window has focus", paste.way(true, 7, 9) == "copy")
check.that("should only copy when no window had focus before", paste.way(true, nil, nil) == "copy")
check.that("should only copy without Accessibility", paste.way(false, 7, 7) == "copy")
check.that("should not look for windows without Accessibility", not paste.canLook(false))
check.that("should look for windows with Accessibility", paste.canLook(true))

check.finish()
