-- What a clicked notification opens. hs.notify.new keeps a function it's given in its
-- registry until Hammerspoon reloads, so one closure per notification stayed for good. A
-- feature instead registers one function under a fixed tag and keeps each notification's
-- target here, found again by its title and text. Only the newest LIMIT are kept: a click on
-- an older one does nothing.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local notices = {}

notices.LIMIT = 20

-- A notification's title and text, which the clicked notification gives back.
function notices.key(title, text)
  return tostring(title or "") .. "\n" .. tostring(text or "")
end

function notices.new(limit)
  return { limit = limit or notices.LIMIT, order = {}, targets = {} }
end

local function forget(book, key)
  for index, kept in ipairs(book.order) do
    if kept == key then return table.remove(book.order, index) end
  end
end

-- Keeps target for key as the newest. The same key again replaces its target, so two
-- notifications that read the same open the latest one's.
function notices.add(book, key, target)
  forget(book, key)
  book.order[#book.order + 1] = key
  book.targets[key] = target
  while #book.order > book.limit do
    book.targets[table.remove(book.order, 1)] = nil
  end
end

-- The target kept for key, or nil once it has been dropped.
function notices.find(book, key)
  return book.targets[key]
end

return notices
