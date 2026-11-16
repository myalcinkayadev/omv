-- Builds aerospace.toml from omv's defaults and the user's ~/.config/omv/aerospace.toml.
-- AeroSpace reads one file and has no include, so omv writes this one. A key the user sets
-- replaces omv's same key in the same table, whole value; a key or table omv doesn't have is
-- added; [[array]] entries such as [[on-window-detected]] are appended after omv's. omv's
-- comments stay; the user's are dropped.
--
-- It reads the TOML aerospace.toml uses, line by line: key = value, with a value going on
-- over lines while brackets are open; [table] and [[array]] headers; # comments. Brackets and
-- # inside quotes don't count. It isn't a full TOML parser.
--
-- Run: luajit aerospace_merge.lua <defaults> <user file>. Prints the built file, or the user
-- file's line it can't read on stderr and exits 1.

local merge = {}

merge.HEADER = "# Built by omv from its defaults and ~/.config/omv/aerospace.toml. Edit that file, then run omv reload."

local function trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end

-- How many brackets a line opens, net, outside quotes, ignoring a # comment.
local function depthOf(line)
  local depth, quote, i = 0, nil, 1
  while i <= #line do
    local char = line:sub(i, i)
    if quote then
      if char == "\\" and quote == '"' then i = i + 1
      elseif char == quote then quote = nil end
    elseif char == "'" or char == '"' then quote = char
    elseif char == "#" then break
    elseif char == "[" or char == "{" then depth = depth + 1
    elseif char == "]" or char == "}" then depth = depth - 1 end
    i = i + 1
  end
  return depth
end

-- A key or table name in one spelling: parts split on dots outside quotes, each trimmed and
-- unquoted, so 'alt-h' and alt-h, or gaps . inner and gaps.inner, are the same.
local function canonical(name)
  local parts, part, quote = {}, "", nil
  for char in name:gmatch(".") do
    if quote then
      if char == quote then quote = nil else part = part .. char end
    elseif char == "'" or char == '"' then quote = char
    elseif char == "." then parts[#parts + 1] = trim(part); part = ""
    else part = part .. char end
  end
  parts[#parts + 1] = trim(part)
  return table.concat(parts, ".")
end

-- The text's lines as items: { kind = "other" | "header" | "key", lines = {...}, section,
-- array (header of an [[array]]), key }. Or nil and "line N: reason".
local function read(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  if lines[#lines] == "" then lines[#lines] = nil end
  local items, section, i = {}, "", 1
  while i <= #lines do
    local line, bare = lines[i], trim(lines[i])
    if bare == "" or bare:sub(1, 1) == "#" then
      items[#items + 1] = { kind = "other", lines = { line } }
    elseif bare:sub(1, 1) == "[" then
      local array = bare:match("^%[%[%s*([^%[%]]-)%s*%]%]%s*$") or bare:match("^%[%[%s*([^%[%]]-)%s*%]%]%s*#")
      local name = array or bare:match("^%[%s*([^%[%]]-)%s*%]%s*$") or bare:match("^%[%s*([^%[%]]-)%s*%]%s*#")
      if not name or name == "" then return nil, "line " .. i .. ": a table name needs its closing ]" end
      section = array and "[[" .. canonical(name) .. "]]" or canonical(name)
      items[#items + 1] = { kind = "header", lines = { line }, section = section, array = array ~= nil, number = i }
    else
      local key, value = bare:match("^([^=]-)%s*=%s*(.*)$")
      if not key or key == "" or value == "" then return nil, "line " .. i .. ": expected key = value" end
      local item, start, depth = { kind = "key", lines = { line }, section = section, key = canonical(key), number = i }, i, depthOf(value)
      while depth > 0 do
        i = i + 1
        if i > #lines then return nil, "line " .. start .. ": the value's brackets are never closed" end
        item.lines[#item.lines + 1] = lines[i]
        depth = depth + depthOf(lines[i])
      end
      items[#items + 1] = item
    end
    i = i + 1
  end
  return items
end

-- The user's settings: keys by table, the tables in first-seen order, and the [[array]]
-- entries as lines to append.
local function settings(items)
  local keys, order, arrays, current = {}, {}, {}, nil
  for _, item in ipairs(items) do
    if item.kind == "header" and item.array then
      current = { item.lines[1] }
      arrays[#arrays + 1] = current
    elseif item.kind == "header" then
      current = nil
    elseif item.kind == "key" and current then
      for _, line in ipairs(item.lines) do current[#current + 1] = line end
    elseif item.kind == "key" then
      if not keys[item.section] then
        keys[item.section] = { list = {}, byKey = {} }
        order[#order + 1] = item.section
      end
      local table = keys[item.section]
      if not table.byKey[item.key] then table.list[#table.list + 1] = item.key end
      table.byKey[item.key] = item.lines
    end
  end
  return keys, order, arrays
end

local function append(out, lines)
  for _, line in ipairs(lines) do out[#out + 1] = line end
end

local function pathOf(section, key)
  return section == "" and key or section .. "." .. key
end

local function startsWith(text, prefix) return text:sub(1, #prefix) == prefix end

-- The user's settings written in a way that can't merge with how omv writes the same keys,
-- as "line N: reason", or nil. TOML forbids defining a table twice, so a user key must sit in
-- the same table, with the same name, as omv's.
local function clash(omvItems, userItems)
  local paths, headers, arrays = {}, { [""] = true }, {}
  for _, item in ipairs(omvItems) do
    if item.kind == "header" and item.array then arrays[#arrays + 1] = item.section:sub(3, -3)
    elseif item.kind == "header" then headers[item.section] = true
    elseif item.kind == "key" and not startsWith(item.section, "[[") then
      paths[#paths + 1] = { path = pathOf(item.section, item.key), section = item.section, key = item.key }
    end
  end
  local function advice(number, omv)
    local where = omv.section == "" and "at the top" or "under [" .. omv.section .. "]"
    return "line " .. number .. ": omv sets " .. omv.path .. " " .. where .. "; write it there as " .. omv.key .. " = …"
  end
  for _, item in ipairs(userItems) do
    if item.kind == "header" and not item.array then
      for _, array in ipairs(arrays) do
        if startsWith(item.section, array .. ".") then
          return "line " .. item.number .. ": write a [[" .. array .. "]] entry's keys under it, as if.app-id = …"
        end
      end
      if not headers[item.section] then
        for _, omv in ipairs(paths) do
          if startsWith(omv.path, item.section .. ".") then return advice(item.number, omv) end
        end
      end
    elseif item.kind == "key" and not startsWith(item.section, "[[") then
      local path = pathOf(item.section, item.key)
      for _, omv in ipairs(paths) do
        if omv.path == path and (omv.section ~= item.section or omv.key ~= item.key)
          or startsWith(omv.path, path .. ".") or startsWith(path, omv.path .. ".") then
          return advice(item.number, omv)
        end
      end
    end
  end
end

-- The built text, or nil and the user file's "line N: reason".
function merge.build(defaults, user)
  if not user or trim(user) == "" then return merge.HEADER .. "\n" .. defaults end
  local userItems, problem = read(user)
  if not userItems then return nil, problem end
  local omvItems = assert(read(defaults))
  problem = clash(omvItems, userItems)
  if problem then return nil, problem end
  local keys, order, arrays = settings(userItems)

  -- Where each of omv's tables ends: its last key, or its header when it has none. New keys
  -- go there. Top-level keys go after the last top-level key.
  local last, present = {}, { [""] = true }
  for index, item in ipairs(omvItems) do
    if item.kind == "header" and not item.array then present[item.section] = true; last[item.section] = index end
    if item.kind == "key" and not item.section:find("^%[%[") then last[item.section] = index end
  end

  local out, used = { merge.HEADER }, {}
  local function addNew(section)
    local table = keys[section]
    if not table then return end
    for _, key in ipairs(table.list) do
      if not used[section .. "\0" .. key] then append(out, table.byKey[key]) end
    end
  end

  if not last[""] then addNew("") end
  for index, item in ipairs(omvItems) do
    local mine = item.kind == "key" and keys[item.section] and keys[item.section].byKey[item.key]
    if mine and not item.section:find("^%[%[") then
      append(out, mine)
      used[item.section .. "\0" .. item.key] = true
    else
      append(out, item.lines)
    end
    if item.section and last[item.section] == index then addNew(item.section) end
  end

  for _, section in ipairs(order) do
    if not present[section] then
      out[#out + 1] = ""
      out[#out + 1] = "[" .. section .. "]"
      addNew(section)
    end
  end
  for _, entry in ipairs(arrays) do
    out[#out + 1] = ""
    append(out, entry)
  end
  return table.concat(out, "\n") .. "\n"
end

local function readFile(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

-- Run as a script, not loaded by the tests.
if arg and arg[0] and arg[0]:match("aerospace_merge%.lua$") then
  local defaults = readFile(arg[1])
  if not defaults then
    io.stderr:write("omv: can't read " .. tostring(arg[1]) .. "\n")
    os.exit(1)
  end
  local text, problem = merge.build(defaults, readFile(arg[2]))
  if not text then
    io.stderr:write("~/.config/omv/aerospace.toml " .. problem .. "\n")
    os.exit(1)
  end
  io.write(text)
end

return merge
