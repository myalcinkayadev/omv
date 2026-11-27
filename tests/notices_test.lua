-- Behavior of the targets kept for clicked notifications: found by title and text, replaced
-- by a newer one that reads the same, and dropped past the limit.
-- Run through notices_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local notices = require("notices")

check.that("should name the same notification the same when its title and text match",
  notices.key("omv · needs your approval", "omv") == notices.key("omv · needs your approval", "omv"))
check.that("should name notifications apart when their text differs",
  notices.key("Checks passed", "#12") ~= notices.key("Checks passed", "#13"))
check.that("should name a notification without text", notices.key("Checks passed", nil) == "Checks passed\n")

local book = notices.new()
notices.add(book, notices.key("Checks passed", "#12"), "https://github.com/o/r/pull/12")
check.that("should find the target of a notification when it's clicked",
  notices.find(book, notices.key("Checks passed", "#12")) == "https://github.com/o/r/pull/12")
check.that("should find nothing for a notification it never kept", notices.find(book, notices.key("Checks passed", "#99")) == nil)

notices.add(book, notices.key("Checks passed", "#12"), "https://github.com/o/r/pull/12#latest")
check.that("should open the newest target when two notifications read the same",
  notices.find(book, notices.key("Checks passed", "#12")) == "https://github.com/o/r/pull/12#latest")
check.that("should keep one entry when two notifications read the same", #book.order == 1)

local full = notices.new()
for number = 1, notices.LIMIT + 1 do notices.add(full, notices.key("Checks passed", "#" .. number), number) end
check.that("should drop the oldest target when one more than the limit arrives",
  notices.find(full, notices.key("Checks passed", "#1")) == nil)
check.that("should keep the newest target when one more than the limit arrives",
  notices.find(full, notices.key("Checks passed", "#" .. (notices.LIMIT + 1))) == notices.LIMIT + 1)
check.that("should keep no more than the limit", #full.order == notices.LIMIT)

local refreshed = notices.new(2)
notices.add(refreshed, "a", 1)
notices.add(refreshed, "b", 2)
notices.add(refreshed, "a", 3)
notices.add(refreshed, "c", 4)
check.that("should count a notification seen again as the newest when dropping", notices.find(refreshed, "a") == 3 and notices.find(refreshed, "b") == nil)

check.finish()
