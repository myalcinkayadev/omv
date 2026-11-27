-- World clocks for the calendar card, kept in ~/.config/omv/clocks as name = time zone lines,
-- such as NYC = America/New_York, with # for a comment. This module reads the file and draws
-- the rows; the times themselves are worked out in the card's page by clocks.js.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local card = require("card")
local snippets = require("snippets")

local clocks = {}

-- More would push the card past a laptop screen's height.
local MAX_CLOCKS = 8
local PADDING = 10
local LINE_HEIGHT = 22

clocks.SCRIPT = card.readBeside("clocks.js")

-- The file's clocks in order, each { name, zone }. The file is name = text lines like
-- snippets', so their reader is reused; a line without a zone is left out.
function clocks.parse(text)
  local list = {}
  for _, entry in ipairs(snippets.parse(text)) do
    if entry.text ~= "" and #list < MAX_CLOCKS then list[#list + 1] = { name = entry.name, zone = entry.text } end
  end
  return list
end

-- What the section adds to the card's height: its title and one line per clock.
function clocks.height(list)
  if not list or #list == 0 then return 0 end
  return PADDING + (#list + 1) * LINE_HEIGHT
end

-- The section's HTML, with each zone for clocks.js to fill in; empty without clocks.
function clocks.html(list)
  if not list or #list == 0 then return "" end
  local rows = { "<div class=clocks><div class=label>Clocks</div>" }
  for _, clock in ipairs(list) do
    rows[#rows + 1] = '<div class=clock data-zone="' .. card.escape(clock.zone) .. '">'
      .. "<span class=name>" .. card.escape(clock.name) .. "</span>"
      .. "<span class=time></span><span class=diff></span></div>"
  end
  rows[#rows + 1] = "</div><script>" .. clocks.SCRIPT .. "</script>"
  return table.concat(rows)
end

return clocks
