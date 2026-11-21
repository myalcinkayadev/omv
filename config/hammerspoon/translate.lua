-- Translating the selection (Option+Y): which language it goes to, what translate.sh's
-- answers mean, and the card that shows the translation. Has no Hammerspoon dependency, so
-- the Lua tests can run it with luajit.

local translators = require("translators")

local translate = {}

-- What text goes into when the Mac's languages don't give one.
local FALLBACK = "en"

-- "tr-TR", "zh-Hans" or "en" as the bare language: "tr", "zh", "en". English when unknown.
function translate.language(locale)
  return (locale or FALLBACK):match("^(%a+)") or FALLBACK
end

-- The Mac's preferred languages, in order, as bare languages.
function translate.languages(locales)
  local codes = {}
  for index, locale in ipairs(locales or {}) do codes[index] = translate.language(locale) end
  return codes
end

-- Text goes into the language you chose on the card, unless it's in that language already.
-- Otherwise into the first of the Mac's languages it isn't in, so on a Mac set to English
-- then Turkish, Turkish goes into English and English into Turkish. Without such a
-- language, into English; nil when it's in English already.
function translate.target(source, languages, chosen)
  local from = translate.language(source)
  if chosen and chosen ~= from then return chosen end
  for _, language in ipairs(languages) do
    if language ~= from then return language end
  end
  if from == FALLBACK then return nil end
  return FALLBACK
end

-- The saved choice: a language code such as "de" or "zh-TW"; nil for none.
function translate.parseChoice(text)
  local code = (text or ""):match("^%s*([%a%-]+)%s*$")
  return code
end

-- `translate.sh detect`: a language code, or "unknown".
function translate.parseDetect(output)
  local code = (output or ""):match("^%s*(%S+)")
  if not code or code == "unknown" then return nil end
  return code
end

-- `translate.sh <from> <to>`: "ok<TAB>From<TAB>To" and the translation on the lines after it,
-- or "missing<TAB>From<TAB>To" when a language isn't downloaded.
function translate.parseResult(code, output)
  local status, from, to, rest = (output or ""):match("^(%a+)\t([^\t\n]*)\t([^\t\n]*)\n?(.*)$")
  if code ~= 0 or not status then return { error = "Couldn't translate the selection" } end
  if status == "missing" then return { missing = true, from = from, to = to } end
  if status ~= "ok" then return { error = "Couldn't translate the selection" } end
  return { text = (rest:gsub("\n+$", "")), from = from, to = to }
end

-- A region of a language that's listed whole, such as en-GB beside en, is left out; Chinese
-- keeps its regions, which are written in another script.
local function isExtraRegion(code, listed)
  local base = code:match("^(%a+)%-")
  return base ~= nil and base ~= "zh" and listed[base] == true
end

-- `translate.sh languages <from>`: "code<TAB>Name<TAB>installed|supported" a line, as
-- { code, name, installed }: downloaded ones first, each group by name, without from.
function translate.parseLanguages(output, from)
  local lines, listed, languages = {}, {}, {}
  for code, name, state in (output or ""):gmatch("([^\t\n]+)\t([^\t\n]+)\t(%a+)") do
    lines[#lines + 1] = { code = code, name = name, installed = state == "installed" }
    listed[code] = true
  end
  for _, language in ipairs(lines) do
    if language.code ~= from and not isExtraRegion(language.code, listed) then
      languages[#languages + 1] = language
    end
  end
  table.sort(languages, function(a, b)
    if a.installed ~= b.installed then return a.installed end
    return a.name < b.name
  end)
  return languages
end

-- The card to pick a language on: automatic first, then each language. For Apple, the ones
-- on the Mac come first and the rest are marked to download; an online service has them all.
function translate.languagesScreen(languages, online)
  local rows = { { id = "lang:auto", icon = "󰁨", label = "Automatic", hint = "your Mac's languages" } }
  for _, language in ipairs(languages) do
    local row = { id = "lang:" .. language.code, icon = "󰗊", label = language.name }
    if not online then
      row.group = language.installed and "On this Mac" or "Download first"
      row.hint = not language.installed and "download" or nil
    end
    rows[#rows + 1] = row
  end
  return { prompt = "Translate into", rows = rows, compact = true }
end

-- A row picked on that card: the language's code, false for automatic, nil for another row.
function translate.picked(id)
  local code = (id or ""):match("^lang:(.+)$")
  if code == "auto" then return false end
  return code
end

-- `translate.sh download <from> <to>`: "ready" once both languages are downloaded.
function translate.downloaded(code, output)
  return code == 0 and (output or ""):match("^ready") ~= nil
end

-- The selected text without its outer spaces; nil when nothing is selected.
function translate.selection(text)
  local trimmed = (text or ""):match("^%s*(.-)%s*$")
  if trimmed == "" then return nil end
  return trimmed
end

-- A translation's card: the service, the selection and its translation, then replacing the
-- selection, copying, translating back, and another language or service. Apple without a
-- language gets a way to download it, or to another service.
function translate.screen(result)
  local service = translators.find(result.service) or translators.LIST[1]
  local prompt = result.from .. " → " .. result.to .. " · " .. service.name .. (service.online and " · online" or "")
  if result.missing then
    return {
      prompt = prompt,
      passage = result.from .. " isn't on this Mac yet. Apple translates on the Mac after a one-time download a language.",
      rows = {
        { id = "download", icon = "󰇚", label = "Download " .. result.from .. " and " .. result.to, hint = "Enter" },
        { id = "service", icon = "󰒓", label = "Another service", hint = "›" },
      },
    }
  end
  return {
    prompt = prompt,
    quote = result.original,
    passage = result.text,
    rows = {
      { id = "replace", icon = "󰬴", label = "Replace the selection", hint = "Enter" },
      { id = "copy", icon = "󰆏", label = "Copy", hint = "⌘C", key = "c" },
      { id = "back", icon = "󰓡", label = "Translate back to " .. result.from, hint = "⌘B", key = "b" },
      { id = "other", icon = "󰗊", label = "Another language", hint = "⌘L ›", key = "l" },
      { id = "service", icon = "󰒓", label = "Another service", hint = "⌘K ›", key = "k" },
    },
  }
end

-- `translate.sh names <code>...`: a language's name a line.
function translate.parseNames(output)
  local names = {}
  for name in (output or ""):gmatch("([^\n]+)") do names[#names + 1] = name end
  return names
end

-- The passage's height in points: about 56 characters a line, a line for each line break,
-- and at most 10 lines; a longer translation scrolls.
local LINE_CHARACTERS, LINE_HEIGHT, MAX_LINES, PADDING = 56, 22, 10, 20

function translate.passageHeight(text)
  local lines = 0
  for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
    lines = lines + math.max(1, math.ceil(#line / LINE_CHARACTERS))
  end
  return math.min(lines, MAX_LINES) * LINE_HEIGHT + PADDING
end

return translate
