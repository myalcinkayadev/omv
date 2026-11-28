-- One matcher for what's typed in the palette and what's said to Right Command: the same
-- words, a prefix, one letter off, or the same sound, so "said" finds Zed and "ghasti" finds
-- Ghostty. A typo and a word heard wrong are the same problem.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local soundmatch = {}

-- WHOLE is the whole label, such as Zed for "zed", above EXACT, one of its words, as in Open Zed.
soundmatch.WHOLE, soundmatch.EXACT, soundmatch.PREFIX, soundmatch.SPELLING, soundmatch.SOUND = 5, 4, 3, 2, 1
-- One letter off counts only from this long, so short words stay themselves.
soundmatch.NEAR_LENGTH = 5
-- A sound match needs this many letters said, so "sd" isn't Zed.
local SOUND_LENGTH = 3

function soundmatch.normal(text)
  return (tostring(text or ""):lower():gsub("[^%w]", ""))
end

-- Whether a and b are at most one letter added, dropped or changed apart.
function soundmatch.oneEdit(a, b)
  if math.abs(#a - #b) > 1 then return false end
  local i, j, edits = 1, 1, 0
  while i <= #a and j <= #b do
    if a:sub(i, i) == b:sub(j, j) then
      i, j = i + 1, j + 1
    else
      edits = edits + 1
      if edits > 1 then return false end
      if #a > #b then i = i + 1
      elseif #b > #a then j = j + 1
      else i, j = i + 1, j + 1 end
    end
  end
  return edits + (#a - i + 1) + (#b - j + 1) <= 1
end

local VOWELS = { a = true, e = true, i = true, o = true, u = true, y = true }

-- How text sounds, a simplified Metaphone: letters that sound alike become one, vowels after
-- the first letter and h go, and a letter said twice counts once. "said" and "Zed" are both st.
function soundmatch.key(text)
  local word = tostring(text or ""):lower():gsub("[^%a]", "")
  word = word:gsub("ph", "f"):gsub("ck", "k"):gsub("gh", "k"):gsub("x", "ks"):gsub("q", "k")
  word = word:gsub("c([eiy])", "s%1"):gsub("c", "k"):gsub("z", "s"):gsub("d", "t")
  local out, last = {}, nil
  for index = 1, #word do
    local letter = word:sub(index, index)
    local keep = index == 1 or not (VOWELS[letter] or letter == "h")
    if keep and letter ~= last then out[#out + 1] = letter end
    last = letter
  end
  return table.concat(out)
end

-- The verbs omv's commands start with: words, not names, so they never match by sound, and
-- "said" isn't "Set a reminder".
local VERBS = { set = true, open = true, show = true, toggle = true, start = true, stop = true, new = true, go = true,
  turn = true, take = true, copy = true, paste = true, move = true, close = true, quit = true }

-- The label's words, and the label as one word, as normal text.
local function parts(label)
  local list = { soundmatch.normal(label) }
  for word in tostring(label):gmatch("[%w]+") do list[#list + 1] = soundmatch.normal(word) end
  return list
end

-- How well query matches label: WHOLE, EXACT, PREFIX, SPELLING, SOUND, or 0, the best over
-- the label's words and the label as a whole. A match on the whole label counts half a point
-- more than the same on one word, so "said" is Zed before Open Zed.
function soundmatch.score(query, label)
  local said = soundmatch.normal(query)
  if said == "" then return 0 end
  if soundmatch.normal(label) == said then return soundmatch.WHOLE end
  local saidKey = #said >= SOUND_LENGTH and soundmatch.key(query) or nil
  local best = 0
  for index, part in ipairs(parts(label)) do
    local whole = index == 1 and 0.5 or 0
    if part == said then return soundmatch.EXACT end
    if part:sub(1, #said) == said then best = math.max(best, soundmatch.PREFIX + whole)
    elseif #part >= soundmatch.NEAR_LENGTH and soundmatch.oneEdit(said, part) then best = math.max(best, soundmatch.SPELLING + whole)
    elseif saidKey and #saidKey >= 2 and not VERBS[part] and soundmatch.key(part) == saidKey then best = math.max(best, soundmatch.SOUND + whole) end
  end
  return best
end

-- The items whose label matches query, best first, each with .score; and the verdict: strong
-- for one clear best (a spelling match or better, or the only sound match), tied when two or
-- more share the best score, weak for none.
function soundmatch.rank(query, items)
  local ranked = {}
  for index, item in ipairs(items or {}) do
    local score = soundmatch.score(query, item.label)
    if score > 0 then ranked[#ranked + 1] = { item = item, score = score, order = index } end
  end
  table.sort(ranked, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.order < b.order
  end)
  local list = {}
  for _, entry in ipairs(ranked) do
    entry.item.score = entry.score
    list[#list + 1] = entry.item
  end
  if #list == 0 then return list, "weak" end
  if list[2] and list[2].score == list[1].score then return list, "tied" end
  return list, "strong"
end

return soundmatch
