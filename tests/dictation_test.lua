-- Dictation: holding Right Option alone records, releasing types what was heard; two taps
-- lock it hands-free. Run through dictation_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local dictation = require("dictation")

-- Feeds events, { name, time }, to a fresh key state; gives each event's action, "-" for none.
local function run(events)
  local state, actions = dictation.keys(), {}
  for _, event in ipairs(events) do
    local action = dictation.press(state, event[1], event[2])
    actions[#actions + 1] = action or "-"
  end
  return table.concat(actions, " "), state
end

-- The key.
check.that("should record at the press and show the pill after 0.3 s alone",
  run({ { "option-down", 0 }, { "tick", 0.2 }, { "tick", 0.31 } }) == "record - show")
check.that("should cancel when another key is pressed during the hold",
  run({ { "option-down", 0 }, { "other", 0.1 }, { "tick", 0.5 } }) == "record cancel -")
check.that("should not show on a hold shorter than 0.3 s",
  run({ { "option-down", 0 }, { "option-up", 0.2 }, { "tick", 0.7 } }) == "record - cancel")
check.that("should read only Right Option as the key", dictation.eventFor(61, true) == "option-down"
  and dictation.eventFor(61, false) == "option-up" and dictation.eventFor(58, true) == nil)
check.that("should read a release with Shift held", dictation.eventFor(61, false, true) == "option-up-shift")
check.that("should read a Shift press, either side, as a Shift tap", dictation.eventFor(56, false, true) == "shift"
  and dictation.eventFor(60, false, true) == "shift" and dictation.eventFor(56, false, false) == nil)
check.that("should finish when Right Option is released",
  run({ { "option-down", 0 }, { "tick", 0.31 }, { "option-up", 1 } }) == "record show finish")
check.that("should lock on two taps within 0.4 s",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 } }) == "record - lock")
check.that("should finish a locked one on the next tap",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "option-up", 0.35 }, { "option-down", 2 }, { "option-up", 2.1 } })
    == "record - lock - finish -")
check.that("should finish a locked one after 5 minutes",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "option-up", 0.35 }, { "voice", 95 }, { "tick", 100 }, { "voice", 290 }, { "tick", 300.4 } })
    == "record - lock - - - - timeout")
check.that("should cancel on Esc while listening",
  run({ { "option-down", 0 }, { "tick", 0.31 }, { "escape", 1 } }) == "record show cancel")
check.that("should swallow Esc only while listening", (function()
  local state = dictation.keys()
  local idle = select(2, dictation.press(state, "escape", 0))
  dictation.press(state, "option-down", 1)
  dictation.press(state, "tick", 1.4)
  return idle == false and select(2, dictation.press(state, "escape", 2)) == true
end)())
check.that("should leave other keys alone", select(2, dictation.press(dictation.keys(), "other", 0)) == false)

-- The helper's lines.
local partial, final = dictation.parse("partial\tHey there"), dictation.parse("final\tHey there.")
check.that("should read a partial line", partial.kind == "partial" and partial.text == "Hey there")
check.that("should read a final line", final.kind == "final" and final.text == "Hey there.")
check.that("should read a download's progress", dictation.parse("progress\t48").percent == 48)
check.that("should read a level", dictation.parse("level\t0.25").level == 0.25)
check.that("should read a problem", dictation.parse("problem\tno-microphone").problem == "no-microphone")
check.that("should ignore a line it doesn't know", dictation.parse("hello") == nil)
check.that("should type what was heard", dictation.outcome("Hey there.").text == "Hey there." and dictation.outcome("Hey there.").kind == "type")
check.that("should say it didn't catch anything for an empty final",
  dictation.outcome("  ").kind == "notice" and dictation.outcome("  ").text == "Didn't catch that" and dictation.outcome(nil).kind == "notice")
check.that("should say when the microphone is off", dictation.notice("no-microphone") == "No microphone access")
check.that("should say when the language can't be heard", dictation.notice("language", "xx-YY") == "This Mac can't take dictation in xx-YY")

-- Pasting.
local function kinds(steps)
  local names = {}
  for _, step in ipairs(steps) do names[#names + 1] = step.kind end
  return table.concat(names, " ")
end
local steps = dictation.pasteSteps("Hey", { ["public.utf8-plain-text"] = "before" }, "type")
check.that("should restore the clipboard only after the paste and a wait", kinds(steps) == "write paste wait restore"
  and steps[3].seconds >= 0.5 and steps[4].saved["public.utf8-plain-text"] == "before")
check.that("should empty a clipboard that was empty before", kinds(dictation.pasteSteps("Hey", {}, "type")) == "write paste wait clear")
check.that("should mark the paste transient, so clipboard history skips it", steps[1].transient == true and steps[1].text == "Hey")
check.that("should only write the clipboard when copying", kinds(dictation.pasteSteps("Hey", {}, "copy")) == "write")
check.that("should keep the text in clipboard history when it's copied", dictation.pasteSteps("Hey", {}, "copy")[1].transient == false)

-- Where the words go.
local function deliver(info) return dictation.delivery(info, "one two three") end
check.that("should type the words when Right Option is released", deliver({ hasWindow = true, app = "Zed" }).kind == "type")
check.that("should say how many words were typed", deliver({ hasWindow = true }).message == "Typed 3 words")
check.that("should say how many ums were dropped", dictation.delivery({ hasWindow = true }, "one", 2).message == "Typed 1 word · 2 ums dropped")
check.that("should copy the words when Shift+release ends a hold", deliver({ review = true, hasWindow = true }).kind == "copy")
check.that("should show the copied count when the words are copied", deliver({ review = true, hasWindow = true }).message == "Copied 3 words")
check.that("should copy instead of type when the target is a password field", deliver({ secure = true, hasWindow = true }).kind == "copy")
check.that("should say a password field isn't typed into",
  deliver({ secure = true, hasWindow = true }).message == "Not typed into a password field · on the clipboard")
check.that("should copy when no window has focus", deliver({ hasWindow = false }).kind == "copy")
check.that("should paste into the focused app when focus changed before the release",
  deliver({ hasWindow = true, startApp = "Zed", app = "Slack" }).kind == "type")
check.that("should type after 30 s of silence when locked", deliver({ auto = true, hasWindow = true, startApp = "Zed", app = "Zed" }).kind == "type")
check.that("should copy, not type, when a silent lock ends after focus moved",
  deliver({ auto = true, hasWindow = true, startApp = "Zed", app = "Slack" }).kind == "copy")
check.that("should name the app that lost focus",
  deliver({ auto = true, hasWindow = true, startApp = "Zed", app = "Slack" }).message == "Zed lost focus · on the clipboard")

-- Last dictations.
local recent = {}
for index = 1, 12 do recent = dictation.remember(recent, { text = "text " .. index, app = "Ghostty", at = index }) end
check.that("should keep the last ten, newest first", #recent == 10 and recent[1].text == "text 12" and recent[10].text == "text 3")
check.that("should keep each dictation's app and time", recent[1].app == "Ghostty" and recent[1].at == 12)
check.that("should not keep an empty dictation", #dictation.remember({}, { text = "  ", app = "x", at = 1 }) == 0)
local history = dictation.historyRows({ { text = "a", app = "Ghostty", at = 990 }, { text = "b", app = "Notes", at = 1000 - 18 * 60 },
  { text = "c", app = "Zed", at = 1000 - 3 * 3600 } }, 1000)
check.that("should show history times as now, minutes and hours",
  history[1].hint == "Ghostty · now" and history[2].hint == "Notes · 18 min" and history[3].hint == "Zed · 3 h")
check.that("should label each history row with its text", history[2].label == "b" and history[2].id == "dictation:2")

-- Language.
check.that("should use the file's language line", dictation.language("# mine\nlanguage = tr-TR\n", { "en-TR" }) == "tr-TR")
check.that("should use macOS's language without a language line", dictation.language(nil, { "en-TR", "tr-TR" }) == "en-TR")
check.that("should fall back to en-US without either", dictation.language("", {}) == "en-US")
local locales = dictation.parseLocales("transcriber\ten-US en-GB de-DE\ndictation\ten-US tr-TR\n")
check.that("should read the helper's locale lists", locales.transcriber[1] == "en-US" and locales.dictation[2] == "tr-TR")
check.that("should use the transcriber for a language both engines know", dictation.engine("en-TR", locales) == "transcriber")
check.that("should use dictation for a language only it lists", dictation.engine("tr-TR", locales) == "dictation")
check.that("should use the transcriber for a language only it lists", dictation.engine("de-DE", locales) == "transcriber")
check.that("should have no engine for a language neither lists", dictation.engine("xx-YY", locales) == nil)

-- The settings file.
check.that("should have sounds on without a sounds line", dictation.sounds(nil) == true and dictation.sounds("language = tr-TR\n") == true)
check.that("should turn sounds off with sounds = off", dictation.sounds("sounds = off # quiet\n") == false)
local written = dictation.setting("# mine\nlanguage = en-US\n", "language", "tr-TR")
check.that("should replace the language line and keep comments", written == "# mine\nlanguage = tr-TR\n")
check.that("should add a line the file doesn't have", dictation.setting("# mine\n", "sounds", "off") == "# mine\nsounds = off\n")
check.that("should add a line without a file", dictation.setting(nil, "sounds", "off") == "sounds = off\n")
check.that("should remove the language line for macOS's language", dictation.setting(written, "language", nil) == "# mine\n")

-- What the helper says about the Mac.
local mac = dictation.parseLocales("transcriber\ten-US\ndictation\ten-US tr-TR\ninstalled\ten-US\nmicrophone\tgranted\nname\ttr-TR\tTurkish (Türkiye)\n")
check.that("should name a language by what the helper says", dictation.languageName(mac, "tr-TR") == "Turkish (Türkiye)")
check.that("should drop the region from a language's name", dictation.plainLanguage("English (United States)") == "English"
  and dictation.plainLanguage("Turkish (Türkiye)") == "Turkish")
check.that("should keep a language's name without a region as it is", dictation.plainLanguage("Turkish") == "Turkish")
check.that("should name a language it knows nothing of by its id", dictation.languageName(mac, "xx-YY") == "xx-YY")
check.that("should know a language's model is on the Mac", dictation.isInstalled(mac, "en-TR") == true)
check.that("should know a language's model isn't on the Mac", dictation.isInstalled(mac, "tr-TR") == false)
check.that("should read the microphone access", mac.microphone == "granted")

-- The Dictation card.
local function find(rows, id) for _, row in ipairs(rows) do if row.id == id then return row end end end
local function at(rows, id) for index, row in ipairs(rows) do if row.id == id then return index end end end
local cardRows = dictation.cardRows({ language = "Turkish", tabLanguage = "English", sounds = true, microphone = "granted",
  words = { "omv", "AeroSpace", "SketchyBar", "Ghostty", "Hammerspoon" }, cleanup = true, kept = 0,
  talkBackVoice = "Apple", talkBackOutput = "headphones" })
check.that("should list Languages first with both names when a Tab language is set",
  at(cardRows, "languages") == 1 and find(cardRows, "languages").hint == "Turkish, English (Tab)  ›")
check.that("should list only the start language when no Tab language is set",
  find(dictation.cardRows({ language = "English" }), "languages").hint == "English  ›")
check.that("should hint get it when a model is missing",
  find(dictation.cardRows({ language = "English", languageMissing = true }), "languages").hint == "get it · English  ›")
check.that("should have no Key, Tab languages or model row", find(cardRows, "key") == nil and find(cardRows, "language") == nil
  and find(cardRows, "install") == nil)
check.that("should group rows as Hearing, Feedback, Talk-back and Needs", find(cardRows, "languages").group == "Hearing"
  and find(cardRows, "sounds").group == "Feedback" and find(cardRows, "talkBackVoice").group == "Talk-back"
  and find(cardRows, "permissions").group == "Needs")
check.that("should put the talk-back rows at 7 and 8 when talk-back is on", at(cardRows, "talkBackVoice") == 7 and at(cardRows, "talkBackOutput") == 8)
check.that("should keep the toggles where Left/Right finds them", at(cardRows, "cleanup") == dictation.CARD_ROWS.cleanup
  and at(cardRows, "sounds") == dictation.CARD_ROWS.sounds and dictation.CARD_ROWS.talkBackVoice == 7)
check.that("should leave out the talk-back rows when talk-back is off", find(dictation.cardRows({ language = "x" }), "talkBackVoice") == nil)
check.that("should say the microphone is allowed", find(cardRows, "permissions").hint == "allowed")
check.that("should say the microphone will be asked before it was", find(dictation.cardRows({ language = "x" }), "permissions").hint == "asked on the first hold")
check.that("should say no dictation is kept yet", find(cardRows, "dictations").hint == "none yet")
check.that("should count the dictations kept", find(dictation.cardRows({ language = "x", kept = 4 }), "dictations").hint == "the last 4  ›")
local rulesRow = function(rules) return find(dictation.cardRows({ language = "x", replacements = rules }), "replacements").hint end
check.that("should show the first replacement and how many more when there are several", rulesRow({ { from = "slash voice", to = "/voice" },
  { from = "at sign", to = "@" }, { from = "new line", to = "\n" } }) == "slash voice → /voice +2  ›")
check.that("should show the only replacement when there is one", rulesRow({ { from = "at sign", to = "@" } }) == "at sign → @  ›")
check.that("should say none when there are no replacements", rulesRow({}) == "none  ›" and rulesRow(nil) == "none  ›")
check.that("should show the first three of your words and how many more", find(cardRows, "words").hint == "omv, AeroSpace, SketchyBar +2  ›")
check.that("should say none without your words", find(dictation.cardRows({ language = "x" }), "words").hint == "none  ›")
check.that("should show clean-up on or off", find(cardRows, "cleanup").hint == "‹  on  ›"
  and find(dictation.cardRows({ language = "x", cleanup = false }), "cleanup").hint == "‹  off  ›")

-- The Languages screen.
local languageRows = dictation.languageRows({ startName = "English (United States)", startInstalled = true, ownStart = true })
check.that("should hint on this Mac when the start model is installed", find(languageRows, "start").hint == "English (United States) · on this Mac  ›")
check.that("should mark macOS's language when the file picks none",
  find(dictation.languageRows({ startName = "English", startInstalled = true }), "start").hint == "macOS's: English · on this Mac  ›")
check.that("should hint none when no Tab language is set", find(languageRows, "tab").hint == "none  ›")
check.that("should hint get it when the Tab model is missing",
  find(dictation.languageRows({ startName = "English", startInstalled = true, ownStart = true, tabName = "Turkish", tabInstalled = false }), "tab").hint
    == "Turkish · get it  ›")

-- Writing the languages.
check.that("should give the other language when languages lists two", dictation.tabLanguage("languages = en-US, tr-TR\n", "en-US") == "tr-TR")
check.that("should give nil when there's no languages line", dictation.tabLanguage("language = en-US\n", "en-US") == nil)
check.that("should give nil when languages lists only the start language", dictation.tabLanguage("languages = en-US\n", "en-US") == nil)
check.that("should write language and languages when a different tab language is given",
  dictation.withLanguages("sounds = on\n", "en-US", "tr-TR") == "sounds = on\nlanguage = en-US\nlanguages = en-US, tr-TR\n")
check.that("should remove languages when tab is nil",
  dictation.withLanguages("language = en-US\nlanguages = en-US, tr-TR\n", "en-US", nil) == "language = en-US\n")
check.that("should remove languages when tab equals the start language",
  dictation.withLanguages("language = en-US\nlanguages = en-US, tr-TR\n", "tr-TR", "tr-TR") == "language = tr-TR\n")
check.that("should keep other lines when writing", dictation.withLanguages("words = omv\n# mine\n", "tr-TR", nil) == "words = omv\n# mine\nlanguage = tr-TR\n")

-- The meter.
check.that("should map -55 dB and below to 0", dictation.levelOf(-55) == 0 and dictation.levelOf(-90) == 0)
check.that("should map -15 dB and above to 1", dictation.levelOf(-15) == 1 and dictation.levelOf(0) == 1)
check.that("should map between linearly", math.abs(dictation.levelOf(-35) - 0.5) < 0.001)

-- The words.
local lines = dictation.wrap("one two three four five six seven", 10)
check.that("should wrap words into lines no longer than the width", table.concat(lines, "|") == "one two|three four|five six|seven")
check.that("should break a word longer than a line", table.concat(dictation.wrap("abcdefghijkl", 5), "|") == "abcde|fghij|kl")
check.that("should give no lines for no words", #dictation.wrap("", 10) == 0)
local long = dictation.lastLines({ "a", "b", "c", "d", "e", "f" }, 4)
check.that("should keep only the last 4 lines", table.concat(long, "|") == "c|d|e|f")
check.that("should size the pill by its lines, 1 to 4", dictation.pillHeight(0) == dictation.pillHeight(1)
  and dictation.pillHeight(2) > dictation.pillHeight(1) and dictation.pillHeight(6) == dictation.pillHeight(4))

-- Your words and clean-up.
check.that("should read the words line as a list", table.concat(dictation.words("words = omv,  AeroSpace , SketchyBar # mine\n"), "|") == "omv|AeroSpace|SketchyBar")
check.that("should give no words without a words line", #dictation.words("language = tr-TR\n") == 0 and #dictation.words(nil) == 0)
check.that("should clean up unless cleanup = off", dictation.cleanupOn(nil) and not dictation.cleanupOn("cleanup = off\n"))
local cleaned, dropped = dictation.clean("So, um, we move the uh gaps ıı now")
check.that("should drop filler sounds", cleaned == "So, we move the gaps now")
check.that("should count the fillers dropped", dropped == 3)
check.that("should capitalise after dropping a filler at the start", (dictation.clean("Um, the bar is fine")) == "The bar is fine")
check.that("should keep şey, a real word", (dictation.clean("bir şey söyle")) == "bir şey söyle")
check.that("should keep words that contain a filler", (dictation.clean("summer umbrella hummus")) == "summer umbrella hummus")
check.that("should drop Turkish ee", (dictation.clean("ee yarın gelirim")) == "yarın gelirim")

-- Review, and a locked one ending by itself.
check.that("should review on a release with Shift held",
  run({ { "option-down", 0 }, { "tick", 0.31 }, { "option-up-shift", 1 } }) == "record show review")
check.that("should review on a Shift tap while locked",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "option-up", 0.35 }, { "shift", 2 } }) == "record - lock - review")
check.that("should time out a locked one after 30 s without voice",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "option-up", 0.35 }, { "tick", 20 }, { "tick", 30.4 } })
    == "record - lock - - timeout")
check.that("should cancel when Esc is pressed during the countdown",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "option-up", 0.35 }, { "tick", 25 }, { "escape", 26 }, { "tick", 31 } })
    == "record - lock - - cancel -")
check.that("should take a loud level as voice", dictation.isVoice(dictation.levelOf(-25)))
check.that("should not take a quiet room as voice", not dictation.isVoice(dictation.levelOf(-50)))
check.that("should keep a locked one going while voice comes",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "option-up", 0.35 }, { "voice", 25 }, { "tick", 40 } })
    == "record - lock - - -")
local lockedState = select(2, run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "voice", 290 } }))
check.that("should give no time left before the last 10 s", dictation.remaining(lockedState, 280) == nil)
check.that("should count down the last 10 s to the 5-minute limit", dictation.remaining(lockedState, 292.3) == 8)
local quiet = select(2, run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "voice", 10 } }))
check.that("should count down to 30 s of silence when it comes first", dictation.remaining(quiet, 33) == 7)
check.that("should give no time left while held", dictation.remaining(select(2, run({ { "option-down", 0 }, { "tick", 0.31 } })), 290) == nil)

-- The pill's header.
local held = dictation.header({ started = 100, ready = true, app = "Ghostty" }, 106)
check.that("should show the mic, live, while held", held.icon == "mic" and held.live == true and held.status == "Listening")
check.that("should always show a timer", held.timer == "0:06" and held.warning == false)
check.that("should name the app the words land in", held.target.kind == "app" and held.target.name == "Ghostty")
local lockedHeader = dictation.header({ started = 0, ready = true, locked = true, left = 8, app = "Notes" }, 292)
check.that("should show the lock, live, while locked", lockedHeader.icon == "lock" and lockedHeader.live and lockedHeader.status == "Locked")
check.that("should turn the timer into an orange countdown in the last 10 s", lockedHeader.timer == "0:08" and lockedHeader.warning == true)
local finishingHeader = dictation.header({ started = 100, finishing = true, stopped = 111, app = "Ghostty" }, 112)
check.that("should show a spinner, not live, while finishing", finishingHeader.icon == "spinner" and finishingHeader.live == false
  and finishingHeader.status == "Finishing" and finishingHeader.timer == "0:11")
check.that("should warn of a password field as the target", dictation.header({ started = 0, secure = true, app = "Safari" }, 1).target.kind == "password")

check.that("should cut an app name at 18 characters", dictation.header({ started = 0, app = "Visual Studio Code Insiders" }, 1).target.name
  == "Visual Studio Cod…")
check.that("should keep an 18-character app name whole", dictation.header({ started = 0, app = "Microsoft Outlook!" }, 1).target.name
  == "Microsoft Outlook!")

-- The meter: a wave from after the timer to 10 pt before the app chip.
local wide, narrow = dictation.meterLayout(81), dictation.meterLayout(200)
check.that("should end the strip 10 pt before the app chip", wide.x + wide.w == 560 - 18 - 81 - 10)
check.that("should give the wave less room when the app name is long", narrow.w < wide.w)

-- Redrawing: the pill only when its text changes; the wave is dictate.swift's.
local base = { started = 100, app = "Zed", partial = "hello" }
local function with(changes)
  local copy = {}
  for key, value in pairs(base) do copy[key] = value end
  for key, value in pairs(changes) do copy[key] = value end
  return copy
end
check.that("should keep the frame's text within the same second", dictation.frameKey(base, 105.2) == dictation.frameKey(base, 105.6))
check.that("should change the frame's text when the timer ticks", dictation.frameKey(base, 105.2) ~= dictation.frameKey(base, 106.1))
check.that("should change the frame's text when words come", dictation.frameKey(base, 105) ~= dictation.frameKey(with({ partial = "hello there" }), 105))
check.that("should change the frame's text when the app changes", dictation.frameKey(base, 105) ~= dictation.frameKey(with({ app = "Slack" }), 105))
check.that("should change the frame's text when it locks", dictation.frameKey(base, 105) ~= dictation.frameKey(with({ locked = true }), 105))
-- Telling dictate.swift where to draw the wave.
local colors = { fg = "#ffffff", accent = "#8d8d8d", warning = "#f0a35e" }
local strip = { x = 1190.4, y = 1240, w = 262 }
check.that("should tell the helper where the strip is while listening",
  dictation.waveCommand(strip, { started = 0 }, colors, false) == "wave 1190 1240 262 listening -1 ffffff 8d8d8d f0a35e 0")
check.that("should tell the helper the seconds left while locked",
  dictation.waveCommand(strip, { started = 0, locked = true, left = 7 }, colors, false) == "wave 1190 1240 262 locked 7 ffffff 8d8d8d f0a35e 0")
check.that("should tell the helper it's finishing, with no countdown",
  dictation.waveCommand(strip, { started = 0, locked = true, left = 3, finishing = true }, colors, false)
    == "wave 1190 1240 262 finishing -1 ffffff 8d8d8d f0a35e 0")
check.that("should tell the helper when Reduce Motion is on",
  dictation.waveCommand(strip, { started = 0 }, colors, true) == "wave 1190 1240 262 listening -1 ffffff 8d8d8d f0a35e 1")

-- The helper ending.
check.that("should finish with what was heard when the helper ends while finishing",
  dictation.onHelperExit({ finishing = true, partial = "ship it" }) == "finish")
check.that("should hide the pill when the helper ends while listening", dictation.onHelperExit({ partial = "ship it" }) == "hide")
check.that("should leave a problem shown when the helper ends after it", dictation.onHelperExit({ finishing = true, problem = "x" }) == nil)
check.that("should give up finishing after 15 s", dictation.finishOverdue({ finishing = true, stopped = 100 }, 115.1))
check.that("should keep finishing before 15 s", not dictation.finishOverdue({ finishing = true, stopped = 100 }, 114))
check.that("should not count a recording that isn't finishing as overdue", not dictation.finishOverdue({ stopped = 100 }, 200))

-- The app a dictation is kept with.
check.that("should keep a typed dictation with the app it was typed into",
  dictation.historyApp({ startApp = "Zed" }, "Slack") == "Slack")
check.that("should keep a locked one that lost focus with the app it started in",
  dictation.historyApp({ auto = true, startApp = "TextEdit" }, "Finder") == "TextEdit")
check.that("should keep a reviewed one with the app you were in", dictation.historyApp({ review = true }, "Slack") == "Slack")

-- The history file, so dictations outlive a reload.
local kept = { { text = "first\tline\nsecond", app = "Zed", at = 200 }, { text = "older", app = "", at = 100 } }
local back = dictation.parseHistory(dictation.historyText(kept))
check.that("should read back what it saved", #back == 2 and back[1].text == "first\tline\nsecond" and back[1].app == "Zed"
  and back[1].at == 200 and back[2].text == "older" and back[2].app == "" and back[2].at == 100)
check.that("should save one dictation a line", select(2, dictation.historyText(kept):gsub("\n", "")) == 2)
check.that("should read no dictations from an empty file", #dictation.parseHistory("") == 0 and #dictation.parseHistory(nil) == 0)
check.that("should skip a line it can't read", #dictation.parseHistory("garbage\n300\tZed\tok\n") == 1)
local many = {}
for index = 1, 15 do many[#many + 1] = string.format("%d\tZed\ttext %d", 1000 - index, index) end
check.that("should keep the last 10 it reads", #dictation.parseHistory(table.concat(many, "\n")) == 10)

-- Starting until the helper says ready.
local starting = dictation.header({ started = 100, app = "Ghostty" }, 100.2)
check.that("should say Starting when the helper isn't ready", starting.status == "Starting")
check.that("should show no live dot when the helper isn't ready", starting.live == false)
check.that("should say Listening when the helper is ready", dictation.header({ started = 100, ready = true, app = "Zed" }, 101).status == "Listening")
check.that("should say Locked when locked and ready", dictation.header({ started = 0, ready = true, locked = true, app = "Zed" }, 1).status == "Locked")
check.that("should say Starting when locked and not ready", dictation.header({ started = 0, locked = true, app = "Zed" }, 1).status == "Starting")
check.that("should say Finishing when finishing before ready", dictation.header({ started = 0, finishing = true, stopped = 1, app = "Zed" }, 2).status == "Finishing")
check.that("should not chime when shown and not ready", dictation.chimeDue({ shown = true }) == false)
check.that("should not chime when ready and not shown", dictation.chimeDue({ ready = true }) == false)
check.that("should chime when shown and ready", dictation.chimeDue({ shown = true, ready = true }) == true)
check.that("should not chime again when it chimed", dictation.chimeDue({ shown = true, ready = true, chimed = true }) == false)

-- Spoken replacements.
local rules = dictation.replacements("replace = slash voice > /voice\n# replace = gone > x\nreplace = at sign > @\nreplace = no arrow\nreplace =  > empty\nreplace = new line > a\\nb\n")
check.that("should read each replace line as a rule when there are several", #rules == 3)
check.that("should skip a line with no arrow or an empty phrase", (function()
  for _, rule in ipairs(rules) do if rule.from == "no arrow" or rule.to == "empty" then return false end end
  return true end)())
check.that("should ignore a commented replace line", (function()
  for _, rule in ipairs(rules) do if rule.from == "gone" then return false end end
  return true end)())
check.that("should turn \\n in a replacement into a line break", (function()
  for _, rule in ipairs(rules) do if rule.from == "new line" then return rule.to == "a\nb" end end
  return false end)())
check.that("should give no rules without replace lines", #dictation.replacements("language = tr-TR\n") == 0)
local slash = dictation.replacements("replace = slash voice > /voice\n")
check.that("should replace a phrase when the case differs", dictation.replace("Slash Voice now", slash) == "/voice now")
check.that("should keep punctuation next to the phrase", dictation.replace("Run slash voice.", slash) == "Run /voice.")
check.that("should not replace inside a longer word", dictation.replace("two slash voices", slash) == "two slash voices")
local overlap = dictation.replacements("replace = line > L\nreplace = new line > NL\n")
check.that("should prefer the longer phrase when rules overlap", dictation.replace("a new line here", overlap) == "a NL here")
check.that("should match a phrase with pattern characters literally", dictation.replace("use c++ here, not cxx", dictation.replacements("replace = c++ > C plus\n")) == "use C plus here, not cxx")
check.that("should replace a Turkish phrase", dictation.replace("bunu eğik çizgi ile yaz", dictation.replacements("replace = eğik çizgi > /\n")) == "bunu / ile yaz")
check.that("should not replace a Turkish phrase inside a longer word", dictation.replace("çizgiler", dictation.replacements("replace = çizgi > /\n")) == "çizgiler")
check.that("should leave the text as it is when there are no rules", dictation.replace("slash voice", {}) == "slash voice")
check.that("should give empty text for empty text", dictation.replace("", slash) == "")
check.that("should keep a % in a replacement as it is", dictation.replace("per cent", dictation.replacements("replace = per cent > %\n")) == "%")

-- Flipping the language with Tab.
local both = dictation.languages("languages = tr-TR, en-US\n")
check.that("should read the languages line as a list", #both == 2 and both[1] == "tr-TR" and both[2] == "en-US")
check.that("should give no languages without the line", #dictation.languages("language = tr-TR\n") == 0)
check.that("should give the next language", dictation.nextLanguage({ "tr-TR", "en-US", "de-DE" }, "tr-TR") == "en-US")
check.that("should wrap to the first after the last", dictation.nextLanguage({ "tr-TR", "en-US" }, "en-US") == "tr-TR")
check.that("should give no next language with fewer than 2", dictation.nextLanguage({ "tr-TR" }, "tr-TR") == nil
  and dictation.nextLanguage({}, "tr-TR") == nil)
check.that("should give the first other language when the current one isn't listed", dictation.nextLanguage({ "tr-TR", "en-US" }, "de-DE") == "tr-TR"
  and dictation.nextLanguage({ "tr-TR", "en-US" }, "tr") == "tr-TR")
local function pressed(events, last)
  local state = dictation.keys()
  for _, event in ipairs(events) do dictation.press(state, event[1], event[2]) end
  local action, swallow = dictation.press(state, last[1], last[2])
  return action, swallow, state
end
local heldAction, heldSwallow, heldState = pressed({ { "option-down", 0 }, { "tick", 0.31 } }, { "tab", 1 })
check.that("should switch the language on Tab while held", heldAction == "switch" and heldSwallow == true and heldState.phase == "listening")
local lockAction, lockSwallow, lockState = pressed({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "option-up", 0.35 } }, { "tab", 1 })
check.that("should switch the language on Tab when hands-free and stay hands-free", lockAction == "switch" and lockSwallow == true and lockState.phase == "locked")
local earlyAction, earlySwallow = pressed({ { "option-down", 0 } }, { "tab", 0.1 })
check.that("should cancel on Tab before the pill shows", earlyAction == "cancel" and earlySwallow == false)
local tapAction = pressed({ { "option-down", 0 }, { "option-up", 0.1 } }, { "tab", 0.2 })
check.that("should cancel on Tab after a single tap", tapAction == "cancel")
check.that("should join the words before and after a switch with one space", dictation.join("Hello there.", " Merhaba ") == "Hello there. Merhaba")
check.that("should skip an empty side when joining", dictation.join("", "Merhaba") == "Merhaba" and dictation.join("Hi", nil) == "Hi")
check.that("should show the language code when languages are set", dictation.header({ started = 0, ready = true, app = "Zed", locale = "en-US", languages = 2 }, 1).language == "EN")
check.that("should show no language code without languages", dictation.header({ started = 0, ready = true, app = "Zed", locale = "en-US" }, 1).language == nil)

-- Right Command: agents only, and the mic opens only once it's held alone.
local COMMAND = { late = true, lock = false }

local function runWith(events, options)
  local state, actions, swallowed = dictation.keys(), {}, {}
  for _, event in ipairs(events) do
    local action, swallow = dictation.press(state, event[1], event[2], options)
    actions[#actions + 1] = action or "-"
    swallowed[#swallowed + 1] = swallow and "y" or "n"
  end
  return table.concat(actions, " "), table.concat(swallowed, " ")
end

check.that("should give command-down when keyCode 54 goes down with cmd", dictation.eventFor(54, false, false, true) == "command-down")
check.that("should give command-up when keyCode 54 goes up", dictation.eventFor(54, false, false, false) == "command-up")
check.that("should give no action when Right Command is pressed with late", runWith({ { "command-down", 0 } }, COMMAND) == "-")
check.that("should give start when Right Command is held past the hold with late",
  runWith({ { "command-down", 0 }, { "tick", 0.2 }, { "tick", 0.31 } }, COMMAND) == "- - start")
check.that("should give no action when Right Command is released before the hold",
  runWith({ { "command-down", 0 }, { "command-up", 0.1 }, { "tick", 0.5 } }, COMMAND) == "- - -")
check.that("should not lock when Right Command is tapped twice with lock off",
  runWith({ { "command-down", 0 }, { "command-up", 0.1 }, { "command-down", 0.2 }, { "command-up", 0.25 } }, COMMAND) == "- - - -")
check.that("should finish when Right Command is released after the hold",
  runWith({ { "command-down", 0 }, { "tick", 0.31 }, { "command-up", 1 } }, COMMAND) == "- start finish")
check.that("should give no action when another key comes during the hold with late",
  runWith({ { "command-down", 0 }, { "other", 0.1 }, { "tick", 0.5 } }, COMMAND) == "- - -")
check.that("should cancel when another key is pressed while Right Command listens",
  runWith({ { "command-down", 0 }, { "tick", 0.31 }, { "other", 1 } }, COMMAND) == "- start cancel")
check.that("should not swallow another key when Right Command listens",
  select(2, runWith({ { "command-down", 0 }, { "tick", 0.31 }, { "other", 1 } }, COMMAND)) == "n n n")
check.that("should cancel and swallow Esc while Right Command listens",
  runWith({ { "command-down", 0 }, { "tick", 0.31 }, { "escape", 1 } }, COMMAND) == "- start cancel")

check.that("should say Command when an agent recording is ready",
  dictation.header({ started = 0, ready = true, app = "Zed", agent = true }, 1).status == "Command")
check.that("should show the agent icon when recording for an agent",
  dictation.header({ started = 0, ready = true, app = "Zed", agent = true }, 1).icon == "agent")
check.that("should name the target folder in the chip when recording for an agent",
  dictation.header({ started = 0, ready = true, app = "Zed", agent = true, agentTarget = { kind = "paste", chip = "omv" } }, 1).target.name == "omv")
check.that("should show a dash in the chip when an agent recording has no target yet",
  dictation.header({ started = 0, ready = true, app = "Zed", agent = true, agentTarget = { kind = "none", hint = "x" } }, 1).target.name == "—")
check.that("should say Starting when an agent recording isn't ready",
  dictation.header({ started = 0, app = "Zed", agent = true }, 1).status == "Starting")

check.that("should grow the agent pill by 22 for each row", dictation.agentPillHeight(2, 3) == dictation.pillHeight(2) + 66)

check.that("should replace a setting whose key has a hyphen", dictation.setting("talk-back voice = apple\n", "talk-back voice", "kokoro-man")
  == "talk-back voice = kokoro-man\n")
check.that("should hint get it when Kokoro is chosen but not installed", (function()
  for _, row in ipairs(dictation.cardRows({ language = "English", talkBackVoice = "Kokoro, woman", talkBackMissing = true })) do
    if row.id == "talkBackVoice" then return row.hint:find("get it", 1, true) ~= nil end
  end
  return false
end)())
check.that("should list Talk-back speaks with in headphones by default", (function()
  for _, row in ipairs(dictation.cardRows({ language = "English", talkBackVoice = "Apple" })) do
    if row.id == "talkBackOutput" then return row.hint == "‹  in headphones  ›" end
  end
  return false
end)())

check.finish()
