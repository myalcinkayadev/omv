-- Snippets: text you type often, kept in ~/.config/omv/snippets as name = text lines, with
-- \n for a line break and # for a comment. The palette lists them by name; picking one puts
-- its text on the clipboard and pastes it where you were typing.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local snippets = {}

local HINT_LENGTH = 40

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The file's snippets in order; a name given twice keeps its last text, in its first place.
function snippets.parse(text)
  local list, at = {}, {}
  for line in (text or ""):gmatch("[^\n]+") do
    local name, value = line:match("^([^=]*)=(.*)$")
    name = name and trim(name)
    if name and name ~= "" and not name:find("^#") then
      value = trim(value):gsub("\\n", "\n")
      if at[name] then
        list[at[name]].text = value
      else
        list[#list + 1] = { name = name, text = value }
        at[name] = #list
      end
    end
  end
  return list
end

-- One line of the text, cut short, to show beside the name.
local function hint(text)
  local line = text:gsub("%s*\n%s*", " ")
  if #line <= HINT_LENGTH then return line end
  return line:sub(1, HINT_LENGTH) .. "…"
end

function snippets.rows(list)
  local rows = {}
  for index, snippet in ipairs(list) do
    rows[#rows + 1] = { id = "snippet:" .. index, icon = "󰅍", label = snippet.name, hint = hint(snippet.text),
      keywords = "snippet", group = "Snippets" }
  end
  return rows
end

-- After a pick: "paste" when Accessibility lets omv press Cmd+V and the window you were
-- typing in has focus again, else "copy", leaving the text on the clipboard for you.
function snippets.way(accessible, before, after)
  if accessible and before ~= nil and before == after then return "paste" end
  return "copy"
end

return snippets
