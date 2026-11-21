-- The services that translate the selection (Option+Y): Apple on the Mac, and DeepL and
-- Claude online. Google's free web address isn't one: it refuses requests that aren't from
-- a browser. What each is asked and what its answer means, and the cards to pick
-- one. Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local translators = {}

translators.LIST = {
  { id = "apple", name = "Apple", summary = "on this Mac · private", online = false },
  { id = "deepl", name = "DeepL", summary = "online · needs a free key", online = true },
  { id = "claude", name = "Claude", summary = "online · uses your Claude plan", online = true },
}

local ICONS = { apple = "󰇄", deepl = "󰌆", claude = "󰚩" }

function translators.find(id)
  for _, service in ipairs(translators.LIST) do
    if service.id == id then return service end
  end
  return nil
end

-- The saved service: its id, or nil for none or one omv doesn't know.
function translators.parseChoice(text)
  local id = (text or ""):match("^%s*(%a+)%s*$")
  return translators.find(id) and id or nil
end

-- The card shown on first use: each service and what it means for the text.
function translators.chooserScreen()
  local rows = {}
  for index, service in ipairs(translators.LIST) do
    local hint = service.summary
    if index == 1 then hint = hint .. " · recommended" end
    rows[index] = { id = "service:" .. service.id, icon = ICONS[service.id], label = service.name, hint = hint }
  end
  return { prompt = "How should omv translate?", rows = rows, selected = 1 }
end

-- The card to switch service: the one in use marked, the next one selected.
function translators.servicesScreen(current, hasDeeplKey)
  local rows, selected = {}, 1
  for index, service in ipairs(translators.LIST) do
    local hint = service.online and "online" or "on this Mac"
    if service.id == "deepl" and not hasDeeplKey then hint = "add a free key ›" end
    if service.id == current then
      hint = "current"
      selected = index % #translators.LIST + 1
    end
    rows[index] = { id = "service:" .. service.id, icon = ICONS[service.id], label = service.name, hint = hint }
  end
  return { prompt = "Translate with", rows = rows, selected = selected }
end

-- A row picked on those cards: the service's id, nil for another row.
function translators.picked(id)
  local service = (id or ""):match("^service:(%a+)$")
  return translators.find(service) and service or nil
end

-- Percent-encodes text for a URL or a form, byte by byte, so UTF-8 survives.
local function escape(text)
  return (text:gsub("[^%w%-%._~]", function(character)
    return string.format("%%%02X", character:byte())
  end))
end

-- DeepL wants a variant for English and Portuguese, and the script for Chinese.
local DEEPL_TARGETS = { en = "EN-US", pt = "PT-BR", zh = "ZH-HANS" }

-- A request to DeepL: a free key, ending in ":fx", goes to the free plan's address.
function translators.deeplRequest(key, text, source, target)
  local host = key:match(":fx$") and "api-free.deepl.com" or "api.deepl.com"
  local base = target:match("^(%a+)")
  return {
    url = "https://" .. host .. "/v2/translate",
    headers = {
      Authorization = "DeepL-Auth-Key " .. key,
      ["Content-Type"] = "application/x-www-form-urlencoded",
    },
    body = "text=" .. escape(text) .. "&source_lang=" .. source:match("^(%a+)"):upper()
      .. "&target_lang=" .. (DEEPL_TARGETS[base] or base:upper()),
  }
end

-- DeepL's answer, decoded from JSON.
function translators.parseDeepl(answer)
  local first = type(answer) == "table" and type(answer.translations) == "table" and answer.translations[1]
  if type(first) ~= "table" or type(first.text) ~= "string" then return nil end
  return first.text
end

-- A DeepL key copied to the clipboard: letters, digits and dashes, maybe ending ":fx".
function translators.deeplKey(text)
  local key = (text or ""):match("^%s*(%S+)%s*$")
  if not key or #key < 20 then return nil end
  if key:match("^[%w%-]+$") or key:match("^[%w%-]+:fx$") then return key end
  return nil
end

-- The card for DeepL without a key: getting one, then using the one copied.
function translators.keyScreen()
  return {
    prompt = "Add a DeepL key",
    passage = "The free plan covers 500,000 characters a month. Get a key, copy it, then pick Use the copied key. It's kept in the macOS Keychain, never in a file.",
    rows = {
      { id = "deepl:get", icon = "󰖟", label = "Get a free key", hint = "deepl.com" },
      { id = "deepl:use", icon = "󰆒", label = "Use the copied key", hint = "Enter" },
    },
    selected = 2,
  }
end

-- `claude -p` with the instruction, on Sonnet, as quick as Haiku here and with fewer slips;
-- the text to translate comes on stdin.
function translators.claudeArguments(targetName)
  return {
    "-p",
    "Translate the text on stdin into " .. targetName .. ". Keep its tone and formatting. "
      .. "Reply with only the translation: no quotes, notes or explanations.",
    "--model", "sonnet",
  }
end

-- Claude's answer: the translation, nil when it failed or said nothing.
function translators.parseClaude(code, output)
  if code ~= 0 then return nil end
  local text = (output or ""):match("^%s*(.-)%s*$")
  if text == "" then return nil end
  return text
end

return translators
