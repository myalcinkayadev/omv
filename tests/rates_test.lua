-- Behavior of the currency rates the palette's calculator converts with. Run through
-- rates_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local rates = require("rates")

local NOW = 1795680000
local HOUR = 3600
local answer = {
  { date = "2026-11-19", base = "EUR", quote = "USD", rate = 1.08 },
  { date = "2026-11-20", base = "EUR", quote = "TRY", rate = 45.2 },
}

local read = rates.read(answer, NOW)
check.that("should keep each quote's rate", read.quotes.USD.rate == 1.08)
check.that("should keep each quote's date", read.quotes.TRY.date == "2026-11-20")
check.that("should note the base the rates are against", read.base == "EUR")
check.that("should note when the rates were fetched", read.fetched == NOW)
check.that("should skip a quote without a number rate", rates.read({ { date = "2026-11-20", base = "EUR", quote = "BAD", rate = "x" }, answer[1] }, NOW).quotes.BAD == nil)
check.that("should give nothing for an empty answer", rates.read({}, NOW) == nil)
check.that("should give nothing for an answer that isn't a list", rates.read({ message = "not found" }, NOW) == nil)

check.that("should want rates when none are saved", rates.stale(nil, NOW))
check.that("should keep rates fetched under 4 hours ago", not rates.stale({ fetched = NOW - 4 * HOUR + 60 }, NOW))
check.that("should fetch again when the rates are 4 hours old", rates.stale({ fetched = NOW - 4 * HOUR }, NOW))

local saved = rates.read(answer, NOW - 5 * HOUR)
check.that("should keep the old rates when a fetch fails", rates.after(saved, nil, NOW) == saved)
check.that("should keep the old rates when a fetch answers nonsense", rates.after(saved, { message = "busy" }, NOW) == saved)
check.that("should take the new rates when a fetch succeeds", rates.after(saved, answer, NOW).fetched == NOW)

check.that("should save the rates in omv's state folder", rates.path("/Users/me") == "/Users/me/.local/state/omv/rates.json")
check.that("should ask for rates against the euro", rates.URL:find("base=EUR", 1, true) ~= nil)

check.finish()
