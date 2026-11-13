-- The agent grid: Claude Code agents in one tmux session, a pane each, so they keep running
-- after the window closes. Builds the tmux commands, reads which grids run, and finds the
-- pane and attached terminal of a waiting agent.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local agents = require("agents")

local grid = {}

-- tmux refuses "." and ":" in a session name, so anything but letters, digits, - and _ goes.
function grid.sessionName(folder)
  local name = (folder:match("([^/]+)/*$") or "grid"):gsub("[^%w_%-]", "-")
  return "omv-" .. name
end

-- tmux arguments, one list each: the session with the first agent, a pane per further agent,
-- side by side, or two over two for four, with mouse scrolling on and a plain status bar.
function grid.startCommands(session, folders, claudeIn)
  local commands = {}
  for index, folder in ipairs(folders) do
    local run = claudeIn .. " " .. agents.shellQuote(folder)
    if index == 1 then
      commands[1] = { "new-session", "-d", "-s", session, "-c", folder, run }
    else
      commands[#commands + 1] = { "split-window", "-t", session, "-c", folder, run }
    end
  end
  commands[#commands + 1] = { "select-layout", "-t", session, #folders == 4 and "tiled" or "even-horizontal" }
  commands[#commands + 1] = { "set-option", "-t", session, "mouse", "on" }
  commands[#commands + 1] = { "set-option", "-t", session, "status-style", "bg=default,fg=colour244" }
  return commands
end

function grid.attachCommand(session, tmux)
  return tmux .. " attach -t " .. session
end

-- `tmux list-sessions -F '#{session_name}'`: the names, as a set.
function grid.running(output)
  local names = {}
  for name in (output or ""):gmatch("[^\n]+") do names[name] = true end
  return names
end

-- The project rows, with "running" on those whose grid is up.
function grid.projectRows(rows, running)
  for _, row in ipairs(rows) do
    if running[grid.sessionName(row.id)] then row.hint = "running" end
  end
  return rows
end

function grid.runningChoices()
  return {
    { id = "reattach", icon = "󰆍", label = "Reattach" },
    { id = "end", icon = "󰅖", label = "End all agents", hint = "worktrees stay" },
  }
end

-- Ending stops every agent, so one stray Enter mustn't do it.
function grid.confirmEnd(project)
  return {
    prompt = "End " .. project .. "'s agents?",
    selected = 1,
    rows = {
      { id = "cancel", icon = "󰅖", label = "Cancel" },
      { id = "end.confirmed", icon = "󰅖", label = "End all agents" },
    },
  }
end

-- `tmux list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}'`: the pane
-- whose terminal is tty, as a tmux target; nil when tty isn't in tmux.
function grid.paneFor(output, tty)
  for paneTty, target in (output or ""):gmatch("(%S+) (%S+)") do
    if paneTty == tty then return target end
  end
  return nil
end

-- `tmux list-clients -F '#{client_tty} #{session_name}'`: the terminal attached to the
-- target's session, which is the Ghostty window to bring forward.
function grid.clientFor(output, target)
  local session = target:match("^([^:]+)")
  for clientTty, name in (output or ""):gmatch("(%S+) (%S+)") do
    if name == session then return clientTty end
  end
  return nil
end

return grid
