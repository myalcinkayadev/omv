-- Behavior of the checks card's rows and the passed notices. Run through ci_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local ci = require("ci")

local saved = table.concat({
  "SUCCESS\thttps://github.com/acme/api/pull/1\tacme/api#1\tBump deps",
  "PENDING\thttps://github.com/acme/web/pull/7\tacme/web#7\tAdd docs",
  "FAILURE\thttps://github.com/acme/api/pull/42\tacme/api#42\tFix login",
  "NONE\thttps://github.com/acme/cli/pull/3\tacme/cli#3\tTypo",
}, "\n") .. "\n"
local rows = ci.rows(saved)

check.that("should make one row per pull request", #rows == 4)
check.that("should list a failing pull request first", rows[1].id == "https://github.com/acme/api/pull/42")
check.that("should list a running pull request after the failing ones", rows[2].id == "https://github.com/acme/web/pull/7")
check.that("should list a pull request without checks last", rows[4].id == "https://github.com/acme/cli/pull/3")
check.that("should show the title as the label", rows[1].label == "Fix login")
check.that("should show the repository, number and state as the hint", rows[1].hint == "acme/api#42 · failing")
check.that("should call an errored check failing",
  ci.rows("ERROR\thttps://github.com/a/b/pull/1\ta/b#1\tX\n")[1].hint == "a/b#1 · failing")
check.that("should keep the saved order within one state",
  ci.rows("SUCCESS\thttps://x.test/1\ta#1\tOne\nSUCCESS\thttps://x.test/2\ta#2\tTwo\n")[1].label == "One")
check.that("should fall back to the repository and number without a title",
  ci.rows("SUCCESS\thttps://x.test/1\ta/b#1\t\n")[1].label == "a/b#1")
check.that("should return no rows without a state file", #ci.rows(nil) == 0)
check.that("should skip a line that is not a pull request", #ci.rows("garbage line\n") == 0)
check.that("should skip a line whose URL is not https", #ci.rows("SUCCESS\tjavascript:alert(1)\ta#1\tX\n") == 0)

local notices = ci.notices("SUCCESS\thttps://github.com/acme/api/pull/42\tacme/api#42\tFix login\n")
check.that("should make one notice per passed pull request", #notices == 1)
check.that("should name the pull request in the notice's title", notices[1].title == "Checks passed: acme/api#42")
check.that("should show the pull request's title as the notice's text", notices[1].text == "Fix login")
check.that("should keep the URL for a click on the notice", notices[1].url == "https://github.com/acme/api/pull/42")
check.that("should make no notices without a passed file", #ci.notices(nil) == 0)

check.finish()
