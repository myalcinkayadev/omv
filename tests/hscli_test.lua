-- Where Hammerspoon installs the hs command. Run through hscli_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local hscli = require("hscli")

check.that("should install into /opt/homebrew when Homebrew lives there", hscli.prefix(true) == "/opt/homebrew")
check.that("should install into /usr/local when it doesn't", hscli.prefix(false) == "/usr/local")
check.that("should install when hs is missing", hscli.needsInstall(false, false) == true)
check.that("should reinstall when the link leads nowhere", hscli.needsInstall("broken", false) == true)
check.that("should leave a link whose only flaw is the man page", hscli.needsInstall("broken", true) == false)
check.that("should leave a working install alone", hscli.needsInstall(true, true) == false)

check.finish()
