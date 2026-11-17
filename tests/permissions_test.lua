-- The permissions checklist: one row per permission omv needs, with its state. Run through
-- permissions_test.sh with luajit.

local check = dofile(arg[1] .. "/tests/check.lua")
local permissions = require("permissions")
local menu = require("menu")

local function row(rows, key)
  for _, candidate in ipairs(rows) do
    if candidate.id == "permission:" .. key then return candidate end
  end
end

check.that("should mark a permission ✓ when it's granted",
  row(permissions.rows({ screen = true }), "screen").icon == "✓")

check.that("should mark a permission ✗ when it's denied",
  row(permissions.rows({ screen = false }), "screen").icon == "✗")

check.that("should mark a permission to check by hand when a script can't read it", (function()
  local microphone = row(permissions.rows({}), "microphone")
  return microphone.icon == "?" and check.contains(microphone.hint, "check")
end)())

check.that("should say what each permission is for", check.contains(row(permissions.rows({}), "screen").hint, "capture"))

check.that("should mention the Disk card when describing Full Disk Access", check.contains(row(permissions.rows({}), "disk").hint, "Disk card"))

check.that("should list every permission omv needs", (function()
  local rows = permissions.rows({})
  for _, key in ipairs({ "accessibility", "aerospace", "swipe", "screen", "location", "microphone", "calendars", "bluetooth", "disk" }) do
    if not row(rows, key) then return false end
  end
  return #rows == 9
end)())

check.that("should open the Privacy pane a row is for when it's chosen",
  permissions.paneUrl("permission:screen") == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

check.that("should give every row its pane", (function()
  for _, candidate in ipairs(permissions.rows({})) do
    if not permissions.paneUrl(candidate.id) then return false end
  end
  return true
end)())

check.that("should open no pane for an id that isn't a permission", permissions.paneUrl("lock") == nil)

check.that("should open the checklist when it has never been shown", permissions.shouldOpen(nil) == true)

check.that("should not open the checklist again once it has been shown", permissions.shouldOpen("shown\n") == false)

check.that("should list Permissions in the system menu", (function()
  for _, candidate in ipairs(menu.screen("system").rows) do
    if candidate.id == "permissions" then return true end
  end
  return false
end)())

check.finish()
