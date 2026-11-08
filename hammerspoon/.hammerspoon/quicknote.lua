-- Quick note: one line, with the time, at the end of today's Obsidian daily note.
-- init.lua reads and writes the file. Has no Hammerspoon dependency, so the Lua tests can run it.

local quicknote = {}

-- Obsidian's daily notes plugin keeps them here, named like 2026-11-08.md.
local DAILY_FOLDER = "00 - Daily"

function quicknote.path(vault, time)
  return vault .. "/" .. DAILY_FOLDER .. "/" .. os.date("%Y-%m-%d", time) .. ".md"
end

-- "- 09:05 call Ali", or nil when there is nothing to note.
function quicknote.line(text, time)
  local flat = text:gsub("%s+", " "):match("^ ?(.-) ?$")
  if flat == "" then return nil end
  return "- " .. os.date("%H:%M", time) .. " " .. flat
end

-- The note's new content. A missing note starts as a plain file, without the template:
-- Obsidian applies templates only to notes it creates itself.
function quicknote.appended(existing, line)
  if not existing or existing == "" then return line .. "\n" end
  if existing:sub(-1) ~= "\n" then existing = existing .. "\n" end
  return existing .. line .. "\n"
end

return quicknote
