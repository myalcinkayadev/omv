-- Translate the selection (Option+Y): copies what's selected, finds its language on the Mac,
-- and translates it into the first of the Mac's languages it isn't in already, else into
-- English, or into the language picked on the card, kept until Automatic is picked.
-- The first time, a card asks which service translates: Apple on the Mac (translate.sh),
-- DeepL online with a key kept in the Keychain, or Claude Code online. The result card
-- pastes the translation over the selection, copies it, translates it back, or tries
-- another language or service. The clipboard is put back after the copy. Copying and
-- pasting need Accessibility.

local shell = require("shell")
local card = require("card")
local translate = require("translate")
local translators = require("translators")

local feature = {}

local TRANSLATE = hs.configdir .. "/translate.sh"
-- The language and the service you picked on the card.
local LANGUAGE_FILE = shell.STATE_DIR .. "/translate-language"
local SERVICE_FILE = shell.STATE_DIR .. "/translate-service"
local SECURITY = "/usr/bin/security"
local KEYCHAIN = { "-s", "omv-deepl", "-a", "omv" }
local DEEPL_KEYS_PAGE = "https://www.deepl.com/pro-api"
local CLAUDE_PATHS = { shell.HOME .. "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude" }
local COPY_WAIT_SECONDS = 0.5
local HELPER_SECONDS = 10
local CLAUDE_SECONDS = 45
-- Long enough to download two languages on a slow connection.
local DOWNLOAD_SECONDS = 15 * 60
local WIDTH = 520
local PICKER_WIDTH = 420
local QUOTE_HEIGHT = 24

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

-- Runs a program with input on stdin; one still running after seconds is stopped.
local function runTask(program, arguments, input, done, seconds)
  local finished = false
  local task = hs.task.new(program, function(code, output)
    finished = true
    done(code, output)
  end, arguments)
  if not task or (input and not task:setInput(input)) then return done(1, "") end
  task:start()
  feature.limit = hs.timer.doAfter(seconds or HELPER_SECONDS, function()
    if not finished and task:isRunning() then task:terminate() end
  end)
end

local function runHelper(arguments, input, done, seconds)
  runTask(TRANSLATE, arguments, input or "", done, seconds)
end

local function readState(path, parse)
  return parse(shell.readText(path))
end

local function saveState(path, value)
  if not value then return os.remove(path) end
  hs.fs.mkdir(shell.STATE_DIR)
  local file = io.open(path, "w")
  if not file then return end
  file:write(value, "\n")
  file:close()
end

-- The DeepL key from the Keychain, or nil.
local function readDeeplKey(done)
  local arguments = { "find-generic-password", table.unpack(KEYCHAIN) }
  arguments[#arguments + 1] = "-w"
  runTask(SECURITY, arguments, nil, function(code, output)
    done(code == 0 and translators.deeplKey(output) or nil)
  end)
end

local function saveDeeplKey(key, done)
  local arguments = { "add-generic-password", "-U", table.unpack(KEYCHAIN) }
  arguments[#arguments + 1] = "-w"
  arguments[#arguments + 1] = key
  runTask(SECURITY, arguments, nil, function(code) done(code == 0) end)
end

local function claudePath()
  for _, path in ipairs(CLAUDE_PATHS) do
    if hs.fs.attributes(path) then return path end
  end
  return nil
end

-- The window typing was in; the text being translated, its language and the target, with
-- their names; and the result on the card.
local typingIn, selected, shown
local showResult, showLanguages, showServices, showKeyCard, translateWith

-- Each service translates the selected text and hands done a result: { text },
-- { missing = true } for Apple without a language, { needsKey = true } for DeepL without a
-- key, or { error }.
local VIA = {}

function VIA.apple(done)
  runHelper({ selected.source, selected.target }, selected.text, function(code, output)
    done(translate.parseResult(code, output))
  end)
end

function VIA.deepl(done)
  readDeeplKey(function(key)
    if not key then return done({ needsKey = true }) end
    local request = translators.deeplRequest(key, selected.text, selected.source, selected.target)
    hs.http.asyncPost(request.url, request.body, request.headers, function(status, body)
      local decoded, answer = pcall(hs.json.decode, body or "")
      local text = status == 200 and decoded and translators.parseDeepl(answer)
      if text then return done({ text = text }) end
      if status == 403 then return done({ error = "DeepL refused the key" }) end
      done({ error = "DeepL didn't translate it" })
    end)
  end)
end

function VIA.claude(done)
  local path = claudePath()
  if not path then return done({ error = "Claude Code isn't installed" }) end
  runTask(path, translators.claudeArguments(selected.toName), selected.text, function(code, output)
    local text = translators.parseClaude(code, output)
    done(text and { text = text } or { error = "Claude didn't translate it" })
  end, CLAUDE_SECONDS)
end

translateWith = function(service)
  selected.service = service
  local about = translators.find(service)
  if about.online then shell.alert("Translating with " .. about.name .. "…", 1) end
  VIA[service](function(result)
    if result.needsKey then return showKeyCard() end
    if result.error then return shell.alert(result.error, 2) end
    result.from, result.to, result.service, result.original = selected.fromName, selected.toName, service, selected.text
    showResult(result)
  end)
end

-- Reads the names of the selected languages, then translates with service; with none
-- picked yet, the first-use card asks for one.
local showServiceCard

local function translateNamed(service)
  runHelper({ "names", selected.source, selected.target }, nil, function(_, output)
    local names = translate.parseNames(output)
    selected.fromName, selected.toName = names[1] or selected.source, names[2] or selected.target
    if not service then return showServiceCard(translators.chooserScreen()) end
    translateWith(service)
  end)
end

-- macOS's own sheet asks to download the two languages; once they're in, the selection is
-- translated again.
local function downloadLanguages()
  runHelper({ "download", selected.source, selected.target }, nil, function(code, output)
    if not translate.downloaded(code, output) then return shell.alert("The languages weren't downloaded", 1.5) end
    translateWith("apple")
  end, DOWNLOAD_SECONDS)
end

-- The translation becomes the text, translated back into the selection's language.
local function translateBack()
  selected = {
    text = shown.text, source = selected.target, target = selected.source,
    fromName = selected.toName, toName = selected.fromName,
  }
  translateWith(shown.service)
end

local function onResultMessage(message)
  shell.close()
  if message.type ~= "choose" or not shown then return end
  if message.id == "download" then return downloadLanguages() end
  if message.id == "other" then return showLanguages() end
  if message.id == "service" then return showServices() end
  if message.id == "back" then return translateBack() end
  hs.pasteboard.setContents(shown.text)
  if message.id == "copy" then return shell.alert("Copied translation", 1.2) end
  shell.pasteBack(typingIn, "Copied translation · ⌘V to paste")
end

showResult = function(result)
  shown = result
  local screen = translate.screen(result)
  local height = shell.menuHeight(screen) + translate.passageHeight(screen.passage)
    + (screen.quote and QUOTE_HEIGHT or 0)
  shell.show("translate", shell.centered(WIDTH, height), card.html(screen), onResultMessage)
end

local function onLanguageMessage(message)
  shell.close()
  if message.type == "back" and shown then return showResult(shown) end
  if message.type ~= "choose" then return end
  local picked = translate.picked(message.id)
  if picked == nil then return end
  saveState(LANGUAGE_FILE, picked or nil)
  local target = translate.target(selected.source, translate.languages(hs.host.locale.preferredLanguages()), picked or nil)
  if not target then return shell.alert("The selection is in English already", 1.5) end
  selected.target = target
  translateNamed(selected.service)
end

showLanguages = function()
  runHelper({ "languages", selected.source }, nil, function(code, output)
    local languages = translate.parseLanguages(output, selected.source)
    if code ~= 0 or #languages == 0 then return shell.alert("Couldn't list the languages", 1.5) end
    local screen = translate.languagesScreen(languages, translators.find(selected.service).online)
    shell.show("translate", shell.centered(PICKER_WIDTH, shell.listHeight(#screen.rows, shell.LIST_VISIBLE_ROWS)),
      card.html(screen), onLanguageMessage)
  end)
end

-- A service picked on the first-use card or the card to switch: kept from now on.
local function onServiceMessage(message)
  shell.close()
  if message.type == "back" and shown then return showResult(shown) end
  if message.type ~= "choose" then return end
  local service = translators.picked(message.id)
  if not service then return end
  saveState(SERVICE_FILE, service)
  translateWith(service)
end

showServiceCard = function(screen)
  shell.show("translate", shell.centered(WIDTH, shell.menuHeight(screen)), card.html(screen), onServiceMessage)
end

showServices = function()
  readDeeplKey(function(key)
    showServiceCard(translators.servicesScreen(selected.service, key ~= nil))
  end)
end

-- DeepL without a key: get one, copy it, then use the copied key, which goes to the Keychain.
local function onKeyMessage(message)
  shell.close()
  if message.type == "back" then return showServices() end
  if message.type ~= "choose" then return end
  if message.id == "deepl:get" then return shell.open({ DEEPL_KEYS_PAGE })() end
  if message.id ~= "deepl:use" then return end
  local key = translators.deeplKey(hs.pasteboard.getContents())
  if not key then
    shell.alert("Copy your DeepL key first", 1.5)
    return showKeyCard()
  end
  saveDeeplKey(key, function(saved)
    if not saved then return shell.alert("Couldn't keep the key in the Keychain", 2) end
    saveState(SERVICE_FILE, "deepl")
    translateWith("deepl")
  end)
end

showKeyCard = function()
  local screen = translators.keyScreen()
  local height = shell.menuHeight(screen) + translate.passageHeight(screen.passage)
  shell.show("translate", shell.centered(WIDTH, height), card.html(screen), onKeyMessage)
end

local function translateText(text)
  runHelper({ "detect" }, text, function(_, output)
    local source = translate.parseDetect(output)
    if not source then return shell.alert("Couldn't tell the selection's language", 1.5) end
    local chosen = readState(LANGUAGE_FILE, translate.parseChoice)
    local target = translate.target(source, translate.languages(hs.host.locale.preferredLanguages()), chosen)
    if not target then return shell.alert("The selection is in English already", 1.5) end
    selected, shown = { text = text, source = source, target = target }, nil
    translateNamed(readState(SERVICE_FILE, translators.parseChoice))
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
