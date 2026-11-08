-- Turns gh's list of pull requests waiting for your review into rows for the card.
-- Has no Hammerspoon dependency, so the Lua tests can run it with luajit.

local prs = {}

prs.FIELDS = "number,title,url,repository"

-- Opened instead of the card when nothing waits, so the key always lands on GitHub.
prs.REVIEW_REQUESTED_URL = "https://github.com/pulls/review-requested"

-- found is gh's JSON already decoded, or nil when it could not be read.
function prs.rows(found)
  local rows = {}
  for _, pull in ipairs(found or {}) do
    if pull.url then
      local repository = pull.repository and pull.repository.nameWithOwner or "?"
      rows[#rows + 1] = { id = pull.url, label = pull.title or "", hint = repository .. "#" .. tostring(pull.number) }
    end
  end
  return rows
end

return prs
