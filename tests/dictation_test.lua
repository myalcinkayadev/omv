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
check.that("should use dictation for a language both engines know", dictation.engine("en-TR", locales) == "dictation")
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
check.that("should name a language it knows nothing of by its id", dictation.languageName(mac, "xx-YY") == "xx-YY")
check.that("should know a language's model is on the Mac", dictation.isInstalled(mac, "en-TR") == true)
check.that("should know a language's model isn't on the Mac", dictation.isInstalled(mac, "tr-TR") == false)
check.that("should read the microphone access", mac.microphone == "granted")

-- The Dictation card.
local function find(rows, id) for _, row in ipairs(rows) do if row.id == id then return row end end end
local cardRows = dictation.cardRows({ ownLanguage = false, language = "Turkish (Türkiye)", sounds = true, microphone = "granted", installed = true,
  words = { "omv", "AeroSpace", "SketchyBar", "Ghostty", "Hammerspoon" }, cleanup = true, kept = 0 })
check.that("should mark macOS's language on the card", find(cardRows, "language").hint == "macOS's: Turkish (Türkiye)  ›")
check.that("should show a language the file picked without the mark",
  find(dictation.cardRows({ ownLanguage = true, language = "English (United States)" }), "language").hint == "English (United States)  ›")
check.that("should say the microphone is allowed", find(cardRows, "permissions").hint == "allowed")
check.that("should say the microphone will be asked before it was", find(dictation.cardRows({ language = "x" }), "permissions").hint == "asked on the first hold")
check.that("should say the model is on the Mac", find(cardRows, "install").label == "Turkish (Türkiye) model" and find(cardRows, "install").hint == "on this Mac")
check.that("should offer to get a model that isn't", find(dictation.cardRows({ language = "x" }), "install").hint == "get it  ›")
check.that("should say no dictation is kept yet", find(cardRows, "dictations").hint == "none yet")
check.that("should count the dictations kept", find(dictation.cardRows({ language = "x", kept = 4 }), "dictations").hint == "the last 4  ›")
check.that("should show the first three of your words and how many more", find(cardRows, "words").hint == "omv, AeroSpace, SketchyBar +2  ›")
check.that("should say none without your words", find(dictation.cardRows({ language = "x" }), "words").hint == "none  ›")
check.that("should show clean-up on or off", find(cardRows, "cleanup").hint == "‹  on  ›"
  and find(dictation.cardRows({ language = "x", cleanup = false }), "cleanup").hint == "‹  off  ›")

-- The meter.
check.that("should map -55 dB and below to 0", dictation.levelOf(-55) == 0 and dictation.levelOf(-90) == 0)
check.that("should map -15 dB and above to 1", dictation.levelOf(-15) == 1 and dictation.levelOf(0) == 1)
check.that("should map between linearly", math.abs(dictation.levelOf(-35) - 0.5) < 0.001)
check.that("should rise at once", math.abs(dictation.smooth(0, 1) - 0.6) < 0.001)
check.that("should fall slowly", math.abs(dictation.smooth(1, 0) - 0.92) < 0.001)

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
local held = dictation.header({ started = 100, app = "Ghostty" }, 106)
check.that("should show the mic, live, while held", held.icon == "mic" and held.live == true and held.status == "Listening")
check.that("should always show a timer", held.timer == "0:06" and held.warning == false)
check.that("should name the app the words land in", held.target.kind == "app" and held.target.name == "Ghostty")
local lockedHeader = dictation.header({ started = 0, locked = true, left = 8, app = "Notes" }, 292)
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
local layout = { x = 190, w = 200 }
local function wave(recording) return dictation.wave(recording, layout) end
local function height(curves)
  local most = 0
  for _, curve in ipairs(curves) do
    for _, point in ipairs(curve.points) do most = math.max(most, math.abs(point.y - 25)) end
  end
  return most
end
local function bands(low, mid, high) return { low = low, mid = mid, high = high } end
local loud = wave({ bands = bands(1, 1, 1), phases = { 0.3, 0.3, 0.3 } })
check.that("should taper the wave to the centre line at both ends", math.abs(loud[1].points[1].y - 25) < 1e-6
  and math.abs(loud[1].points[#loud[1].points].y - 25) < 1e-6)
check.that("should raise the wave when the voice is louder",
  height(loud) > height(wave({ bands = bands(0.2, 0.2, 0.2), phases = { 0.3, 0.3, 0.3 } })))
check.that("should leave a small ripple when silent", dictation.waveAmplitude({ bands = bands(0, 0, 0) }, "mid") == 1.5
  and height(wave({ bands = bands(0, 0, 0), phases = { 0.3, 0.3, 0.3 } })) > 0)
check.that("should move each curve faster when its band is louder",
  dictation.wavePhase({ 0, 0, 0 }, bands(1, 1, 1), 0.05)[1] > dictation.wavePhase({ 0, 0, 0 }, bands(0.2, 0.2, 0.2), 0.05)[1])
local hiss = wave({ bands = bands(0, 0, 1), phases = { 0.3, 0.3, 0.3 } })
check.that("should drive each curve by its own band", height({ hiss[3] }) > 5 and height({ hiss[1] }) <= 1.5 and height({ hiss[2] }) <= 1.5)
local function hump(curve)
  local best, at = -1, nil
  for _, point in ipairs(curve.points) do
    local taper = dictation.taperAt(curve, point.x)
    if taper > best then best, at = taper, point.x end
  end
  return at
end
check.that("should move the hump right for hiss", hump(hiss[1]) > 190 + 100 + 2)
check.that("should move the hump left for hum", hump(wave({ bands = bands(1, 0, 0) })[1]) < 190 + 100 - 2)
check.that("should keep the hump in the middle when silent", math.abs(hump(wave({ bands = bands(0, 0, 0) })[1]) - (190 + 100)) <= 2)
local counting = wave({ locked = true, left = 7, bands = bands(1, 1, 1), phases = { 0.3, 0.3, 0.3 } })
local lastX = counting[1].points[#counting[1].points].x
check.that("should shrink the wave to the left during the countdown", math.abs(lastX - (190 + 140)) < 2.01)
check.that("should draw the countdown wave in orange", counting[1].warning == true)
local closing = wave({ finishing = true, bands = bands(1, 1, 1) })
check.that("should draw a low, dim wave while finishing", dictation.waveAmplitude({ finishing = true, bands = bands(1, 1, 1) }, "mid") == 2.5
  and closing[1].dim == true)
check.that("should hold the wave still when Reduce Motion is on", dictation.wavePhase({ 1, 2, 3 }, bands(1, 1, 1), 0.05, true)[2] == 2)

-- The bands, scaled by their recent peak.
local function db(amplitude) return 20 * math.log10(amplitude) end
check.that("should read a bands line", (function()
  local line = dictation.parse("bands\t-40 -30.5 -50")
  return line.kind == "bands" and line.bands.low == -40 and line.bands.mid == -30.5 and line.bands.high == -50
end)())
local gain = dictation.newGain()
for _ = 1, 20 do dictation.gain(gain, bands(db(0.1), db(0.1), db(0.1)), 0.033) end
local steady = dictation.gain(gain, bands(db(0.1), db(0.1), db(0.1)), 0.033)
check.that("should keep headroom above the recent peak", math.abs(steady.mid - 0.8) < 0.01)
check.that("should rise to the top only on a new peak", dictation.gain(gain, bands(db(0.1), db(0.2), db(0.1)), 0.033).mid == 1)
local fading = dictation.newGain()
dictation.gain(fading, bands(db(0.1), db(0.1), db(0.1)), 0.033)
for _ = 1, 90 do dictation.gain(fading, bands(-90, -90, -90), 0.033) end
check.that("should let the peak fall slowly so a quieter voice fills the wave again",
  dictation.gain(fading, bands(db(0.05), db(0.05), db(0.05)), 0.033).mid > 0.6)
check.that("should keep room noise as a ripple", dictation.gain(dictation.newGain(), bands(-60, -60, -60), 0.033).mid == 0)

check.that("should draw three curves at 1, 0.5 and 0.25 brightness", #loud == 3 and loud[1].alpha == 1 and loud[2].alpha == 0.5 and loud[3].alpha == 0.25)

check.finish()
