-- The recent Claude Code sessions and their project folders, read from ~/.claude/projects.
-- Shared by the Agents card and the dev layout. Starts nothing when it loads, so the dev
-- layout can list projects while the claude flag keeps the Agents card off.

local shell = require("shell")
local agents = require("agents")

local claudeprojects = {}

-- Enough recent sessions to fill the project list, without reading every one.
local RECENT_SESSIONS = 60
-- A session's folder is near the start of its file, so only that much is read.
local SESSION_HEAD_BYTES = 65536

-- Hands done the recent Claude Code sessions, newest first, as { id, path, cwd, modified }.
-- The id is the file's name, which claude --resume takes. ls runs in the background: over
-- many projects it takes long enough to freeze the cards.
function claudeprojects.recentSessions(done)
  shell.execute("/bin/ls -t " .. shell.HOME .. "/.claude/projects/*/*.jsonl 2>/dev/null | /usr/bin/head -n " .. RECENT_SESSIONS, function(listing)
    local sessions = {}
    for path in listing:gmatch("[^\n]+") do
      local cwd = agents.sessionCwd(shell.readText(path, SESSION_HEAD_BYTES))
      if cwd then
        sessions[#sessions + 1] = { id = path:match("([^/]+)%.jsonl$"), path = path, cwd = cwd,
          modified = hs.fs.attributes(path, "modification") or 0 }
      end
    end
    done(sessions)
  end)
end

function claudeprojects.folderExists(path)
  return hs.fs.attributes(path, "mode") == "directory"
end

-- Hands done the folders of recent Claude Code sessions that still exist, the most recent first.
function claudeprojects.projects(done)
  claudeprojects.recentSessions(function(sessions)
    done(agents.projects(sessions, claudeprojects.folderExists))
  end)
end

return claudeprojects
