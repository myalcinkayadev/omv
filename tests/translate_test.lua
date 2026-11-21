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

check.that("should translate another language into the Mac's first", translate.target("de", { "en", "tr" }) == "en")
check.that("should translate the Mac's first language into its second", translate.target("en", { "en", "tr" }) == "tr")
check.that("should translate the Mac's second language into its first", translate.target("tr", { "en", "tr" }) == "en")
check.that("should translate the only Mac language into English", translate.target("tr", { "tr" }) == "en")
check.that("should read a detected script's language when picking", translate.target("zh-Hans", { "zh" }) == "en")
check.that("should have nothing to translate into for English on an English-only Mac", translate.target("en", { "en" }) == nil)
check.that("should translate into English when the Mac names no language", translate.target("tr", {}) == "en")
check.that("should translate into the language you chose", translate.target("tr", { "en", "tr" }, "de") == "de")
check.that("should pick by the Mac's languages when the text is in the one you chose", translate.target("de", { "en", "tr" }, "de") == "en")
check.that("should pick by the Mac's languages when you chose none", translate.target("tr", { "en", "tr" }, nil) == "en")
check.that("should read the language you chose", translate.parseChoice("de\n") == "de")
check.that("should read no choice from an empty file", translate.parseChoice("") == nil and translate.parseChoice(nil) == nil)
check.that("should read no choice from junk", translate.parseChoice("not a language!\n") == nil)
check.that("should read the Mac's languages from their locales", table.concat(translate.languages({ "en-TR", "tr-TR" }), " ") == "en tr")

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

-- The result card: what was asked is the selection, what it became, and which service.
local result = { text = "Thanks, I'll take a look today.", from = "Turkish", to = "English", service = "apple", original = "Bugün bakacağım." }
local resultCard = translate.screen(result)
local shown = card.html(resultCard)
local function rowIds(screen)
  local list = {}
  for index, row in ipairs(screen.rows) do list[index] = row.id end
  return table.concat(list, " ")
end
check.that("should show the translation on the card", check.contains(check.visible(shown), "Thanks, I'll take a look today."))
check.that("should show the selection above the translation", resultCard.quote == "Bugün bakacağım.")
check.that("should name the languages on the card", check.contains(shown, "Turkish → English"))
check.that("should name the service on the card", check.contains(resultCard.prompt, "Apple"))
check.that("should say when a service is online", check.contains(translate.screen({ text = "a", from = "A", to = "B", service = "deepl" }).prompt, "online"))
check.that("should not say Apple is online", not check.contains(resultCard.prompt, "online"))
check.that("should offer replacing, copying, translating back, a language and a service", rowIds(resultCard) == "replace copy back other service")
check.that("should name the language to translate back into", resultCard.rows[3].label == "Translate back to Turkish")
check.that("should give copying a key", resultCard.rows[2].key == "c")
check.that("should give another language a key", resultCard.rows[4].key == "l")
check.that("should give another service a key", resultCard.rows[5].key == "k")
check.that("should draw a row's key on the card", check.contains(shown, 'data-key="c"'))
check.that("should draw the selection on the card", check.contains(check.visible(shown), "Bugün bakacağım."))
check.that("should escape the translation's markup", check.contains(card.html(translate.screen({ text = "<b>", from = "A", to = "B", service = "apple" })), "&lt;b&gt;"))

check.that("should read language names", table.concat(translate.parseNames("Turkish\nEnglish\n"), ",") == "Turkish,English")
check.that("should read no names from no answer", #translate.parseNames("") == 0)

local listed = translate.parseLanguages("de\tGerman\tsupported\nfr\tFrench\tinstalled\ntr\tTurkish\tinstalled\nen\tEnglish\tinstalled\nbroken line\n", "tr")
local codes = {}
for index, language in ipairs(listed) do codes[index] = language.code end
check.that("should list downloaded languages first, by name", table.concat(codes, " ") == "en fr de")
check.that("should leave the text's own language out", not table.concat(codes, " "):find("tr"))
check.that("should tell a downloaded language", listed[1].installed == true and listed[3].installed == false)
local regional = translate.parseLanguages("en\tEnglish\tinstalled\nen-GB\tEnglish (UK)\tsupported\nar-AE\tArabic (UAE)\tsupported\nzh\tChinese\tsupported\nzh-TW\tChinese (Taiwan)\tsupported\n", "tr")
local regionalCodes = {}
for index, language in ipairs(regional) do regionalCodes[index] = language.code end
check.that("should leave out a region of a language listed whole", not table.concat(regionalCodes, " "):find("en%-GB"))
check.that("should keep a region whose language isn't listed whole", table.concat(regionalCodes, " "):find("ar%-AE") ~= nil)
check.that("should keep Chinese in each script", table.concat(regionalCodes, " "):find("zh%-TW") ~= nil)
check.that("should list no languages from no answer", #translate.parseLanguages("", "tr") == 0)
local picker = translate.languagesScreen(listed)
check.that("should offer to go back to automatic first", picker.rows[1].id == "lang:auto")
check.that("should name each language in the list", picker.rows[2].id == "lang:en" and picker.rows[2].label == "English")
check.that("should mark a language that needs downloading", picker.rows[4].hint == "download")
check.that("should mark no downloaded language", picker.rows[2].hint == nil)
check.that("should group the languages on the Mac", picker.rows[2].group == "On this Mac")
check.that("should group the languages to download", picker.rows[4].group == "Download first")
local online = translate.languagesScreen(listed, true)
check.that("should mark no download for an online service", online.rows[4].hint == nil)
check.that("should not group languages for an online service", online.rows[4].group == nil)
check.that("should read the language picked", translate.picked("lang:fr") == "fr")
check.that("should read automatic as no language", translate.picked("lang:auto") == false)
check.that("should read another row as nothing picked", translate.picked("copy") == nil)

missing.service = "apple"
local download = translate.screen(missing)
check.that("should say a language isn't on the Mac yet", check.contains(download.passage, "Turkish isn't on this Mac yet"))
check.that("should offer to download or another service", rowIds(download) == "download service")
check.that("should name the languages it downloads", download.rows[1].label == "Download Turkish and English")
check.that("should read a download that finished", translate.downloaded(0, "ready\n") == true)
check.that("should read a download you closed", translate.downloaded(1, "") == false)
check.that("should read an answer it can't read as no download", translate.downloaded(0, "what\n") == false)

check.that("should give one line of room to a short translation", translate.passageHeight("Hello") == translate.passageHeight("Hi"))
check.that("should give a long translation more room", translate.passageHeight(string.rep("word ", 60)) > translate.passageHeight("Hi"))
check.that("should give a line break its own line", translate.passageHeight("a\nb") > translate.passageHeight("ab"))
check.that("should cap the room a very long translation takes", translate.passageHeight(string.rep("word ", 2000)) == translate.passageHeight(string.rep("word ", 4000)))

check.finish()
