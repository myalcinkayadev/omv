-- Behavior of the browser's tabs in the palette. Run through tabs_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local tabs = require("tabs")

local F, R = tabs.FIELD_END, tabs.RECORD_END
local function record(window, index, title, url)
  return window .. F .. index .. F .. title .. F .. url .. R
end

local output = record(17, 1, "Docs", "https://docs.example.com/a")
  .. record(17, 2, "Inbox (3)", "https://mail.example.com/")
  .. record(42, 1, "Board", "https://board.example.com/x") .. "\n"
local parsed = tabs.parse(output)
local first = parsed[1]
check.that("should parse the osascript output into one row per tab (window id, tab index, title, URL)",
  #parsed == 3 and first.window == 17 and first.index == 1 and first.title == "Docs" and first.url == "https://docs.example.com/a")
check.that("should keep the browser's order of windows and tabs",
  parsed[2].window == 17 and parsed[2].index == 2 and parsed[3].window == 42 and parsed[3].index == 1)

local rows = tabs.rows(output)
check.that("should focus a tab by its window id and index", rows[2].id == "tab:17:2")
check.that("should show a tab's title as its label", rows[2].label == "Inbox (3)")
check.that("should show a tab's host as its hint", rows[1].hint == "docs.example.com")
check.that("should group tabs under Tabs", rows[1].group == "Tabs")

check.that("should give no rows when the browser is closed", #tabs.rows("\n") == 0)
check.that("should give no rows when the output is empty", #tabs.rows("") == 0)
check.that("should give no rows when there's no output", #tabs.rows(nil) == 0)
check.that("should skip a record it cannot read", #tabs.rows("garbage" .. R .. record(1, 1, "A", "https://a.com")) == 1)

local odd = tabs.rows(record(1, 1, 'Say "hi"\tto\nall | of you', "https://a.com"))
check.that("should keep quotes, tabs, newlines and bars in a title on one line",
  odd[1].label == 'Say "hi" to all | of you')
check.that("should keep a title that holds the field separator",
  tabs.parse(record(1, 1, "a" .. F .. "b", "https://a.com"))[1].title == "a" .. F .. "b")
check.that("should drop only the tab whose title holds the record separator",
  #tabs.parse(record(1, 1, "a" .. R .. "b", "https://a.com") .. record(1, 2, "ok", "https://b.com")) == 1)
check.that("should show a tab without a title by its URL",
  tabs.rows(record(1, 1, "", "https://a.com/x"))[1].label == "https://a.com/x")
check.that("should show a tab with a blank title by its URL",
  tabs.rows(record(1, 1, "  \n", "https://a.com/x"))[1].label == "https://a.com/x")

check.that("should leave out the user and port from a host", tabs.host("https://me@a.example.com:8080/x?y") == "a.example.com")
check.that("should show a URL without a host whole", tabs.host("about:blank") == "about:blank")

local read = tabs.readScript("Helium")
check.that("should read every tab's title from a Chromium browser", check.contains(read, "set titles to title of every tab of every window"))
check.that("should read every tab's name from Safari",
  check.contains(tabs.readScript("Safari"), "set titles to name of every tab of every window"))
check.that("should read nothing when the browser isn't running",
  check.contains(read, 'if application "Helium" is not running then return ""'))
check.that("should refuse a browser name that holds quotes", tabs.readScript('Hel"ium') == nil)
check.that("should refuse a browser name that holds a backslash", tabs.readScript("Hel\\ium") == nil)
check.that("should refuse an empty browser name", tabs.readScript("") == nil)

local chromium = tabs.focusScript("Google Chrome", 17, 2)
check.that("should build the focus script for a Chromium browser", chromium == table.concat({
  'if application "Google Chrome" is not running then return',
  'tell application "Google Chrome"',
  "  set shown to window id 17",
  "  set active tab index of shown to 2",
  "  set index of shown to 1",
  "  activate",
  "end tell",
}, "\n"))
check.that("should build the focus script for Safari", tabs.focusScript("Safari", 17, 2) == table.concat({
  'if application "Safari" is not running then return',
  'tell application "Safari"',
  "  set shown to window id 17",
  "  set current tab of shown to tab 2 of shown",
  "  set index of shown to 1",
  "  activate",
  "end tell",
}, "\n"))
check.that("should refuse to focus in a browser whose name holds quotes", tabs.focusScript('a"b', 1, 1) == nil)
check.that("should refuse to focus a window id that isn't a number", tabs.focusScript("Helium", "1 to 2", 1) == nil)

check.finish()
