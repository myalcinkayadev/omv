-- Translating the selection (Option+Y): which language it goes to, what translate.sh's
-- answers mean, and the card that shows the translation. Has no Hammerspoon dependency, so
-- the Lua tests can run it with luajit.

local translate = {}

-- What the Mac's own language is translated into, and what anything already in it becomes.
local FALLBACK = "en"

-- "tr-TR", "zh-Hans" or "en" as the bare language: "tr", "zh", "en". English when unknown.
function translate.language(locale)
  return (locale or FALLBACK):match("^(%a+)") or FALLBACK
end

-- Text goes into the Mac's language, or into English when it's in the Mac's language
-- already. nil when that's English too: there's nothing to translate it into.
function translate.target(source, home)
  if translate.language(source) ~= home then return home end
  if home == FALLBACK then return nil end
  return FALLBACK
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

-- The selected text without its outer spaces; nil when nothing is selected.
function translate.selection(text)
  local trimmed = (text or ""):match("^%s*(.-)%s*$")
  if trimmed == "" then return nil end
  return trimmed
end

-- A translation's card: the text, then replacing the selection with it or copying it. A
-- language that isn't downloaded gets a way to Translation Languages instead.
function translate.screen(result)
  local languages = result.from .. " → " .. result.to
  if result.missing then
    return {
      prompt = languages,
      passage = "Download " .. result.from .. " and " .. result.to .. " in Translation Languages, then try again.",
      rows = { { id = "settings", icon = "󰒓", label = "Open Translation Languages", hint = "Enter" } },
    }
  end
  return {
    prompt = languages,
    passage = result.text,
    rows = {
      { id = "replace", icon = "󰬴", label = "Replace the selection", hint = "Enter" },
      { id = "copy", icon = "󰆏", label = "Copy" },
    },
  }
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
