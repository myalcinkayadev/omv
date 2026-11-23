-- Behavior of the card's page: the count line, status, key footer, icon tones and clearing.
-- Run through card_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local card = require("card")

local screen = {
  prompt = "Back after 25 min",
  sub = { counts = "2 done · 1 ended", status = "1 needs you", tone = "ask" },
  footer = { { key = "Enter", text = "go to it" }, { key = "⌫", text = "clear row" } },
  clearable = true,
  rows = { { id = "a", icon = "●", tone = "ask", label = "api", hint = "approve" } },
}
local html = card.html(screen)

check.that("should draw the count line under the title", check.contains(html, '<div class=sub>2 done · 1 ended</div>'))
check.that("should draw the status in its tone", check.contains(html, '<span class="status ask">1 needs you</span>'))
check.that("should draw each footer key in a badge", check.contains(html, "<kbd>Enter</kbd>go to it"))
check.that("should drop the body's bottom padding on a card with a footer", check.contains(html, " footed\""))
check.that("should let Hammerspoon read the height the page needs", check.contains(html, "window.omvContentHeight"))
check.that("should draw every footer key", check.contains(html, "<kbd>⌫</kbd>clear row"))
check.that("should give a row its tone", check.contains(html, 'class="row tone-ask"'))
check.that("should ask for Backspace to clear on a card that clears", check.contains(html, " data-clear"))
check.that("should send clear with the selected row on Backspace", check.contains(html, 'send("clear", shown[selected]'))

local plain = card.html({ prompt = "System…", rows = { { id = "x", label = "Lock" } } })
check.that("should not ask for clearing on other cards", not check.contains(plain, " data-clear"))
check.that("should leave other cards without a count line", not check.contains(plain, "<div class=sub>"))
check.that("should leave other cards without a footer", not check.contains(plain, "<div class=foot>"))
check.that("should keep a plain row's class", check.contains(plain, 'class="row"'))

local hostile = card.html({ prompt = "x", sub = { counts = "<b>", status = "<i>", tone = "ok" },
  footer = { { key = "<k>", text = "<t>" } }, rows = {} })
check.that("should escape the count line", check.contains(hostile, "<div class=sub>&lt;b&gt;</div>"))
check.that("should escape the status", check.contains(hostile, "&lt;i&gt;</span>"))
check.that("should escape the footer", check.contains(hostile, "<kbd>&lt;k&gt;</kbd>&lt;t&gt;"))
check.that("should refuse a tone that isn't one of the card's",
  not check.contains(card.html({ prompt = "x", rows = { { id = "y", label = "y", tone = 'x" onclick="z' } } }), "onclick"))

-- Step mode, for the display profile editor.
check.that("should mark a card in step mode, so Left and Right step its row",
  check.contains(card.html({ prompt = "Edit dell…", rows = { { id = "layout", label = "Layout" } }, step = true }), " data-step"))
check.that("should leave a card without step mode unmarked, so Right still picks",
  not check.contains(card.html({ prompt = "Pick…", rows = { { id = "a", label = "A" } } }), " data-step"))

check.that("should start the input with the given text when query is set",
  check.contains(card.html({ prompt = "A name…", rows = {}, input = true, query = 'Code "x"' }), 'data-query="Code &quot;x&quot;"'))
check.finish()
