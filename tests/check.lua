-- Shared helper for the Lua tests, run with luajit. Loads modules from the Hammerspoon
-- folder, so tests use them the way init.lua does, without Hammerspoon itself.

local repo = arg[1]
package.path = repo .. "/hammerspoon/.hammerspoon/?.lua;" .. package.path

local check = { failed = 0 }

function check.that(name, passed)
  print((passed and "ok   - " or "FAIL - ") .. name)
  if not passed then check.failed = check.failed + 1 end
end

function check.contains(text, piece)
  return text:find(piece, 1, true) ~= nil
end

-- The text a page shows, without its tags.
function check.visible(html)
  return (html:gsub("<[^>]*>", ""))
end

function check.finish()
  os.exit(check.failed == 0 and 0 or 1)
end

return check
