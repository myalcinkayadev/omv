-- Behavior of the translation services: Apple on the Mac, and DeepL and Claude online.
-- What each is asked and what its answer means, and the cards to pick one. Run through
-- translators_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local translators = require("translators")
local card = require("card")

local function ids(screen)
  local list = {}
  for index, row in ipairs(screen.rows) do list[index] = row.id end
  return table.concat(list, " ")
end

-- The service you picked, saved to a file.
check.that("should read a saved service", translators.parseChoice("deepl\n") == "deepl")
check.that("should read no service from an empty file", translators.parseChoice("") == nil and translators.parseChoice(nil) == nil)
check.that("should read no service from an unknown name", translators.parseChoice("google\n") == nil)
check.that("should tell an online service", translators.find("deepl").online == true)
check.that("should tell Apple works on the Mac", translators.find("apple").online == false)

-- The first-use card.
local chooser = translators.chooserScreen()
check.that("should offer the three services on first use", ids(chooser) == "service:apple service:deepl service:claude")
check.that("should recommend Apple on first use", chooser.selected == 1 and chooser.rows[1].hint:find("Recommended") ~= nil)
check.that("should say DeepL needs a key", chooser.rows[2].hint:find("key") ~= nil)
check.that("should read the service picked", translators.picked("service:claude") == "claude")
check.that("should read another row as no service", translators.picked("copy") == nil)
check.that("should read an unknown service as none", translators.picked("service:bing") == nil)

-- The card to switch service.
local switch = translators.servicesScreen("apple", false)
check.that("should mark the service in use", switch.rows[1].hint == "current")
check.that("should start on the next service", switch.selected == 2)
check.that("should ask for a DeepL key when there's none", switch.rows[2].hint == "add a free key ›")
check.that("should not ask for a key DeepL has", translators.servicesScreen("apple", true).rows[2].hint == "online")

-- DeepL.
local key = "0123abcd-4567-89ef-0123-456789abcdef:fx"
local free = translators.deeplRequest(key, "merhaba", "tr", "en")
check.that("should send a free key to DeepL's free address", free.url == "https://api-free.deepl.com/v2/translate")
check.that("should send a paid key to DeepL's paid address", translators.deeplRequest("0123abcd-4567-89ef-0123-456789abcdef", "a", "tr", "en").url == "https://api.deepl.com/v2/translate")
check.that("should send DeepL the key in its header", free.headers.Authorization == "DeepL-Auth-Key " .. key)
check.that("should ask DeepL for American English", free.body:find("target_lang=EN-US", 1, true) ~= nil)
check.that("should tell DeepL the source language", free.body:find("source_lang=TR", 1, true) ~= nil)
check.that("should ask DeepL for Brazilian Portuguese", translators.deeplRequest(key, "a", "en", "pt").body:find("target_lang=PT-BR", 1, true) ~= nil)
check.that("should escape the text for DeepL", translators.deeplRequest(key, "a b", "en", "de").body:find("text=a%20b", 1, true) ~= nil)
check.that("should read DeepL's translation", translators.parseDeepl({ translations = { { text = "Hello" } } }) == "Hello")
check.that("should read no translation from DeepL's error", translators.parseDeepl({ message = "Wrong key" }) == nil)
check.that("should take a copied DeepL key", translators.deeplKey("  " .. key .. "\n") == key)
check.that("should refuse copied text that isn't a key", translators.deeplKey("hello world") == nil)
check.that("should refuse an empty clipboard as a key", translators.deeplKey(nil) == nil)
local keyCard = translators.keyScreen()
check.that("should offer to get a key first", keyCard.rows[1].id == "deepl:get")
check.that("should offer to use the copied key", keyCard.rows[2].id == "deepl:use")
check.that("should say where the key is kept", keyCard.passage:find("Keychain") ~= nil)

-- Claude.
local claude = translators.claudeArguments("Turkish")
check.that("should ask Claude for the target language", table.concat(claude, " "):find("into Turkish", 1, true) ~= nil)
check.that("should ask Claude for the translation alone", table.concat(claude, " "):find("only the translation", 1, true) ~= nil)
check.that("should run Claude without a session", claude[1] == "-p")
check.that("should ask Claude's fast model", table.concat(claude, " "):find("--model haiku", 1, true) ~= nil)
check.that("should read Claude's translation", translators.parseClaude(0, "  Hello there.\n") == "Hello there.")
check.that("should read no translation when Claude fails", translators.parseClaude(1, "Hello") == nil)
check.that("should read no translation from Claude's empty answer", translators.parseClaude(0, " \n") == nil)

check.that("should draw the first-use card", check.contains(card.html(chooser), "How should omv translate?"))

check.finish()
