-- Behavior of Send to agent's rows and the text it pastes. Run through sendto_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local sendto = require("sendto")

check.that("should keep plain text as it is", sendto.clean("fix the login bug") == "fix the login bug")
check.that("should keep newlines inside the text", sendto.clean("one\ntwo") == "one\ntwo")
check.that("should keep tabs", sendto.clean("a\tb") == "a\tb")
check.that("should turn Windows line ends into newlines", sendto.clean("one\r\ntwo") == "one\ntwo")
check.that("should drop trailing newlines so the paste never sends itself", sendto.clean("run it\n\n") == "run it")
check.that("should drop an escape that could end the bracketed paste", sendto.clean("a\27[201~b") == "a[201~b")
check.that("should drop other control characters", sendto.clean("a\0b\7c\127d") == "abcd")
check.that("should give nil for text of only spaces", sendto.clean(" \n\t ") == nil)
check.that("should give nil for an empty text", sendto.clean("") == nil)
check.that("should give nil for no text", sendto.clean(nil) == nil)

local sessions = {
  { id = "/dev/ttys001", label = "omv", state = "done" },
  { id = "/dev/ttys002", label = "api", state = "asks" },
  { id = "/dev/ttys003", label = "web", state = "working" },
  { id = "-", label = "zed", state = "done" },
}
local rows = sendto.rows(sessions, "hello", "Selection")

check.that("should offer only sessions that are done, each for text and a screenshot", #rows == 2)
check.that("should never offer a session that asks for approval", (function()
  for _, row in ipairs(rows) do if row.id:find("ttys002", 1, true) then return false end end
  return true
end)())
check.that("should never offer a session that is working", (function()
  for _, row in ipairs(rows) do if row.id:find("ttys003", 1, true) then return false end end
  return true
end)())
check.that("should never offer a session outside a terminal", (function()
  for _, row in ipairs(rows) do if row.label:find("zed", 1, true) then return false end end
  return true
end)())
check.that("should list the text row first", rows[1].id == "text:/dev/ttys001")
check.that("should name the source and the session in the label", rows[1].label == "Selection → omv")
check.that("should count the characters in the hint", rows[1].hint == "5 characters")
check.that("should say one character for a single one", sendto.rows(sessions, "x", "Clipboard")[1].hint == "1 character")
check.that("should count characters, not bytes", sendto.rows(sessions, "çay", "Clipboard")[1].hint == "3 characters")
check.that("should offer a screenshot row", rows[2].id == "shot:/dev/ttys001")
check.that("should offer only screenshots without text", #sendto.rows(sessions, nil, nil) == 1)
check.that("should offer nothing without a done session", #sendto.rows({ sessions[2] }, "x", "Selection") == 0)
check.that("should offer nothing without sessions", #sendto.rows(nil, "x", "Selection") == 0)

local kind, tty = sendto.parseId("text:/dev/ttys001")
check.that("should read a text row's kind", kind == "text")
check.that("should read a row's terminal", tty == "/dev/ttys001")
check.that("should read a screenshot row's kind", sendto.parseId("shot:/dev/ttys004") == "shot")
check.that("should refuse a row for a terminal that isn't a plain device", sendto.parseId("text:/dev/ttys1; rm -rf ~") == nil)
check.that("should refuse an unknown kind", sendto.parseId("run:/dev/ttys001") == nil)
check.that("should refuse no row", sendto.parseId(nil) == nil)

local path = sendto.shotPath(os.time({ year = 2026, month = 11, day = 21, hour = 9, min = 5, sec = 7 }))
check.that("should name a screenshot by its time", path:match("/omv%-shot%-20261121%-090507%.png$") ~= nil)
check.that("should keep spaces out of a screenshot's path's name", not path:match("[^/]* [^/]*%.png$"))
check.that("should remove a screenshot older than a day", sendto.isOldShot("omv-shot-20261120-090507.png", 0, sendto.SHOT_SECONDS + 1))
check.that("should keep a screenshot from today", not sendto.isOldShot("omv-shot-20261121-090507.png", 100, 200))
check.that("should never remove a file that isn't one of its screenshots", not sendto.isOldShot("notes.txt", 0, sendto.SHOT_SECONDS + 1))

check.finish()
