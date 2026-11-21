-- Translate the selection (Option+Y): copies what's selected, finds its language and
-- translates it on the Mac through translate.sh, into the Mac's language or, from that,
-- into English. A card shows the translation; Enter pastes it over the selection. The
-- clipboard is put back after the copy. Copying and pasting need Accessibility.

local shell = require("shell")
local card = require("card")
local translate = require("translate")

local feature = {}

local TRANSLATE = hs.configdir .. "/translate.sh"
local TRANSLATION_LANGUAGES = "x-apple.systempreferences:com.apple.Localization-Settings.extension"
local COPY_WAIT_SECONDS = 0.5
local HELPER_SECONDS = 10
local WIDTH = 520

-- Each copy of the clipboard's contents, so a copy for the translation can be undone.
local function saveClipboard()
  return hs.pasteboard.readAllData()
end

local function restoreClipboard(saved)
  if saved and next(saved) then return hs.pasteboard.writeAllData(saved) end
  hs.pasteboard.clearContents()
end

-- Copies the selection with Cmd+C and hands its text to done, nil when nothing was copied.
local function copySelection(done)
  local saved, before = saveClipboard(), hs.pasteboard.changeCount()
  local deadline = hs.timer.secondsSinceEpoch() + COPY_WAIT_SECONDS
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  hs.timer.waitUntil(function()
    return hs.pasteboard.changeCount() ~= before or hs.timer.secondsSinceEpoch() >= deadline
  end, function()
    local copied = hs.pasteboard.changeCount() ~= before and hs.pasteboard.getContents() or nil
    restoreClipboard(saved)
    done(copied)
  end, 0.05)
end

-- Runs translate.sh with the text on stdin; a helper that hangs is stopped.
local function runHelper(arguments, text, done)
  local finished = false
  local task = hs.task.new(TRANSLATE, function(code, output)
    finished = true
    done(code, output)
  end, arguments)
  if not task or not task:setInput(text) then return done(1, "") end
  task:start()
  feature.limit = hs.timer.doAfter(HELPER_SECONDS, function()
    if not finished and task:isRunning() then task:terminate() end
  end)
end

local typingIn, shown

local function onMessage(message)
  shell.close()
  if message.type ~= "choose" or not shown then return end
  if message.id == "settings" then return hs.urlevent.openURL(TRANSLATION_LANGUAGES) end
  hs.pasteboard.setContents(shown.text)
  if message.id == "copy" then return shell.alert("Copied translation", 1.2) end
  shell.pasteBack(typingIn, "Copied translation · ⌘V to paste")
end

local function showResult(result)
  if result.error then return shell.alert(result.error, 1.5) end
  shown = result
  local screen = translate.screen(result)
  local height = shell.menuHeight(screen) + translate.passageHeight(screen.passage)
  shell.show("translate", shell.centered(WIDTH, height), card.html(screen), onMessage)
end

local function translateText(text)
  runHelper({ "detect" }, text, function(_, output)
    local source = translate.parseDetect(output)
    if not source then return shell.alert("Couldn't tell the selection's language", 1.5) end
    local home = translate.language((hs.host.locale.preferredLanguages() or {})[1])
    local target = translate.target(source, home)
    if not target then return shell.alert("The selection is in English already", 1.5) end
    runHelper({ source, target }, text, function(code, answer)
      showResult(translate.parseResult(code, answer))
    end)
  end)
end

function feature.selection()
  if shell.isOpen("translate") then return shell.close() end
  typingIn = shell.typingIn()
  if typingIn == nil then return shell.alert("Translating needs Accessibility for Hammerspoon", 2) end
  copySelection(function(copied)
    local text = translate.selection(copied)
    if not text then return shell.alert("Select some text first", 1.2) end
    translateText(text)
  end)
end

return feature
