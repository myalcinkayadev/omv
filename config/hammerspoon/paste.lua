-- Pasting for you, after a snippet or a clipboard history item is picked: the text goes on
-- the clipboard, then Cmd+V once the window you were typing in has focus again. Both need
-- Accessibility, and without it hs.window's calls stall, so then nothing looks for windows
-- and the text is only copied. shell.pasteBack does the waiting and the keystroke.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local paste = {}

function paste.canLook(accessible)
  return accessible == true
end

-- "paste" when Accessibility lets omv press Cmd+V and the window you were typing in has
-- focus again, else "copy", leaving the text on the clipboard for you.
function paste.way(accessible, before, after)
  if accessible and before ~= nil and before == after then return "paste" end
  return "copy"
end

return paste
