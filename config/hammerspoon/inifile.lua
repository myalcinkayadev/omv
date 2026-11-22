-- Changes ~/.config/omv/workspaces' [section] lines in place: a key's value, a section added,
-- or removed. Only the lines asked for change; comments and the rest stay as written.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local inifile = {}

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitLines(text)
  local lines = {}
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  if lines[#lines] == "" then lines[#lines] = nil end
  return lines
end

local function joined(lines)
  return #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
end

-- A section's name in one spelling: lowercase, spaces between words single.
local function nameOf(name)
  return trim(name):gsub("%s+", " "):lower()
end

-- The first and last line of section name, or nil. It ends before the next header.
local function bounds(lines, name)
  local first
  for index, line in ipairs(lines) do
    local header = trim((line:gsub("#.*$", ""))):match("^%[(.*)%]$")
    if first and header then return first, index - 1 end
    if not first and header and nameOf(header) == nameOf(name) then first = index end
  end
  return first, first and #lines or nil
end

local function keyPattern(key)
  return "^%s*" .. key:gsub("%p", "%%%0") .. "%s*="
end

-- The line with value in place of its own, keeping how it's aligned and its comment.
local function replaced(line, value)
  local head, rest = line:match("^(%s*[^=]-%s*=%s*)(.-)$")
  local comment = rest:match("(%s+#.*)$") or ""
  return head .. value .. comment
end

-- text with key in section set to value, or its line removed for nil. A section that doesn't
-- exist yet is added at the end. A key written as a comment loses its #.
function inifile.set(text, section, key, value)
  local lines = splitLines(text)
  local first, last = bounds(lines, section)
  if not first then
    if value == nil then return text end
    if #lines > 0 and trim(lines[#lines]) ~= "" then lines[#lines + 1] = "" end
    lines[#lines + 1] = "[" .. section .. "]"
    lines[#lines + 1] = key .. " = " .. tostring(value)
    return joined(lines)
  end
  local pattern = keyPattern(key)
  for index = first + 1, last do
    if lines[index]:match(pattern) then
      if value == nil then table.remove(lines, index) else lines[index] = replaced(lines[index], tostring(value)) end
      return joined(lines)
    end
  end
  if value == nil then return text end
  for index = first + 1, last do
    local commented = lines[index]:match("^%s*#%s*(.*)$")
    if commented and commented:match(pattern) then
      lines[index] = replaced(commented, tostring(value))
      return joined(lines)
    end
  end
  local after = last
  while after > first and trim(lines[after]) == "" do after = after - 1 end
  table.insert(lines, after + 1, key .. " = " .. tostring(value))
  return joined(lines)
end

-- text without section, and the lines taken out; text unchanged and nil without it. One blank
-- line stays between the sections around it.
function inifile.removeSection(text, section)
  local lines = splitLines(text)
  local first, last = bounds(lines, section)
  if not first then return text, nil end
  while last < #lines and trim(lines[last + 1]) == "" do last = last + 1 end
  local removed = {}
  for _ = first, last do removed[#removed + 1] = table.remove(lines, first) end
  while #removed > 0 and trim(removed[#removed]) == "" do removed[#removed] = nil end
  return joined(lines), joined(removed)
end

function inifile.hasSection(text, section)
  return bounds(splitLines(text), section) ~= nil
end

-- Whether section exists with nothing under its header, not even a comment.
function inifile.isEmpty(text, section)
  local lines = splitLines(text)
  local first, last = bounds(lines, section)
  if not first then return false end
  for index = first + 1, last do
    if trim(lines[index]) ~= "" then return false end
  end
  return true
end

return inifile
