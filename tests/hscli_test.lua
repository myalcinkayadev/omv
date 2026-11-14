-- Where Hammerspoon installs the hs command. Run through hscli_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local hscli = require("hscli")

check.that("should install into /opt/homebrew when Homebrew lives there", hscli.prefix(true) == "/opt/homebrew")
check.that("should install into /usr/local when it doesn't", hscli.prefix(false) == "/usr/local")

check.finish()
