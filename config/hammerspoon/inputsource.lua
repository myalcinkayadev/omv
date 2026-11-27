-- Input source (the bar item): the current keyboard input source as a short tag, such as
-- TR or US, and the source a click switches to. Sources are macOS's ids, such as
-- com.apple.keylayout.Turkish-QWERTY-PC, in the order Hammerspoon lists them.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local inputsource = {}

-- Layouts whose first two letters aren't the tag people know, by the last part of their id.
-- Any other id is tagged by its first two letters, which reads right for most layouts.
local KNOWN_TAGS = {
  ["US"] = "US", ["ABC"] = "US", ["ABC-Extended"] = "US", ["USInternational-PC"] = "US",
  ["Turkish"] = "TR", ["Turkish-QWERTY"] = "TR", ["Turkish-QWERTY-PC"] = "TR", ["Turkish-Standard"] = "TR",
  ["British"] = "GB", ["British-PC"] = "GB", ["German"] = "DE", ["Spanish"] = "ES", ["Spanish-ISO"] = "ES",
  ["Ukrainian"] = "UA",
}

local function lastPart(id)
  return id:match("([^.]+)$")
end

-- The short tag for a source id, or nil for one without letters to show.
function inputsource.tag(id)
  if not id or id == "" then return nil end
  local name = lastPart(id)
  if not name then return nil end
  if KNOWN_TAGS[name] then return KNOWN_TAGS[name] end
  local letters = name:gsub("%A", ""):sub(1, 2)
  if letters == "" then return nil end
  return letters:upper()
end

local function indexOf(sources, id)
  for index, source in ipairs(sources) do
    if source == id then return index end
  end
  return nil
end

-- The source after current, wrapping to the first; the first when current isn't listed.
-- nil with fewer than two sources, since there's nothing to switch to.
function inputsource.nextSource(sources, current)
  if #sources < 2 then return nil end
  local index = indexOf(sources, current)
  if not index then return sources[1] end
  return sources[index % #sources + 1]
end

-- The item's SketchyBar properties: hidden with one source, as there's no choice to show.
function inputsource.barProperties(sources, current)
  local tag = inputsource.tag(current)
  if #sources < 2 or not tag then return { "drawing=off" } end
  return { "drawing=on", "label=" .. tag }
end

return inputsource
