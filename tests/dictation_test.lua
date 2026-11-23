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
check.that("should finish when Right Option is released",
  run({ { "option-down", 0 }, { "tick", 0.31 }, { "option-up", 1 } }) == "record show finish")
check.that("should lock on two taps within 0.4 s",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 } }) == "record - lock")
check.that("should finish a locked one on the next tap",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "option-up", 0.35 }, { "option-down", 2 }, { "option-up", 2.1 } })
    == "record - lock - finish -")
check.that("should finish a locked one after 5 minutes",
  run({ { "option-down", 0 }, { "option-up", 0.1 }, { "option-down", 0.3 }, { "option-up", 0.35 }, { "tick", 100 }, { "tick", 300.4 } })
    == "record - lock - - finish")
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
local steps = dictation.pasteSteps("Hey", { ["public.utf8-plain-text"] = "before" }, false, true)
check.that("should restore the clipboard only after the paste and a wait", kinds(steps) == "write paste wait restore"
  and steps[3].seconds >= 0.5 and steps[4].saved["public.utf8-plain-text"] == "before")
check.that("should empty a clipboard that was empty before", kinds(dictation.pasteSteps("Hey", {}, false, true)) == "write paste wait clear")
check.that("should mark the paste transient, so clipboard history skips it", steps[1].transient == true and steps[1].text == "Hey")
check.that("should leave the text on the clipboard without a window to type in",
  kinds(dictation.pasteSteps("Hey", {}, false, false)) == "write notice")
check.that("should not type into a password field", kinds(dictation.pasteSteps("Hey", {}, true, true)) == "write notice")
check.that("should keep the text in clipboard history when it isn't typed", dictation.pasteSteps("Hey", {}, true, true)[1].transient == false)

-- Last dictations.
local recent = {}
for index = 1, 12 do recent = dictation.remember(recent, "text " .. index) end
check.that("should keep the last ten, newest first", #recent == 10 and recent[1] == "text 12" and recent[10] == "text 3")
check.that("should not keep an empty dictation", #dictation.remember({}, "") == 0)

-- Language.
check.that("should use the file's language line", dictation.language("# mine\nlanguage = tr-TR\n", { "en-TR" }) == "tr-TR")
check.that("should use macOS's language without a language line", dictation.language(nil, { "en-TR", "tr-TR" }) == "en-TR")
check.that("should fall back to en-US without either", dictation.language("", {}) == "en-US")
local locales = dictation.parseLocales("transcriber\ten-US en-GB de-DE\ndictation\ten-US tr-TR\n")
check.that("should read the helper's locale lists", locales.transcriber[1] == "en-US" and locales.dictation[2] == "tr-TR")
check.that("should use the transcriber for a language it lists", dictation.engine("en-TR", locales) == "transcriber")
check.that("should use dictation for a language only it lists", dictation.engine("tr-TR", locales) == "dictation")
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
check.that("should name a language it knows nothing of by its id", dictation.languageName(mac, "xx-YY") == "xx-YY")
check.that("should know a language's model is on the Mac", dictation.isInstalled(mac, "en-TR") == true)
check.that("should know a language's model isn't on the Mac", dictation.isInstalled(mac, "tr-TR") == false)
check.that("should read the microphone access", mac.microphone == "granted")

-- The Dictation card.
local function find(rows, id) for _, row in ipairs(rows) do if row.id == id then return row end end end
local cardRows = dictation.cardRows({ ownLanguage = false, language = "Turkish (Türkiye)", sounds = true, microphone = "granted", installed = true })
check.that("should mark macOS's language on the card", find(cardRows, "language").hint == "macOS's: Turkish (Türkiye)  ›")
check.that("should show a language the file picked without the mark",
  find(dictation.cardRows({ ownLanguage = true, language = "English (United States)" }), "language").hint == "English (United States)  ›")
check.that("should say the microphone is allowed", find(cardRows, "permissions").hint == "allowed")
check.that("should say the microphone will be asked before it was", find(dictation.cardRows({ language = "x" }), "permissions").hint == "asked on the first hold")
check.that("should say the model is on the Mac", find(cardRows, "install").label == "Turkish (Türkiye) model" and find(cardRows, "install").hint == "on this Mac")
check.that("should offer to get a model that isn't", find(dictation.cardRows({ language = "x" }), "install").hint == "get it  ›")
check.that("should say no dictation is kept yet", find(cardRows, "last").hint == "none yet")

-- The meter.
check.that("should map -55 dB and below to 0", dictation.levelOf(-55) == 0 and dictation.levelOf(-90) == 0)
check.that("should map -15 dB and above to 1", dictation.levelOf(-15) == 1 and dictation.levelOf(0) == 1)
check.that("should map between linearly", math.abs(dictation.levelOf(-35) - 0.5) < 0.001)
check.that("should rise at once", math.abs(dictation.smooth(0, 1) - 0.6) < 0.001)
check.that("should fall slowly", math.abs(dictation.smooth(1, 0) - 0.92) < 0.001)
local history = {}
for index = 1, 30 do history = dictation.pushLevel(history, index / 30) end
check.that("should keep the last 24 levels, oldest dropped", #history == 24 and history[24] == 1 and math.abs(history[1] - 7 / 30) < 0.001)

-- The words.
local lines = dictation.wrap("one two three four five six seven", 10)
check.that("should wrap words into lines no longer than the width", table.concat(lines, "|") == "one two|three four|five six|seven")
check.that("should break a word longer than a line", table.concat(dictation.wrap("abcdefghijkl", 5), "|") == "abcde|fghij|kl")
check.that("should give no lines for no words", #dictation.wrap("", 10) == 0)
local long = dictation.lastLines({ "a", "b", "c", "d", "e", "f" }, 4)
check.that("should keep only the last 4 lines", table.concat(long, "|") == "c|d|e|f")
check.that("should size the pill by its lines, 1 to 4", dictation.pillHeight(0) == dictation.pillHeight(1)
  and dictation.pillHeight(2) > dictation.pillHeight(1) and dictation.pillHeight(6) == dictation.pillHeight(4))

check.finish()
