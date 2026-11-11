-- Pull requests waiting for your review (Option+Shift+G, or a click on the bar's count).

local shell = require("shell")
local card = require("card")
local prs = require("prs")
local apps = require("apps")

local feature = {}

local GH = "/opt/homebrew/bin/gh"

local function onPrsMessage(message)
  if message.type ~= "choose" then return shell.close() end
  -- Leave focus to the browser, which AeroSpace shows on workspace 3.
  shell.leaveFocus()
  shell.close()
  shell.open({ "-a", apps.read(shell.readText(apps.PATH)).browser, message.id })()
end

local function showPrs(output)
  local readable, found = pcall(hs.json.decode, output)
  local rows = prs.rows(readable and found or nil)
  if #rows == 0 then return shell.open({ "-a", apps.read(shell.readText(apps.PATH)).browser, prs.REVIEW_REQUESTED_URL })() end
  shell.show("prs", shell.centered(shell.LIST_WIDTH, shell.listHeight(#rows)),
    card.html({ prompt = "Pull requests…", rows = rows, compact = true }), onPrsMessage)
end

function feature.toggle()
  if shell.isOpen("prs") then return shell.close() end
  hs.task.new(GH, function(code, output)
    if code ~= 0 then return shell.alert("Could not reach GitHub", 1.2) end
    showPrs(output)
  end, { "search", "prs", "--review-requested=@me", "--state=open", "--json", prs.FIELDS }):start()
end

return feature
