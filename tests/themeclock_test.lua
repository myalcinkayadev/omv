-- Behavior of the theme by the clock. Run through themeclock_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local themeclock = require("themeclock")

local config = themeclock.parse("day = catppuccin-latte\nnight = vantablack\n")
check.that("should read the day theme", config and config.day == "catppuccin-latte")
check.that("should read the night theme", config and config.night == "vantablack")
check.that("should ignore spaces around the name and the theme", themeclock.parse("  day=a \n night =b").night == "b")
check.that("should ignore a comment line", themeclock.parse("# day = a\nnight = b") == nil)
check.that("should be off without a night theme", themeclock.parse("day = a") == nil)
check.that("should be off without a file", themeclock.parse(nil) == nil)
check.that("should refuse a theme name that could be a path", themeclock.parse("day = ../x\nnight = b") == nil)

-- UTC epoch seconds for a time, to compare the sun's times against.
local function leap(year)
  return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

local function utc(year, month, day, hour, minute)
  local days = 0
  for y = 1970, year - 1 do days = days + (leap(y) and 366 or 365) end
  local lengths = { 31, leap(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  for m = 1, month - 1 do days = days + lengths[m] end
  return ((days + day - 1) * 24 + hour) * 3600 + minute * 60
end

local function near(actual, expected)
  return actual ~= nil and math.abs(actual - expected) <= 5 * 60
end

local june = { year = 2026, month = 6, day = 21 }
-- Istanbul: sunrise 05:33 and sunset 20:39 local time (UTC+3).
local rise, set = themeclock.sun(june, 41.01, 28.98)
check.that("should find Istanbul's sunrise to within 5 minutes", near(rise, utc(2026, 6, 21, 2, 33)))
check.that("should find Istanbul's sunset to within 5 minutes", near(set, utc(2026, 6, 21, 17, 39)))
-- San Francisco: sunrise 05:48 and sunset 20:35 local time (UTC-7), which is the next day in UTC.
rise, set = themeclock.sun(june, 37.77, -122.42)
check.that("should find a sunrise west of Greenwich to within 5 minutes", near(rise, utc(2026, 6, 21, 12, 48)))
check.that("should put a sunset that falls on the next UTC day on the right day", near(set, utc(2026, 6, 22, 3, 35)))
-- Tromsø has the midnight sun in June, and polar night in December.
check.that("should find no times where the sun never sets", themeclock.sun(june, 69.65, 18.96) == nil)
check.that("should find no times where the sun never rises", themeclock.sun({ year = 2026, month = 12, day = 21 }, 69.65, 18.96) == nil)
-- Sydney in December: sunrise 05:42 and sunset 20:05 local time (UTC+11).
rise = themeclock.sun({ year = 2026, month = 12, day = 21 }, -33.87, 151.21)
check.that("should find a sunrise in the southern hemisphere to within 5 minutes", near(rise, utc(2026, 12, 20, 18, 42)))

local sunrise, sunset = 1000, 2000
check.that("should be day between sunrise and sunset", themeclock.period(1500, sunrise, sunset) == "day")
check.that("should be night before sunrise", themeclock.period(999, sunrise, sunset) == "night")
check.that("should be night from sunset on", themeclock.period(2000, sunrise, sunset) == "night")
check.that("should be day at sunrise", themeclock.period(1000, sunrise, sunset) == "day")
check.that("should be day at noon without the sun's times", themeclock.period(0, nil, nil, { hour = 12 }) == "day")
check.that("should be day from 7:00 without the sun's times", themeclock.period(0, nil, nil, { hour = 7 }) == "day")
check.that("should be night from 19:00 without the sun's times", themeclock.period(0, nil, nil, { hour = 19 }) == "night")
check.that("should be night at 6:00 without the sun's times", themeclock.period(0, nil, nil, { hour = 6 }) == "night")

check.finish()
