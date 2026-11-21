-- Behavior of translating the selection (Option+Y): which language it goes to, what the
-- helper's answers mean, and the card that shows the translation. Run through
-- translate_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local translate = require("translate")
local card = require("card")

check.that("should read a Mac language's code from its locale", translate.language("tr-TR") == "tr")
check.that("should read a bare language code as it is", translate.language("en") == "en")
check.that("should read a script's language without the script", translate.language("zh-Hans") == "zh")
check.that("should take English when the Mac names no language", translate.language(nil) == "en")

check.that("should translate another language into the Mac's", translate.target("de", "tr") == "tr")
check.that("should translate English into the Mac's language", translate.target("en", "tr") == "tr")
check.that("should translate the Mac's language into English", translate.target("tr", "tr") == "en")
check.that("should read a detected script's language when picking", translate.target("zh-Hans", "zh") == "en")
check.that("should have nothing to translate into for English on an English Mac", translate.target("en", "en") == nil)

check.that("should read a detected language", translate.parseDetect("tr\n") == "tr")
check.that("should read no language when the helper can't tell", translate.parseDetect("unknown\n") == nil)
check.that("should read no language from no answer", translate.parseDetect("") == nil)

local done = translate.parseResult(0, "ok\tTurkish\tEnglish\nThanks, I'll take a look today.\n")
check.that("should read a translation's text", done.text == "Thanks, I'll take a look today.")
check.that("should read the languages a translation went between", done.from == "Turkish" and done.to == "English")
check.that("should keep a translation's line breaks", translate.parseResult(0, "ok\tA\tB\none\ntwo\n").text == "one\ntwo")
local missing = translate.parseResult(0, "missing\tTurkish\tEnglish\n")
check.that("should tell when a language isn't downloaded", missing.missing == true and missing.from == "Turkish")
check.that("should tell a failed helper apart", translate.parseResult(1, "").error ~= nil)
check.that("should tell an answer it can't read apart", translate.parseResult(0, "what\n").error ~= nil)

check.that("should have nothing to translate in an empty selection", translate.selection("") == nil)
check.that("should have nothing to translate in only spaces", translate.selection("  \n ") == nil)
check.that("should translate the selection without its outer spaces", translate.selection("  merhaba \n") == "merhaba")

local shown = card.html(translate.screen(done))
check.that("should show the translation on the card", check.contains(check.visible(shown), "Thanks, I'll take a look today."))
check.that("should name the languages on the card", check.contains(shown, "Turkish → English"))
check.that("should offer to replace the selection first", translate.screen(done).rows[1].id == "replace")
check.that("should offer to copy the translation", translate.screen(done).rows[2].id == "copy")
check.that("should escape the translation's markup", check.contains(card.html(translate.screen({ text = "<b>", from = "A", to = "B" })), "&lt;b&gt;"))

local download = translate.screen(missing)
check.that("should say which languages to download", check.contains(download.passage, "Turkish and English"))
check.that("should offer to open Translation Languages", download.rows[1].id == "settings")

check.that("should give one line of room to a short translation", translate.passageHeight("Hello") == translate.passageHeight("Hi"))
check.that("should give a long translation more room", translate.passageHeight(string.rep("word ", 60)) > translate.passageHeight("Hi"))
check.that("should give a line break its own line", translate.passageHeight("a\nb") > translate.passageHeight("ab"))
check.that("should cap the room a very long translation takes", translate.passageHeight(string.rep("word ", 2000)) == translate.passageHeight(string.rep("word ", 4000)))

check.finish()
