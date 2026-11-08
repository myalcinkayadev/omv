-- Behavior of the pull request card's rows. Run through prs_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local prs = require("prs")

local found = {
  { number = 42, title = "Fix login", url = "https://github.com/acme/api/pull/42", repository = { nameWithOwner = "acme/api" } },
  { number = 7, title = "Add docs", url = "https://github.com/acme/web/pull/7", repository = { nameWithOwner = "acme/web" } },
}
local rows = prs.rows(found)

check.that("should make one row per pull request", #rows == 2)
check.that("should show the title as the label", rows[1].label == "Fix login")
check.that("should show the repository and number as the hint", rows[1].hint == "acme/api#42")
check.that("should use the pull request's URL as the row id", rows[2].id == "https://github.com/acme/web/pull/7")
check.that("should return no rows when gh's answer could not be read", #prs.rows(nil) == 0)
check.that("should skip a pull request without a URL", #prs.rows({ { number = 1, title = "x" } }) == 0)

check.finish()
