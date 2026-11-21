-- The checks on your own open pull requests (a click on the bar's item), and a notice when
-- a failing one passes. The bar's github_ci.sh asks GitHub; this only reads what it saved.

local shell = require("shell")
local card = require("card")
local ci = require("ci")
local apps = require("apps")

local feature = {}

local function openInBrowser(url)
  shell.open({ "-a", apps.read(shell.readText(apps.PATH)).browser, url })()
end

local function onCiMessage(message)
  if message.type ~= "choose" then return shell.close() end
  -- Leave focus to the browser, which AeroSpace shows on workspace 3.
  shell.leaveFocus()
  shell.close()
  openInBrowser(message.id)
end

function feature.toggle()
  if shell.isOpen("ci") then return shell.close() end
  local rows = ci.rows(shell.readText(ci.STATE))
  if #rows == 0 then return shell.alert("No open pull requests", 1.2) end
  shell.show("ci", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows)),
    card.html({ prompt = "Checks…", rows = rows, compact = true }), onCiMessage)
end

-- The bar calls this after it wrote the passed file; each notice opens its pull request.
function feature.passed()
  local notices = ci.notices(shell.readText(ci.PASSED))
  os.remove(ci.PASSED)
  for _, notice in ipairs(notices) do
    hs.notify.new(function() openInBrowser(notice.url) end,
      { title = notice.title, informativeText = notice.text, withdrawAfter = 0 }):send()
  end
end

return feature
