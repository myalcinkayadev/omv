-- The checks on your own open pull requests, as the bar's github_ci.sh saved them: one line
-- per pull request, "<state>\t<url>\t<repo>#<n>\t<title>". Turns them into the card's rows,
-- failing first, and into the notices for those that went from failing to passing.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local ci = {}

ci.STATE = (os.getenv("HOME") or "") .. "/.local/state/omv/github-ci"
ci.PASSED = (os.getenv("HOME") or "") .. "/.local/state/omv/github-ci-passed"

-- GitHub's rollup states, as the card names them, in the order the card lists them.
local STATES = {
  FAILURE = { rank = 1, word = "failing" },
  ERROR = { rank = 1, word = "failing" },
  PENDING = { rank = 2, word = "running" },
  EXPECTED = { rank = 2, word = "running" },
  SUCCESS = { rank = 3, word = "passed" },
  NONE = { rank = 4, word = "no checks" },
}

-- text is the state file's contents, or nil when there's none.
function ci.parse(text)
  local found = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local state, url, name, title = line:match("^([A-Z]+)\t([^\t]+)\t([^\t]+)\t?(.*)$")
    if state and url:match("^https://") then
      found[#found + 1] = { state = state, url = url, name = name, title = title }
    end
  end
  return found
end

local function described(state)
  return STATES[state] or { rank = 5, word = state:lower() }
end

-- The card's rows: failing first, then running, passed and those without checks.
function ci.rows(text)
  local found = ci.parse(text)
  for index, pull in ipairs(found) do pull.index = index end
  table.sort(found, function(a, b)
    local left, right = described(a.state).rank, described(b.state).rank
    if left ~= right then return left < right end
    return a.index < b.index
  end)
  local rows = {}
  for _, pull in ipairs(found) do
    local label = pull.title ~= "" and pull.title or pull.name
    rows[#rows + 1] = { id = pull.url, label = label, hint = pull.name .. " · " .. described(pull.state).word }
  end
  return rows
end

-- One notice per pull request in the passed file.
function ci.notices(text)
  local notices = {}
  for _, pull in ipairs(ci.parse(text)) do
    local body = pull.title ~= "" and pull.title or pull.name
    notices[#notices + 1] = { title = "Checks passed: " .. pull.name, text = body, url = pull.url }
  end
  return notices
end

return ci
