-- Send to agent (Option+P): the rows that send the selection, the clipboard or a screenshot
-- to an agent waiting for its next prompt, and the text that is pasted there.
-- Only sessions that are done are offered: one that asks for approval could take the paste
-- as its answer, and one that works may start asking at any moment. Enter is never pressed,
-- so what lands in the prompt waits for you to read it and send it.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local sendto = {}

sendto.SHOT_DIR = (os.getenv("HOME") or "") .. "/.local/state/omv/agent-shots"
-- Screenshots older than this are removed when the next one is taken.
sendto.SHOT_SECONDS = 24 * 60 * 60

-- The text as it may be pasted into a terminal, or nil when nothing is left. Control
-- characters other than tab and newline are dropped: an escape could end the terminal's
-- bracketed paste early and run the rest as typed keys. Trailing newlines go too, so a
-- paste can never send itself.
function sendto.clean(text)
  if type(text) ~= "string" then return nil end
  local cleaned = text:gsub("\r\n?", "\n"):gsub("[%z\1-\8\11-\31\127]", ""):gsub("%s+$", "")
  if cleaned:match("^%s*$") then return nil end
  return cleaned
end

-- Characters, not bytes: a UTF-8 continuation byte doesn't start one.
local function characters(text)
  return select(2, text:gsub("[^\128-\191]", ""))
end

local function plainTty(tty)
  return type(tty) == "string" and tty:match("^/dev/ttys%d+$") ~= nil
end

-- sessionRows are claudewait.rows'. source is "Selection" or "Clipboard", or nil without
-- text. One row per done session for the text, then one per session for a screenshot.
function sendto.rows(sessionRows, text, source)
  local targets = {}
  for _, row in ipairs(sessionRows or {}) do
    if row.state == "done" and plainTty(row.id) then targets[#targets + 1] = row end
  end
  local rows = {}
  if text and source then
    local count = characters(text)
    for _, target in ipairs(targets) do
      rows[#rows + 1] = { id = "text:" .. target.id, label = source .. " → " .. target.label,
        hint = count .. (count == 1 and " character" or " characters") }
    end
  end
  for _, target in ipairs(targets) do
    rows[#rows + 1] = { id = "shot:" .. target.id, label = "Screenshot → " .. target.label, hint = "Pick a region" }
  end
  return rows
end

-- What a row sends, "text" or "shot", and the terminal it goes to; nil for an unknown row.
function sendto.parseId(id)
  local kind, tty = tostring(id or ""):match("^(%a+):(.+)$")
  if (kind ~= "text" and kind ~= "shot") or not plainTty(tty) then return nil end
  return kind, tty
end

-- A screenshot's path, with no spaces, so the agent reads it as one path.
function sendto.shotPath(time)
  return sendto.SHOT_DIR .. "/omv-shot-" .. os.date("%Y%m%d-%H%M%S", time) .. ".png"
end

-- Whether a file in the screenshot folder is an old screenshot of ours to remove.
function sendto.isOldShot(name, modified, now)
  return name:match("^omv%-shot%-%d+%-%d+%.png$") ~= nil and now - modified > sendto.SHOT_SECONDS
end

return sendto
