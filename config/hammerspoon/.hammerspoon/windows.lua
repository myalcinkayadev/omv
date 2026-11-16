-- Turns `aerospace list-windows` output into rows for the Option+Space window card.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local windows = {}

-- The title comes last, so a title that contains "|" stays whole.
windows.FORMAT = "%{window-id}|%{app-name}|%{workspace}|%{window-title}"

function windows.rows(output)
  local rows = {}
  for line in output:gmatch("[^\n]+") do
    local id, app, workspace, title = line:match("^(%d+)|([^|]*)|([^|]*)|(.*)$")
    if id then
      rows[#rows + 1] = {
        id = id,
        label = title ~= "" and title or app,
        hint = app .. " · " .. workspace,
      }
    end
  end
  return rows
end

return windows
